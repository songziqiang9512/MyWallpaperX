import Metal

extension SceneAuthoredEffectChainRenderer {
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
              dependencyEffect.blendMode == plan.blendMode,
              dependencyEffect.blendMode == 0 || dependencyEffect.blendMode == 5,
              let encoder = SceneOffscreenEffectRenderer.beginEncoder(
                  commandBuffer: commandBuffer,
                  target: targets.outputTexture
              ) else {
            return nil
        }
        var uniforms = sourceUniforms
        var flags = SceneEffectFlags(rawValue: uniforms.effectFlags)
        flags.insert(.dependencyBlend)
        uniforms.effectFlags = flags.rawValue
        uniforms.dependencyBlendMode = UInt32(dependencyEffect.blendMode)
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(
            texture: sourceTexture,
            shakeMaskTexture: nil,
            waterMaskTexture: masks.water,
            foliageMaskTexture: masks.foliage,
            auxMaskTexture: masks.iris ?? masks.opacity,
            dependencyTexture: dependencyEffect.texture,
            mvp: SceneOffscreenEffectRenderer.fullTargetMVP,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        return targets.outputTexture
    }
}
