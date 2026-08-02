#!/usr/bin/env python3
"""Bounded particle audio response execution gate."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DEBUG_FIXTURE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner+AudioSpectrum.swift"
)
BENCHMARK_SOURCE = REPOSITORY_ROOT / "script/scene_wallpaper_benchmark.py"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleInitializer.swift",
    SOURCE_ROOT / "Particles/SceneParticleAudioResponsePlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleVortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+Operator.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    SOURCE_ROOT / "Particles/SceneParticleWorldSpacePlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleBoids.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationDiagnostic.swift",
    SOURCE_ROOT / "Particles/SceneParticleControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+ControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Boids.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+AudioResponse.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Vortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleCapVelocity.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+CapVelocity.swift",
    SOURCE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
    SOURCE_ROOT / "Particles/SceneParticleLayerImageEmissionMap.swift",
    SOURCE_ROOT / "Particles/SceneParticleOscillationCache.swift",
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Initializer.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Random.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+InstanceOverride.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",
]

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let silence = SceneParticleAudioInput.silent
        let active = SceneParticleAudioInput(
            left: Array(repeating: 1, count: 16),
            right: Array(repeating: 1, count: 16)
        )
        let asymmetric = SceneParticleAudioInput(
            left: [0.5, 1] + Array(repeating: 0, count: 14),
            right: Array(repeating: 0, count: 16)
        )

        let leftPlan = plan(mode: 1, bounds: .vector([0, 1]), exponent: 2)
        let rightPlan = plan(mode: 2, bounds: .vector([0, 1]), exponent: 2)
        let centerPlan = plan(mode: 3, bounds: .vector([0, 1]), exponent: 2)

        var silentEmitter = simulator(emitterJSON, seed: 1, step: 0.1)
        var activeEmitter = simulator(emitterJSON, seed: 1, step: 0.1)
        var partitionedEmitter = simulator(emitterJSON, seed: 1, step: 0.1)
        silentEmitter.advance(by: 1, audioInput: silence)
        activeEmitter.advance(by: 1, audioInput: active)
        partitionedEmitter.advance(by: 0.4, audioInput: active)
        partitionedEmitter.advance(by: 0.6, audioInput: active)

        var authorOffEmitter = simulator(authorOffEmitterJSON, seed: 1, step: 0.1)
        authorOffEmitter.advance(by: 1, audioInput: silence)
        var invalidEmitter = simulator(invalidEmitterJSON, seed: 1, step: 0.1)
        invalidEmitter.advance(by: 1, audioInput: active)

        var silentInitializer = simulator(turbulentInitializerJSON, seed: 7, step: 0.1)
        var activeInitializer = simulator(turbulentInitializerJSON, seed: 7, step: 0.1)
        silentInitializer.advance(by: 0.1, audioInput: silence)
        activeInitializer.advance(by: 0.1, audioInput: active)
        var zeroPhaseSilent = simulator(zeroPhaseInitializerJSON, seed: 7, step: 0.1)
        var zeroPhaseActive = simulator(zeroPhaseInitializerJSON, seed: 7, step: 0.1)
        zeroPhaseSilent.advance(by: 0.1, audioInput: silence)
        zeroPhaseActive.advance(by: 0.1, audioInput: active)

        var silentTurbulence = simulator(turbulenceJSON, seed: 9, step: 0.1)
        var activeTurbulence = simulator(turbulenceJSON, seed: 9, step: 0.1)
        silentTurbulence.advance(by: 0.1, audioInput: silence)
        activeTurbulence.advance(by: 0.1, audioInput: active)

        var silentVortex = simulator(vortexJSON, seed: 11, step: 1)
        var activeVortex = simulator(vortexJSON, seed: 11, step: 1)
        silentVortex.advance(by: 1, audioInput: silence)
        activeVortex.advance(by: 1, audioInput: active)

        let payload: [String: Any] = [
            "leftResponse": leftPlan.evaluate(asymmetric),
            "rightResponse": rightPlan.evaluate(asymmetric),
            "centerResponse": centerPlan.evaluate(asymmetric),
            "invalidPlans": invalidPlans(),
            "silentEmitterCount": silentEmitter.particles.count,
            "activeEmitterCount": activeEmitter.particles.count,
            "emitterPartitioned": activeEmitter.particles == partitionedEmitter.particles,
            "authorOffEmitterCount": authorOffEmitter.particles.count,
            "invalidEmitterCount": invalidEmitter.particles.count,
            "invalidEmitterDiagnostics": invalidEmitter.diagnostics.map(\.kind.rawValue),
            "initializerSilent": vector(silentInitializer.particles[0].velocity),
            "initializerActive": vector(activeInitializer.particles[0].velocity),
            "zeroPhaseStable": zeroPhaseSilent.particles == zeroPhaseActive.particles,
            "turbulenceSilent": vector(silentTurbulence.particles[0].velocity),
            "turbulenceActive": vector(activeTurbulence.particles[0].velocity),
            "vortexSilent": vector(silentVortex.particles[0].velocity),
            "vortexActive": vector(activeVortex.particles[0].velocity),
            "vortexDiagnostics": activeVortex.diagnostics.map(\.kind.rawValue).sorted(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func plan(
        mode: Int,
        bounds: SceneParticleNumericValue?,
        exponent: Double,
        start: Int? = nil,
        end: Int? = nil
    ) -> SceneParticleAudioResponsePlan {
        SceneParticleAudioResponsePlan(.init(
            mode: mode, bounds: bounds, exponent: exponent,
            frequencyStart: start, frequencyEnd: end
        ))!
    }

    private static func invalidPlans() -> [Bool] {
        [
            SceneParticleAudioResponse(mode: 9, bounds: nil, exponent: nil,
                frequencyStart: nil, frequencyEnd: nil),
            SceneParticleAudioResponse(mode: 1, bounds: .vector([1, 0]), exponent: nil,
                frequencyStart: nil, frequencyEnd: nil),
            SceneParticleAudioResponse(mode: 1, bounds: nil, exponent: -1,
                frequencyStart: nil, frequencyEnd: nil),
            SceneParticleAudioResponse(mode: 1, bounds: nil, exponent: nil,
                frequencyStart: 0, frequencyEnd: 16),
        ].map { SceneParticleAudioResponsePlan($0) == nil }
    }

    private static func simulator(
        _ source: String, seed: UInt64, step: Double
    ) -> SceneParticleSimulator {
        let root = try! JSONSerialization.jsonObject(
            with: Data(source.utf8)
        ) as! [String: Any]
        return SceneParticleSimulator(
            definition: SceneParticleDefinitionParser().parse(root: root),
            seed: seed,
            fixedTimeStep: step
        )
    }

    private static func vector(_ value: SIMD3<Double>) -> [Double] {
        [value.x, value.y, value.z]
    }

    private static let emitterJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[{"name":"boxrandom","rate":60,"distancemax":0,"audioprocessingmode":3}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#
    private static let authorOffEmitterJSON = emitterJSON.replacingOccurrences(
        of: #""audioprocessingmode":3"#, with: #""audioprocessingmode":0"#
    )
    private static let invalidEmitterJSON = emitterJSON.replacingOccurrences(
        of: #""audioprocessingmode":3"#, with: #""audioprocessingmode":9"#
    )
    private static let turbulentInitializerJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemax":0}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"turbulentvelocityrandom","forward":"0 1 0","right":"1 0 0","phasemin":0.7,"phasemax":0.7,"scale":0.2,"speedmin":25,"speedmax":25,"audioprocessingmode":3}],
     "renderer":[{"name":"sprite"}]}
    """#
    private static let zeroPhaseInitializerJSON = turbulentInitializerJSON
        .replacingOccurrences(of: #""phasemin":0.7,"phasemax":0.7"#,
                              with: #""phasemin":0,"phasemax":0"#)
    private static let turbulenceJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemax":0}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1 1 0","scale":0.02,"speedmin":25,"speedmax":25,"phasemin":1,"phasemax":1,"timescale":0,"audioprocessingmode":3}],
     "renderer":[{"name":"sprite"}]}
    """#
    private static let vortexJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"directions":"1 1 1","distancemin":"10 0 0","distancemax":"10 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "operator":[{"name":"vortex","axis":"0 0 1","distanceinner":0,"distanceouter":10,"speedinner":0,"speedouter":100,"audioprocessingmode":3}],
     "renderer":[{"name":"sprite"}]}
    """#
}
'''


class SceneParticleAudioResponseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-particle-audio-response-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        binary = directory / "scene-particle-audio-response"
        compilation = subprocess.run(
            ["/usr/bin/swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_channel_mean_bounds_and_exponent_are_bounded(self) -> None:
        self.assertAlmostEqual(self.result["leftResponse"], 0.5625)
        self.assertEqual(self.result["rightResponse"], 0)
        self.assertAlmostEqual(self.result["centerResponse"], 0.140625)
        self.assertEqual(self.result["invalidPlans"], [True] * 4)

    def test_emitter_is_silent_without_audio_and_partition_stable(self) -> None:
        self.assertEqual(self.result["silentEmitterCount"], 0)
        self.assertEqual(self.result["activeEmitterCount"], 60)
        self.assertTrue(self.result["emitterPartitioned"])
        self.assertEqual(self.result["authorOffEmitterCount"], 60)
        self.assertEqual(self.result["invalidEmitterCount"], 0)
        self.assertIn("audioResponseIgnored", self.result["invalidEmitterDiagnostics"])

    def test_phase_consumers_change_only_for_nonzero_response(self) -> None:
        self.assertNotEqual(self.result["initializerSilent"], self.result["initializerActive"])
        self.assertTrue(self.result["zeroPhaseStable"])
        self.assertNotEqual(self.result["turbulenceSilent"], self.result["turbulenceActive"])

    def test_vortex_speed_tracks_audio_and_stops_on_silence(self) -> None:
        self.assertEqual(self.result["vortexSilent"], [0, 0, 0])
        self.assertEqual(self.result["vortexActive"], [0, 100, 0])
        self.assertIn("audioResponseBounded", self.result["vortexDiagnostics"])
        self.assertIn("vortexBounded", self.result["vortexDiagnostics"])

    def test_isolated_runtime_fixture_reuses_the_shared_inbox(self) -> None:
        source = DEBUG_FIXTURE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("SceneAudioSpectrumInbox.shared.publish", source)
        self.assertIn("leftValue", source)
        self.assertIn("rightValue", source)
        self.assertIn("frame.isMultiple(of: 2)", source)
        self.assertIn(
            '--mwx-debug-scene-audio-spectrum-fixture',
            BENCHMARK_SOURCE.read_text(encoding="utf-8"),
        )


if __name__ == "__main__":
    unittest.main()
