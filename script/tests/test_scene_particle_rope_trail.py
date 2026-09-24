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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAudioResponsePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
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
            "largeHistory": largeHistoryContract(),
            "subdivision": subdivisionContract(),
            "appearance": appearanceContract(),
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
            "length": 30,
            "segments": 16,
            "subdivision": 0,
        ], maximumCount: 3855)

        let rejected: [Bool] = [
            plan(["name": "ropetrail"], maximumCount: 1) == nil,
            plan(["name": "ropetrail", "length": 0], maximumCount: 1) == nil,
            plan(["name": "ropetrail", "length": -1], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "segments": 0,
            ], maximumCount: 1) == nil,
            plan([
                "name": "ropetrail", "length": 1, "segments": 65536,
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
                "name": "ropetrail", "length": 1, "subdivision": -1,
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
            ], maximumCount: 13108) == nil,
            plan([
                "name": "ropetrail", "length": 30, "segments": 16, "subdivision": 0,
            ], maximumCount: 3856) == nil,
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
            "explicitEmptyRendererRejected": !explicitEmptyRenderer.rendererWasImplicit
                && explicitEmptyRenderer.renderers.isEmpty,
        ]
    }

    private static func appearanceContract() -> [String: Any] {
        let base: [String: Any] = ["name": "ropetrail", "length": 1, "segments": 4, "subdivision": 0]
        func history() -> SceneParticleRopeTrailHistory {
            var history = SceneParticleRopeTrailHistory(plan: plan(base, maximumCount: 1)!)
            for step in 0...16 {
                history.ingest(by: step == 0 ? 0 : 1.0 / 16,
                    particles: [.init(id: 1, position: SIMD3(Float(step), 0, 0),
                        size: 2, color: SIMD3(1, 0, 0), alpha: 1)])
            }
            return history
        }
        let original = history()
        func changed(size: Float = 2, alpha: Float = 1,
                     color: SIMD3<Float> = SIMD3(1, 0, 0)) -> [SceneParticleGPUInstance] {
            var value = original
            return value.advance(by: 0, particles: [.init(id: 1, position: SIMD3(16, 0, 0),
                size: size, color: color, alpha: alpha)], layerAlpha: 1)
        }
        let alpha = changed(alpha: 0.2), size = changed(size: 8), color = changed(color: SIMD3(0, 1, 0))
        let invisible = changed(alpha: 0)
        var life = original
        let dead = life.advance(by: 0, particles: [], layerAlpha: 1)
        let newborn = life.advance(by: 0, particles: [.init(id: 1, position: .zero,
            size: 2, color: SIMD3(1, 1, 1), alpha: 1)], layerAlpha: 1)
        life = original
        let replay = life.advance(by: 0, particles: [.init(id: 1, position: SIMD3(16, 0, 0),
            size: 8, color: SIMD3(1, 0, 0), alpha: 1)], layerAlpha: 1)
        return ["alphaUniform": !alpha.isEmpty && alpha.allSatisfy { abs($0.rotationAndAlpha.w - 0.2) < 0.000001 },
                "sizeUniform": !size.isEmpty && size.allSatisfy { $0.positionAndSize.w == 4 && $0.trailHeadJoin.w == 4 && $0.trailTailJoin.w == 4 },
                "colorUniform": !color.isEmpty && color.allSatisfy { $0.colorAndFrameMix.x == 0 && $0.colorAndFrameMix.y == 1 },
                "noOldAlpha": invisible.allSatisfy { $0.rotationAndAlpha.w == 0 },
                "clearedOnDeath": dead.isEmpty && newborn.isEmpty,
                "replay": zip(size, replay).allSatisfy { $0.positionAndSize == $1.positionAndSize && $0.rotationAndAlpha == $1.rotationAndAlpha }]
    }

    private static func subdivisionContract() -> [String: Any] {
        func values(_ subdivision: Int?) -> [SceneParticleGPUInstance] {
            var renderer: [String: Any] = ["name": "ropetrail", "length": 1, "segments": 4]
            if let subdivision { renderer["subdivision"] = subdivision }
            var history = SceneParticleRopeTrailHistory(plan: plan(renderer, maximumCount: 1)!)
            var output: [SceneParticleGPUInstance] = []
            for step in 0...128 {
                let t = Float(step) / 128
                output = history.advance(by: step == 0 ? 0 : 1.0 / 128,
                    particles: [.init(id: 1, position: SIMD3(t, t * t, 0),
                        size: 0.1 + t * 0.1, color: SIMD3(repeating: 1), alpha: 1)],
                    layerAlpha: 1)
            }
            return output
        }
        let omitted = values(nil), explicit = values(1), coarse = values(0)
        func error(_ values: [SceneParticleGPUInstance]) -> Float {
            values.map { abs($0.positionAndSize.y - $0.positionAndSize.x * $0.positionAndSize.x) }.max() ?? 1
        }
        let equal = zip(omitted, explicit).allSatisfy {
            $0.positionAndSize == $1.positionAndSize && $0.velocityAndTrail == $1.velocityAndTrail
                && $0.trailHeadJoin == $1.trailHeadJoin && $0.trailTailJoin == $1.trailTailJoin
        }
        let joints = zip(omitted, omitted.dropFirst()).allSatisfy { newer, older in
            let a = SIMD3(newer.positionAndSize.x, newer.positionAndSize.y, newer.positionAndSize.z)
                - SIMD3(newer.velocityAndTrail.x, newer.velocityAndTrail.y, newer.velocityAndTrail.z) * 0.5
            let b = SIMD3(older.positionAndSize.x, older.positionAndSize.y, older.positionAndSize.z)
                + SIMD3(older.velocityAndTrail.x, older.velocityAndTrail.y, older.velocityAndTrail.z) * 0.5
            return simd_distance(a, b) < 0.000001 && newer.trailTailJoin.w == older.trailHeadJoin.w
        }
        let turns = zip(omitted, omitted.dropFirst()).map { newer, older -> Double in
            let first = SIMD3(newer.velocityAndTrail.x, newer.velocityAndTrail.y, newer.velocityAndTrail.z)
            let second = SIMD3(older.velocityAndTrail.x, older.velocityAndTrail.y, older.velocityAndTrail.z)
            let firstLength = simd_length(first), secondLength = simd_length(second)
            guard firstLength > 0.000001, secondLength > 0.000001 else { return 0 }
            let cosine = min(max(simd_dot(first / firstLength, second / secondLength), -1), 1)
            return Double(acos(cosine)) * 180 / Double.pi
        }
        return ["defaultMatchesOne": equal && omitted.count == explicit.count,
                "fineCount": omitted.count, "coarseCount": coarse.count,
                "maximumSegmentTurnDegrees": turns.max() ?? 0,
                "errorRatio": error(omitted) / error(coarse), "sharedEndpoints": joints,
                "fractionRejected": plan(["name": "ropetrail", "length": 1, "subdivision": 0.5], maximumCount: 1) == nil,
                "overflowRejected": plan(["name": "ropetrail", "length": 1, "subdivision": 1e100], maximumCount: 1) == nil,
                "budgetRejected": plan(["name": "ropetrail", "length": 1, "segments": 1024, "subdivision": 64], maximumCount: 1) == nil]
    }

    private static func largeHistoryContract() -> [String: Any] {
        guard let plan = plan([
            "name": "ropetrail", "length": 30, "segments": 16, "subdivision": 0,
        ], maximumCount: 1300) else { return ["accepted": false] }
        var history = SceneParticleRopeTrailHistory(plan: plan)
        func particles(at time: Float) -> [SceneParticleRopeTrailParticle] {
            (0..<1300).map { index in
                .init(id: UInt64(index), position: SIMD3(time, Float(index), 0),
                      size: 2, color: SIMD3(repeating: 1), alpha: 1)
            }
        }
        for index in 0...320 {
            history.ingest(by: index == 0 ? 0 : 0.125,
                           particles: particles(at: Float(index) * 0.125))
        }
        let instances = history.advance(by: 0, particles: particles(at: 40), layerAlpha: 1)
        // Every drawable segment must lie inside the authored trail window,
        // carry its own particle lane, and have a drawable length.
        let correct = instances.allSatisfy { instance in
            let x = instance.positionAndSize.x, y = instance.positionAndSize.y
            let length = simd_length(SIMD3(
                instance.velocityAndTrail.x, instance.velocityAndTrail.y,
                instance.velocityAndTrail.z
            ))
            return x >= 40 - 30 - 0.001 && x <= 40 + 0.001
                && y >= 0 && y <= 1299
                && length > 0.0001 && length <= 30
                && instance.rotationAndAlpha.w > 0
        }
        let restored = history
        let cleared = history.advance(by: 1, particles: [], layerAlpha: 1).count
        history = restored
        let replay = history.advance(by: 0, particles: particles(at: 40), layerAlpha: 1)
        return ["accepted": true, "count": instances.count, "correct": correct,
                "cleared": cleared, "replayed": replay.count]
    }

    private static func historyContract() -> [String: Any] {
        let noFadePlan = plan([
            "name": "ropetrail",
            "length": 1,
            "segments": 4,
            "subdivision": 0,
            "fadealpha": false,
        ], maximumCount: 2)!
        let fadePlan = plan([
            "name": "ropetrail",
            "length": 1,
            "segments": 4,
            "subdivision": 0,
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
        self.assertTrue(profiles["explicitEmptyRendererRejected"])

    def test_current_particle_appearance_applies_to_the_complete_trail(self) -> None:
        for key, value in self.result["appearance"].items():
            self.assertTrue(value, key)

    def test_subdivision_refines_authored_curvature_and_shares_endpoints(self) -> None:
        value = self.result["subdivision"]
        self.assertTrue(value["defaultMatchesOne"])
        # Drawable nodes come from the prepared history, so the finer profile
        # keeps more nodes than the coarse one instead of a fixed count.
        self.assertGreater(value["fineCount"], value["coarseCount"])
        self.assertGreaterEqual(value["fineCount"], 8)
        self.assertLessEqual(value["errorRatio"], 0.26)
        self.assertTrue(value["sharedEndpoints"])
        # A curved authored path must not be drawn as a visibly cornered
        # polyline: no drawable segment may turn by more than a few degrees.
        self.assertLess(value["maximumSegmentTurnDegrees"], 5.0)
        self.assertTrue(value["fractionRejected"])
        self.assertTrue(value["overflowRejected"])
        self.assertTrue(value["budgetRejected"])

    def test_long_dense_history_preserves_segments_and_snapshot(self) -> None:
        result = self.result["largeHistory"]
        self.assertTrue(result["accepted"])
        self.assertGreaterEqual(result["count"], 20800)
        self.assertTrue(result["correct"])
        self.assertEqual(result["cleared"], 0)
        self.assertEqual(result["replayed"], result["count"])

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
        # Both sampling rates must cover the same authored path; the finer
        # one simply resolves it with more drawable nodes.
        coarse, fine = history["coarsePositions"], history["finePositions"]
        self.assertTrue(coarse and fine)
        self.assertGreaterEqual(len(fine), len(coarse))
        # Both sampling rates must cover the same authored trail window; the
        # finer rate simply resolves it with more drawable segments.
        self.assertLessEqual(min(fine) - 1e-3, min(coarse))
        self.assertGreaterEqual(max(fine) + 1e-3, max(coarse))


if __name__ == "__main__":
    unittest.main()
