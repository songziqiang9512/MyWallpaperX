import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderProceduralNoise(
        _ noise: SceneProceduralNoiseExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        noisePipeline: SceneProceduralNoisePipeline,
        dependencyEffect: SceneDependencyEffectInput?,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard proceduralNoiseDependencyMatches(dependencyEffect, plan: noise),
              noise.layerID == noise.renderGraph.layerID,
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
              noisePipeline.encode(
                  source: targets.inputTexture,
                  layerTexture: dependencyEffect?.texture,
                  target: targets.outputTexture,
                  uniforms: .init(
                      scale: noise.scale,
                      offset: noise.offset,
                      magnitude: noise.magnitude,
                      thresholds: noise.thresholds,
                      colorsMin: SIMD4(noise.colorsMin, 0),
                      colorsMax: SIMD4(noise.colorsMax, 0),
                      params0: SIMD4(
                          noise.opacity, noise.exponent,
                          noise.fractalScale, noise.fractalInfluence
                      ),
                      params1: SIMD4(
                          noise.gradient, noise.seed,
                          noise.animationSpeed, noise.scrollDirection
                      ),
                      params2: SIMD4(
                          noise.scrollSpeed, noise.thresholdOffset,
                          noise.shiftAmount, time
                      ),
                      perspective01: noise.perspective01,
                      perspective23: noise.perspective23,
                      params3: SIMD4(noise.depthFade, 0, 0, 0),
                      variant: UInt32(noise.variant.rawValue),
                      fractals: UInt32(noise.fractals)
                  ),
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }

    static func proceduralNoiseDependencyMatches(
        _ input: SceneDependencyEffectInput?,
        plan: SceneProceduralNoiseExecutionPlan
    ) -> Bool {
        guard plan.effectKey.layerID == plan.layerID,
              plan.renderGraph.layerID == plan.layerID,
              plan.renderGraph.effects.count == 1,
              plan.renderGraph.effects.first?.key == plan.effectKey,
              plan.renderGraph.nodes.count == 1,
              plan.renderGraph.nodes.first?.effect == plan.effectKey,
              plan.renderGraph.nodes.first?.instancePassIndex == 0 else {
            return false
        }
        switch (plan.dependencyProviderLayerID, plan.dependencySlotIndex) {
        case (nil, nil):
            return input == nil
        case (let providerLayerID?, 3):
            guard plan.variant == .legacyWorleyColor,
                  let input,
                  input.consumerLayerID == plan.layerID,
                  input.providerLayerID == providerLayerID,
                  input.variant == .primary,
                  input.slot.effectID == plan.effectKey.descriptorID,
                  input.slot.passIndex == 0,
                  input.slot.slotIndex == 3,
                  input.blendMode == 0,
                  input.frameEpoch > 0 else { return false }
            return true
        default:
            return false
        }
    }
}
