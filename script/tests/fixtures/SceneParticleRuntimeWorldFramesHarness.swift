import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func syntheticWorldSpaceGravityFrame() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-gravity-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func writeGravityParticle(_ path: String, startTime: Double) throws {
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 100, "flags": 1,
                "starttime": startTime,
                "emitter": [[
                    "name": "sphererandom", "rate": 120,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "operator": [[
                    "name": "movement", "flags": 1, "gravity": "60 0 0",
                ]],
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeGravityParticle("particles/world-gravity-prewarm.json", startTime: 0.1)
        try writeGravityParticle("particles/world-gravity-live.json", startTime: 0)
        let materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor] = [
            .init(
                materialPath: "materials/shared.json",
                shaderPath: "genericparticle",
                texturePaths: ["shared.png"],
                blending: "additive"
            )
        ]
        func descriptor(_ path: String) -> SceneRenderDescriptor {
            SceneRenderDescriptor(
                layers: [layer(81, path)],
                renderOrderLayerIDs: [81],
                materialPasses: materialPasses
            )
        }
        func positions(_ batches: [SceneParticleDrawBatch]) -> [[Float]] {
            (batches.first { $0.layerID == 81 })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        func axisSums(_ values: [[Float]]) -> (x: Double, y: Double) {
            (
                values.reduce(0) { $0 + abs(Double($1[0])) },
                values.reduce(0) { $0 + abs(Double($1[1])) }
            )
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        // Prewarm: the init-time warm-up must convert world gravity through
        // the injected launch frame (a +90 degree Z rotation sends world +X
        // gravity into the local Y axis).
        let plusZ = simd_float4x4(columns: (
            SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        ))
        let prewarm = SceneParticleRuntime(
            descriptor: descriptor("particles/world-gravity-prewarm.json"),
            cacheDirectory: directory,
            device: device,
            staticWorldSpaceFrames: [
                81: SceneParticleWorldSpaceFrame(worldFrame: plusZ)!,
            ]
        )
        let prewarmPositions = positions(
            prewarm.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
        )
        // Live gravity: with a transform lane and a -90 degree Z current
        // frame, world +X gravity runs into local +Y during the advance.
        let minusZ = simd_float4x4(columns: (
            SIMD4(0, -1, 0, 0), SIMD4(1, 0, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        ))
        let live = SceneParticleRuntime(
            descriptor: descriptor("particles/world-gravity-live.json"),
            cacheDirectory: directory,
            device: device
        )
        _ = live.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
        var livePositions: [[Float]] = []
        for _ in 0..<6 {
            livePositions = positions(
                live.advance(
                    by: 1.0 / 60.0,
                    dynamicValues: snapshotWithTransformLane(layerID: 81),
                    layerWorldFrames: [81: minusZ]
                )
            )
        }
        let prewarmSums = axisSums(prewarmPositions)
        let liveSums = axisSums(livePositions)
        return [
            "prewarmPositions": prewarmPositions,
            "prewarmX": prewarmSums.x,
            "prewarmY": prewarmSums.y,
            "livePositions": livePositions,
            "liveX": liveSums.x,
            "liveY": liveSums.y,
        ]
    }

    /// Offline replay of a real captured render descriptor: advances the
    /// particle runtime with an injected pointer position and reports the
    /// layer's demand registration and birth positions.
    static func snapshotWithTransformLane(layerID: Int) -> SceneDynamicSnapshot {
        let lane = SceneDynamicTarget.layer(layerID: layerID, field: .origin)
        return SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [
                SceneDynamicTargetDefinition(
                    target: lane,
                    valueType: .vector3,
                    authoredValue: .vector3(0, 0, 0)
                ),
            ],
            timelineValues: [lane: .vector3(10, 0, 0)]
        ).snapshot
    }

    static func syntheticWorldSpaceFreeze() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-freeze-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/world-freeze.json",
            material: "materials/shared.json",
            flags: 1,
            velocityX: 120,
            lifetime: 2.0 / 60.0,
            moves: true,
            movementFlags: 1,
            rate: 120,
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(71, "particles/world-freeze.json")],
            renderOrderLayerIDs: [71],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = runtime.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
        let moving = runtime.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 1))
        let frozen = runtime.advance(by: 1.0 / 60.0, dynamicValues: snapshotWithTransformLane(layerID: 71))
        let frozenAgain = runtime.advance(by: 1.0 / 60.0, dynamicValues: snapshotWithTransformLane(layerID: 71))
        func positions(_ batches: [SceneParticleDrawBatch]) -> [[Float]] {
            (batches.first { $0.layerID == 71 })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        // Live-frame adoption: the same transform lane with the renderer's
        // current world frame keeps the system simulating through that frame.
        func liveRuntime(
            worldFrame: simd_float4x4
        ) -> (positions: [[Float]], followsCurrent: Bool, frozen: Bool) {
            let live = SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device
            )
            _ = live.advance(by: 1.0 / 60.0, dynamicValues: .empty(frameIndex: 0))
            var livePositions: [[Float]] = []
            for _ in 0..<3 {
                livePositions = positions(
                    live.advance(
                        by: 1.0 / 60.0,
                        dynamicValues: snapshotWithTransformLane(layerID: 71),
                        layerWorldFrames: [71: worldFrame]
                    )
                )
            }
            return (
                livePositions,
                live.diagnostics.contains {
                    $0.kind == .simulationLimitation
                        && $0.layerID == 71
                        && $0.detail == "world-space frame follows current transform"
                },
                live.diagnostics.contains {
                    $0.kind == .simulationLimitation
                        && $0.layerID == 71
                        && $0.detail == "world-space frame frozen after runtime transform write"
                }
            )
        }
        let liveIdentity = liveRuntime(
            worldFrame: matrix_identity_float4x4
        )
        let liveRotated = liveRuntime(
            worldFrame: simd_float4x4(columns: (
                SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
            ))
        )
        return [
            "movingLayerActive": moving.contains { $0.layerID == 71 },
            "movingPositions": positions(moving),
            "frozenPositions": positions(frozen),
            "frozenAgainPositions": positions(frozenAgain),
            "freezeDiagnostic": runtime.diagnostics.contains {
                $0.kind == .simulationLimitation
                    && $0.layerID == 71
                    && $0.detail == "world-space frame frozen after runtime transform write"
            },
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
            "liveIdentityPositions": liveIdentity.positions,
            "liveIdentityFollowsCurrent": liveIdentity.followsCurrent,
            "liveIdentityFrozen": liveIdentity.frozen,
            "liveRotatedPositions": liveRotated.positions,
            "liveRotatedFollowsCurrent": liveRotated.followsCurrent,
            "liveRotatedFrozen": liveRotated.frozen,
        ]
    }

    static func syntheticWorldSpaceFreezeRecovery() throws -> [String: Any] {
        // Freeze transaction recovery. The world-space freeze/re-adopt
        // state participates in the frame transaction: a degenerate
        // (zero-scale) transform write must hold the previous-current
        // state for that frame only, a discarded frame must roll the
        // freeze back with the simulation, and a restored valid transform
        // must resume simulation. Local-space systems under the same
        // scripted ancestor chain never consume the world frame and must
        // keep simulating.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/world-recovery.json",
            material: "materials/shared.json",
            flags: 1,
            velocityX: 120,
            lifetime: 10,
            moves: true,
            movementFlags: 1,
            rate: 120,
            under: directory
        )
        try writeParticle(
            "particles/local-recovery.json",
            material: "materials/shared.json",
            velocityX: 120,
            lifetime: 10,
            moves: true,
            rate: 120,
            under: directory
        )
        try writeParticle(
            "particles/world-chain.json",
            material: "materials/shared.json",
            flags: 1,
            velocityX: 120,
            lifetime: 10,
            moves: true,
            movementFlags: 1,
            rate: 120,
            children: [["name": "particles/chain-child.json", "type": "static"]],
            under: directory
        )
        try writeParticle(
            "particles/chain-child.json",
            material: "materials/shared.json",
            velocityX: 60,
            lifetime: 10,
            moves: true,
            rate: 60,
            under: directory
        )
        func particleLayer(
            _ id: Int, _ path: String, parentID: Int? = nil
        ) -> SceneRenderDescriptor.Layer {
            .init(
                id: id, name: nil, contentKind: "particle", particlePath: path,
                particleInstanceOverride: nil, parentID: parentID, visible: true, alpha: 1
            )
        }
        let descriptor = SceneRenderDescriptor(
            layers: [
                particleLayer(80, "particles/local-recovery.json"),
                particleLayer(81, "particles/world-recovery.json"),
                particleLayer(82, "particles/local-recovery.json", parentID: 80),
                particleLayer(83, "particles/local-recovery.json", parentID: 80),
                particleLayer(84, "particles/world-chain.json", parentID: 83),
            ],
            renderOrderLayerIDs: [80, 81, 82, 83, 84],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        func makeRuntime() -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device,
                staticWorldSpaceChains: [
                    80: [80], 81: [81], 82: [82, 80], 83: [83, 80], 84: [84, 83, 80],
                ]
            )
        }
        func motion(_ batches: [SceneParticleDrawBatch], layerID: Int) -> Float {
            (batches.first { $0.layerID == layerID })?.instances.reduce(0) {
                $0 + abs($1.positionAndSize.x)
            } ?? -1
        }
        let zeroScale = simd_float4x4(
            columns: (SIMD4(repeating: 0), SIMD4(repeating: 0),
                      SIMD4(repeating: 0), SIMD4(repeating: 0))
        )
        let lane81 = snapshotWithTransformLane(layerID: 81)
        let lane80 = snapshotWithTransformLane(layerID: 80)
        let frameDelta = 1.0 / 60.0

        // A: valid -> degenerate -> restored (degenerate frame committed).
        let recovery = makeRuntime()
        _ = recovery.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 0))
        let beforeDegenerate = recovery.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 1)
        )
        let degenerateFrame = recovery.advance(
            by: frameDelta, dynamicValues: lane81, layerWorldFrames: [81: zeroScale]
        )
        let restoredFrame = recovery.advance(
            by: frameDelta, dynamicValues: lane81,
            layerWorldFrames: [81: matrix_identity_float4x4]
        )

        // B: valid -> degenerate -> discard -> valid. The degenerate frame
        // is dropped by the host, so the freeze must roll back with the
        // simulation values and the next valid frame simulates again.
        let rollback = makeRuntime()
        _ = rollback.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 0))
        let preRollback = rollback.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 1)
        )
        let rollbackSnapshot = rollback.frameSnapshot()
        _ = rollback.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 2))
        _ = rollback.advance(
            by: frameDelta, dynamicValues: lane81, layerWorldFrames: [81: zeroScale]
        )
        rollback.restoreFrame(rollbackSnapshot)
        let afterRestore = rollback.advance(
            by: frameDelta, dynamicValues: lane81,
            layerWorldFrames: [81: matrix_identity_float4x4]
        )

        // C: a local-space system under a scripted ancestor keeps
        // simulating: its simulation never consumes the world frame.
        let localUnderScript = makeRuntime()
        _ = localUnderScript.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 0))
        let localStart = localUnderScript.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 1)
        )
        var localLane: [SceneParticleDrawBatch] = []
        for _ in 0..<3 {
            localLane = localUnderScript.advance(by: frameDelta, dynamicValues: lane80)
        }

        // D: a world-space system at the bottom of a two-level ancestor
        // chain (root + static child on the same layer delta).
        let chained = makeRuntime()
        _ = chained.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 0))
        let chainedSteady = chained.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 1)
        )
        let chainedFrozen = chained.advance(
            by: frameDelta, dynamicValues: lane80, layerWorldFrames: [84: zeroScale]
        )
        let chainedRestored = chained.advance(
            by: frameDelta, dynamicValues: lane80,
            layerWorldFrames: [84: matrix_identity_float4x4]
        )

        // E: vanishing-write recovery. A one-shot undeclared script write
        // (or a finished timeline) stops producing a transform lane on the
        // frames after the write; the dynamic snapshot falls back to the
        // authored transform and the resolver serves a valid frame again.
        // The frozen system must be re-evaluated on those lane-less frames
        // and resume simulation through the launch-static fallback.
        let vanishing = makeRuntime()
        _ = vanishing.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 0))
        let vanishingSteady = vanishing.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 1)
        )
        let vanishingFrozen = vanishing.advance(
            by: frameDelta, dynamicValues: lane81, layerWorldFrames: [81: zeroScale]
        )
        let vanishingResumed = vanishing.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 2),
            layerWorldFrames: [81: matrix_identity_float4x4]
        )
        let vanishingNext = vanishing.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 3),
            layerWorldFrames: [81: matrix_identity_float4x4]
        )

        // F: conservative hold. A lane-less frame that still cannot
        // construct a current frame for the frozen layer keeps the
        // previous-current freeze instead of guessing a recovery.
        let conservative = makeRuntime()
        _ = conservative.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 0))
        _ = conservative.advance(by: frameDelta, dynamicValues: .empty(frameIndex: 1))
        let conservativeFrozen = conservative.advance(
            by: frameDelta, dynamicValues: lane81, layerWorldFrames: [81: zeroScale]
        )
        let conservativeHeld = conservative.advance(
            by: frameDelta, dynamicValues: .empty(frameIndex: 2)
        )
        // G: the local write disappears while an unrelated chain keeps
        // receiving transforms. Recovery must depend on this chain alone.
        let unrelated = makeRuntime()
        _ = unrelated.advance(by: frameDelta)
        _ = unrelated.advance(by: frameDelta)
        let unrelatedFrozen = unrelated.advance(
            by: frameDelta, dynamicValues: lane81, layerWorldFrames: [81: zeroScale]
        )
        let unrelatedHeld = unrelated.advance(
            by: frameDelta, dynamicValues: lane80, layerWorldFrames: [81: zeroScale]
        )
        let frozenSnapshot = unrelated.frameSnapshot()
        let unrelatedResumed = unrelated.advance(
            by: frameDelta, dynamicValues: lane80,
            layerWorldFrames: [81: matrix_identity_float4x4]
        )
        unrelated.restoreFrame(frozenSnapshot)
        let rollbackHeld = unrelated.advance(by: frameDelta, dynamicValues: lane80)
        let unrelatedReplay = unrelated.advance(
            by: frameDelta, dynamicValues: lane80,
            layerWorldFrames: [81: matrix_identity_float4x4]
        )
        let unrelatedNext = unrelated.advance(
            by: frameDelta, dynamicValues: lane80,
            layerWorldFrames: [81: matrix_identity_float4x4]
        )
        return [
            "unrelatedWriteKeepsInvalidFrozen": motion(unrelatedHeld, layerID: 81)
                == motion(unrelatedFrozen, layerID: 81),
            "unrelatedWriteResumes": motion(unrelatedResumed, layerID: 81)
                > motion(unrelatedFrozen, layerID: 81) + 0.5,
            "unrelatedWriteStaysUnfrozen": motion(unrelatedNext, layerID: 81)
                > motion(unrelatedReplay, layerID: 81) + 0.5,
            "recoveryRollbackKeepsFrozen": motion(rollbackHeld, layerID: 81)
                == motion(unrelatedFrozen, layerID: 81),
            "recoveryReplayMatches": motion(unrelatedReplay, layerID: 81)
                == motion(unrelatedResumed, layerID: 81),
            "degenerateHoldsPrevious": motion(degenerateFrame, layerID: 81)
                == motion(beforeDegenerate, layerID: 81),
            "recoveryResumes": motion(restoredFrame, layerID: 81)
                > motion(degenerateFrame, layerID: 81) + 0.5,
            "resumeDiagnostic": recovery.diagnostics.contains {
                $0.kind == .simulationLimitation
                    && $0.layerID == 81
                    && $0.detail == "world-space frame resumed after transform recovered"
            },
            "rollbackResumes": motion(afterRestore, layerID: 81)
                > motion(preRollback, layerID: 81) + 0.5,
            "localKeepsMoving": motion(localLane, layerID: 82)
                > motion(localStart, layerID: 82) + 0.5,
            "localFreezeDiagnosticAbsent": !localUnderScript.diagnostics.contains {
                $0.kind == .simulationLimitation
                    && $0.layerID == 82
                    && $0.detail == "world-space frame frozen after runtime transform write"
            },
            "chainedFrozenHoldsPrevious": motion(chainedFrozen, layerID: 84)
                == motion(chainedSteady, layerID: 84),
            "chainedRecoveryResumes": motion(chainedRestored, layerID: 84)
                > motion(chainedFrozen, layerID: 84) + 0.5,
            "chainedRootAndChildBatches": chainedRestored
                .filter { $0.layerID == 84 }.count >= 2,
            "vanishingWriteHoldsDuringDegenerate": motion(vanishingFrozen, layerID: 81)
                == motion(vanishingSteady, layerID: 81),
            "vanishingWriteResumes": motion(vanishingResumed, layerID: 81)
                > motion(vanishingFrozen, layerID: 81) + 0.5,
            "vanishingWriteStaysUnfrozen": motion(vanishingNext, layerID: 81)
                > motion(vanishingResumed, layerID: 81) + 0.5,
            "vanishingWriteResumeDiagnostic": vanishing.diagnostics.contains {
                $0.kind == .simulationLimitation
                    && $0.layerID == 81
                    && $0.detail == "world-space frame resumed after transform recovered"
            },
            "conservativeHoldKeepsPrevious": motion(conservativeHeld, layerID: 81)
                == motion(conservativeFrozen, layerID: 81),
        ]
    }

}
