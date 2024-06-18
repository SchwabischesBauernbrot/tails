from gettext import gettext
import gi

from tailsgreeter.translatable_window import TranslatableWindow

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

_ = gettext


class RepairFilesystemDialog(Gtk.MessageDialog, TranslatableWindow):
    def __init__(self):
        Gtk.MessageDialog.__init__(self, title=_("Repairing the File System"))
        TranslatableWindow.__init__(self, self)
        self.get_message_area().get_parent().destroy()
        self.content_area = self.get_content_area()
        box = Gtk.Box(spacing=6, margin=12)
        self.spinner = Gtk.Spinner()
        self.spinner.start()
        box.pack_start(self.spinner, False, False, 0)
        self.label = Gtk.Label(_("This may take a long time..."))
        box.pack_start(self.label, False, False, 0)
        box.show_all()
        self.content_area.pack_start(box, False, False, 0)
        self.close_button = self.add_button(_("Close"), Gtk.ResponseType.OK)
        self.close_button.set_visible(False)
        self.store_translations(self)
