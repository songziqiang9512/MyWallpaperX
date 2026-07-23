import Metal

enum SceneOpacityRenderer {
    static func render(
        alpha: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneOpacityPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard pipeline.encode(
            source: inputTexture,
            target: outputTexture,
            alpha: alpha,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return outputTexture
    }
}
