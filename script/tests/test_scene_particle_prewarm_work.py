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
                     "nextStepHistory", "continuedHandoff", "retainedSnapshotUnchanged", "drained"):
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

    def test_failed_birth_and_short_lived_work_complete_and_drain(self) -> None:
        for name, row in self.result["workload"].items():
            with self.subTest(name=name):
                self.assertReplay(row)
                self.assertFalse(row["limited"], row)
                self.assertEqual(row["completedSteps"], 1920)
                self.assertEqual(row["time"], 60)
                self.assertGreater(row["nextID"], 0)
                if name == "failed-initializer":
                    self.assertEqual(row["population"], 0)
                    self.assertEqual(row["acceptedBirths"], 0)
                    self.assertEqual(row["processedPopulation"], 0)
                else:
                    self.assertEqual(row["population"], 0)
                    self.assertGreater(row["processedPopulation"], 0)
                    self.assertEqual(row["acceptedBirths"], row["nextID"])
                    self.assertEqual(row["deaths"], row["nextID"])

    def test_empty_capacity_and_zero_rate_keep_their_simulation_clock(self) -> None:
        rows = self.result["emptySystems"]
        for name in ("capacity", "boids", "dispatch", "rate-zero"):
            row = rows["empty-" + name]
            with self.subTest(name=name):
                self.assertEqual(row["population"], 0)
                self.assertEqual(row["nextID"], 0)
                self.assertEqual(row["time"], 0 if name == "rate-zero" else 60)
                self.assertFalse(row["limited"], row)

    def test_child_step_bound_and_complete_root_partial_step_stay_distinct(self) -> None:
        row = self.result["bounds"]
        self.assertEqual(row["childTime"], 7.5)
        self.assertTrue(row["childLimited"])
        self.assertEqual(row["exactTime"], 112.5)
        self.assertFalse(row["exactLimited"])
        self.assertEqual(row["overTime"], 112.5 + 1 / 32)
        self.assertFalse(row["overLimited"])
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
                    "step241": 241, "childCancelled": 3}
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

    def test_death_compaction_preserves_order_payload_and_retained_history(self) -> None:
        expected = {
            "none": ([], [0, 1, 2, 3, 4, 5, 6, 7]),
            "prefix": ([0, 1], [2, 3, 4, 5, 6, 7]),
            "interior": ([2, 5], [0, 1, 3, 4, 6, 7]),
            "mixed": ([0, 1, 4, 6], [2, 3, 5, 7]),
            "all": ([0, 1, 2, 3, 4, 5, 6, 7], []),
        }
        for name, (deaths, survivors) in expected.items():
            with self.subTest(name=name):
                row = self.result["orderedDeaths"][name]
                self.assertEqual(row["retainedIDs"], list(range(8)))
                self.assertEqual(row["retainedAges"], [3 / 32] * 8)
                self.assertEqual(row["deaths"], deaths)
                self.assertEqual(row["deathSizes"], [identity + 1 for identity in deaths])
                self.assertEqual(row["deathAges"], [4 / 32] * len(deaths))
                self.assertEqual(row["survivors"], survivors)
                self.assertEqual(row["cachedIDs"], survivors)
                self.assertEqual(row["historyIDs"], [survivors])

    def test_field_writer_baselines_preserve_birth_values_and_do_not_accumulate(self) -> None:
        # (size, color, alpha): alpha 0.1875 is one 0.5 alphaChange on the 0.375
        # birth value; movementOnly has no writer, so all three resets are skipped.
        expected = {"none": (7, [1, 0, 1], 0.1875), "size": (14, [1, 0, 1], 0.1875),
                    "oscillate": (21, [1, 0, 1], 0.1875),
                    "twoSizeWriters": (42, [1, 0, 1], 0.1875),
                    "color": (7, [0.5, 0, 0.75], 0.1875),
                    "combined": (42, [0.5, 0, 0.75], 0.1875),
                    "renamed": (42, [0.5, 0, 0.75], 0.1875),
                    "movementOnly": (7, [1, 0, 1], 0.375)}
        rows = self.result["fieldWriters"]["rows"]
        self.assertEqual(set(rows), set(expected))
        for name, (size, color, alpha) in expected.items():
            row = rows[name]
            with self.subTest(name=name):
                self.assertReplay(row)
                self.assertEqual(row["prewarm"]["age"], 1)
                self.assertEqual(row["live"]["age"], 1.25)
                for phase in ("prewarm", "live"):
                    state = row[phase]
                    self.assertEqual((state["size"], state["color"]), (size, color))
                    self.assertEqual((state["initialSize"], state["initialColor"]), (7, [1, 0, 1]))
                    self.assertEqual((state["alpha"], state["initialAlpha"]), (alpha, 0.375))

    def test_event_color_writer_resets_when_follow_payload_becomes_unusable(self) -> None:
        row = self.result["fieldWriters"]["event"]
        self.assertReplay(row)
        self.assertTrue(row["sameParticle"])
        self.assertEqual(row["prewarm"]["color"], [0.25, 0.5, 0.75])
        self.assertEqual(row["validLive"]["color"], [0.25, 0.5, 0.75])
        self.assertEqual(len(row["unavailableLive"]), 3)
        for state in row["unavailableLive"]:
            self.assertEqual(state["color"], [1, 0, 1])
        self.assertEqual(row["recoveredLive"]["color"], [0, 0.25, 1])
        for state in (row["prewarm"], row["validLive"], *row["unavailableLive"], row["recoveredLive"]):
            self.assertEqual((state["size"], state["initialSize"]), (7, 7))
            self.assertEqual(state["initialColor"], [1, 0, 1])
            self.assertEqual((state["alpha"], state["initialAlpha"]), (0.1875, 0.375))


if __name__ == "__main__":
    unittest.main()
