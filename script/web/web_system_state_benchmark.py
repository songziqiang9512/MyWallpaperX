#!/usr/bin/env python3
"""Verify Web audio capture recovery across overlapping system interruptions."""

from __future__ import annotations

import argparse
import json
import os
import pwd
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from web_debug_defaults import debug_defaults_suites, delete_debug_defaults_suite, make_debug_defaults_suite
from web_wallpaper_benchmark import APP_NAME, DEFAULT_APP_BINARY, REPO_ROOT, start_unified_log_capture, terminate_process
EXPECTED_ACTIONS = [
    "system-sleep", "display-sleep", "system-wake", "display-wake", "screen-lock", "screen-unlock", "stop", "completed",
]
DEBUG_ACTION_RE = re.compile(r"MWX DEBUG SYSTEM STATE:\s*(?:action=)?(?P<action>[a-z-]+)\b")
DIAG_RE = re.compile(
    r"MWX WEB DIAG record=(?P<record>\S+) screen=(?P<screen>\S+) "
    r"severity=(?P<severity>\S+) type=(?P<type>\S+) "
    r"url=(?P<url>\S+) message=(?P<message>.*)$"
)
AUDIO_STARTED_RE = re.compile(r"MWX AUDIO CAPTURE: started\b")
AUDIO_STOPPED_RE = re.compile(r"MWX AUDIO CAPTURE: stopped\b")
AUDIO_DATA_RE = re.compile(r"MWX AUDIO CAPTURE: data generation=\d+ peak=[0-9.]+")
AUDIO_FAILED_RE = re.compile(r"MWX AUDIO CAPTURE: failed\b")
AUDIO_RETRY_RE = re.compile(r"MWX AUDIO CAPTURE: retry scheduled\b")
FINAL_STOP_TOKENS = ("phase=idle", "surfaces=0", "loopbacks=0", "observers=0")

def actual_home() -> Path:
    return Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()


def real_workshop_root() -> Path:
    return (actual_home() / "Movies/MyWallpaperX/\u521b\u610f\u5de5\u574a").resolve()

def is_same_or_descendant(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_runtime_paths(workshop_root: Path, runtime_home: Path, sample_id: str) -> Path:
    if is_same_or_descendant(workshop_root, real_workshop_root()):
        raise ValueError(
            "runtime Workshop root must not be the real ~/Movies/MyWallpaperX/Workshop library"
        )
    if not workshop_root.is_dir():
        raise ValueError(f"runtime Workshop root does not exist: {workshop_root}")
    if runtime_home == actual_home():
        raise ValueError("runtime HOME must not be the real user home")
    if not sample_id.isdigit():
        raise ValueError("sample id must contain digits only")

    sample_project = workshop_root / "Web" / sample_id / "project.json"
    if not sample_project.is_file():
        raise ValueError(f"sample project is missing: {sample_project}")
    runtime_home.mkdir(parents=True, exist_ok=True)
    return sample_project


def diagnostic_events(log_text: str) -> list[dict[str, str]]:
    events: list[dict[str, str]] = []
    for line in log_text.splitlines():
        match = DIAG_RE.search(line)
        if match:
            events.append(match.groupdict())
    return events


def score_log(log_text: str, sample_id: str, expected_defaults_suite: str) -> dict[str, Any]:
    lines = log_text.splitlines()
    defaults_suite_confirmed = expected_defaults_suite in debug_defaults_suites(log_text)
    action_entries = [
        (match.group("action"), index)
        for index, line in enumerate(lines)
        if (match := DEBUG_ACTION_RE.search(line))
    ]
    actions = [action for action, _ in action_entries]
    action_positions = {action: index for action, index in action_entries}
    all_audio_start_positions = [
        index for index, line in enumerate(lines) if AUDIO_STARTED_RE.search(line)
    ]
    all_audio_stop_positions = [
        index for index, line in enumerate(lines) if AUDIO_STOPPED_RE.search(line)
    ]
    all_audio_data_positions = [
        index for index, line in enumerate(lines) if AUDIO_DATA_RE.search(line)
    ]
    ready_positions = [
        index
        for index, line in enumerate(lines)
        if f"MWX WEB DIAG record={sample_id} " in line and "type=host.ready " in line
    ]
    measurement_start = ready_positions[0] if ready_positions else -1
    audio_start_positions = [index for index in all_audio_start_positions if index > measurement_start]
    audio_stop_positions = [index for index in all_audio_stop_positions if index > measurement_start]
    audio_data_positions = [index for index in all_audio_data_positions if index > measurement_start]
    released_surface_positions = [
        index
        for index, line in enumerate(lines)
        if "type=lifecycle.surface.released " in line
    ]
    events = diagnostic_events(log_text)
    ready_count = sum(
        event["type"] == "host.ready" and event["record"] == sample_id
        for event in events
    )
    audio_start_count = len(audio_start_positions)
    audio_stop_count = len(audio_stop_positions)
    audio_data_count = len(audio_data_positions)
    capture_failure_count = len(AUDIO_FAILED_RE.findall(log_text))
    capture_retry_count = len(AUDIO_RETRY_RE.findall(log_text))
    stop_events = [event for event in events if event["type"] == "lifecycle.stop"]
    final_stop_message = stop_events[-1]["message"] if stop_events else None
    final_stop_zero = bool(
        final_stop_message
        and all(token in final_stop_message for token in FINAL_STOP_TOKENS)
    )
    released_surface_count = sum(
        event["type"] == "lifecycle.surface.released" for event in events
    )
    retained_surface_count = sum(
        event["type"] == "lifecycle.surface.retained" for event in events
    )
    timeline_valid = False
    if (
        actions == EXPECTED_ACTIONS
        and ready_positions
        and len(audio_start_positions) == 3
        and len(audio_stop_positions) == 3
        and len(audio_data_positions) == 3
        and released_surface_positions
    ):
        timeline_valid = (
            ready_positions[0] < audio_start_positions[0]
            < audio_data_positions[0]
            < action_positions["system-sleep"]
            < audio_stop_positions[0]
            < action_positions["system-wake"]
            < action_positions["display-wake"]
            < audio_start_positions[1]
            < audio_data_positions[1]
            < action_positions["screen-lock"]
            < audio_stop_positions[1]
            < action_positions["screen-unlock"]
            < audio_start_positions[2]
            < audio_data_positions[2]
            < action_positions["stop"]
            < audio_stop_positions[2]
            < released_surface_positions[-1]
            < action_positions["completed"]
        )

    failures: list[str] = []
    if not defaults_suite_confirmed:
        failures.append("debug UserDefaults isolation suite was not confirmed in app logs")
    if actions != EXPECTED_ACTIONS:
        failures.append(f"debug action order {actions} did not match {EXPECTED_ACTIONS}")
    if ready_count < 1:
        failures.append(f"missing host.ready for {sample_id}")
    if audio_start_count != 3:
        failures.append(f"audio capture started {audio_start_count} time(s), expected exactly 3")
    if audio_stop_count != 3:
        failures.append(f"audio capture stopped {audio_stop_count} time(s), expected exactly 3")
    if audio_data_count != 3:
        failures.append(f"audio capture produced data {audio_data_count} time(s), expected exactly 3")
    if not timeline_valid:
        failures.append("capture start/data/stop timeline did not match interruption boundaries")
    if capture_failure_count:
        failures.append(f"audio capture failed {capture_failure_count} time(s)")
    if capture_retry_count:
        failures.append(f"audio capture scheduled {capture_retry_count} retry/retries")
    if not final_stop_zero:
        failures.append("final lifecycle.stop did not report an idle zero state")
    if released_surface_count < 1:
        failures.append("no Web surface release was observed")
    if retained_surface_count:
        failures.append(f"{retained_surface_count} Web surface(s) remained retained")

    return {
        "passed": not failures,
        "sample_id": sample_id,
        "debug_defaults_suite": expected_defaults_suite if defaults_suite_confirmed else None,
        "expected_actions": EXPECTED_ACTIONS,
        "observed_actions": actions,
        "host_ready_count": ready_count,
        "audio_start_count": audio_start_count,
        "audio_stop_count": audio_stop_count,
        "audio_data_count": audio_data_count,
        "total_audio_start_count": len(all_audio_start_positions),
        "total_audio_stop_count": len(all_audio_stop_positions),
        "total_audio_data_count": len(all_audio_data_positions),
        "capture_timeline_valid": timeline_valid,
        "capture_failure_count": capture_failure_count,
        "capture_retry_count": capture_retry_count,
        "lifecycle_stop_count": len(stop_events),
        "final_stop_message": final_stop_message,
        "final_stop_zero": final_stop_zero,
        "released_surface_count": released_surface_count,
        "retained_surface_count": retained_surface_count,
        "failures": failures,
    }


def make_output_dir(value: str | None) -> Path:
    if value:
        output_dir = Path(value).expanduser().resolve()
    else:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        output_dir = REPO_ROOT / f".codex/web-system-state-benchmark-{stamp}"
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def write_reports(output_dir: Path, report: dict[str, Any]) -> tuple[Path, Path]:
    json_path = output_dir / "report.json"
    markdown_path = output_dir / "report.md"
    json_path.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# MyWallpaperX Web System State Benchmark",
        "",
        f"- Result: {'PASS' if report['passed'] else 'FAIL'}",
        f"- Sample: `{report['sample_id']}`",
        f"- UserDefaults suite: `{report['debug_defaults_suite'] or '-'}`",
        f"- Actions: {' -> '.join(report['observed_actions']) or '-'}",
        f"- Host ready: {report['host_ready_count']}",
        f"- Audio start/data/stop: {report['audio_start_count']}/{report['audio_data_count']}/{report['audio_stop_count']}",
        f"- Capture timeline valid: {report['capture_timeline_valid']}",
        f"- Capture failure/retry: {report['capture_failure_count']}/{report['capture_retry_count']}",
        f"- Final stop zero: {report['final_stop_zero']}",
        f"- Released/retained surfaces: {report['released_surface_count']}/{report['retained_surface_count']}",
        f"- Log: `{report['log_path']}`",
    ]
    if report["failures"]:
        lines.extend(["", "## Failures", ""])
        lines.extend(f"- {failure}" for failure in report["failures"])
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, markdown_path


def run_benchmark(args: argparse.Namespace) -> int:
    if not args.runtime_workshop_root or not args.runtime_home:
        print("--runtime-workshop-root and --runtime-home are required", file=sys.stderr)
        return 2

    workshop_root = Path(args.runtime_workshop_root).expanduser().resolve()
    runtime_home = Path(args.runtime_home).expanduser().resolve()
    app_binary = Path(args.app).expanduser().resolve()
    try:
        sample_project = validate_runtime_paths(workshop_root, runtime_home, args.id)
    except ValueError as error:
        print(f"Precondition failed: {error}", file=sys.stderr)
        return 2
    if not app_binary.is_file() or not os.access(app_binary, os.X_OK):
        print(f"App binary is missing or not executable: {app_binary}", file=sys.stderr)
        return 2
    if args.duration <= 0:
        print("--duration must be positive", file=sys.stderr)
        return 2
    audio_file = Path(args.audio_file).expanduser().resolve()
    if not args.no_audio_fixture and not audio_file.is_file():
        print(f"Audio fixture is missing: {audio_file}", file=sys.stderr)
        return 2
    if not 0 < args.audio_volume <= 1:
        print("--audio-volume must be greater than 0 and at most 1", file=sys.stderr)
        return 2

    output_dir = make_output_dir(args.output_dir)
    log_path = output_dir / "app.log"
    if args.kill_existing:
        subprocess.run(
            ["/usr/bin/pkill", "-x", APP_NAME],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        time.sleep(0.25)

    command = [
        str(app_binary),
        "--mwx-debug-user-defaults-suite", (defaults_suite := make_debug_defaults_suite()),
        "--mwx-debug-suppress-main-window",
        "--mwx-log-web-diagnostics",
        "--mwx-debug-web-system-state-sequence",
        args.id,
        "--mwx-debug-workshop-root",
        str(workshop_root),
    ]
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)

    started = time.monotonic()
    process: subprocess.Popen[Any] | None = None
    audio_process: subprocess.Popen[Any] | None = None
    exit_code: int | None = None
    launch_error: str | None = None
    with log_path.open("w", encoding="utf-8") as handle:
        log_process = start_unified_log_capture(handle)
        try:
            time.sleep(0.25)
            try:
                process = subprocess.Popen(
                    command,
                    cwd=REPO_ROOT,
                    stdout=handle,
                    stderr=subprocess.STDOUT,
                    env=environment,
                    start_new_session=True,
                )
            except OSError as error:
                launch_error = str(error)
            deadline = time.monotonic() + args.duration
            while process is not None and process.poll() is None and time.monotonic() < deadline:
                if not args.no_audio_fixture and (
                    audio_process is None or audio_process.poll() is not None
                ):
                    audio_process = subprocess.Popen(
                        ["/usr/bin/afplay", "-v", str(args.audio_volume), str(audio_file)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                time.sleep(0.1)
        finally:
            if audio_process is not None and audio_process.poll() is None:
                audio_process.terminate()
                try:
                    audio_process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    audio_process.kill()
            if process is not None:
                exit_code = terminate_process(process)
            terminate_process(log_process)
            delete_debug_defaults_suite(defaults_suite, environment)

    report = score_log(log_path.read_text(encoding="utf-8", errors="replace"), args.id, defaults_suite)
    report.update(
        {
            "schema_version": 1,
            "generated_at": datetime.now().isoformat(timespec="seconds"),
            "duration_seconds": round(time.monotonic() - started, 2),
            "requested_duration_seconds": args.duration,
            "process_exit_code": exit_code,
            "launch_error": launch_error,
            "app_binary": str(app_binary),
            "runtime_workshop_root": str(workshop_root),
            "runtime_home": str(runtime_home),
            "audio_fixture": None if args.no_audio_fixture else str(audio_file),
            "sample_project": str(sample_project),
            "log_path": str(log_path),
        }
    )
    if launch_error:
        report["failures"].insert(0, f"failed to launch app: {launch_error}")
        report["passed"] = False

    json_path, markdown_path = write_reports(output_dir, report)
    print(f"Report JSON: {json_path}")
    print(f"Report Markdown: {markdown_path}")
    print(f"System state result: {'PASS' if report['passed'] else 'FAIL'}")
    return 0 if report["passed"] else 1


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Verify Web audio capture recovery across system interruptions.")
    parser.add_argument("--app", default=str(DEFAULT_APP_BINARY))
    parser.add_argument("--runtime-workshop-root")
    parser.add_argument("--runtime-home")
    parser.add_argument("--id", default="1509243786")
    parser.add_argument("--duration", type=float, default=18.0)
    parser.add_argument("--audio-file", default="/System/Library/Sounds/Submarine.aiff")
    parser.add_argument("--audio-volume", type=float, default=0.15)
    parser.add_argument("--no-audio-fixture", action="store_true")
    parser.add_argument("--output-dir")
    parser.add_argument("--kill-existing", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    return run_benchmark(make_parser().parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
