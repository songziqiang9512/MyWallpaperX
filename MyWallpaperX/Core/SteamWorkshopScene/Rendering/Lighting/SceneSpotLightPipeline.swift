import Metal
import simd

final class SceneSpotLightPipeline {
    private struct Uniforms {
        var color: SIMD4<Float>
        var innerRatio: Float
        var density: Float
        var exponent: Float
        var volumetricsExponent: Float
        var intensity: Float
    }

    private let state: MTLRenderPipelineState
    private static let vertices: [SceneQuadVertex] = [
        .init(position: SIMD2(0, -1), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2(1, -1), texcoord: SIMD2(1, 0)),
        .init(position: SIMD2(0, 1), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2(1, 1), texcoord: SIMD2(1, 1)),
    ]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm || pixelFormat == .rgba16Float,
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneSpotLightVert"),
              let fragment = library.makeFunction(name: "sceneSpotLightFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
    }

    func draw(
        plan: SceneSpotLightPlan,
        color: SIMD3<Float>,
        intensity: Float,
        alpha: Float,
        worldFrame: simd_float4x4,
        viewProjection: simd_float4x4,
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        var mvp = viewProjection * worldFrame
            * SceneMatrix.scale(SIMD3(plan.radius, plan.supportHalfWidth, 1))
        guard mvp.columns.0.allFinite,
              mvp.columns.1.allFinite,
              mvp.columns.2.allFinite,
              mvp.columns.3.allFinite else {
            return false
        }
        var vertices = Self.vertices
        var uniforms = Uniforms(
            color: SIMD4(color, alpha),
            innerRatio: plan.innerRatio,
            density: plan.density,
            exponent: plan.exponent,
            volumetricsExponent: plan.volumetricsExponent,
            intensity: intensity
        )
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(
            &vertices,
            length: MemoryLayout<SceneQuadVertex>.stride * vertices.count,
            index: 0
        )
        encoder.setVertexBytes(
            &mvp,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
#if DEBUG
        SceneGPUStageTimestampHook.drew(encoder)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
#endif
        return true
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
