// External texture transport and pixel readback; material preparation and draw are production.
@main enum SceneStaticModelNormalChecks {
    static func main() throws {
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let root = URL(fileURLWithPath: input["root"] as! String)
        let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
        var rows: [[String: Any]] = []
        for item in input["cases"] as! [[String: Any]] {
            rows.append(try autoreleasepool { try run(item, root: root, device: device, queue: queue) })
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows],
            options: [.sortedKeys]), as: UTF8.self))
    }

    static func run(_ item: [String: Any], root: URL, device: MTLDevice,
                    queue: MTLCommandQueue) throws -> [String: Any] {
        let name = item["name"] as! String, folder = root.appendingPathComponent(name)
        func number(_ key: String) -> Float { (item[key] as! NSNumber).floatValue }
        func vector(_ key: String) -> SIMD3<Float> {
            let values = item[key] as! [NSNumber]
            return SIMD3(values[0].floatValue, values[1].floatValue, values[2].floatValue)
        }
        let renamed = item["renamed"] as! Bool
        let modelPath = renamed ? "models/alternate-body.mdl" : "models/input.mdl"
        let materialPath = renamed ? "materials/alternate-surface.json" : "materials/input.json"
        let normalRelative = renamed ? "materials/surface-vectors.png" : "materials/normal.png"
        let combo = Int(number("normalCombo"))
        var combos = ["LIGHTING": 1]
        if combo >= 0 { combos["NORMALMAP"] = combo }
        let reflection = item["reflection"] as! Bool
        if reflection { combos["REFLECTION"] = 1 }
        var primary = SceneRenderDescriptor.MaterialPassDescriptor(materialPath: materialPath,
            textureSlots: ["materials/white.png", normalRelative], combos: combos,
            constantShaderValues: ["alpha": .init(components: [Double(number("alpha"))]),
                "roughness": .init(components: [1])])
        primary.shaderPath = item["shader"] as? String
        primary.cullMode = "nocull"; primary.blending = item["additive"] as! Bool ? "additive" : "translucent"
        var farPass = SceneRenderDescriptor.MaterialPassDescriptor(materialPath: "materials/far.json",
            textureSlots: ["materials/blue.png"], combos: ["LIGHTING": 0], constantShaderValues: [:])
        farPass.shaderPath = "generic4"; farPass.cullMode = "nocull"; farPass.blending = "normal"
        var near = SceneRenderDescriptor.Layer(id: 7, staticModelPath: modelPath)
        near.utilityLayer = nil; near.usesPerspective = true; near.originXYZ = [0, 0, 0]
        near.scaleXYZ = [vector("scale").x, vector("scale").y, vector("scale").z]
        near.anglesXYZ = [0, 0, number("rotation")]
        var far = SceneRenderDescriptor.Layer(id: 9, staticModelPath: "models/far.mdl")
        far.utilityLayer = nil; far.usesPerspective = true; far.originXYZ = [0, 0, 0]
        var descriptor = SceneRenderDescriptor(lighting: nil, layers: [near, far],
            renderOrderLayerIDs: [7, 9], materialPasses: [primary, farPass])
        descriptor.camera = .init(eye: [0, 0, 160], center: [0, 0, 0], up: [0, 1, 0],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: 60,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 1000)
        let loader = try SceneTextureLoader(root: folder, device: device)
        let width = Int(number("width")), storage = item["storage"] as! String
        let format: MTLPixelFormat = storage == "bc5" ? .bc5_rgSnorm
            : storage == "rg" ? .rg8Unorm : .rgba8Unorm
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: storage == "bc5" ? 4 : width, height: storage == "bc5" ? 4 : 1, mipmapped: false)
        td.storageMode = .shared; td.usage = .shaderRead
        let normalTexture = device.makeTexture(descriptor: td)!
        let pixels: [UInt8] = storage == "bc5" ? [127, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            : (item["pixels"] as! [NSNumber]).map(\.uint8Value)
        pixels.withUnsafeBytes { normalTexture.replace(region: MTLRegionMake2D(0, 0, td.width, td.height),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: storage == "bc5" ? 16
                : width * (storage == "rg" ? 2 : 4)) }
        let normalPath = folder.appendingPathComponent(normalRelative).resolvingSymlinksInPath().path
        let sourceFormat = Int(number("format"))
        loader.candidates[normalPath] = .init(texture: normalTexture, identity: .file(path: normalPath),
            generation: .immutable(revision: 1), purpose: .normal, content: .data,
            physicalSize: CGSize(width: td.width, height: td.height), mappedSize: CGSize(width: td.width, height: td.height),
            uvTransform: .init(origin: SIMD2(number("frameOffset"), 0),
                xAxis: SIMD2(number("frameScale"), 0), yAxis: SIMD2(0, 1)),
            sampling: .init(texFlags: (item["nearest"] as! Bool ? 1 : 0)
                | (item["repeat"] as! Bool ? 0 : 2)),
            authoredFormat: sourceFormat >= 0 ? SceneShaderTextureFormat(rawValue: UInt32(sourceFormat)) : nil)
        var sources = try prepareModelSources(descriptor, view: .init(root: folder))
        let resources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor,
            resourceView: .init(root: folder), device: device, textureLoader: loader,
            preparedSources: &sources, cancellationCheck: {})
        precondition(resources[7]?.count == 1 && resources[9]?.count == 1, "Prepared geometry: " + name)
        let renderer = SceneMetalRenderer(device: device, resources: resources)
        renderer.renderDescriptor = descriptor
        let worlds = SceneLayerWorldFrameResolver.compute(descriptor: descriptor,
            byID: [7: near, 9: far])
        let camera = SceneParticleCameraFrame(camera: descriptor.camera,
            viewportSize: CGSize(width: 64, height: 64))
        precondition(camera.defaultsToPerspective && camera.resolvesPerspective(for: near)
            && camera.resolvesPerspective(for: far))
        let center = camera.reverseDepthViewProjection(usesPerspective: true) * worlds[7]! * SIMD4<Float>(0, 0, 0, 1)
        precondition(abs(center.x / center.w) < 0.00001 && abs(center.y / center.w) < 0.00001)
        let ambient = item["ambient"] as! Bool
        let lighting = SceneLightSnapshot(ambient: ambient ? SIMD3(repeating: 1) : .zero,
            skylight: .zero, directional: ambient || reflection ? [] : [.init(directionTowardLight: vector("light"),
                color: SIMD3(repeating: 1), intensity: 2)], point: [], spot: [], overflowCount: 0)
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 64, height: 64, mipmapped: false)
        outputDescriptor.storageMode = .shared; outputDescriptor.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: outputDescriptor)!, cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: output,
            clearColor: MTLClearColorMake(item["additive"] as! Bool ? 64.0 / 255.0 : 0, 0, 0, 0), clearEnabled: true)
        let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: cb)
        var leases: [SceneParticleDepthTargetLease] = []
        let snapshot = SceneDynamicSnapshot.empty(frameIndex: 1, generation: 1)
        if reflection {
            let reflectionDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: 64, height: 64, mipmapped: false)
            reflectionDescriptor.storageMode = .shared; reflectionDescriptor.usage = .shaderRead
            let colorBands = device.makeTexture(descriptor: reflectionDescriptor)!
            let bytes = (0..<64 * 64).flatMap { pixel -> [UInt8] in
                pixel % 64 < 32 ? [255, 0, 0, 255] : [0, 0, 255, 255]
            }
            bytes.withUnsafeBytes { colorBands.replace(region: MTLRegionMake2D(0, 0, 64, 64),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 256) }
            _ = state.sharedDepth(pass: pass, pool: renderer.staticModelDepthTargetPool,
                device: device, commandBuffer: cb, leases: &leases)
            let encoder = state.sceneDepthEncoder(pass: pass, commandBuffer: cb)!
            let draw = renderer.staticModelDraws(layer: near, worldFrames: worlds, snapshot: snapshot)!.first!
            precondition(resources.pipeline!.draw(mesh: draw.mesh, texture: draw.texture,
                colorTextureIsPremultiplied: false, emissiveMask: nil, emissiveMaskTextureFrame: nil,
                emissiveMaskSampling: nil, normalMap: draw.entry.normalMap, modelMatrix: draw.world,
                normalMatrix: draw.normalMatrix, viewProjection: camera.reverseDepthViewProjection(usesPerspective: true),
                cameraPosition: camera.perspectiveEyePosition, textureFrame: draw.textureFrame,
                sampling: draw.sampling, layerAlpha: draw.alpha, material: draw.material,
                additiveRGB: item["additive"] as! Bool,
                lighting: lighting, writesDepth: true, reflectionTexture: colorBands,
                commandBuffer: cb, encoder: encoder))
        } else { for layer in item["far"] as! Bool ? [near, far] : [near] {
            _ = renderer.drawStaticModel(layer: layer, state: state, worldFrames: worlds,
                frameContext: .init(dynamicValues: snapshot), cameraFrame: camera, lighting: lighting,
                pass: pass, commandBuffer: cb, leases: &leases)
        } }
        let depth = state.sharedDepth(pass: pass, pool: renderer.staticModelDepthTargetPool,
            device: device, commandBuffer: cb, leases: &leases).lease!.texture
        precondition(pass.finishEnsuringClear())
        let readback = device.makeBuffer(length: 256, options: .storageModeShared)!
        let blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: depth, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: .init(x: 32, y: 32, z: 0), sourceSize: .init(width: 1, height: 1, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        blit.endEncoding(); leases.forEach { $0.arm(on: cb) }; state.arm(on: cb)
        cb.commit(); cb.waitUntilCompleted()
        precondition(cb.status == .completed && cb.error == nil)
        func rgba(_ x: Int, _ y: Int) -> [Int] {
            var bytes = [UInt8](repeating: 0, count: 4)
            output.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            return [Int(bytes[2]), Int(bytes[1]), Int(bytes[0]), Int(bytes[3])]
        }
        return ["name": name, "rgba": rgba(32, 32), "outside": rgba(0, 0),
            "encoding": resources[7]!.first!.normalMap?.encoding.rawValue ?? 0,
            "depth": readback.contents().bindMemory(to: Float.self, capacity: 1).pointee,
            "requests": loader.requests, "completed": true]
    }
}
