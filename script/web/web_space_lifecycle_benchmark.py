#!/usr/bin/env python3
"""Verify Web host Space and screen observer lifecycle behavior."""

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

from web_debug_defaults import (
    debug_defaults_suites,
    delete_debug_defaults_suite,
    make_debug_defaults_suite,
)
from web_system_state_benchmark import DIAG_RE, validate_runtime_paths
from web_wallpaper_benchmark import (
    APP_NAME,
    DEFAULT_APP_BINARY,
    REPO_ROOT,
    start_unified_log_capture,
    terminate_process,
)


EXPECTED_ACTIONS = [
    "default-space",
    "workspace-space",
    "screen-burst",
    "relaunch",
    "workspace-space-after-relaunch",
    "stop",
    "post-stop-notifications",
    "completed",
]
ACTION_RE = re.compile(
    r"MWX DEBUG SPACE LIFECYCLE:\s*(?:action=)?(?P<action>[a-z0-9-]+)\b"
)
EVENT_TYPES = (
    "lifecycle.space.observed",
    "lifecycle.space.reasserted",
    "lifecycle.screen.observed",
    "lifecycle.screen.reconciled",
)
EXPECTED_EVENT_COUNTS = {
    "lifecycle.space.observed": 2,
    "lifecycle.space.reasserted": 2,
    "lifecycle.screen.observed": 3,
    "lifecycle.screen.reconciled": 1,
}
FINAL_STOP_TOKENS = ("phase=idle", "surfaces=0", "loopbacks=0", "observers=0")
MINIMUM_DURATION_SECONDS = 22.0


def diagnostic_positions(
    lines: list[str], event_type: str, after: int = -1
) -> list[int]:
    positions: list[int] = []
    for index, line in enumerate(lines):
        if index <= after:
            continue
        match = DIAG_RE.search(line)
        if match and match.group("type") == event_type:
            positions.append(index)
    return positions


def count_between(positions: list[int], start: int, end: int) -> int:
    return sum(start < position < end for position in positions)


def score_log(
    log_text: str,
    sample_id: str,
    expected_defaults_suite: str,
) -> dict[str, Any]:
    lines = log_text.splitlines()
    defaults_suite_confirmed = expected_defaults_suite in debug_defaults_suites(log_text)
    ready_positions = [
        index
        for index, line in enumerate(lines)
        if f"MWX WEB DIAG record={sample_id} " in line and "type=host.ready " in line
    ]
    measurement_start = ready_positions[0] if ready_positions else len(lines)
    action_entries = [
        (match.group("action"), index)
        for index, line in enumerate(lines)
        if index > measurement_start and (match := ACTION_RE.search(line))
    ]
    actions = [action for action, _ in action_entries]
    action_positions = {action: index for action, index in action_entries}
    event_positions = {
        event_type: diagnostic_positions(lines, event_type, measurement_start)
        for event_type in EVENT_TYPES
    }
    event_counts = {
        event_type: len(positions) for event_type, positions in event_positions.items()
    }

    windows: dict[str, dict[str, int]] = {}
    timeline_valid = False
    if actions == EXPECTED_ACTIONS and len(ready_positions) == 2:
        default_position = action_positions["default-space"]
        workspace_position = action_positions["workspace-space"]
        screen_position = action_positions["screen-burst"]
        relaunch_position = action_positions["relaunch"]
        second_workspace_position = action_positions["workspace-space-after-relaunch"]
        stop_position = action_positions["stop"]
        post_stop_position = action_positions["post-stop-notifications"]
        completed_position = action_positions["completed"]
        window_bounds = {
            "default_space": (default_position, workspace_position),
            "workspace_space": (workspace_position, screen_position),
            "screen_burst": (screen_position, relaunch_position),
            "workspace_after_relaunch": (second_workspace_position, stop_position),
            "post_stop": (post_stop_position, completed_position),
        }
        windows = {
            name: {
                event_type: count_between(event_positions[event_type], start, end)
                for event_type in EVENT_TYPES
            }
            for name, (start, end) in window_bounds.items()
        }
        timeline_valid = (
            ready_positions[0] < default_position
            < workspace_position
            < screen_position
            < relaunch_position
            < ready_positions[1]
            < second_workspace_position
            < stop_position
            < post_stop_position
            < completed_position
        )

    scoped_stop_positions = diagnostic_positions(lines, "lifecycle.stop", measurement_start)
    stop_messages = []
    for index in scoped_stop_positions:
        match = DIAG_RE.search(lines[index])
        if match:
            stop_messages.append(match.group("message"))
    final_stop_message = stop_messages[-1] if stop_messages else None
    final_stop_zero = bool(
        final_stop_message
        and all(token in final_stop_message for token in FINAL_STOP_TOKENS)
    )
    released_count = len(
        diagnostic_positions(lines, "lifecycle.surface.released", measurement_start)
    )
    retained_count = len(
        diagnostic_positions(lines, "lifecycle.surface.retained", measurement_start)
    )

    failures: list[str] = []
    if not defaults_suite_confirmed:
        failures.append("debug UserDefaults isolation suite was not confirmed in app logs")
    if len(ready_positions) != 2:
        failures.append(
            f"host.ready appeared {len(ready_positions)} time(s), expected exactly 2"
        )
    if actions != EXPECTED_ACTIONS:
        failures.append(f"debug action order {actions} did not match {EXPECTED_ACTIONS}")
    if not timeline_valid:
        failures.append("host readiness and observer actions did not follow the expected timeline")
    for event_type, expected_count in EXPECTED_EVENT_COUNTS.items():
        if event_counts[event_type] != expected_count:
            failures.append(
                f"{event_type} appeared {event_counts[event_type]} time(s), "
                f"expected exactly {expected_count}"
            )

    if windows:
        if any(windows["default_space"].values()):
            failures.append("default NotificationCenter incorrectly reached a Web host observer")
        if (
            windows["workspace_space"]["lifecycle.space.observed"] != 1
            or windows["workspace_space"]["lifecycle.space.reasserted"] != 1
        ):
            failures.append("workspace notification did not produce exactly one Space callback")
        if (
            windows["screen_burst"]["lifecycle.screen.observed"] != 3
            or windows["screen_burst"]["lifecycle.screen.reconciled"] != 1
        ):
            failures.append("three screen notifications were not coalesced into one reconciliation")
        if (
            windows["workspace_after_relaunch"]["lifecycle.space.observed"] != 1
            or windows["workspace_after_relaunch"]["lifecycle.space.reasserted"] != 1
        ):
            failures.append("observer reinstall did not produce exactly one Space callback")
        if any(windows["post_stop"].values()):
            failures.append("a lifecycle observer callback ran after playback stopped")
    if len(scoped_stop_positions) != 1 or not final_stop_zero:
        failures.append("final lifecycle.stop did not report one idle zero-resource state")
    if released_count < 1:
        failures.append("no Web surface release was observed before completion")
    if retained_count:
        failures.append(f"{retained_count} Web surface(s) remained retained")

    return {
        "passed": not failures,
        "sample_id": sample_id,
        "debug_defaults_suite": expected_defaults_suite if defaults_suite_confirmed else None,
        "expected_actions": EXPECTED_ACTIONS,
        "observed_actions": actions,
        "host_ready_count": len(ready_positions),
        "timeline_valid": timeline_valid,
        "event_counts": event_counts,
        "window_counts": windows,
        "lifecycle_stop_count": len(scoped_stop_positions),
        "final_stop_message": final_stop_message,
        "final_stop_zero": final_stop_zero,
        "released_surface_count": released_count,
        "retained_surface_count": retained_count,
        "failures": failures,
    }


def make_output_dir(value: str | None) -> Path:
    output_dir = (
        Path(value).expanduser().resolve()
        if value
        else REPO_ROOT
        / f".codex/web-space-lifecycle-benchmark-{datetime.now():%Y%m%d-%H%M%S}"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def write_reports(output_dir: Path, report: dict[str, Any]) -> tuple[Path, Path]:
    json_path = output_dir / "report.json"
    markdown_path = output_dir / "report.md"
    json_path.write_text(
        json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8"
    )
    lines = [
        "# MyWallpaperX Web Space Lifecycle Benchmark",
        "",
        f"- Result: {'PASS' if report['passed'] else 'FAIL'}",
        f"- Sample: `{report['sample_id']}`",
        f"- UserDefaults suite: `{report['debug_defaults_suite'] or '-'}`",
        f"- Actions: {' -> '.join(report['observed_actions']) or '-'}",
        f"- Host ready: {report['host_ready_count']} (expected 2)",
        f"- Timeline valid: {report['timeline_valid']}",
        f"- Event counts: `{json.dumps(report['event_counts'], sort_keys=True)}`",
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
    if args.duration < MINIMUM_DURATION_SECONDS:
        print(
            f"--duration must be at least {MINIMUM_DURATION_SECONDS:.0f} seconds",
            file=sys.stderr,
        )
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
    defaults_suite = make_debug_defaults_suite()
    command = [
        str(app_binary),
        "--mwx-debug-user-defaults-suite",
        defaults_suite,
        "--mwx-debug-suppress-main-window",
        "--mwx-log-web-diagnostics",
        "--mwx-debug-web-space-lifecycle-sequence",
        args.id,
        "--mwx-debug-workshop-root",
        str(workshop_root),
    ]
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)

    started = time.monotonic()
    process: subprocess.Popen[Any] | None = None
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
                time.sleep(0.1)
        finally:
            if process is not None:
                exit_code = terminate_process(process)
            terminate_process(log_process)
            delete_debug_defaults_suite(defaults_suite, environment)

    report = score_log(
        log_path.read_text(encoding="utf-8", errors="replace"),
        args.id,
        defaults_suite,
    )
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
    print(f"Space lifecycle result: {'PASS' if report['passed'] else 'FAIL'}")
    return 0 if report["passed"] else 1


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify Web host Space routing, screen debounce, and observer cleanup."
    )
    parser.add_argument("--app", default=str(DEFAULT_APP_BINARY))
    parser.add_argument("--runtime-workshop-root")
    parser.add_argument("--runtime-home")
    parser.add_argument("--id", default="1509243786")
    parser.add_argument("--duration", type=float, default=23.0)
    parser.add_argument("--output-dir")
    parser.add_argument("--kill-existing", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    return run_benchmark(make_parser().parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
