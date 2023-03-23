import logging
import os.path
import tempfile
from os import PathLike
import sys
from pathlib import Path
import subprocess
from typing import List, Union

import tps
import tps.logging

logger = tps.logging.get_logger(__name__)


def _run(cmd: List, *args, **kwargs) -> subprocess.CompletedProcess:
    """Run a command and print it's stderr continuously but also return
    stderr in the return CompletedProcess and any raised CalledProcessError.

    This allows us to have stderr both in the logs of the tps service
    and in the error message which might be returned to the client."""
    cmd = [str(s) for s in cmd]
    # This method will be called from executil.run() (or check_call, or check_output),
    # and we want to attribute the log message to its caller
    logger.debug(f"Executing command {' '.join(cmd)}", stacklevel=3)

    if tps.PROFILING:
        cmd = prepare_for_profiling(cmd)

    p = None
    try:
        kwargs["stderr"] = subprocess.PIPE
        kwargs["text"] = True
        p = subprocess.run(cmd, *args, **kwargs)
        return p
    finally:
        if p: print(p.stderr, file=sys.stderr)
        logger.debug(f"Done executing command", stacklevel=3)


def run(cmd: List, *args, **kwargs) -> subprocess.CompletedProcess:
    return _run(cmd, *args, **kwargs)


def check_call(cmd: List, *args, **kwargs):
    return _run(cmd, *args, **kwargs, check=True)


def check_output(cmd: List, *args, **kwargs) -> str:
    p = _run(cmd, *args, **kwargs, check=True, stdout=subprocess.PIPE)
    return p.stdout


def execute_hooks(hooks_dir: Union[str, PathLike]):
    """
    Execute all regular files in the specified directory, in (locale) lexicographic order.

    If any of these runs fails, the execution is stopped, and an exception is raised immediately.
    """
    hooks_dir = Path(hooks_dir)
    if not hooks_dir.exists():
        return

    for file in sorted(hooks_dir.iterdir()):
        if file.is_dir():
            continue
        logger.info(f"Executing hook {file}", stacklevel=2)
        cmd = [str(file)]
        if tps.PROFILING:
            cmd = prepare_for_profiling(cmd)
        try:
            check_call(cmd)
        finally:
            logger.debug(f"Done executing hook", stacklevel=2)


def prepare_for_profiling(cmd: List) -> List:
    uptime = Path("/proc/uptime").read_text().split()[0]
    profile_file = tempfile.NamedTemporaryFile(prefix=f"{uptime}-{os.path.basename(cmd[0])}.",
                                               dir=tps.PROFILES_DIR,
                                               delete=False)
    profile_file.close()
    logger.info(f"Creating profile in {profile_file.name}")
    return [
        "strace",
        "--follow-forks",
        "--quiet",
        "--relative-timestamps",
        "--syscall-times",
        "--summary",
        "--trace=file,process,network,signal,ipc,desc,memory",
        f"--output={profile_file.name}"] + cmd
