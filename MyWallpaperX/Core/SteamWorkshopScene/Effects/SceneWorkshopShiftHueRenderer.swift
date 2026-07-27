import Metal

enum SceneWorkshopShiftHueRenderer {
    static func render(
        plan: SceneWorkshopShiftHueExecutionPlan,
        time: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneWorkshopShiftHuePipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard pipeline.encode(
            source: inputTexture,
            target: outputTexture,
            speed: plan.speed,
            time: time,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return outputTexture
    }
}
