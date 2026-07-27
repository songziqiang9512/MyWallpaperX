import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderWorkshopStage(
        _ stage: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        switch stage.backend {
        case .workshopShiftHue(let shiftHue):
            return renderWorkshopShiftHue(
                shiftHue,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                shiftHuePipeline: pipelines.shiftHue,
                time: time,
                commandBuffer: commandBuffer
            )
        case .workshopAudioBars(let audioBars):
            return renderWorkshopAudioBars(
                audioBars,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                audioBarsPipeline: pipelines.audioBars,
                spectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        case .workshopGradient(let gradient):
            return renderWorkshopGradient(
                gradient,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                gradientPipeline: pipelines.workshopGradient,
                commandBuffer: commandBuffer
            )
        case .workshopAudioHueShift(let hueShift):
            return renderWorkshopAudioHueShift(
                hueShift,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                hueShiftPipeline: pipelines.shiftHue,
                spectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        default:
            return nil
        }
    }
}
