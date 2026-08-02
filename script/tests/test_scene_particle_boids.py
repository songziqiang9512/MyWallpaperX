#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleVortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+Operator.swift",
    SOURCE_ROOT / "Particles/SceneParticleWorldSpacePlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleBoids.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationDiagnostic.swift",
    SOURCE_ROOT / "Particles/SceneParticleControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+ControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Boids.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Vortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleCapVelocity.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+CapVelocity.swift",
    SOURCE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
    SOURCE_ROOT / "Particles/SceneParticleLayerImageEmissionMap.swift",
    SOURCE_ROOT / "Particles/SceneParticleOscillationCache.swift",
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Random.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+InstanceOverride.swift",
]

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let accepted = simulate(operatorFields: acceptedFields)
        let reversed = simulate(operatorFields: acceptedFields, reversed: true)
        let rejected = [
            "separation": simulate(operatorFields: #""neighborthreshold":20,"separationfactor":1,"cohesionfactor":1,"alignmentfactor":2"#),
            "largeGroup": simulate(operatorFields: acceptedFields, maximumCount: 65),
            "malformed": simulate(operatorFields: #""neighborthreshold":20,"separationfactor":0,"cohesionfactor":1,"alignmentfactor":"bad""#),
            "unknownField": simulate(operatorFields: acceptedFields + #", "separationthreshold":5"#),
            "flags": simulate(operatorFields: acceptedFields + #", "flags":1"#),
            "audio": simulate(operatorFields: acceptedFields + #", "audioprocessingmode":1"#),
            "missingSeparation": simulate(operatorFields: #""neighborthreshold":20,"cohesionfactor":1,"alignmentfactor":2"#),
            "officialPreview": simulate(operatorFields: #""neighborthreshold":50,"separationfactor":25,"cohesionfactor":4"#, maximumCount: 250),
        ]
        let payload: [String: Any] = [
            "acceptedDiagnostics": diagnostics(accepted),
            "acceptedVelocities": velocities(accepted),
            "reversedVelocities": velocities(reversed),
            "rejected": rejected.mapValues { value in [
                "diagnostics": diagnostics(value),
                "velocities": velocities(value),
            ] },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static let acceptedFields = #""neighborthreshold":20,"separationfactor":0,"cohesionfactor":1,"alignmentfactor":2"#

    private static func simulate(
        operatorFields: String,
        maximumCount: Int = 3,
        reversed: Bool = false
    ) -> SceneParticleSimulator {
        let source = """
        {
          "material":"materials/test.json",
          "maxcount":\(maximumCount),
          "emitter":[{"name":"sphererandom","rate":0}],
          "operator":[{"name":"boids",\(operatorFields)}],
          "renderer":[{"name":"sprite"}]
        }
        """
        let data = source.data(using: .utf8)!
        let definition = try! SceneParticleDefinitionParser().parse(data: data)
        var simulator = SceneParticleSimulator(
            definition: definition,
            seed: 1,
            fixedTimeStep: 0.5
        )
        let states = [
            state(id: 0, position: SIMD3(0, 0, 0), velocity: SIMD3(0, 0, 0)),
            state(id: 1, position: SIMD3(10, 0, 0), velocity: SIMD3(2, 0, 0)),
            state(id: 2, position: SIMD3(100, 0, 0), velocity: SIMD3(5, 0, 0)),
        ]
        simulator.particles = reversed ? states.reversed() : states
        simulator.advance(by: 0.5)
        return simulator
    }

    private static func state(
        id: UInt64,
        position: SIMD3<Double>,
        velocity: SIMD3<Double>
    ) -> SceneParticleState {
        .init(
            id: id, position: position, velocity: velocity,
            color: SIMD3(repeating: 1), alpha: 1, size: 1,
            rotation: .zero, angularVelocity: .zero, age: 0, lifetime: 10,
            initialColor: SIMD3(repeating: 1), initialAlpha: 1, initialSize: 1
        )
    }

    private static func diagnostics(_ simulator: SceneParticleSimulator) -> [String] {
        simulator.diagnostics.map(\.kind.rawValue)
    }

    private static func velocities(_ simulator: SceneParticleSimulator) -> [String: [Double]] {
        Dictionary(uniqueKeysWithValues: simulator.particles.map {
            (String($0.id), [$0.velocity.x, $0.velocity.y, $0.velocity.z])
        })
    }
}
'''


class SceneParticleBoidsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-particle-boids-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        binary = directory / "scene-particle-boids"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.results = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_alignment_and_cohesion_use_a_step_snapshot(self) -> None:
        self.assertEqual(self.results["acceptedDiagnostics"], ["boidsBounded"])
        self.assertEqual(self.results["acceptedVelocities"]["0"], [7, 0, 0])
        self.assertEqual(self.results["acceptedVelocities"]["1"], [-5, 0, 0])
        self.assertEqual(self.results["acceptedVelocities"]["2"], [5, 0, 0])
        self.assertEqual(
            self.results["acceptedVelocities"],
            self.results["reversedVelocities"],
            "同一步必须使用不可变快照，结果不得依赖粒子数组顺序",
        )

    def test_unsupported_profiles_remain_fail_closed(self) -> None:
        initial_velocities = {"0": [0, 0, 0], "1": [2, 0, 0], "2": [5, 0, 0]}
        self.assertEqual(
            set(self.results["rejected"]),
            {
                "separation",
                "largeGroup",
                "malformed",
                "unknownField",
                "flags",
                "audio",
                "missingSeparation",
                "officialPreview",
            },
        )
        for name, result in self.results["rejected"].items():
            with self.subTest(name=name):
                expected_diagnostics = ["boidsUnsupported"]
                if name == "audio":
                    expected_diagnostics = ["audioResponseIgnored", "boidsUnsupported"]
                self.assertEqual(result["diagnostics"], expected_diagnostics)
                self.assertEqual(result["velocities"], initial_velocities)


if __name__ == "__main__":
    unittest.main()
