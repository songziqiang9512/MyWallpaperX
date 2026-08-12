import Metal

extension SceneEffectStageRenderer {
    static func renderBlend(
        _ blend: SceneBlendExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        blendPipeline: SceneBlendPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.blendEffects[blend.effectKey.descriptorID],
              let arguments = resources.resolvedArguments(for: blend),
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: sourcePipeline,
                  commandBuffer: commandBuffer
              ),
              blendPipeline.encode(
                  source: targets.inputTexture,
                  blend: arguments.blend.texture,
                  target: targets.outputTexture,
                  multiply: blend.resolvedMultiply(in: dynamicValues),
                  alphaMultiply: blend.alphaMultiply,
                  writesAlpha: blend.writesAlpha,
                  blendUVScale: arguments.uvScale,
                  blendSampling: arguments.blend.sampling,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
