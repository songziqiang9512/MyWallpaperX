#!/usr/bin/env python3
"""Turbulent forward magnitude and axis rotation through actual birth/simulation.

CPU-only Swift execution. MWX_SCENE_TURBULENT_FORWARD_SOURCE may select a frozen
before version of SceneParticleSimulationSupport.swift for a red/green run.
This does not claim general noise/up parity or Metal card geometry.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_particle_audio_response import SWIFT_SOURCES as PARTICLE_SOURCES

SOURCE_ROOT = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene"
TRAIL_SOURCE = SOURCE_ROOT / "Systems/Particles/SceneParticleTrailRenderPlan.swift"

HARNESS = r'''
import Foundation

@main enum Harness {
    static func make(_ forward: String, normal: String = "0 0 1",
                     offset: Double = 0, speed: Double = 10, count: Int = 1) throws
        -> (SceneParticleSimulator, SceneParticleTrailRenderPlan) {
        let authored: [String: Any] = [
            "material": "owned.json", "maxcount": count, "starttime": 0, "flags": 0,
            "emitter": [["name": "boxrandom", "rate": 0, "instantaneous": count,
                         "distancemin": "0 0 0", "distancemax": "0 0 0"]],
            "initializer": [
                ["name": "lifetimerandom", "min": 8, "max": 8],
                ["name": "sizerandom", "min": 32, "max": 32],
                ["name": "turbulentvelocityrandom", "forward": forward,
                 "right": normal, "scale": 0, "offset": offset,
                 "phasemin": 0, "phasemax": 0, "timescale": 0,
                 "speedmin": speed, "speedmax": speed]],
            "operator": [["name": "movement", "flags": 0, "gravity": "0 0 0", "drag": 0]],
            "renderer": [["name": "spritetrail", "length": 0.007]]]
        // Exercise the same JSON representation accepted from authored files.
        let json = try JSONSerialization.data(withJSONObject: authored)
        let root = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let definition = SceneParticleDefinitionParser().parse(root: root)
        let renderer = definition.renderers[0]
        guard let trail = SceneParticleTrailRenderPlan(length: renderer.length,
            minimumLength: renderer.minimumLength, maximumLength: renderer.maximumLength,
            hasMalformedFields: renderer.hasMalformedFields) else {
            throw NSError(domain: "owned-trail-admission", code: 1)
        }
        let sim = SceneParticleSimulator(definition: definition, seed: 81,
            fixedTimeStep: 0.125)
        return (sim, trail)
    }

    static func vector(_ value: SIMD3<Double>) -> [Double] { [value.x, value.y, value.z] }

    static func observe(_ sim: SceneParticleSimulator, _ trail: SceneParticleTrailRenderPlan)
        -> [String: Any] {
        ["count": sim.particles.count, "time": sim.simulationTime,
         "ids": sim.particles.map(\.id), "ages": sim.particles.map(\.age),
         "velocities": sim.particles.map { vector($0.velocity) },
         "positions": sim.particles.map { vector($0.position) },
         "stretch": sim.particles.map { Double(trail.stretch(for: $0.velocity)) },
         "nextID": sim.frameSnapshot().nextParticleID,
         "randomState": sim.frameSnapshot().random.state,
         "gpuFinite": sim.particles.allSatisfy {
             SceneParticleSimulationMath.isGPUFinite($0.position)
                && SceneParticleSimulationMath.isGPUFinite($0.velocity) },
         "diagnostics": sim.diagnostics.map { ["kind": $0.kind.rawValue,
                                               "component": $0.componentName ?? ""] }]
    }

    static func main() throws {
        let inputs = ["0 1 0", "0 2 0", "0 20 0", "0 .5 0", "3 4 0"]
        var cases: [[String: Any]] = []
        for forward in inputs {
            let (sim, trail) = try make(forward)
            sim.advance(by: 0.125)
            let birth = observe(sim, trail)
            for _ in 1..<16 { sim.advance(by: 0.125) }
            let (repeatSim, _) = try make(forward)
            repeatSim.advance(by: 2)
            cases.append(["forward": forward, "birth": birth, "after": observe(sim, trail),
                "repeatSameSeed": sim.particles == repeatSim.particles
                    && sim.frameSnapshot().random.state == repeatSim.frameSnapshot().random.state])
        }
        // Both forward=1e38 and speed=10 fit the GPU scalar ABI individually;
        // their multiplied velocity exceeds it. Birth attempts must reach the
        // existing safety owner, rather than pass through an invalid parse.
        let (unsafe, unsafeTrail) = try make("0 1e38 0", count: 4)
        unsafe.advance(by: 2)
        let (peer, peerTrail) = try make("0 2 0", count: 4)
        peer.advance(by: 2)
        let axes: [(String, String, Double)] = [
            ("tilted-negative", "0 1 1", -0.5), ("tilted-positive", "0 1 1", 0.5),
            ("reversed-normal", "0 -1 -1", -0.5), ("scaled-normal", "0 10 10", -0.5),
            ("zero-offset", "0 1 1", 0), ("orthogonal", "0 0 1", -0.5)]
        var axisCases: [[String: Any]] = []
        for (name, normal, offset) in axes {
            let (sim, trail) = try make("0 2 0", normal: normal, offset: offset, speed: 40)
            sim.advance(by: 0.125)
            let birth = observe(sim, trail)
            for _ in 1..<16 { sim.advance(by: 0.125) }
            axisCases.append(["name": name, "birth": birth, "after": observe(sim, trail)])
        }
        func explicit(_ sim: SceneParticleSimulator) throws -> SceneParticleSimulator.PlaybackCandidate {
            try sim.preparePlaybackCandidate(commands: [(.init(layerID: 42, action: .emit,
                revision: 1, count: 1), .init())], charge: { _, _ in }, release: { _ in })
        }
        let (explicitPeer, _) = try make("0 2 0", offset: -0.5, speed: 40, count: 2)
        let positive = try explicit(explicitPeer)
        var invalidAxes: [[String: Any]] = []
        for normal in ["0 1 0", "0 0 0"] {
            let (sim, _) = try make("0 2 0", normal: normal, offset: -0.5, speed: 40, count: 2)
            let before = sim.frameSnapshot()
            var rejected = false
            do { _ = try explicit(sim) }
            catch SceneParticleEmissionFailure.unavailable { rejected = true }
            let after = sim.frameSnapshot()
            invalidAxes.append(["normal": normal, "rejected": rejected,
                "unchanged": after.particles == before.particles && after.random.state == before.random.state
                    && after.nextParticleID == before.nextParticleID && after.playback == before.playback
                    && after.simulationTime == before.simulationTime && after.diagnostics == before.diagnostics
                    && after.birthEvents == before.birthEvents])
        }
        let payload: [String: Any] = ["cases": cases, "axisCases": axisCases,
            "invalidAxes": invalidAxes, "explicitPositive": positive.state.particles.map { vector($0.velocity) },
            "overflowInputsIndividuallyFinite": Float(1e38).isFinite && Float(10).isFinite,
            "overflow": observe(unsafe, unsafeTrail), "safePeer": observe(peer, peerTrail)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneParticleTurbulentForwardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("swiftc")
        if compiler is None:
            raise unittest.SkipTest("requires Swift")
        sources = list(PARTICLE_SOURCES) + [TRAIL_SOURCE]
        override = os.environ.get("MWX_SCENE_TURBULENT_FORWARD_SOURCE")
        if override:
            selected = Path(override).resolve(strict=True)
            sources = [selected if source.name == "SceneParticleSimulationSupport.swift"
                       else source for source in sources]
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-particle-turbulent-forward-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS)
        binary = directory / "turbulent-forward"
        compiled = subprocess.run([compiler, *map(str, sources), str(harness), "-o", str(binary)],
                                  capture_output=True, text=True, timeout=120)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary)], check=True, capture_output=True,
                                   text=True, timeout=30)
        cls.result = json.loads(completed.stdout)

    def assert_vector(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for value, target in zip(actual, expected):
            self.assertAlmostEqual(value, target, places=8)

    def test_authored_magnitude_controls_birth_and_two_second_motion(self):
        expected = [[0, 10, 0], [0, 20, 0], [0, 200, 0], [0, 5, 0], [30, 40, 0]]
        self.assertEqual(len(self.result["cases"]), len(expected))
        for case, velocity in zip(self.result["cases"], expected):
            with self.subTest(forward=case["forward"]):
                birth, after = case["birth"], case["after"]
                self.assertEqual(birth["count"], 1)
                self.assertEqual(after["count"], 1)
                self.assert_vector(birth["velocities"][0], velocity)
                self.assert_vector(after["velocities"][0], velocity)
                self.assert_vector(birth["positions"][0], [value * .125 for value in velocity])
                self.assert_vector(after["positions"][0], [value * 2 for value in velocity])
                self.assertEqual(after["time"], 2)
                self.assertEqual(after["ages"], [2])
                self.assertTrue(after["gpuFinite"])
                self.assertEqual(after["ids"], birth["ids"])

    def test_actual_velocity_drives_trail_stretch_and_seed_is_repeatable(self):
        # Declared speed magnitudes 10,20,200,5,50 with authored length .007.
        expected = [.07, .14, 1.4, .035, .35]
        for case, stretch in zip(self.result["cases"], expected):
            with self.subTest(forward=case["forward"]):
                self.assertAlmostEqual(case["birth"]["stretch"][0], stretch, places=6)
                self.assertAlmostEqual(case["after"]["stretch"][0], stretch, places=6)
                self.assertTrue(case["repeatSameSeed"])

    def test_multiplied_float_overflow_rejects_births_and_safe_peer_survives(self):
        self.assertTrue(self.result["overflowInputsIndividuallyFinite"])
        bad, peer = self.result["overflow"], self.result["safePeer"]
        self.assertEqual(bad["count"], 0)
        self.assertEqual(bad["nextID"], 4, "all four births must reach actual initialization")
        self.assertIn({"kind": "invalidEmitterState", "component": "particle-initialization"},
                      bad["diagnostics"])
        self.assertEqual(peer["count"], 4)
        self.assertEqual(peer["nextID"], 4)
        self.assertTrue(peer["gpuFinite"])
        self.assertNotIn({"kind": "invalidEmitterState", "component": "particle-initialization"},
                         peer["diagnostics"])
        for position, velocity in zip(peer["positions"], peer["velocities"]):
            self.assert_vector(velocity, [0, 20, 0])
            self.assert_vector(position, [0, 40, 0])

    def test_non_orthogonal_axis_retains_parallel_component_and_magnitude(self):
        # Independent unit-axis rotation values, declared before product changes.
        # Black-box XY observations identify this bounded offset/zero-noise case;
        # Z is the explicit standard rotation contract, not an observed GPU value.
        positive_x = [27.12040395368359, 75.10330247561491, 4.89669752438509]
        negative_x = [-27.12040395368359, 75.10330247561491, 4.89669752438509]
        expected = [positive_x, negative_x, negative_x, positive_x, [0, 80, 0],
                    [38.35404308833624, 70.20660495122982, 0]]
        cases = self.result["axisCases"]
        self.assertEqual(len(cases), len(expected))
        random_states = set()
        for case, velocity in zip(cases, expected):
            with self.subTest(case=case["name"]):
                birth, after = case["birth"], case["after"]
                self.assertEqual(birth["count"], 1)
                self.assertEqual(after["count"], 1)
                self.assert_vector(birth["velocities"][0], velocity)
                self.assert_vector(after["velocities"][0], velocity)
                self.assert_vector(birth["positions"][0], [v * .125 for v in velocity])
                self.assert_vector(after["positions"][0], [v * 2 for v in velocity])
                self.assertAlmostEqual(sum(v * v for v in after["velocities"][0]), 6400, places=8)
                self.assertAlmostEqual(after["stretch"][0], .56, places=6)
                self.assertEqual(after["time"], 2)
                self.assertTrue(after["gpuFinite"])
                random_states.add(after["randomState"])
        self.assertEqual(len(random_states), 1, "axis changes preserve RNG consumption order")

    def test_parallel_and_zero_axes_reject_strict_birth_with_rollback(self):
        self.assertEqual(len(self.result["explicitPositive"]), 1)
        self.assert_vector(self.result["explicitPositive"][0], [38.35404308833624, 70.20660495122982, 0])
        self.assertEqual([case["normal"] for case in self.result["invalidAxes"]], ["0 1 0", "0 0 0"])
        for case in self.result["invalidAxes"]:
            with self.subTest(normal=case["normal"]):
                self.assertTrue(case["rejected"])
                self.assertTrue(case["unchanged"])


if __name__ == "__main__":
    unittest.main()
