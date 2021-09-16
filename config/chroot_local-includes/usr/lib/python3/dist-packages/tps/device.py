import logging
import os
from pathlib import Path
import re
import stat
from typing import Optional

from gi.repository import GLib, UDisks

from tailslib import LIVE_USER_UID, LIVE_USERNAME
from tps import executil
from tps import TPS_MOUNT_POINT, udisks
from tps.dbus.errors import IncorrectPassphraseError
from tps.job import Job

logger = logging.getLogger(__name__)

TAILS_MOUNTPOINT = "/lib/live/mount/medium"
PARTITION_GUID = "8DA63339-0007-60C0-C436-083AC8230908" # Linux reserved
PARTITION_LABEL = "TailsData"


class PartitionNotFoundError(Exception):
    pass

class InvalidPartitionError(Exception):
    pass

class PartitionNotUnlockedError(Exception):
    pass

class InvalidBootDeviceError(Exception):
    pass

class InvalidCleartextDeviceError(Exception):
    pass

class InvalidStatError(Exception):
    pass


class BootDevice(object):
    def __init__(self, udisks_object: UDisks.Object):
        self.udisks_object = udisks_object
        self.partition_table = \
            udisks_object.get_partition_table() # type: UDisks.PartitionTable
        self.block = self.udisks_object.get_block()
        if not self.block:
            raise InvalidBootDeviceError("Device is not a block device")
        self.device_path = self.block.props.device

    @classmethod
    def get_tails_boot_device(cls) -> "BootDevice":
        """Get the device which Tails was booted from"""
        # Get the underlying block device of the Tails system partition
        try:
            dev_num = os.stat(TAILS_MOUNTPOINT).st_dev
        except FileNotFoundError as e:
            raise InvalidBootDeviceError(e)

        block = udisks.get_block_for_dev(dev_num)
        if not block or not block.get_object():
            msg = f"Could not get udisks object of boot device " \
                  f"{os.major(dev_num)}:{os.minor(dev_num)}"
            raise InvalidBootDeviceError(msg)
        device_object = block.get_object()

        # Get the udisks partition object
        partition = device_object.get_partition()
        if not partition:
            msg = f"Boot device {block.props.device} is not a partition"
            raise InvalidBootDeviceError(msg)

        return BootDevice(udisks.get_object(partition.props.table))

    def get_beginning_of_free_space(self) -> int:
        """Get the beginning of the free space on the device, in bytes"""
        # Get the partitions
        partitions = [udisks.get_object(p).get_partition()
                      for p in self.partition_table.props.partitions]
        # Get the ends of the partitions, in bytes
        partition_ends = [p.props.offset + p.props.size for p in partitions]
        # Return the end of the last partition, which is the beginning
        # of the free space.
        return max(partition_ends)


class Partition(object):
    """The Persistent Storage encrypted partition"""

    def __init__(self, udisks_object: UDisks.Object):
        self.udisks_object = udisks_object
        self.block = self.udisks_object.get_block()
        if not self.block:
            raise InvalidPartitionError("Device is not a block device")
        self.device_path = self.block.props.device
        self.partition = self.udisks_object.get_partition()  # type: UDisks.Partition
        if not self.partition:
            raise InvalidPartitionError(f"Device {self.device_path} is not a "
                                        f"partition")

    def get_cleartext_device(self) -> "CleartextDevice":
        """Get the cleartext device of Persistent Storage encrypted
        partition"""
        encrypted = self._get_encrypted()
        cleartext_device_path = encrypted.props.cleartext_device
        if cleartext_device_path == "/":
            raise PartitionNotUnlockedError(f"Device {self.device_path} is "
                                            f"not unlocked")
        return CleartextDevice(udisks.get_object(cleartext_device_path))

    def _get_encrypted(self) -> UDisks.Encrypted:
        """Get the UDisks.Encrypted interface of the partition"""
        encrypted = self.udisks_object.get_encrypted()
        if not encrypted:
            raise InvalidPartitionError(f"Device {self.device_path} is not "
                                        f"encrypted")
        return encrypted

    def is_unlocked(self) -> bool:
        try:
            self.get_cleartext_device()
            return True
        except (InvalidPartitionError, PartitionNotUnlockedError):
            return False

    @classmethod
    def exists(cls) -> bool:
        """Return true if the Persistent Storage partition exists and
        false otherwise."""
        return bool(cls.find())

    @classmethod
    def find(cls) -> Optional["Partition"]:
        """Return the Persistent Storage encrypted partition or raise
        a PartitionNotFoundError."""
        parent_device = BootDevice.get_tails_boot_device()
        partitions = parent_device.partition_table.props.partitions
        for partition_name in sorted(partitions):
            partition = udisks.get_object(partition_name)
            if not partition:
                continue
            if partition.get_partition().props.name == PARTITION_LABEL:
                return Partition(partition)
        return None

    @classmethod
    def create(cls, job: Job, passphrase: str) -> "Partition":
        """Create the Persistent Storage encrypted partition"""
        parent_device = BootDevice.get_tails_boot_device()
        offset = parent_device.get_beginning_of_free_space()

        # Create and format the partition
        partition_table = parent_device.partition_table
        path = partition_table.call_create_partition_and_format_sync(
            arg_offset=offset,
            # Size 0 means maximal size
            arg_size=0,
            arg_type=PARTITION_GUID,
            arg_name=PARTITION_LABEL,
            arg_options=GLib.Variant('a{sv}', {}),
            arg_format_type="ext4",
            arg_format_options=GLib.Variant('a{sv}', {
                "label": GLib.Variant('s', PARTITION_LABEL),
                "encrypt.passphrase": GLib.Variant('s', passphrase),
            }),
        )

        # Wait for all UDisks and udev events to finish
        udisks.settle()
        executil.check_call(["udevadm", "settle"])

        # Create the Partition object
        partition = Partition(udisks.get_object(path))

        # Get the cleartext device
        cleartext_device = partition.get_cleartext_device()

        # Rename the cleartext device to "TailsData_unlocked", so that
        # is has the same name as after a reboot.
        cleartext_device.rename_dm_device("TailsData_unlocked")

        # Mount the cleartext device
        cleartext_device.mount()

        return partition

    def delete(self):
        """Delete the Persistent Storage encrypted partition"""
        # Ensure that the partition is unmounted
        self._ensure_unmounted()
        # Delete the partition. By setting tear-down to true, udisks
        # automatically locks the encrypted device if it is currently
        # unlocked.
        self.partition.call_delete_sync(arg_options=GLib.Variant('a{sv}', {
            "tear-down": GLib.Variant('b', True),
        }))

    def unlock(self, passphrase: str):
        """Unlock the Persistent Storage encrypted partition"""
        encrypted = self._get_encrypted()

        try:
            encrypted.call_unlock_sync(
                arg_passphrase=passphrase,
                arg_options=GLib.Variant('a{sv}', {}),
                cancellable=None,
            )
        except GLib.Error as err:
            if err.matches(UDisks.error_quark(), UDisks.Error.FAILED) and \
                    re.search('Failed to activate device: (Operation not '
                              'permitted|Incorrect passphrase)', err.message):
                raise IncorrectPassphraseError(err) from err
            raise

        # Wait for all UDisks and udev events to finish
        udisks.settle()
        executil.check_call(["udevadm", "settle"])

        # Get the cleartext device
        cleartext_device = self.get_cleartext_device()

        # Rename the cleartext device to "TailsData_unlocked", so that
        # is has the same name as after a reboot.
        cleartext_device.rename_dm_device("TailsData_unlocked")

    def _ensure_unmounted(self):
        try:
            cleartext_device = self.get_cleartext_device()
        except (InvalidPartitionError, PartitionNotUnlockedError):
            # There is no cleartext device for this partition, so there
            # is nothing to unmount
            return

        try:
            cleartext_device.force_unmount()
        except GLib.Error as err:
            # Ignore errors caused by the device not being mounted.
            if not err.matches(UDisks.error_quark(), UDisks.Error.NOT_MOUNTED):
                raise

    def change_passphrase(self, passphrase: str, new_passphrase: str):
        """Change the passphrase of the Persistent Storage encrypted
        partition"""
        encrypted = self._get_encrypted()
        try:
            encrypted.call_change_passphrase_sync(
                arg_passphrase=passphrase,
                arg_new_passphrase=new_passphrase,
                arg_options=GLib.Variant('a{sv}', {}),
            )
        except GLib.Error as err:
            if err.matches(UDisks.error_quark(), UDisks.Error.FAILED) and \
                    "No keyslot with given passphrase found" in err.message:
                raise IncorrectPassphraseError(err) from err
            raise


class CleartextDevice(object):
    def __init__(self, udisks_object: UDisks.Object):
        self.udisks_object = udisks_object
        self.block = self.udisks_object.get_block()
        if not self.block:
            raise InvalidCleartextDeviceError("Device is not a block device")
        self.device_path = self.block.props.device
        self.mount_point = Path(TPS_MOUNT_POINT)

    def is_mounted(self):
        p = executil.run(["findmnt", f"--source={self.device_path}",
                          f"--mountpoint={str(self.mount_point)}"])
        if p.returncode == 0:
            return True
        if p.returncode == 1:
            return False
        # If the return code is not 0 and not 1, something unexpected
        # happened, so we raise a CalledProcessException
        p.check_returncode()

    def mount(self):
        # Ensure that the mount point exists
        self.mount_point.mkdir(mode=0o770, parents=True, exist_ok=True)

        # Mount the Persistent Storage partition
        executil.check_call(["mount", "-o", "acl", self.device_path,
                             self.mount_point])

        # XXX: live-persist checked the owner and access rights of the
        # mount point here and disables the config files if they are
        # not correct. I wonder of what use that check is. If an
        # attacker is able to modify files on the volume, they can most
        # probably also set the access rights back to normal again
        # afterwards.

        # Ensure that the mount point has the correct owner, permissions
        # and ACL.
        # Permissions are set to 770. ACLs are set to allow the amnesia
        # user to traverse the directory, which is needed for mounts
        # using the link option (e.g. dotfiles).
        # refs: #7465
        os.chown(self.mount_point, uid=0, gid=0)
        self.mount_point.chmod(0o770)
        executil.check_call(["/bin/setfacl", "--remove-all",
                             self.mount_point])
        executil.check_call(["/bin/setfacl", "--modify",
                             f"user:{LIVE_USERNAME}:x", self.mount_point])

        # Ensure that all persistent directories have safe permissions.
        # refs: #7458
        for d in self.mount_point.iterdir():
            if not d.is_dir():
                continue
            # Note: we chmod even custom persistent directories.
            # This may break things by changing otherwise correct
            # permissions copied from the directory that was made
            # persistent, so we only do that if the persistent directory
            # is owned by amnesia:amnesia, and thus unlikely to be
            # a system directory. This e.g. avoids setting wrong
            # permissions on the APT, CUPS and NetworkManager
            # persistent directories.
            if d.stat().st_uid == LIVE_USER_UID or \
                    d.stat().st_gid == LIVE_USER_UID:
                continue
            # Remove all permissions for group and others
            current = stat.S_IMODE(d.stat().st_mode)
            d.chmod(current & ~stat.S_IRWXG & ~stat.S_IRWXO)

    def force_unmount(self):
        filesystem = self.udisks_object.get_filesystem()
        if not filesystem:
            # There is no filesystem, so there is nothing to unmount
            return
        # Unmount the filesystem until no mount points are left
        while filesystem.props.mount_points:
            filesystem.call_unmount_sync(arg_options=GLib.Variant('a{sv}', {
                "force": GLib.Variant('b', True),
            }))

    def get_dm_name(self) -> Optional[str]:
        udisks_devno = self.block.props.device_number
        out = executil.check_output(["dmsetup", "ls", "-o", "devno"])
        for line in out.strip().split("\n"):
            name, devno = line.split()
            if devno == f"({os.major(udisks_devno)}:{os.minor(udisks_devno)})":
                return name
        return None

    def rename_dm_device(self, new_name: str):
        dm_name = self.get_dm_name()
        if not dm_name:
            logger.warning("Can't rename dm device: dm name not found")
            return
        executil.check_call(["dmsetup", "rename", dm_name, new_name])
