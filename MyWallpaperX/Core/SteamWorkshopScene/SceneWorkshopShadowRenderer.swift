import Metal

enum SceneWorkshopShadowRenderer {
    static func render(
        plan: SceneWorkshopShadowExecutionPlan,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneWorkshopShadowPipeline,
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
