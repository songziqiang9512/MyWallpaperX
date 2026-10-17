import CoreGraphics
import CryptoKit
import Dispatch
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
        let twoFrameBatch = batches.first { $0.layerID == 42 }
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
            "twoFrameWholeSource": twoFrameBatch.map {
                $0.colorUVScale == SIMD2(repeating: 1) && !$0.instances.isEmpty
                    && $0.instances.allSatisfy { $0.frame0B.x == 1 && $0.frame0B.y == 0 }
            } ?? false,
            "atlasProfile": try animatedRopeAtlasContract(device: device),
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

    static func syntheticStaticScaledRope() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-static-scaled-rope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writePNG(directory.appendingPathComponent("materials/renamed.png"))
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        func leaf(
            _ name: String, maximum: Int = 4, subdivision: Int = 0,
            renderer: String = "rope", flags: Int = 0,
            movementWorld: Bool = false, alternate: Bool = false,
            children: [[String: Any]] = []
        ) throws -> String {
            let path = "particles/\(name).json"
            let origins: [Any]
            if alternate { origins = ["1 2 3", "5 6 7"] }
            else { origins = [[1, 2, 3], [5, 6, 7]] }
            var render: [String: Any] = ["name": renderer]
            if renderer == "rope" { render["subdivision"] = subdivision }
            try writeJSON([
                "material": alternate ? "materials/renamed.json" : "materials/shared.json",
                "maxcount": maximum, "flags": flags,
                "emitter": origins.map { origin in [
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "origin": origin, "distancemin": 0, "distancemax": 0,
                ] },
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    ["name": "sizerandom", "min": 4, "max": 4],
                ],
                "operator": movementWorld ? [["name": "movement", "flags": 1]] : [],
                "renderer": [render], "children": children,
            ], to: directory.appendingPathComponent(path))
            return path
        }
        func child(
            _ path: String, type: String = "static", scale: Any = [1, 1, 1],
            origin: Any = [0, 0, 0]
        ) -> [String: Any] {
            ["name": path, "type": type, "maxcount": 1, "scale": scale, "origin": origin]
        }
        var layers: [SceneRenderDescriptor.Layer] = []
        var labels: [Int: String] = [:]
        func container(_ id: Int, _ label: String, children: [[String: Any]]) throws {
            let path = "particles/root-\(label).json"
            try writeParticle(path, material: "materials/shared.json",
                rate: 0, instantaneous: 1, children: children, under: directory)
            layers.append(layer(id, path))
            labels[id] = label
        }

        let inclined = try leaf("inclined", flags: 1)
        let renamed = try leaf("renamed-ribbon", flags: 1, alternate: true)
        try container(821, "geometry", children: [
            child(inclined, scale: [2, 2, 3], origin: [11, 13, 17]),
        ])
        try container(822, "equivalent", children: [
            child(renamed, scale: "2 2 3", origin: "11 13 17"),
        ])

        let largeA = try leaf("large-a", maximum: 256, subdivision: 100)
        let largeB = try leaf("large-b", maximum: 256, subdivision: 100)
        let medium = try leaf("medium", maximum: 151, subdivision: 100)
        let legacy = try leaf("legacy", maximum: 129, subdivision: 63)
        try container(823, "ordered", children: [
            child(largeA), child(largeB), child(medium), child(legacy),
        ])
        // 32766 and 8194 reserve exactly the available incremental envelope.
        let boundary = try leaf("boundary", maximum: 382, subdivision: 85)
        let exact = try leaf("exact", maximum: 242, subdivision: 33)
        let over = try leaf("over-one", maximum: 150, subdivision: 54)
        try container(824, "exact", children: [child(boundary), child(exact)])
        try container(825, "over", children: [child(boundary), child(over), child(legacy)])

        var occupied: [[String: Any]] = []
        for index in 0..<3 {
            occupied.append(child(try leaf("capacity-\(index)", maximum: 20_000,
                renderer: "sprite")))
        }
        occupied.append(child(try leaf("capacity-tail", maximum: 5_236, renderer: "sprite")))
        // Only 300 particle slots remain: reject 382 before reserving credit,
        // then admit a 256-capacity Rope that needs the larger expansion.
        occupied.append(child(boundary))
        occupied.append(child(largeA))
        try container(826, "capacity", children: occupied)

        let event = try leaf("event-scaled")
        let world = try leaf("world-movement", movementWorld: true)
        let nested = try leaf("nested-scaled", children: [child(inclined, type: "eventspawn")])
        let malformed = try leaf("malformed-scale")
        let negative = try leaf("negative-scale")
        let nonuniform = try leaf("nonuniform-scale")
        let nestedLarge = try leaf("nested-large", maximum: 256, subdivision: 100)
        let bridge = try leaf("bridge", renderer: "sprite", children: [
            child(nestedLarge, type: "eventspawn"),
        ])
        try container(827, "rejections", children: [
            child(event, type: "eventspawn", scale: [2, 2, 3]),
            child(world, scale: [2, 2, 3]), child(nested, scale: [2, 2, 3]),
            child(malformed, scale: "bad"), child(negative, scale: [-1, -1, 1]),
            child(nonuniform, scale: [2, 3, 4]),
            child(largeB, type: "eventspawn"), child(bridge), child(legacy),
        ])
        let runtime = SceneParticleRuntime(descriptor: .init(
            layers: layers, renderOrderLayerIDs: layers.map(\.id),
            materialPasses: [
                .init(materialPath: "materials/shared.json", shaderPath: "genericparticle",
                    texturePaths: ["shared.png"], blending: "additive"),
                .init(materialPath: "materials/renamed.json", shaderPath: "genericparticle",
                    texturePaths: ["renamed.png"], blending: "additive"),
            ]
        ), cacheDirectory: directory, device: device)
        func signatures(_ batches: [SceneParticleDrawBatch]) -> [String: [[Float]]] {
            Dictionary(uniqueKeysWithValues: batches.map { batch in
                ("\(batch.layerID):\(batch.particlePath)", batch.instances.map { item in [
                    item.positionAndSize.x, item.positionAndSize.y,
                    item.positionAndSize.z, item.positionAndSize.w,
                    item.velocityAndTrail.x, item.velocityAndTrail.y, item.velocityAndTrail.z,
                    item.frame0B.z, item.frame0B.w, item.rotationAndAlpha.w,
                ] })
            })
        }
        let initial = runtime.frameSnapshot()
        _ = runtime.advance(by: 1.0 / 60.0)
        let first = runtime.advance(by: 1.0 / 60.0)
        let expected = signatures(first)
        let systemCount = runtime.lifecycleSnapshot.childSystemCount
        runtime.restoreFrame(initial)
        _ = runtime.advance(by: 1.0 / 60.0)
        let replay = runtime.advance(by: 1.0 / 60.0)
        let replayMatches = expected == signatures(replay)
            && systemCount == runtime.lifecycleSnapshot.childSystemCount
        var observed: [String: [String: Int]] = [:]
        for batch in replay where !batch.particlePath.hasPrefix("particles/root-") {
            let name = URL(fileURLWithPath: batch.particlePath).deletingPathExtension().lastPathComponent
            observed[labels[batch.layerID]!, default: [:]][name] = batch.instances.count
        }
        let geometry = replay.first { $0.particlePath == inclined }?.instances ?? []
        let alias = replay.first { $0.particlePath == renamed }?.instances ?? []
        let uploadsMatch = replay.allSatisfy { batch in
            batch.instanceBuffer.update(device: device, instances: batch.instances)
                && batch.instanceBuffer.count == batch.instances.count
        }
        let diagnostics = runtime.diagnostics.map { "\($0.layerID ?? -1):\($0.detail ?? "")" }
        runtime.teardown()
        let shortPath = "particles/short-scaled-ribbon.json"
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 16, "flags": 1,
            "emitter": [[0, 0, 0], [10, 5, 3]].map { point in [
                "name": "sphererandom", "rate": 60, "duration": 0.04,
                "origin": point, "distancemin": 0, "distancemax": 0,
            ] },
            "initializer": [
                ["name": "lifetimerandom", "min": 0.05, "max": 0.05],
                ["name": "sizerandom", "min": 4, "max": 4],
            ],
            "renderer": [["name": "rope", "subdivision": 1]],
        ], to: directory.appendingPathComponent(shortPath))
        try writeParticle("particles/root-retirement.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [child(shortPath, scale: [2, 2, 3], origin: [11, 13, 17])],
            under: directory)
        let naturalRuntime = SceneParticleRuntime(descriptor: .init(
            layers: [layer(828, "particles/root-retirement.json")],
            renderOrderLayerIDs: [828], materialPasses: [
                .init(materialPath: "materials/shared.json", shaderPath: "genericparticle",
                    texturePaths: ["shared.png"], blending: "additive"),
            ]
        ), cacheDirectory: directory, device: device)
        func naturalSequence() -> (rows: [[Int]], geometry: [[String: [[Float]]]]) {
            var rows: [[Int]] = []
            var geometry: [[String: [[Float]]]] = []
            for cadence in 1...12 {
                let batches = naturalRuntime.advance(by: 1.0 / 60.0)
                let count = batches.first { $0.particlePath == shortPath }?.instances.count ?? 0
                let lifecycle = naturalRuntime.lifecycleSnapshot
                rows.append([cadence, count, lifecycle.childSystemCount,
                    lifecycle.childParticleCount])
                geometry.append(signatures(batches))
            }
            return (rows, geometry)
        }
        let naturalInitial = naturalRuntime.frameSnapshot()
        let completedSequence = naturalSequence()
        naturalRuntime.restoreFrame(naturalInitial)
        let replayedSequence = naturalSequence()
        let naturalReplayMatches = completedSequence.rows == replayedSequence.rows
            && completedSequence.geometry == replayedSequence.geometry
        naturalRuntime.teardown()
        return [
            "observed": observed,
            "geometryPositions": geometry.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            },
            "geometryHalfWidths": geometry.map(\.positionAndSize.w),
            "geometryDisplacements": geometry.map {
                [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z]
            },
            "equivalentPositions": alias.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            },
            "equivalentHalfWidths": alias.map(\.positionAndSize.w),
            "equivalentDisplacements": alias.map {
                [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z]
            },
            "replayMatches": replayMatches, "uploadsMatch": uploadsMatch,
            "diagnostics": diagnostics,
            "afterTeardownChildSystems": runtime.lifecycleSnapshot.childSystemCount,
            "afterTeardownChildParticles": runtime.lifecycleSnapshot.childParticleCount,
            "naturalRetirementCadences": completedSequence.rows,
            "naturalRetirementReplayMatches": naturalReplayMatches,
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

    // Hand-authored TEX and particles: no Workshop payload or sample dispatch.
    static func animatedRopeAtlasContract(device: MTLDevice) throws -> [[String: Any]] {
        guard let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue() else { throw HarnessError.noMetal }
        var results: [[String: Any]] = []
        for (variant, stem) in ["prism", "renamed-ribbon"].enumerated() {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mwx-atlas-rope-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let atlas = "materials/\(stem).tex", multi = "materials/\(stem)-multi.tex"
            try writeRopeAtlas(directory.appendingPathComponent(atlas))
            try writeRopeAtlas(directory.appendingPathComponent(multi), images: 2)
            let material = "materials/\(stem).json", multiple = "materials/\(stem)-multi.json"
            let baseID = 501 + variant * 100
            func definition(_ renderer: String, _ material: String, flags: Int = 0) -> [String: Any] {
                var render: [String: Any] = ["name": renderer, "orientation": "screen", "flags": 0]
                if renderer == "rope" { render["subdivision"] = 0 }
                if renderer == "spritetrail" || renderer == "ropetrail" { render["length"] = 1 }
                if renderer == "ropetrail" { render["segments"] = 4; render["subdivision"] = 0 }
                return ["id": variant + 19, "material": material, "maxcount": 8,
                    "flags": flags, "animationmode": variant == 0 ? "sequence" : "Sequence",
                    "sequencemultiplier": 1, "emitter": [["name": "sphererandom", "rate": 4,
                        "distancemin": 0, "distancemax": 0]],
                    "initializer": [["name": "lifetimerandom", "min": renderer == "sprite" ? 2 : 8,
                        "max": renderer == "sprite" ? 2 : 8],
                        ["name": "sizerandom", "min": 32, "max": 32],
                        ["name": "velocityrandom", "min": [32,0,0], "max": [32,0,0]]],
                    "operator": [["name": "movement"]], "renderer": [render]]
            }
            var layers: [SceneRenderDescriptor.Layer] = []
            for (offset, renderer, source) in [(0,"rope",material), (1,"sprite",material),
                (2,"rope",multiple), (3,"ropetrail",material), (4,"spritetrail",material)] {
                let path = "particles/\(stem)-\(offset).json"
                try writeJSON(definition(renderer, source, flags: renderer == "sprite" ? 2 : 0),
                    to: directory.appendingPathComponent(path))
                layers.append(layer(baseID + offset, path))
            }
            let child = "particles/\(stem)-child.json", parent = "particles/\(stem)-parent.json"
            try writeJSON(definition("rope", material), to: directory.appendingPathComponent(child))
            var parentDefinition = definition("sprite", material, flags: 2)
            parentDefinition["children"] = [["name": child, "origin": [0,0,0]]]
            try writeJSON(parentDefinition, to: directory.appendingPathComponent(parent))
            layers.append(layer(baseID + 5, parent))
            let systemNeighbors: [(String, String, Any)] = [
                ("flags", "flags", 2), ("mode", "animationmode", "randomframe"),
                ("multiplier", "sequencemultiplier", 2)]
            let renderNeighbors: [(String, String, Any)] = [
                ("world", "flags", 1), ("uvscale", "uvscale", 2),
                ("scroll", "uvscrolling", true), ("smooth", "uvsmoothing", true)]
            for (offset, item) in (systemNeighbors + renderNeighbors).enumerated() {
                var bad = definition("rope", material)
                if offset < systemNeighbors.count { bad[item.1] = item.2 }
                else {
                    var renderer = (bad["renderer"] as! [[String: Any]])[0]
                    renderer[item.1] = item.2; bad["renderer"] = [renderer]
                }
                let path = "particles/\(stem)-unsupported-\(item.0).json"
                try writeJSON(bad, to: directory.appendingPathComponent(path))
                layers.append(layer(baseID + 6 + offset, path))
            }
            let refracted = "materials/\(stem)-refraction.json"
            let refractedPath = "particles/\(stem)-refraction.json"
            try writeJSON(definition("rope", refracted), to: directory.appendingPathComponent(refractedPath))
            layers.append(layer(baseID + 13, refractedPath))
            let descriptor = SceneRenderDescriptor(layers: layers,
                renderOrderLayerIDs: layers.map(\.id), materialPasses: [
                    .init(materialPath: material, shaderPath: "genericparticle",
                        texturePaths: ["\(stem).tex"], blending: "translucent"),
                    .init(materialPath: multiple, shaderPath: "genericparticle",
                        texturePaths: ["\(stem)-multi.tex"], blending: "translucent"),
                    .init(materialPath: refracted, shaderPath: "genericparticle",
                        texturePaths: ["\(stem).tex"], blending: "translucent", combos: ["REFRACT": 1])])
            let runtime = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
            var phases: [[String: Any]] = []
            for steps in [45, 30] {
                var batches: [SceneParticleDrawBatch] = []
                for _ in 0..<steps { batches = runtime.advance(by: 1.0 / 60.0) }
                let rope = batches.first { $0.layerID == baseID }
                let sprite = batches.first { $0.layerID == baseID + 1 }
                let trail = batches.first { $0.layerID == baseID + 4 }
                let childBatch = batches.first { $0.particlePath == child }
                func spans(_ batch: SceneParticleDrawBatch?) -> [[Float]] {
                    (batch?.instances ?? []).map { [$0.frame0A.z,$0.frame0A.w,$0.frame0B.x,$0.frame0B.y] }
                }
                phases.append(["ropeCount": rope?.instances.count ?? 0,
                    "ropeFrames": spans(rope), "childFrames": spans(childBatch),
                    "spriteFrames": spans(sprite), "trailFrames": spans(trail),
                    "spriteOrigins": sprite?.instances.map { $0.frame0A.x } ?? [],
                    "ropeTextureSize": rope.map { [$0.texture.width, $0.texture.height] } ?? [],
                    "ropeUVScale": rope.map { [$0.colorUVScale.x,$0.colorUVScale.y] } ?? [],
                    "ropePixels": try rope.map { try ropeAtlasPixels($0, device: device, pipeline: pipeline, queue: queue) } ?? [],
                    "spritePixels": try sprite.map { try ropeAtlasPixels($0, device: device, pipeline: pipeline, queue: queue, firstOnly: true) } ?? []])
            }
            let identities = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
                .filter { !$0.hasSuffix("/") }.sorted().compactMap { name -> [String: Any]? in
                    let url = directory.appendingPathComponent(name)
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return ["path": name, "bytes": data.count,
                        "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
                }
            results.append(["variant": stem, "baseID": baseID,
                "activeLayerIDs": runtime.activeLayerIDs,
                "diagnostics": runtime.diagnostics.map { "\($0.kind.rawValue):\($0.layerID ?? -1):\($0.detail ?? "")" },
                "phases": phases, "inputIdentities": identities])
        }
        return results
    }

    static func writeRopeAtlas(_ url: URL, images: Int = 1) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        // Four square cells in one 16x4 RGBA source. Multi-image is a negative.
        for word: UInt32 in [0,4,16,4,16,4,0] { appendUInt32(word, to: &data) }
        data.append(Data("TEXB0002\0".utf8)); appendUInt32(UInt32(images), to: &data)
        let colors: [[UInt8]] = [[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,255,0,255]]
        for _ in 0..<images {
            for word: UInt32 in [1,16,4,0,0,256] { appendUInt32(word, to: &data) }
            for _ in 0..<4 { for x in 0..<16 { data.append(contentsOf: colors[x/4]) } }
        }
        data.append(Data("TEXS0002\0".utf8)); appendUInt32(4, to: &data)
        for index in 0..<4 {
            appendUInt32(UInt32(images == 1 ? 0 : index % images), to: &data)
            appendFloat32(0.25, to: &data)
            for value: Float in [Float(index*4),0,4,0,0,4] { appendFloat32(value, to: &data) }
        }
        try data.write(to: url)
    }

    static func ropeAtlasPixels(_ batch: SceneParticleDrawBatch, device: MTLDevice,
                                pipeline: SceneParticleMetalPipeline, queue: MTLCommandQueue,
                                firstOnly: Bool = false) throws -> [[Int]] {
        guard let first = batch.instances.first,
              let command = queue.makeCommandBuffer() else { return [] }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 128, height: 64, mipmapped: false)
        td.usage = .renderTarget; td.storageMode = .shared
        guard let output = device.makeTexture(descriptor: td) else { return [] }
        let buffer = SceneParticleMetalInstanceBuffer()
        guard buffer.update(device: device, instances: firstOnly ? [first] : batch.instances) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        let uniforms = SceneParticleLayerUniforms(
            viewProjection: SceneMatrix.ortho(left: -8,right: 56,bottom: -32,top: 32,near: -1,far: 1),
            layerModel: SceneMatrix.identity(), basis: .init(right: SIMD3(1,0,0), up: SIMD3(0,1,0)),
            viewportSize: SIMD2(128,64))
        let drawn = pipeline.draw(texture: batch.texture, instances: buffer, uniforms: uniforms,
            renderState: batch.renderState, colorUVScale: batch.colorUVScale,
            colorSampling: batch.colorSampling, encoder: encoder)
        encoder.endEncoding(); guard drawn else { return [] }
        buffer.markSubmitted(on: command)
        let done = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in done.signal() }; command.commit()
        guard done.wait(timeout: .now()+5) == .success, command.status == .completed else { return [] }
        let x = Int((first.positionAndSize.x + 8) * 2)
        // The existing Sprite upload halves authored size32 to width16, so
        // sample strictly inside Y±8; Rope retains its own endpoint width.
        return (firstOnly ? [26,30,34,38] : [20,28,36,44]).map { y in
            var bgra = [UInt8](repeating: 0,count: 4)
            output.getBytes(&bgra, bytesPerRow: 4,
                from: MTLRegionMake2D(x,y,1,1), mipmapLevel: 0)
            return [Int(bgra[2]),Int(bgra[1]),Int(bgra[0]),Int(bgra[3])]
        }
    }

}
