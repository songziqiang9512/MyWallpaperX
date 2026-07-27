import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderSpin(
        _ spin: SceneSpinExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        spinPipeline: SceneSpinPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard spin.layerID == spin.renderGraph.layerID,
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
              spinPipeline.encode(
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  uniforms: .init(
                      center: spin.center,
                      size: spin.size,
                      feather: spin.feather,
                      speed: spin.speed,
                      ratio: spin.ratio,
                      angle: spin.angle,
                      phase: spin.phase,
                      time: time
                  ),
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
