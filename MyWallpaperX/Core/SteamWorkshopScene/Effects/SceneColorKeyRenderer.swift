import Metal

enum SceneColorKeyRenderer {
    static func render(
        plan: SceneColorKeyExecutionPlan,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneColorKeyPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard pipeline.encode(
            source: inputTexture,
            target: outputTexture,
            plan: plan,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return outputTexture
    }
}
