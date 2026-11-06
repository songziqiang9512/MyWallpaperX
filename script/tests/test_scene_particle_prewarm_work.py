#!/usr/bin/env python3
"""Actual prewarm work against the production Parser, Simulator and recorder."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_particle_simulator import SWIFT_SOURCES

FIXTURE = Path(__file__).parent / "fixtures/SceneParticlePrewarmWorkHarness.swift"


class SceneParticlePrewarmWorkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-prewarm-work-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        paths = [*SWIFT_SOURCES, FIXTURE, Path(__file__),
                 Path(__file__).with_name("test_scene_particle_simulator.py")]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        evidence = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        destination = Path(evidence) / "prewarm-work" if evidence else None
        if destination:
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "inputs-before.json").write_text(json.dumps(before, indent=2))
        binary = directory / "prewarm-work"
        compiled = subprocess.run(
            [swiftc, "-O", "-D", "DEBUG", "-module-cache-path", str(directory / "module-cache"),
             *map(str, SWIFT_SOURCES), str(FIXTURE), "-o", str(binary)],
            capture_output=True, timeout=180,
        )
        if destination:
            (destination / "compile.stdout").write_bytes(compiled.stdout)
            (destination / "compile.stderr").write_bytes(compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr.decode(errors="replace"))
        actual = subprocess.run([str(binary)], capture_output=True, timeout=90)
        after = {str(p): hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in before}
        if destination:
            (destination / "runtime.stdout").write_bytes(actual.stdout)
            (destination / "runtime.stderr").write_bytes(actual.stderr)
            (destination / "identity.json").write_text(json.dumps({
                "inputsBefore": before, "inputsAfter": after, "inputsStable": before == after,
                "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "returnCode": actual.returncode,
            }, indent=2))
        if before != after:
            raise RuntimeError("prewarm inputs changed during compilation/execution")
        if actual.returncode:
            raise RuntimeError(actual.stderr.decode(errors="replace"))
        cls.result = json.loads(actual.stdout)

    def assertReplay(self, row: dict) -> None:
        for fact in ("sameObservableState", "sameHistory", "nextStepObservableState", "nextStepEvents",
                     "nextStepHistory", "continuedHandoff", "drained"):
            self.assertTrue(row[fact], (fact, row))

    def test_sparse_capacity_and_renaming_complete_with_exact_live_handoff(self) -> None:
        rows = self.result["sparse"]["rows"]
        self.assertEqual([row["name"] for row in rows], ["ordinary", "renamed"])
        for row in rows:
            with self.subTest(name=row["name"]):
                self.assertReplay(row)
                self.assertEqual(row["time"], 60)
                self.assertEqual(row["completedSteps"], 1920)
                self.assertEqual(row["handoffCadences"], 2048)
                self.assertFalse(row["limited"], row)
                self.assertTrue(row["renamedEquivalent"], row)
                self.assertGreater(row["population"], 0)
                self.assertLess(row["population"], 64)
                self.assertEqual(row["historyCount"], 36)
                self.assertTrue(row["historyHasPopulation"])

    def test_instance_rate_scales_the_same_wall_step_sequence_once(self) -> None:
        row = self.result["sparse"]["scaledClock"]
        self.assertReplay(row)
        self.assertEqual(row["completedSteps"], 288)
        self.assertAlmostEqual(row["time"], 10.8, places=10)
        self.assertFalse(row["limited"], row)
        self.assertGreater(row["deaths"], 0)

    def test_dense_failed_birth_and_short_lived_work_keep_a_real_prefix(self) -> None:
        for name, row in self.result["workload"].items():
            with self.subTest(name=name):
                self.assertReplay(row)
                self.assertTrue(row["limited"], row)
                self.assertGreaterEqual(row["completedSteps"], 240)
                self.assertLess(row["time"], 60)
                self.assertGreater(row["nextID"], 0)
                if name == "dense":
                    self.assertEqual(row["population"], 20_000)
                elif name == "failed-initializer":
                    self.assertEqual(row["population"], 0)
                    self.assertEqual(row["acceptedBirths"], 0)
                    self.assertEqual(row["processedPopulation"], 0)
                else:
                    self.assertEqual(row["population"], 0)
                    self.assertGreater(row["processedPopulation"], 0)
                    self.assertEqual(row["acceptedBirths"], row["nextID"])
                    self.assertEqual(row["deaths"], row["nextID"])

    def test_boids_cost_has_a_real_populated_consumer(self) -> None:
        rows = self.result["populationWork"]
        for name in ("linear", "boids"):
            row = rows[name]
            self.assertReplay(row)
            self.assertTrue(row["limited"], row)
            self.assertEqual(row["population"], 64)
        self.assertTrue(rows["boids"]["boidsPlanPrepared"])
        self.assertLess(rows["boids"]["time"], rows["linear"]["time"])

    def test_empty_capacity_boids_dispatch_and_zero_rate_do_not_spend_live_work(self) -> None:
        rows = self.result["populationWork"]
        for name in ("capacity", "boids", "dispatch", "rate-zero"):
            row = rows["empty-" + name]
            with self.subTest(name=name):
                self.assertEqual(row["population"], 0)
                self.assertEqual(row["nextID"], 0)
                self.assertEqual(row["time"], 0 if name == "rate-zero" else 60)
                self.assertFalse(row["limited"], row)

    def test_child_root_step_bounds_and_partial_last_step_stay_distinct(self) -> None:
        row = self.result["bounds"]
        self.assertEqual(row["childTime"], 7.5)
        self.assertTrue(row["childLimited"])
        self.assertEqual(row["exactTime"], 112.5)
        self.assertFalse(row["exactLimited"])
        self.assertEqual(row["overTime"], 112.5)
        self.assertTrue(row["overLimited"])
        self.assertEqual(row["partialTime"], 8 + 1 / 128)
        self.assertEqual(row["partialAge"], 8 + 1 / 128)
        self.assertEqual(row["partialX"], 512.5)
        self.assertEqual(row["partialHistoryCount"], 8)
        self.assertFalse(row["partialLimited"])
        self.assertTrue(row["partialDrained"])

    def test_complete_mode_runs_dense_boids_and_beyond_the_bounded_ceiling(self) -> None:
        expected = {"dense": (1920, 60, 20_000, 0),
                    "boids": (1920, 60, 64, 8), "beyond3600": (4096, 128, 2, 8)}
        for name, (steps, duration, population, history) in expected.items():
            row = self.result["complete"][name]
            with self.subTest(name=name):
                self.assertReplay(row)
                self.assertEqual(row["completedSteps"], steps)
                self.assertEqual(row["time"], duration)
                self.assertEqual(row["population"], population)
                self.assertEqual(row["historyCount"], history)
                self.assertFalse(row["limited"])
                self.assertEqual(row["handoffCadences"], 8)
                if history:
                    self.assertTrue(row["historyHasPopulation"])

    def test_complete_mode_preserves_the_fractional_last_slice_and_history(self) -> None:
        row = self.result["complete"]["partial"]
        self.assertEqual(row["time"], 128 + 1 / 128)
        self.assertEqual(row["age"], 128 + 1 / 128)
        self.assertEqual(row["x"], 8192.5)
        self.assertTrue(row["samePlainLinearState"])
        self.assertTrue(row["samePlainHistory"])
        self.assertEqual(row["historyCount"], 8)
        self.assertFalse(row["limited"])
        self.assertTrue(row["drained"])

    def test_cancellation_stops_at_complete_steps_without_changing_live_handoff(self) -> None:
        expected = {"beforeStart": 0, "threeSteps": 3, "step240": 240,
                    "step241": 241, "bounded": 241}
        for name, steps in expected.items():
            row = self.result["cancellation"][name]
            with self.subTest(name=name):
                self.assertReplay(row)
                self.assertEqual(row["time"], steps / 32)
                self.assertEqual(row["cancellationChecks"], steps + 1)
                self.assertTrue(row["checksOnlyDuringWarmup"])
                self.assertTrue(row["cancelled"])
                self.assertTrue(row["limited"])

        row = self.result["cancellation"]["continues"]
        self.assertReplay(row)
        self.assertEqual(row["time"], 20)
        self.assertEqual(row["cancellationChecks"], 640)
        self.assertTrue(row["checksOnlyDuringWarmup"])
        self.assertFalse(row["cancelled"])
        self.assertFalse(row["limited"])


if __name__ == "__main__":
    unittest.main()
