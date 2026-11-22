#!/usr/bin/env python3
"""Verify debounced Web audio capture restart and final resource cleanup."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from web_system_state_benchmark import (
    diagnostic_events,
    is_same_or_descendant,
    real_workshop_root,
    validate_runtime_paths,
)
from web_debug_defaults import debug_defaults_suites, delete_debug_defaults_suite, make_debug_defaults_suite
from web_wallpaper_benchmark import APP_NAME, DEFAULT_APP_BINARY, REPO_ROOT, start_unified_log_capture, terminate_process


EXPECTED_ACTIONS = ["burst-1", "burst-2", "burst-3", "single", "stop", "completed"]
ACTION_RE = re.compile(
    r"MWX DEBUG AUDIO RESTART:\s*(?:action=)?(?P<action>[a-z0-9-]+)\b"
)
AUDIO_STARTED_RE = re.compile(r"MWX AUDIO CAPTURE: started\b")
AUDIO_DATA_RE = re.compile(r"MWX AUDIO CAPTURE: data generation=\d+ peak=[0-9.]+")
AUDIO_STOPPED_RE = re.compile(r"MWX AUDIO CAPTURE: stopped\b")
AUDIO_RESTART_RE = re.compile(r"MWX AUDIO CAPTURE: restarting reason=debug\b")
LISTENERS_INSTALLED_RE = re.compile(r"MWX AUDIO CAPTURE: listeners installed\b")
LISTENERS_REMOVED_RE = re.compile(r"MWX AUDIO CAPTURE: listeners removed\b")
AUDIO_FAILED_RE = re.compile(r"MWX AUDIO CAPTURE: failed\b")
AUDIO_RETRY_RE = re.compile(r"MWX AUDIO CAPTURE: retry scheduled\b")
LISTENER_REMOVAL_FAILED_RE = re.compile(r"MWX AUDIO CAPTURE: listener removal failed\b")
FINAL_STOP_TOKENS = ("phase=idle", "surfaces=0", "loopbacks=0", "observers=0")


def matching_positions(lines: list[str], pattern: re.Pattern[str], after: int) -> list[int]:
    return [index for index, line in enumerate(lines) if index > after and pattern.search(line)]


def score_log(log_text: str, sample_id: str, expected_defaults_suite: str) -> dict[str, Any]:
    lines = log_text.splitlines()
    defaults_suite_confirmed = expected_defaults_suite in debug_defaults_suites(log_text)
    ready_positions = [
        index
        for index, line in enumerate(lines)
        if f"MWX WEB DIAG record={sample_id} " in line and "type=host.ready " in line
    ]
    measurement_start = ready_positions[0] if ready_positions else len(lines)
    scoped_lines = lines[measurement_start + 1 :]
    scoped_text = "\n".join(scoped_lines)

    action_entries = [
        (match.group("action"), index)
        for index, line in enumerate(lines)
        if index > measurement_start and (match := ACTION_RE.search(line))
    ]
    actions = [action for action, _ in action_entries]
    action_positions = {action: index for action, index in action_entries}
    start_positions = matching_positions(lines, AUDIO_STARTED_RE, measurement_start)
    data_positions = matching_positions(lines, AUDIO_DATA_RE, measurement_start)
    stop_positions = matching_positions(lines, AUDIO_STOPPED_RE, measurement_start)
    restart_positions = matching_positions(lines, AUDIO_RESTART_RE, measurement_start)
    installed_positions = matching_positions(lines, LISTENERS_INSTALLED_RE, measurement_start)
    removed_positions = matching_positions(lines, LISTENERS_REMOVED_RE, measurement_start)
    released_positions = [
        index
        for index, line in enumerate(lines)
        if index > measurement_start and "type=lifecycle.surface.released " in line
    ]
    scoped_events = diagnostic_events(scoped_text)
    stop_events = [event for event in scoped_events if event["type"] == "lifecycle.stop"]
    final_stop_message = stop_events[-1]["message"] if stop_events else None
    final_stop_zero = bool(
        final_stop_message
        and all(token in final_stop_message for token in FINAL_STOP_TOKENS)
    )
    lifecycle_stop_positions = [
        index
        for index, line in enumerate(lines)
        if index > measurement_start and "type=lifecycle.stop " in line
    ]
    released_count = sum(
        event["type"] == "lifecycle.surface.released" for event in scoped_events
    )
    retained_count = sum(
        event["type"] == "lifecycle.surface.retained" for event in scoped_events
    )
    failure_count = len(AUDIO_FAILED_RE.findall(log_text))
    retry_count = len(AUDIO_RETRY_RE.findall(log_text))
    listener_removal_failure_count = len(LISTENER_REMOVAL_FAILED_RE.findall(log_text))

    timeline_valid = False
    if (
        ready_positions
        and actions == EXPECTED_ACTIONS
        and len(start_positions) == 3
        and len(data_positions) == 3
        and len(stop_positions) == 3
        and len(restart_positions) == 2
        and len(installed_positions) == 3
        and len(removed_positions) == 3
        and released_positions
        and lifecycle_stop_positions
    ):
        timeline_valid = (
            ready_positions[0]
            < installed_positions[0]
            < start_positions[0]
            < data_positions[0]
            < action_positions["burst-1"]
            < action_positions["burst-2"]
            < action_positions["burst-3"]
            < restart_positions[0]
            < removed_positions[0]
            < stop_positions[0]
            < installed_positions[1]
            < start_positions[1]
            < data_positions[1]
            < action_positions["single"]
            < restart_positions[1]
            < removed_positions[1]
            < stop_positions[1]
            < installed_positions[2]
            < start_positions[2]
            < data_positions[2]
            < action_positions["stop"]
            < removed_positions[2]
            < stop_positions[2]
            < action_positions["completed"]
            and action_positions["stop"]
            < released_positions[-1]
            < action_positions["completed"]
            and action_positions["stop"]
            < lifecycle_stop_positions[-1]
            < action_positions["completed"]
        )

    failures: list[str] = []
    if not defaults_suite_confirmed:
        failures.append("debug UserDefaults isolation suite was not confirmed in app logs")
    if not ready_positions:
        failures.append(f"missing host.ready for {sample_id}")
    if actions != EXPECTED_ACTIONS:
        failures.append(f"debug action order {actions} did not match {EXPECTED_ACTIONS}")
    if len(restart_positions) != 2:
        failures.append(
            f"debug invalidations restarted capture {len(restart_positions)} time(s), expected exactly 2"
        )
    for label, count in (
        ("started", len(start_positions)),
        ("produced data", len(data_positions)),
        ("stopped", len(stop_positions)),
    ):
        if count != 3:
            failures.append(f"audio capture {label} {count} time(s), expected exactly 3")
    if len(installed_positions) != 3 or len(removed_positions) != 3:
        failures.append(
            "audio listener install/remove count was "
            f"{len(installed_positions)}/{len(removed_positions)}, expected 3/3"
        )
    if not timeline_valid:
        failures.append("three capture cycles did not follow the burst, single, and stop boundaries")
    if failure_count:
        failures.append(f"audio capture failed {failure_count} time(s)")
    if retry_count:
        failures.append(f"audio capture scheduled {retry_count} retry/retries")
    if listener_removal_failure_count:
        failures.append(
            f"audio listener removal failed {listener_removal_failure_count} time(s)"
        )
    if not final_stop_zero:
        failures.append("final lifecycle.stop did not report an idle zero state")
    if released_count < 1:
        failures.append("no Web surface release was observed before completion")
    if retained_count:
        failures.append(f"{retained_count} Web surface(s) remained retained")

    return {
        "passed": not failures,
        "sample_id": sample_id,
        "debug_defaults_suite": expected_defaults_suite if defaults_suite_confirmed else None,
        "measurement_started_after_host_ready": bool(ready_positions),
        "expected_actions": EXPECTED_ACTIONS,
        "observed_actions": actions,
        "host_ready_count": len(ready_positions),
        "audio_restart_count": len(restart_positions),
        "audio_start_count": len(start_positions),
        "audio_data_count": len(data_positions),
        "audio_stop_count": len(stop_positions),
        "listener_install_count": len(installed_positions),
        "listener_remove_count": len(removed_positions),
        "capture_timeline_valid": timeline_valid,
        "capture_failure_count": failure_count,
        "capture_retry_count": retry_count,
        "listener_removal_failure_count": listener_removal_failure_count,
        "lifecycle_stop_count": len(stop_events),
        "final_stop_message": final_stop_message,
        "final_stop_zero": final_stop_zero,
        "released_surface_count": released_count,
        "retained_surface_count": retained_count,
        "failures": failures,
    }


def make_output_dir(value: str | None) -> Path:
    if value:
        output_dir = Path(value).expanduser().resolve()
    else:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        output_dir = REPO_ROOT / f".codex/web-audio-restart-benchmark-{stamp}"
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def write_reports(output_dir: Path, report: dict[str, Any]) -> tuple[Path, Path]:
    json_path = output_dir / "report.json"
    markdown_path = output_dir / "report.md"
    json_path.write_text(
        json.dumps(report, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )
    lines = [
        "# MyWallpaperX Web Audio Restart Benchmark",
        "",
        f"- Result: {'PASS' if report['passed'] else 'FAIL'}",
        f"- Sample: `{report['sample_id']}`",
        f"- UserDefaults suite: `{report['debug_defaults_suite'] or '-'}`",
        f"- Actions: {' -> '.join(report['observed_actions']) or '-'}",
        f"- Host ready: {report['host_ready_count']}",
        f"- Debug restarts: {report['audio_restart_count']} (expected 2)",
        f"- Audio start/data/stop: {report['audio_start_count']}/{report['audio_data_count']}/{report['audio_stop_count']}",
        f"- Listener install/remove: {report['listener_install_count']}/{report['listener_remove_count']}",
        f"- Capture timeline valid: {report['capture_timeline_valid']}",
        f"- Capture failure/retry/listener removal failure: {report['capture_failure_count']}/{report['capture_retry_count']}/{report['listener_removal_failure_count']}",
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
        "--mwx-debug-web-audio-restart-sequence",
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
    print(f"Audio restart result: {'PASS' if report['passed'] else 'FAIL'}")
    return 0 if report["passed"] else 1


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Verify debounced Web audio capture restart and final cleanup.")
    parser.add_argument("--app", default=str(DEFAULT_APP_BINARY))
    parser.add_argument("--runtime-workshop-root")
    parser.add_argument("--runtime-home")
    parser.add_argument("--id", default="1509243786")
    parser.add_argument("--duration", type=float, default=15.0)
    parser.add_argument("--audio-file", default="/System/Library/Sounds/Submarine.aiff")
    parser.add_argument("--audio-volume", type=float, default=0.1)
    parser.add_argument("--no-audio-fixture", action="store_true")
    parser.add_argument("--output-dir")
    parser.add_argument("--kill-existing", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    return run_benchmark(make_parser().parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
