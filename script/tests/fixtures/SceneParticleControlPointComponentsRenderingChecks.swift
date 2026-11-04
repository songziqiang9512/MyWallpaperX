import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

enum SceneParticleControlPointComponentsRenderingChecks {
    private static let width = 256
    private static let height = 160
    private static let material = "owned/paint.json"

    static func run() throws -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneParticleMetalPipeline(device: device) else { throw failure("device") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-cp-components-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try whitePNG(directory.appendingPathComponent("owned/white.png"))
        try Harness.writeJSON(definition(color: "0 255 0", size: 8, start: 0.5),
                              to: directory.appendingPathComponent("particles/peer.json"))
        let probe = try probePipeline(device)
        var rows: [[String: Any]] = []

        let worldCP: [[String: Any]] = [["id": 0, "flags": 0, "offset": "0 0 0"],
                                       ["id": 1, "flags": 2, "offset": "16 24 0"]]
        try Harness.writeJSON(definition(count: 4, rate: 1, size: 16, points: worldCP,
            between: ["name": "mapsequencebetweencontrolpoints", "count": 3, "flags": 23]),
            to: directory.appendingPathComponent("particles/world.json"))
        var worldLayer = Harness.layer(101, "particles/world.json", particleCount: 2,
                                       controlPoint: SIMD3(64, 79.5, 0))
        worldLayer.originXYZ = [192, 79.5, 0]; worldLayer.scaleXYZ = [-1.5, 0.75, 1]
        let worldDescriptor = descriptor(worldLayer)
        let worldFrames = frames(worldDescriptor)
        let world = SceneParticleRuntime(descriptor: worldDescriptor, cacheDirectory: directory,
            device: device, stockTextureBundleURL: nil)
        var batches = world.advance(by: 1.0 / 60, layerWorldFrames: worldFrames)
        rows.append(try draw("world-between23", runtime: world, batches: batches,
            descriptor: worldDescriptor, worldFrames: worldFrames, device: device, queue: queue,
            pipeline: pipeline, probe: probe,
            pixels: [[192, 80], [166, 80], [141, 80], [115, 80], [32, 130], [64, 80]]))
        // Real Runtime must replace the old frame with nil before these new births.
        batches = world.advance(by: 1, layerWorldFrames: [:])
        rows.append(try draw("world-missing-frame", runtime: world, batches: batches,
            descriptor: worldDescriptor, worldFrames: worldFrames, device: device, queue: queue,
            pipeline: pipeline, probe: probe, pixels: [[192, 80], [32, 130], [64, 80]]))

        let localCP: [[String: Any]] = [["id": 0, "flags": 0, "offset": "0 0 0"],
                                       ["id": 1, "flags": 0, "offset": "64 0 0"]]
        try Harness.writeJSON(definition(origin: "16 8 0", points: localCP, velocity: "0 8 0",
            operators: [["name": "movement", "drag": 0, "gravity": "0 0 0"],
                        ["name": "maintaindistancebetweencontrolpoints"]]),
            to: directory.appendingPathComponent("particles/maintain.json"))
        var movingLayer = Harness.layer(102, "particles/maintain.json")
        movingLayer.originXYZ = [48, 95.5, 0]
        let movingDescriptor = descriptor(movingLayer), movingFrames = frames(movingDescriptor)
        let moving = SceneParticleRuntime(descriptor: movingDescriptor, cacheDirectory: directory,
            device: device, stockTextureBundleURL: nil)
        let first = snapshot(layerID: 102, start: SIMD3(0, 0, 0), end: SIMD3(64, 0, 0), frame: 1)
        let next = snapshot(layerID: 102, start: SIMD3(16, 0, 0), end: SIMD3(144, 0, 0), frame: 2)
        for _ in 0..<30 { batches = moving.advance(by: 1.0 / 60, dynamicValues: first, layerWorldFrames: movingFrames) }
        rows.append(try draw("maintain-before", runtime: moving, batches: batches,
            descriptor: movingDescriptor, worldFrames: movingFrames, device: device, queue: queue,
            pipeline: pipeline, probe: probe, pixels: [[64, 52], [96, 48], [32, 130]]))
        for _ in 0..<30 { batches = moving.advance(by: 1.0 / 60, dynamicValues: next, layerWorldFrames: movingFrames) }
        rows.append(try draw("maintain-after", runtime: moving, batches: batches,
            descriptor: movingDescriptor, worldFrames: movingFrames, device: device, queue: queue,
            pipeline: pipeline, probe: probe, pixels: [[96, 48], [64, 52], [32, 130]]))

        let prewarmCP: [[String: Any]] = [["id": 0, "flags": 0, "offset": "0 0 0"],
                                         ["id": 1, "flags": 2, "offset": "96 127.5 0"]]
        try Harness.writeJSON(definition(count: 3, start: 0.5, points: prewarmCP,
            between: ["name": "mapsequencebetweencontrolpoints", "count": 3]),
            to: directory.appendingPathComponent("particles/prewarm.json"))
        var warmLayer = Harness.layer(103, "particles/prewarm.json")
        warmLayer.originXYZ = [32, 127.5, 0]
        let warmDescriptor = descriptor(warmLayer), warmFrames = frames(warmDescriptor)
        let initial = snapshot(layerID: 103, start: SIMD3(0, 0, 0), end: SIMD3(160, 127.5, 0), frame: 0)
        let warm = SceneParticleRuntime(descriptor: warmDescriptor, cacheDirectory: directory,
            device: device, stockTextureBundleURL: nil, initialDynamicValues: initial)
        batches = warm.advance(by: 0, dynamicValues: initial, layerWorldFrames: warmFrames)
        rows.append(try draw("prewarm-initial-cp128", runtime: warm, batches: batches,
            descriptor: warmDescriptor, worldFrames: warmFrames, device: device, queue: queue,
            pipeline: pipeline, probe: probe,
            pixels: [[32, 32], [96, 32], [160, 32], [64, 32], [32, 130]]))
        let childPoints: [[String: Any]] = [["id": 0, "flags": 0, "offset": "0 0 0"],
                                           ["id": 1, "flags": 2, "offset": "64 80 0"]]
        try Harness.writeJSON(definition(count: 3, points: childPoints,
            between: ["name": "mapsequencebetweencontrolpoints", "count": 3]),
            to: directory.appendingPathComponent("particles/static-child.json"))
        var childRoot = definition(count: 0)
        childRoot["children"] = [["name": "particles/static-child.json", "type": "static",
                                  "origin": "16 12 0", "scale": "2 2 2"]]
        try Harness.writeJSON(childRoot, to: directory.appendingPathComponent("particles/child-root.json"))
        var childLayer = Harness.layer(104, "particles/child-root.json")
        childLayer.originXYZ = [192, 80, 0]; childLayer.scaleXYZ = [-1.5, 0.75, 1]
        let childDescriptor = descriptor(childLayer), childFrames = frames(childDescriptor)
        let childRuntime = SceneParticleRuntime(descriptor: childDescriptor, cacheDirectory: directory,
            device: device, stockTextureBundleURL: nil)
        batches = childRuntime.advance(by: 1.0 / 60, layerWorldFrames: childFrames)
        var childRow = try draw("static-child-world-between", runtime: childRuntime, batches: batches,
            descriptor: childDescriptor, worldFrames: childFrames, device: device, queue: queue,
            pipeline: pipeline, probe: probe,
            pixels: [[168, 71], [116, 75], [64, 80], [32, 130], [96, 80], [192, 80]])
        let childState = childRuntime.frameSnapshot().layers[0]
        let systems = childState.child?.systems ?? []
        childRow["childPopulation"] = childRuntime.lifecycleSnapshot.childParticleCount
        childRow["childSystemCount"] = childRuntime.lifecycleSnapshot.childSystemCount
        childRow["rootTargetPopulation"] = childState.root?.simulatorFrame.particles.count ?? 0
        childRow["childPositions"] = systems.flatMap { $0.simulatorFrame.particles }.map {
            [$0.position.x, $0.position.y, $0.position.z]
        }
        childRow["childOrigins"] = systems.map { [$0.origin.x, $0.origin.y, $0.origin.z] }
        childRow["childHasPointFrame"] = systems.map { $0.simulatorFrame.controlPointFrame != nil }
        rows.append(childRow)
        let followPoints: [[String: Any]] = [["id": 0, "flags": 2, "offset": "50 80 0"],
                                            ["id": 1, "flags": 2, "offset": "100 80 0"]]
        var followDefinition = definition(origin: "25 0 0", points: followPoints,
            operators: [["name": "maintaindistancebetweencontrolpoints"]])
        followDefinition["flags"] = 1
        var followEmitters = followDefinition["emitter"] as! [[String: Any]]
        followEmitters[0]["controlpoint"] = 0
        followDefinition["emitter"] = followEmitters
        var followWriters = followDefinition["initializer"] as! [[String: Any]]
        followWriters[0]["min"] = 120; followWriters[0]["max"] = 120
        followDefinition["initializer"] = followWriters
        try Harness.writeJSON(followDefinition, to: directory.appendingPathComponent("particles/follow-world.json"))
        var followRoot = definition(velocity: "10 0 0",
            operators: [["name": "movement", "drag": 0, "gravity": "0 0 0"]])
        var parentWriters = followRoot["initializer"] as! [[String: Any]]
        parentWriters[0]["min"] = 120; parentWriters[0]["max"] = 120
        parentWriters[3]["min"] = 0; parentWriters[3]["max"] = 0
        followRoot["initializer"] = parentWriters
        followRoot["children"] = [["name": "particles/follow-world.json", "type": "eventfollow", "maxcount": 1]]
        try Harness.writeJSON(followRoot, to: directory.appendingPathComponent("particles/follow-parent.json"))
        let followDescriptor = descriptor(Harness.layer(105, "particles/follow-parent.json"))
        let followFrames = frames(followDescriptor)
        let follow = SceneParticleRuntime(descriptor: followDescriptor, cacheDirectory: directory,
            device: device, stockTextureBundleURL: nil)
        _ = follow.advance(by: 1, layerWorldFrames: followFrames)
        for stage in [2, 3] {
            let followBatches = follow.advance(by: 1, layerWorldFrames: followFrames)
            var row = try draw("follow-world-\(stage)", runtime: follow, batches: followBatches,
                descriptor: followDescriptor, worldFrames: followFrames, device: device, queue: queue,
                pipeline: pipeline, probe: probe, pixels: [[75, 80], [65, 80], [32, 130]], expectedBatchCount: 3)
            let followState = follow.frameSnapshot().layers[0]
            let childSystems = followState.child?.systems ?? []
            row["childPopulation"] = follow.lifecycleSnapshot.childParticleCount
            row["childSystemCount"] = follow.lifecycleSnapshot.childSystemCount
            row["childOrigins"] = childSystems.map { [$0.origin.x, $0.origin.y, $0.origin.z] }
            row["childPositions"] = childSystems.flatMap { $0.simulatorFrame.particles }.map {
                [$0.position.x, $0.position.y, $0.position.z]
            }
            row["childIDs"] = childSystems.flatMap { $0.simulatorFrame.particles.map { String($0.id) } }
            row["childBirthOrigins"] = childSystems.map { system in
                Dictionary(uniqueKeysWithValues: system.particleOrigins.map {
                    (String($0.key), [$0.value.x, $0.value.y, $0.value.z])
                })
            }
            row["childHasPointFrame"] = childSystems.map { $0.simulatorFrame.controlPointFrame != nil }
            row["rootAlpha"] = followState.root!.simulatorFrame.particles.map(\.alpha)
            row["childBatchPositions"] = followBatches.filter { $0.particlePath == "particles/follow-world.json" }
                .flatMap(\.instances).map { [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z] }
            rows.append(row)
        }
        return ["device": device.name, "sampleCount": 1, "rows": rows]
    }

    private static func definition(
        color: String = "255 0 0", origin: String = "0 0 0", count: Int = 1,
        rate: Double = 0, size: Double = 8, start: Double = 0,
        points: [[String: Any]] = [], velocity: String? = nil,
        between: [String: Any]? = nil, operators: [[String: Any]] = []
    ) -> [String: Any] {
        var initializers: [[String: Any]] = [
            ["name": "lifetimerandom", "min": 20, "max": 20],
            ["name": "sizerandom", "min": size, "max": size],
            ["name": "colorrandom", "min": color, "max": color],
            ["name": "alpharandom", "min": 1, "max": 1],
        ]
        if let velocity { initializers.append(["name": "velocityrandom", "min": velocity, "max": velocity]) }
        if let between { initializers.append(between) }
        return ["material": material, "maxcount": 32, "starttime": start, "flags": 0,
                "controlpoint": points,
                "emitter": [["name": "sphererandom", "instantaneous": count, "rate": rate,
                    "origin": origin, "directions": "1 0 0", "distancemin": 0, "distancemax": 0,
                    "speedmin": 0, "speedmax": 0]],
                "initializer": initializers, "operator": operators, "renderer": [["name": "sprite"]]]
    }

    private static func descriptor(_ layer: SceneRenderDescriptor.Layer) -> SceneRenderDescriptor {
        var peer = Harness.layer(201, "particles/peer.json")
        peer.originXYZ = [32, 29.5, 0]
        var result = SceneRenderDescriptor(layers: [layer, peer], renderOrderLayerIDs: [layer.id, peer.id],
            materialPasses: [.init(materialPath: material, shaderPath: "genericparticle",
                texturePaths: ["owned/white.png"], blending: "translucent")])
        result.camera = .init(authoredOrthographicProjectionActive: true)
        result.camera.orthoWidth = Float(width); result.camera.orthoHeight = Float(height)
        return result
    }

    private static func frames(_ descriptor: SceneRenderDescriptor) -> [Int: simd_float4x4] {
        SceneLayerWorldFrameResolver.compute(descriptor: descriptor,
            byID: Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }))
    }

    private static func snapshot(
        layerID: Int, start: SIMD3<Double>, end: SIMD3<Double>, frame: UInt64
    ) -> SceneDynamicSnapshot {
        let a = SceneDynamicTarget.particle(layerID: layerID, field: .controlPoint(0))
        let b = SceneDynamicTarget.particle(layerID: layerID, field: .controlPoint(1))
        return SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: frame,
            definitions: [.init(target: a, valueType: .vector3, authoredValue: .vector3(0, 0, 0)),
                          .init(target: b, valueType: .vector3, authoredValue: .vector3(64, 0, 0))],
            sceneScriptValues: [a: .vector3(start.x, start.y, start.z), b: .vector3(end.x, end.y, end.z)]).snapshot
    }

    private static func draw(
        _ name: String, runtime: SceneParticleRuntime, batches: [SceneParticleDrawBatch],
        descriptor: SceneRenderDescriptor, worldFrames: [Int: simd_float4x4],
        device: MTLDevice, queue: MTLCommandQueue, pipeline: SceneParticleMetalPipeline,
        probe: MTLRenderPipelineState, pixels: [[Int]], expectedBatchCount: Int = 2
    ) throws -> [String: Any] {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        td.storageMode = .shared; td.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: td), let command = queue.makeCommandBuffer()
        else { throw failure("target") }
        let camera = SceneParticleCameraFrame(camera: descriptor.camera,
            viewportSize: CGSize(width: width, height: height))
        let prepared = pipeline.prepare(batches)
        guard prepared.count == expectedBatchCount else { throw failure("runtime-batches:\(name)") }
        var records: [(SceneParticleMetalPipeline.PreparedBatch, SceneParticleLayerUniforms, MTLBuffer)] = []
        for batch in prepared {
            guard let world = worldFrames[batch.draw.layerID],
                  let state = batch.instanceBuffer.currentDrawState(),
                  batch.instanceBuffer.armSubmission(on: command),
                  let positions = device.makeBuffer(length: state.count * 4 * 16, options: .storageModeShared)
            else { throw failure("runtime-instance-buffer") }
            var uniforms = camera.particleUniforms(layerModel: SceneParticleCameraFrame.particleLayerModel(
                worldFrame: world, parallaxOffset: .zero), orientation: batch.draw.orientation,
                orientationAxis: batch.draw.orientationAxis, usesPerspective: batch.draw.usesPerspective,
                usesSceneCamera: batch.draw.renderState.usesSceneCamera,
                inheritsNativeSceneCamera: batch.draw.inheritsNativeSceneCamera,
                viewportSize: SIMD2(Float(width), Float(height)), sizeIsWorldSpace: batch.draw.sizeIsWorldSpace)
            let pass = MTLRenderPassDescriptor()
            pass.renderTargetWidth = 1; pass.renderTargetHeight = 1; pass.defaultRasterSampleCount = 1
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw failure("probe-encoder") }
            var quad: [SIMD4<Float>] = [SIMD4(-0.5, -0.5, 0, 1), SIMD4(0.5, -0.5, 1, 1),
                                      SIMD4(-0.5, 0.5, 0, 0), SIMD4(0.5, 0.5, 1, 0)]
            encoder.setRenderPipelineState(probe)
            encoder.setVertexBytes(&quad, length: 64, index: 0)
            encoder.setVertexBuffer(state.buffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneParticleLayerUniforms>.stride, index: 2)
            encoder.setVertexBuffer(positions, offset: 0, index: 3)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 4, instanceCount: state.count)
            encoder.endEncoding()
            records.append((batch, uniforms, positions))
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw failure("draw-encoder") }
        var encoded: [Bool] = []
        for (batch, uniforms, _) in records {
            encoded.append(pipeline.draw(texture: batch.draw.texture, instances: batch.instanceBuffer,
                uniforms: uniforms, renderState: batch.draw.renderState,
                colorUVScale: batch.draw.colorUVScale, colorSampling: batch.draw.colorSampling, encoder: encoder))
        }
        encoder.endEncoding()
        for (batch, _, _) in records {
            guard batch.instanceBuffer.markSubmitted(on: command) else { throw failure("submission") }
        }
        let completed = SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        guard completed else { throw command.error ?? failure("completion") }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let sampled = pixels.map { p -> [Int] in
            let offset = (p[1] * width + p[0]) * 4
            return [Int(bytes[offset + 2]), Int(bytes[offset + 1]), Int(bytes[offset]), Int(bytes[offset + 3])]
        }
        let state = runtime.frameSnapshot().layers[0].root!.simulatorFrame
        let geometry: [[[Double]]] = records.map { batch, _, buffer in
            let values = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: batch.draw.instances.count * 4)
            return batch.draw.instances.indices.map { index in
                let vertices = (0..<4).map { values[index * 4 + $0] }
                let xs = vertices.map { Double(($0.x / $0.w + 1) * Float(width) / 2) }
                let ys = vertices.map { Double((1 - $0.y / $0.w) * Float(height) / 2) }
                return [xs.min()!, ys.min()!, xs.max()!, ys.max()!]
            }
        }
        return ["name": name, "activeLayerIDs": runtime.activeLayerIDs, "encoded": encoded,
                "completed": completed, "rootPopulation": runtime.lifecycleSnapshot.rootParticleCount,
                "batchLayerIDs": prepared.map { $0.draw.layerID },
                "instances": prepared.map { $0.draw.instances.count }, "vertexBounds": geometry,
                "positions": state.particles.map { [$0.position.x, $0.position.y, $0.position.z] },
                "sizes": state.particles.map(\.size), "ages": state.particles.map(\.age),
                "hasPointFrame": state.controlPointFrame != nil,
                "dynamicControlPoints": Dictionary(uniqueKeysWithValues: state.dynamicControlPoints.map {
                    (String($0.key), [$0.value.x, $0.value.y, $0.value.z])
                }),
                "pixelCoordinates": pixels, "rgba": sampled,
                "particlePaths": prepared.map { $0.draw.particlePath },
                "textureExtents": prepared.map { [$0.draw.texture.width, $0.draw.texture.height] }]
    }

    private static func probePipeline(_ device: MTLDevice) throws -> MTLRenderPipelineState {
        let source = sceneParticleShaderSource + """
        vertex void componentProbe(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
            constant QuadVertex *quad [[buffer(0)]], device const ParticleInstance *instances [[buffer(1)]],
            constant LayerUniforms &uniforms [[buffer(2)]], device float4 *positions [[buffer(3)]]) {
            Varyings result = particleVertex(vertexID, instanceID, quad, instances, uniforms, false);
            positions[instanceID * 4 + vertexID] = result.position;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "componentProbe")
        descriptor.isRasterizationEnabled = false
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func whitePNG(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let output = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw failure("white-source") }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        guard let image = context.makeImage() else { throw failure("white-image") }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw failure("white-write") }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "particle-control-point-runtime-rendering", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
