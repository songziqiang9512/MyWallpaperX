import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderColorKey(
        _ colorKey: SceneColorKeyExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        colorKeyPipeline: SceneColorKeyPipeline,
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
        return SceneColorKeyRenderer.render(
            plan: colorKey,
            inputTexture: targets.inputTexture,
            outputTexture: targets.outputTexture,
            pipeline: colorKeyPipeline,
            commandBuffer: commandBuffer
        )
    }
}
