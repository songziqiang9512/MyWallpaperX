#!/usr/bin/env python3
"""Authored turbulent forward magnitude through real parse, birth and simulation.

CPU-only Swift execution. MWX_SCENE_TURBULENT_FORWARD_SOURCE may select a frozen
before version of SceneParticleSimulationSupport.swift for a red/green run.
This does not claim angular/noise parity or Metal card geometry.
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
    static func make(_ forward: String, count: Int = 1) throws
        -> (SceneParticleSimulator, SceneParticleTrailRenderPlan) {
        let authored: [String: Any] = [
            "material": "owned.json", "maxcount": count, "starttime": 0, "flags": 0,
            "emitter": [["name": "boxrandom", "rate": 0, "instantaneous": count,
                         "distancemin": "0 0 0", "distancemax": "0 0 0"]],
            "initializer": [
                ["name": "lifetimerandom", "min": 8, "max": 8],
                ["name": "sizerandom", "min": 32, "max": 32],
                ["name": "turbulentvelocityrandom", "forward": forward,
                 "right": "0 0 1", "scale": 0, "offset": 0,
                 "phasemin": 0, "phasemax": 0, "timescale": 0,
                 "speedmin": 10, "speedmax": 10]],
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
            fixedTimeStep: 0.125, trailHistoryCapacity: SceneParticleTrailRenderPlan.historySampleCapacity)
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
         "historyCount": sim.trailDirectionSamples().count,
         "nextID": sim.frameSnapshot().nextParticleID,
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
        let payload: [String: Any] = ["cases": cases,
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
                self.assertEqual(case["after"]["historyCount"], 1)
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


if __name__ == "__main__":
    unittest.main()
