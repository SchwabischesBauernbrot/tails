#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
import zbargtk


def got_text(zbar, text):
    print("Scanned text:", text)
    # E.g., to disable the video once scanned
    # (not very good UX, only for example purpose)
    zbar.props.video_enabled = False


win = Gtk.Window()
win.connect("destroy", Gtk.main_quit)

# Create a widget; zbar is a __gi__.ZBarGtk.
# Somehow gi creates the type automatically, or something happens when
# libzbargtk0 is loaded.
zbar = zbargtk.create_widget()
zbar.connect("decoded_text", got_text)
# You can request a certain video size.
# This is not a property of the zbar widget, but I would like it to be, in
# the PR I will do to the upstream project
# zbargtk.request_video_size(zbar, 640 // 2, 480 * 2)
# The rest is managed through properties, so you can do this to set a device:
zbar.props.video_device = '/dev/video1'
# At the beginning, zbar doesn't have a device, you need to set one.
# The call is async, so it returns immediately, but takes a little bit
# to effectively lkoad it
win.add(zbar)

win.show_all()
Gtk.main()
