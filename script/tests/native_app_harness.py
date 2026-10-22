"""Launch added active-AppKit checks; launcher status is not the App exit status.

Existing CLI behavior checks retain their own direct-child exit assertions.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
import plistlib
import signal
import subprocess
from typing import Sequence
import uuid


PROOF_ENVIRONMENT_KEYS = frozenset({
    "MWX_PREVIEW_PROOF_DIR", "MWX_SIL_DEMAND_PROOF_DIR", "MWX_VIDEO_PREFETCH_PROOF_DIR",
})


@dataclass(frozen=True)
class NativeAppLaunch:
    launch_returncode: int
    stdout: str
    stderr: str


def prepare_native_app(work: Path, name: str) -> Path:
    contents = work / (name + ".app") / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    binary = contents / "MacOS" / name
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.mywallpaperx.tests." + uuid.uuid4().hex,
        "CFBundleName": name,
        "CFBundleExecutable": name,
        "CFBundlePackageType": "APPL",
        "NSPrincipalClass": "NSApplication",
        "LSMinimumSystemVersion": "15.0",
    }))
    return binary


def run_native_app(
    binary: Path, arguments: Sequence[str] = (), *, timeout: float,
    proof_environment: str | None = None,
) -> NativeAppLaunch:
    binary = binary.resolve()
    work = binary.parents[3]
    home, temporary = work / "home", work / "tmp"
    home.mkdir(exist_ok=True)
    temporary.mkdir(exist_ok=True)
    stdout, stderr, pid_file = [work / ("native-app" + suffix) for suffix in (".stdout", ".stderr", ".pid")]
    stdout.write_text("")
    stderr.write_text("")
    pid_file.unlink(missing_ok=True)
    overrides = {
        "HOME": str(home), "CFFIXED_USER_HOME": str(home), "TMPDIR": str(temporary) + "/",
        "CLANG_MODULE_CACHE_PATH": str(work / "clang-modules"),
        "SWIFT_MODULECACHE_PATH": str(work / "swift-modules"),
        "MWX_NATIVE_HARNESS_PID_PATH": str(pid_file),
    }
    if proof_environment is not None:
        if proof_environment not in PROOF_ENVIRONMENT_KEYS:
            raise ValueError("unsupported native fixture proof environment key")
        if value := os.environ.get(proof_environment):
            overrides[proof_environment] = value
    command = ["/usr/bin/open", "-n", "-W", "--stdout", str(stdout), "--stderr", str(stderr)]
    for key, value in overrides.items():
        command += ["--env", key + "=" + value]
    command += [str(binary.parents[2]), "--args", *arguments]
    try:
        launched = subprocess.run(command, capture_output=True, text=True, cwd=work, timeout=timeout)
    except subprocess.TimeoutExpired:
        if pid_file.exists():
            pid = int(pid_file.read_text())
            owner = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="],
                                   capture_output=True, text=True).stdout.strip()
            if owner == str(binary):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        raise
    return NativeAppLaunch(launched.returncode, stdout.read_text(),
                           stderr.read_text() + launched.stdout + launched.stderr)
