#!/usr/bin/env python3
"""Native one-shot terminal material receipts; no GPU commands are submitted."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_resolved_material_runtime_bridge import (
    RESOURCE_PHASE_UNAVAILABLE_SUPPORT,
    SCENE_DEPENDENCY_BINDING_SUPPORT,
    SUBMISSION_COORDINATOR_FIXTURE,
    SUBMISSION_SWIFT_SOURCES,
)

MAIN = r"""
@main enum TerminalReceiptMain {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let payload: [String: Any] = [
            "metalAvailable": true,
            "results": SceneSubmissionTerminalReplayChecks.run(device: device, queue: queue),
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
"""

FIXTURE_INPUTS = [Path(__file__).with_name("fixtures") / name for name in (
    "SceneSubmissionCoordinatorDependencies.swift", "SceneSubmissionTerminalReplayChecks.swift",
    "SceneSubmissionScenarioInputs.swift", "SceneSubmissionAdmissionChecks.swift",
    "SceneSubmissionPublicationChecks.swift", "SceneSubmissionAtomicPreparationChecks.swift",
    "SceneSubmissionRuntimeBridgeChecks.swift", "SceneSubmissionLifecycleChecks.swift",
    "SceneSubmissionCoordinatorMain.swift",
)]


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneTerminalMaterialReceiptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-terminal-receipt-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        inputs = [*SUBMISSION_SWIFT_SOURCES, *FIXTURE_INPUTS, Path(__file__).resolve(),
                  Path(__file__).with_name("test_scene_resolved_material_runtime_bridge.py")]
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        harness = root / "Harness.swift"
        harness.write_text(SUBMISSION_COORDINATOR_FIXTURE.split("@main", 1)[0]
                          + SCENE_DEPENDENCY_BINDING_SUPPORT
                          + RESOURCE_PHASE_UNAVAILABLE_SUPPORT + MAIN)
        harness_sha = hashlib.sha256(harness.read_bytes()).hexdigest()
        binary = root / "receipt"
        compiled = subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            *map(str, SUBMISSION_SWIFT_SOURCES), str(harness), "-framework", "Metal",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
        ], capture_output=True, text=True)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        if before != after or hashlib.sha256(harness.read_bytes()).hexdigest() != harness_sha:
            raise AssertionError("source-modified-during-compilation")
        completed = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
        cls.payload = json.loads(completed.stdout)
        if not cls.payload["metalAvailable"]:
            raise unittest.SkipTest("Metal device unavailable")
        cls.results = cls.payload["results"]
        print("TERMINAL_RECEIPT_RESULTS " + json.dumps(cls.payload, sort_keys=True), flush=True)
        print("TERMINAL_RECEIPT_INPUT_SHA256 " + json.dumps(before, sort_keys=True), flush=True)
        print("TERMINAL_RECEIPT_HARNESS_SHA256 " + harness_sha, flush=True)

    def test_success_and_inactive_keep_distinct_output_contracts(self) -> None:
        for key in ("terminalReceiptConsumesOnceWithoutTextureSampling",
                    "opaqueTerminalReceiptConsumesOnce",
                    "straightTerminalReceiptConsumesOnce",
                    "absentReplayLeavesTicketForOrdinaryTextureComposite",
                    "absentReplayAllowsOrdinaryTextureReceipt"):
            with self.subTest(key=key):
                self.assertTrue(self.results[key])

    def test_ticket_and_claim_are_one_shot_and_epoch_bound(self) -> None:
        for key in ("repeatedTerminalReceiptRejectsWithoutSecondDraw",
                    "staleTerminalTicketRejectsBeforeDraw", "ticketCannotHidePreparedReplay",
                    "unconsumedClaimRejectsBeforeDraw"):
            with self.subTest(key=key):
                self.assertTrue(self.results[key])

    def test_foreign_targets_and_append_failure_never_confirm_output(self) -> None:
        for key in ("foreignCommandBufferRejectsBeforeDraw", "foreignMainTargetRejectsWithoutReceipt",
                    "terminalAppendFailureDropsFrameWithoutFallbackReceipt", "unadmittedReplayRejectsBeforeDraw"):
            with self.subTest(key=key):
                self.assertTrue(self.results[key])

    def test_replay_cannot_claim_texture_sampling_or_named_publication(self) -> None:
        self.assertTrue(self.results["terminalReplayCannotClaimLegacyTextureOrNamedReceipt"])

    def test_data_output_never_appends_terminal_draw(self) -> None:
        self.assertTrue(self.results["dataOutputRejectsBeforeDraw"])


if __name__ == "__main__":
    unittest.main()
