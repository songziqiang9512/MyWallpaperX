"""Authored scalar Remap through real preparation and fixed-step simulation.

FBM is a project approximation. These invariants do not claim official noise,
phase, scale-domain or trajectory parity. The optional Simulator source selects
a frozen before owner for a behavioral red run, without copying implementation.
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

from script.tests.scene.test_scene_particle_audio_response import SWIFT_SOURCES

HARNESS = r'''
import Foundation

@main enum Harness {
    static func number(_ value: Double) -> Any {
        value.isFinite ? value as Any : String(describing: value)
    }
    static func vector(_ value: SIMD3<Double>) -> [Any] {
        [number(value.x), number(value.y), number(value.z)]
    }
    static func observe(_ simulator: SceneParticleSimulator) -> [String: Any] {
        let frame = simulator.frameSnapshot()
        return ["time": number(simulator.simulationTime),
            "ids": simulator.particles.map(\.id),
            "ages": simulator.particles.map { number($0.age) },
            "alpha": simulator.particles.map { number($0.alpha) },
            "velocity": simulator.particles.map { vector($0.velocity) },
            "position": simulator.particles.map { vector($0.position) },
            "nextID": frame.nextParticleID, "randomState": frame.random.state,
            "gpuFinite": simulator.particles.allSatisfy {
                SceneParticleSimulationMath.isGPUFinite($0.velocity)
                    && SceneParticleSimulationMath.isGPUFinite($0.position)
            },
            "diagnostics": simulator.diagnostics.map {
                ["kind": $0.kind.rawValue, "component": $0.componentName ?? ""]
            }]
    }
    static func main() throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let cases = try JSONSerialization.jsonObject(with: input) as! [[String: Any]]
        var results: [String: Any] = [:]
        let parser = SceneParticleDefinitionParser()
        for item in cases {
            let definition = parser.parse(root: item["definition"] as! [String: Any])
            let simulator = SceneParticleSimulator(definition: definition,
                instanceOverride: parser.parseInstanceOverride(item["instanceOverride"] as? [String: Any]),
                initialTiming: .init(sceneTime: item["initialSceneTime"] as? Double ?? 0),
                seed: (item["seed"] as? NSNumber)?.uint64Value ?? 81, fixedTimeStep: 0.125)
            var states: [[String: Any]] = []
            var snapshots: [String: SceneParticleSimulator.FrameSnapshot] = [:]
            for step in item["steps"] as! [[String: Any]] {
                if let key = step["restore"] as? String { simulator.restoreFrame(snapshots[key]!) }
                if let duration = step["advance"] as? Double {
                    simulator.advance(by: duration, timing: .init(sceneTime: step["sceneTime"] as? Double ?? 0))
                }
                if let key = step["save"] as? String { snapshots[key] = simulator.frameSnapshot() }
                states.append(observe(simulator))
            }
            results[item["name"] as! String] = states
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

SPEED = {"name": "remapvalue", "flags": 3, "output": "speed",
         "outputrangemin": -5, "outputrangemax": 7,
         "transformfunction": "fbmnoise", "transforminputscale": 8}
VELOCITY = {"name": "remapvalue", "operation": "remap", "output": "velocity",
            "outputrangemin": "-10 -20 0", "outputrangemax": "10 -40 0",
            "transformfunction": "simplexnoise", "transforminputscale": 10}
MOVEMENT = {"name": "movement", "gravity": "0 0 0", "drag": 0}
SINE = {"name": "remapvalue", "input": "particlesystemtime", "output": "opacity",
        "transformfunction": "sine"}


def fixture(operators, *, initial="2 -4 6", count=1, lifetime=8, steps=None, seed=81):
    return {"seed": seed, "steps": steps or [{"advance": 0.125}],
            "definition": {"material": "owned.json", "maxcount": count,
                "emitter": [{"name": "boxrandom", "rate": 0, "instantaneous": count,
                             "distancemin": "0 0 0", "distancemax": "0 0 0"}],
                "initializer": [{"name": "lifetimerandom", "min": lifetime, "max": lifetime},
                                {"name": "velocityrandom", "min": initial, "max": initial}],
                "operator": copy.deepcopy(operators), "renderer": [{"name": "sprite"}]}}


def cases():
    result = []

    def add(name, operators, **kwargs):
        result.append(dict(fixture(operators, **kwargs), name=name))

    for value in [-0.5, 0, 0.5, 2]:
        constant = dict(SPEED, outputrangemin=value, outputrangemax=value)
        add("constant-" + str(value), [constant, MOVEMENT])
    half = dict(SPEED, outputrangemin=0.5, outputrangemax=0.5)
    add("explicit-multiply", [dict(half, operation="multiply"), MOVEMENT])
    for index, representation in enumerate(["0.5", [0.5], {"value": 0.5},
                                            {"value": {"value": 0.5}}]):
        add("valid-scalar-shape-" + str(index), [dict(half,
            flags="3", outputrangemin=representation, outputrangemax=representation,
            transforminputscale={"value": "8"}), MOVEMENT])
    add("valid-vector-array", [dict(VELOCITY, outputrangemin=[-10, -20, 0],
        outputrangemax={"value": [10, -40, 0]}), MOVEMENT])
    add("negative-vector", [half, MOVEMENT], initial="-2 -4 -6")
    add("zero-vector", [half, MOVEMENT], initial="0 0 0")
    add("near-float-limit", [half, MOVEMENT], initial="2e38 1 -2e38")
    add("speed-after-movement", [MOVEMENT, half])
    add("two-half-steps", [half, MOVEMENT], steps=[{"advance": 0.25}])
    add("legacy-vector", [VELOCITY, MOVEMENT])
    rain = [{"name": "alphafade", "fadeintime": 0, "fadeouttime": 0},
            VELOCITY, SPEED, MOVEMENT]
    add("rain-shape", rain, count=2, steps=[{"advance": 1}])
    add("rain-without-speed", [rain[0], VELOCITY, MOVEMENT], count=2, steps=[{"advance": 1}])
    add("rain-split", rain, count=2, steps=[{"advance": 0.125}] * 8)
    add("rain-replay", rain, count=2, steps=[{"advance": 0.25, "save": "prefix"},
        {"advance": 0.25}, {"restore": "prefix"}, {"advance": 0.25}])
    # Reset velocity every step, making temporal coefficients observable even
    # after a zero coefficient; this is normal authored operator composition.
    reset = dict(VELOCITY, outputrangemin="0 20 0", outputrangemax="0 20 0")
    add("temporal-motion", [reset, SPEED, MOVEMENT], count=2,
        steps=[{"advance": 0.125}] * 63)
    add("temporal-other-seed", [reset, SPEED, MOVEMENT], seed=82,
        steps=[{"advance": 0.125}] * 63)
    add("maximum-scale", [dict(SPEED, transforminputscale=1_000_000), MOVEMENT])

    invalid = [("operation", None), ("operation", ""), ("operation", 1),
        ("operation", "remap"), ("flags", None), ("flags", True),
        ("flags", 3.5), ("flags", "invalid"), ("flags", 0), ("flags", 2),
        ("flags", 4), ("input", None), ("input", "particlesystemtime"),
        ("inputrange", 1), ("blendinstart", 0), ("future", 1),
        ("transformfunction", "simplexnoise"), ("transforminputscale", 0),
        ("transforminputscale", -1), ("transforminputscale", "NaN"),
        ("transforminputscale", "inf"), ("transforminputscale", 1_000_001),
        ("outputrangemin", None), ("outputrangemin", "NaN"),
        ("outputrangemax", "inf"), ("outputrangemax", True),
        ("outputrangemax", "1 2 3"), ("outputrangemax", 1_000_001)]
    for index, (field, value) in enumerate(invalid):
        add("invalid-" + str(index), [dict(SPEED, **{field: value}), MOVEMENT])
    for field, value in [("flags", 3), ("outputrangemin", -5),
                         ("outputrangemax", 7), ("transforminputscale", 8)]:
        for index, representation in enumerate([
            [value, "invalid"], [None, value], [[value]],
            {"value": [value, "invalid"]}, [{"value": value}],
        ]):
            add("invalid-shape-" + field + "-" + str(index),
                [dict(SPEED, **{field: representation}), MOVEMENT])
    for field in ["flags", "outputrangemin", "outputrangemax", "transforminputscale"]:
        incomplete = copy.deepcopy(SPEED)
        del incomplete[field]
        add("missing-" + field, [incomplete, MOVEMENT])
    add("unsupported-with-healthy-peer", [dict(SPEED, future=1), VELOCITY, MOVEMENT])
    add("legacy-explicit-flags0", [dict(VELOCITY, flags=0), MOVEMENT])
    for index, flags in enumerate([None, True, 3.5, "invalid"]):
        add("legacy-invalid-flags-" + str(index), [dict(VELOCITY, flags=flags), MOVEMENT])
    result.extend(sine_cases())
    return result


def sine_cases():
    result = []

    def add(name, operators, times, **kwargs):
        steps = [{"advance": .125, "sceneTime": time} for time in times]
        entry = dict(fixture(operators, steps=steps, **kwargs), name=name)
        entry["definition"]["initializer"].append({"name": "alpharandom", "min": .625, "max": .625})
        result.append(entry)
        return entry

    unit_times = [0, .25, .5, .75, 1, 1.5]
    add("sine-defaults", [SINE], unit_times)
    add("sine-explicit", [dict(SINE, flags=0, operation="multiply", transforminputscale=2,
                              inputrangemin=0, inputrangemax=1, outputrangemin=0, outputrangemax=1)],
        unit_times)
    ranged = dict(SINE, operation="remap", inputrangemin=2, inputrangemax=6,
                  outputrangemin=.25, outputrangemax=.75)
    range_times = [2, 3, 4, 6, 8, 0]
    add("sine-range", [ranged], range_times)
    add("sine-zero-scale", [dict(ranged, transforminputscale=0)], range_times)
    add("sine-negative-scale", [dict(ranged, transforminputscale=-1)], range_times)
    renamed = add("sine-renamed", [dict(ranged, id=912)], range_times)
    renamed["definition"]["material"] = "materials/renamed-wave.json"
    linear = dict(ranged)
    del linear["transformfunction"]
    add("time-linear", [linear], [0, 2, 3, 4, 6, 8])

    peer = {"name": "alphachange", "startvalue": .5, "endvalue": .5}
    assignment = dict(SINE, operation="remap")
    add("sine-multiply-current", [peer, SINE], [.25])
    add("sine-assign-current", [peer, assignment], [.25])
    add("sine-assign-before-peer", [assignment, peer], [.25])
    add("sine-lifecycle", [peer, dict(assignment, blendinstart=0, blendinend=.5)], [.25] * 5, lifetime=1)
    add("sine-alpha-overflow", [peer, dict(assignment, outputrangemin=.25, outputrangemax=4e38)], [0, .5, 0])

    clock = add("sine-clock", [assignment], [.25, .25, .5], count=2)
    first = dict(clock["definition"]["emitter"][0], instantaneous=1)
    clock["definition"]["emitter"] = [first, dict(first, delay=.1875)]
    clock["steps"][1]["advance"] = .25
    warm = dict(copy.deepcopy(clock), name="sine-clock-prewarm", instanceOverride={"rate": 2},
                initialSceneTime=.25, steps=[{}, {"advance": .25, "sceneTime": .5}])
    warm["definition"]["starttime"] = .375
    result.append(warm)

    for field, value in [("input", "unknown-clock"), ("output", "unsupported-channel"),
                         ("inputrangemin", "0 0 0"), ("flags", 7)]:
        add(f"sine-invalid-{field}", [dict(SINE, **{field: value}), peer, MOVEMENT], [.5])
    return result


class SceneParticleScalarSpeedRemapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("swiftc")
        if compiler is None:
            raise unittest.SkipTest("requires Swift")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-scalar-speed-remap-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        harness, fixture_file, binary = directory / "Harness.swift", directory / "cases.json", directory / "remap"
        harness.write_text(HARNESS)
        fixture_file.write_text(json.dumps(cases()))
        sources = list(SWIFT_SOURCES)
        override = os.environ.get("MWX_SCENE_SPEED_REMAP_SIMULATOR_SOURCE")
        if override:
            selected = Path(override).resolve(strict=True)
            sources = [selected if source.name == "SceneParticleSimulator.swift" else source for source in sources]
        compiled = subprocess.run([compiler, "-D", "DEBUG", *map(str, sources), str(harness), "-o", str(binary)],
                                  capture_output=True, text=True, timeout=120)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary), str(fixture_file)], check=True,
                                   capture_output=True, text=True, timeout=30)
        cls.result = json.loads(completed.stdout)
        # Bind persisted test output to the actual product files used by this run.
        print("Scalar Remap CPU identity: " + json.dumps({
            str(source): hashlib.sha256(source.read_bytes()).hexdigest()
            for source in sources if source.name in {
                "SceneParticleRemapValue.swift", "SceneParticleOscillationCache.swift",
                "SceneParticleSimulator.swift", "SceneParticleSimulationSupport.swift",
                "SceneParticleSimulationDiagnostic.swift"}}, sort_keys=True))

    def assert_vector(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for value, target in zip(actual, expected):
            self.assertAlmostEqual(value, target, places=8)

    def state(self, name, index=0):
        return self.result[name][index]

    def test_actual_rain_shape_executes_both_noise_writers(self):
        rain = self.state("rain-shape")
        without_speed = self.state("rain-without-speed")
        self.assertNotEqual(rain["velocity"], without_speed["velocity"])
        self.assertNotEqual(rain["position"], without_speed["position"])
        self.assertTrue(rain["gpuFinite"])
        self.assertNotIn("remapValueUnsupported", [entry["kind"] for entry in rain["diagnostics"]])

    def test_default_multiply_clamps_after_mapping_and_keeps_vector_direction(self):
        for factor in [-0.5, 0, 0.5, 2]:
            with self.subTest(mapped=factor):
                multiplier = min(max(factor, 0), 1)
                state = self.state("constant-" + str(factor))
                self.assert_vector(state["velocity"][0], [2 * multiplier, -4 * multiplier, 6 * multiplier])
                self.assert_vector(state["position"][0], [0.25 * multiplier, -0.5 * multiplier, 0.75 * multiplier])
        self.assertEqual(self.state("explicit-multiply"), self.state("constant-0.5"))
        for index in range(4):
            self.assertEqual(self.state("valid-scalar-shape-" + str(index)),
                             self.state("constant-0.5"))
        self.assertEqual(self.state("valid-vector-array"), self.state("legacy-vector"))
        self.assert_vector(self.state("negative-vector")["velocity"][0], [-1, -2, -3])
        self.assert_vector(self.state("zero-vector")["velocity"][0], [0, 0, 0])
        near = self.state("near-float-limit")
        self.assertEqual(near["velocity"][0], [1e38, 0.5, -1e38])
        self.assertTrue(near["gpuFinite"])

    def test_each_step_multiplies_current_velocity_in_authored_order(self):
        before, after = self.state("constant-0.5"), self.state("speed-after-movement")
        self.assertEqual(before["velocity"], after["velocity"])
        self.assert_vector(after["position"][0], [0.25, -0.5, 0.75])
        self.assert_vector(self.state("two-half-steps")["velocity"][0], [0.5, -1, 1.5])

    def test_partition_and_snapshot_replay_preserve_state_and_rng(self):
        self.assertEqual(self.state("rain-shape"), self.state("rain-split", -1))
        replay = self.result["rain-replay"]
        self.assertEqual(replay[1], replay[3])
        self.assertEqual(self.state("rain-shape")["randomState"], self.state("rain-without-speed")["randomState"])

    def test_project_fbm_varies_over_life_without_seed_or_particle_lockstep(self):
        states = self.result["temporal-motion"]
        speeds = [state["velocity"][0][1] for state in states]
        peer = [state["velocity"][1][1] for state in states]
        self.assertTrue(all(isinstance(value, (int, float)) and math.isfinite(value) and 0 <= value <= 20
                            for value in speeds + peer))
        self.assertGreater(max(speeds) - min(speeds), 2)
        self.assertNotEqual(speeds, peer)
        other = [state["velocity"][0][1] for state in self.result["temporal-other-seed"]]
        self.assertNotEqual(speeds, other)
        self.assertTrue(self.state("maximum-scale")["gpuFinite"])

    def test_unsupported_fields_flags_and_numbers_skip_only_target_operator(self):
        names = [name for name in self.result if name.startswith(("invalid-", "missing-"))]
        for name in names:
            with self.subTest(case=name):
                state = self.state(name)
                self.assert_vector(state["velocity"][0], [2, -4, 6])
                self.assert_vector(state["position"][0], [0.25, -0.5, 0.75])
                self.assertIn("remapValueUnsupported", [entry["kind"] for entry in state["diagnostics"]])
                self.assertTrue(state["gpuFinite"])
        peer, baseline = self.state("unsupported-with-healthy-peer"), self.state("legacy-vector")
        self.assertEqual(peer["velocity"], baseline["velocity"])
        self.assertEqual(peer["position"], baseline["position"])
        for name in self.result:
            if name == "legacy-explicit-flags0" or name.startswith("legacy-invalid-flags-"):
                with self.subTest(case=name):
                    self.assert_vector(self.state(name)["velocity"][0], [2, -4, 6])

    def test_sine_defaults_explicit_ranges_scale_and_renamed_operator(self):
        for name, expected in {
            "sine-defaults": [0, .3125, .625, .3125, 0, .625],
            "sine-explicit": [0, .3125, .625, .3125, 0, .625],
            "sine-range": [.25, .5, .75, .25, .75, .75],
            "sine-zero-scale": [.25] * 6,
            "sine-negative-scale": [.25, .3232233047033631, .5, .75, .5, .5],
            "time-linear": [0, .25, .375, .5, .75, 1],
        }.items():
            with self.subTest(case=name):
                self.assert_vector([state["alpha"][0] for state in self.result[name]], expected)
        self.assertEqual(self.result["sine-renamed"], self.result["sine-range"])

    def test_sine_applies_authored_order_and_blends_current_alpha_with_result(self):
        for name, alpha in [("sine-multiply-current", .15625), ("sine-assign-current", .5),
                            ("sine-assign-before-peer", .25)]:
            with self.subTest(case=name):
                self.assert_vector(self.state(name)["alpha"], [alpha])
        self.assert_vector([state["alpha"][0] for state in self.result["sine-lifecycle"]],
                           [.3125, .359375, .40625, .453125, .5])
        self.assert_vector([state["alpha"][0] for state in self.result["sine-alpha-overflow"]],
                           [.25, .3125, .25])

    def test_sine_consumes_frame_timing_with_different_particle_ages_and_rates(self):
        first, middle, updated = self.result["sine-clock"]
        prepared, handoff = self.result["sine-clock-prewarm"]
        self.assertEqual(first["ages"], [0])
        for state in (middle, prepared):
            self.assertEqual((state["time"], state["ages"]), (.375, [.25, .125]))
        self.assertEqual((updated["time"], updated["ages"]), (.5, [.375, .25]))
        self.assertEqual((handoff["time"], handoff["ages"]), (.875, [.75, .625]))
        self.assert_vector(first["alpha"], [.5])
        for state in (middle, prepared):
            self.assert_vector(state["alpha"], [.5, .5])
        self.assert_vector(updated["alpha"], [1, 1])
        self.assert_vector(handoff["alpha"], [1, 1])

    def test_unsupported_sine_fields_only_skip_the_remap(self):
        for name in self.result:
            if name.startswith("sine-invalid-"):
                with self.subTest(case=name):
                    state = self.state(name)
                    self.assert_vector(state["alpha"], [.3125])
                    self.assert_vector(state["position"][0], [.25, -.5, .75])
                    self.assertIn("remapValueUnsupported", [entry["kind"] for entry in state["diagnostics"]])


if __name__ == "__main__":
    unittest.main()
