import Metal

extension SceneEffectStageRenderer {
    /// Tint stage：遮罩挂在 effect 实例上（同一层可有多个 tint 各绑一张），按
    /// descriptorID 取；声明了遮罩却取不到贴图时整段拒绝，不静默降级成无遮罩。
    static func renderTint(
        _ tint: SceneTintExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        tintPipeline: SceneTintPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.tintEffects[tint.effectKey.descriptorID],
              resources.matches(tint),
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              tintPipeline.encode(
                  source: targets.inputTexture,
                  mask: tint.maskTexturePath != nil ? resources.mask : nil,
                  maskUVScale: resources.maskUVScale,
                  maskMultipliesBlendAlpha: tint.shaderProfile.maskMultipliesBlendAlpha,
                  target: targets.outputTexture,
                  color: tint.resolvedColor(in: dynamicValues),
                  alpha: tint.resolvedAlpha(in: dynamicValues),
                  blendMode: tint.blendMode,
                  commandBuffer: commandBuffer
              )
        else {
            return nil
        }
        return targets.outputTexture
    }
}
