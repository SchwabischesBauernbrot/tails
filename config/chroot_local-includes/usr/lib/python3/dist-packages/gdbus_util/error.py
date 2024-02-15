from abc import abstractmethod

from gi.repository import Gio, GLib


class DBusError(Exception):
    """
    An abstract base class for errors that can be returned to D-Bus
    clients.

    Subclasses must define a valid D-Bus error name with the :attr:`name`
    attribute. See the `D-Bus specification`__ for the naming rules.

    .. __: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-names-error

    """

    @property
    @abstractmethod
    def name(self) -> str:
        """A valid D-Bus error name, for example
        ``"org.example.Error.FooBar"``."""

    @classmethod
    def is_instance(cls, err) -> bool:
        """Check if the given error is an instance of this class.

        This method is meant for clients which handle a :class:`DBusError`.
        """
        if not Gio.DBusError.is_remote_error(err):
            return False

        return Gio.DBusError.get_remote_error(err) == cls.name

    @classmethod
    def strip_remote_error(cls, err: GLib.Error):
        """Remove the D-Bus error prefix from the message.

        This method is meant for clients which handle a :class:`DBusError`.

        It serves the same purpose as :meth:`Gio.DBusError.strip_remote_error`,
        but that method is broken in PyGObject, see
        https://gitlab.gnome.org/GNOME/pygobject/-/issues/342."""

        prefix = f"GDBus.Error:{cls.name}: "
        if err.message.startswith(prefix):
            err.message = err.message[len(prefix) :]
            return

        prefix = "GDBus.Error:"
        if err.message.startswith(prefix):
            err.message = err.message[len(prefix) :]
