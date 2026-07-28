import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderWorkshopSimpleAudioBars(
        _ audioBars: SceneWorkshopAudioBarsExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        audioBarsPipeline: SceneWorkshopSimpleAudioBarsPipeline,
        spectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resolved = audioBars.resolvedSimpleParameters(in: dynamicValues),
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: masks.water,
                  foliageMaskTexture: masks.foliage,
                  auxMaskTexture: auxMask,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              audioBarsPipeline.encode(
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  parameters: resolved.parameters,
                  color: resolved.color,
                  spectrum: spectrum,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
