#!/usr/bin/env python3
"""Run product-selection C0/C1/W0 with a fixed signed App and isolated inputs.

C0 means an empty owned HOME, not a flushed OS or WebKit cache. C1 reuses
that HOME in a new App process. W0 requests the same content twice in one App.
Copy inputs once before invoking this tool; their absolute paths stay fixed.
With --baseline-app, each iteration runs both arms serially and reverses their
order on alternate iterations; each arm keeps its C0/C1/W0 group together.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import pwd
import signal
import shutil
import statistics
import subprocess
import sys
import time
import uuid

from web_benchmark_capture import (
    discard_staged_app, require_fresh_output_dir, stage_signed_app, verify_staged_app,
)
from web_debug_defaults import (
    debug_defaults_suites, delete_debug_defaults_suite, make_debug_defaults_suite,
)
from web_wallpaper_benchmark import terminate_process

STARTUP_BUNDLE_ID = "com.songziqiang.MyWallpaperX.Debug.Startup"
PRODUCTION_BUNDLE_ID = "com.songziqiang.MyWallpaperX"


def defaults_values(domain: str) -> dict | None:
    result = subprocess.run(["/usr/bin/defaults", "export", domain, "-"], capture_output=True)
    if result.returncode:
        if b"does not exist" in result.stderr + result.stdout:
            return None
        raise RuntimeError(f"could not inspect defaults domain {domain}")
    return plistlib.loads(result.stdout)


def reset_startup_defaults(domain: str) -> None:
    if domain != STARTUP_BUNDLE_ID:
        raise ValueError("refusing to reset anything except the dedicated startup test domain")
    if defaults_values(domain):
        subprocess.run(["/usr/bin/defaults", "delete", domain], check=True, capture_output=True)
    if defaults_values(domain):
        raise RuntimeError("dedicated startup defaults domain was not cleared")


def production_preferences_identity() -> dict:
    values = defaults_values(PRODUCTION_BUNDLE_ID)
    path = Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library/Preferences" / (PRODUCTION_BUNDLE_ID + ".plist")
    return {"semanticSHA256": hashlib.sha256(plistlib.dumps(values, sort_keys=True)).hexdigest()
            if values is not None else None,
            "fileSHA256": hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None}


def tree_identity(root: Path) -> dict:
    """Hash authored inputs, excluding the two established derived Scene files."""
    ignored = {".DS_Store", ".mywallpaperx-scene-interpretation.json",
               ".mywallpaperx-scene-preview-log.txt"}
    digest = hashlib.sha256()
    count = size = 0
    for path in sorted(root.rglob("*")):
        if path.name in ignored:
            continue
        if path.is_symlink():
            raise ValueError(f"isolated inputs must not contain symlinks: {path}")
        if not path.is_file():
            continue
        entry = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                entry.update(chunk)
                size += len(chunk)
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + entry.digest())
        count += 1
    return {"sha256": digest.hexdigest(), "files": count, "bytes": size}


def isolated_path(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    media = (Path(pwd.getpwuid(os.getuid()).pw_dir) / "Movies/MyWallpaperX").resolve()
    if resolved == media or resolved.is_relative_to(media) or media.is_relative_to(resolved):
        raise ValueError(f"path overlaps real user media: {resolved}")
    return resolved


def child_processes(parent: int) -> dict[int, str]:
    rows = subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid=,lstart=,command="], text=True)
    all_rows = {}
    for line in rows.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3:
            all_rows[int(parts[0])] = (int(parts[1]), parts[2])
    found = {}
    owners = {parent}
    while True:
        added = {pid: identity for pid, (ppid, identity) in all_rows.items()
                 if ppid in owners and pid not in owners}
        if not added:
            return found
        found.update(added)
        owners.update(added)


def living_owned_processes(known: dict[int, str]) -> dict[int, str]:
    living = {}
    for pid, identity in known.items():
        value = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart=,command="],
                               capture_output=True, text=True).stdout.strip()
        if value == identity:
            living[pid] = identity
    return living


def native_result_valid(native: object, engine: str, item_id: str, mode: str) -> bool:
    if not isinstance(native, dict) or native.get("passed") is not True:
        return False
    if engine == "web" and native.get("timingSchemaVersion") not in (2, 3):
        return False
    rows = native.get("rows")
    if not isinstance(rows, list) or len(rows) < (2 if mode == "sequence" else 1):
        return False
    ids = set()
    required = ["entryToPresentedMs", "entryToParentFinalizedMs"] if engine == "scene" else ["entryToCommitMs"]
    for row in rows:
        if (not isinstance(row, dict) or row.get("passed", True) is not True
                or row.get("recordID") != item_id or not row.get("requestID")
                or row["requestID"] in ids):
            return False
        ids.add(row["requestID"])
        for key in required:
            value = row.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or not 0 <= value < 300_000:
                return False
        if engine == "scene" and any(type(row.get(key)) is not int or row[key] <= 0
                                     for key in ("daemonPID", "daemonGeneration")):
            return False
    if engine == "scene" and mode == "sequence":
        if len({(row["daemonPID"], row["daemonGeneration"]) for row in rows}) != 1:
            return False
    return True


def input_paths_match(native: object, engine: str, sample: Path, workshop: Path) -> bool:
    if not isinstance(native, dict):
        return False
    if engine == "web":
        entry = Path(native.get("entryPath", "/missing-entry")).resolve()
        return (Path(native.get("recordRoot", "/missing-record")).resolve() == sample
                and Path(native.get("workshopRoot", "/missing-workshop")).resolve() == workshop
                and entry.is_relative_to(sample) and entry.is_file())
    return all(Path(row.get("rootPath", "/missing-root")).resolve() == sample
               for row in native.get("rows", []))


def home_paths_match(native: dict, engine: str, home: Path) -> bool:
    if engine == "web":
        return Path(native.get("foundationHome", "/missing-home")).resolve() == home
    return all(Path(row.get("homePath", "/missing-home")).resolve() == home
               and Path(row.get("cacheRootPath", "/missing-cache")).resolve().is_relative_to(home)
               for row in native.get("rows", []))


def stop_owned_children(known: dict[int, str]) -> dict[int, str]:
    for action in (signal.SIGTERM, signal.SIGKILL):
        for pid in living_owned_processes(known):
            try:
                os.kill(pid, action)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            remaining = living_owned_processes(known)
            if not remaining:
                return {}
            time.sleep(0.1)
    return living_owned_processes(known)


def finish_selection_process(process, children: dict[int, str]) -> dict:
    """Always attempt every owned-process cleanup step, including after interruption."""
    errors = []

    def attempt(operation, action, fallback):
        try:
            return action()
        except BaseException as error:
            errors.append({"operation": operation, "errorType": type(error).__name__})
            return fallback

    # Capture descendants before stopping the parent can reparent them.
    children.update(attempt("capture-owned-children", lambda: child_processes(process.pid), {}))
    exit_code = attempt("terminate-app", lambda: terminate_process(process), None)
    remaining = attempt("inspect-owned-children", lambda: living_owned_processes(children), dict(children))
    try:
        deadline = time.monotonic() + 5
        while remaining and time.monotonic() < deadline:
            time.sleep(0.1)
            remaining = living_owned_processes(remaining)
    except BaseException as error:
        errors.append({"operation": "await-owned-child-exit", "errorType": type(error).__name__})
    cleanup_remaining = attempt("stop-owned-children", lambda: stop_owned_children(remaining), dict(remaining))
    verified = False
    try:
        cleanup_remaining = living_owned_processes(children)
        verified = True
    except BaseException as error:
        errors.append({"operation": "verify-owned-child-exit", "errorType": type(error).__name__})
    parent_exit = attempt("verify-app-exit", process.poll, None)
    return {"exitCode": exit_code, "remainingOwnedChildren": remaining,
            "remainingAfterFailureCleanup": cleanup_remaining,
            "ownedProcessesExited": verified and not cleanup_remaining and parent_exit is not None,
            "errors": errors}


def attach_cleanup_diagnostic(error: BaseException, cleanup: dict) -> None:
    error.startup_cleanup = cleanup
    if cleanup["errors"] or not cleanup["ownedProcessesExited"]:
        note = "Startup process cleanup: " + json.dumps(cleanup, sort_keys=True)
        if hasattr(error, "add_note"):
            error.add_note(note)
        print(note, file=sys.stderr)


def run_selection(binary: Path, args, home: Path, suite: str, token: str, output: Path, mode: str) -> dict:
    output.mkdir()
    native_path = output / "native.json"
    command = [str(binary), "--mwx-debug-suppress-main-window",
               "--mwx-debug-workshop-root", str(args.workshop_root),
               "--mwx-debug-user-defaults-suite", suite,
               "--mwx-debug-startup-defaults-token", token,
               "--mwx-debug-startup-fps", str(args.fps)]
    if args.engine == "scene":
        command += ["--mwx-debug-scene-daemon-client", "--mwx-debug-scene-product-entry",
                    "--mwx-debug-scene-daemon-stable", "--mwx-debug-scene-root", str(args.sample_root),
                    "--mwx-debug-scene-startup-report", str(native_path),
                    "--mwx-debug-scene-startup-mode", mode,
                    "--mwx-debug-scene-result-dir", str(output),
                    "--mwx-debug-scene-performance-fps", str(args.fps)]
    else:
        command += ["--mwx-debug-web-startup-report", str(native_path), args.item_id,
                    "--mwx-debug-web-startup-mode", mode]
    removed_overrides = sorted(key for key in os.environ if key.startswith(("MWX_", "MYWALLPAPERX_")))
    environment = {key: value for key, value in os.environ.items() if key not in removed_overrides}
    environment.update(HOME=str(home), CFFIXED_USER_HOME=str(home))
    # Inherited route/cache/diagnostic overrides invalidate the declared policy.
    native = None
    failure = None
    children = {}
    with (output / "app.log").open("w") as log:
        process = subprocess.Popen(command, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        original_error = None
        try:
            started = time.monotonic()
            deadline = started + args.timeout
            while time.monotonic() < deadline:
                children.update(child_processes(process.pid))
                if process.poll() is not None:
                    break
                time.sleep(0.2)
            else:
                failure = "App failed to exit normally within the bounded window"
        except BaseException as error:
            original_error = error
            raise
        finally:
            cleanup = finish_selection_process(process, children)
            if original_error is not None:
                attach_cleanup_diagnostic(original_error, cleanup)
            elif cleanup["errors"]:
                error = RuntimeError("startup owned-process cleanup could not be verified cleanly")
                attach_cleanup_diagnostic(error, cleanup)
                raise error
        exit_code = cleanup["exitCode"]
    if native_path.is_file():
        try:
            native = json.loads(native_path.read_text())
        except (OSError, ValueError) as error:
            failure = f"invalid native report: {error}"
    remaining = cleanup["remainingOwnedChildren"]
    cleanup_remaining = cleanup["remainingAfterFailureCleanup"]
    suites = debug_defaults_suites((output / "app.log").read_text(errors="replace"))
    passed = (failure is None and exit_code == 0 and not remaining and cleanup["ownedProcessesExited"] and suite in suites
              and native_result_valid(native, args.engine, args.item_id, mode)
              and input_paths_match(native, args.engine, args.sample_root, args.workshop_root)
              and home_paths_match(native, args.engine, home)
              and native.get("standardDefaultsDomain") == STARTUP_BUNDLE_ID
              and native.get("standardDefaultsSentinelVerified") is True)
    return {"passed": passed, "failure": failure, "command": command, "appPID": process.pid,
            "exitCode": exit_code, "normalExit": failure is None and exit_code == 0,
            "debugDefaultsConfirmed": suite in suites, "remainingOwnedChildren": remaining,
            "remainingAfterFailureCleanup": cleanup_remaining,
            "ownedProcessesExited": cleanup["ownedProcessesExited"],
            "observedChildren": children, "home": str(home), "native": native,
            "removedInheritedOverrideNames": removed_overrides}


def summarize(runs: list[dict], engine: str) -> dict:
    field = "entryToPresentedMs" if engine == "scene" else "entryToCommitMs"
    result = {}
    for condition in ("C0", "C1", "W0"):
        values = []
        for run in runs:
            if run["condition"] != condition or not run["passed"]:
                continue
            rows = run["native"]["rows"]
            # W0 row zero establishes an active session; only later selections are warm.
            for row in rows[1:] if condition == "W0" else rows:
                value = row.get(field)
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    values.append(value)
        result[condition] = {"field": field, "count": len(values), "valuesMs": values,
                             "medianMs": statistics.median(values) if values else None,
                             "rangeMs": [min(values), max(values)] if values else None}
    return result


def summarize_paired(runs: list[dict], engine: str, iterations: int) -> dict:
    """Compare complete iteration/condition pairs; never grant performance acceptance."""
    result = {"complete": False, "iterations": iterations, "conditions": {},
              "observationUnit": "one App per iteration, arm and condition",
              "differenceConvention": "candidate - baseline; negative is faster",
              "percentConvention": "100 * (candidate - baseline) / baseline",
              "performanceAccepted": False}
    if engine not in ("scene", "web") or type(iterations) is not int or iterations < 1:
        return dict(result, reason="invalid engine or iteration count")
    if not isinstance(runs, list) or len(runs) != iterations * 6:
        return dict(result, reason="incomplete or extra paired records")
    observations = {}
    for run in runs:
        if not isinstance(run, dict):
            return dict(result, reason="invalid paired record")
        iteration, condition, arm = (run.get(key) for key in ("iteration", "condition", "arm"))
        if (type(iteration) is not int or not 0 <= iteration < iterations
                or condition not in ("C0", "C1", "W0") or arm not in ("baseline", "candidate")):
            return dict(result, reason="invalid iteration, condition or arm")
        key = (iteration, condition, arm)
        if key in observations or run.get("passed") is not True or run.get("qualified", True) is not True:
            return dict(result, reason="duplicate or unsuccessful paired record")
        try:
            rows = run["native"]["rows"]
            expected_count = (6 if engine == "web" else 1) if condition == "W0" else 1
            if not isinstance(rows, list) or len(rows) != expected_count + (condition == "W0"):
                return dict(result, reason="ambiguous original timing record")
            field = "entryToPresentedMs" if engine == "scene" else "entryToCommitMs"
            requests = [row.get("requestID") for row in rows]
            if (any(not isinstance(request, str) or not request for request in requests)
                    or len(set(requests)) != len(requests)
                    or any(row.get("failed") or row.get("passed") is False for row in rows)
                    or any(not isinstance(row.get(field), (int, float)) or isinstance(row[field], bool)
                           or not math.isfinite(row[field]) or row[field] < 0 for row in rows)):
                return dict(result, reason="invalid or duplicate original timing row")
            # Keep the original timing-field selection and W0 row-zero exclusion.
            values = summarize([run], engine)[condition]["valuesMs"]
        except (KeyError, TypeError, AttributeError):
            return dict(result, reason="invalid original timing record")
        if len(values) != expected_count:
            return dict(result, reason="incomplete within-App timing group")
        observations[key] = (statistics.median(values), values)
    conditions = {}
    for condition in ("C0", "C1", "W0"):
        pairs = []
        for iteration in range(iterations):
            baseline_group = observations.get((iteration, condition, "baseline"))
            candidate_group = observations.get((iteration, condition, "candidate"))
            if baseline_group is None or candidate_group is None:
                return dict(result, reason="missing iteration/condition partner")
            baseline, baseline_values = baseline_group
            candidate, candidate_values = candidate_group
            difference = candidate - baseline
            percent = difference / baseline * 100 if baseline else None
            if percent is not None and not math.isfinite(percent):
                percent = None
            pairs.append({"iteration": iteration, "baselineMs": baseline, "candidateMs": candidate,
                          "baselineValuesMs": baseline_values, "baselineCount": len(baseline_values),
                          "candidateValuesMs": candidate_values, "candidateCount": len(candidate_values),
                          "differenceMs": difference, "differencePercent": percent})
        differences = [pair["differenceMs"] for pair in pairs]
        percentages = [pair["differencePercent"] for pair in pairs]
        conditions[condition] = {"field": "entryToPresentedMs" if engine == "scene" else "entryToCommitMs",
                                 "withinAppAggregation": "median",
                                 "initialSelectionExcluded": condition == "W0",
                                 "count": iterations, "pairs": pairs,
                                 "medianDifferenceMs": statistics.median(differences),
                                 "medianDifferencePercent": statistics.median(percentages)
                                 if all(value is not None for value in percentages) else None}
    return dict(result, complete=True, conditions=conditions)


def run_arm_conditions(binary: Path, identity: dict, args, index: int, arm: str, runs: list) -> tuple[bool, bool]:
    """One arm owns its HOME and private suite across its contiguous C0/C1/W0."""
    paired = args.baseline_app is not None
    home_root = args.runtime_root / arm if paired else args.runtime_root
    output_root = args.output_dir / arm if paired else args.output_dir
    home_root.mkdir(exist_ok=True)
    output_root.mkdir(exist_ok=True)
    home = home_root / f"home-{index}"
    home.mkdir()
    suite = make_debug_defaults_suite()
    token = uuid.uuid4().hex
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    iteration_error = None
    owned_processes_exited = True
    failed = False
    try:
        reset_startup_defaults(identity["bundle_identifier"])
        subprocess.run(["/usr/bin/defaults", "write", STARTUP_BUNDLE_ID,
                        "MWXStartupDefaultsToken", "-string", token], check=True, capture_output=True)
        for condition in ("C0", "C1", "W0"):
            owned_processes_exited = False
            try:
                row = run_selection(binary, args, home, suite, token,
                                    output_root / f"{index}-{condition}",
                                    "sequence" if condition == "W0" else "single")
            except BaseException as error:
                owned_processes_exited = getattr(error, "startup_cleanup", {}).get("ownedProcessesExited", False)
                raise
            owned_processes_exited = row["ownedProcessesExited"]
            row.update(iteration=index, condition=condition, arm=arm)
            runs.append(row)
            if not row["passed"]:
                failed = True
                break
    except BaseException as error:
        iteration_error = error
        raise
    finally:
        if not owned_processes_exited:
            if iteration_error is not None:
                iteration_error.startup_defaults_retained = True
        else:
            cleanup_errors = []
            for operation, action in (
                ("delete-private-suite", lambda: delete_debug_defaults_suite(suite, environment)),
                ("reset-test-standard-domain", lambda: reset_startup_defaults(identity["bundle_identifier"])),
            ):
                try:
                    action()
                except BaseException as cleanup_error:
                    cleanup_errors.append((operation, cleanup_error))
            if cleanup_errors:
                diagnostic = [{"operation": operation, "errorType": type(error).__name__}
                              for operation, error in cleanup_errors]
                if iteration_error is not None:
                    iteration_error.startup_defaults_retained = True
                    iteration_error.startup_defaults_cleanup_errors = diagnostic
                    note = "Startup defaults cleanup errors: " + ", ".join(
                        f"{operation}={type(error).__name__}" for operation, error in cleanup_errors)
                    if hasattr(iteration_error, "add_note"):
                        iteration_error.add_note(note)
                    print(note, file=sys.stderr)
                else:
                    cleanup_errors[0][1].startup_defaults_retained = True
                    cleanup_errors[0][1].startup_defaults_cleanup_errors = diagnostic
                    raise cleanup_errors[0][1]
    return failed, not owned_processes_exited


def write_failure_diagnostic(args, identity, runs, production_before, error: BaseException, identities=None) -> None:
    """Report only fingerprints and error types; never replace the original exception."""
    diagnostic = {"schemaVersion": 1, "passed": False, "failureType": type(error).__name__,
                  "engine": args.engine, "label": args.label, "appIdentity": identity,
                  "runtimeRetained": args.runtime_root.exists(), "runs": runs,
                  "processCleanup": getattr(error, "startup_cleanup", None),
                  "testDefaultsRetained": getattr(error, "startup_defaults_retained", False),
                  "defaultsCleanupErrors": getattr(error, "startup_defaults_cleanup_errors", []),
                  "productionPreferencesBefore": production_before,
                  "productionPreferencesAfter": None, "productionPreferencesUnchanged": None}
    if args.baseline_app is not None:
        diagnostic["appIdentities"] = identities or {}
        diagnostic["currentArm"] = getattr(args, "current_arm", None)
    try:
        after = production_preferences_identity()
        diagnostic["productionPreferencesAfter"] = after
        if production_before is not None:
            diagnostic["productionPreferencesUnchanged"] = production_before == after
    except BaseException as inspection_error:
        diagnostic["productionPreferencesInspectionErrorType"] = type(inspection_error).__name__
    try:
        target = args.output_dir / "failure.json"
        target.write_text(json.dumps(diagnostic, ensure_ascii=False, indent=2) + "\n")
        print(f"Startup {args.label}: exception diagnostic — {target}", file=sys.stderr)
    except BaseException as diagnostic_error:
        print(f"Startup exception diagnostic failed ({type(diagnostic_error).__name__}); "
              f"failure environment retained at {args.runtime_root}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, metavar="EXECUTABLE",
                        help="Contents/MacOS/MyWallpaperX executable inside the fixed signed App")
    parser.add_argument("--baseline-app", type=Path, metavar="EXECUTABLE",
                        help="Direct predecessor executable for alternating same-input comparison")
    parser.add_argument("--engine", choices=("scene", "web"), required=True)
    parser.add_argument("--sample-root", type=Path, required=True)
    parser.add_argument("--workshop-root", type=Path, required=True)
    parser.add_argument("--item-id", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--fps", choices=(30, 60), type=int, default=30)
    parser.add_argument("--label", required=True)
    parser.add_argument("--keep-runtime", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.iterations <= 20 or not 1 <= args.timeout <= 300:
        parser.error("iterations must be 1...20 and timeout 1...300 seconds")
    for key in ("sample_root", "workshop_root", "runtime_root", "output_dir"):
        setattr(args, key, isolated_path(getattr(args, key)))
    protected = [args.sample_root, args.workshop_root]
    for writable in (args.runtime_root, args.output_dir):
        if any(writable == p or writable.is_relative_to(p) or p.is_relative_to(writable)
               for p in protected):
            parser.error("writable paths must be disjoint from input roots")
    if (args.runtime_root == args.output_dir or args.runtime_root.is_relative_to(args.output_dir)
            or args.output_dir.is_relative_to(args.runtime_root)):
        parser.error("output-dir and runtime-root must be disjoint")
    if not (args.sample_root / "project.json").is_file():
        parser.error("sample-root must be a complete isolated sample")
    if args.engine == "scene" and args.sample_root.name != args.item_id:
        parser.error("item-id must match the isolated sample directory name")
    require_fresh_output_dir(args.output_dir)
    require_fresh_output_dir(args.runtime_root)
    production_before = None
    identity = None
    arms = {}
    runs = []
    failed = False
    defaults_retained = False
    try:
        initial = tree_identity(args.sample_root)
        production_before = production_preferences_identity()
        sources = {"baseline": args.baseline_app, "candidate": args.app} if args.baseline_app else {"candidate": args.app}
        for arm, source in sources.items():
            args.current_arm = arm
            binary, identity = stage_signed_app(
                source, args.output_dir, runtime_bundle_name="MyWallpaperX.app")
            arms[arm] = (binary, identity)
            info = plistlib.loads((Path(identity["runtime_bundle_path"]) / "Contents/Info.plist").read_bytes())
            if identity["bundle_identifier"] != STARTUP_BUNDLE_ID or info.get("CFBundleIdentifier") != STARTUP_BUNDLE_ID:
                discard_staged_app(identity)
                raise ValueError("startup tests require the dedicated signed Debug.Startup bundle identity")
        identity = arms["candidate"][1]
        for index in range(args.iterations):
            order = list(arms) if index % 2 == 0 else list(reversed(arms))
            for arm in order:
                args.current_arm = arm
                arm_failed, retained = run_arm_conditions(*arms[arm], args, index, arm, runs)
                failed |= arm_failed
                defaults_retained |= retained
                if failed:
                    break
            if failed:
                break
        for arm, (_, staged_identity) in arms.items():
            args.current_arm = arm
            verify_staged_app(staged_identity)
        final = tree_identity(args.sample_root)
        production_after = production_preferences_identity()
        failed |= initial != final or production_before != production_after
        report = {"schemaVersion": 1, "passed": not failed, "label": args.label,
                  "toolSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  "engine": args.engine, "inputBefore": initial, "inputAfter": final,
                  "sampleRoot": str(args.sample_root), "appIdentity": identity,
                  "productionPreferencesBefore": production_before,
                  "productionPreferencesAfter": production_after,
                  "productionPreferencesUnchanged": production_before == production_after,
                  "testDefaultsRetained": defaults_retained,
                  "conditions": {"C0": "new App, fresh owned HOME and reset test standard domain; OS/WebKit coldness unknown",
                                 "C1": "new App, same HOME, sample root, standard domain and private suite",
                                 "W0": "same App sequence; only rows after the first are warm"},
                  "systemCacheState": "not purged; input hashing precedes launch; system WebKit state unknown",
                  "summary": summarize(runs, args.engine), "runs": runs}
        if args.baseline_app is not None:
            report["appIdentities"] = {arm: staged[1] for arm, staged in arms.items()}
            report["summary"] = {arm: summarize([run for run in runs if run["arm"] == arm], args.engine)
                                 for arm in arms}
            report["pairedSummary"] = summarize_paired(runs if not failed else [], args.engine, args.iterations)
        if not failed and not args.keep_runtime:
            for _, staged_identity in arms.values():
                discard_staged_app(staged_identity)
            shutil.rmtree(args.runtime_root)
        report["runtimeRetained"] = args.runtime_root.exists()
        target = args.output_dir / "report.json"
        target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"Startup {args.label}: {'FAILED' if failed else 'PASSED'} — {target}")
        return int(failed)
    except BaseException as error:
        # Keep the exact App/HOME on unexpected failures for diagnosis.
        try:
            write_failure_diagnostic(args, identity, runs, production_before, error,
                                     {arm: staged[1] for arm, staged in arms.items()})
        except BaseException as diagnostic_error:
            if hasattr(error, "add_note"):
                error.add_note(f"Startup failure diagnostic unavailable: {type(diagnostic_error).__name__}")
        raise


if __name__ == "__main__":
    raise SystemExit(main())
