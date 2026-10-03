"""Compile the real extracted submission stage and exercise its lifetime boundary."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FRAME = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame"
STAGE = FRAME / "SceneMetalRenderer+Submission.swift"
FIXTURE = ROOT / "script/tests/fixtures/SceneRendererSubmissionStageHarness.swift"


class SceneRendererSubmissionStageTests(unittest.TestCase):
    def run_stage(self, mutation: tuple[str, str] | None = None):
        with tempfile.TemporaryDirectory(prefix="mwx-renderer-submission-") as directory:
            scratch = Path(directory)
            stage = STAGE
            if mutation:
                source = STAGE.read_text()
                old, new = mutation
                # Source matching only locates fault injection. The oracle is
                # the event sequence from executing the same product stage.
                self.assertEqual(source.count(old), 1)
                stage = scratch / STAGE.name
                stage.write_text(source.replace(old, new, 1))
            binary = scratch / "harness"
            built = subprocess.run([
                "xcrun", "swiftc", "-parse-as-library", str(stage),
                str(FRAME / "SceneMetalRenderer+FrameOutcome.swift"),
                str(FRAME / "SceneSourceUpdateTransaction.swift"), str(FIXTURE),
                "-module-cache-path", str(scratch / "cache"), "-o", str(binary),
            ], capture_output=True, text=True, timeout=90)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            return json.loads(run.stdout)

    def test_submission_cancellation_and_completion(self):
        for name, passed in self.run_stage().items():
            with self.subTest(name=name):
                self.assertTrue(passed)

    def test_cancellation_omission_is_detected(self):
        results = self.run_stage(("            compositionGroupRuntime?.cancel()\n", ""))
        self.assertFalse(results["cancellationOrderAndExactlyOnce"])
        self.assertFalse(results["deinitCancelsUnsubmittedResources"])
        self.assertTrue(results["submissionOrder"])

    def test_commit_before_resource_arm_is_detected(self):
        results = self.run_stage((
            "            mainPassForSubmission?.armCompositionPins()\n            commandBuffer.commit()",
            "            commandBuffer.commit()\n            mainPassForSubmission?.armCompositionPins()",
        ))
        self.assertFalse(results["submissionOrder"])
        self.assertTrue(results["cancellationOrderAndExactlyOnce"])


if __name__ == "__main__":
    unittest.main()
