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
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleRopeTrailPlan.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import simd

@main
enum Harness {
    static func main() throws {
        let result: [String: Any] = [
            "profiles": profileContract(),
            "history": historyContract(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func profileContract() -> [String: Any] {
        let defaultProfile = plan([
            "name": "ropetrail",
            "length": 0.4,
        ], maximumCount: 35)
        let fadeProfile = plan([
            "name": "ropetrail",
            "length": 0.5,
            "segments": 6,
            "fadealpha": true,
        ], maximumCount: 16)
        let longProfile = plan([
            "name": "ropetrail",
            "length": 3,
        ], maximumCount: 100)
        let budgetBoundary = plan([
            "name": "ropetrail",
            "length": 4,
            "segments": 8,
        ], maximumCount: 512)

        let rejected: [Bool] = [
            plan(["name": "ropetrail"], maximumCount: 1) == nil,
            plan(["name": "ropetrail", "length": 0], maximumCount: 1) == nil,
            plan(["name": "ropetrail", "length": 4.01], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "segments": 0,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "segments": 9,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "orientation": "upright",
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "axis": "0 0 1",
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "flags": 1,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "minlength": 0.1,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "maxlength": 2,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "subdivision": 1,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "uvscale": 1,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "uvsmoothing": false,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "uvscrolling": false,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "fadesize": true,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "futurefield": 1,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1,
            ], maximumCount: 0) == nil,
            plan([
                "name": "ropetrail", "length": 1,
            ], maximumCount: 513) == nil,
        ]

        let malformedSegments = definition([
            "name": "ropetrail",
            "length": 1,
            "segments": 1.5,
        ], maximumCount: 1)
        let malformedFade = definition([
            "name": "ropetrail",
            "length": 1,
            "fadealpha": "true",
        ], maximumCount: 1)
        let malformedNumericFadeAlpha = definition([
            "name": "ropetrail",
            "length": 1,
            "fadealpha": 1,
        ], maximumCount: 1)
        let malformedNumericFadeSize = definition([
            "name": "ropetrail",
            "length": 1,
            "fadesize": 0,
        ], maximumCount: 1)
        let malformedLength = definition([
            "name": "ropetrail",
            "length": "bad",
        ], maximumCount: 1)
        let malformedDefinitions = [
            malformedSegments,
            malformedFade,
            malformedNumericFadeAlpha,
            malformedNumericFadeSize,
            malformedLength,
        ]
        let multipleRenderers = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": [
                ["name": "ropetrail", "length": 1],
                ["name": "sprite"],
            ],
        ])
        let multipleRendererRejected: Bool = {
            guard let renderer = multipleRenderers.renderers.first else { return false }
            return SceneParticleRopeTrailPlan(
                renderer: renderer,
                rendererCount: multipleRenderers.renderers.count,
                maximumParticleCount: 1
            ) == nil
        }()
        let explicitObjectRenderer = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": ["name": "ropetrail", "length": 1],
        ])
        let onlyMalformedRenderer = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": [NSNull()],
        ])
        let explicitEmptyRenderer = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": [],
        ])

        return [
            "defaultAccepted": defaultProfile != nil,
            "defaultSegments": defaultProfile?.segmentCount ?? -1,
            "defaultFade": defaultProfile?.fadesAlpha ?? true,
            "fadeAccepted": fadeProfile != nil,
            "fadeSegments": fadeProfile?.segmentCount ?? -1,
            "fadeEnabled": fadeProfile?.fadesAlpha ?? false,
            "longAccepted": longProfile != nil,
            "budgetBoundaryAccepted": budgetBoundary != nil,
            "allUnsupportedRejected": rejected.allSatisfy { $0 },
            "malformedFlagged": malformedDefinitions.allSatisfy {
                $0.renderers.first?.hasMalformedFields == true
            },
            "malformedDiagnosed": malformedDefinitions.allSatisfy {
                $0.diagnostics.contains { $0.kind == .malformedComponent }
            },
            "malformedRejected": malformedDefinitions.allSatisfy {
                guard let renderer = $0.renderers.first else { return false }
                return SceneParticleRopeTrailPlan(
                    renderer: renderer,
                    rendererCount: $0.renderers.count,
                    maximumParticleCount: $0.maximumCount ?? 1
                ) == nil
            },
            "multipleRendererRejected": multipleRendererRejected,
            "explicitObjectRendererRejected": !explicitObjectRenderer.rendererWasImplicit
                && explicitObjectRenderer.renderers.isEmpty
                && explicitObjectRenderer.diagnostics.contains {
                    $0.kind == .malformedComponent && $0.path == "renderer"
                },
            "onlyMalformedRendererRejected": !onlyMalformedRenderer.rendererWasImplicit
                && onlyMalformedRenderer.renderers.isEmpty
                && onlyMalformedRenderer.diagnostics.contains {
                    $0.kind == .malformedComponent && $0.path == "renderer[0]"
                },
            "explicitEmptyRendererDefaultsToSprite": explicitEmptyRenderer.rendererWasImplicit
                && explicitEmptyRenderer.renderers.count == 1
                && explicitEmptyRenderer.renderers.first?.kind == .sprite,
        ]
    }

    private static func historyContract() -> [String: Any] {
        let noFadePlan = plan([
            "name": "ropetrail",
            "length": 1,
            "segments": 4,
            "fadealpha": false,
        ], maximumCount: 2)!
        let fadePlan = plan([
            "name": "ropetrail",
            "length": 1,
            "segments": 4,
            "fadealpha": true,
        ], maximumCount: 2)!

        let firstFrame = firstFrameCount(plan: noFadePlan)
        let noFade = linearInstances(plan: noFadePlan)
        let fade = linearInstances(plan: fadePlan)
        let curved = curvedInstances(plan: noFadePlan)
        let lifecycle = lifecycleCounts(plan: noFadePlan)
        let invalid = invalidLifecycleCounts(plan: noFadePlan)
        let staticAndZeroSize = staticAndZeroSizeCounts(plan: noFadePlan)
        let partition = partitionPositions(plan: noFadePlan)

        let noFadeAlphas = noFade.map { $0.rotationAndAlpha.w }
        let fadeAlphas = fade.map { $0.rotationAndAlpha.w }
        let directions = curved.map {
            [$0.velocityAndTrail.x, $0.velocityAndTrail.y]
        }
        let uvContinuous = zip(fade, fade.dropFirst()).allSatisfy {
            abs($0.0.frame0A.y - ($0.1.frame0A.y + $0.1.frame0A.w)) < 0.0001
        }
        return [
            "firstFrameCount": firstFrame,
            "linearCount": noFade.count,
            "linearDirections": noFade.map {
                [$0.velocityAndTrail.x, $0.velocityAndTrail.y]
            },
            "linearStretches": noFade.map(\.velocityAndTrail.w),
            "noFadeAlphas": noFadeAlphas,
            "fadeAlphas": fadeAlphas,
            "fadeStrictlyDecreases": zip(
                fadeAlphas,
                fadeAlphas.dropFirst()
            ).allSatisfy(>),
            "uvContinuous": uvContinuous,
            "uvUsesVerticalTextureAxis": fade.allSatisfy {
                abs($0.frame0A.z) < 0.0001
                    && $0.frame0A.w < 0
                    && abs($0.frame0B.x - 1) < 0.0001
                    && abs($0.frame0B.y) < 0.0001
                    && $0.frame0B.z < $0.frame0B.w
            },
            "curvedDirections": directions,
            "lifecycleCounts": lifecycle,
            "invalidLifecycleCounts": invalid,
            "staticAndZeroSizeCounts": staticAndZeroSize,
            "coarsePositions": partition.coarse,
            "finePositions": partition.fine,
        ]
    }

    private static func firstFrameCount(
        plan: SceneParticleRopeTrailPlan
    ) -> Int {
        var history = SceneParticleRopeTrailHistory(plan: plan)
        return history.advance(
            by: 0,
            particles: [particle(id: 1, x: 0)],
            layerAlpha: 1
        ).count
    }

    private static func linearInstances(
        plan: SceneParticleRopeTrailPlan
    ) -> [SceneParticleGPUInstance] {
        var history = SceneParticleRopeTrailHistory(plan: plan)
        var instances: [SceneParticleGPUInstance] = []
        for step in 0...4 {
            instances = history.advance(
                by: step == 0 ? 0 : 0.25,
                particles: [particle(
                    id: 1,
                    x: Float(step * 10),
                    alpha: 0.8
                )],
                layerAlpha: 0.5
            )
        }
        return instances
    }

    private static func curvedInstances(
        plan: SceneParticleRopeTrailPlan
    ) -> [SceneParticleGPUInstance] {
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0),
            SIMD2(10, 0),
            SIMD2(10, 10),
            SIMD2(20, 10),
            SIMD2(20, 20),
        ]
        var history = SceneParticleRopeTrailHistory(plan: plan)
        var instances: [SceneParticleGPUInstance] = []
        for (index, point) in points.enumerated() {
            instances = history.advance(
                by: index == 0 ? 0 : 0.25,
                particles: [particle(id: 1, x: point.x, y: point.y)],
                layerAlpha: 1
            )
        }
        return instances
    }

    private static func lifecycleCounts(
        plan: SceneParticleRopeTrailPlan
    ) -> [Int] {
        var history = SceneParticleRopeTrailHistory(plan: plan)
        var counts: [Int] = []
        counts.append(history.advance(
            by: 0,
            particles: [particle(id: 1, x: 0), particle(id: 2, x: 100)],
            layerAlpha: 1
        ).count)
        counts.append(history.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 10), particle(id: 2, x: 110)],
            layerAlpha: 1
        ).count)
        counts.append(history.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 20)],
            layerAlpha: 1
        ).count)
        counts.append(history.advance(
            by: 0.25,
            particles: [],
            layerAlpha: 1
        ).count)
        counts.append(history.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 30)],
            layerAlpha: 1
        ).count)
        return counts
    }

    private static func invalidLifecycleCounts(
        plan: SceneParticleRopeTrailPlan
    ) -> [Int] {
        var history = SceneParticleRopeTrailHistory(plan: plan)
        _ = history.advance(
            by: 0,
            particles: [particle(id: 1, x: 0)],
            layerAlpha: 1
        )
        let visible = history.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 10)],
            layerAlpha: 1
        ).count
        let invalid = history.advance(
            by: 0.25,
            particles: [particle(id: 1, x: .nan)],
            layerAlpha: 1
        ).count
        let restarted = history.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 20)],
            layerAlpha: 1
        ).count
        return [visible, invalid, restarted]
    }

    private static func staticAndZeroSizeCounts(
        plan: SceneParticleRopeTrailPlan
    ) -> [Int] {
        var staticHistory = SceneParticleRopeTrailHistory(plan: plan)
        _ = staticHistory.advance(
            by: 0,
            particles: [particle(id: 1, x: 0)],
            layerAlpha: 1
        )
        let staticCount = staticHistory.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 0)],
            layerAlpha: 1
        ).count

        var zeroHistory = SceneParticleRopeTrailHistory(plan: plan)
        _ = zeroHistory.advance(
            by: 0,
            particles: [particle(id: 1, x: 0, size: 0)],
            layerAlpha: 1
        )
        let zeroCount = zeroHistory.advance(
            by: 0.25,
            particles: [particle(id: 1, x: 10, size: 0)],
            layerAlpha: 1
        ).count
        return [staticCount, zeroCount]
    }

    private static func partitionPositions(
        plan: SceneParticleRopeTrailPlan
    ) -> (coarse: [Float], fine: [Float]) {
        func positions(stepCount: Int) -> [Float] {
            var history = SceneParticleRopeTrailHistory(plan: plan)
            var instances: [SceneParticleGPUInstance] = []
            for step in 0...stepCount {
                let time = Double(step) / Double(stepCount)
                instances = history.advance(
                    by: step == 0 ? 0 : 1 / Double(stepCount),
                    particles: [particle(id: 1, x: Float(time * 40))],
                    layerAlpha: 1
                )
            }
            return instances.map(\.positionAndSize.x)
        }
        return (positions(stepCount: 4), positions(stepCount: 16))
    }

    private static func particle(
        id: UInt64,
        x: Float,
        y: Float = 0,
        size: Float = 2,
        alpha: Float = 1
    ) -> SceneParticleRopeTrailParticle {
        SceneParticleRopeTrailParticle(
            id: id,
            position: SIMD3(x, y, 0),
            size: size,
            color: SIMD3(repeating: 1),
            alpha: alpha
        )
    }

    private static func plan(
        _ renderer: [String: Any],
        maximumCount: Int
    ) -> SceneParticleRopeTrailPlan? {
        let value = definition(renderer, maximumCount: maximumCount)
        guard let renderer = value.renderers.first else { return nil }
        return SceneParticleRopeTrailPlan(
            renderer: renderer,
            rendererCount: value.renderers.count,
            maximumParticleCount: value.maximumCount ?? 1
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


class SceneParticleRopeTrailTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-particle-rope-trail-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-rope-trail"
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

    def test_strict_tier_a_profiles_and_malformed_fields(self) -> None:
        profiles = self.result["profiles"]
        self.assertTrue(profiles["defaultAccepted"])
        self.assertEqual(profiles["defaultSegments"], 4)
        self.assertFalse(profiles["defaultFade"])
        self.assertTrue(profiles["fadeAccepted"])
        self.assertEqual(profiles["fadeSegments"], 6)
        self.assertTrue(profiles["fadeEnabled"])
        self.assertTrue(profiles["longAccepted"])
        self.assertTrue(profiles["budgetBoundaryAccepted"])
        self.assertTrue(profiles["allUnsupportedRejected"])
        self.assertTrue(profiles["malformedFlagged"])
        self.assertTrue(profiles["malformedDiagnosed"])
        self.assertTrue(profiles["malformedRejected"])
        self.assertTrue(profiles["multipleRendererRejected"])
        self.assertTrue(profiles["explicitObjectRendererRejected"])
        self.assertTrue(profiles["onlyMalformedRendererRejected"])
        self.assertTrue(profiles["explicitEmptyRendererDefaultsToSprite"])

    def test_history_builds_bounded_segments_with_continuous_uv(self) -> None:
        history = self.result["history"]
        self.assertEqual(history["firstFrameCount"], 0)
        self.assertEqual(history["linearCount"], 4)
        self.assertEqual(history["linearDirections"], [[10, 0]] * 4)
        self.assertEqual(history["linearStretches"], [5] * 4)
        for alpha in history["noFadeAlphas"]:
            self.assertAlmostEqual(alpha, 0.4, places=6)
        self.assertTrue(history["fadeStrictlyDecreases"])
        self.assertTrue(history["uvContinuous"])
        self.assertTrue(history["uvUsesVerticalTextureAxis"])
        directions = history["curvedDirections"]
        self.assertIn([10, 0], directions)
        self.assertIn([0, 10], directions)

    def test_history_clears_dead_or_invalid_tracks_and_is_partition_stable(self) -> None:
        history = self.result["history"]
        self.assertEqual(history["lifecycleCounts"], [0, 2, 2, 0, 0])
        self.assertEqual(history["invalidLifecycleCounts"], [1, 0, 0])
        self.assertEqual(history["staticAndZeroSizeCounts"], [0, 0])
        self.assertEqual(history["coarsePositions"], history["finePositions"])


if __name__ == "__main__":
    unittest.main()
