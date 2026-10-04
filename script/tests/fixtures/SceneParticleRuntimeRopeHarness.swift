import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func syntheticRopeTrail() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-rope-trail-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func writeMalformedRendererParticle(_ path: String, renderer: Any) throws {
            try writeJSON([
                "material": "materials/shared.json",
                "maxcount": 100,
                "emitter": [["name": "sphererandom", "rate": 1]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 1, "max": 1],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "renderer": renderer,
            ], to: directory.appendingPathComponent(path))
        }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeAnimatedTEX(directory.appendingPathComponent("materials/animated.tex"))
        try writeParticle(
            "particles/rope-trail.json",
            material: "materials/shared.json",
            flags: 5,
            renderer: "ropetrail",
            rendererLength: 0.5,
            velocityX: 100,
            startTime: 1,
            moves: true,
            rate: 0,
            instantaneous: 1,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-missing-length.json",
            material: "materials/shared.json",
            renderer: "ropetrail",
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-animated.json",
            material: "materials/animated.json",
            renderer: "ropetrail",
            rendererLength: 0.5,
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-mixed-renderers.json",
            material: "materials/shared.json",
            renderer: "ropetrail",
            rendererLength: 0.5,
            additionalRenderers: [["name": "sprite", "flags": 0]],
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeParticle(
            "particles/rope-trail-malformed-renderers.json",
            material: "materials/shared.json",
            renderer: "ropetrail",
            rendererLength: 0.5,
            additionalRenderers: [NSNull()],
            velocityX: 100,
            moves: true,
            under: directory
        )
        try writeMalformedRendererParticle(
            "particles/rope-trail-object-renderer.json",
            renderer: ["name": "ropetrail", "length": 0.5]
        )
        try writeMalformedRendererParticle(
            "particles/rope-trail-only-malformed-renderer.json",
            renderer: [NSNull()]
        )
        try writeMalformedRendererParticle(
            "particles/rope-trail-empty-renderer.json",
            renderer: []
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(31, "particles/rope-trail.json"),
                layer(32, "particles/rope-trail-missing-length.json"),
                layer(33, "particles/rope-trail-animated.json"),
                layer(34, "particles/rope-trail-mixed-renderers.json"),
                layer(35, "particles/rope-trail-malformed-renderers.json"),
                layer(36, "particles/rope-trail-object-renderer.json"),
                layer(37, "particles/rope-trail-only-malformed-renderer.json"),
                layer(38, "particles/rope-trail-empty-renderer.json"),
            ],
            renderOrderLayerIDs: [31, 32, 33, 34, 35, 36, 37, 38],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                ),
                .init(
                    materialPath: "materials/animated.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["animated.tex"],
                    blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        func makeRuntime() -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device,
                staticWorldSpaceFrames: [
                    31: SceneParticleWorldSpaceFrame(
                        worldFrame: matrix_identity_float4x4
                    )!,
                ]
            )
        }
        let coarseRuntime = makeRuntime()
        let fineRuntime = makeRuntime()
        let prewarmedBatch = coarseRuntime.advance(by: 0).first {
            $0.layerID == 31
        }
        _ = fineRuntime.advance(by: 0)
        let coarseBatch = coarseRuntime.advance(by: 0.5).first {
            $0.layerID == 31
        }
        var fineBatch: SceneParticleDrawBatch?
        for _ in 0..<30 {
            fineBatch = fineRuntime.advance(by: 1.0 / 60.0).first {
                $0.layerID == 31
            }
        }
        let diagnosticDetails = coarseRuntime.diagnostics.map {
            "\($0.kind.rawValue):\($0.layerID ?? -1):\($0.detail ?? "")"
        }
        return [
            "activeLayerIDs": coarseRuntime.activeLayerIDs,
            "prewarmedInstanceCount": prewarmedBatch?.instances.count ?? -1,
            "prewarmedAllSegmentsMoveForward": prewarmedBatch?.instances.allSatisfy {
                $0.velocityAndTrail.x > 0
                    && abs($0.velocityAndTrail.y) < 0.0001
                    && $0.velocityAndTrail.w > 0
            } ?? false,
            "coarseSignature": ropeTrailSignature(coarseBatch),
            "fineSignature": ropeTrailSignature(fineBatch),
            "bufferMatches": coarseBatch.map { $0.instanceBuffer.update(device: device, instances: $0.instances) && $0.instanceBuffer.count == $0.instances.count } ?? false,
            "usesPerspective": coarseBatch?.usesPerspective ?? false,
            "sizeIsWorldSpace": coarseBatch?.sizeIsWorldSpace ?? false,
            "orientationScreen": coarseBatch?.orientation == .screen,
            "mixedRendererLoaded": coarseRuntime.activeLayerIDs.contains(34),
            "malformedRendererLoaded": coarseRuntime.activeLayerIDs.contains(35),
            "objectRendererLoaded": coarseRuntime.activeLayerIDs.contains(36),
            "onlyMalformedRendererLoaded": coarseRuntime.activeLayerIDs.contains(37),
            "emptyRendererLoaded": coarseRuntime.activeLayerIDs.contains(38),
            "diagnosticDetails": diagnosticDetails,
            "missingSpriteRenderer": coarseRuntime.diagnostics.contains {
                $0.kind == .missingSpriteRenderer
            },
        ]
    }

    static func syntheticRope() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-rope-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeAnimatedTEX(directory.appendingPathComponent("materials/animated.tex"))
        try writeParticle(
            "particles/rope.json",
            material: "materials/shared.json",
            renderer: "rope",
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeParticle(
            "particles/rope-animated.json",
            material: "materials/animated.json",
            renderer: "rope",
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeParticle(
            "particles/rope-mixed.json",
            material: "materials/shared.json",
            renderer: "rope",
            additionalRenderers: [["name": "sprite"]],
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeParticle(
            "particles/rope-world.json",
            material: "materials/shared.json",
            renderer: "rope",
            rendererFlags: 1,
            velocityX: 100,
            moves: true,
            rate: 5,
            under: directory
        )
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 100,
            "emitter": [[
                "name": "sphererandom", "rate": 5,
                "distancemin": 0, "distancemax": 0,
                "flags": 2,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": [100, 0, 0], "max": [100, 0, 0]],
            ],
            "operator": [["name": "movement"]],
            "renderer": [["name": "rope", "subdivision": 1]],
        ], to: directory.appendingPathComponent("particles/rope-subdivision.json"))
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 100,
            "emitter": [["name": "sphererandom", "rate": 5]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": [100, 0, 0], "max": [100, 0, 0]],
            ],
            "operator": [["name": "movement"]],
            "renderer": [["name": "rope", "uvscale": 2, "uvscrolling": true]],
        ], to: directory.appendingPathComponent("particles/rope-scroll.json"))
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 100,
            "emitter": [["name": "sphererandom", "rate": 5]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "rope", "uvscale": -1]],
        ], to: directory.appendingPathComponent("particles/rope-invalid.json"))
        try writeJSON([
            "material": "materials/shared.json",
            "maxcount": 20,
            "controlpoint": [
                ["id": 0, "parentcontrolpoint": 1],
                ["id": 1, "parentcontrolpoint": 2],
            ],
            "emitter": [[
                "name": "sphererandom", "rate": 5,
                "distancemin": 0, "distancemax": 0,
                "flags": 2,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": [50, 20, 0], "max": [50, 20, 0]],
            ],
            "operator": [["name": "movement"]],
            "renderer": [[
                "name": "rope", "subdivision": 1, "uvscale": 2,
                "uvscrolling": true, "uvsmoothing": false,
            ]],
        ], to: directory.appendingPathComponent("particles/rope-child.json"))
        try writeParticle(
            "particles/rope-parent.json",
            material: "materials/shared.json",
            children: [["name": "particles/rope-child.json", "origin": [40, 20, 0]]],
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(41, "particles/rope.json"),
                layer(42, "particles/rope-animated.json"),
                layer(43, "particles/rope-mixed.json"),
                layer(44, "particles/rope-world.json"),
                layer(45, "particles/rope-subdivision.json"),
                layer(46, "particles/rope-scroll.json"),
                layer(47, "particles/rope-invalid.json"),
                layer(48, "particles/rope-parent.json"),
            ],
            renderOrderLayerIDs: [41, 42, 43, 44, 45, 46, 47, 48],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                ),
                .init(
                    materialPath: "materials/animated.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["animated.tex"],
                    blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<90 {
            batches = runtime.advance(by: 1.0 / 60.0)
        }
        let batch = batches.first { $0.layerID == 41 }
        let subdivisionBatch = batches.first { $0.layerID == 45 }
        let scrollingBatch = batches.first { $0.layerID == 46 }
        let childBatch = batches.first { $0.particlePath == "particles/rope-child.json" }
        let instances = batch?.instances ?? []
        let diagnosticDetails = runtime.diagnostics.map {
            "\($0.kind.rawValue):\($0.layerID ?? -1):\($0.detail ?? "")"
        }
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "instanceCount": instances.count,
            "bufferMatches": batch.map { $0.instanceBuffer.update(device: device, instances: $0.instances) && $0.instanceBuffer.count == instances.count } ?? false,
            "orientationScreen": batch?.orientation == .screen,
            "usesPerspective": batch?.usesPerspective ?? true,
            "allSegmentsNonzero": instances.allSatisfy {
                simd_length(SIMD3(
                    $0.velocityAndTrail.x,
                    $0.velocityAndTrail.y,
                    $0.velocityAndTrail.z
                )) > 0.0001
                    && $0.velocityAndTrail.w > 0
            },
            "uvStartsAtZero": instances.first?.frame0B.z == 0,
            "uvEndsAtOne": instances.last?.frame0B.w == 1,
            "uvContinuous": zip(instances, instances.dropFirst()).allSatisfy {
                abs($0.0.frame0B.w - $0.1.frame0B.z) < 0.0001
            },
            "usesDisplacement": instances.allSatisfy { $0.frame1B.z == 1 },
            // WE rope default subdivision is 3 (4 sub-segments per node
            // pair); the authored subdivision-1 fixture halves that density.
            "subdivisionHalvesDefaultDensity": subdivisionBatch?.instances.count
                == instances.count / 2,
            "scrollUVStart": scrollingBatch?.instances.first?.frame0B.z ?? -1,
            "scrollUVEnd": scrollingBatch?.instances.last?.frame0B.w ?? -1,
            "childRopeCount": childBatch?.instances.count ?? 0,
            "childRopeUsesSubdivision": (childBatch?.instances.count ?? 0) % 2 == 0,
            "childRopeTranslated": childBatch?.instances.allSatisfy {
                $0.positionAndSize.x >= 40 && $0.positionAndSize.y >= 20
            } ?? false,
            "childRopeUVStartsWithPhase": (childBatch?.instances.first?.frame0B.z ?? 0) > 0,
            "diagnosticDetails": diagnosticDetails,
        ]
    }

    static func ropeTrailSignature(
        _ batch: SceneParticleDrawBatch?
    ) -> [Float] {
        batch?.instances.flatMap {
            [
                $0.positionAndSize.x,
                $0.positionAndSize.y,
                $0.velocityAndTrail.x,
                $0.velocityAndTrail.y,
                $0.velocityAndTrail.w,
                $0.frame0B.z,
                $0.frame0B.w,
                $0.rotationAndAlpha.w,
            ]
        } ?? []
    }

}
