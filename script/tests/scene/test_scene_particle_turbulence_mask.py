#!/usr/bin/env python3
"""Exercise the prepared spatial force through the real simulator and particle buffer."""
from __future__ import annotations

import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene.test_scene_particle_turbulent_forward import PARTICLE_SOURCES


HARNESS = r'''
import Foundation

@main enum Harness {
    static let step = 0.125

    static func make(_ mask: Any, phase: Double = 0.3, speed: Double = 24,
                     initial: String = "3 -2 1", count: Int = 1,
                     movement: Bool = false, movementFirst: Bool = false,
                     randomRanges: Bool = false, spaceScale: Double = 0.002,
                     origin: String = "128 42 -19", phaseMax: Double? = nil) throws -> SceneParticleSimulator {
        let turbulence: [String: Any] = [
            "name": "turbulence", "mask": mask, "scale": spaceScale, "timescale": 0,
            "phasemin": phase, "phasemax": phaseMax ?? (randomRanges ? phase + 0.9 : phase),
            "speedmin": speed, "speedmax": randomRanges ? speed * 2 : speed]
        let move: [String: Any] = ["name": "movement", "flags": 0,
                                  "gravity": "0 0 0", "drag": 0]
        let operators = movement
            ? (movementFirst ? [move, turbulence] : [turbulence, move]) : [turbulence]
        let authored: [String: Any] = [
            "material": "owned.json", "maxcount": count, "starttime": 0, "flags": 0,
            "emitter": [["name": "boxrandom", "rate": 0, "instantaneous": count,
                         "distancemin": "0 0 0", "distancemax": "0 0 0", "origin": origin]],
            "initializer": [["name": "lifetimerandom", "min": 8, "max": 8],
                            ["name": "velocityrandom", "min": initial, "max": initial]],
            "operator": operators]
        let data = try JSONSerialization.data(withJSONObject: authored)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let definition = SceneParticleDefinitionParser().parse(root: root)
        guard definition.operators.contains(where: { $0.kind == .turbulence }) else {
            throw NSError(domain: "owned-operator-not-parsed", code: 1)
        }
        return SceneParticleSimulator(definition: definition, seed: 81, fixedTimeStep: step)
    }

    static func vector(_ value: SIMD3<Double>) -> [Double] { [value.x, value.y, value.z] }

    static func observe(_ sim: SceneParticleSimulator) -> [String: Any] {
        let state = sim.frameSnapshot()
        var value: [String: Any] = ["ids": sim.particles.map(\.id), "count": sim.particles.count,
                "velocities": sim.particles.map { vector($0.velocity) },
                "positions": sim.particles.map { vector($0.position) },
                "ages": sim.particles.map(\.age), "time": sim.simulationTime,
                "randomState": state.random.state, "nextID": state.nextParticleID,
                "gpuFinite": sim.particles.allSatisfy {
                    SceneParticleSimulationMath.isGPUFinite($0.velocity)
                        && SceneParticleSimulationMath.isGPUFinite($0.position) }]
#if DEBUG
        value["diagnostics"] = sim.diagnostics.map(\.kind.rawValue)
#endif
        return value
    }

    static func run(_ mask: Any, initial: String = "3 -2 1", steps: Int = 1,
                    movement: Bool = false, movementFirst: Bool = false,
                    randomRanges: Bool = false, count: Int = 1) throws -> [String: Any] {
        let sim = try make(mask, initial: initial, count: count, movement: movement,
                           movementFirst: movementFirst, randomRanges: randomRanges)
        sim.advance(by: step)
        let first = observe(sim)
        for _ in 1..<steps { sim.advance(by: step) }
        return ["first": first, "final": observe(sim)]
    }

    static func main() throws {
        var output: [String: Any] = [:]
        output["unit"] = try run(1.0)
        output["quarter"] = try run(0.25)
        output["double"] = try run(2.0)
        output["axes"] = try run("2 0.25 1")
        output["zeroAxis"] = try run("0 1 1")
        output["negative"] = try run("-1 -0.5 1")
        output["zero"] = try run("0 0 0")
        output["unitMotion"] = try run(1.0, initial: "0 0 0", steps: 8, movement: true)
        output["quarterMotion"] = try run(0.25, initial: "0 0 0", steps: 8, movement: true)
        output["doubleMotion"] = try run(2.0, initial: "0 0 0", steps: 8, movement: true)
        output["movementFirst"] = try run(1.0, initial: "0 0 0", movement: true, movementFirst: true)
        output["randomUnit"] = try run(1.0, initial: "0 0 0", randomRanges: true, count: 3)
        output["randomQuarter"] = try run(0.25, initial: "0 0 0", randomRanges: true, count: 3)

        let noSpace = try make("1 0 0", spaceScale: 0)
        let explicitZeroPhase = try make("1 0 0", phase: 0)
        let explicitNonzeroPhase = try make("1 0 0", phase: 2.5)
        let shiftedSpan = try make("1 0 0", phase: 2, phaseMax: 3)
        let baseSpan = try make("1 0 0", phase: 0, phaseMax: 1)
        let negativeSpace = try make("1 0 0", spaceScale: -0.002, origin: "128 0 0")
        let lowCadence = try make("1 0 0", phase: 0)
        for system in [noSpace, explicitZeroPhase, explicitNonzeroPhase, shiftedSpan, baseSpan, negativeSpace] {
            system.advance(by: step)
        }
        lowCadence.advance(by: step, timing: .init(turbulenceForceFactor: 0.7))
        output["forceInvariants"] = ["zeroSpace": observe(noSpace), "fixedZero": observe(explicitZeroPhase),
            "fixedNonzero": observe(explicitNonzeroPhase), "shiftedSpan": observe(shiftedSpan),
            "baseSpan": observe(baseSpan), "negativeSpace": observe(negativeSpace), "lowCadence": observe(lowCadence)]

        // Both the old velocity and the masked force increment fit Float.
        // Only their sum on particle 0 is unsafe. Particle 1 shares the actual
        // parsed operator, field position, time, phase and speed but starts at
        // zero, so its safe update must continue. Nonzero Z witnesses that
        // rejection must keep the whole prior vector, not only its X axis.
        let control = try make("1 1 1", phase: 0, speed: 16, initial: "0 0 0", count: 2)
        control.advance(by: step)
        let unitDelta = control.particles[0].velocity
        let mask = 1.5e38 / unitDelta.x
        let expectedDelta = unitDelta * SIMD3(mask, 1, 1)
        let unsafe = try make("\(mask) 1 1", phase: 0, speed: 16, initial: "0 0 0", count: 2)
        unsafe.advance(by: step)
        let prior = SIMD3(2.5e38, 7.0, 9.0)
        var state = unsafe.frameSnapshot()
        state.particles[0].velocity = prior
        state.particles[1].velocity = .zero
        unsafe.restoreFrame(state)
        let before = observe(unsafe)
        unsafe.advance(by: step)
        output["overflow"] = ["before": before, "after": observe(unsafe),
            "prior": vector(prior), "expectedSafeDelta": vector(expectedDelta),
            "priorAndDeltaFloatFinite": SceneParticleSimulationMath.isGPUFinite(prior)
                && SceneParticleSimulationMath.isGPUFinite(expectedDelta),
            "unsafeSumRejectedByFloat": !Float(prior.x + expectedDelta.x).isFinite,
            "otherAxisWouldChange": abs(expectedDelta.z) > 1e-6]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneParticleTurbulenceMaskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("swiftc")
        if compiler is None:
            raise unittest.SkipTest("requires Swift")
        sources = list(PARTICLE_SOURCES)
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-turbulence-mask-")
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        results = {}
        for mode, flags in [("debug", ["-D", "DEBUG"]), ("release", [])]:
            binary = directory / ("turbulence-mask-" + mode)
            compiled = subprocess.run([compiler, "-O", *flags, *map(str, sources), str(harness),
                "-module-cache-path", str(directory / ("module-cache-" + mode)), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            if compiled.returncode:
                raise RuntimeError(compiled.stderr)
            completed = subprocess.run([str(binary)], check=True, capture_output=True,
                                       text=True, timeout=30)
            results[mode] = json.loads(completed.stdout)
        cls.result, cls.release_result = results["debug"], results["release"]

    def test_release_preserves_mask_sampling_particles_rng_and_operator_order(self):
        def without_reports(value):
            if isinstance(value, dict):
                return {key: without_reports(item) for key, item in value.items() if key != "diagnostics"}
            if isinstance(value, list):
                return [without_reports(item) for item in value]
            return value
        self.assertEqual(self.release_result, without_reports(self.result))

    def assert_vector(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for value, wanted in zip(actual, expected):
            self.assertTrue(math.isclose(value, wanted, rel_tol=1e-12, abs_tol=1e-11),
                            f"{actual} != {expected}")

    def delta(self, key):
        velocity = self.result[key]["first"]["velocities"][0]
        return [v - prior for v, prior in zip(velocity, [3, -2, 1])]

    def test_force_uses_position_signed_scale_and_phase_span(self):
        result = self.result["forceInvariants"]
        velocity = lambda key: result[key]["velocities"][0]
        self.assert_vector(velocity("zeroSpace"), [3, -2, 1])
        self.assert_vector(velocity("fixedZero"), velocity("fixedNonzero"))
        self.assert_vector(velocity("baseSpan"), velocity("shiftedSpan"))
        self.assertNotEqual(velocity("baseSpan"), velocity("fixedZero"))
        self.assertNotEqual(velocity("negativeSpace"), velocity("zeroSpace"))
        self.assertAlmostEqual(velocity("lowCadence")[0] - 3, (velocity("fixedZero")[0] - 3) * 0.7)

    def test_scalar_mask_scales_actual_operator_velocity_increment(self):
        unit = self.delta("unit")
        self.assertTrue(all(abs(value) > 1e-6 for value in unit))
        self.assert_vector(self.delta("quarter"), [v * 0.25 for v in unit])
        self.assert_vector(self.delta("double"), [v * 2 for v in unit])

    def test_per_axis_mask_projects_the_same_raw_field_without_renormalizing(self):
        unit = self.delta("unit")
        self.assert_vector(self.delta("axes"), [unit[0] * 2, unit[1] * 0.25, unit[2]])
        self.assert_vector(self.delta("zeroAxis"), [0, unit[1], unit[2]])

    def test_negative_mask_reverses_only_selected_axes_and_zero_preserves_prior(self):
        unit = self.delta("unit")
        self.assert_vector(self.delta("negative"), [-unit[0], -unit[1] * 0.5, unit[2]])
        self.assert_vector(self.result["zero"]["first"]["velocities"][0], [3, -2, 1])

    def test_spatial_feedback_changes_the_trajectory_after_the_first_step(self):
        unit = self.result["unitMotion"]["final"]
        origin = [128, 42, -19]
        self.assertGreater(sum((v - start) ** 2 for v, start in zip(unit["positions"][0], origin)), 0.01)
        for key, factor in (("quarterMotion", 0.25), ("doubleMotion", 2)):
            with self.subTest(mask=key):
                current = self.result[key]["final"]
                self.assertNotAlmostEqual(current["velocities"][0][0], unit["velocities"][0][0] * factor)
                self.assertEqual(self.result[key]["first"]["ages"], [0])
                self.assertEqual(current["ages"], [1 - .125])
                self.assertEqual(current["time"], 1)

    def test_seed_phase_particle_identity_and_authored_operator_order_are_preserved(self):
        unit = self.result["randomUnit"]["first"]
        quarter = self.result["randomQuarter"]["first"]
        self.assertEqual(unit["count"], 3)
        for key in ("ids", "ages", "time", "randomState", "nextID", "diagnostics"):
            self.assertEqual(unit[key], quarter[key])
        self.assertGreater(len({tuple(v) for v in unit["velocities"]}), 1)
        for actual, reference in zip(quarter["velocities"], unit["velocities"]):
            self.assert_vector(actual, [v * 0.25 for v in reference])
        first = self.result["movementFirst"]["first"]
        force_first = self.result["unitMotion"]["first"]
        self.assert_vector(first["velocities"][0], force_first["velocities"][0])
        self.assert_vector(first["positions"][0], [128, 42, -19])
        self.assertNotEqual(force_first["positions"][0], first["positions"][0])

    def test_float_sum_overflow_rejects_one_whole_velocity_and_keeps_safe_sibling(self):
        result = self.result["overflow"]
        self.assertTrue(result["priorAndDeltaFloatFinite"])
        self.assertTrue(result["unsafeSumRejectedByFloat"])
        self.assertTrue(result["otherAxisWouldChange"])
        before, after = result["before"], result["after"]
        self.assertEqual(before["count"], 2)
        self.assertEqual(after["count"], 2)
        self.assertEqual(after["ids"], before["ids"])
        self.assertEqual(after["randomState"], before["randomState"])
        self.assertEqual(after["nextID"], before["nextID"])
        self.assert_vector(after["velocities"][0], result["prior"])
        self.assert_vector(after["velocities"][1], result["expectedSafeDelta"])
        self.assertTrue(after["gpuFinite"])


if __name__ == "__main__":
    unittest.main()
