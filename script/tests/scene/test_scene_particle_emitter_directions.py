#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.scene.test_scene_particle_simulator import SWIFT_SOURCES


HARNESS = (Path(__file__).resolve().parents[1] / "fixtures") / "SceneParticleEmitterDirectionsHarness.swift"


class SceneParticleEmitterDirectionsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-emitter-directions-")
        cls.addClassCleanup(cls.temporary.cleanup)
        binary = Path(cls.temporary.name) / "directions"
        compiled = subprocess.run(
            [swiftc, "-O", "-D", "DEBUG", *map(str, SWIFT_SOURCES), str(HARNESS), "-o", str(binary)],
            capture_output=True, text=True,
        )
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode:
            raise AssertionError(completed.stderr)
        cls.results = json.loads(completed.stdout)

    def test_finite_large_directions_and_renamed_inputs_preserve_real_births_rng_and_ids(self):
        rows = self.results["equivalents"]
        self.assertEqual(len(rows), 13)
        for row in rows:
            with self.subTest(name=row["name"]):
                self.assertEqual(row["actual"], row["reference"])
                first = row["actual"]["first"]
                self.assertEqual(first["ids"], list(map(str, range(8))))
                self.assertEqual(first["birthIDs"], first["ids"])
                self.assertEqual(first["nextID"], "8")
                self.assertEqual(first, row["actual"]["replayed"])
                self.assertGreater(row["actual"]["second"]["ages"][0], first["ages"][0])
                if "mask" in row:
                    for position in first["positions"]:
                        for axis in range(3):
                            if not row["mask"] & (1 << axis):
                                self.assertEqual(position[axis], 0)
                        radius = math.dist(position, (0, 0, 0))
                        if row["mask"]:
                            self.assertGreaterEqual(radius, 1 - 1e-6)
                            self.assertLessEqual(radius, 4 + 1e-6)
                        else:
                            self.assertEqual(radius, 0)

    def test_zero_radius_and_fixed_tiny_radius_keep_representable_float_positions(self):
        first = self.results["zeroRadius"]["first"]
        self.assertEqual(first["positions"], [[7, 8, 9]] * 8)
        tiny = next(row for row in self.results["equivalents"] if row["name"] == "tiny-fixed")
        self.assertEqual(tiny["actual"], tiny["reference"])
        for position in tiny["actual"]["first"]["positions"]:
            self.assertAlmostEqual(math.dist(position, (0, 0, 0)), 1, places=6)

    def test_radial_zero_and_subnormal_eighth_use_real_rng_and_do_not_collapse(self):
        self.assertEqual(self.results["rngProbes"], {"zero": 0, "eighth": 0.125})
        self.assertEqual(self.results["zeroDraw"]["first"]["positions"], [[1, 0, 0]])
        value = self.results["subnormal"]["first"]["positions"]
        self.assertEqual(len(value), 1)
        self.assertGreater(value[0][0], 0)
        self.assertAlmostEqual(value[0][0] / 6.175820573015582e-17, 1, places=6)
        self.assertEqual(value[0][1:], [0, 0])

    def test_original_active_axis_threshold_is_unchanged(self):
        rows = self.results["thresholds"]
        self.assertEqual(len(rows), 6)
        for row in rows:
            with self.subTest(name=row["name"]):
                positions = row["actual"]["first"]["positions"]
                self.assertEqual(len(positions), 8)
                if row["name"].endswith("above"):
                    self.assertTrue(any(position[0] != 0 for position in positions))
                else:
                    self.assertTrue(all(position[0] == 0 for position in positions))
                self.assertTrue(all(position[2] == 0 for position in positions))

    def test_malformed_directions_and_nonfinite_canonical_sphere_ranges_are_local_cold_rejections(self):
        expected = {"short", "malformed", "nan", "infinity", "bool",
                    "infinite-maximum", "infinite-minimum"}
        self.assertEqual({row["name"] for row in self.results["invalid"]}, expected)
        for row in self.results["invalid"]:
            with self.subTest(name=row["name"]):
                self.assertEqual(row["actual"], self.results["peerReference"])
                self.assertEqual(row["actual"]["first"]["positions"], [[7, 8, 9]])

    def test_finite_power_overflow_and_real_float_overflow_keep_rng_id_progression_and_peer(self):
        for name in ("finiteOverflow", "floatOverflow"):
            with self.subTest(name=name):
                actual = self.results[name]
                reference = self.results[name + "Reference"]
                for stage in ("first", "second", "replayed"):
                    a, b = actual[stage], reference[stage]
                    self.assertEqual(a["positions"], [[7, 8, 9]])
                    self.assertEqual(a["ids"], ["2"])
                    self.assertEqual(a["nextID"], "3")
                    self.assertEqual(a["random"], b["random"])
                    self.assertEqual(a["nextID"], b["nextID"])
                self.assertEqual(actual["first"], actual["replayed"])

    def test_explicit_candidates_commit_rollback_retry_and_exact_count_rejection(self):
        row = self.results["transaction"]
        self.assertTrue(row["accepted"])
        self.assertEqual(row["before"], row["afterPrepare"])
        self.assertEqual(row["candidate"], row["committed"])
        self.assertEqual(row["candidate"], row["retry"])
        self.assertEqual(row["rolledBack"], row["before"])
        self.assertEqual(row["candidate"]["ids"], ["0", "1"])
        self.assertEqual(row["candidate"]["nextID"], "2")
        self.assertEqual(row["candidate"]["revision"], "1")
        self.assertTrue(row["partialRejected"])
        self.assertEqual(row["afterRejected"], row["before"])
        rejected = self.results["overflowTransaction"]
        self.assertFalse(rejected["accepted"])
        self.assertEqual(rejected["before"], rejected["afterRejected"])

    def test_natural_world_sphere_measures_only_the_emitter_speed_in_world_space(self):
        births = self.results["speedBirths"]
        self.assertEqual(births["world"], [[2, 0, 0], [4, 8, 0]])
        self.assertEqual(births["local"], [[2, 0, 0], [12, 8, 0]])
        for name in ("controlPoint", "explicit"):
            self.assertEqual(births[name], [[2, 0, 0], [12, 0, 0]])
        self.assertEqual(births["worldMovement"], [[2, 0, 0], [4, 0, 0]])

        (x, y, _), (vx, vy, vz) = births["diagonalInward"]
        self.assertGreater(min(x, y), 0)
        self.assertLess(max(vx, vy), 0)
        self.assertAlmostEqual(x * vy, y * vx)
        self.assertAlmostEqual(math.hypot(3 * vx, 0.5 * vy, vz), 12)
        self.assertAlmostEqual(births["tinyWorld"][1][0] * 9.99999993922529e-9, 12)
        self.assertEqual(births["tinyLocal"][1], [0, 0, 0])


if __name__ == "__main__":
    unittest.main()
