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
        var combos = ["LIGHTING": item["lighting"] as? Int ?? 1]
        combos.merge(item["mapCombos"] as? [String: Int] ?? [:], uniquingKeysWith: { _, value in value })
        if let gradientCombo = item["gradientCombo"] as? Int { combos["SHADINGGRADIENT"] = gradientCombo }
        if combo >= 0 { combos["NORMALMAP"] = combo }
        let reflection = item["reflection"] as! Bool
        if reflection && combos["REFLECTION"] == nil { combos["REFLECTION"] = 1 }
        var values: [String: SceneDocument.ShaderValue] = [
            "alpha": .init(components: [Double(number("alpha"))]), "roughness": .init(components: [1])]
        for (key, value) in item["constants"] as? [String: Any] ?? [:] {
            let components = (value as? [NSNumber])?.map(\.doubleValue) ?? [(value as! NSNumber).doubleValue]
            values[key] = .init(components: components)
        }
        let componentRelative = renamed ? "materials/alternate-components.png" : "materials/components.png"
        var textureSlots: [String?] = [renamed ? "materials/alternate-color.png" : "materials/white.png", normalRelative]
        if item["materialPixels"] != nil { textureSlots.append(componentRelative) }
        let gradientRelative = renamed ? "materials/alternate-ramp.png" : "materials/ramp.png"
        if item["gradientPixels"] != nil,
           !(item["gradientDefault"] as? Bool ?? false) || (item["gradientExplicit"] as? Bool ?? false) {
            textureSlots += Array(repeating: nil, count: 5 - textureSlots.count)
            textureSlots[4] = gradientRelative
        }
        var primary = SceneRenderDescriptor.MaterialPassDescriptor(materialPath: materialPath,
            textureSlots: textureSlots, combos: combos, constantShaderValues: values)
        if item["gradientUser"] as? Bool == true {
            primary.userTextureInputs = [nil, nil, nil, nil, .init(kind: .property, value: "fixture-ramp")]
        }
        primary.shaderPath = item["shader"] as? String
        primary.userShaderValues = item["userShaderValues"] as? [String: String] ?? [:]
        primary.cullMode = "nocull"; primary.blending = item["additive"] as! Bool ? "additive" : "translucent"
        var farPass = SceneRenderDescriptor.MaterialPassDescriptor(materialPath: "materials/far.json",
            textureSlots: ["materials/blue.png"], combos: ["LIGHTING": 0], constantShaderValues: [:])
        farPass.shaderPath = "generic4"; farPass.cullMode = "nocull"; farPass.blending = "normal"
        var near = SceneRenderDescriptor.Layer(id: 7, staticModelPath: modelPath)
        near.utilityLayer = nil; near.usesPerspective = true; near.originXYZ = [0, 0, 0]
        near.scaleXYZ = [vector("scale").x, vector("scale").y, vector("scale").z]
        near.anglesXYZ = [0, 0, number("rotation")]
        var far = SceneRenderDescriptor.Layer(id: 9, staticModelPath: "models/far.mdl")
        let gradientShadow = item["gradientShadow"] as? Bool ?? false
        far.utilityLayer = nil; far.usesPerspective = true; far.originXYZ = [0, 0, gradientShadow ? 20 : 0]
        var descriptor = SceneRenderDescriptor(lighting: nil, layers: [near, far],
            renderOrderLayerIDs: [7, 9], materialPasses: [primary, farPass])
        descriptor.hdrEnabled = item["hdr"] as? Bool ?? false
        descriptor.camera = .init(eye: [0, 0, 160], center: [0, 0, 0], up: [0, 1, 0],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: 60,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 1000)
        let loader = try SceneTextureLoader(root: folder, device: device)
        let resourceView = SceneResourceView(projectRootURL: folder, packageRootURL: nil,
            stockAssetsRootURL: item["gradientDefault"] as? Bool == true ? folder.appendingPathComponent("stock") : nil)
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
        if let componentPixels = item["materialPixels"] as? [NSNumber] {
            let componentWidth = item["materialWidth"] as? Int ?? 1
            let componentDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: componentWidth, height: 1, mipmapped: false)
            componentDescriptor.storageMode = .shared; componentDescriptor.usage = .shaderRead
            let componentTexture = device.makeTexture(descriptor: componentDescriptor)!
            let bytes = componentPixels.map(\.uint8Value)
            precondition(bytes.count == componentWidth * 4)
            bytes.withUnsafeBytes { componentTexture.replace(region: MTLRegionMake2D(0, 0, componentWidth, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: componentWidth * 4) }
            let componentPath = folder.appendingPathComponent(componentRelative).resolvingSymlinksInPath().path
            let header = item["mapHeader"] as? Int ?? 0
            loader.candidates[componentPath] = .init(texture: componentTexture,
                identity: .file(path: componentPath), generation: .immutable(revision: 1), purpose: .mask,
                content: .data, physicalSize: CGSize(width: componentWidth, height: 1),
                mappedSize: CGSize(width: componentWidth, height: 1),
                uvTransform: .init(origin: SIMD2((item["mapOffset"] as? NSNumber)?.floatValue ?? 0, 0),
                    xAxis: SIMD2((item["mapScale"] as? NSNumber)?.floatValue ?? 1, 0), yAxis: SIMD2(0, 1)),
                sampling: header < 0 ? .directImageFallback : .init(texFlags: UInt32(header) << 20
                    | (item["mapNearest"] as? Bool ?? true ? 1 : 0)
                    | (item["mapRepeat"] as? Bool ?? false ? 0 : 2)))
        }
        if let gradientPixels = item["gradientPixels"] as? [NSNumber] {
            let gradientWidth = item["gradientWidth"] as? Int ?? 1
            let gradientHeight = item["gradientHeight"] as? Int ?? 1
            let storage = item["gradientStorage"] as? String ?? "rgba"
            let channels = storage == "r" ? 1 : storage == "rg" ? 2 : 4
            let gradientDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: storage == "r" ? .r8Unorm : storage == "rg" ? .rg8Unorm : .rgba8Unorm,
                width: gradientWidth, height: gradientHeight, mipmapped: false)
            gradientDescriptor.storageMode = .shared; gradientDescriptor.usage = .shaderRead
            let gradientTexture = device.makeTexture(descriptor: gradientDescriptor)!
            let bytes = gradientPixels.map(\.uint8Value)
            precondition(bytes.count == gradientWidth * gradientHeight * channels)
            bytes.withUnsafeBytes { gradientTexture.replace(region: MTLRegionMake2D(0, 0, gradientWidth, gradientHeight),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: gradientWidth * channels) }
            func pair(_ key: String, _ fallback: SIMD2<Float>) -> SIMD2<Float> {
                guard let values = item[key] as? [NSNumber] else { return fallback }
                return SIMD2(values[0].floatValue, values[1].floatValue)
            }
            for url in [folder.appendingPathComponent(gradientRelative),
                        folder.appendingPathComponent("stock/materials/gradient/gradient_toon_smooth.tex")] {
                let path = url.resolvingSymlinksInPath().path
                let format = item["gradientFormat"] as? Int ?? (storage == "r" ? 9 : storage == "rg" ? 8 : 0)
                loader.candidates[path] = .init(texture: gradientTexture, identity: .file(path: path),
                    generation: .immutable(revision: 1), purpose: .mask, content: .data,
                    physicalSize: CGSize(width: gradientWidth, height: gradientHeight),
                    mappedSize: CGSize(width: gradientWidth, height: gradientHeight),
                    uvTransform: .init(origin: pair("gradientOrigin", .zero),
                        xAxis: pair("gradientXAxis", SIMD2(1, 0)), yAxis: pair("gradientYAxis", SIMD2(0, 1))),
                    sampling: .init(texFlags: item["gradientNearest"] as? Bool ?? true ? 3 : 2),
                    authoredFormat: format < 0 ? nil : SceneShaderTextureFormat(rawValue: UInt32(format)))
            }
        }
        var sources = try prepareModelSources(descriptor, view: resourceView)
        let resources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor,
            resourceView: resourceView, device: device, textureLoader: loader,
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
        let kind = item["lightKind"] as? String ?? "directional"
        let color = item["lightColor"] == nil ? SIMD3<Float>(repeating: 1) : vector("lightColor")
        let intensity = (item["lightIntensity"] as? NSNumber)?.floatValue ?? 2
        let radius = (item["lightRadius"] as? NSNumber)?.floatValue ?? 160
        let direct = !ambient && !reflection
        let lighting = SceneLightSnapshot(ambient: ambient ? SIMD3(repeating: 1) : .zero,
            skylight: .zero, directional: direct && kind == "directional" ? [.init(layerID: 11,
                castsShadow: gradientShadow, directionTowardLight: vector("light"), color: color, intensity: intensity)] : [],
            point: direct && kind == "point" ? [.init(layerID: 11, position: SIMD3(0, 0, 80),
                color: color, intensity: intensity, radius: radius)] : [],
            spot: direct && kind == "spot" ? [.init(layerID: 11, position: SIMD3(0, 0, 80),
                directionFromLight: item["spotAway"] as? Bool == true ? SIMD3(0, 0, 1) : SIMD3(0, 0, -1),
                color: color, intensity: intensity, radius: radius, innerConeCosine: cos(.pi/6),
                outerConeCosine: cos(.pi/4), outerConeDegrees: 45)] : [], overflowCount: 0)
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 64, height: 64, mipmapped: false)
        outputDescriptor.storageMode = .shared; outputDescriptor.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: outputDescriptor)!, cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: output,
            clearColor: MTLClearColorMake(item["additive"] as! Bool ? 64.0 / 255.0 : 0, 0, 0, 0), clearEnabled: true)
        let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: cb)
        var leases: [SceneParticleDepthTargetLease] = []
        let snapshot = SceneDynamicSnapshot.empty(frameIndex: 1, generation: 1)
        let shadowPool = gradientShadow ? SceneOffscreenTexturePool(device: device,
            pixelFormat: .bgra8Unorm, residentByteBudget: 64 * 1024 * 1024) : nil
        if let pool = shadowPool {
            let visible: Set<Int> = [7, 9]
            let candidates = renderer.shadowDrawCandidates(orderedLayers: [near, far], visible: visible,
                worldFrames: worlds, snapshot: snapshot, groups: nil)!
            renderer.prepareModelShadow(state: state, candidates: candidates,
                lights: [.directional(lighting.directional[0])], orderedLayers: [near, far], visible: visible,
                batches: [:], particlePipeline: nil, mainPass: pass, groups: nil, pool: pool,
                commandBuffer: cb, leases: &leases, mandatoryCapacity: { true }, recordsEvidence: false, cameraFrame: camera)
            precondition(state.shadows.count == 1)
        }
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
                colorTextureIsPremultiplied: false, materialMap: draw.entry.materialMap, normalMap: draw.entry.normalMap,
                gradient: draw.entry.gradient, modelMatrix: draw.world,
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
        withExtendedLifetime(shadowPool) {}
        precondition(cb.status == .completed && cb.error == nil)
        func rgba(_ x: Int, _ y: Int) -> [Int] {
            var bytes = [UInt8](repeating: 0, count: 4)
            output.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            return [Int(bytes[2]), Int(bytes[1]), Int(bytes[0]), Int(bytes[3])]
        }
        var result: [String: Any] = ["name": name, "rgba": rgba(32, 32), "outside": rgba(0, 0),
            "encoding": resources[7]!.first!.normalMap?.encoding.rawValue ?? 0,
            "components": resources[7]!.first!.materialMap?.components ?? 0,
            "emissionSeed": resources[7]!.first!.material.emissiveBrightness,
            "surfaceProfile": resources[7]!.first!.material.surfaceProfile != nil,
            "gradient": resources[7]!.first!.gradient != nil,
            "replicatesRed": resources[7]!.first!.gradient?.replicatesRed ?? false,
            "depth": readback.contents().bindMemory(to: Float.self, capacity: 1).pointee,
            "requests": loader.requests, "completed": true]
        if item["geometryFacts"] as? Bool == true {
            func xyz(_ value: SIMD4<Float>) -> SIMD3<Float> { SIMD3(value.x, value.y, value.z) }
            let world = renderer.staticModelWorld(for: near.id, worldFrames: worlds)
            let eye = camera.perspectiveEyePosition
            let unprojected = simd_inverse(camera.reverseDepthViewProjection(usesPerspective: true))
                * SIMD4<Float>(2 * 32.5 / 64 - 1, 1 - 2 * 32.5 / 64, 0.01, 1)
            let ray = xyz(unprojected) / unprojected.w - eye
            let planeNormal = simd_cross(xyz(world.columns.0), xyz(world.columns.1))
            let position = eye + ray * (simd_dot(planeNormal, xyz(world.columns.3) - eye) / simd_dot(planeNormal, ray))
            let normal = simd_normalize(SceneStaticModelPipeline.normalMatrix(for: world)! * vector("geometryNormal"))
            result["geometry"] = ["position": [position.x, position.y, position.z],
                "eye": [eye.x, eye.y, eye.z], "normal": [normal.x, normal.y, normal.z]]
        }
        return result
    }
}
