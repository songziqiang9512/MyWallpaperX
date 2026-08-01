#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleRopePlan.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import simd

@main
enum Harness {
    static func main() throws {
        let result: [String: Any] = [
            "profiles": profileContract(),
            "topology": topologyContract(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func profileContract() -> [String: Any] {
        let basic = plan(["name": "rope"], maximumCount: 3)
        let explicitDefaults = plan([
            "name": "rope",
            "orientation": "screen",
            "subdivision": 0,
            "uvsmoothing": false,
            "uvscrolling": false,
        ], maximumCount: 512)
        let rejected = [
            plan(["name": "rope", "orientation": "upright"], maximumCount: 3),
            plan(["name": "rope", "axis": "0 0 1"], maximumCount: 3),
            plan(["name": "rope", "flags": 1], maximumCount: 3),
            plan(["name": "rope", "length": 1], maximumCount: 3),
            plan(["name": "rope", "minlength": 1], maximumCount: 3),
            plan(["name": "rope", "maxlength": 1], maximumCount: 3),
            plan(["name": "rope", "segments": 2], maximumCount: 3),
            plan(["name": "rope", "subdivision": 1], maximumCount: 3),
            plan(["name": "rope", "fadealpha": false], maximumCount: 3),
            plan(["name": "rope", "fadesize": false], maximumCount: 3),
            plan(["name": "rope", "uvscale": 1], maximumCount: 3),
            plan(["name": "rope", "uvsmoothing": true], maximumCount: 3),
            plan(["name": "rope", "uvscrolling": true], maximumCount: 3),
            plan(["name": "rope", "futurefield": 1], maximumCount: 3),
            plan(["name": "rope"], maximumCount: 0),
            plan(["name": "rope"], maximumCount: 1),
            plan(["name": "rope"], maximumCount: 513),
        ]
        let malformed = definition([
            "name": "rope",
            "subdivision": "bad",
        ], maximumCount: 3)
        let multiple = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 3,
            "emitter": [["name": "sphererandom"]],
            "renderer": [["name": "rope"], ["name": "sprite"]],
        ])
        let multipleRejected: Bool = {
            guard let renderer = multiple.renderers.first else { return false }
            return SceneParticleRopePlan(
                renderer: renderer,
                rendererCount: multiple.renderers.count,
                maximumParticleCount: multiple.maximumCount ?? 1
            ) == nil
        }()
        return [
            "basicAccepted": basic != nil,
            "basicLimit": basic?.particleLimit ?? -1,
            "explicitDefaultsAccepted": explicitDefaults != nil,
            "budgetBoundary": explicitDefaults?.particleLimit ?? -1,
            "allAdvancedRejected": rejected.allSatisfy { $0 == nil },
            "malformedFlagged": malformed.renderers.first?.hasMalformedFields == true,
            "malformedRejected": planFromDefinition(malformed) == nil,
            "multipleRejected": multipleRejected,
        ]
    }

    private static func topologyContract() -> [String: Any] {
        let value = plan(["name": "rope"], maximumCount: 3)!
        let instances = value.instances(
            particles: [
                particle(id: 2, position: SIMD3(20, 10, 0), size: 6, alpha: 0.25),
                particle(id: 0, position: SIMD3(0, 0, 0), size: 2, alpha: 0.5),
                particle(id: 1, position: SIMD3(10, 0, 0), size: 4, alpha: 1),
            ],
            layerAlpha: 0.5
        )
        let duplicateIDs = value.instances(
            particles: [
                particle(id: 1, position: SIMD3(0, 0, 0)),
                particle(id: 1, position: SIMD3(1, 0, 0)),
            ],
            layerAlpha: 1
        )
        let nonfinite = value.instances(
            particles: [
                particle(id: 0, position: SIMD3(0, 0, 0)),
                particle(id: 1, position: SIMD3(.infinity, 0, 0)),
            ],
            layerAlpha: 1
        )
        let overBudget = value.instances(
            particles: (0..<4).map {
                particle(id: UInt64($0), position: SIMD3(Double($0), 0, 0))
            },
            layerAlpha: 1
        )
        return [
            "count": instances.count,
            "positions": instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y]
            },
            "sizes": instances.map(\.positionAndSize.w),
            "alphas": instances.map(\.rotationAndAlpha.w),
            "displacements": instances.map {
                [$0.velocityAndTrail.x, $0.velocityAndTrail.y]
            },
            "uvRanges": instances.map { [$0.frame0B.z, $0.frame0B.w] },
            "uvContinuous": instances.count == 2
                && abs(instances[0].frame0B.w - instances[1].frame0B.z) < 0.0001,
            "usesDisplacement": instances.allSatisfy { $0.frame1B.z == 1 },
            "duplicateRejected": duplicateIDs.isEmpty,
            "nonfiniteRejected": nonfinite.isEmpty,
            "overBudgetRejected": overBudget.isEmpty,
        ]
    }

    private static func particle(
        id: UInt64,
        position: SIMD3<Double>,
        size: Double = 2,
        alpha: Double = 1
    ) -> SceneParticleState {
        SceneParticleState(
            id: id,
            position: position,
            velocity: .zero,
            color: SIMD3(0.5, 0.75, 1),
            alpha: alpha,
            size: size,
            rotation: .zero,
            angularVelocity: .zero,
            age: 0,
            lifetime: 1,
            initialColor: SIMD3(0.5, 0.75, 1),
            initialAlpha: alpha,
            initialSize: size
        )
    }

    private static func plan(
        _ renderer: [String: Any],
        maximumCount: Int
    ) -> SceneParticleRopePlan? {
        planFromDefinition(definition(renderer, maximumCount: maximumCount))
    }

    private static func planFromDefinition(
        _ definition: SceneParticleDefinition
    ) -> SceneParticleRopePlan? {
        guard let renderer = definition.renderers.first else { return nil }
        return SceneParticleRopePlan(
            renderer: renderer,
            rendererCount: definition.renderers.count,
            maximumParticleCount: definition.maximumCount ?? 1
        )
    }

    private static func definition(
        _ renderer: [String: Any],
        maximumCount: Int
    ) -> SceneParticleDefinition {
        SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": maximumCount,
            "emitter": [["name": "sphererandom"]],
            "renderer": [renderer],
        ])
    }
}
'''


class SceneParticleRopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-particle-rope-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-rope"
        environment = os.environ.copy()
        module_cache = directory / "module-cache"
        environment["CLANG_MODULE_CACHE_PATH"] = str(module_cache)
        environment["SWIFT_MODULECACHE_PATH"] = str(module_cache)
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_only_bounded_basic_profile_is_admitted(self) -> None:
        profiles = self.result["profiles"]
        self.assertTrue(profiles["basicAccepted"])
        self.assertEqual(profiles["basicLimit"], 3)
        self.assertTrue(profiles["explicitDefaultsAccepted"])
        self.assertEqual(profiles["budgetBoundary"], 512)
        self.assertTrue(profiles["allAdvancedRejected"])
        self.assertTrue(profiles["malformedFlagged"])
        self.assertTrue(profiles["malformedRejected"])
        self.assertTrue(profiles["multipleRejected"])

    def test_spawn_order_builds_adjacent_segments_with_continuous_uv(self) -> None:
        topology = self.result["topology"]
        self.assertEqual(topology["count"], 2)
        self.assertEqual(topology["positions"], [[5, 0], [15, 5]])
        self.assertEqual(topology["sizes"], [3, 5])
        self.assertEqual(topology["displacements"], [[10, 0], [10, 10]])
        self.assertEqual(topology["uvRanges"], [[0, 0.5], [0.5, 1]])
        self.assertTrue(topology["uvContinuous"])
        self.assertTrue(topology["usesDisplacement"])
        self.assertAlmostEqual(topology["alphas"][0], 0.375, places=6)
        self.assertAlmostEqual(topology["alphas"][1], 0.3125, places=6)

    def test_invalid_or_over_budget_topology_fails_closed(self) -> None:
        topology = self.result["topology"]
        self.assertTrue(topology["duplicateRejected"])
        self.assertTrue(topology["nonfiniteRejected"])
        self.assertTrue(topology["overBudgetRejected"])


if __name__ == "__main__":
    unittest.main()
