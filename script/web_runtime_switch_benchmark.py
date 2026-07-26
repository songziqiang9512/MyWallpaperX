#!/usr/bin/env python3
"""Verify rapid Video -> Web -> Video ownership and resource cleanup."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import zipfile
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
    "preflight",
    "video1",
    "web",
    "video2",
    "inject-stale-failure",
    "crash-video2",
    "crash-video2-delayed",
    "stop",
    "completed",
]
EXPECTED_CHECKPOINTS = [
    "preflight",
    "video1-requested",
    "web-requested",
    "video2-requested",
    "stale-event-filtered",
    "video2-stable",
    "video2-recovered",
    "recovery-pending",
    "stopped",
    "post-stop",
]
BUNDLED_VIDEO_FILES = {f"Video{index}.mp4" for index in range(1, 6)}


def validate_bundled_video_archive(resources: Path) -> None:
    archive_path = resources / "Videos.zip"
    if not archive_path.is_file():
        raise ValueError(f"App bundle is missing {archive_path.name}")
    try:
        with zipfile.ZipFile(archive_path) as archive:
            names = set(archive.namelist())
            corrupt = archive.testzip()
    except (OSError, zipfile.BadZipFile) as error:
        raise ValueError(f"App bundled video archive is invalid: {error}") from error
    if names != BUNDLED_VIDEO_FILES:
        raise ValueError(f"App bundled video archive entries are invalid: {sorted(names)}")
    if corrupt is not None:
        raise ValueError(f"App bundled video archive is corrupt: {corrupt}")
SWITCH_ACTIONS = ["preflight", "video1", "web", "video2"]
OWNERSHIP_ACTIONS = [
    "inject-stale-failure",
    "crash-video2",
    "crash-video2-delayed",
]
CLEANUP_ACTIONS = ["stop", "completed"]
SWITCH_CHECKPOINTS = [
    "preflight",
    "video1-requested",
    "web-requested",
    "video2-requested",
    "video2-stable",
]
OWNERSHIP_CHECKPOINTS = [
    "stale-event-filtered",
    "video2-recovered",
    "recovery-pending",
]
CLEANUP_CHECKPOINTS = ["stopped", "post-stop"]
ACTION_RE = re.compile(
    r"MWX DEBUG RUNTIME SWITCH: action=(?P<action>[a-z0-9-]+) "
    r"elapsedMs=(?P<elapsed>\d+)"
)
CHECKPOINT_RE = re.compile(
    r"MWX DEBUG RUNTIME SWITCH: checkpoint=(?P<checkpoint>[a-z0-9-]+) "
    r"state=(?P<state>\{.*\})\s*$"
)
PRECONDITION_RE = re.compile(
    r"MWX DEBUG RUNTIME SWITCH: precondition=(?P<reason>\S+)"
)
FINAL_STOP_TOKENS = ("phase=idle", "surfaces=0", "loopbacks=0", "observers=0")
ZERO_WEB_FIELDS = (
    "currentRequest",
    "loopbacks",
    "monitors",
    "observers",
    "pointerTimer",
    "surfaces",
    "watchTimer",
    "watchers",
)
MINIMUM_DURATION_SECONDS = 14.0
MAX_SWITCH_INTERVAL_MILLISECONDS = 300


def parse_timeline(
    log_text: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    actions: list[dict[str, Any]] = []
    checkpoints: list[dict[str, Any]] = []
    errors: list[str] = []
    for line_number, line in enumerate(log_text.splitlines(), 1):
        if match := ACTION_RE.search(line):
            actions.append(
                {
                    "name": match.group("action"),
                    "elapsed_ms": int(match.group("elapsed")),
                    "line": line_number,
                }
            )
        if match := CHECKPOINT_RE.search(line):
            try:
                state = json.loads(match.group("state"))
            except json.JSONDecodeError as error:
                errors.append(f"checkpoint JSON on line {line_number} is invalid: {error}")
                continue
            if not isinstance(state, dict):
                errors.append(f"checkpoint JSON on line {line_number} is not an object")
                continue
            checkpoints.append(
                {
                    "name": match.group("checkpoint"),
                    "state": state,
                    "line": line_number,
                }
            )
    return actions, checkpoints, errors


def single_session(state: dict[str, Any]) -> dict[str, Any] | None:
    sessions = state.get("sessions")
    if not isinstance(sessions, list) or len(sessions) != 1:
        return None
    session = sessions[0]
    return session if isinstance(session, dict) else None


def web_state_is_zero(state: dict[str, Any]) -> bool:
    web = state.get("web")
    return bool(
        isinstance(web, dict)
        and web.get("phase") == "idle"
        and all(web.get(field) == 0 for field in ZERO_WEB_FIELDS)
    )


def validate_checkpoint_schema(
    name: str,
    state: dict[str, Any],
    failures: list[str],
) -> None:
    scalar_types = {
        "crashCount": int,
        "elapsedMs": int,
        "kind": str,
        "path": str,
        "playbackFailures": int,
        "playing": bool,
        "staleFailureInjected": bool,
        "staleHandlerCaptured": bool,
    }
    for field, expected_type in scalar_types.items():
        if type(state.get(field)) is not expected_type:
            failures.append(f"checkpoint {name} has invalid or missing {field}")

    for field in (
        "sessions",
        "recoveredAlive",
        "recoveredPids",
        "video1Alive",
        "video1Pids",
        "video2Alive",
        "video2Pids",
    ):
        value = state.get(field)
        if not isinstance(value, list):
            failures.append(f"checkpoint {name} has invalid or missing {field}")
            continue
        if field != "sessions" and any(type(item) is not int for item in value):
            failures.append(f"checkpoint {name} has non-integer {field} entries")

    sessions = state.get("sessions")
    if isinstance(sessions, list):
        for index, session in enumerate(sessions):
            if not isinstance(session, dict):
                failures.append(f"checkpoint {name} session {index} is not an object")
                continue
            for field in ("display", "pid", "requested"):
                value = session.get(field)
                if field == "requested" and value is None:
                    continue
                if type(value) is not int:
                    failures.append(
                        f"checkpoint {name} session {index} has invalid {field}"
                    )
            for field in ("accepted", "ready"):
                value = session.get(field)
                if value is not None and type(value) is not int:
                    failures.append(
                        f"checkpoint {name} session {index} has invalid {field}"
                    )
            for field in ("launched", "running"):
                if type(session.get(field)) is not bool:
                    failures.append(
                        f"checkpoint {name} session {index} has invalid {field}"
                    )

    web = state.get("web")
    if not isinstance(web, dict):
        failures.append(f"checkpoint {name} has invalid or missing web state")
        return
    if not isinstance(web.get("phase"), str):
        failures.append(f"checkpoint {name} has invalid or missing web phase")
    for field in ZERO_WEB_FIELDS:
        if type(web.get(field)) is not int:
            failures.append(f"checkpoint {name} has invalid or missing web.{field}")


def validate_video_state(
    state: dict[str, Any],
    expected_path: str,
    failures: list[str],
    label: str,
) -> dict[str, Any] | None:
    if state.get("kind") != "video" or state.get("path") != expected_path:
        failures.append(
            f"{label} state was {state.get('kind')}/{state.get('path')}, "
            f"expected video/{expected_path}"
        )
    session = single_session(state)
    if session is None:
        failures.append(f"{label} did not own exactly one daemon session")
        return None
    if not session.get("running") or not isinstance(session.get("pid"), int):
        failures.append(f"{label} daemon session was not running with a valid PID")
    if not isinstance(session.get("requested"), int):
        failures.append(f"{label} daemon session had no play request ID")
    return session


def score_log(
    log_text: str,
    sample_id: str,
    expected_defaults_suite: str,
) -> dict[str, Any]:
    lines = log_text.splitlines()
    actions, checkpoints, parse_errors = parse_timeline(log_text)
    action_names = [entry["name"] for entry in actions]
    checkpoint_names = [entry["name"] for entry in checkpoints]
    action_by_name = {entry["name"]: entry for entry in actions}
    checkpoint_by_name = {entry["name"]: entry for entry in checkpoints}
    states = {name: entry["state"] for name, entry in checkpoint_by_name.items()}
    switch_failures = list(parse_errors)
    ownership_failures: list[str] = []
    cleanup_failures: list[str] = []
    for name in SWITCH_CHECKPOINTS:
        state = states.get(name)
        if state is not None:
            validate_checkpoint_schema(name, state, switch_failures)
    for name in OWNERSHIP_CHECKPOINTS:
        state = states.get(name)
        if state is not None:
            validate_checkpoint_schema(name, state, ownership_failures)
    for name in CLEANUP_CHECKPOINTS:
        state = states.get(name)
        if state is not None:
            validate_checkpoint_schema(name, state, cleanup_failures)

    defaults_suite_confirmed = expected_defaults_suite in debug_defaults_suites(log_text)
    if not defaults_suite_confirmed:
        switch_failures.append("debug UserDefaults isolation suite was not confirmed in app logs")
    precondition_failures = [match.group("reason") for line in lines if (match := PRECONDITION_RE.search(line))]
    if precondition_failures:
        switch_failures.append(f"runner preconditions failed: {precondition_failures}")
    switch_action_names = [name for name in action_names if name in SWITCH_ACTIONS]
    ownership_action_names = [name for name in action_names if name in OWNERSHIP_ACTIONS]
    cleanup_action_names = [name for name in action_names if name in CLEANUP_ACTIONS]
    if switch_action_names != SWITCH_ACTIONS:
        switch_failures.append(
            f"switch action order {switch_action_names} did not match {SWITCH_ACTIONS}"
        )
    if ownership_action_names != OWNERSHIP_ACTIONS:
        ownership_failures.append(
            f"ownership action order {ownership_action_names} did not match {OWNERSHIP_ACTIONS}"
        )
    if cleanup_action_names != CLEANUP_ACTIONS:
        cleanup_failures.append(
            f"cleanup action order {cleanup_action_names} did not match {CLEANUP_ACTIONS}"
        )
    switch_checkpoint_names = [
        name for name in checkpoint_names if name in SWITCH_CHECKPOINTS
    ]
    ownership_checkpoint_names = [
        name for name in checkpoint_names if name in OWNERSHIP_CHECKPOINTS
    ]
    cleanup_checkpoint_names = [
        name for name in checkpoint_names if name in CLEANUP_CHECKPOINTS
    ]
    if switch_checkpoint_names != SWITCH_CHECKPOINTS:
        switch_failures.append(
            f"switch checkpoint order {switch_checkpoint_names} did not match {SWITCH_CHECKPOINTS}"
        )
    if ownership_checkpoint_names != OWNERSHIP_CHECKPOINTS:
        ownership_failures.append(
            f"ownership checkpoint order {ownership_checkpoint_names} did not match {OWNERSHIP_CHECKPOINTS}"
        )
    if cleanup_checkpoint_names != CLEANUP_CHECKPOINTS:
        cleanup_failures.append(
            f"cleanup checkpoint order {cleanup_checkpoint_names} did not match {CLEANUP_CHECKPOINTS}"
        )
    if action_names != EXPECTED_ACTIONS:
        ownership_failures.append(
            f"full action order {action_names} did not match {EXPECTED_ACTIONS}"
        )
    if checkpoint_names != EXPECTED_CHECKPOINTS:
        ownership_failures.append(
            f"full checkpoint order {checkpoint_names} did not match {EXPECTED_CHECKPOINTS}"
        )

    switch_interval: int | None = None
    if all(name in action_by_name for name in ("video1", "web", "video2")):
        video1_elapsed = action_by_name["video1"]["elapsed_ms"]
        web_elapsed = action_by_name["web"]["elapsed_ms"]
        video2_elapsed = action_by_name["video2"]["elapsed_ms"]
        switch_interval = video2_elapsed - video1_elapsed
        if not video1_elapsed <= web_elapsed <= video2_elapsed:
            switch_failures.append("runtime request timestamps were not monotonic")
        if switch_interval < 0 or switch_interval >= MAX_SWITCH_INTERVAL_MILLISECONDS:
            switch_failures.append(
                f"Video1 -> Video2 requests took {switch_interval}ms; "
                f"expected less than {MAX_SWITCH_INTERVAL_MILLISECONDS}ms"
            )
    else:
        switch_failures.append("runtime switch timing could not be measured")

    preflight = states.get("preflight")
    if preflight is not None and (
        preflight.get("kind") != "-"
        or preflight.get("sessions") != []
        or not web_state_is_zero(preflight)
    ):
        switch_failures.append("preflight did not start from an idle zero-resource state")

    video1 = states.get("video1-requested")
    video1_session = (
        validate_video_state(video1, "Video1.mp4", switch_failures, "Video1")
        if video1
        else None
    )
    if video1 is not None and video1_session:
        if video1.get("video1Pids") != [video1_session.get("pid")]:
            switch_failures.append("Video1 PID snapshot did not match its daemon session")

    web = states.get("web-requested")
    if web is not None:
        web_details = web.get("web") if isinstance(web.get("web"), dict) else {}
        if web.get("kind") != "web" or web.get("sessions") != []:
            switch_failures.append("Web request did not replace the Video1 engine/session state")
        if web_details.get("phase") not in ("launching", "ready"):
            switch_failures.append("Web host did not enter launching or ready phase")
        if web_details.get("surfaces") != 1 or web_details.get("currentRequest") != 1:
            switch_failures.append("Web request did not create exactly one owned surface")

    video2_requested = states.get("video2-requested")
    requested_session = (
        validate_video_state(
            video2_requested, "Video2.mp4", switch_failures, "Video2 requested"
        )
        if video2_requested
        else None
    )
    if video2_requested is not None and not web_state_is_zero(video2_requested):
        switch_failures.append("Web resources were not zero immediately after the Video2 request")

    stable = states.get("video2-stable")
    stable_session = (
        validate_video_state(stable, "Video2.mp4", switch_failures, "Video2 stable")
        if stable
        else None
    )
    if stable is not None:
        if stable.get("playing") is not True:
            switch_failures.append("Video2 was not playing at the stable checkpoint")
        if not web_state_is_zero(stable):
            switch_failures.append("Web resources were not zero at the Video2 stable checkpoint")
        if stable.get("video1Alive") != []:
            switch_failures.append("a Video1 daemon PID remained alive after Video2 became stable")
    if requested_session and stable_session:
        requested_pid = requested_session.get("pid")
        stable_pid = stable_session.get("pid")
        video1_pid = video1_session.get("pid") if video1_session else None
        if requested_pid != stable_pid:
            switch_failures.append("Video2 daemon PID changed before reaching stable playback")
        if requested_pid == video1_pid:
            switch_failures.append("Video2 reused the terminated Video1 daemon PID")
        request_id = stable_session.get("requested")
        if (
            not stable_session.get("launched")
            or not isinstance(request_id, int)
            or stable_session.get("accepted") != request_id
            or stable_session.get("ready") != request_id
        ):
            switch_failures.append("Video2 daemon did not launch, accept, and ready the latest request")
        if stable.get("video2Pids") != [stable_pid] or stable.get("video2Alive") != [stable_pid]:
            switch_failures.append("Video2 PID ownership snapshot was inconsistent at stable playback")

    stale_filtered = states.get("stale-event-filtered")
    if stale_filtered is not None:
        if stale_filtered.get("staleHandlerCaptured") is not True:
            ownership_failures.append("Video1 stale reader callback was not captured")
        if stale_filtered.get("staleFailureInjected") is not True:
            ownership_failures.append("stale Video1 failure event was not injected")
        if stale_filtered.get("playbackFailures") != 0:
            ownership_failures.append("stale Video1 output reached the current Video2 session")
        if (
            stale_filtered.get("kind") != "video"
            or stale_filtered.get("path") != "Video2.mp4"
            or not web_state_is_zero(stale_filtered)
        ):
            ownership_failures.append("stale reader check did not preserve Video2 ownership")

    recovered = states.get("video2-recovered")
    recovered_session = (
        validate_video_state(
            recovered, "Video2.mp4", ownership_failures, "Video2 recovered"
        )
        if recovered
        else None
    )
    if recovered is not None:
        if recovered.get("playbackFailures") != 0:
            ownership_failures.append("playback failure notification escaped during recovery")
        if recovered.get("video2Alive") != []:
            ownership_failures.append("terminated Video2 daemon remained alive after recovery")
        if not web_state_is_zero(recovered):
            ownership_failures.append("Web resources reappeared during Video2 recovery")
    if stable_session and recovered_session:
        stable_pid = stable_session.get("pid")
        recovered_pid = recovered_session.get("pid")
        if recovered_pid == stable_pid:
            ownership_failures.append("Video2 crash recovery did not create a new daemon PID")
        request_id = recovered_session.get("requested")
        if (
            not recovered_session.get("launched")
            or not isinstance(request_id, int)
            or recovered_session.get("accepted") != request_id
            or recovered_session.get("ready") != request_id
        ):
            ownership_failures.append(
                "recovered Video2 daemon did not launch, accept, and ready its request"
            )
        if (
            recovered.get("recoveredPids") != [recovered_pid]
            or recovered.get("recoveredAlive") != [recovered_pid]
        ):
            ownership_failures.append("recovered Video2 PID ownership snapshot was inconsistent")

    recovery_pending = states.get("recovery-pending")
    if recovery_pending is not None and (
        recovery_pending.get("kind") != "video"
        or recovery_pending.get("path") != "Video2.mp4"
        or recovery_pending.get("playing") is not False
        or recovery_pending.get("sessions") != []
        or recovery_pending.get("recoveredAlive") != []
        or recovery_pending.get("crashCount", 0) < 2
        or recovery_pending.get("playbackFailures") != 0
        or not web_state_is_zero(recovery_pending)
    ):
        ownership_failures.append(
            "nonzero-backoff recovery was not pending before the stop intent"
        )

    for checkpoint in ("stopped", "post-stop"):
        stopped = states.get(checkpoint)
        if stopped is not None and (
            stopped.get("kind") != "-"
            or stopped.get("path") != "-"
            or stopped.get("playing") is not False
            or stopped.get("sessions") != []
            or stopped.get("video1Alive") != []
            or stopped.get("video2Alive") != []
            or stopped.get("recoveredAlive") != []
            or stopped.get("playbackFailures") != 0
            or not web_state_is_zero(stopped)
        ):
            cleanup_failures.append(
                f"{checkpoint} did not release all engine, daemon, and Web resources"
            )

    diagnostic_entries: list[tuple[int, dict[str, str]]] = []
    for index, line in enumerate(lines, 1):
        if match := DIAG_RE.search(line):
            diagnostic_entries.append((index, match.groupdict()))
    web_line = action_by_name.get("web", {}).get("line", -1)
    video2_line = action_by_name.get("video2", {}).get("line", len(lines) + 1)
    stable_line = checkpoint_by_name.get("video2-stable", {}).get("line", len(lines) + 1)
    profile_entries = [
        entry for entry in diagnostic_entries
        if entry[1]["type"] == "runtime.profile" and web_line < entry[0] < video2_line
    ]
    stop_entries = [
        entry for entry in diagnostic_entries
        if entry[1]["type"] == "lifecycle.stop" and video2_line < entry[0] < stable_line
    ]
    release_entries = [
        entry for entry in diagnostic_entries
        if entry[1]["type"] == "lifecycle.surface.released"
        and video2_line < entry[0] < stable_line
    ]
    retained_entries = [
        entry for entry in diagnostic_entries
        if entry[1]["type"] == "lifecycle.surface.retained"
    ]
    ready_after_video2 = [
        entry for entry in diagnostic_entries
        if entry[1]["type"] == "host.ready" and entry[0] > video2_line
    ]
    origin_errors = [
        entry for entry in diagnostic_entries if entry[1]["type"] == "runtime.origin.error"
    ]
    loopback_starts = sum(
        entry[1]["type"] == "runtime.origin" and "httpLoopback" in entry[1]["message"]
        for entry in diagnostic_entries
    )
    loopback_stops = sum(
        entry[1]["type"] == "loopback.stopped" for entry in diagnostic_entries
    )
    if len(profile_entries) != 1:
        switch_failures.append("Web request did not emit exactly one runtime.profile before Video2")
    if len(stop_entries) != 1 or not all(
        token in stop_entries[0][1]["message"] for token in FINAL_STOP_TOKENS
    ):
        switch_failures.append("Video2 did not stop Web with one idle zero-resource lifecycle event")
    if not release_entries:
        switch_failures.append("the replaced Web surface was not released before Video2 stabilized")
    if retained_entries:
        switch_failures.append(f"{len(retained_entries)} Web surface(s) remained retained")
    if ready_after_video2:
        switch_failures.append("a stale Web host became ready after the Video2 request")
    if origin_errors:
        switch_failures.append("Web runtime origin setup failed during the switch sequence")
    if loopback_stops < loopback_starts:
        switch_failures.append(
            f"stopped {loopback_stops} loopback server(s), expected at least {loopback_starts}"
        )

    failures = switch_failures + ownership_failures + cleanup_failures
    return {
        "passed": not failures,
        "switch_passed": not switch_failures,
        "ownership_passed": not ownership_failures,
        "cleanup_passed": not cleanup_failures,
        "sample_id": sample_id,
        "debug_defaults_suite": expected_defaults_suite if defaults_suite_confirmed else None,
        "expected_actions": EXPECTED_ACTIONS,
        "observed_actions": action_names,
        "expected_checkpoints": EXPECTED_CHECKPOINTS,
        "observed_checkpoints": checkpoint_names,
        "switch_interval_ms": switch_interval,
        "video1_pids": video1.get("video1Pids", []) if video1 is not None else [],
        "video2_pids": stable.get("video2Pids", []) if stable is not None else [],
        "recovered_pids": recovered.get("recoveredPids", []) if recovered is not None else [],
        "lifecycle_stop_count": len(stop_entries),
        "released_surface_count": len(release_entries),
        "retained_surface_count": len(retained_entries),
        "loopback_start_count": loopback_starts,
        "loopback_stop_count": loopback_stops,
        "precondition_failures": precondition_failures,
        "switch_failures": switch_failures,
        "ownership_failures": ownership_failures,
        "cleanup_failures": cleanup_failures,
        "failures": failures,
    }


def apply_process_outcome(
    report: dict[str, Any],
    launch_error: str | None,
    process_survived_duration: bool,
) -> None:
    report["process_survived_duration"] = process_survived_duration
    failure: str | None = None
    if launch_error:
        failure = f"failed to launch app: {launch_error}"
    elif not process_survived_duration:
        failure = "app exited before the benchmark deadline"
    if failure is None:
        return
    report["switch_failures"].insert(0, failure)
    report["failures"].insert(0, failure)
    report["switch_passed"] = False
    report["passed"] = False


def make_output_dir(value: str | None) -> Path:
    output_dir = (
        Path(value).expanduser().resolve()
        if value
        else REPO_ROOT
        / f".codex/web-runtime-switch-benchmark-{datetime.now():%Y%m%d-%H%M%S}"
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
        "# MyWallpaperX Web Runtime Switch Benchmark",
        "",
        f"- Result: {'PASS' if report['scope_passed'] else 'FAIL'} (scope: {report['requested_scope']})",
        f"- Switch gate: {'PASS' if report['switch_passed'] else 'FAIL'}",
        f"- Ownership gate: {'PASS' if report['ownership_passed'] else 'FAIL'}",
        f"- Cleanup gate: {'PASS' if report['cleanup_passed'] else 'FAIL'}",
        f"- Sample: `{report['sample_id']}`",
        f"- UserDefaults suite: `{report['debug_defaults_suite'] or '-'}`",
        f"- Actions: {' -> '.join(report['observed_actions']) or '-'}",
        f"- Switch interval: {report['switch_interval_ms']} ms (<300 ms required)",
        f"- Video1/Video2 PIDs: {report['video1_pids']} / {report['video2_pids']}",
        f"- Recovered Video2 PIDs: {report['recovered_pids']}",
        f"- Web lifecycle stop: {report['lifecycle_stop_count']}",
        f"- Released/retained surfaces: {report['released_surface_count']}/{report['retained_surface_count']}",
        f"- Loopback start/stop: {report['loopback_start_count']}/{report['loopback_stop_count']}",
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
    resources = app_binary.parent.parent / "Resources"
    try:
        validate_bundled_video_archive(resources)
    except ValueError as error:
        print(f"Precondition failed: {error}", file=sys.stderr)
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
        "--mwx-debug-run-web-workshop-id",
        args.id,
        "--mwx-debug-web-runtime-switch-sequence",
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
    process_survived_duration = False
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
            process_survived_duration = bool(
                process is not None
                and process.poll() is None
                and time.monotonic() >= deadline
            )
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
            "schema_version": 2,
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
            "requested_scope": args.scope,
        }
    )
    apply_process_outcome(report, launch_error, process_survived_duration)
    report["scope_passed"] = (
        report["passed"] if args.scope == "full" else report["switch_passed"]
    )
    json_path, markdown_path = write_reports(output_dir, report)
    print(f"Report JSON: {json_path}")
    print(f"Report Markdown: {markdown_path}")
    print(
        f"Runtime switch result ({args.scope}): "
        f"{'PASS' if report['scope_passed'] else 'FAIL'}"
    )
    return 0 if report["scope_passed"] else 1


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify rapid Video -> Web -> Video ownership and cleanup."
    )
    parser.add_argument("--app", default=str(DEFAULT_APP_BINARY))
    parser.add_argument("--runtime-workshop-root")
    parser.add_argument("--runtime-home")
    parser.add_argument("--id", default="1509243786")
    parser.add_argument("--duration", type=float, default=14.0)
    parser.add_argument("--output-dir")
    parser.add_argument("--scope", choices=("full", "switch"), default="full")
    parser.add_argument("--kill-existing", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    return run_benchmark(make_parser().parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
