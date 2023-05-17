import logging
import os
import subprocess
import threading
from pathlib import Path

from gi.repository import Gio, GLib
from logging import getLogger
import time
from typing import TYPE_CHECKING, List, Optional

from tps import executil
from tps.configuration import features
from tps.configuration.config_file import ConfigFile, InvalidStatError
from tps.configuration.feature import Feature, ConflictingProcessesError
from tps.dbus.errors import InvalidConfigFileError, FailedPreconditionError, \
    FeatureActivationFailedError, ActivationFailedError, DeactivationFailedError
from tps.dbus.object import DBusObject
from tps.device import udisks, BootDevice, Partition, InvalidBootDeviceError
from tps.job import ServiceUsingJobs
from tps import State, IN_PROGRESS_STATES, DBUS_ROOT_OBJECT_PATH, \
    DBUS_SERVICE_INTERFACE, TPS_MOUNT_POINT, TPS_BACKUP_MOUNT_POINT, \
    ON_ACTIVATED_HOOKS_DIR, ON_DEACTIVATED_HOOKS_DIR, \
    DBUS_FEATURES_PATH

if TYPE_CHECKING:
    from tps.job import Job

logger = getLogger(__name__)


class AlreadyCreatedError(Exception):
    pass


class NotCreatedError(Exception):
    pass


class AlreadyUnlockedError(Exception):
    pass


class NotUnlockedError(Exception):
    pass


class Service(DBusObject, ServiceUsingJobs):
    dbus_info = '''
        <node>
            <interface name='org.boum.tails.PersistentStorage'>
                <method name='Quit'/>
                <method name='Reload'/>
                <method name='GetFeatures'>
                    <arg name='features' direction='out' type='as'/>
                </method>
                <method name='Create'>
                    <arg name='passphrase' direction='in' type='s'/>
                </method>
                <method name='CreateBackup'>
                    <arg name='passphrase' direction='in' type='s'/>
                    <arg name='device' direction='in' type='s'/>
                </method>
                <method name='UpdateBackup'>
                    <arg name='passphrase' direction='in' type='s'/>
                    <arg name='device' direction='in' type='s'/>
                </method>
                <method name='ChangePassphrase'>
                    <arg name='passphrase' direction='in' type='s'/>
                    <arg name='new_passphrase' direction='in' type='s'/>
                </method>
                <method name='Delete'/>
                <method name='Activate'/>
                <method name='Unlock'>
                    <arg name='passphrase' direction='in' type='s'/>
                </method>
                <method name='UpgradeLUKS'>
                    <arg name='passphrase' direction='in' type='s'/>
                </method>
                <method name='TestPassphrase'>
                    <arg name='passphrase' direction='in' type='s'/>
                    <arg name='device' direction='in' type='s'/>
                    <arg name='is_correct' direction='out' type='b'/>
                </method>
                <property name="State" type="s" access="read" />
                <property name="Error" type="s" access="read" />
                <property name="IsCreated" type="b" access="read"/>
                <property name="IsUnlocked" type="b" access="read"/>
                <property name="IsUpgraded" type="b" access="read"/>
                <property name="BootDeviceIsSupported" type="b" access="read"/>
                <property name="Device" type="s" access="read"/>
                <property name="Job" type="o" access="read"/>
            </interface>
        </node>
        '''

    dbus_path = DBUS_ROOT_OBJECT_PATH

    def __init__(self, connection: Gio.DBusConnection, loop: GLib.MainLoop):
        super().__init__(connection=connection)
        self.connection = connection
        self.mainloop = loop
        self.object_manager = None  # type: Optional[Gio.DBusObjectManagerServer]
        self.config_file = ConfigFile(TPS_MOUNT_POINT)
        self.bus_id = None
        self.features = list()  # type: List[Feature]
        self._partition = None  # type: Optional[Partition]
        self._device = ""
        self.state = State.UNKNOWN
        self._error = ""
        self._unlocked = False
        self._upgraded = False
        self._created = False
        self.enable_features_lock = threading.Lock()

        # Check if the boot device is valid for creating a Persistent
        # Storage. We only do this once and not in refresh_state(),
        # because we don't expect the boot device to change while the
        # service is running.
        try:
            self._boot_device = BootDevice.get_tails_boot_device()
        except InvalidBootDeviceError as e:
            logger.warning("Invalid boot device: %s", e)
            self._boot_device = None
            self.State = State.NOT_CREATED
            self.Error = str(e)
            return

        self.refresh_state()

    # ----- Exported methods ----- #

    def Quit_method_call_handler(self, connection: Gio.DBusConnection,
                                 parameters: GLib.Variant,
                                 invocation: Gio.DBusMethodInvocation):
        """Terminate the Persistent Storage service."""
        # Make the D-Bus method return first, else our main thread
        # might exit before we can call return, resulting in a NoReply
        # error on the client.
        invocation.return_value(None)
        connection.flush_sync()
        logger.info("Quit() was called, terminating...")
        self.settle()
        self.unregister(self.connection)
        self.wait_for_method_calls_to_finish(True)
        self.stop()

    def Reload(self):
        """Reload the state of the service and all features"""
        self.refresh_state()
        self.refresh_features()

    def GetFeatures(self) -> List[str]:
        """List the IDs of all features"""
        self.refresh_features()
        return [f.Id for f in self.features]

    def Create(self, passphrase: str):
        """Create the Persistent Storage partition and activate the
        default features"""

        logger.info("Creating Persistent Storage...")

        # Check if we can create the Persistent Storage
        if self.state != State.NOT_CREATED:
            msg = "Can't create Persistent Storage when state is '%s'" % \
                  self.state.name
            raise FailedPreconditionError(msg)

        try:
            self.do_create(passphrase)
        finally:
            self.refresh_state(overwrite_in_progress=True)
            self.refresh_features()

        logger.info("Done creating Persistent Storage")

    def do_create(self, passphrase: str):
        self.State = State.CREATING
        with self.new_job() as job:
            self._partition = Partition.create(job, passphrase)

        # Activate all features that should be enabled by default
        for feature in (f for f in self.features if f.enabled_by_default):
            try:
                feature.do_activate(None, non_blocking=True)
            except ConflictingProcessesError as e:
                # We can't automatically activate the feature, but
                # lets not bother the user about that, because they
                # did not explicitly enable the feature. If they try
                # to enable it explicitly, they will see a message
                # about the conflicting process.
                logger.warning(e)
            finally:
                feature.refresh_state()

        self.run_on_activated_hooks()

    def CreateBackup(self, passphrase: str, device: str):
        """Create a backup of the Persistent Storage partition"""
        logger.info(f"Creating Persistent Storage backup on device {device}...")

        if self.state != State.UNLOCKED:
            msg = "Can't create backup of Persistent Storage when state is '%s'" % \
                  self.state.name
            raise FailedPreconditionError(msg)

        dev_num = os.stat(device).st_rdev
        device = BootDevice(udisks.get_block_for_dev(dev_num).get_object())
        partition = Partition.create(None, passphrase, device)

        # Mount the cleartext device
        Path(TPS_BACKUP_MOUNT_POINT).mkdir(parents=True, exist_ok=True)
        cleartext_device_path = partition.get_cleartext_device().device_path
        executil.check_call(["mount", cleartext_device_path,
                             TPS_BACKUP_MOUNT_POINT])

        # Copy the data from the Persistent Storage to the new device
        executil.check_call(['/usr/local/lib/tails-backup-rsync'])

        # Unmount the cleartext device
        partition.get_cleartext_device().force_unmount()

        # Delete the mountpoint
        Path(TPS_BACKUP_MOUNT_POINT).rmdir()

        # Close the LUKS device
        partition._get_encrypted().call_lock_sync(
            arg_options=GLib.Variant('a{sv}', {}),
        )

    def UpdateBackup(self, passphrase: str, device: str):
        """Update a backup of the Persistent Storage partition"""
        logger.info(f"Updating Persistent Storage backup on device {device}...")

        if self.state != State.UNLOCKED:
            msg = "Can't update backup of Persistent Storage when state is '%s'" % \
                  self.state.name
            raise FailedPreconditionError(msg)

        dev_num = os.stat(device).st_rdev
        device = BootDevice(udisks.get_block_for_dev(dev_num).get_object())
        partition = Partition.create(None, passphrase, device)

        was_unlocked = partition.is_unlocked()
        if was_unlocked:
            cleartext_device = partition.get_cleartext_device()
            cleartext_device.mount_point = TPS_BACKUP_MOUNT_POINT
            was_mounted = cleartext_device.is_mounted()
        else:
            was_mounted = False

        # Upgrade the LUKS device of the backup Persistent Storage to
        # LUKS2 and convert the PBKDF to argon2id if necessary
        if not partition.is_upgraded():
            partition.test_passphrase(passphrase)
            # The partition must be locked before upgrading to LUKS2
            partition.ensure_locked()
            partition.upgrade_luks2()
            partition.convert_pbkdf_argon2id(passphrase)

        # Unlock the backup Persistent Storage
        if not partition.is_unlocked():
            partition.unlock(passphrase)

        # Mount the cleartext device
        if not was_mounted:
            Path(TPS_BACKUP_MOUNT_POINT).mkdir(parents=True, exist_ok=True)
            cleartext_device_path = partition.get_cleartext_device().device_path
            executil.check_call(["mount", cleartext_device_path,
                                 TPS_BACKUP_MOUNT_POINT])

        # Copy the data from the Persistent Storage to the new device
        executil.check_call(['/usr/local/lib/tails-backup-rsync'])

        # Unmount the cleartext device and delete the mountpoint
        if not was_mounted:
            partition.get_cleartext_device().force_unmount()
            Path(TPS_BACKUP_MOUNT_POINT).rmdir()

        # Close the LUKS device
        if not was_unlocked:
            partition._get_encrypted().call_lock_sync(
                arg_options=GLib.Variant('a{sv}', {}),
            )

    def Delete(self):
        """Delete the Persistent Storage partition"""
        # Check if we can delete the Persistent Storage
        if self.state not in (State.NOT_UNLOCKED, State.UNLOCKED):
            msg = "Can't delete Persistent Storage when state is '%s'" % \
                  self.state.name
            raise FailedPreconditionError(msg)

        logger.info("Deleting Persistent Storage...")

        try:
            # Disable all features first to ensure that no process is
            # accessing any of the mounts
            for feature in self.features:
                if feature.IsActive:
                    feature.Deactivate()
            self.do_delete()
        finally:
            self.refresh_state(overwrite_in_progress=True)
            self.refresh_features()

        logger.info("Done deleting Persistent Storage")

    def do_delete(self):
        # Delete the partition
        self.State = State.DELETING
        self._partition.delete()

    def Activate(self):
        """Activate all Persistent Storage features which are currently
        configured in the persistence.conf config file."""

        logger.info("Activating Persistent Storage...")

        # Wait for all udev and UDisks events to finish
        executil.check_call(["udevadm", "settle"])
        udisks.settle()

        # Check if we can activate the Persistent Storage
        if self.state != State.UNLOCKED:
            msg = "Can't activate features when state is '%s'" % \
                  self.state.name
            return FailedPreconditionError(msg)

        partition = Partition.find()
        if not partition:
            raise NotCreatedError("No Persistent Storage found")

        try:
            self.do_activate()
        finally:
            self.refresh_state()
            self.refresh_features()

        logger.info("Done activating Persistent Storage")

    def do_activate(self):
        # Ensure that the config file exists
        if not self.config_file.exists():
            self.config_file.save([])

        # Check that the config file has secure ownership and
        # permissions. If not, disable the file and create an empty
        # file.
        try:
            self.config_file.check_file_stat()
        except InvalidStatError as e:
            logger.warning(f"Disabling invalid config file: {e}")
            try:
                self.config_file.disable_and_create_empty()
                self.run_on_activated_hooks()
            finally:
                raise InvalidConfigFileError(e) from e

        self.refresh_features()
        failed_feature_names = list()
        for feature in [f for f in self.features if f.IsEnabled]:
            try:
                feature.do_activate(None, non_blocking=True)
            except Exception as e:
                logger.exception(e)
                failed_feature_names.append(feature.translatable_name)
            finally:
                feature.refresh_state(emit_properties_changed_signal=True)

        self.run_on_activated_hooks()

        if any(failed_feature_names):
            # We want to show a translatable error message to the user
            # but because the Service.Activate method is called in the
            # Welcome Screen (and only there), only the Welcome Screen
            # knows which language the user has currently selected.
            # So we let the Welcome Screen translate the error message
            # instead and make it easy for it by just passing the list
            # of translatable feature names in the error message.
            msg = ":".join(failed_feature_names)
            raise FeatureActivationFailedError(msg)

    def Unlock(self, passphrase: str):
        """Unlock and mount the Persistent Storage"""

        logger.info("Unlocking Persistent Storage...")

        # Check if we can unlock the Persistent Storage
        if self.state != State.NOT_UNLOCKED:
            msg = "Can't unlock when state is '%s'" % self.state.name
            raise FailedPreconditionError(msg)

        try:
            self.do_unlock(passphrase)
        finally:
            self.refresh_state(overwrite_in_progress=True)
            # We don't refresh the features here to avoid that any errors
            # caused by unexpected state of the Persistent Storage are
            # shown to the user as "Failed to Unlock", which would be
            # misleading because it was unlocked successfully.
            # We expect the caller to call Activate next after a
            # successful Unlock call and we refresh the features there,
            # so it should be fine to skip it here.

        logger.info("Done unlocking Persistent Storage")

    def do_unlock(self, passphrase: str):
        self.state = State.UNLOCKING

        # Unlock the Persistent Storage
        if not self._partition.is_unlocked():
            self._partition.unlock(passphrase)

        # Mount the Persistent Storage
        cleartext_device = self._partition.get_cleartext_device()
        if not cleartext_device.is_mounted():
            cleartext_device.mount()

    def UpgradeLUKS(self, passphrase: str):
        """Upgrade the LUKS header and key derivation function"""

        logger.info("Upgrading Persistent Storage...")

        # Check if we can unlock the Persistent Storage
        if self.state != State.NOT_UNLOCKED:
            msg = "Can't upgrade when state is '%s'" % self.state.name
            raise FailedPreconditionError(msg)

        try:
            self.do_upgrade_luks(passphrase)
        finally:
            self.refresh_state(overwrite_in_progress=True)

        logger.info("Done upgrading Persistent Storage")

    def do_upgrade_luks(self, passphrase: str):
        self.state = State.UNLOCKING
        self._partition.test_passphrase(passphrase)
        self._partition.upgrade_luks2()
        self._partition.convert_pbkdf_argon2id(passphrase)

    def TestPassphrase(self, passphrase: str, device: str) -> bool:
        """Do not unlock the Persistent Storage, just test if the
        specified passphrase is correct. Return True if the passphrase
        is correct, False otherwise."""

        if device == "":
            device = BootDevice.get_tails_boot_device()
        else:
            dev_num = os.stat(device).st_rdev
            device = BootDevice(udisks.get_block_for_dev(dev_num).get_object())

        logger.info(f"Testing passphrase for {device.device_path}...")

        partition = Partition.find(device)
        if not partition:
            raise NotCreatedError("No Persistent Storage found")

        try:
            executil.check_call(["cryptsetup", "luksOpen", "--test-passphrase",
                                 "--key-file=-", partition.device_path],
                                input=passphrase)
            logger.info("Passphrase is correct")
            return True
        except subprocess.CalledProcessError as e:
            if e.returncode == 2:
                logger.info("Passphrase is incorrect")
                return False
            raise
        finally:
            logger.info("Done testing passphrase")


    def ChangePassphrase(self, passphrase: str, new_passphrase: str):
        """Change the passphrase of the Persistent Storage encrypted
        partition"""

        logger.info("Changing passphrase...")

        partition = Partition.find()
        if not partition:
            raise NotCreatedError("No Persistent Storage found")

        partition.change_passphrase(passphrase, new_passphrase)

        logger.info("Done changing passphrase")

    # ----- Exported properties ----- #

    @property
    def State(self) -> str:
        """The state of the Persistent Storage"""
        return self.state.name

    @State.setter
    def State(self, state: State):
        if self.state == state:
            # Nothing to do
            return
        self.state = state
        changed_properties = {"State": GLib.Variant("s", state.name)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    @property
    def Error(self) -> str:
        """The error message, if State is ERROR"""
        return self._error

    @Error.setter
    def Error(self, msg: str):
        if self._error == msg:
            # Nothing to do
            return
        self._error = msg
        changed_properties = {"Error": GLib.Variant("s", msg)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    @property
    def IsCreated(self) -> bool:
        """Whether the Persistent Storage partition is created."""
        return self._created

    @IsCreated.setter
    def IsCreated(self, value: bool):
        if self._created == value:
            # Nothing to do
            return
        self._created = value
        changed_properties = {"IsCreated": GLib.Variant("b", value)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    @property
    def IsUnlocked(self) -> bool:
        """Whether the Persistent Storage partition is unlocked and
        mounted (we also require it to be mounted to avoid having to add
        a separate property IsMounted)."""
        # We could use the cached value, self._unlocked, here, but the
        # cost of refreshing seem to be low here, and the benefit is
        # that the value will be correct even if the user unlocked the
        # partition in some other way than by using this service's
        # Unlock() method (for example GNOME Disks or cryptsetup).
        self.refresh_state()
        return self._unlocked

    @IsUnlocked.setter
    def IsUnlocked(self, value: bool):
        if self._unlocked == value:
            # Nothing to do
            return
        self._unlocked = value
        changed_properties = {"IsUnlocked": GLib.Variant("b", value)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    @property
    def IsUpgraded(self) -> bool:
        """Whether the LUKS header and key derivation function have
        been upgraded to LUKS2 and argon2id"""
        self.refresh_state()
        return self._upgraded

    @IsUpgraded.setter
    def IsUpgraded(self, value: bool):
        if self._upgraded == value:
            # Nothing to do
            return
        self._upgraded = value
        changed_properties = {"IsUpgraded": GLib.Variant("b", value)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    @property
    def BootDeviceIsSupported(self) -> bool:
        return bool(self._boot_device)

    @property
    def Device(self) -> str:
        return self._device

    @Device.setter
    def Device(self, value: str):
        if self._device == value:
            # Nothing to do
            return
        self._device = value
        changed_properties = {"Device": GLib.Variant("s", value)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    @property
    def Job(self) -> str:
        return self._job.dbus_path if self._job else "/"

    @Job.setter
    def Job(self, job: "Job"):
        self._job = job
        changed_properties = {"Job": GLib.Variant("s", self.Job)}
        self.emit_properties_changed_signal(
            self.connection,
            DBUS_SERVICE_INTERFACE,
            changed_properties,
        )

    # ----- Non-exported functions ----- #

    def start(self):
        """Start the Persistent Storage service."""
        try:
            self.register(self.connection)

            # Create the object manager
            object_manager_path = DBUS_FEATURES_PATH
            self.object_manager = Gio.DBusObjectManagerServer(
                object_path=object_manager_path,
            )

            for FeatureClass in features.get_classes():
                feature = FeatureClass(self)
                feature.register(self.connection)
                self.object_manager.export(Gio.DBusObjectSkeleton.new(feature.dbus_path))
                self.features.append(feature)

            # Export the object manager on the connection. We do this
            # after exporting the features above to avoid
            # InterfacesAdded signals being emitted.
            self.object_manager.set_connection(self.connection)

            self.refresh_features()

            logger.debug("Done registering objects")
        except:
            self.stop()
            raise

    def stop(self):
        self.settle()
        logger.debug("Exiting")
        self.mainloop.quit()

    def settle(self):
        # Wait until all pending events on the main loop were handled
        context = self.mainloop.get_context()  # type: GLib.MainContext
        while context.iteration(may_block=False):
            logger.debug("Waiting for mainloop events to be handled")
            time.sleep(0.1)

    def enable_feature(self, feature: Feature):
        with self.enable_features_lock:
            enabled_features = [ftr for ftr in self.features
                                if ftr.IsEnabled]
            self.config_file.save(enabled_features + [feature])
            feature.refresh_state(["IsEnabled"])
            if not feature.IsEnabled:
                msg = f"Failed to enable feature '{feature.Id}' in config file"
                raise ActivationFailedError(msg)

    def disable_feature(self, feature: Feature):
        with self.enable_features_lock:
            enabled_features = [ftr for ftr in self.features
                                if ftr.IsEnabled]
            enabled_features.remove(feature)
            self.config_file.save(enabled_features)
            feature.refresh_state(["IsEnabled"])
            if feature.IsEnabled:
                msg = f"Failed to disable feature '{feature.Id}' in config file"
                raise DeactivationFailedError(msg)

    def refresh_features(self):
        # Refresh custom features
        mounts = list()
        if self.config_file.exists():
            mounts = self.config_file.parse()
            known_mounts = [mount for feature in self.features
                            for mount in feature.Mounts]
            unknown_mounts = [mount for mount in mounts
                              if mount not in known_mounts]
            for i, mount in enumerate(unknown_mounts):
                class CustomFeature(Feature):
                    Id = f"CustomFeature{i}"
                    translatable_name = f"Custom Feature ({mount.dest_orig})"
                    Description = str(mount.dest_orig)
                    Mounts = [mount]
                custom_feature = CustomFeature(self, is_custom=True)
                custom_feature.register(self.connection)
                self.object_manager.export(Gio.DBusObjectSkeleton.new(custom_feature.dbus_path))
                self.features.append(custom_feature)

        # Remove the ones whose mount entry was removed from the config
        # file
        custom_features = [f for f in self.features if f.is_custom]
        for known_custom_feature in custom_features:
            if known_custom_feature.Mounts[0] not in mounts:
                known_custom_feature.unregister(self.connection)
                self.object_manager.unexport(known_custom_feature.dbus_path)
                self.features.remove(known_custom_feature)

        # Refresh state of all features
        exceptions = list()
        for feature in self.features:
            try:
                feature.refresh_state(emit_properties_changed_signal=True)
            except Exception as e:
                if exceptions: logging.exception(e)
                exceptions.append(exceptions)
        if exceptions:
            raise exceptions[0]

    def refresh_state(self, overwrite_in_progress: bool = False):
        if not self._boot_device:
            # The boot device doesn't exist, which is already handled
            # in the __init__ method, so we don't change the state here
            return

        # Don't overwrite the state if we're in the middle of something.
        # In all methods which set any of these states, we ensure that
        # the state is set to something else when the operation is done
        # or failed.
        if not overwrite_in_progress and self.state in IN_PROGRESS_STATES:
            return

        # Check if the partition exists
        self._partition = Partition.find()
        if not self._partition:
            self.State = State.NOT_CREATED
            self.Device = ""
            self.IsCreated = False
            self.IsUnlocked = False
            self.IsUpgraded = False
            return

        self.Device = self._partition.device_path
        self.IsCreated = True
        self.IsUpgraded = self._partition.is_upgraded()

        # Check if the partition is unlocked and mounted
        if not self._partition.is_unlocked_and_mounted():
            self.State = State.NOT_UNLOCKED
            self.IsUnlocked = False
            return

        self.State = State.UNLOCKED
        self.IsUnlocked = True

    @staticmethod
    def run_on_activated_hooks():
        executil.execute_hooks(ON_ACTIVATED_HOOKS_DIR)

    @staticmethod
    def run_on_deactivated_hooks():
        executil.execute_hooks(ON_DEACTIVATED_HOOKS_DIR)
