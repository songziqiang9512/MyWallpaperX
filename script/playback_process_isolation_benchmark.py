#!/usr/bin/env python3
"""Block parent UI while Web/music continue, then verify failure/restart/handoffs.

The Scene argument must point to an isolated copy. No user media is modified;
the app's native DEBUG runner drives the real production clients and children.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from web_benchmark_capture import (
    discard_staged_app, require_fresh_output_dir, stage_signed_app, verify_staged_app,
)
from web_wallpaper_benchmark import terminate_process


def native_outcome(result: object, expected: int) -> str:
    if not isinstance(result, dict):
        return "failed"
    checks, not_covered = result.get("checks"), result.get("notCovered")
    if (not isinstance(checks, dict) or not isinstance(not_covered, dict)
            or checks.keys() & not_covered.keys()
            or len(checks) + len(not_covered) != expected
            or any(type(value) is not bool or not value for value in checks.values())
            or any(not isinstance(reason, str) or not reason for reason in not_covered.values())):
        return "failed"
    outcome = "incomplete" if not_covered else "passed"
    if result.get("outcome") != outcome or result.get("passed") is not (outcome == "passed"):
        return "failed"
    return outcome


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--runtime-home", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--scene-root", type=Path)
    parser.add_argument("--timeout", type=float, default=240)
    args = parser.parse_args()
    home = args.runtime_home.expanduser().resolve()
    output = args.output_dir.expanduser().resolve()
    media = (Path.home() / "Movies/MyWallpaperX").resolve()
    for path in [home, output, *([args.scene_root.resolve()] if args.scene_root else [])]:
        if path == media or path.is_relative_to(media):
            parser.error("runtime paths must be isolated from real user media")
    if home.exists() and any(home.iterdir()):
        parser.error("runtime home must be fresh")
    require_fresh_output_dir(output)
    home.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    binary, identity = stage_signed_app(args.app, output)
    native_report = output / "native-report.json"
    command = [str(binary), "--mwx-debug-suppress-main-window",
        "--mwx-debug-web-process-isolation-report", str(native_report)]
    if args.scene_root:
        command += ["--mwx-debug-isolation-scene-root", str(args.scene_root.resolve())]
    environment = os.environ.copy()
    environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home))
    failure = None
    result = None
    with (output / "app.log").open("w") as log:
        process = subprocess.Popen(command, env=environment, stdout=log,
            stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                if native_report.exists():
                    result = json.loads(native_report.read_text())
                    break
                if process.poll() is not None:
                    failure = f"App exited before report: {process.returncode}"
                    break
                time.sleep(0.1)
            else:
                failure = "native runner timed out"
        finally:
            terminate_process(process)
    verify_staged_app(identity)
    expected = 33 if args.scene_root else 25
    outcome = native_outcome(result, expected) if failure is None else "failed"
    passed = outcome == "passed"
    if passed:
        discard_staged_app(identity)
    report = {"passed": passed, "outcome": outcome, "failure": failure, "result": result, "appIdentity": identity}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Playback process isolation: {outcome.upper()} — {output / 'report.json'}")
    if outcome == "incomplete":
        print("Not covered: " + json.dumps(result["notCovered"], ensure_ascii=False))
    return 0 if passed else 2 if outcome == "incomplete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
