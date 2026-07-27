import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderWorkshopAudioHueShift(
        _ hueShift: SceneWorkshopAudioHueShiftExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        hueShiftPipeline: SceneWorkshopShiftHuePipeline,
        spectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let offset = SceneAudioResponse.evaluate(
            spectrum: spectrum,
            parameters: hueShift.audio
        )
        guard targets.plan.logicalTargets.isEmpty,
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
              hueShiftPipeline.encodeHueOffset(
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  offset: offset,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
