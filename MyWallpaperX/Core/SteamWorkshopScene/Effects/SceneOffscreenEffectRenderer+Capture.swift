import Metal
import simd

extension SceneOffscreenEffectRenderer {
    static func beginEncoder(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture
    ) -> MTLRenderCommandEncoder? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        return commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    static func captureSource(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let encoder = beginEncoder(commandBuffer: commandBuffer, target: target) else {
            return false
        }
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(
            texture: sourceTexture,
            shakeMaskTexture: nil,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            mvp: fullTargetMVP,
            uniforms: sourceUniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        return true
    }

    static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
    static let neutralUniforms = SceneLayerFragmentUniforms.neutral()
}
