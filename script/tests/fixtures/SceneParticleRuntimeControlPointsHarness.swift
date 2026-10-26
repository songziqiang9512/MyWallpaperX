import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func syntheticVelocityDefaults() throws -> [String: Any] {
        func velocity(minimum: Any?, maximum: Any?) -> [Double] {
            var velocity: [String: Any] = ["name": "velocityrandom"]
            if let minimum { velocity["min"] = minimum }
            if let maximum { velocity["max"] = maximum }
            let definition = SceneParticleDefinitionParser().parse(root: [
                "material": "materials/unused.json",
                "maxcount": 1,
                "emitter": [[
                    "name": "sphererandom", "rate": 0, "instantaneous": 1,
                    "distancemin": 0, "distancemax": 0,
                ]],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    velocity,
                ],
                "renderer": [["name": "sprite"]],
            ])
            var simulator = SceneParticleSimulator(definition: definition, seed: 7)
            simulator.advance(by: 1.0 / 60.0)
            guard let value = simulator.particles.first?.velocity else { return [] }
            return [value.x, value.y, value.z]
        }
        return [
            "maximumOnly": velocity(minimum: nil, maximum: [0, 100, 0]),
            "minimumOnly": velocity(minimum: [0, -100, 0], maximum: nil),
            "omitted": velocity(minimum: nil, maximum: nil),
        ]
    }


    static func syntheticChildPointerControlPoint() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-child-pointer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/root.json", material: "materials/shared.json",
            lifetime: 1, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/child-force.json", "type": "eventfollow",
                "maxcount": 1, "scale": "2.5 2.5 1",
            ], [
                "name": "particles/child-emitter.json", "type": "eventfollow",
                "maxcount": 1, "scale": "2.5 2.5 1",
            ]], under: directory
        )
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "operator": [
                [
                    "name": "controlpointattract", "controlpoint": 1,
                    "origin": "0 0 0", "scale": 60, "threshold": 5,
                ],
                ["name": "movement"],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child-force.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child-emitter.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "origin": "5 0 0", "distancemin": 0, "distancemax": 0,
                "controlpoint": 1,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/child-static-emitter.json", "type": "eventfollow",
                "maxcount": 1, "scale": "2.5 2.5 1",
            ]],
        ], to: directory.appendingPathComponent("particles/root-pointer.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 0, "offset": "4 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child-static-emitter.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(18, "particles/root.json")],
            renderOrderLayerIDs: [18],
            materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let demandRuntime = SceneParticleRuntime(
            descriptor: descriptor, cacheDirectory: directory, device: device
        )
        let dynamicTarget = SceneDynamicTarget.particle(
            layerID: 18, field: .controlPoint(1)
        )
        let dynamicDefinition = SceneDynamicTargetDefinition(
            target: dynamicTarget,
            valueType: .vector3,
            authoredValue: .vector3(0, 0, 0)
        )
        let dynamicResolver = SceneDynamicSnapshotResolver()
        func dynamicSnapshot(_ value: SIMD3<Double>) -> SceneDynamicSnapshot {
            dynamicResolver.resolve(
                frameIndex: 1,
                generation: 1,
                definitions: [dynamicDefinition],
                timelineValues: [dynamicTarget: .vector3(value.x, value.y, value.z)]
            ).snapshot
        }
        func velocity(
            pointer: SIMD3<Double>?, dynamic: SIMD3<Double>? = nil
        ) -> [Float] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    dynamicValues: dynamic.map(dynamicSnapshot) ?? .empty(frameIndex: 0),
                    pointerLocalPositions: pointer.map { [18: $0] } ?? [:]
                )
            }
            guard let value = batches.first(where: {
                $0.particlePath == "particles/child-force.json"
            })?.instances.first?.velocityAndTrail else { return [] }
            return [value.x, value.y, value.z]
        }
        func emitterPositions(
            initialPointer: SIMD3<Double>?,
            recoveredPointer: SIMD3<Double>? = nil,
            dynamic: SIMD3<Double>? = nil
        ) -> [[Float]] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    dynamicValues: dynamic.map(dynamicSnapshot) ?? .empty(frameIndex: 0),
                    pointerLocalPositions: initialPointer.map { [18: $0] } ?? [:]
                )
            }
            if let recoveredPointer {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: [18: recoveredPointer]
                )
            }
            return batches.first(where: {
                $0.particlePath == "particles/child-emitter.json"
            })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        func rootPointerChildStaticPosition() -> [Float] {
            let pointerDescriptor = SceneRenderDescriptor(
                layers: [layer(19, "particles/root-pointer.json")],
                renderOrderLayerIDs: [19],
                materialPasses: descriptor.materialPasses
            )
            let runtime = SceneParticleRuntime(
                descriptor: pointerDescriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: [19: SIMD3(10, 0, 0)]
                )
            }
            guard let position = batches.first(where: {
                $0.particlePath == "particles/child-static-emitter.json"
            })?.instances.first?.positionAndSize else { return [] }
            return [position.x, position.y, position.z]
        }
        return [
            "outside": velocity(pointer: nil),
            // Root-local x=10 becomes child-local x=4 through authored scale 2.5,
            // which is inside threshold 5. Without that frame conversion it is outside.
            "insideScaled": velocity(pointer: SIMD3(10, 0, 0)),
            "dynamicInsideScaled": velocity(
                pointer: nil, dynamic: SIMD3(10, 0, 0)
            ),
            "emitterMissing": emitterPositions(initialPointer: nil),
            "emitterDynamicOnly": emitterPositions(
                initialPointer: nil, dynamic: SIMD3(10, 0, 0)
            ),
            "emitterRecovered": emitterPositions(
                initialPointer: nil, recoveredPointer: SIMD3(10, 0, 0)
            ),
            // Root pointer overlays are root-only. The root emitter's +5 origin
            // makes the event-follow child origin differ from pointer x=10:
            // authored child CP1 yields 15 + 4*2.5 = 25, while the old leak
            // would add child-local (10-15)/2.5 to CP1 and yield x=20.
            "rootPointerChildStaticPosition": rootPointerChildStaticPosition(),
            "pointerDemandLayerIDs": demandRuntime.pointerControlPointLayerIDs.sorted(),
            "rootWorldForce": try rootWorldForceRuntimeFacts(directory: directory, device: device),
        ]
    }


    static func rootWorldForceRuntimeFacts(directory: URL, device: MTLDevice) throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        for (id, name) in [(640, "world-lumen"), (1640, "renamed-force-spark")] {
            let path = "particles/\(name).json"
            func definition(flags: Int = 2, threshold: Double? = nil, warm: Bool = true, pointOffset: String = "0 0 0") -> [String: Any] {
                var force: [String: Any] = ["name": "controlpointattract", "controlpoint": 1, "scale": 60]
                if let threshold { force["threshold"] = threshold }
                return ["material": "materials/shared.json", "maxcount": 1, "flags": 0,
                    "starttime": warm ? 1.0 / 60 : 0,
                    "emitter": [["name": "boxrandom", "rate": 0, "instantaneous": 1, "distancemax": 0]],
                    "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
                    "operator": [["name": "movement", "gravity": "0 0 0"], force],
                    "renderer": [["name": "sprite"]],
                    "controlpoint": [["id": 1, "flags": flags, "offset": pointOffset]]]
            }
            try writeJSON(definition(), to: directory.appendingPathComponent(path))
            var root = layer(id, path, controlPoint: .init(110, 220, 0))
            root.originXYZ = [100, 200, 0]; root.originHasScript = true
            var d = SceneRenderDescriptor(layers: [root], renderOrderLayerIDs: [id],
                materialPasses: [.init(materialPath: "materials/shared.json", shaderPath: "genericparticle",
                                      texturePaths: ["shared.png"], blending: "additive")])
            // A carrier stores the prepared camera fact; the separate CPU gate obtains it
            // through the production JSON loader and DescriptorBuilder.
            d.camera = .init(authoredOrthographicProjectionActive: true)
            d.camera.orthoWidth = 1000; d.camera.orthoHeight = 800
            let target = SceneDynamicTarget.layer(layerID: id, field: .origin)
            func snapshot(_ origin: SIMD3<Double>) -> SceneDynamicSnapshot {
                SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                    definitions: [.init(target: target, valueType: .vector3, authoredValue: .vector3(100, 200, 0))],
                    sceneScriptValues: [target: .vector3(origin.x, origin.y, origin.z)]).snapshot
            }
            func frames(_ input: SceneDynamicSnapshot) -> [Int: simd_float4x4] {
                let byID = Dictionary(uniqueKeysWithValues: d.layers.map { ($0.id, $0) })
                return SceneLayerDynamicWorldFrameResolver.resolve(descriptor: d, byID: byID, snapshot: input,
                    staticFrames: SceneLayerWorldFrameResolver.compute(descriptor: d, byID: byID))
            }
            func velocity(_ batches: [SceneParticleDrawBatch]) -> SIMD3<Float>? {
                batches.first(where: { $0.layerID == id })?.instances.first.map {
                    SIMD3($0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z)
                }
            }
            let first = snapshot(.init(140, 260, 0)), next = snapshot(.init(80, 180, 0))
            let runtime = SceneParticleRuntime(descriptor: d, cacheDirectory: directory, device: device,
                                               initialDynamicValues: first)
            let initial = velocity(runtime.advance(by: 0, dynamicValues: first, layerWorldFrames: frames(first)))
            let updated = velocity(runtime.advance(by: 1.0 / 60, dynamicValues: next, layerWorldFrames: frames(next)))
            let missing = velocity(runtime.advance(by: 1.0 / 60, dynamicValues: next))
            let recovered = velocity(runtime.advance(by: 1.0 / 60, dynamicValues: next, layerWorldFrames: frames(next)))
            func childForceIsInert(flags: Int) throws -> (acceptedBoundary: Bool, facts: [String: Any]) {
                let childPath = "particles/\(name)-child-\(flags).json"
                try writeJSON(definition(flags: flags, warm: false, pointOffset: "100 0 0"), to: directory.appendingPathComponent(childPath))
                let parentPath = "particles/\(name)-parent-\(flags).json"
                try writeParticle(parentPath, material: "materials/shared.json", lifetime: 10, rate: 0,
                    instantaneous: 1, children: [["name": childPath, "type": "eventfollow", "maxcount": 1]], under: directory)
                let parent = layer(id + 1, parentPath)
                var childDescriptor = SceneRenderDescriptor(layers: [parent], renderOrderLayerIDs: [id + 1],
                                                            materialPasses: d.materialPasses)
                childDescriptor.camera = .init(authoredOrthographicProjectionActive: true)
                childDescriptor.camera.orthoWidth = 1000; childDescriptor.camera.orthoHeight = 800
                let childRuntime = SceneParticleRuntime(descriptor: childDescriptor, cacheDirectory: directory, device: device)
                var batches: [SceneParticleDrawBatch] = []
                for _ in 0..<2 { batches = childRuntime.advance(by: 1.0 / 60) }
                let child = batches.filter { $0.particlePath == childPath }.flatMap(\.instances)
                let systems = childRuntime.frameSnapshot().layers.compactMap(\.child).flatMap(\.systems)
                let inert = !child.isEmpty && child.allSatisfy {
                    $0.velocityAndTrail.x == 0 && $0.velocityAndTrail.y == 0 && $0.velocityAndTrail.z == 0
                }
                let healthyParent = batches.contains { $0.particlePath == parentPath && !$0.instances.isEmpty }
                var facts: [String: Any] = [
                    "childCount": child.count, "healthyParent": healthyParent,
                    "velocities": child.map { [$0.velocityAndTrail.x, $0.velocityAndTrail.y, $0.velocityAndTrail.z] },
                ]
#if DEBUG
                let diagnostics = systems.flatMap { $0.simulator.diagnostics }.map { $0.kind.rawValue }
                facts["diagnostics"] = diagnostics
                facts["unsupportedForceReported"] = diagnostics.contains("controlPointForceUnsupported")
#endif
                return (inert && healthyParent, facts)
            }
            func components(_ value: SIMD3<Float>?) -> [Float] { value.map { [$0.x, $0.y, $0.z] } ?? [] }
            let childWorld = try childForceIsInert(flags: 2), childDefault = try childForceIsInert(flags: 0)
            results.append(["name": name, "initialVelocity": components(initial), "updatedVelocity": components(updated),
                "missingVelocity": components(missing), "recoveredVelocity": components(recovered),
                "prewarmUsesInitialTypedFrame": initial.map { $0.x < -0.3 && $0.y < -0.3 } ?? false,
                "currentFrameChangesForce": initial.flatMap { a in updated.map { $0.x > a.x + 0.3 && $0.y > a.y + 0.3 } } ?? false,
                "missingCurrentFrameSkipsForce": updated != nil && updated == missing,
                "forceRecovers": missing.flatMap { a in recovered.map { $0.x > a.x + 0.3 && $0.y > a.y + 0.3 } } ?? false,
                "childWorldNotAdmitted": childWorld.acceptedBoundary,
                "childMissingDefaultNotInherited": childDefault.acceptedBoundary,
                "childWorldFacts": childWorld.facts, "childDefaultFacts": childDefault.facts])
        }
        return results
    }

    static func syntheticDynamicControlPointAngle() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-dynamic-cp-angle-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 0, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "velocityrandom", "min": [1, 0, 0], "max": [1, 0, 0]],
            ],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/angle-child.json", "type": "eventfollow", "maxcount": 1,
            ]],
        ], to: directory.appendingPathComponent("particles/root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "controlpoint": [["id": 1, "flags": 0, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 0, "instantaneous": 1,
                "distancemin": 0, "distancemax": 0, "controlpoint": 1,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "velocityrandom", "min": [1, 0, 0], "max": [1, 0, 0]],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/angle-child.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(180, "particles/root.json")],
            renderOrderLayerIDs: [180],
            materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let target = SceneDynamicTarget.particle(
            layerID: 180, field: .controlPointAngles(1)
        )
        let definition = SceneDynamicTargetDefinition(
            target: target, valueType: .vector3, authoredValue: .vector3(0, 0, 0)
        )
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ value: SceneDynamicValue) -> SceneDynamicSnapshot {
            resolver.resolve(
                frameIndex: 1, generation: 1, definitions: [definition],
                timelineValues: [target: value]
            ).snapshot
        }
        func velocities(_ values: SceneDynamicSnapshot) -> [[Float]] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor, cacheDirectory: directory, device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<2 {
                batches = runtime.advance(by: 1.0 / 60.0, dynamicValues: values)
            }
            return [
                batches.first { $0.particlePath == "particles/root.json" }?.instances.first
                    .map { [$0.velocityAndTrail.x, $0.velocityAndTrail.y] } ?? [],
                batches.first { $0.particlePath == "particles/angle-child.json" }?.instances.first
                    .map { [$0.velocityAndTrail.x, $0.velocityAndTrail.y] } ?? [],
            ]
        }
        return [
            "dynamic": velocities(snapshot(.vector3(0, 0, Double.pi / 2))),
            "fallback": velocities(.empty(frameIndex: 0)),
            "malformed": velocities(snapshot(.vector2(0, 1))),
        ]
    }

    static func syntheticDynamicControlPoint() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-dynamic-cp-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/control-point.json",
            material: "materials/shared.json",
            lifetime: 10,
            rate: 1,
            emitterControlPoint: 1,
            controlPointOffset: [1, 1, 1],
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(
                90,
                "particles/control-point.json",
                controlPoint: SIMD3(2, 3, 4)
            )],
            renderOrderLayerIDs: [90],
            materialPasses: [.init(
                materialPath: "materials/shared.json",
                shaderPath: "genericparticle",
                texturePaths: ["shared.png"],
                blending: "additive"
            )]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let target = SceneDynamicTarget.particle(layerID: 90, field: .controlPoint(1))
        let definition = SceneDynamicTargetDefinition(
            target: target,
            valueType: .vector3,
            authoredValue: .vector3(2, 3, 4)
        )
        let resolver = SceneDynamicSnapshotResolver()
        func snapshot(_ value: SceneDynamicValue, frame: UInt64) -> SceneDynamicSnapshot {
            resolver.resolve(
                frameIndex: frame,
                generation: frame,
                definitions: [definition],
                timelineValues: [target: value]
            ).snapshot
        }
        _ = runtime.advance(
            by: 1,
            dynamicValues: snapshot(.vector3(10, 20, 30), frame: 1)
        )
        _ = runtime.advance(
            by: 1,
            dynamicValues: snapshot(.vector3(-5, 6, 7), frame: 2)
        )
        let fallback = runtime.advance(by: 1)
        return [
            "positions": fallback.first?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "activeLayerIDs": runtime.activeLayerIDs,
        ]
    }



}
