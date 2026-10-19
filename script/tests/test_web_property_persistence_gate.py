#!/usr/bin/env python3

import json
import subprocess
import tempfile
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from web_property_persistence_gate import (
    A_ID,
    B_ID,
    is_same_or_descendant,
    parse_contract_events,
    real_workshop_root,
    runtime_cache_path,
    score_stage,
)


ROOT = Path("/private/tmp/mwx-property-test")
OLD_FILE = ROOT / "selected.jpg"
NEW_FILE = ROOT / "restored.jpg"
OLD_DIRECTORY = ROOT / "selected-directory"
NEW_DIRECTORY = ROOT / "restored-directory"
SUITE = "com.songziqiang.MyWallpaperX.Debug.WebProperty.123.456"


def contract(stage: str, action: str, *, restored: bool = False, empty: bool = False,
             include_exit_proof: bool = True) -> str:
    if empty:
        file_raw = file_resolved = file_payload = ""
        directory_raw = directory_resolved = directory_payload = ""
        file_source = directory_source = "unresolved"
    else:
        file_raw = str(OLD_FILE)
        directory_raw = str(OLD_DIRECTORY)
        file_resolved = file_payload = str(NEW_FILE if restored else OLD_FILE)
        directory_resolved = directory_payload = str(NEW_DIRECTORY if restored else OLD_DIRECTORY)
        file_source = directory_source = "bookmarkedOverride"
    payload = {
        "stage": stage, "action": action,
        "fileRaw": file_raw, "fileResolved": file_resolved,
        "fileSource": file_source, "filePayload": file_payload,
        "directoryRaw": directory_raw, "directoryResolved": directory_resolved,
        "directorySource": directory_source, "directoryPayload": directory_payload,
        "fileBookmarkPresent": "false" if empty else "true",
        "directoryBookmarkPresent": "false" if empty else "true",
        "modeRaw": 1 if empty else 2, "modePayload": 1 if empty else 2,
    }
    if action == "completed" and include_exit_proof:
        payload.update({
            "stopProof": "web-daemon-process-exit-v1", "stopResult": "exited",
            "stopTimedOut": "false", "pidProbe": "kill-zero-esrch-v1", "parentPID": "30200",
            "capturedChildPIDs": "30201,30202", "systemLiveChildPIDs": "", "adapterLiveChildPIDs": "",
            "activeRequestPresent": "false", "pendingRequestPresent": "false", "stopWaitSeconds": "0.04",
        })
    return "MWX DEBUG WEB PROPERTY: " + json.dumps(payload)


def diag(record: str, kind: str, message: str = "ready") -> str:
    return (
        f"MWX WEB DIAG record={record} screen=1 severity=info "
        f"type={kind} url=- message={message}"
    )


def live_resolution() -> str:
    return f"MWX WEB RUNTIME CACHE: live resource resolution record={A_ID}"


def passing_stage(stage: str) -> str:
    defaults = f"MWX DEBUG DEFAULTS: suite={SUITE}"
    if stage == "set-switch":
        body = [
            contract(stage, "set"), diag(A_ID, "host.ready"),
            diag(B_ID, "host.ready"), diag(A_ID, "host.ready"),
            contract(stage, "returned-a"),
        ]
    elif stage == "restore-clear":
        body = [
            live_resolution(), diag(A_ID, "host.ready"),
            contract(stage, "restored", restored=True),
            contract(stage, "cleared", empty=True),
        ]
    else:
        body = [contract(stage, "verified-cleared", empty=True), diag(A_ID, "host.ready")]
    body.extend([
        contract(stage, "completed", empty=stage != "set-switch"),
    ])
    return "\n".join([defaults, *body])


def score(log_text: str, stage: str) -> dict:
    return score_stage(
        log_text, stage, OLD_FILE, OLD_DIRECTORY, NEW_FILE, NEW_DIRECTORY, SUITE
    )


class WebPropertyPersistenceGateTests(unittest.TestCase):
    def test_all_three_stage_fixtures_pass(self) -> None:
        for stage in ("set-switch", "restore-clear", "verify-cleared"):
            with self.subTest(stage=stage):
                result = score(passing_stage(stage), stage)
                self.assertTrue(result["passed"], result["failures"])
                self.assertTrue(result["daemon_exit_proven"])
                self.assertFalse(result["surface_release_measured"])
                self.assertNotIn("released_surface_count", result)

    def test_rejects_malformed_or_incomplete_contract_json(self) -> None:
        malformed = "MWX DEBUG WEB PROPERTY: {not-json}"
        events, errors = parse_contract_events(malformed)
        self.assertEqual(events, [])
        self.assertTrue(errors)
        incomplete = 'MWX DEBUG WEB PROPERTY: {"stage":"set-switch","action":"set"}'
        _, errors = parse_contract_events(incomplete)
        self.assertTrue(any("missing fields" in error for error in errors))

    def test_rejects_wrong_action_order(self) -> None:
        fixture = passing_stage("set-switch").replace(
            contract("set-switch", "set"), contract("set-switch", "returned-a"), 1
        )
        self.assertFalse(score(fixture, "set-switch")["passed"])

    def test_rejects_missing_or_wrong_host_ready_sequence(self) -> None:
        fixture = passing_stage("set-switch").replace(diag(B_ID, "host.ready"), "", 1)
        result = score(fixture, "set-switch")
        self.assertFalse(result["passed"])
        self.assertEqual(result["host_ready_count"], 2)
        wrong = passing_stage("set-switch").replace(
            diag(B_ID, "host.ready"), diag(A_ID, "host.ready"), 1
        )
        self.assertFalse(score(wrong, "set-switch")["passed"])

    def test_rejects_restore_that_does_not_follow_bookmark_move(self) -> None:
        fixture = passing_stage("restore-clear").replace(str(NEW_FILE), str(OLD_FILE))
        result = score(fixture, "restore-clear")
        self.assertFalse(result["passed"])
        self.assertTrue(any("restored.fileResolved" in item for item in result["failures"]))

    def test_rejects_restore_without_bookmarked_sources(self) -> None:
        fixture = passing_stage("restore-clear").replace("bookmarkedOverride", "absolutePath")
        result = score(fixture, "restore-clear")
        self.assertFalse(result["passed"])
        self.assertTrue(any("Source" in item for item in result["failures"]))

    def test_rejects_bookmark_or_mode_state_mismatch(self) -> None:
        restored = passing_stage("restore-clear").replace(
            '"fileBookmarkPresent": "true"', '"fileBookmarkPresent": "false"', 1
        )
        self.assertFalse(score(restored, "restore-clear")["passed"])
        cleared = passing_stage("verify-cleared").replace('"modePayload": 1', '"modePayload": 2', 1)
        self.assertFalse(score(cleared, "verify-cleared")["passed"])

    def test_rejects_missing_or_late_live_resolution(self) -> None:
        missing = passing_stage("restore-clear").replace(live_resolution() + "\n", "", 1)
        self.assertFalse(score(missing, "restore-clear")["passed"])
        late = passing_stage("restore-clear").replace(live_resolution() + "\n", "", 1)
        late = late.replace(
            diag(A_ID, "host.ready"), diag(A_ID, "host.ready") + "\n" + live_resolution(), 1
        )
        self.assertFalse(score(late, "restore-clear")["passed"])

    def test_rejects_missing_defaults_suite(self) -> None:
        fixture = passing_stage("set-switch").replace(f"MWX DEBUG DEFAULTS: suite={SUITE}\n", "", 1)
        result = score(fixture, "set-switch")
        self.assertFalse(result["passed"])
        self.assertFalse(result["defaults_suite_valid"])

    def test_rejects_clear_or_restart_that_revives_values(self) -> None:
        for stage, action in (
            ("restore-clear", "cleared"),
            ("verify-cleared", "verified-cleared"),
        ):
            with self.subTest(stage=stage):
                empty_event = contract(stage, action, empty=True)
                revived = contract(stage, action)
                result = score(passing_stage(stage).replace(empty_event, revived), stage)
                self.assertFalse(result["passed"])
                self.assertTrue(any("was not empty" in item for item in result["failures"]))

    def test_rejects_live_children_pending_active_timeout_and_untrusted_exit_probe(self) -> None:
        original = passing_stage("verify-cleared")
        for field, value in (
            ("systemLiveChildPIDs", "30201"), ("adapterLiveChildPIDs", "30202"),
            ("activeRequestPresent", "true"), ("pendingRequestPresent", "true"),
            ("stopTimedOut", "true"), ("stopResult", "timeout"),
            ("stopResult", "adapter-unavailable"), ("pidProbe", "kill-succeeded"),
            ("stopProof", "legacy-surface-count"), ("stopWaitSeconds", "nan"),
            ("stopWaitSeconds", False),
        ):
            with self.subTest(field=field, value=value):
                events, _ = parse_contract_events(original)
                previous = json.dumps(events[-1][field])
                fixture = original.replace(f'"{field}": {previous}', f'"{field}": {json.dumps(value)}', 1)
                result = score(fixture, "verify-cleared")
                self.assertFalse(result["passed"], result)
                self.assertFalse(result["daemon_exit_proven"])

    def test_rejects_missing_or_invalid_captured_pid_proof(self) -> None:
        for value in ("", "0", "-1", "30201,30201", "30200", "not-a-pid"):
            with self.subTest(value=value):
                fixture = passing_stage("verify-cleared").replace(
                    '"capturedChildPIDs": "30201,30202"', '"capturedChildPIDs": ' + json.dumps(value), 1)
                self.assertFalse(score(fixture, "verify-cleared")["passed"])
        current = contract("verify-cleared", "completed", empty=True)
        missing = contract("verify-cleared", "completed", empty=True, include_exit_proof=False)
        legacy_only = passing_stage("verify-cleared").replace(current, missing)
        legacy_only += "\n" + diag(A_ID, "lifecycle.stop", "phase=idle surfaces=0 loopbacks=0 observers=0")
        legacy_only += "\n" + diag(A_ID, "lifecycle.surface.released", "screen=1")
        result = score(legacy_only, "verify-cleared")
        self.assertFalse(result["passed"])
        self.assertFalse(result["daemon_exit_proven"])

    def test_rejects_early_completion_or_ready_after_exit_proof(self) -> None:
        completed = contract("verify-cleared", "completed", empty=True)
        early = passing_stage("verify-cleared").replace(completed, "", 1)
        early = completed + "\n" + early
        self.assertFalse(score(early, "verify-cleared")["passed"])
        late_ready = passing_stage("verify-cleared").replace(diag(A_ID, "host.ready"), "", 1)
        late_ready += "\n" + diag(A_ID, "host.ready")
        result = score(late_ready, "verify-cleared")
        self.assertFalse(result["passed"])
        self.assertFalse(result["timeline_valid"])

    def test_actual_debug_wait_requires_os_child_exit_and_empty_request_state(self) -> None:
        from script.tests.test_steam_library_interactions import method
        repository = Path(__file__).resolve().parents[2]
        source = (repository / "MyWallpaperX/App/Debug/DebugWebPropertyPersistenceRunner.swift").read_text()
        wait = method(source, "private static func stopAndWaitForWebExit(").replace("private static func", "static func", 1)
        harness = r'''
import Foundation
import Darwin
@MainActor final class WebDaemonHostAdapter {
    var liveProcessIdentifiers: [Int32] = []
    var activeRequest: Int?
    var hasPendingRequest = false
}
@MainActor final class WallpaperEngine {
    var stopAction: (() -> Void)?
    func stopPlayback() { stopAction?() }
}
@MainActor enum DebugWebPropertyPersistenceRunner {
    static var observedChildPIDs = Set<Int32>()
// ACTUAL WAIT
}
@main enum Harness {
    @MainActor static func main() async throws {
        let host = WebDaemonHostAdapter()
        let engine = WallpaperEngine()
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["0.15"]
        try child.run()
        host.liveProcessIdentifiers = [child.processIdentifier]; host.activeRequest = 1; host.hasPendingRequest = true
        engine.stopAction = { host.liveProcessIdentifiers = []; host.activeRequest = nil; host.hasPendingRequest = false }
        let exited = await DebugWebPropertyPersistenceRunner.stopAndWaitForWebExit(engine: engine, host: host, timeout: 2)
        precondition(exited["stopResult"] == "exited" && exited["systemLiveChildPIDs"] == "")
        precondition(Double(exited["stopWaitSeconds"]!)! >= 0.1, "logical clearing must not substitute for OS child exit")
        child.waitUntilExit()
        let live = Process(); live.executableURL = URL(fileURLWithPath: "/bin/sleep"); live.arguments = ["1"]
        try live.run()
        DebugWebPropertyPersistenceRunner.observedChildPIDs = [live.processIdentifier]
        let timeout = await DebugWebPropertyPersistenceRunner.stopAndWaitForWebExit(engine: engine, host: host, timeout: 0.03)
        precondition(timeout["stopResult"] == "timeout" && timeout["stopTimedOut"] == "true")
        precondition(timeout["systemLiveChildPIDs"] == String(live.processIdentifier), "live exact PID must remain in receipt")
        live.terminate(); live.waitUntilExit()
        engine.stopAction = nil
        host.hasPendingRequest = true
        let pending = await DebugWebPropertyPersistenceRunner.stopAndWaitForWebExit(engine: engine, host: host, timeout: 0.03)
        precondition(pending["stopResult"] == "timeout" && pending["pendingRequestPresent"] == "true")
        host.hasPendingRequest = false; host.activeRequest = 1
        let active = await DebugWebPropertyPersistenceRunner.stopAndWaitForWebExit(engine: engine, host: host, timeout: 0.03)
        precondition(active["stopResult"] == "timeout" && active["activeRequestPresent"] == "true")
        host.activeRequest = nil
        DebugWebPropertyPersistenceRunner.observedChildPIDs = []
        let noProof = await DebugWebPropertyPersistenceRunner.stopAndWaitForWebExit(engine: engine, host: host, timeout: 0.03)
        precondition(noProof["stopResult"] == "timeout" && noProof["capturedChildPIDs"] == "")
        print("web-property-exit-proof-pass")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-property-exit-proof-") as raw:
            directory = Path(raw)
            main = directory / "Harness.swift"
            main.write_text(harness.replace("// ACTUAL WAIT", wait))
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(main),
                "-module-cache-path", str(directory / "modules"), "-o", str(directory / "check")],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(directory / "check")], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("web-property-exit-proof-pass", run.stdout)

    def test_runtime_cache_path_uses_expected_record_stem(self) -> None:
        path = runtime_cache_path(Path("/tmp/home"))
        self.assertEqual(path.name, "MTUwOTI0Mzc4Ng-runtime.json")

    def test_identifies_real_workshop_descendants(self) -> None:
        root = real_workshop_root()
        self.assertTrue(is_same_or_descendant(root / "Web", root))
        self.assertFalse(is_same_or_descendant(root.parent / "isolated-workshop", root))


if __name__ == "__main__":
    unittest.main()
