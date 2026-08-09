import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderWorkshopStage(
        _ stage: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
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
        case .workshopShiftHue(let shiftHue):
            guard let shiftHuePipeline = pipelines.shiftHue else { return nil }
            return renderWorkshopShiftHue(
                shiftHue,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                shiftHuePipeline: shiftHuePipeline,
                time: time,
                commandBuffer: commandBuffer
            )
        case .workshopAudioBars(let audioBars):
            guard case .enhancedSegmented = audioBars.profile,
                  let audioBarsPipeline = pipelines.audioBars else { return nil }
            return renderWorkshopAudioBars(
                audioBars,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
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
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                gradientPipeline: gradientPipeline,
                commandBuffer: commandBuffer
            )
        case .workshopAudioHueShift(let hueShift):
            guard let hueShiftPipeline = pipelines.shiftHue else { return nil }
            return renderWorkshopAudioHueShift(
                hueShift,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                hueShiftPipeline: hueShiftPipeline,
                spectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        default:
            return nil
        }
    }
}
