"""Authored linked effect targets reach one real clock and typed snapshots."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from . import test_scene_timeline_runtime as timeline_gate
from .fixtures.scene_timeline_combined_cases import effect_linked_cases, non_effect_no_lane_cases


FIXTURE = Path(__file__).with_name("fixtures") / "SceneEffectTimelineGroupsHarness.swift"


class SceneEffectTimelineGroupsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-effect-timeline-groups-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        declarations, boundary, _ = timeline_gate.HARNESS_SOURCE.partition("@main")
        if not boundary:
            raise RuntimeError("existing passive Timeline harness boundary missing")
        support = root / "PassiveSceneDeclarations.swift"
        support.write_text(declarations)
        binary = root / "groups"
        compiled = subprocess.run(["swiftc", "-module-cache-path", str(root / "cache"),
            *map(str, dict.fromkeys(timeline_gate.SWIFT_SOURCES)), str(support), str(FIXTURE),
            "-o", str(binary)], capture_output=True, text=True, timeout=180)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        cls.results = {}
        for name, (scene, expected) in effect_linked_cases().items():
            path = root / f"{name}.json"
            path.write_text(json.dumps(scene, allow_nan=False))
            observed = subprocess.run([str(binary), str(path)], capture_output=True, text=True, timeout=20)
            if observed.returncode:
                raise RuntimeError(f"{name}: {observed.stderr}")
            cls.results[name] = expected, json.loads(observed.stdout)
        cls.host_results = {}
        for name, (scene, expected) in non_effect_no_lane_cases().items():
            path = root / f"host-{name}.json"
            path.write_text(json.dumps(scene, allow_nan=False))
            observed = subprocess.run([str(binary), str(path), "host-boundary"],
                                      capture_output=True, text=True, timeout=20)
            if observed.returncode:
                raise RuntimeError(f"{name}: {observed.stderr}")
            cls.host_results[name] = expected, json.loads(observed.stdout)

    def assert_values(self, actual, expected):
        for target, value in expected.items():
            self.assertIn(target, actual)
            self.assertAlmostEqual(actual[target], value, places=11, msg=target)

    def test_complete_targets_keep_scope_clock_fallbacks_and_names(self):
        for name, (expected, observed) in self.results.items():
            if not expected["accepted"]:
                continue
            with self.subTest(case=name):
                targets = expected["targets"]
                self.assertEqual(observed["groupTargets"], targets)
                self.assertEqual(observed["effectTargets"], sorted(targets + (
                    [expected["independentE0"]] if expected["independentE0"] else [])))
                bindings = {row["target"]: row for row in observed["bindings"]}
                self.assertEqual(len(bindings), len(observed["bindings"]))
                self.assertEqual(len(bindings), len(targets) + 3 + bool(expected["independentE0"]))
                group = [bindings[target] for target in targets]
                owners = {row["owner"] for row in group}
                self.assertEqual(len(owners), 1)
                self.assertIn(next(iter(owners)), [target for target in targets
                    if target.endswith(":" + expected["rootKey"])])
                self.assertEqual(sorted(row["name"] for row in group if row["name"]), sorted(expected["names"]))
                for row in group:
                    self.assertEqual((row["fps"], row["length"], row["mode"], row["paused"]), (10, 40, expected["mode"], True))
                    self.assertEqual(row["authored"], expected["fallbacks"][row["target"]])
                    self.assertEqual(row["laneCount"], 0 if row["target"] in expected["constantTargets"] else 1)
                    if expected["response"]:
                        self.assertEqual([row["smoothing"], row["stiffness"]], expected["response"])
                if expected["response"]:
                    self.assertTrue(any("responseOptionsUnmodeled" in message for message in observed["diagnostics"]))
                for target, row in bindings.items():
                    if target not in targets:
                        self.assertFalse(row["grouped"], target)
                        self.assertEqual(row["owner"], target)

    def test_each_curve_and_pass_alias_reaches_the_real_snapshot(self):
        for name, (expected, observed) in self.results.items():
            if not expected["accepted"]:
                continue
            with self.subTest(case=name):
                self.assert_values(observed["initial"], expected["frames"]["0"])
                for frame, label in (("0", "initialSnapshot"), ("10", "key10Snapshot")):
                    snapshot = observed[label]
                    self.assert_values({target: row["value"] for target, row in snapshot.items()}, expected["frames"][frame])
                    self.assertTrue(all(row["source"] == "timeline" for row in snapshot.values()))
                absent = observed["withoutGroupTimelineSnapshot"]
                for target in expected["targets"]:
                    self.assertNotEqual(absent[target]["source"], "timeline", target)
                    self.assertEqual(absent[target]["value"], expected["fallbacks"][target])

    def test_member_commands_share_original_state_without_borrowing_other_tracks(self):
        phases = {"key10": "10", "played30": "30", "paused30": "30", "completed40": "40",
                  "restart0": "0", "activePlay10": "10", "seekPlaying30": "30", "stopped0": "0",
                  "stopPlay10": "10", "playStop0": "0", "preview10": "10"}
        for name, (expected, observed) in self.results.items():
            if not expected["accepted"]:
                continue
            with self.subTest(case=name):
                if expected["mode"] == "single":
                    for label, frame in phases.items():
                        self.assertIn(label, observed)
                        self.assert_values(observed[label], expected["frames"][frame])
                else:
                    self.assert_values(observed["key10"], expected["frames"]["10"])
                self.assertEqual(set(observed["preview10"]), set(expected["targets"]))
                self.assertTrue(observed["previewDidNotCommit"])
                self.assertTrue(observed["independentTracksUnchanged"])
                self.assertTrue(all(observed["retirement"].values()), observed["retirement"])

    def test_no_lane_child_uses_its_own_value_through_shared_commands_and_retirement(self):
        for name in ("missing-lanes", "constant-child", "different-constants", "renamed-constant-child"):
            expected, observed = self.results[name]
            with self.subTest(case=name):
                self.assertEqual(len(expected["constantTargets"]), 2)
                for target in expected["constantTargets"]:
                    own = expected["fallbacks"][target]
                    for phase in ("initial", "key10", "played30", "paused30", "seekPlaying30", "stopped0"):
                        self.assertIn(target, observed[phase])
                        self.assertEqual(observed[phase][target], own, (target, phase))
                    if name != "missing-lanes":
                        self.assertNotEqual(own, 7)
                self.assertTrue(all(observed["retirement"].values()), observed["retirement"])

    def test_effect_constant_route_does_not_create_general_or_layer_no_lane_producers(self):
        for name, (expected, observed) in self.host_results.items():
            with self.subTest(case=name):
                self.assertEqual(observed["generalHosts"], expected["generalHosts"])
                self.assertEqual(observed["layerHosts"], expected["layerHosts"])
                self.assertEqual(observed["targets"], sorted(expected["values"]))
                self.assertEqual(observed["values"], expected["values"])
                self.assertEqual(observed["sources"], dict.fromkeys(expected["values"], "timeline"))
                if name.endswith("-empty"):
                    self.assertTrue(observed["diagnostics"])

    def test_signed_zero_aliases_keep_their_actual_snapshot_bits(self):
        expected, observed = self.results["signed-zero"]
        targets = expected["signedZero"]
        for label, bits in (("positive", "0"), ("negative", "8000000000000000")):
            target = targets[label]
            self.assertEqual(observed["initialSnapshot"][target]["bits"], bits)
            self.assertEqual(observed["withoutGroupTimelineSnapshot"][target]["bits"], "0")
            binding = next(row for row in observed["bindings"] if row["target"] == target)
            self.assertEqual(binding["authoredBits"], "0")

    def test_incomplete_or_conflicting_component_keeps_real_independent_neighbors(self):
        for name, (expected, observed) in self.results.items():
            if expected["accepted"]:
                continue
            with self.subTest(case=name):
                self.assertEqual(observed["effectTargets"], [])
                self.assertEqual(observed["groupTargets"], [])
                self.assertTrue(observed["diagnostics"])
                self.assertEqual(len(observed["bindings"]), 3)
                self.assertEqual(observed["initial"][f"layer:{expected['peer']}:alpha"], .75)
                self.assertEqual(sum(target.startswith(f"effect:{expected['layer']}:1:")
                                     for target in observed["initial"]), 2)
                self.assertTrue(all(row["source"] == "timeline" for row in observed["initialSnapshot"].values()))


if __name__ == "__main__":
    unittest.main()
