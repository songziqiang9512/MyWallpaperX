import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderBlend(
        _ blend: SceneBlendExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        blendPipeline: SceneBlendPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.blendEffects[blend.effectKey.descriptorID],
              resources.matches(blend),
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: masks.water,
                  foliageMaskTexture: masks.foliage,
                  auxMaskTexture: auxMask,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: sourcePipeline,
                  commandBuffer: commandBuffer
              ),
              blendPipeline.encode(
                  source: targets.inputTexture,
                  blend: resources.texture,
                  target: targets.outputTexture,
                  multiply: blend.multiply,
                  blendUVScale: resources.uvScale,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
