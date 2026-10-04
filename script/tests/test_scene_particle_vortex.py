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
    static func vector(_ value: SIMD3<Double>) -> [Double] {
        [value.x, value.y, value.z]
    }

    // Keep numeric vector-only `particles` below stable for the existing finite
    // checks. Lifecycle/constraint metadata has its own typed output record.
    static func state(_ simulator: SceneParticleSimulator) -> [String: Any] {
        func metadata(_ particle: SceneParticleState) -> [String: Any] {
            ["id": particle.id, "position": vector(particle.position),
             "velocity": vector(particle.velocity), "age": particle.age,
             "radius": hypot(particle.position.x, particle.position.y),
             "anchor": particle.vortexRadius.map { $0 as Any } ?? NSNull()]
        }
        return ["time": simulator.simulationTime,
                "particles": simulator.particles.map(metadata),
                "births": simulator.birthEvents.map(metadata),
                "deaths": simulator.deathEvents.map(metadata)]
    }

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
            var states: [[String: Any]] = []
            var snapshots: [String: SceneParticleSimulator.FrameSnapshot] = [:]
            var radiusMinimum = Double.infinity
            var radiusMaximum = -Double.infinity
            var maximumAnchorError = 0.0
            var sampledParticles = 0
            var advances = 0
            func advance(_ delta: Double, _ stage: [String: Any] = [:]) {
                var points = controlPoints
                var angles = controlPointAngles
                if let value = stage["dynamicCP"] as? [Double] {
                    points[0] = SIMD3(value[0], value[1], value[2])
                }
                if let value = stage["dynamicAngles"] as? [Double] {
                    angles[0] = SIMD3(value[0], value[1], value[2])
                }
                let speed = (stage["instanceSpeed"] as? Double).flatMap {
                    SceneParticleDefinitionParser().parseInstanceOverride(["speed": $0])
                }
                simulator.advance(by: delta, dynamicControlPoints: points,
                    dynamicControlPointAngles: angles, dynamicInstanceOverride: speed)
                advances += 1
                for particle in simulator.particles {
                    let radius = hypot(particle.position.x, particle.position.y)
                    radiusMinimum = min(radiusMinimum, radius)
                    radiusMaximum = max(radiusMaximum, radius)
                    if let anchor = particle.vortexRadius {
                        maximumAnchorError = max(maximumAnchorError, abs(radius - anchor))
                    }
                    sampledParticles += 1
                }
            }
            if let stages = item["stages"] as? [[String: Any]] {
                for stage in stages {
                    if let name = stage["restore"] as? String {
                        simulator.restoreFrame(snapshots[name]!)
                    }
                    if let delta = stage["delta"] as? Double { advance(delta, stage) }
                    if let name = stage["save"] as? String {
                        snapshots[name] = simulator.frameSnapshot()
                    }
                    states.append(state(simulator))
                }
            } else {
                let deltas = item["deltas"] as? [Double] ?? Array(
                    repeating: item["delta"] as? Double ?? 0.1,
                    count: item["steps"] as? Int ?? 6)
                for delta in deltas { advance(delta) }
            }
            results[item["name"] as! String] = [
                "diagnostics": simulator.diagnostics.map(\.kind.rawValue),
                "particles": simulator.particles.map { p in [
                    "position": [p.position.x, p.position.y, p.position.z],
                    "velocity": [p.velocity.x, p.velocity.y, p.velocity.z]
                ] },
                "state": state(simulator), "states": states,
                "radiusSummary": [
                    "minimum": sampledParticles > 0 ? radiusMinimum : 0,
                    "maximum": sampledParticles > 0 ? radiusMaximum : 0,
                    "maximumAnchorError": maximumAnchorError,
                    "samples": sampledParticles, "advances": advances
                ]
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
        ("radius-maintained", {"flags": 2}),
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
    cases.extend(radius_fixtures(base))
    return cases


def radius_fixtures(base: dict) -> list[dict]:
    """Owned input probes; radius invariants do not assert official phase parity."""
    ring = copy.deepcopy(base)
    ring["emitter"][0]["origin"] = "120 0 0"
    ring["initializer"][0].update(min=1000, max=1000)
    ring["operator"][1].update(flags=2, speedouter=2500)
    cases = []

    def add(name, definition=ring, **inputs):
        cases.append({"name": name, "definition": copy.deepcopy(definition), **inputs})

    for speed, drag in [(0, 0), (128, 0), (128, 0.5)]:
        definition = copy.deepcopy(ring)
        definition["initializer"].append({"name": "velocityrandom",
            "min": f"{speed} 0 0", "max": f"{speed} 0 0"})
        definition["operator"][0]["drag"] = drag
        add(f"ring-long-{speed}-{drag}", definition, steps=444 * 60, delta=1 / 60)
    add("ring-long-partitioned", steps=4440, delta=0.1)
    negative = copy.deepcopy(ring)
    negative["operator"][1]["speedouter"] = -2500
    add("ring-long-negative", negative, steps=444 * 60, delta=1 / 60)
    zero = copy.deepcopy(ring)
    zero["emitter"][0]["origin"] = "0 0 0"
    add("ring-zero-radius", zero, steps=60, delta=1 / 60)
    radial = copy.deepcopy(ring)
    radial["initializer"].append({"name": "velocityrandom", "min": "128 0 0", "max": "128 0 0"})
    add("ring-first-movement", radial, stages=[{"delta": 1 / 60}, {"delta": 1 / 60}])
    add("ring-force-overflow", stages=[
        {"delta": 1 / 60, "instanceSpeed": 1e40}, {"delta": 1 / 60}])
    overflow = copy.deepcopy(ring)
    overflow["operator"][0]["drag"] = 1e40
    add("ring-movement-overflow", overflow,
        stages=[{"delta": 1 / 60}, {"delta": 1 / 60}])
    add("ring-snapshot", radial, stages=[
        {"save": "initial"}, {"delta": 1 / 60, "save": "anchored"},
        {"delta": 0.5}, {"restore": "anchored"}, {"delta": 0.5},
        {"restore": "initial"}, {"delta": 1 / 60}])
    for field, value in [("dynamicCP", [6, 4, 0]), ("dynamicAngles", [0, 0, 0.3])]:
        add(f"ring-reanchor-{field}", stages=[
            {"delta": 0.1}, {"delta": 0.2, field: value},
            {"delta": 1 / 60}, {"delta": 0.2}])
    population = copy.deepcopy(radial)
    population["emitter"][0].update(rate=60, instantaneous=0)
    population["initializer"][0].update(min=0.05, max=0.05)
    add("ring-population", population, stages=[
        {"delta": 1 / 60}, {"delta": 2 / 60},
        {"delta": 1 / 60, "instanceSpeed": 0.23},
        {"delta": 1 / 60, "instanceSpeed": 0.23},
        {"delta": 1 / 60, "instanceSpeed": 0.23}, {"delta": 1 / 60}])
    real_shape = copy.deepcopy(radial)
    real_shape.update(maxcount=32)
    real_shape["emitter"][0].update(rate=60, instantaneous=1)
    real_shape["initializer"][0].update(min=0.4, max=0.7)
    real_shape["operator"][0]["drag"] = 0.5
    real_shape["operator"].insert(1, {"name": "alphafade", "fadeintime": 0.1, "fadeouttime": 0.8})
    add("ring-author-shape", real_shape, instanceSpeed=0.23, steps=600, delta=1 / 60)

    # Each rejected definition has a paired neighbor-only simulator. Equality
    # proves the radius vortex is skipped locally, including a second vortex
    # whose ordinary acceleration semantics remain admitted.
    rejected = {}
    for name in ["multiple-movement", "multiple-vortex", "wrong-order", "no-movement",
                 "gravity", "scalar-gravity", "short-gravity", "long-gravity",
                 "movement-flags", "world-space", "attract", "cap-velocity"]:
        definition = copy.deepcopy(radial)
        operators = definition["operator"]
        if name == "multiple-movement":
            operators.insert(0, copy.deepcopy(operators[0]))
        elif name == "multiple-vortex":
            other = copy.deepcopy(operators[1])
            other["flags"] = 0
            operators.append(other)
        elif name == "wrong-order":
            operators.reverse()
        elif name == "no-movement":
            del operators[0]
        elif name == "gravity":
            operators[0]["gravity"] = "0 0 4"
        elif name == "scalar-gravity":
            operators[0]["gravity"] = 1
        elif name == "short-gravity":
            operators[0]["gravity"] = "0 0"
        elif name == "long-gravity":
            operators[0]["gravity"] = "0 0 0 0"
        elif name == "movement-flags":
            operators[0]["flags"] = 1
        elif name == "world-space":
            definition["flags"] = 1
        elif name == "attract":
            operators.append({"name": "controlpointattract", "origin": "0 0 0",
                              "scale": -50, "threshold": 99999})
        elif name == "cap-velocity":
            operators.append({"name": "capvelocity", "maxspeed": 50})
        rejected[name] = definition
    for name, definition in rejected.items():
        add(f"ring-reject-{name}", definition)
        neighbor = copy.deepcopy(definition)
        neighbor["operator"] = [value for value in neighbor["operator"]
                                if value.get("name") != "vortex_v2" or value.get("flags") != 2]
        add(f"ring-neighbor-{name}", neighbor)
    for name, gravity in [("absent", None), ("scalar-zero", 0), ("vector-zero", "0 0 0")]:
        definition = copy.deepcopy(ring)
        if gravity is None:
            del definition["operator"][0]["gravity"]
        else:
            definition["operator"][0]["gravity"] = gravity
        add(f"ring-admit-gravity-{name}", definition)
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
                     "other-axis", "other-cp", "bad-cp", "audio-v2",
                     "malformed-audio-mode", "malformed-disabled-audio", "malformed-blend", "angle-center", "pointer-center"]:
            with self.subTest(name=name):
                self.assertEqual(self.particle(name)["position"], [12, 0, 0])
                self.assertEqual(self.particle(name)["velocity"], [0, 0, 0])
                self.assertTrue(set(self.result[name]["diagnostics"]) & {"unsupportedOperator", "vortexUnsupported"})

    def state_particle(self, name, stage=None):
        state = self.result[name]["state"] if stage is None else self.result[name]["states"][stage]
        self.assertEqual(len(state["particles"]), 1)
        return state["particles"][0]

    def test_radius_flag_executes_and_remains_stable_for_444_seconds(self):
        self.assertNotIn("vortexUnsupported", self.result["radius-maintained"]["diagnostics"])
        self.assertAlmostEqual(self.state_particle("radius-maintained")["anchor"], 12, delta=1e-10)
        for speed, drag in [(0, 0), (128, 0), (128, 0.5)]:
            name = f"ring-long-{speed}-{drag}"
            expected = 120 + speed * (1 - drag / 60) / 60
            with self.subTest(name=name):
                value = self.result[name]
                self.assertNotIn("vortexUnsupported", value["diagnostics"])
                self.assertAlmostEqual(value["state"]["time"], 444, delta=1e-8)
                self.assertEqual(value["radiusSummary"]["samples"], 444 * 60)
                for key in ["minimum", "maximum"]:
                    self.assertAlmostEqual(value["radiusSummary"][key], expected, delta=1e-8)
                self.assertLess(value["radiusSummary"]["maximumAnchorError"], 1e-8)
                self.assertAlmostEqual(self.state_particle(name)["anchor"], expected, delta=1e-10)
                for vector in self.particle(name).values():
                    self.assertTrue(all(math.isfinite(component) for component in vector))

    def test_radius_anchor_follows_initial_movement_and_removes_radial_velocity(self):
        first, second = [self.state_particle("ring-first-movement", i) for i in [0, 1]]
        expected = 120 + 128 / 60
        self.assertAlmostEqual(first["position"][0], expected, delta=1e-10)
        self.assertEqual(first["position"][1:], [0, 0])
        for value in [first, second]:
            self.assertAlmostEqual(value["radius"], expected, delta=1e-10)
            self.assertAlmostEqual(value["anchor"], expected, delta=1e-10)
            self.assertAlmostEqual(sum(p * v for p, v in zip(value["position"], value["velocity"])),
                                   0, delta=1e-8)
        self.assertLess(second["position"][1], 0)

    def test_radius_drag_signed_speed_zero_radius_and_frame_partitioning(self):
        positive = self.particle("ring-long-0-0")
        negative = self.particle("ring-long-negative")
        for field in ["position", "velocity"]:
            for index, sign in enumerate([1, -1, 1]):
                self.assertAlmostEqual(positive[field][index], sign * negative[field][index], delta=1e-8)
            for actual, expected in zip(self.particle("ring-long-partitioned")[field], positive[field]):
                self.assertAlmostEqual(actual, expected, delta=1e-8)
        self.assertLess(self.state_particle("ring-long-negative")["radius"], 120 + 1e-8)
        speeds = [math.hypot(*self.particle(name)["velocity"][:2])
                  for name in ["ring-long-128-0", "ring-long-128-0.5"]]
        self.assertGreater(speeds[0], speeds[1] * 10)
        self.assertEqual(self.particle("ring-zero-radius"),
                         {"position": [0, 0, 0], "velocity": [0, 0, 0]})
        self.assertIsNone(self.state_particle("ring-zero-radius")["anchor"])
        self.assertNotIn("vortexUnsupported", self.result["ring-zero-radius"]["diagnostics"])

    def test_radius_snapshot_restore_preserves_anchored_and_unanchored_state(self):
        states = self.result["ring-snapshot"]["states"]
        self.assertEqual(states[0], states[5])
        self.assertEqual(states[1], states[3])
        self.assertEqual(states[2], states[4])
        self.assertEqual(states[1], states[6])
        self.assertEqual(states[0]["particles"], [])
        self.assertGreater(states[1]["particles"][0]["anchor"], 120)

    def test_dynamic_control_point_invalidation_clears_anchor_and_recovery_reanchors(self):
        for field in ["dynamicCP", "dynamicAngles"]:
            name = f"ring-reanchor-{field}"
            first, invalid, recovered, stable = [self.state_particle(name, i) for i in range(4)]
            with self.subTest(field=field):
                self.assertIsNone(invalid["anchor"])
                self.assertNotEqual(invalid["position"], first["position"])
                self.assertNotAlmostEqual(invalid["radius"], first["anchor"], delta=0.1)
                self.assertAlmostEqual(recovered["anchor"], recovered["radius"], delta=1e-10)
                self.assertNotAlmostEqual(recovered["anchor"], first["anchor"], delta=0.1)
                self.assertAlmostEqual(stable["radius"], recovered["anchor"], delta=1e-8)
                self.assertEqual(stable["id"], first["id"])

    def test_new_births_and_deaths_do_not_inherit_previous_particle_anchor(self):
        states = self.result["ring-population"]["states"]
        first = self.state_particle("ring-population", 0)
        second = self.state_particle("ring-population", 2)
        third = self.state_particle("ring-population", 5)
        self.assertEqual([first["id"], second["id"], third["id"]], [0, 1, 2])
        self.assertEqual(states[1]["particles"], [])
        self.assertEqual(states[4]["particles"], [])
        self.assertAlmostEqual(first["anchor"], 120 + 128 / 60, delta=1e-10)
        self.assertAlmostEqual(second["anchor"], 120 + 128 * 0.23 / 60, delta=1e-10)
        self.assertAlmostEqual(third["anchor"], first["anchor"], delta=1e-10)
        self.assertEqual(states[1]["deaths"][0]["anchor"], first["anchor"])
        self.assertEqual(states[4]["deaths"][1]["anchor"], second["anchor"])
        for birth in states[5]["births"]:
            self.assertIsNone(birth["anchor"])
            self.assertEqual(birth["position"], [120, 0, 0])

    def test_real_author_shape_with_drag_fade_speed_override_and_short_lives(self):
        result = self.result["ring-author-shape"]
        self.assertNotIn("vortexUnsupported", result["diagnostics"])
        self.assertGreater(len(result["state"]["births"]), 500)
        self.assertGreater(len(result["state"]["deaths"]), 500)
        self.assertLess(result["radiusSummary"]["maximumAnchorError"], 1e-8)
        expected = 120 + 128 * 0.23 * (1 - 0.5 / 60) / 60
        for value in result["state"]["particles"]:
            self.assertAlmostEqual(value["anchor"], expected, delta=1e-10)
            self.assertAlmostEqual(value["radius"], expected, delta=1e-8)

    def test_radius_unsupported_combinations_reject_only_vortex(self):
        for name in ["multiple-movement", "multiple-vortex", "wrong-order", "no-movement",
                     "gravity", "scalar-gravity", "short-gravity", "long-gravity",
                     "movement-flags", "world-space", "attract", "cap-velocity"]:
            active = f"ring-reject-{name}"
            neighbor = f"ring-neighbor-{name}"
            with self.subTest(name=name):
                self.assertIn("vortexUnsupported", self.result[active]["diagnostics"])
                self.assertEqual(self.result[active]["particles"], self.result[neighbor]["particles"])
                self.assertEqual(self.result[active]["state"], self.result[neighbor]["state"])
                self.assertIsNone(self.state_particle(active)["anchor"])
        for name in ["absent", "scalar-zero", "vector-zero"]:
            active = f"ring-admit-gravity-{name}"
            self.assertNotIn("vortexUnsupported", self.result[active]["diagnostics"])
            self.assertEqual(self.particle(active), self.particle("ring-admit-gravity-vector-zero"))
            self.assertAlmostEqual(self.state_particle(active)["anchor"], 120, delta=1e-10)

    def test_failed_force_does_not_anchor_and_failed_movement_does_not_half_commit(self):
        force_failed, force_recovered = [self.state_particle("ring-force-overflow", i) for i in [0, 1]]
        self.assertEqual(force_failed["position"], [120, 0, 0])
        self.assertEqual(force_failed["velocity"], [0, 0, 0])
        self.assertIsNone(force_failed["anchor"])
        self.assertAlmostEqual(force_recovered["anchor"], 120, delta=1e-10)
        self.assertLess(force_recovered["velocity"][1], 0)
        before, failed = [self.state_particle("ring-movement-overflow", i) for i in [0, 1]]
        self.assertIn("invalidOperatorState", self.result["ring-movement-overflow"]["diagnostics"])
        self.assertEqual(failed["position"], before["position"])
        self.assertEqual(failed["anchor"], before["anchor"])
        # Movement rejected its complete candidate; the subsequent independent
        # vortex force may still add a valid finite tangent impulse.
        for actual, expected in zip(failed["velocity"], before["velocity"]):
            self.assertAlmostEqual(actual, 2 * expected, delta=1e-10)


if __name__ == "__main__":
    unittest.main()
