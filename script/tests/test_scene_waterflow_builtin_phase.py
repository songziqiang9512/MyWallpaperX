#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneWaterFlowBuiltInPhaseTexture.swift"
)

HARNESS = r'''
import Metal

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(SceneWaterFlowBuiltInPhaseTexture.phaseValue(radius: 0) == 29, "center phase")
require(SceneWaterFlowBuiltInPhaseTexture.phaseValue(radius: 0.25) > 75, "inner rise")
require(SceneWaterFlowBuiltInPhaseTexture.phaseValue(radius: 0.60) > 190, "ring peak")
require(SceneWaterFlowBuiltInPhaseTexture.phaseValue(radius: 0.88) < 40, "outer falloff")
require(SceneWaterFlowBuiltInPhaseTexture.phaseValue(radius: 1) == 0, "edge phase")

if let device = MTLCreateSystemDefaultDevice() {
    let texture = SceneWaterFlowBuiltInPhaseTexture.make(
        path: "particle/normal_ring_smooth",
        device: device
    )
    require(texture?.pixelFormat == .r8Unorm, "pixel format")
    require(texture?.width == 64 && texture?.height == 64, "dimensions")
    require(
        SceneWaterFlowBuiltInPhaseTexture.make(path: "particle/unknown", device: device) == nil,
        "unknown built-in rejected"
    )
}

print("PASS")
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneWaterFlowBuiltInPhaseTests(unittest.TestCase):
    def test_radial_phase_contract(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-waterflow-phase-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            executable = root / "phase-test"
            harness.write_text(HARNESS, encoding="utf-8")
            subprocess.run(
                ["swiftc", str(SOURCE), str(harness), "-o", str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stdout.strip(), "PASS")


if __name__ == "__main__":
    unittest.main()
