import Metal
import simd

enum SceneOffscreenEffectRenderer {
    static func beginEncoder(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture
    ) -> MTLRenderCommandEncoder? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return nil
        }
        SceneGPUCensus.recordOffscreenRender(.offscreenEffectCapture)
        return encoder
    }

    static func captureSource(
        sourceTexture: MTLTexture,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer,
        sourceLighting: SceneBaseMaterialLitCapturePayload? = nil
    ) -> Bool {
        if sourceTexture === target { return true }
        let sourceLighting = sourceLighting?.resolvingEnvironment(
            for: target, commandBuffer: commandBuffer)
        guard let encoder = beginEncoder(commandBuffer: commandBuffer, target: target) else {
            return false
        }
        if let sourceLighting = sourceLighting?.validated(for: target) {
            sourceLighting.pipeline.bind(encoder: encoder)
            sourceLighting.pipeline.drawLayer(
                texture: sourceTexture,
                normalTexture: sourceLighting.normalTexture,
                materialMapTexture: sourceLighting.materialMapTexture,
                environmentTexture: sourceLighting.environmentTexture,
                mvp: fullTargetMVP,
                uniforms: sourceUniforms,
                litPayload: sourceLighting.lights,
                encoder: encoder
            )
        } else {
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(
                texture: sourceTexture,
                mvp: fullTargetMVP,
                uniforms: sourceUniforms,
                encoder: encoder
            )
        }
        encoder.endEncoding()
        return true
    }

    static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
}
