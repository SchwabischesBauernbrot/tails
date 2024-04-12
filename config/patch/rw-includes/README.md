# Read-write includes directory

This directory is used to share files between the host and the Tails VM.

When you add `early_patch` (or `patch`) to the boot options of the Tails
VM, any files in this directory will be bind mounted (or copied, if you
use `early_patch=umount`) to the root filesystem of the Tails VM in the
initramfs phase of the boot process.

If the files are bind mounted, they will be read-write in the Tails VM,
so any changes made in the Tails VM will be reflected on the host,
allowing you to persist changes across reboots.

The files and directories in this directory must be writable by the
libvirt-qemu user on the host. You can use the
`config/patch/set-rw-includes-permissions.sh` script to set the correct
permissions.

## Examples

Make the bash history persistent:

```bash
mkdir -p rw-includes/root
touch rw-includes/root/.bash_history
./set-rw-includes-permissions.sh
```

Have a `.bashrc` for the root user:

```bash
mkdir -p rw-includes/root
cp /etc/skel/.bashrc rw-includes/root/
./set-rw-includes-permissions.sh
```
