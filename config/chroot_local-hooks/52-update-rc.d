#!/bin/sh

set -e
set -u

### Tweak systemd unit files

# Workaround for https://bugs.debian.org/934389
systemctl enable memlockd.service

# Enable our own systemd unit files
systemctl enable initramfs-shutdown.service
systemctl enable onion-grater.service
systemctl enable tails-allow-external-TailsData-access.service
systemctl enable tails-autotest-broken-gnome-shell.service
systemctl enable tails-autotest-remote-shell.service
systemctl enable tails-create-netns.service
systemctl enable tails-persistent-storage.service
systemctl enable tails-remove-overlayfs-dirs.service
systemctl enable tails-set-wireless-devices-state.service
systemctl enable tails-shutdown-on-media-removal.service
systemctl enable tails-tor-has-bootstrapped.target
systemctl enable tails-wait-until-tor-has-bootstrapped.service
systemctl enable tails-tor-has-bootstrapped-flag-file.service
systemctl enable tca-portal.socket
systemctl enable run-initramfs.mount
systemctl enable var-tmp.mount

# Enable our own systemd user unit files
systemctl --global enable tails-add-GNOME-bookmarks.service
systemctl --global enable tails-additional-software-install.service
systemctl --global enable tails-configure-keyboard.service
systemctl --global enable tails-security-check.service
systemctl --global enable tails-upgrade-frontend.service
systemctl --global enable tails-virt-notify-user.service
systemctl --global enable tails-wait-until-tor-has-bootstrapped.service
systemctl --global enable tails-create-persistent-storage.service

# This causes the proxies to run during the whole session, instead of
# being started and stopped when needed. The only app which needs
# the proxies and doesn't define this requirement in a systemd service
# yet is the Unsafe Browser. Once that is fixed, we can remove these
# lines (and the [Install] sections from the service files).
systemctl --global enable "tails-a11y-bus-proxy.service"
systemctl --global enable "tails-ibus-proxy.service"

# Use socket activation only, to delay the startup of cupsd.
systemctl disable cups.service
systemctl enable  cups.socket

# We're starting NetworkManager and Tor ourselves.
systemctl disable NetworkManager.service
systemctl disable NetworkManager-wait-online.service

# systemd-networkd fallbacks to Google's nameservers when no other nameserver
# is provided by the network configuration. As of Debian Buster,
# this service is disabled
# by default, but it feels safer to make this explicit. Besides, it might be
# that systemd-networkd vs. firewall setup ordering is suboptimal in this respect,
# so let's avoid any risk of DNS leaks here.
systemctl mask systemd-networkd.service

# Do not sync the system clock to the hardware clock on shutdown
systemctl mask hwclock-save.service

# Do not run timesyncd: we have our own time synchronization mechanism
systemctl mask systemd-timesyncd.service

# Do not let pppd-dns manage /etc/resolv.conf
systemctl mask pppd-dns.service

# Conflicts with our custom shutdown procedure
systemctl mask live-tools.service

# "Daily man-db regeneration" is not needed in Tails (#16631)
systemctl mask man-db.timer

# Blocked by our firewall so cannot work; would need some security analysis
# before we enable it
systemctl mask avahi-daemon.socket
systemctl mask avahi-daemon.service
