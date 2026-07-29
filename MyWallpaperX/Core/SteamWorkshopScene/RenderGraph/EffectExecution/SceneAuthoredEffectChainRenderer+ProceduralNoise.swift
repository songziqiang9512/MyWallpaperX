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
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard noise.layerID == noise.renderGraph.layerID,
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
                      variant: UInt32(noise.variant.rawValue),
                      fractals: UInt32(noise.fractals)
                  ),
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
