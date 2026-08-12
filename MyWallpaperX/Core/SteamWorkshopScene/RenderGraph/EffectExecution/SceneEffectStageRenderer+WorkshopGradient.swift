import Metal

extension SceneEffectStageRenderer {
    static func renderWorkshopGradient(
        _ gradient: SceneWorkshopGradientExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        gradientPipeline: SceneWorkshopGradientPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard gradient.layerID == gradient.renderGraph.layerID,
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              gradientPipeline.encode(
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
