import Metal

enum SceneOpacityRenderer {
    static func render(
        alpha: Float,
        mask: MTLTexture?,
        maskUVScale: SIMD2<Float>,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneOpacityPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard pipeline.encode(
            source: inputTexture,
            target: outputTexture,
            alpha: alpha,
            mask: mask,
            maskUVScale: maskUVScale,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return outputTexture
    }
}
