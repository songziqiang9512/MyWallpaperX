#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/SceneParticleTrailRenderPlan.swift"
)

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let authored = SceneParticleTrailRenderPlan(
            length: 0.005,
            minimumLength: 1,
            maximumLength: 20
        )!
        let bounded = SceneParticleTrailRenderPlan(
            length: 1,
            minimumLength: 2,
            maximumLength: 4
        )!
        let largeAuthoredRange = SceneParticleTrailRenderPlan(
            length: 1,
            minimumLength: 300,
            maximumLength: 400
        )!
        let defaults = SceneParticleTrailRenderPlan(
            length: 1,
            minimumLength: nil,
            maximumLength: nil
        )!

        let invalidPlans: [SceneParticleTrailRenderPlan?] = [
            SceneParticleTrailRenderPlan(length: nil, minimumLength: nil, maximumLength: nil),
            SceneParticleTrailRenderPlan(length: .nan, minimumLength: nil, maximumLength: nil),
            SceneParticleTrailRenderPlan(length: .infinity, minimumLength: nil, maximumLength: nil),
            SceneParticleTrailRenderPlan(length: -1, minimumLength: nil, maximumLength: nil),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: .nan, maximumLength: 2),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: -.infinity, maximumLength: 2),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: -1, maximumLength: 2),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: 1, maximumLength: .nan),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: 1, maximumLength: .infinity),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: 1, maximumLength: -1),
            SceneParticleTrailRenderPlan(length: 1, minimumLength: 2, maximumLength: 1),
        ]
        let result: [String: Any] = [
            "authored": authored.stretch(for: SIMD3(1_350, 0, 0)),
            "minimum": bounded.stretch(for: SIMD3(0.5, 0, 0)),
            "maximum": bounded.stretch(for: SIMD3(5, 0, 0)),
            "threeDimensional": bounded.stretch(for: SIMD3(1, 2, 2)),
            "largeAuthoredMaximum": largeAuthoredRange.stretch(for: SIMD3(1_000, 0, 0)),
            "zeroSpeed": defaults.stretch(for: .zero),
            "nonFiniteSpeed": bounded.stretch(for: SIMD3(.nan, 0, 0)),
            "invalidCount": invalidPlans.compactMap { $0 }.count,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneParticleTrailRenderPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-particle-trail-plan-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-trail-plan"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                str(SOURCE), str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_authored_drop_velocity_produces_expected_stretch(self) -> None:
        self.assertAlmostEqual(self.result["authored"], 6.75)

    def test_authored_minimum_maximum_and_three_dimensional_speed_are_used(self) -> None:
        self.assertEqual(self.result["minimum"], 2)
        self.assertEqual(self.result["maximum"], 4)
        self.assertEqual(self.result["threeDimensional"], 3)

    def test_large_authored_range_zero_speed_and_non_finite_speed_are_safe(self) -> None:
        self.assertEqual(self.result["largeAuthoredMaximum"], 400)
        self.assertEqual(self.result["zeroSpeed"], 1)
        self.assertEqual(self.result["nonFiniteSpeed"], 2)

    def test_invalid_authored_values_fail_closed(self) -> None:
        self.assertEqual(self.result["invalidCount"], 0)


if __name__ == "__main__":
    unittest.main()
