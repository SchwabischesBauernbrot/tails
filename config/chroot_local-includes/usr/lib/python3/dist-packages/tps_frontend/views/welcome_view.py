from logging import getLogger
from gi.repository import GLib, Gtk
import subprocess

from tps import TPSErrorType
from tps_frontend import _, WELCOME_VIEW_UI_FILE
from tps_frontend.view import View

logger = getLogger(__name__)


class WelcomeView(View):
    _ui_file = WELCOME_VIEW_UI_FILE

    def __init__(self, window) -> None:
        super().__init__(window)
        self.continue_button = self.builder.get_object("continue_button")  # type: Gtk.Button
        self.device_not_supported_label = self.builder.get_object(
            "device_not_supported_label"
        )  # type: Gtk.Box
        self.warning_icon = self.builder.get_object("warning_icon")  # type: Gtk.Image

    def show(self) -> None:
        super().show()

        error: GLib.Variant = self.window.service_proxy.get_cached_property("Error")
        device_is_supported = not error

        if error:
            self.handle_error(error.get_uint32())

        self.device_not_supported_label.set_visible(not device_is_supported)
        self.warning_icon.set_visible(not device_is_supported)
        self.continue_button.set_visible(device_is_supported)

        if device_is_supported:
            self.continue_button.grab_focus()

    def handle_error(self, error: int) -> None:
        error_type = TPSErrorType(error)
        logger.warning("Error: %s", error_type)
        if error_type == TPSErrorType.TOO_MANY_PARTITIONS:
            self.device_not_supported_label.set_label(
                _(
                    "Sorry, it is impossible to create a Persistent Storage "
                    "because there is already a second partition "
                    "on the USB stick.\n\n"
                    "To be able to use Tails with a Persistent Storage, "
                    "please try to follow our instructions on "
                    '<a href="install">installing Tails on a USB stick</a> '
                    "again.",
                ),
            )
        elif error_type == TPSErrorType.FIRST_BOOT_REPARTITIONING_FAILED:
            self.device_not_supported_label.set_label(
                _(
                    "Sorry, it is impossible to create a Persistent Storage "
                    "because resizing the Tails system partition failed when "
                    "your Tails USB stick was started for the first time.\n\n"
                    "To be able to use Tails with a Persistent Storage, "
                    "please try to follow our instructions on "
                    '<a href="install">installing Tails on a USB stick</a> '
                    "again.",
                ),
            )
        elif error_type == TPSErrorType.INVALID_BOOT_DEVICE:
            logger.warning(
                "You can only create a Persistent Storage on a USB stick "
                "installed with a USB image or Tails Cloner.",
            )
        else:
            self.device_not_supported_label.set_label(
                _("An unexpected error occurred."),
            )
            self.window.display_error(
                _("An unexpected error occurred"),
                _("Error code: %s", error_type),
                with_send_report_button=True,
            )

    def on_cancel_button_clicked(self, button: Gtk.Button):
        self.window.destroy()

    def on_activate_link(self, label: Gtk.Label, uri: str):
        logger.debug("Opening documentation: %s", uri)
        subprocess.run(
            ["/usr/local/bin/tails-documentation", uri],  # noqa: S603
            check=False,
        )
        return True

    def on_continue_button_clicked(self, button: Gtk.Button):
        self.window.passphrase_view.show()
