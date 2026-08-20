import Metal

extension SceneEffectStageRenderer {
    static func renderWorkshopStage(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        switch stage.backend {
        case .workshopAudioBars(let audioBars):
            guard case .enhancedSegmented = audioBars.profile,
                  let audioBarsPipeline = pipelines.audioBars else { return nil }
            return renderWorkshopAudioBars(
                audioBars,
                sourceTexture: sourceTexture,
                masks: masks,
targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                audioBarsPipeline: audioBarsPipeline,
                spectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        case .workshopGradient(let gradient):
            guard let gradientPipeline = pipelines.workshopGradient else { return nil }
            return renderWorkshopGradient(
                gradient,
                sourceTexture: sourceTexture,
                masks: masks,
targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                gradientPipeline: gradientPipeline,
                commandBuffer: commandBuffer
            )
        default:
            return nil
        }
    }
}
