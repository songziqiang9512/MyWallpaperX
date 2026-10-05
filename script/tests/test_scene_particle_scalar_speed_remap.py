"""Rain scalar Remap through real preparation and fixed-step simulation.

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

from .test_scene_particle_audio_response import SWIFT_SOURCES

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
        for item in cases {
            let definition = SceneParticleDefinitionParser().parse(root: item["definition"] as! [String: Any])
            let plans = definition.operators.map { SceneParticleOperatorExecutionPlan($0, definition: definition) }
            let simulator = SceneParticleSimulator(definition: definition,
                seed: (item["seed"] as? NSNumber)?.uint64Value ?? 81, fixedTimeStep: 0.125)
            var states: [[String: Any]] = []
            var snapshots: [String: SceneParticleSimulator.FrameSnapshot] = [:]
            for step in item["steps"] as! [[String: Any]] {
                if let key = step["restore"] as? String { simulator.restoreFrame(snapshots[key]!) }
                if let duration = step["advance"] as? Double { simulator.advance(by: duration) }
                if let key = step["save"] as? String { snapshots[key] = simulator.frameSnapshot() }
                states.append(observe(simulator))
            }
            var entry: [String: Any] = [
                "scalarAdmission": plans.map { $0.scalarSpeedRemap != nil },
                "velocityAdmission": plans.map { $0.velocityRemap != nil },
                "states": states,
            ]
            if let plan = plans.compactMap(\.scalarSpeedRemap).first {
                entry["preparedScalar"] = [plan.minimum, plan.maximum, plan.inputScale]
                let probes = (0...64).map { Double($0) / 64 }
                func coefficients(seed: UInt64, particleID: UInt64) -> [Any] {
                    probes.map { life in
                        SceneParticleSimulationMath.scalarSpeedRemapMultiplier(plan,
                            normalizedLife: life, particleID: particleID, simulationSeed: seed)
                            .map(number) ?? NSNull()
                    }
                }
                entry["coefficients"] = coefficients(seed: 81, particleID: 0)
                entry["repeatCoefficients"] = coefficients(seed: 81, particleID: 0)
                entry["otherSeedCoefficients"] = coefficients(seed: 82, particleID: 0)
                entry["otherParticleCoefficients"] = coefficients(seed: 81, particleID: 1)
            }
            results[item["name"] as! String] = entry
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
        compiled = subprocess.run([compiler, *map(str, sources), str(harness), "-o", str(binary)],
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
        return self.result[name]["states"][index]

    def test_actual_rain_shape_enters_exact_prepared_scalar_plan(self):
        rain = self.result["rain-shape"]
        self.assertEqual(rain["scalarAdmission"], [False, False, True, False])
        self.assertEqual(rain["velocityAdmission"], [False, True, False, False])
        self.assertEqual(rain["preparedScalar"], [-5, 7, 8])
        self.assertTrue(self.state("rain-shape")["gpuFinite"])

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
        replay = self.result["rain-replay"]["states"]
        self.assertEqual(replay[1], replay[3])
        self.assertEqual(self.state("rain-shape")["randomState"], self.state("rain-without-speed")["randomState"])

    def test_project_fbm_varies_over_life_without_seed_or_particle_lockstep(self):
        rain = self.result["rain-shape"]
        values = rain["coefficients"]
        self.assertTrue(all(isinstance(value, (int, float)) and math.isfinite(value) and 0 <= value <= 1
                            for value in values))
        self.assertGreater(max(values) - min(values), 0.1)
        self.assertEqual(values, rain["repeatCoefficients"])
        self.assertNotEqual(values, rain["otherSeedCoefficients"])
        self.assertNotEqual(values, rain["otherParticleCoefficients"])
        states = self.result["temporal-motion"]["states"]
        speeds = [state["velocity"][0][1] for state in states]
        peer = [state["velocity"][1][1] for state in states]
        self.assertGreater(max(speeds) - min(speeds), 1)
        self.assertNotEqual(speeds, peer)
        other = [state["velocity"][0][1] for state in self.result["temporal-other-seed"]["states"]]
        self.assertNotEqual(speeds, other)
        self.assertTrue(self.state("maximum-scale")["gpuFinite"])

    def test_unsupported_fields_flags_and_numbers_skip_only_target_operator(self):
        names = [name for name in self.result if name.startswith(("invalid-", "missing-"))]
        for name in names:
            with self.subTest(case=name):
                self.assertFalse(any(self.result[name]["scalarAdmission"]))
                state = self.state(name)
                self.assert_vector(state["velocity"][0], [2, -4, 6])
                self.assert_vector(state["position"][0], [0.25, -0.5, 0.75])
                self.assertIn("remapValueUnsupported", [entry["kind"] for entry in state["diagnostics"]])
                self.assertTrue(state["gpuFinite"])
        peer, baseline = self.state("unsupported-with-healthy-peer"), self.state("legacy-vector")
        self.assertEqual(peer["velocity"], baseline["velocity"])
        self.assertEqual(peer["position"], baseline["position"])
        self.assertFalse(any(self.result["legacy-explicit-flags0"]["velocityAdmission"]))
        for name in self.result:
            if name.startswith("legacy-invalid-flags-"):
                with self.subTest(case=name):
                    self.assertFalse(any(self.result[name]["velocityAdmission"]))
                    self.assert_vector(self.state(name)["velocity"][0], [2, -4, 6])


if __name__ == "__main__":
    unittest.main()
