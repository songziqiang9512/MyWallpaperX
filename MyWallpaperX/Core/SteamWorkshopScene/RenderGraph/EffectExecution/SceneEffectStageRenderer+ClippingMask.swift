import Metal

extension SceneEffectStageRenderer {
    static func renderClippingMask(
        _ plan: SceneClippingMaskExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        dependencyEffect: SceneDependencyEffectInput?,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              let dependencyEffect,
              clippingDependencyMatches(dependencyEffect, plan: plan),
              let encoder = SceneOffscreenEffectRenderer.beginEncoder(
                  commandBuffer: commandBuffer,
                  target: targets.outputTexture
              ) else {
            return nil
        }
        var uniforms = sourceUniforms
        uniforms.usesDependencyBlend = 1
        uniforms.dependencyBlendMode = UInt32(dependencyEffect.blendMode)
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(
            texture: sourceTexture,
            dependencyTexture: dependencyEffect.texture,
            mvp: SceneOffscreenEffectRenderer.fullTargetMVP,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        return targets.outputTexture
    }

    static func clippingDependencyMatches(
        _ input: SceneDependencyEffectInput?,
        plan: SceneClippingMaskExecutionPlan
    ) -> Bool {
        guard let input,
              input.consumerLayerID == plan.layerID,
              input.providerLayerID == plan.providerLayerID,
              input.variant == .primary,
              input.slot.effectID == plan.effectKey.descriptorID,
              input.slot.slotIndex == 1,
              input.blendMode == plan.blendMode,
              input.blendMode == 0 || input.blendMode == 5,
              input.frameEpoch > 0,
              plan.renderGraph.layerID == plan.layerID,
              plan.renderGraph.effects.count == 1,
              plan.renderGraph.effects.first?.key == plan.effectKey,
              plan.renderGraph.nodes.count == 1,
              plan.renderGraph.nodes.first?.effect == plan.effectKey,
              plan.renderGraph.nodes.first?.instancePassIndex
                == input.slot.passIndex else { return false }
        return true
    }
}
