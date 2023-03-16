"""Tails Additional Software configuration file management."""

import gettext
import grp
import logging
import os
import os.path
from pathlib import Path
import pwd
import re
import subprocess
from typing import Optional

import atomicwrites
import systemd.journal

from tailslib import PERSISTENT_STORAGE_USERNAME
from tailslib.persistence import get_persistence_path, PERSISTENCE_DIR
from tailslib.utils import run_with_user_env

gettext.install("tails")
_ = gettext.gettext

PACKAGES_STATE_DIR = "/run/live-additional-software/packages"
INSTALLED_PACKAGES_FILE = "/run/live-additional-software/packages/installed"
REMOVED_PACKAGES_FILE = "/run/live-additional-software/packages/removed"
ASP_STATE_INSTALLER_ASKED = "/run/live-additional-software/installer-asked"
ASP_LOG_FILE = "/run/live-additional-software/log"
OLD_APT_LISTS_DIR = os.path.join(PERSISTENCE_DIR, 'apt', 'lists.old')
APT_ARCHIVES_DIR = "/var/cache/apt/archives"
APT_LISTS_DIR = "/var/lib/apt/lists"
PACKAGES_LIST_FILE = "live-additional-software.conf"


class ASPError(Exception):
    """Base class for exceptions raised by """


class ASPDataError(ASPError):
    """Raised when the data read does not have the expected format."""
    pass


def set_up_logging(log_to_journal=False):
    debug = os.getenv("DEBUG") or \
            "debug" in Path("/proc/cmdline").read_text().split()
    log_level = logging.DEBUG if debug else logging.INFO
    log_format = "%(levelname)s:%(filename)s:%(lineno)d: %(message)s"
    stderr_handler = logging.StreamHandler()
    file_handler = logging.FileHandler(ASP_LOG_FILE)
    handlers = [stderr_handler, file_handler]
    if log_to_journal:
        handlers.append(systemd.journal.JournalHandler())
    logging.basicConfig(level=log_level, format=log_format, handlers=handlers)


def _write_config(packages):
    config_file_owner_uid = pwd.getpwnam(PERSISTENT_STORAGE_USERNAME).pw_uid
    config_file_owner_gid = grp.getgrnam(PERSISTENT_STORAGE_USERNAME).gr_gid

    packages_list_path = get_packages_list_path()
    try:
        os.setegid(config_file_owner_gid)
        os.seteuid(config_file_owner_uid)
        with atomicwrites.atomic_write(packages_list_path,
                                       overwrite=True) as f:
            for package in sorted(packages):
                f.write(package + '\n')
        os.chmod(packages_list_path, 0o0644)
    finally:
        os.seteuid(0)
        os.setegid(0)


def filter_package_details(pkg):
    """Filter target release, version and architecture from pkg."""
    return re.split("[/:=]", pkg)[0]


def get_packages_list_path(return_nonexistent=False):
    """Return the package list file path in current or new persistence.

    The return_nonexistent arguments is passed to get_persistence_path.
    """
    persistence_dir = get_persistence_path(return_nonexistent)
    return os.path.join(persistence_dir, PACKAGES_LIST_FILE)


def get_additional_packages():
    """Return the list of all additional packages configured."""
    packages = set()
    try:
        with open(get_packages_list_path()) as f:
            for line in f:
                line = line.strip()
                if line:
                    packages.add(line)
    except FileNotFoundError:
        # Just return an empty set.
        pass
    return packages


def remove_additional_packages(old_packages):
    """Remove packages from additional packages configuration.

    Removes the packages from additional packages configuration.

    The old_packages argument should be a list of packages names.
    """
    logging.info("Removing from additional packages list: %s" % old_packages)
    packages = get_additional_packages()
    # The list of packages was initially provided by apt after removing them,
    # so we don't check the names.
    packages -= old_packages

    _write_config(packages)


def _notify(title, body="", accept_label="", deny_label="",
            documentation_target="", urgent=False, return_id=False,
            ):
    """Display a notification to the user of the live system.

    The notification will show title and body.

    If accept_label or deny_label are set, they will be shown on action buttons
    and the method will wait for user input and return 1 if the button with
    accept_label was clicked or 0 if the button with deny_label was
    clicked.

    If documentation_target is set, a "Documentation" action button will open
    corresponding tails documentation when clicked.

    If return_id is true, returns the notification ID, which may be used to
    close the notification.

    Else, return None.
    """

    cmd = "/usr/local/lib/tails-additional-software-notify"
    if urgent:
        urgent = "urgent"
    else:
        urgent = ""

    try:
        completed_process = subprocess.run(
            [
                "/usr/local/lib/run-with-user-env",
                cmd, title, body, accept_label, deny_label,
                documentation_target, urgent
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if completed_process.stderr:
            logging.warning("%s", completed_process.stderr)
        if completed_process.returncode == 1:
            # sudo failed to execute the command
            raise OSError(completed_process.stderr)
    except OSError as e:
        logging.warning("Warning: unable to notify the user. %s" % e)
        logging.warning("The notification was: %s %s" % (title, body))
        return None

    if return_id:
        for line in completed_process.stdout.splitlines():
            if line.startswith("id="):
                return line[3:]
    else:
        if completed_process.returncode == 0:
            return 1
        elif completed_process.returncode == 3:
            return 0
        else:
            return None


def _notify_failure(summary, details=None):
    """Display a failure notification to the user of the live system.

    The user has the option to edit the configuration or to view the system
    log.
    """
    if details:
        # Translators: Don't translate {details}, it's a placeholder and will
        # be replaced.
        details = _("{details} Please check your list of additional "
                    "software or read the system log to "
                    "understand the problem.").format(details=details)

    else:
        details = _("Please check your list of additional "
                    "software or read the system log to "
                    "understand the problem.")

    action_clicked = _notify(summary, details, _("Show Log"), _("Configure"),
                             urgent=True)
    if action_clicked == 1:
        show_system_log()
    elif action_clicked == 0:
        show_configuration_window()


def show_system_log():
    """Show additional packages configuration window."""
    run_with_user_env("gtk-launch", "org.gnome.gedit.desktop", ASP_LOG_FILE)


def show_configuration_window():
    """Show additional packages configuration window."""
    run_with_user_env("gtk-launch", "org.boum.tails.additional-software-config.desktop")
