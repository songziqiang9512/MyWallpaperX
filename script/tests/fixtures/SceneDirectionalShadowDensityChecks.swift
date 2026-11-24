@main enum SceneDirectionalShadowDensityChecks {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let input = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        var rows: [[String: Any]] = []
        for item in input {
            rows.append(try autoreleasepool { try run(item, device: device, queue: queue) })
        }
        let output = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }

    static func run(_ item: [String: Any], device: MTLDevice,
                    queue: MTLCommandQueue) throws -> [String: Any] {
        let width = item["width"] as! Int, height = item["height"] as! Int
        let lit = item["lit"] as? Bool ?? true
        let layerID = item["layerID"] as? Int ?? 11
        let directionalLimit = item["directionalLimit"] is NSNull ? nil : (item["directionalLimit"] as? Int ?? 4096)
        let pipeline = SceneStaticModelPipeline(device: device, preparesShadows: directionalLimit != nil)!
        let vertices = [SIMD3<Float>(16, 16, 0), SIMD3(48, 16, 0),
                        SIMD3(48, 48, 0), SIMD3(16, 48, 0)].map {
            SceneMdlStaticModel.Vertex(position: $0, normal: SIMD3(0, 0, 1),
                tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(repeating: 0.5))
        }
        let mesh = pipeline.makeMesh(model: SceneStaticModelFixture.model(
            vertices: vertices, indices: [0, 2, 1, 0, 3, 2]))!
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
        let source = device.makeTexture(descriptor: sourceDescriptor)!
        let white: [UInt8] = [255, 255, 255, 255]
        white.withUnsafeBytes {
            source.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        var material = SceneStaticModelMaterial(color: SIMD3(repeating: 1), opacity: 1,
            receivesLighting: lit, textureAlphaIsOpacity: true, textureAlphaIsTintMask: false,
            emissiveColor: .zero, emissiveBrightness: 0, brightness: 1,
            usesHDRBrightness: false, viewTint: nil)
        material.cullMode = .none
        let entry = ScenePreparedStaticModelResources.Entry(
            materialPath: item["materialPath"] as? String ?? "density-surface",
            dynamicMaterialPath: "", mesh: mesh, albedo: PreparedTexture(texture: source),
            material: material)
        let layers = [SceneRenderDescriptor.Layer(id: layerID)]
        let renderer = SceneMetalRenderer(device: device,
            resources: .init(pipeline: pipeline, entries: [layerID: [entry]],
                directionalShadowDimensionLimit: directionalLimit))
        let cameraDescriptor = SceneRenderDescriptor.CameraDescriptor(
            eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
            orthoWidth: 64, orthoHeight: 64, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 1000)
        renderer.renderDescriptor = .init(lighting: nil, layers: layers,
            renderOrderLayerIDs: [layerID], camera: cameraDescriptor)
        let camera = SceneParticleCameraFrame(camera: cameraDescriptor,
            viewportSize: CGSize(width: width, height: height))
        let world = [layerID: SceneMatrix.scale(SIMD3<Float>(1, -1, 1))]
        var directionals: [SceneLightSnapshot.Directional] = []
        var points: [SceneLightSnapshot.Point] = []
        var spots: [SceneLightSnapshot.Spot] = []
        var lights: [SceneLightSnapshot.ShadowLight] = []
        for raw in item["lights"] as! [[String: Any]] {
            let id = raw["id"] as! Int
            switch raw["kind"] as! String {
            case "directional":
                let light = SceneLightSnapshot.Directional(layerID: id, castsShadow: true,
                    directionTowardLight: SIMD3(0, 0, 1), color: SIMD3(repeating: 1), intensity: 0.25)
                directionals.append(light)
                lights.append(.directional(light))
            case "point":
                let light = SceneLightSnapshot.Point(layerID: id, castsShadow: true,
                    position: SIMD3(32, -32, 10), color: SIMD3(repeating: 1),
                    intensity: 0.25, radius: 100)
                points.append(light)
                lights.append(.point(light))
            default:
                let degrees: Float = raw["kind"] as! String == "invalid-spot" ? 100 : 45
                let light = SceneLightSnapshot.Spot(layerID: id, castsShadow: true,
                    position: SIMD3(32, -32, 10), directionFromLight: SIMD3(0, 0, -1),
                    color: SIMD3(repeating: 1), intensity: 0.25, radius: 100,
                    innerConeCosine: cos(.pi / 6), outerConeCosine: cos(degrees * .pi / 180),
                    outerConeDegrees: degrees)
                spots.append(light)
                lights.append(.spot(light))
            }
        }
        let lighting = SceneLightSnapshot(ambient: SIMD3(repeating: 0.5), skylight: .zero,
            directional: directionals, point: points, spot: spots, overflowCount: 0)
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: targetDescriptor)!
        let cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: output,
            clearColor: MTLClearColorMake(0, 0, 0, 1), clearEnabled: true)
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .bgra8Unorm,
            residentByteBudget: item["budgetBytes"] as! Int)
        let state = SceneMetalRenderer.StaticModelFrame(commandBuffer: cb)
        let dynamic = SceneDynamicSnapshot.empty(frameIndex: 1, generation: 1)
        let visible: Set<Int> = [layerID]
        let candidates = renderer.shadowDrawCandidates(orderedLayers: layers, visible: visible,
            worldFrames: world, snapshot: dynamic, groups: nil)!
        var leases: [SceneParticleDepthTargetLease] = []
        renderer.prepareModelShadow(state: state, candidates: candidates, lights: lights,
            orderedLayers: layers, visible: visible, batches: [:], particlePipeline: nil,
            mainPass: pass, groups: nil, pool: pool, commandBuffer: cb, leases: &leases,
            mandatoryCapacity: { true }, recordsEvidence: false, cameraFrame: camera)
        var shadowPipelinesSkipped = false
        if directionalLimit == nil {
            let depth = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: 16, height: 16, mipmapped: false)
            depth.storageMode = .private
            depth.usage = .renderTarget
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = device.makeTexture(descriptor: depth)!
            pass.depthAttachment.loadAction = .clear
            let encoder = cb.makeRenderCommandEncoder(descriptor: pass)!
            let projections: [SceneStaticModelShadowProjection] = [
                .directional(.init(worldToClip: matrix_identity_float4x4, depthBias: 0)),
                .spot(SceneSpotShadowProjection.make(light: spots.last!)!),
                .point(.init(light: points[0]))
            ]
            shadowPipelinesSkipped = projections.allSatisfy { projection in
                !pipeline.drawShadow(mesh: mesh, texture: source, textureFrame: .identity, sampling: .linearClamp,
                    modelMatrix: matrix_identity_float4x4, projection: projection, face: 0,
                    viewport: .init(originX: 0, originY: 0, width: 16, height: 16, znear: 0, zfar: 1),
                    layerAlpha: 1, material: material, encoder: encoder)
            }
            encoder.endEncoding()
        }
        let maps: [[String: Any]] = state.shadows.map { shadow in
            // Observe the existing residency key without reserving another target.
            let slots = pool.allocationCache.locked {
                pool.allocationCache.residents.compactMap { key, entry -> Int? in
                    guard case let .current(.modelShadow(slot, _, _)) = key,
                          case let .composition(texture, _) = entry.allocation,
                          texture === shadow.texture else { return nil }
                    return slot
                }.sorted()
            }
            var row: [String: Any] = ["lightID": shadow.lightLayerID, "slots": slots,
                "width": shadow.texture.width, "height": shadow.texture.height]
            if case let .directional(projection) = shadow.projection {
                row["matrix"] = (0..<4).flatMap { column in
                    [projection.worldToClip[column].x, projection.worldToClip[column].y,
                     projection.worldToClip[column].z, projection.worldToClip[column].w]
                }
            }
            return row
        }
        let colorEncodedLit = renderer.drawStaticModel(layer: layers[0], state: state,
            worldFrames: world, frameContext: .init(dynamicValues: dynamic), cameraFrame: camera,
            lighting: lighting, pass: pass, commandBuffer: cb, leases: &leases)
        let finished = pass.finishEnsuringClear()
        leases.forEach { $0.arm(on: cb) }
        state.arm(on: cb)
        cb.commit()
        cb.waitUntilCompleted()
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes {
            output.getBytes($0.baseAddress!, bytesPerRow: 4,
                from: MTLRegionMake2D(width / 2, height / 2, 1, 1), mipmapLevel: 0)
        }
        return ["name": item["name"]!, "physicalExtent": [output.width, output.height],
            "maps": maps, "colorRGBA": [pixel[2], pixel[1], pixel[0], pixel[3]],
            "colorEncodedLit": colorEncodedLit, "finished": finished,
            "completed": cb.status == .completed && cb.error == nil,
            "shadowResidentBytes": pool.residentByteCost, "shadowPipelinesSkipped": shadowPipelinesSkipped]
    }
}
