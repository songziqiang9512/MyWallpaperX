import Metal

extension SceneEffectStageRenderer {
    static func renderTransform(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        switch stage.backend {
        case .transform(let transform):
            guard transform.renderGraph.renderTargets.isEmpty,
                  targets.plan.logicalTargets.isEmpty,
                  capture(
                      sourceTexture: sourceTexture,
                      target: targets.outputTexture,
                      sourceUniforms: sourceUniforms,
                      pipeline: pipeline,
                      commandBuffer: commandBuffer
                  ) else {
                return nil
            }
        default:
            return nil
        }
        return targets.outputTexture
    }

    private static func capture(
        sourceTexture: MTLTexture,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        SceneOffscreenEffectRenderer.captureSource(
            sourceTexture: sourceTexture,
            target: target,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        )
    }
}
