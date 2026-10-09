@main enum ShadowTelemetryProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let pipeline = SceneStaticModelPipeline(device: device, colorPixelFormat: .rgba16Float)!
        let light = SceneLightSnapshot.Spot(layerID: 1, castsShadow: true, position: .zero,
            directionFromLight: SIMD3(0, 0, 1), color: SIMD3(repeating: 1), intensity: 1,
            radius: 10, innerConeCosine: 0.9, outerConeCosine: 0.7, outerConeDegrees: 45)
        let projection = SceneSpotShadowProjection.make(light: light)!
        let vertices = [SIMD3<Float>(-0.5, -0.5, 1), SIMD3(0.5, -0.5, 1), SIMD3(0, 0.5, 1)].map {
            SceneMdlStaticModel.Vertex(position: $0, normal: SIMD3(0, 0, -1), tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(0.5, 0.5))
        }
        let mesh = pipeline.makeMesh(vertices: vertices, indices: [0, 1, 2])!
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
        textureDescriptor.storageMode = .shared; textureDescriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: textureDescriptor)!
        var white: [Float] = [1, 1, 1, 1]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 16)
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 16, height: 16, mipmapped: false)
        depthDescriptor.storageMode = .private; depthDescriptor.usage = .renderTarget
        let target = device.makeTexture(descriptor: depthDescriptor)!
        let descriptor = MTLRenderPassDescriptor()
        descriptor.depthAttachment.texture = target
        descriptor.depthAttachment.loadAction = .clear; descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 1
        let material = SceneStaticModelMaterial(color: SIMD3(repeating: 1), opacity: 1, receivesLighting: true,
            textureAlphaIsOpacity: true, textureAlphaIsTintMask: false, emissiveColor: .zero,
            emissiveBrightness: 1, brightness: 1, usesHDRBrightness: false, viewTint: nil)
        let hub = ScenePerformanceCounterHub.shared
        let metrics: [ScenePerformanceMetric] = [.pipelineStateBinds, .drawCalls, .geometryDrawCalls]
        var results: [[String: Any]] = []
        for alpha: Float in [.nan, 1, 0.5] {
            for metric in metrics { hub.set(metric, 0) }
            let commandBuffer = queue.makeCommandBuffer()!
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
            let accepted = pipeline.drawShadow(mesh: mesh, texture: texture, textureFrame: .identity,
                sampling: .linearClamp, modelMatrix: matrix_identity_float4x4, projection: .spot(projection), face: 0,
                viewport: MTLViewport(originX: 0, originY: 0, width: 16, height: 16, znear: 0, zfar: 1),
                layerAlpha: alpha, material: material, encoder: encoder)
            encoder.endEncoding(); commandBuffer.commit(); commandBuffer.waitUntilCompleted()
            let snapshot = hub.snapshot()
            results.append(["accepted": accepted, "completed": commandBuffer.status == .completed && commandBuffer.error == nil,
                            "binds": snapshot[.pipelineStateBinds] ?? 0,
                            "draws": snapshot[.drawCalls] ?? 0,
                            "geometry": snapshot[.geometryDrawCalls] ?? 0])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": results]), as: UTF8.self))
    }
}
