import Metal

enum SceneWaterWavesRenderer {
    static func render(
        plan: SceneWaterWavesExecutionPlan,
        resources: SceneWaterWavesEffectTextures,
        time: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneWaterWavesPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard resources.matches(plan),
              let mask = resources.mask,
              pipeline.encode(
                  source: inputTexture,
                  mask: mask,
                  target: outputTexture,
                  plan: plan,
                  time: time,
                  maskUVScale: resources.maskUVScale,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return outputTexture
    }
}
