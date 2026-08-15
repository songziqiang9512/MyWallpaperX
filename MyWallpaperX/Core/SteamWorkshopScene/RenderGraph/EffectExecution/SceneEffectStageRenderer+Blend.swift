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
        dependencyEffect: SceneDependencyEffectInput?,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let blendTexture: MTLTexture
        let blendUVScale: SIMD2<Float>
        let blendSampling: SceneTextureSampling
        if let providerLayerID = blend.dependencyProviderLayerID {
            guard let dependencyEffect,
                  dependencyEffect.consumerLayerID == blend.layerID,
                  dependencyEffect.providerLayerID == providerLayerID,
                  dependencyEffect.variant == .primary,
                  dependencyEffect.slot.effectID == blend.effectKey.descriptorID,
                  dependencyEffect.slot.passIndex == 0,
                  dependencyEffect.slot.slotIndex == 1,
                  dependencyEffect.blendMode == blend.blendMode else {
                return nil
            }
            blendTexture = dependencyEffect.texture
            blendUVScale = SIMD2(repeating: 1)
            blendSampling = .linearClamp
        } else {
            guard dependencyEffect == nil,
                  let resources = masks.blendEffects[blend.effectKey.descriptorID],
                  let arguments = resources.resolvedArguments(for: blend) else {
                return nil
            }
            blendTexture = arguments.blend.texture
            blendUVScale = arguments.uvScale
            blendSampling = arguments.blend.sampling
        }
        guard targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: sourcePipeline,
                  commandBuffer: commandBuffer
              ),
              blendPipeline.encode(
                  source: targets.inputTexture,
                  blend: blendTexture,
                  target: targets.outputTexture,
                  multiply: blend.resolvedMultiply(in: dynamicValues),
                  alphaMultiply: blend.alphaMultiply,
                  writesAlpha: blend.writesAlpha,
                  blendUVScale: blendUVScale,
                  blendSampling: blendSampling,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
