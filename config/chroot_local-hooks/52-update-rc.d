#!/bin/sh

set -e
set -u

### Tweak systemd unit files

# Workaround for https://bugs.debian.org/934389
systemctl enable memlockd.service

# Enable our own systemd unit files
systemctl enable initramfs-shutdown.service
systemctl enable onion-grater.service
systemctl enable tails-synchronize-data-to-new-persistent-volume-on-shutdown.service
systemctl enable tails-autotest-broken-Xorg.service
systemctl enable tails-autotest-remote-shell.service
systemctl enable tails-remove-overlayfs-dirs.service
systemctl enable tails-set-wireless-devices-state.service
systemctl enable tails-shutdown-on-media-removal.service
systemctl enable tails-tor-has-bootstrapped.target
systemctl enable tails-wait-until-tor-has-bootstrapped.service
systemctl enable tails-tor-has-bootstrapped-flag-file.service
systemctl enable run-initramfs.mount
systemctl enable var-tmp.mount

# Enable our own systemd user unit files
systemctl --global enable tails-add-GNOME-bookmarks.service
systemctl --global enable tails-additional-software-install.service
systemctl --global enable tails-configure-keyboard.service
systemctl --global enable tails-create-tor-browser-directories.service
systemctl --global enable tails-kill-gdm-session.service
systemctl --global enable tails-security-check.service
systemctl --global enable tails-upgrade-frontend.service
systemctl --global enable tails-virt-notify-user.service
systemctl --global enable tails-wait-until-tor-has-bootstrapped.service

# Use socket activation only, to delay the startup of cupsd.
# In practice, this means that cupsd is started during
# the initialization of the GNOME session, which is fine: by then,
# the persistent /etc/cups has been mounted.
systemctl disable cups.service
systemctl enable  cups.socket

# We're starting NetworkManager and Tor ourselves.
# We disable tor.service (as opposed to tor@default.service) because
# it's an important goal to never start Tor before the user has had
# a chance to choose to do so in an obfuscated way: if some other
# package enables tor@whatever.service someday, disabling tor.service
# will disable it as well, while disabling tor@default.service would not.
systemctl disable tor.service
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
