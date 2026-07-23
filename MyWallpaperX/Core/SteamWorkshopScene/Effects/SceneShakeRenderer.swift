import Metal

enum SceneShakeRenderer {
    static func render(
        plan: SceneShakeExecutionPlan,
        resources: SceneShakeEffectTextures,
        time: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneShakePipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard resources.matches(plan),
              let flowTexture = resources.flow,
              pipeline.encode(
                  source: inputTexture,
                  flowMap: flowTexture,
                  phaseMap: resources.phase,
                  flowUVScale: resources.flowUVScale,
                  target: outputTexture,
                  plan: plan,
                  time: time,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return outputTexture
    }
}
