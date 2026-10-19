#!/usr/bin/env python3
"""Sprite A2C shader/PSO readback; does not qualify official thresholds or Runtime admission."""
from __future__ import annotations

import unittest
from pathlib import Path

from script.tests.scene_particle_render_test_support import run_particle_harness
from script.tests.test_scene_particle_rendering import HARNESS_SOURCE, SWIFT_SOURCES


FIXTURE = Path(__file__).resolve().parent / "fixtures/SceneParticleCoverageRenderingHarness.swift"
COVERAGE_HARNESS = HARNESS_SOURCE.split("@main", 1)[0] + r'''
@main enum CoverageHarness {
    static func main() throws {
        let result = try SceneParticleCoverageRenderingHarness.run()
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneParticleCoverageRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = run_particle_harness(tuple([*SWIFT_SOURCES, FIXTURE]), COVERAGE_HARNESS)

    @staticmethod
    def pixels(row: dict[str, object]) -> list[list[int]]:
        values = row["actual"]
        return [values[index:index + 4] for index in range(0, len(values), 4)]

    def test_texture_and_particle_alpha_each_act_once_against_hardware_coverage(self) -> None:
        rows = self.result["coverage"]
        self.assertEqual(self.result["sampleCount"], 1)
        self.assertEqual(len(rows), 16, "Eight real Sprite alpha pairs with both depth attachment states")
        for row in rows:
            with self.subTest(texture=row["textureAlpha"], particle=row["particleAlpha"], depth=row["depth"]):
                self.assertTrue(row["encoded"], row)
                self.assertTrue(row["completed"], row)
                self.assertEqual(len(row["actual"]), 64 * 4)
                self.assertLessEqual(row["maximumByteError"], 1, row)

    def test_transparent_inputs_preserve_destination_and_opaque_inputs_preserve_rgb(self) -> None:
        for row in self.result["coverage"]:
            if row["textureAlpha"] == 0 or row["particleAlpha"] == 0:
                expected = [16, 24, 40, 102]
            elif row["textureAlpha"] == 255 and row["particleAlpha"] == 1:
                # (240,80,32) * particle RGB(.5,.75,1.25) * overbright1.2.
                expected = [144, 72, 48, 255]
            else:
                continue
            with self.subTest(texture=row["textureAlpha"], particle=row["particleAlpha"], depth=row["depth"]):
                for pixel in self.pixels(row):
                    self.assertEqual(pixel, expected)

    def test_covered_fragments_keep_straight_rgb_and_alpha_to_one(self) -> None:
        # Coverage decisions remain GPU-defined. Every stored pixel must be
        # untouched clear or full straight RGB, never alpha-attenuated RGB.
        allowed = ([16, 24, 40, 102], [144, 72, 48, 255])
        for row in self.result["coverage"]:
            with self.subTest(texture=row["textureAlpha"], particle=row["particleAlpha"], depth=row["depth"]):
                for pixel in self.pixels(row):
                    self.assertIn(pixel, allowed)

    def test_existing_translucent_and_additive_particles_keep_pma_output(self) -> None:
        rows = self.result["ordinary"]
        self.assertEqual(len(rows), 4)
        expected = {"translucent": [66, 43, 43, 162], "additive": [72, 52, 59, 162]}
        for row in rows:
            with self.subTest(mode=row["mode"], depth=row["depth"]):
                self.assertTrue(row["encoded"])
                self.assertTrue(row["completed"])
                self.assertLessEqual(row["maximumByteError"], 1, row)
                for pixel in self.pixels(row):
                    for actual, value in zip(pixel, expected[row["mode"]], strict=True):
                        self.assertAlmostEqual(actual, value, delta=1)

    def test_unrequested_coverage_pso_rejects_only_coverage_draw(self) -> None:
        rows = self.result["missing"]
        self.assertEqual(len(rows), 2)
        for row in rows:
            with self.subTest(depth=row["depth"]):
                self.assertTrue(row["unpreparedCoverageAttempted"])
                self.assertFalse(row["unpreparedCoverageEncoded"], row)
                self.assertTrue(row["encoded"], "Healthy PMA draw must still encode on the same encoder")
                self.assertTrue(row["completed"])
                self.assertLessEqual(row["maximumByteError"], 1, row)

    def test_shared_depth_attachment_does_not_change_no_depth_coverage(self) -> None:
        rows = self.result["coverage"]
        plain = {(row["textureAlpha"], row["particleAlpha"]): row for row in rows if not row["depth"]}
        shared = {(row["textureAlpha"], row["particleAlpha"]): row for row in rows if row["depth"]}
        self.assertEqual(len(plain), 8)
        self.assertEqual(plain.keys(), shared.keys())
        for key, row in plain.items():
            with self.subTest(alpha_pair=key):
                self.assertEqual(row["actual"], shared[key]["actual"])


if __name__ == "__main__":
    unittest.main()
