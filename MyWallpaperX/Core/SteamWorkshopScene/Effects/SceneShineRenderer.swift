import Metal

enum SceneShineRenderer {
    static func renderCaptured(
        plan: SceneShineExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        shinePipeline: SceneShinePipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.shineEffects[plan.effectKey.descriptorID],
              resources.matches(plan),
              let noise = resources.noise,
              let firstHalf = targets.texture(for: plan.firstHalfTarget),
              let secondHalf = targets.texture(for: plan.secondHalfTarget),
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: sourcePipeline,
                  commandBuffer: commandBuffer
              ),
              shinePipeline.encodeDownsample(
                  source: targets.inputTexture,
                  mask: plan.maskTexturePath == nil ? nil : resources.mask,
                  maskUVScale: resources.maskUVScale,
                  noise: noise,
                  target: firstHalf,
                  plan: plan,
                  time: time,
                  commandBuffer: commandBuffer
              ),
              shinePipeline.encodeCast(
                  source: firstHalf,
                  target: secondHalf,
                  plan: plan,
                  time: time,
                  commandBuffer: commandBuffer
              ),
              shinePipeline.encodeGaussian(
                  source: secondHalf,
                  target: firstHalf,
                  plan: plan,
                  vertical: false,
                  commandBuffer: commandBuffer
              ),
              shinePipeline.encodeGaussian(
                  source: firstHalf,
                  target: secondHalf,
                  plan: plan,
                  vertical: true,
                  commandBuffer: commandBuffer
              ),
              shinePipeline.encodeCombine(
                  rays: secondHalf,
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  plan: plan,
                  commandBuffer: commandBuffer
              )
        else {
            return nil
        }
        return targets.outputTexture
    }
}
