"""Isolated UserDefaults suites for Debug Web host processes."""

from __future__ import annotations

import os
import re
import subprocess
import time


DEBUG_DEFAULTS_PREFIX = "com.songziqiang.MyWallpaperX.Debug."
DEBUG_DEFAULTS_RE = re.compile(r"MWX DEBUG DEFAULTS: suite=(?P<suite>\S+)")


def make_debug_defaults_suite() -> str:
    return f"{DEBUG_DEFAULTS_PREFIX}{os.getpid()}.{time.time_ns()}"


def delete_debug_defaults_suite(
    suite_name: str,
    environment: dict[str, str] | None = None,
) -> None:
    if not suite_name.startswith(DEBUG_DEFAULTS_PREFIX):
        raise ValueError("refusing to delete a defaults suite outside the Debug namespace")
    subprocess.run(
        ["/usr/bin/defaults", "delete", suite_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=environment,
        check=False,
    )


def debug_defaults_suites(log_text: str) -> list[str]:
    return [match.group("suite") for match in DEBUG_DEFAULTS_RE.finditer(log_text)]
