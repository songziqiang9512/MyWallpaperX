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
        let volume = input["volume"] as! Bool
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
            result.depthTest = pass["depthtest"] as? String
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
            if volume {
                layers[index].utilityLayer = nil
                layers[index].usesPerspective = true
            }
        }
        layers[0].alpha = (input["layerAlpha"] as! NSNumber).doubleValue
        layers[1].alpha = (input["farLayerAlpha"] as! NSNumber).doubleValue
        let farFirst = input["farFirst"] as! Bool
        var order = farFirst ? Array(ids.reversed()) : ids
        if volume {
            var light = SceneRenderDescriptor.Layer(id: 99)
            light.contentKind = "pointLight"
            light.pointLight = ScenePointLightDefinition.parse(["light": "lpoint",
                "castvolumetrics": true, "density": 1, "volumetricsexponent": 2, "castshadow": false])!
            layers.append(light)
            order.append(99)
        }
        var descriptor = SceneRenderDescriptor(lighting: nil, layers: layers,
            renderOrderLayerIDs: order, materialPasses: passes)
        descriptor.camera = .init(eye: volume ? [32,32,100] : [0,0,0],
            center: volume ? [32,32,0] : [0,0,-1], up: [0,1,0],
            orthoWidth: volume ? nil : 64, orthoHeight: volume ? nil : 64,
            fovDegrees: volume ? 60 : nil,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 1000)
        let loader = try SceneTextureLoader(root: directory, device: device)
        var sources = try prepareModelSources(descriptor, view: .init(root: directory))
        let materialPlan = try ScenePreparedStaticModelResources.compileMaterialPlan(
            descriptor: descriptor, resourceView: .init(root: directory), cancellationCheck: {})
        let assets = try SceneStaticModelAssetInputs(materialPlan: materialPlan, resourceView: .init(root: directory),
            descriptor: descriptor, loader: loader, device: device)
        let resources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor,
            resourceView: .init(root: directory), device: device, textureLoader: loader,
            materialPlan: materialPlan, albedoStates: assets.launchStates,
            preparedSources: &sources, cancellationCheck: {})
        let renderer = SceneMetalRenderer(device: device, resources: resources)
        assets.publish(to: renderer.textureRegistry)
        renderer.renderDescriptor = descriptor
        let worlds = SceneLayerWorldFrameResolver.compute(descriptor: descriptor,
            byID: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) }))
        let camera = SceneParticleCameraFrame(camera: descriptor.camera,
            viewportSize: CGSize(width: 64, height: 64))
        if volume {
            precondition(camera.defaultsToPerspective && resources.pipeline!.supportsCameraDepth)
            for (index, z) in [Float(10), -10].enumerated() {
                precondition(camera.resolvesPerspective(for: layers[index]))
                let center = camera.reverseDepthViewProjection(usesPerspective: true)
                    * renderer.staticModelWorld(for: ids[index], worldFrames: worlds) * SIMD4<Float>(32,32,z,1)
                precondition(center.w > 0 && abs(center.x / center.w) < 0.00001
                    && abs(center.y / center.w) < 0.00001 && center.z / center.w > 0
                    && center.z / center.w < 1)
            }
        }
        let dynamic = SceneDynamicSnapshot.empty(frameIndex: 1, generation: 1)
        let lighting = SceneLightSnapshot(ambient: .zero, skylight: .zero,
            directional: [], point: [], spot: [], overflowCount: 0)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 64, height: 64, mipmapped: false)
        td.storageMode = .shared; td.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: td)!, cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: output,
            clearColor: MTLClearColorMake(0,0,0,0), clearEnabled: true)
        let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: cb, collectsVolumeOccluders: volume)
        var leases: [SceneParticleDepthTargetLease] = []
        var selected = [(0, input["near"] as! Bool), (1, input["far"] as! Bool)]
        if farFirst { selected.reverse() }
        for (index, enabled) in selected where enabled {
            _ = renderer.drawStaticModel(layer: layers[index], state: state, worldFrames: worlds,
                frameContext: .init(dynamicValues: dynamic), cameraFrame: camera, lighting: lighting,
                pass: pass, commandBuffer: cb, leases: &leases)
        }
        // Empty control still uses the actual frame depth owner, then clears it
        // through MainPassEncoder exactly as a normal first model would.
        let preparedDepth = state.sharedDepth(pass: pass, pool: renderer.staticModelDepthTargetPool,
            device: device, commandBuffer: cb, leases: &leases)
        if selected.allSatisfy({ !$0.1 }) {
            precondition(state.sceneDepthEncoder(pass: pass, commandBuffer: cb) != nil)
        }
        let volumePool = volume ? SceneOffscreenTexturePool(device: device,
            residentByteBudget: 8 * 1024 * 1024) : nil
        let volumeDepth = volume ? renderer.encodeVolumeOccluderDepth(state: state, pass: pass,
            pool: volumePool, groups: nil, needsTerminalScratch: false) : nil
        if volume { precondition(volumeDepth != nil) }
        precondition(pass.finishEnsuringClear())
        let depth = preparedDepth.lease!.texture
        let buffer = device.makeBuffer(length: volume ? 512 : 256, options: .storageModeShared)!
        let blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: depth, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: .init(x: 32,y: 32,z: 0), sourceSize: .init(width: 1,height: 1,depth: 1),
            to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        if let volumeDepth {
            blit.copy(from: volumeDepth, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: .init(x: 32,y: 32,z: 0), sourceSize: .init(width: 1,height: 1,depth: 1),
                to: buffer, destinationOffset: 256, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        }
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
        var result: [String: Any] = ["name": name, "prepared": resources[ids[0]]?.count == 1 && resources[ids[1]]?.count == 1,
            "preparedBlend": resources[ids[0]]![0].materialBlending?.rawValue ?? "unresolved",
            "preparedFarBlend": resources[ids[1]]![0].materialBlending?.rawValue ?? "unresolved",
            "opacity": resources[ids[0]]![0].material.opacity,
            "preparedWritesDepth": ids.map { resources[$0]![0].writesDepth },
            "rgba": rgba(32,32), "outside": rgba(1,1),
            "depth": buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee,
            "leases": leases.count, "sharedDepth": preparedDepth.lease != nil,
            "encoded": selected.allSatisfy { index, enabled in
                !enabled || renderer.dependencyRuntime.encoded[ids[index]] == true
            }, "completed": true]
        if volume {
            result["volumeDepth"] = buffer.contents().advanced(by: 256)
                .bindMemory(to: Float.self, capacity: 1).pointee
        }
        return result
    }
}
