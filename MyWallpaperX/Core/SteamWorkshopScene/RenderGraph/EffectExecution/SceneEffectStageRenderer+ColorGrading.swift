import Metal

extension SceneEffectStageRenderer {
    static func renderColorStage(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        switch stage.backend {
        case .colorGrading(let colorGrading):
            guard let pipeline = pipelines.colorGrading else { return nil }
            return renderColorGrading(
                colorGrading, sourceTexture: sourceTexture, masks: masks,
targets: targets, sourceUniforms: sourceUniforms,
                pipeline: sourcePipeline, colorGradingPipeline: pipeline,
                commandBuffer: commandBuffer
            )
        default:
            return nil
        }
    }

    static func renderColorGrading(
        _ colorGrading: SceneColorGradingExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        colorGradingPipeline: SceneColorGradingPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              colorGradingPipeline.encode(
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  plan: colorGrading,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
