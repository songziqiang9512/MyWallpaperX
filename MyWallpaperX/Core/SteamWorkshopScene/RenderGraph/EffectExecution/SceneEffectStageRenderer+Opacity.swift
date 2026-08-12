import Metal

extension SceneEffectStageRenderer {
    static func renderOpacity(
        _ opacity: SceneOpacityExecutionPlan,
        stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        opacityPipeline: SceneOpacityPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        var opacityMask: MTLTexture?
        var opacityMaskUVScale = SIMD2<Float>(repeating: 1)
        if opacity.maskTexturePath != nil {
            guard let resources = masks.opacityEffects[opacity.effectKey.descriptorID],
                  resources.matches(opacity),
                  let texture = resources.mask else {
                return nil
            }
            opacityMask = texture
            opacityMaskUVScale = resources.maskUVScale
        }
        guard let alpha = stage.opacityAlpha(in: dynamicValues),
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return SceneOpacityRenderer.render(
            alpha: alpha,
            mask: opacityMask,
            maskUVScale: opacityMaskUVScale,
            inputTexture: targets.inputTexture,
            outputTexture: targets.outputTexture,
            pipeline: opacityPipeline,
            commandBuffer: commandBuffer
        )
    }
}
