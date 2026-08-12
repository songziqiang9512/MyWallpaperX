import Metal

extension SceneEffectStageRenderer {
    static func renderWorkshopAudioBars(
        _ audioBars: SceneWorkshopAudioBarsExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        audioBarsPipeline: SceneWorkshopAudioBarsPipeline,
        spectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              audioBarsPipeline.encode(
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  shape: audioBars.shape,
                  spectrum: spectrum,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
