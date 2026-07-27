import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderWorkshopShiftHue(
        _ shiftHue: SceneWorkshopShiftHueExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        shiftHuePipeline: SceneWorkshopShiftHuePipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
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
              ) else {
            return nil
        }
        return SceneWorkshopShiftHueRenderer.render(
            plan: shiftHue,
            time: time,
            inputTexture: targets.inputTexture,
            outputTexture: targets.outputTexture,
            pipeline: shiftHuePipeline,
            commandBuffer: commandBuffer
        )
    }
}
