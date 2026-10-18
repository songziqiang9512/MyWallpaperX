// Inputs and readbacks only: all material, world, depth and draw logic is production.
@main enum SceneStaticModelBlendChecks {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let root = URL(fileURLWithPath: input["root"] as! String)
        var rows: [[String: Any]] = []
        for item in input["cases"] as! [[String: Any]] {
            rows.append(try run(item, root: root, device: device, queue: queue))
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows],
            options: [.sortedKeys]), as: UTF8.self))
    }

    static func run(_ input: [String: Any], root: URL, device: MTLDevice,
                    queue: MTLCommandQueue) throws -> [String: Any] {
        let name = input["name"] as! String, directory = root.appendingPathComponent(name)
        let renamed = input["renamed"] as! Bool
        let stems = renamed ? ["ember_surface", "sky_surface"] : ["red", "blue"]
        let ids = renamed ? [407, 901] : [1, 2]
        var passes = try stems.map { stem -> SceneRenderDescriptor.MaterialPassDescriptor in
            let data = try Data(contentsOf: directory.appendingPathComponent("materials/\(stem).json"))
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let pass = (object["passes"] as! [[String: Any]])[0]
            let constants = (pass["constantshadervalues"] as! [String: NSNumber]).mapValues {
                SceneDocument.ShaderValue(components: [$0.doubleValue])
            }
            var result = SceneRenderDescriptor.MaterialPassDescriptor(
                materialPath: "materials/\(stem).json", textureSlots: pass["textures"] as! [String],
                combos: pass["combos"] as! [String: Int], constantShaderValues: constants,
                depthWrite: pass["depthwrite"] as? String)
            result.blending = pass["blending"] as? String
            result.cullMode = pass["cullmode"] as? String
            result.shaderPath = pass["shader"] as? String
            return result
        }
        if renamed { passes.reverse() }
        var layers = ids.enumerated().map { index, id in
            SceneRenderDescriptor.Layer(id: id, staticModelPath: "models/\(stems[index]).mdl")
        }
        // The reused quad helper is canonical-down. Explicit author Y scale
        // cancels the already-qualified static-model local F; no camera rescue.
        for index in layers.indices {
            layers[index].originXYZ = [0, 64, 0]
            layers[index].scaleXYZ = [1, -1, 1]
        }
        layers[0].alpha = (input["layerAlpha"] as! NSNumber).doubleValue
        var descriptor = SceneRenderDescriptor(lighting: nil, layers: layers,
            renderOrderLayerIDs: ids, materialPasses: passes)
        descriptor.camera = .init(eye: [0,0,0], center: [0,0,-1], up: [0,1,0],
            orthoWidth: 64, orthoHeight: 64, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 1000)
        let loader = try SceneTextureLoader(root: directory, device: device)
        let resources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor,
            resourceView: .init(root: directory), device: device, textureLoader: loader,
            cancellationCheck: {})
        let renderer = SceneMetalRenderer(device: device, resources: resources)
        renderer.renderDescriptor = descriptor
        let worlds = SceneLayerWorldFrameResolver.compute(descriptor: descriptor,
            byID: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) }))
        let camera = SceneParticleCameraFrame(camera: descriptor.camera,
            viewportSize: CGSize(width: 64, height: 64))
        let dynamic = SceneDynamicSnapshot.empty(frameIndex: 1, generation: 1)
        let lighting = SceneLightSnapshot(ambient: .zero, skylight: .zero,
            directional: [], point: [], spot: [], overflowCount: 0)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 64, height: 64, mipmapped: false)
        td.storageMode = .shared; td.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: td)!, cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: output,
            clearColor: MTLClearColorMake(0,0,0,0), clearEnabled: true)
        let state = SceneMetalRenderer.StaticModelFrame()
        var leases: [SceneParticleDepthTargetLease] = []
        let selected = [(0, input["near"] as! Bool), (1, input["far"] as! Bool)]
        for (index, enabled) in selected where enabled {
            _ = renderer.drawStaticModel(layer: layers[index], state: state, worldFrames: worlds,
                frameContext: .init(dynamicValues: dynamic), cameraFrame: camera, lighting: lighting,
                pass: pass, commandBuffer: cb, leases: &leases)
        }
        // Empty control still uses the actual frame depth owner, then clears it
        // through MainPassEncoder exactly as a normal first model would.
        if leases.isEmpty {
            let draw = renderer.staticModelDraws(layer: layers[0], worldFrames: worlds, snapshot: dynamic)![0]
            let depth = state.depth(for: draw, pass: pass, pool: renderer.staticModelDepthTargetPool,
                device: device, leases: &leases)
            precondition(pass.encoder(depthTexture: depth.lease!.texture, clearsDepth: true, clearDepth: 0) != nil)
        }
        precondition(pass.finishEnsuringClear())
        let depth = state.sharedLease!.texture
        let buffer = device.makeBuffer(length: 256, options: .storageModeShared)!
        let blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: depth, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: .init(x: 32,y: 32,z: 0), sourceSize: .init(width: 1,height: 1,depth: 1),
            to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        blit.endEncoding()
        leases.forEach { $0.arm(on: cb) }; state.arm(on: cb)
        cb.commit(); cb.waitUntilCompleted()
        precondition(cb.status == .completed && cb.error == nil)
        func rgba(_ x: Int, _ y: Int) -> [Int] {
            var bytes = [UInt8](repeating: 0, count: 4)
            output.getBytes(&bytes, bytesPerRow: 4,
                from: MTLRegionMake2D(x,y,1,1), mipmapLevel: 0)
            return [Int(bytes[2]), Int(bytes[1]), Int(bytes[0]), Int(bytes[3])]
        }
        return ["name": name, "prepared": resources[ids[0]]?.count == 1 && resources[ids[1]]?.count == 1,
            "preparedBlend": resources[ids[0]]![0].materialBlending?.rawValue ?? "unresolved",
            "opacity": resources[ids[0]]![0].material.opacity,
            "rgba": rgba(32,32), "outside": rgba(1,1),
            "depth": buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee,
            "leases": leases.count, "sharedDepth": state.sharedLease != nil,
            "encoded": selected.allSatisfy { index, enabled in
                !enabled || renderer.dependencyRuntime.encoded[ids[index]] == true
            }, "completed": true]
    }
}
