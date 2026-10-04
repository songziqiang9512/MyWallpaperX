"""Vortex author input through the real parser, prepared plan and simulator.

The behavioral cases use real v2 wire fields and owned input values. Numerical
trajectory agreement requires a separate fixed official capture comparison;
these invariants do not substitute for that visible comparison.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .test_scene_particle_audio_response import SWIFT_SOURCES


HARNESS = r'''
import Foundation
@main enum Harness {
    static func main() throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let cases = try JSONSerialization.jsonObject(with: input) as! [[String: Any]]
        var results: [String: Any] = [:]
        for item in cases {
            let definition = SceneParticleDefinitionParser().parse(root: item["definition"] as! [String: Any])
            let simulator = SceneParticleSimulator(
                definition: definition,
                instanceOverride: (item["instanceSpeed"] as? Double).flatMap {
                    SceneParticleDefinitionParser().parseInstanceOverride(["speed": $0])
                },
                seed: 81, fixedTimeStep: 1.0 / 60
            )
            var controlPoints: [Int: SIMD3<Double>] = [:]
            var controlPointAngles: [Int: SIMD3<Double>] = [:]
            if let value = item["dynamicCP"] as? [Double] {
                controlPoints[0] = SIMD3(value[0], value[1], value[2])
            }
            if let value = item["dynamicAngles"] as? [Double] {
                controlPointAngles[0] = SIMD3(value[0], value[1], value[2])
            }
            let deltas = item["deltas"] as? [Double] ?? Array(repeating: 0.1, count: 6)
            for delta in deltas {
                simulator.advance(by: delta, dynamicControlPoints: controlPoints,
                                  dynamicControlPointAngles: controlPointAngles)
            }
            results[item["name"] as! String] = [
                "diagnostics": simulator.diagnostics.map(\.kind.rawValue),
                "particles": simulator.particles.map { p in [
                    "position": [p.position.x, p.position.y, p.position.z],
                    "velocity": [p.velocity.x, p.velocity.y, p.velocity.z]
                ] }
            ]
        }
        let output = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        FileHandle.standardOutput.write(output)
    }
}
'''


def fixtures() -> list[dict]:
    base = {
        "material": "owned.json", "maxcount": 1,
        "emitter": [{"name": "boxrandom", "rate": 0, "instantaneous": 1,
                     "directions": "1 1 1", "origin": "12 0 0", "distancemin": "0 0 0", "distancemax": "0 0 0"}],
        "initializer": [{"name": "lifetimerandom", "min": 100, "max": 100}],
        "operator": [{"name": "movement", "drag": 0, "gravity": "0 0 0"},
                     {"name": "vortex_v2", "distanceinner": 0, "distanceouter": 32,
                      "speedinner": 0, "speedouter": 30}],
        "renderer": [{"name": "sprite"}],
    }
    cases = []
    for name, changes in [
        ("positive", {}), ("zero", {"speedinner": 0, "speedouter": 0}),
        ("negative", {"speedouter": -30}), ("classic", {"name": "vortex"}),
        ("unknown-field", {"unknownfixture": 1}),
        ("malformed", {"speedouter": "nan"}),
        ("equal-distance", {"distanceinner": 32, "distanceouter": 32}),
        ("unknown-flags", {"flags": 4}),
        ("radius-pending", {"flags": 2}),
        ("other-axis", {"axis": "1 0 0"}),
        ("other-cp", {"controlpoint": 1}),
        ("bad-cp", {"controlpoint": "bad"}),
        ("audio-v2", {"audioprocessingmode": 3}),
        ("audio-zero", {"audioprocessingmode": 0}),
        ("malformed-audio-mode", {"audioprocessingmode": "bad"}),
        ("malformed-disabled-audio", {"audioprocessingmode": 0, "audioprocessingbounds": "bad"}),
        ("malformed-blend", {"blendinstart": "bad"}),
        ("explicit-origin", {"axis": "0 0 1", "controlpoint": 0}),
    ]:
        definition = copy.deepcopy(base)
        definition["operator"][1].update(changes)
        cases.append({"name": name, "definition": definition})
    partitioned = copy.deepcopy(cases[0])
    partitioned.update(name="partitioned", deltas=[0.2, 0.1, 0.3])
    cases.append(partitioned)
    definition = copy.deepcopy(base)
    definition["controlpoint"] = [{"id": i, "offset": "0 0 0", "flags": 0} for i in range(8)]
    cases.append({"name": "static-real-cp-table", "definition": definition})
    for name, points in [("shifted-center", [{"id": 0, "offset": "6 4 0", "flags": 0}]),
                         ("angle-center", [{"id": 0, "angles": "1 0 0", "flags": 0}]),
                         ("pointer-center", [{"id": 0, "flags": 1}])]:
        definition = copy.deepcopy(base)
        definition["controlpoint"] = points
        if name == "pointer-center":
            definition["emitter"][0]["controlpoint"] = 1
        if name == "shifted-center":
            definition["emitter"][0].update(origin="18 4 0")
        cases.append({"name": name, "definition": definition})
    for field, value in [("dynamicCP", [6, 4, 0]), ("dynamicAngles", [0, 0, 0.3])]:
        for active in [False, True]:
            definition = copy.deepcopy(base)
            definition["operator"][0]["gravity"] = "0 0 4"
            if not active:
                del definition["operator"][1]
            cases.append({"name": f"{field}-{active}", "definition": definition, field: value})
    # Independent own-input CUA observation: particle clock 12 +/- 2 seconds,
    # positions +/- 2 scene units. This is a bounded response check, not a golden.
    for speed in [0.1, 1]:
        definition = copy.deepcopy(base)
        definition["emitter"][0]["origin"] = "120 0 0"
        definition["operator"][1].update(distanceouter=200, speedinner=speed, speedouter=speed)
        cases.append({"name": f"response-{speed}", "definition": definition, "deltas": [0.1] * 120})
    high = copy.deepcopy(base)
    high["emitter"][0]["origin"] = "32 0 0"
    high["initializer"][0].update(min=0.7, max=0.7)
    high["controlpoint"] = [{"id": i, "offset": "0 0 0", "flags": 0} for i in range(8)]
    high["operator"][0]["drag"] = 0.5
    high["operator"][1].update(speedinner=0, speedouter=3000)
    high["operator"].append({"name": "controlpointattract", "origin": "0 0 0",
                             "scale": -1500, "threshold": 99999})
    for name, definition in [("high-speed", high), ("high-no-vortex", copy.deepcopy(high)),
                              ("high-vortex-before-movement", copy.deepcopy(high))]:
        if name == "high-no-vortex":
            del definition["operator"][1]
        elif name == "high-vortex-before-movement":
            definition["operator"][0], definition["operator"][1] = definition["operator"][1], definition["operator"][0]
        cases.append({"name": name, "definition": definition, "instanceSpeed": 0.94, "deltas": [0.1] * 5})
    return cases


class SceneParticleVortexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        keep = os.environ.get("MWX_VORTEX_TEST_ARTIFACTS")
        if keep:
            cls.root = Path(keep)
            cls.root.mkdir(parents=True, exist_ok=True)
        else:
            cls.scratch = tempfile.TemporaryDirectory(prefix="mwx-vortex-")
            cls.addClassCleanup(cls.scratch.cleanup)
            cls.root = Path(cls.scratch.name)
        harness, data, binary = [cls.root / n for n in ["Harness.swift", "inputs.json", "probe"]]
        harness.write_text(HARNESS)
        data.write_text(json.dumps(fixtures(), indent=2))
        paths = [*SWIFT_SOURCES, harness, data, Path(__file__)]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        command = ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (cls.root / "compile.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        result = subprocess.run([str(binary), str(data)], capture_output=True, text=True)
        (cls.root / "result.json").write_text(result.stdout)
        unchanged = all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in hashes.items())
        (cls.root / "identity.json").write_text(json.dumps({"sources": hashes, "unchanged": unchanged,
            "command": command, "exit": result.returncode}, indent=2))
        if result.returncode or not unchanged:
            raise AssertionError(result.stderr or "source identity changed")
        cls.result = json.loads(result.stdout)

    def particle(self, name):
        self.assertEqual(len(self.result[name]["particles"]), 1)
        return self.result[name]["particles"][0]

    def test_real_v2_wire_executes_instead_of_being_skipped(self):
        value = self.particle("positive")
        self.assertNotEqual(value["position"], [12, 0, 0])
        self.assertNotIn("unsupportedOperator", self.result["positive"]["diagnostics"])
        self.assertNotIn("vortexUnsupported", self.result["positive"]["diagnostics"])
        self.assertLess(value["position"][1], 0)
        self.assertEqual(value, self.particle("explicit-origin"))
        self.assertEqual(value, self.particle("static-real-cp-table"))
        self.assertEqual(value, self.particle("audio-zero"))

    def test_zero_speed_preserves_stationary_particle_and_classic_still_executes(self):
        self.assertEqual(self.particle("zero")["position"], [12, 0, 0])
        self.assertEqual(self.particle("zero")["velocity"], [0, 0, 0])
        self.assertNotEqual(self.particle("classic")["position"], [12, 0, 0])

    def test_signed_speed_reverses_rotation_without_changing_radial_symmetry(self):
        positive, negative = [self.particle(n) for n in ["positive", "negative"]]
        self.assertNotEqual(positive["position"][1], 0)
        for field in ["position", "velocity"]:
            for index, sign in enumerate([1, -1, 1]):
                self.assertAlmostEqual(positive[field][index], sign * negative[field][index], delta=1e-8)

    def test_partitioning_display_delta_does_not_change_fixed_step_result(self):
        for field in ["position", "velocity"]:
            for actual, expected in zip(self.particle("partitioned")[field], self.particle("positive")[field]):
                self.assertAlmostEqual(actual, expected, delta=1e-8)

    def test_shifted_center_rejects_only_vortex_without_moving_particle(self):
        self.assertEqual(self.particle("shifted-center")["position"], [18, 4, 0])
        self.assertEqual(self.particle("shifted-center")["velocity"], [0, 0, 0])
        self.assertIn("vortexUnsupported", self.result["shifted-center"]["diagnostics"])

    def test_unsupported_dynamic_center_skips_only_vortex_and_keeps_movement(self):
        for field in ["dynamicCP", "dynamicAngles"]:
            self.assertEqual(self.particle(f"{field}-True"), self.particle(f"{field}-False"))
            self.assertGreater(self.particle(f"{field}-True")["position"][2], 0.5)

    def test_frozen_independent_response_at_shared_particle_time(self):
        for name, expected in [("response-0.1", [120, -5, 0]), ("response-1", [116, -50, 0])]:
            for actual, observed in zip(self.particle(name)["position"], expected):
                self.assertAlmostEqual(actual, observed, delta=2)

    def test_real_high_speed_combination_remains_finite_and_preserves_authored_order(self):
        active = self.particle("high-speed")
        inactive = self.particle("high-no-vortex")
        for name in ["high-speed", "high-no-vortex", "high-vortex-before-movement"]:
            self.assertNotIn("vortexUnsupported", self.result[name]["diagnostics"])
            for vector in self.particle(name).values():
                self.assertTrue(all(math.isfinite(component) for component in vector))
        self.assertLess(active["position"][1], -1)
        self.assertEqual(inactive["position"][1], 0)
        self.assertNotEqual(active, self.particle("high-vortex-before-movement"))

    def test_invalid_operator_preserves_finite_neighbor_state(self):
        for name in ["unknown-field", "malformed", "equal-distance", "unknown-flags",
                     "radius-pending", "other-axis", "other-cp", "bad-cp", "audio-v2",
                     "malformed-audio-mode", "malformed-disabled-audio", "malformed-blend", "angle-center", "pointer-center"]:
            with self.subTest(name=name):
                self.assertEqual(self.particle(name)["position"], [12, 0, 0])
                self.assertEqual(self.particle(name)["velocity"], [0, 0, 0])
                self.assertTrue(set(self.result[name]["diagnostics"]) & {"unsupportedOperator", "vortexUnsupported"})


if __name__ == "__main__":
    unittest.main()
