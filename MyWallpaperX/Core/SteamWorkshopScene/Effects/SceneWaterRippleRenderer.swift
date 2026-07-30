import Metal

enum SceneWaterRippleRenderer {
    static func render(
        plan: SceneWaterRippleExecutionPlan,
        sourceTexture: MTLTexture,
        resources: SceneWaterRippleEffectTextures,
        target: MTLTexture,
        time: Float,
        pipeline: SceneWaterRipplePipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let arguments = resources.resolvedArguments(for: plan),
              pipeline.encode(
                  source: sourceTexture,
                  normalMap: arguments.normal.texture,
                  target: target,
                  plan: plan.runtimePlan,
                  time: time,
                  maskTexture: arguments.mask.texture,
                  maskUVScale: arguments.maskUVScale,
                  normalSampling: arguments.normal.sampling,
                  maskSampling: arguments.mask.sampling,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return target
    }
}
