from gdbus_util import DBusError


class ActivationFailedError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.ActivationFailed"


class DeactivationFailedError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.DeactivationFailed"


class DeletionFailedError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.DeletionFailed"


class FailedPreconditionError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.FailedPrecondition"


class JobCancelledError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.JobCancelled"


class TargetIsBusyError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.TargetIsBusyError"


class NotEnoughMemoryError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.NotEnoughMemoryError"


class IncorrectPassphraseError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.IncorrectPassphraseError"


class SymlinkSourceDirectoryError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.SymlinkSourceDirectoryError"


class InvalidConfigFileError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.InvalidConfigFileError"


class FeatureActivationFailedError(DBusError):
    name = "org.boum.tails.PersistentStorage.Error.FeatureActivationFailedError"
