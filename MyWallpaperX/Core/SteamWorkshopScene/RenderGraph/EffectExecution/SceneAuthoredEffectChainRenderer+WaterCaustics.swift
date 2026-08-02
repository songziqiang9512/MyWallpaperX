import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderWaterCaustics(
        _ plan: SceneWaterCausticsExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let causticsPipeline = pipelines.waterCaustics,
              let resources = masks.waterCausticsEffects[plan.effectKey.descriptorID],
              resources.matches(plan),
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
              causticsPipeline.encode(
                  source: targets.inputTexture,
                  resources: resources,
                  target: targets.outputTexture,
                  plan: plan,
                  time: time,
                  commandBuffer: commandBuffer
              )
        else { return nil }
        return targets.outputTexture
    }
}
