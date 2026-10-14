#!/usr/bin/env python3
"""CPU-only regression for the real telemetry-owned stage timestamp diagnostic."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
DIAGNOSTICS = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics"
SOURCES = [
    DIAGNOSTICS / "SceneFramePerformanceTelemetry.swift",
    DIAGNOSTICS / "SceneGPUStageTimestampObservation.swift",
    ROOT / "script/tests/fixtures/SceneGPUStageTimestampChecks.swift",
]
EXPECTED_FACTS = {
    "valid-draw-stage", "clock-ratio-units", "render-sentinel-rejected",
    "reverse-rejected", "outside-calibration-rejected", "truncated-rejected",
    "unknown-draw-rejected", "clear-gap-explicit", "clear-not-zero-cost",
    "zero-not-sdk-sentinel", "zero-cannot-prove-no-draw", "vertex-only-explicit",
    "fragment-required-neighbor", "blit-stage", "no-calibration-span",
    "subtract-before-double", "submit-once", "completion-once",
    "cancel-no-submit-or-completion", "inflight-stale-not-qualified",
    "gpu-failure-not-qualified", "range-dense", "range-overflow-preserves-prefix",
    "range-exact-capacity", "range-invalid-count", "disabled-no-device-path",
}


def input_manifest() -> dict[str, str]:
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in SOURCES}


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is unavailable")
class SceneGPUStageTimestampTests(unittest.TestCase):
    def test_cpu_assessment_lifecycle_and_bounded_sample_ranges(self) -> None:
        before = input_manifest()
        environment = os.environ.copy()
        # The opt-in is process local. A caller's profiling configuration must
        # never make this CPU-only fixture select a Metal observation.
        environment.pop("MWX_SCENE_GPU_STAGE_TIMESTAMPS_OUTPUT", None)
        environment.pop("MWX_SCENE_GPU_STAGE_TIMESTAMPS_DELAY_SECONDS", None)
        with tempfile.TemporaryDirectory(prefix="mwx-gpu-stage-timestamps-") as temporary:
            directory = Path(temporary)
            environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
            binary = directory / "gpu-stage-timestamps"
            command = ["swiftc", "-swift-version", "5", "-DDEBUG", "-O",
                       *(str(path) for path in SOURCES),
                       "-framework", "Metal", "-framework", "QuartzCore", "-o", str(binary)]
            compiled = subprocess.run(command, cwd=ROOT, env=environment,
                                      capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(binary)], cwd=ROOT, env=environment,
                                       capture_output=True, text=True, timeout=10)
            after = input_manifest()
            proof = os.environ.get("MWX_SCENE_GPU_STAGE_TIMESTAMP_PROOF")
            if proof:
                destination = Path(proof)
                destination.mkdir(parents=True, exist_ok=True)
                (destination / "inputs.json").write_text(json.dumps({
                    "command": command, "before": before, "after": after,
                }, indent=2) + "\n")
                (destination / "compiler.log").write_text(compiled.stdout + compiled.stderr)
                (destination / "result.json").write_text(completed.stdout)
                (destination / "runtime.stderr.log").write_text(completed.stderr)
            self.assertEqual(before, after, "fixture input changed while focused gate ran")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
        self.assertEqual(set(result["facts"]), EXPECTED_FACTS)
        self.assertTrue(result["passed"], result)
        for name, passed in result["facts"].items():
            with self.subTest(fact=name):
                self.assertIs(passed, True)


if __name__ == "__main__":
    unittest.main()
