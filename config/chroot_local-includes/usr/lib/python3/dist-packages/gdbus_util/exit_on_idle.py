import logging
import signal
import threading
from enum import Enum

from gi.repository import GLib
from gi.repository import Gio

try:
    import cysystemd.daemon as systemd_daemon
except ImportError:
    import systemd.daemon as systemd_daemon

logger = logging.getLogger(__package__)

maincontext = GLib.MainContext().default()


class _State(Enum):
    RUNNING = 0
    FLUSHING = 1
    STOPPING = 2


class ExitOnIdleService:
    """
    A base class which implements race-free exit-on-idle for a D-Bus
    service. It is useful for services that are meant to be started on
    demand and exit automatically when they are no longer needed.

    A timer is started with `timeout` seconds when the :meth:`run`
    method is called. When the timer expires, the service will check if
    it is idle. If it is, the service will shut down gracefully. If it's
    not, the timer is reset.

    The idle check is implemented by the :meth:`check_idle` method. By
    default this method always returns True. Subclasses should override
    this method to implement the idle check. The :class:`DBusObject`
    class has a :meth:`check_idle` method which checks if there are any
    ongoing method calls. If the :class:`ExitOnIdleService` instance is
    also a :class:`DBusObject`, it will use that method as the idle
    check by default [1]_.

    The timer can be reset by calling the :meth:`reset_idle_timer`
    method. If the :class:`ExitOnIdleService` instance is also a
    :class:`DBusObject`, it will automatically reset the idle timeout
    whenever a method call is received (or a property is read or
    written).

    To avoid that requests are lost when the service shuts down, the
    service will first unregister the bus name and then handle any
    pending requests before exiting.

    If the service is run as a systemd service, systemd will be
    notified that the service is stopping, so that it will queue any
    start requests instead of assuming that the service is still
    running.

    See `sleeper-service.py`_ for a simple example or
    `accounts-service.py`_ for a more complex example of how to to
    implement an exit-on-idle service.

    .. _sleeper-service.py: https://github.com/adombeck/python-gdbus-util/blob/main/examples/exit-on-idle/sleeper-service.py
    .. _accounts-service.py: https://github.com/adombeck/python-gdbus-util/blob/main/examples/more-complex/accounts-service.py

    .. [1] Note that this only works as expected if no other D-Bus
           objects are registered on the same connection. If there are
           other D-Bus objects, the :meth:`check_idle` method should be
           overridden to check if all objects are idle. The
           `accounts-service.py`_ example demonstrates how to do this.

    :param connection: The D-Bus connection on which to register the
        name.
    :type connection: :class:`Gio.DBusConnection`
    :param name: The name to register on the bus.
    :type name: str
    :param timeout: The idle timeout in seconds.
    :type timeout: int
    """

    def __init__(self, connection: Gio.DBusConnection, name: str, timeout: int) -> None:
        self.connection = connection
        self.name = name
        self.timeout = timeout
        self._state: _State = _State.RUNNING
        self._idle_timeout_source: GLib.Source | None = None
        self._idle_timer_lock = threading.Lock()
        self._acquired_name = False

    def check_idle(self) -> bool:
        """
        Check if the service is idle. This method should be overridden
        by the subclass. By default, it always returns True.
        """

        return True

    def _on_name_acquired(self, connection: Gio.DBusConnection, name: str) -> None:
        logger.info(f"Acquired name {name} on the system bus")
        self._acquired_name = True

    def _on_name_lost(self, connection: Gio.DBusConnection, name: str) -> None:
        if not self._acquired_name:
            logger.error(f"Failed to acquire name {name} on the system bus")
        else:
            logger.info(f"Lost name {name} on the system bus, stopping...")
        self.graceful_shutdown()

    def graceful_shutdown(self) -> None:
        """Stop the service gracefully."""
        self._state = _State.FLUSHING
        maincontext.wakeup()

    def reset_idle_timer(self) -> None:
        """Reset the idle timer. This method should be called whenever the
        service is active."""
        # Take a lock to ensure that any timeout source that was created
        # is destroyed before we create a new one.
        with self._idle_timer_lock:
            if self._state != _State.RUNNING:
                return

            if self._idle_timeout_source:
                self._idle_timeout_source.destroy()

            self._idle_timeout_source = GLib.timeout_source_new_seconds(self.timeout)
            self._idle_timeout_source.set_callback(self._on_idle_timer_expiration)
            self._idle_timeout_source.attach(maincontext)

    def _on_idle_timer_expiration(self, user_data=None) -> None:
        if self._state != _State.RUNNING:
            logger.debug(f"Ignoring idle timer expiration, state is {self._state}")
            return

        if not self.check_idle():
            logger.debug("Idle timer expired, but not idle, resetting...")
            self.reset_idle_timer()
            return

        logger.info("Idle timer expired, shutting down gracefully...")
        self.graceful_shutdown()

    def _on_bus_name_released(
        self, bus: Gio.DBusConnection, res: Gio.AsyncResult = None
    ) -> None:
        logger.debug("Bus name released")
        self._state = _State.STOPPING
        maincontext.wakeup()

    def _on_terminating_signal(self, sig, frame):
        logger.info("Received SIGTERM, shutting down gracefully...")
        self.graceful_shutdown()

    def run(self, handle_signals: bool = True) -> None:
        """
        Run the service. The service registers the name on the provided
        D-Bus connection and enters the GLib main loop.

        This method blocks until one of the following conditions is met:

        * The service is idle for `timeout` seconds.
        * The :meth:`graceful_shutdown` method is called.
        * The D-Bus name is lost or the connection is closed.
        * A SIGTERM, SIGINT or SIGHUP signal is received, if
          `handle_signals` is `True`.

        In all of these cases, the service will shut down gracefully.
        This means that the service will notify systemd that it is
        stopping (if running as a systemd service), release the D-Bus
        name and process any queued requests before this method returns.

        :param handle_signals: If `True`, the service will handle the
            SIGTERM, SIGINT and SIGHUP signals and shut down gracefully
            when one of these signals is received.
        :type handle_signals: bool
        """
        bus_id = Gio.bus_own_name_on_connection(
            self.connection,
            self.name,
            Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
            self._on_name_acquired,
            self._on_name_lost,
        )

        if handle_signals:
            # Handle SIGTERM, SIGINT and SIGHUP signals
            signal.signal(signal.SIGTERM, self._on_terminating_signal)
            signal.signal(signal.SIGINT, self._on_terminating_signal)
            signal.signal(signal.SIGHUP, self._on_terminating_signal)

        logger.debug("Entering main loop")

        logger.debug("Setting idle timer to %d seconds", self.timeout)
        self.reset_idle_timer()

        # Run the main loop until we are asked to exit
        while self._state == _State.RUNNING:
            maincontext.iteration()

        # Inform the service manager that we are going down, so that it
        # will queue all further start requests, instead of assuming we
        # are still running.
        # See https://github.com/systemd/systemd/blob/4931b8e471438abbc44d/src/shared/bus-util.c#L131
        logger.debug("Notifying systemd that we are stopping")
        systemd_daemon.notify("STOPPING=1")

        # Unregister the name and wait for the NameOwnerChanged signal.
        # We do this in order to make sure that any queued requests are
        # still processed before we really exit.
        # See https://github.com/systemd/systemd/blob/4931b8e471438abbc44d/src/shared/bus-util.c#L67
        match = (
            f"sender='org.freedesktop.DBus',"
            f"type='signal',"
            f"interface='org.freedesktop.DBus',"
            f"member='NameOwnerChanged'"
            f"path='/org/freedesktop/DBus'"
            f"arg0='{self.name}'"
            f"arg1='{self.connection.get_unique_name()}'"
            f"arg2=''"
        )
        self.connection.call(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "AddMatch",
            GLib.Variant("(s)", (match,)),
            GLib.VariantType.new("u"),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
            self._on_bus_name_released,
        )

        # systemd will send us a SIGTERM once we release the bus name
        # (if we're running as a type=dbus systemd service), so we
        # ignore SIGTERM for the remainder of the shutdown process.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        logger.debug("Releasing bus name")
        Gio.bus_unown_name(bus_id)

        # Keep iterating the main context to ensure that any queued
        # requests are still processed before we really stop.
        logger.debug("Processing queued requests...")
        while self._state == _State.FLUSHING:
            maincontext.iteration()

        logger.info("Stopping")
