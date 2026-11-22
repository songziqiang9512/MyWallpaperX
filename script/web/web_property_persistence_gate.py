#!/usr/bin/env python3
"""Exercise Web file/directory overrides across switches, restarts, and reset."""
from __future__ import annotations

import argparse
import base64
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from web_system_state_benchmark import is_same_or_descendant, real_workshop_root, validate_runtime_paths
from web_wallpaper_benchmark import (
    APP_NAME,
    DEFAULT_APP_BINARY,
    REPO_ROOT,
    start_unified_log_capture,
    terminate_process,
)

A_ID = "1509243786"
B_ID = "923576681"
PREFIX = "MWX DEBUG WEB PROPERTY: "
DEBUG_SUITE_PREFIX = "com.songziqiang.MyWallpaperX.Debug.WebProperty."
REQUIRED_FIELDS = {
    "stage", "action", "fileRaw", "fileResolved", "fileSource", "filePayload",
    "directoryRaw", "directoryResolved", "directorySource", "directoryPayload",
    "fileBookmarkPresent", "directoryBookmarkPresent", "modeRaw", "modePayload",
}
EXPECTED_ACTIONS = {
    "set-switch": ["set", "returned-a", "completed"], "restore-clear": ["restored", "cleared", "completed"],
    "verify-cleared": ["verified-cleared", "completed"],
}
EXPECTED_READY = {
    "set-switch": [A_ID, B_ID, A_ID], "restore-clear": [A_ID],
    "verify-cleared": [A_ID],
}
DIAG_RE = re.compile(
    r"MWX WEB DIAG record=(?P<record>\S+) screen=(?P<screen>\S+) severity=(?P<severity>\S+) "
    r"type=(?P<type>\S+) "
    r"url=(?P<url>\S+) message=(?P<message>.*)$"
)
LIVE_RESOLUTION_RE = re.compile(rf"MWX WEB RUNTIME CACHE: live resource resolution record={A_ID}\b")
DEFAULTS_SUITE_RE = re.compile(r"MWX DEBUG DEFAULTS: suite=(?P<suite>\S+)")
EXIT_RECEIPT_FIELDS = (
    "stopProof", "stopResult", "stopTimedOut", "pidProbe", "parentPID",
    "capturedChildPIDs", "systemLiveChildPIDs", "adapterLiveChildPIDs",
    "activeRequestPresent", "pendingRequestPresent", "stopWaitSeconds",
)
def parse_contract_events(log_text: str) -> tuple[list[dict[str, Any]], list[str]]:
    events: list[dict[str, Any]] = []
    errors: list[str] = []
    for line_number, line in enumerate(log_text.splitlines(), 1):
        if PREFIX not in line:
            continue
        raw = line.split(PREFIX, 1)[1].strip()
        try:
            event = json.loads(raw)
        except json.JSONDecodeError as error:
            errors.append(f"line {line_number} has invalid property JSON: {error.msg}")
            continue
        if not isinstance(event, dict):
            errors.append(f"line {line_number} property payload is not an object")
            continue
        missing = sorted(REQUIRED_FIELDS - event.keys())
        if missing:
            errors.append(f"line {line_number} is missing fields: {', '.join(missing)}")
        event["_line"] = line_number
        events.append(event)
    return events, errors
def normalized_path(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return ""
    return str(Path(value).expanduser().resolve())
def require_state(event: dict[str, Any], bookmark: str, mode: str) -> list[str]:
    failures = []
    for field in ("fileBookmarkPresent", "directoryBookmarkPresent"):
        if event.get(field) != bookmark:
            failures.append(f"{event.get('action')}.{field} was not {bookmark}")
    for field in ("modeRaw", "modePayload"):
        if str(event.get(field)) not in {mode, f"{mode}.0"}:
            failures.append(f"{event.get('action')}.{field} was not {mode}")
    return failures
def require_paths(
    event: dict[str, Any], raw_file: Path, resolved_file: Path,
    raw_directory: Path, resolved_directory: Path,
) -> list[str]:
    failures: list[str] = []
    action = event.get("action", "unknown")
    expected = {
        "fileRaw": raw_file, "fileResolved": resolved_file, "filePayload": resolved_file,
        "directoryRaw": raw_directory, "directoryResolved": resolved_directory,
        "directoryPayload": resolved_directory,
    }
    for field, path in expected.items():
        if normalized_path(event.get(field)) != str(path.resolve()):
            failures.append(f"{action}.{field} did not match {path}")
    for field in ("fileSource", "directorySource"):
        if event.get(field) != "bookmarkedOverride":
            failures.append(f"{action}.{field} was {event.get(field)!r}, expected bookmarkedOverride")
    failures.extend(require_state(event, "true", "2"))
    return failures
def require_empty(event: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    for field in (
        "fileRaw", "fileResolved", "filePayload", "directoryRaw",
        "directoryResolved", "directoryPayload",
    ):
        if event.get(field) not in (None, ""):
            failures.append(f"{event.get('action')}.{field} was not empty")
    failures.extend(require_state(event, "false", "1"))
    return failures

def require_daemon_exit_receipt(event: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    missing = [field for field in EXIT_RECEIPT_FIELDS if field not in event]
    if missing:
        failures.append(f"completed exit receipt is missing fields: {', '.join(missing)}")
    expected = {
        "stopProof": "web-daemon-process-exit-v1", "stopResult": "exited",
        "stopTimedOut": "false", "pidProbe": "kill-zero-esrch-v1",
        "activeRequestPresent": "false", "pendingRequestPresent": "false",
    }
    for field, value in expected.items():
        if event.get(field) != value:
            failures.append(f"completed exit receipt {field} was not {value}")

    def pid_list(field: str) -> list[int] | None:
        raw = event.get(field)
        if not isinstance(raw, str):
            failures.append(f"completed exit receipt {field} is not a PID list")
            return None
        if not raw:
            return []
        parts = raw.split(",")
        if any(not re.fullmatch(r"[1-9][0-9]*", part) for part in parts) or len(set(parts)) != len(parts):
            failures.append(f"completed exit receipt {field} contains invalid PID identities")
            return None
        return [int(part) for part in parts]

    captured = pid_list("capturedChildPIDs")
    if not captured:
        failures.append("completed exit receipt contains no captured child PID proof")
    for field in ("systemLiveChildPIDs", "adapterLiveChildPIDs"):
        if pid_list(field):
            failures.append(f"completed exit receipt still has {field}")
    parent = event.get("parentPID")
    if not isinstance(parent, str) or not re.fullmatch(r"[1-9][0-9]*", parent):
        failures.append("completed exit receipt parentPID is invalid")
    elif captured and int(parent) in captured:
        failures.append("completed exit receipt captured the parent as a child")
    try:
        raw_elapsed = event.get("stopWaitSeconds", "")
        if not isinstance(raw_elapsed, str):
            raise ValueError
        elapsed = float(raw_elapsed)
        if not math.isfinite(elapsed) or elapsed < 0:
            raise ValueError
    except (TypeError, ValueError):
        failures.append("completed exit receipt stopWaitSeconds is invalid")
    return failures

def score_stage(log_text: str, stage: str, original_file: Path, original_directory: Path,
                moved_file: Path, moved_directory: Path, expected_suite: str) -> dict[str, Any]:
    lines = log_text.splitlines()
    events, failures = parse_contract_events(log_text)
    actions = [str(event.get("action", "")) for event in events]
    if actions != EXPECTED_ACTIONS[stage]:
        failures.append(f"action order {actions} did not match {EXPECTED_ACTIONS[stage]}")
    wrong_stages = [event.get("stage") for event in events if event.get("stage") != stage]
    if wrong_stages:
        failures.append(f"property events used unexpected stages: {wrong_stages}")
    observed_suites = [match.group("suite") for line in lines if (match := DEFAULTS_SUITE_RE.search(line))]
    suite_valid = bool(observed_suites) and set(observed_suites) == {expected_suite}
    suite_valid = suite_valid and expected_suite.startswith(DEBUG_SUITE_PREFIX)
    if not suite_valid:
        failures.append(f"defaults suites {observed_suites} did not match Debug suite {expected_suite}")

    diagnostics = []
    for index, line in enumerate(lines, 1):
        if match := DIAG_RE.search(line):
            diagnostics.append({**match.groupdict(), "line": index})
    ready_records = [event["record"] for event in diagnostics if event["type"] == "host.ready"]
    if ready_records != EXPECTED_READY[stage]:
        failures.append(f"host.ready sequence {ready_records} did not match {EXPECTED_READY[stage]}")
    live_resolution_lines = [index for index, line in enumerate(lines, 1) if LIVE_RESOLUTION_RE.search(line)]
    ready_lines = [event["line"] for event in diagnostics if event["type"] == "host.ready"]
    live_resolution_valid = stage != "restore-clear" or bool(
        live_resolution_lines and ready_lines and live_resolution_lines[0] < ready_lines[0]
    )
    if not live_resolution_valid:
        failures.append("live resource resolution was not observed before restored host.ready")
    by_action = {str(event.get("action")): event for event in events}
    if stage == "set-switch":
        for action in ("set", "returned-a"):
            if action in by_action:
                failures.extend(require_paths(
                    by_action[action], original_file, original_file,
                    original_directory, original_directory,
                ))
    elif stage == "restore-clear":
        if "restored" in by_action:
            failures.extend(require_paths(
                by_action["restored"], original_file, moved_file,
                original_directory, moved_directory,
            ))
        if "cleared" in by_action:
            failures.extend(require_empty(by_action["cleared"]))
    elif "verified-cleared" in by_action:
        failures.extend(require_empty(by_action["verified-cleared"]))

    completed = by_action.get("completed", {})
    exit_failures = require_daemon_exit_receipt(completed)
    failures.extend(exit_failures)
    completed_line = completed.get("_line", -1)
    preceding_lines = ready_lines + [event["_line"] for event in events if event.get("action") != "completed"]
    timeline_valid = bool(ready_lines and completed_line > 0 and all(line < completed_line for line in preceding_lines))
    if not timeline_valid:
        failures.append("completion was not logged after the required property states and host.ready sequence")
    return {
        "stage": stage, "passed": not failures,
        "expected_actions": EXPECTED_ACTIONS[stage], "observed_actions": actions,
        "expected_ready_records": EXPECTED_READY[stage], "ready_records": ready_records,
        "host_ready_count": len(ready_records), "defaults_suite": expected_suite,
        "defaults_suite_valid": suite_valid, "live_resolution_count": len(live_resolution_lines),
        "live_resolution_before_ready": live_resolution_valid,
        "daemon_exit_proven": not exit_failures,
        "daemon_exit_receipt": {field: completed.get(field) for field in EXIT_RECEIPT_FIELDS},
        "surface_release_measured": False,
        "timeline_valid": timeline_valid, "failures": failures,
    }

def runtime_cache_path(runtime_home: Path, sample_id: str = A_ID) -> Path:
    stem = base64.b64encode(sample_id.encode()).decode().replace("+", "-").replace("/", "_").rstrip("=")
    return runtime_home / "Library/Caches/MyWallpaperX/SteamWorkshop/WebRuntime" / f"{stem}-runtime.json"

def validate_sample_contract(project: Path) -> None:
    root = json.loads(project.read_text(encoding="utf-8-sig"))
    properties = root.get("general", {}).get("properties", {})
    expected_types = {"image": "file", "customdirectory": "directory", "wallpapermode": "combo"}
    for key, expected_type in expected_types.items():
        if properties.get(key, {}).get("type") != expected_type:
            raise ValueError(f"{A_ID} property {key} is not {expected_type}")
    options = properties["wallpapermode"].get("options", [])
    if not any(option.get("value") == 2 for option in options):
        raise ValueError(f"{A_ID} wallpapermode does not expose activation value 2")

def create_fixtures(sample_root: Path, fixture_root: Path) -> dict[str, Path]:
    candidates = sorted(
        path for path in sample_root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    )
    if len(candidates) < 3:
        raise ValueError(f"sample {A_ID} does not contain three image fixtures")
    fixture_root.mkdir(parents=True)
    original_file = fixture_root / f"selected-file{candidates[0].suffix.lower()}"
    original_directory = fixture_root / "selected-directory"
    original_directory.mkdir()
    shutil.copy2(candidates[0], original_file)
    for index, source in enumerate(candidates[1:3], 1):
        shutil.copy2(source, original_directory / f"image-{index}{source.suffix.lower()}")
    return {
        "original_file": original_file.resolve(),
        "original_directory": original_directory.resolve(),
        "moved_file": (fixture_root / f"restored-file{original_file.suffix}").resolve(),
        "moved_directory": (fixture_root / "restored-directory").resolve(),
    }

def run_stage(app: Path, workshop_root: Path, runtime_home: Path, output_dir: Path,
              stage: str, fixture_file: Path, fixture_directory: Path, timeout: float,
              paths: dict[str, Path], defaults_suite: str) -> dict[str, Any]:
    stage_dir = output_dir / stage
    stage_dir.mkdir(parents=True, exist_ok=True)
    log_path = stage_dir / "app.log"
    command = [
        str(app), "--mwx-debug-suppress-main-window", "--mwx-log-web-diagnostics",
        "--mwx-debug-run-web-workshop-id", A_ID,
        "--mwx-debug-web-property-persistence-stage", stage,
        "--mwx-debug-web-property-file", str(fixture_file),
        "--mwx-debug-web-property-directory", str(fixture_directory),
        "--mwx-debug-workshop-root", str(workshop_root),
        "--mwx-debug-user-defaults-suite", defaults_suite,
    ]
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)
    started = time.monotonic()
    exit_code: int | None = None
    timed_out = False
    launch_error: str | None = None
    with log_path.open("w", encoding="utf-8") as handle:
        log_process = start_unified_log_capture(handle)
        process: subprocess.Popen[Any] | None = None
        try:
            time.sleep(0.25)
            try:
                process = subprocess.Popen(
                    command, cwd=REPO_ROOT, stdout=handle, stderr=subprocess.STDOUT,
                    env=environment, start_new_session=True,
                )
                exit_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                if process is not None:
                    exit_code = terminate_process(process)
            except OSError as error:
                launch_error = str(error)
        finally:
            time.sleep(0.4)
            terminate_process(log_process)
    result = score_stage(log_path.read_text(encoding="utf-8", errors="replace"), stage,
                         paths["original_file"], paths["original_directory"],
                         paths["moved_file"], paths["moved_directory"], defaults_suite)
    if launch_error:
        result["failures"].insert(0, f"failed to launch app: {launch_error}")
    if timed_out:
        result["failures"].insert(0, f"app did not exit within {timeout:.1f}s")
    if exit_code != 0:
        result["failures"].append(f"app exit code was {exit_code}, expected 0")
    result.update({
        "passed": not result["failures"], "exit_code": exit_code,
        "timed_out": timed_out, "launch_error": launch_error,
        "duration_seconds": round(time.monotonic() - started, 2), "log_path": str(log_path),
    })
    return result

def write_report(output_dir: Path, report: dict[str, Any]) -> None:
    (output_dir / "report.json").write_text(
        json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# MyWallpaperX Web Property Persistence Gate", "",
        f"- Result: {'PASS' if report['passed'] else 'FAIL'}",
        f"- Stages: {len(report['stages'])}/3",
        f"- Resource override runtime cache absent: {report['override_cache_absent']}",
        "- Cleanup evidence: captured Web child PID exit and adapter request state; surface retention is not measured.",
    ]
    lines.extend(
        f"- {stage['stage']}: {'PASS' if stage['passed'] else 'FAIL'}; "
        f"ready={stage['host_ready_count']} daemon_exit_proven={stage['daemon_exit_proven']}"
        for stage in report["stages"]
    )
    if report["failures"]:
        lines.extend(["", "## Failures", "", *(f"- {item}" for item in report["failures"])])
    (output_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

def run_gate_with_suite(args: argparse.Namespace, defaults_suite: str) -> int:
    workshop_root = Path(args.runtime_workshop_root).expanduser().resolve()
    runtime_home = Path(args.runtime_home).expanduser().resolve()
    app = Path(args.app).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else (
        REPO_ROOT / f".codex/web-property-persistence-{datetime.now():%Y%m%d-%H%M%S}")
    try:
        if runtime_home.exists() and any(runtime_home.iterdir()):
            raise ValueError("runtime HOME must be empty for a deterministic persistence run")
        a_project = validate_runtime_paths(workshop_root, runtime_home, A_ID)
        validate_runtime_paths(workshop_root, runtime_home, B_ID)
        validate_sample_contract(a_project)
        if not app.is_file() or not os.access(app, os.X_OK):
            raise ValueError(f"App binary is missing or not executable: {app}")
        if args.timeout <= 0:
            raise ValueError("--timeout must be positive")
        fixture_root = output_dir / "fixtures"
        if fixture_root.exists():
            raise ValueError(f"fixture directory already exists: {fixture_root}")
        if is_same_or_descendant(fixture_root, workshop_root):
            raise ValueError("fixtures must be outside the runtime Workshop root")
        output_dir.mkdir(parents=True, exist_ok=True)
        paths = create_fixtures(workshop_root / "Web" / A_ID, fixture_root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Precondition failed: {error}", file=sys.stderr)
        return 2
    if args.kill_existing:
        subprocess.run(["/usr/bin/pkill", "-x", APP_NAME], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.25)
    cache_path = runtime_cache_path(runtime_home)
    stages: list[dict[str, Any]] = []
    failures: list[str] = []

    first = run_stage(app, workshop_root, runtime_home, output_dir, "set-switch",
                      paths["original_file"], paths["original_directory"], args.timeout, paths, defaults_suite)
    stages.append(first)
    override_cache_absent = not cache_path.exists()
    if not override_cache_absent:
        first["failures"].append(f"resource override wrote runtime execution cache: {cache_path}")
        first["passed"] = False
    if not first["passed"]:
        failures.extend(f"set-switch: {item}" for item in first["failures"])
    else:
        paths["original_file"].rename(paths["moved_file"])
        paths["original_directory"].rename(paths["moved_directory"])
        second = run_stage(app, workshop_root, runtime_home, output_dir, "restore-clear",
                           paths["moved_file"], paths["moved_directory"], args.timeout, paths, defaults_suite)
        stages.append(second)
        if not second["passed"]:
            failures.extend(f"restore-clear: {item}" for item in second["failures"])
        else:
            third = run_stage(app, workshop_root, runtime_home, output_dir, "verify-cleared",
                              paths["moved_file"], paths["moved_directory"], args.timeout, paths, defaults_suite)
            stages.append(third)
            if not third["passed"]:
                failures.extend(f"verify-cleared: {item}" for item in third["failures"])

    cache_exists_after_clear = cache_path.exists()
    if len(stages) == 3 and not cache_exists_after_clear:
        failures.append("baseline runtime execution cache was not restored after clear")
    report = {
        "schema_version": 2, "generated_at": datetime.now().isoformat(timespec="seconds"),
        "passed": len(stages) == 3 and not failures,
        "defaults_suite": defaults_suite,
        "app_binary": str(app), "runtime_workshop_root": str(workshop_root),
        "runtime_home": str(runtime_home), "fixture_paths": {key: str(value) for key, value in paths.items()},
        "runtime_cache_path": str(cache_path), "override_cache_absent": override_cache_absent,
        "cache_exists_after_clear": cache_exists_after_clear, "stages": stages, "failures": failures,
    }
    write_report(output_dir, report)
    print(f"Report JSON: {output_dir / 'report.json'}")
    print(f"Report Markdown: {output_dir / 'report.md'}")
    print(f"Web property persistence result: {'PASS' if report['passed'] else 'FAIL'}")
    return 0 if report["passed"] else 1

def run_gate(args: argparse.Namespace) -> int:
    defaults_suite = f"{DEBUG_SUITE_PREFIX}{os.getpid()}.{time.time_ns()}"
    try:
        return run_gate_with_suite(args, defaults_suite)
    finally:
        subprocess.run(["/usr/bin/defaults", "delete", defaults_suite], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Verify Web file/directory persistence in the real host.")
    parser.add_argument("--app", default=str(DEFAULT_APP_BINARY))
    parser.add_argument("--runtime-workshop-root", required=True)
    parser.add_argument("--runtime-home", required=True)
    parser.add_argument("--output-dir")
    parser.add_argument("--timeout", type=float, default=32.0)
    parser.add_argument("--kill-existing", action="store_true")
    return parser

if __name__ == "__main__":
    raise SystemExit(run_gate(make_parser().parse_args(sys.argv[1:])))
