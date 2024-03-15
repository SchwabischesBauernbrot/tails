#!/bin/sh

set -eu
set -x

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
INCLUDES_DIR="${SCRIPT_DIR}/rw-includes"

# Change only the owner of the includes dir, not the group, and allow
# the group the same access as the owner, to allow the logged-in user
# to modify the files.
sudo chown -R libvirt-qemu "${INCLUDES_DIR}"
sudo chmod -R g=u "${INCLUDES_DIR}"
