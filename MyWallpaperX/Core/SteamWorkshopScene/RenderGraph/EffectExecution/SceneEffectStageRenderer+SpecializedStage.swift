import Metal

extension SceneEffectStageRenderer {
    static func renderSpecializedStage(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        pointerMovement: Float,
        primaryButtonIsDown: Bool,
        frameTime: Float,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        dependencyEffect: SceneDependencyEffectInput?,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        switch stage.backend {
        case .waterWaves(let waterWaves):
            return renderWaterWaves(
                waterWaves, sourceTexture: sourceTexture, masks: masks,
                targets: targets, sourceUniforms: sourceUniforms,
                pipeline: pipeline, pipelines: pipelines,
                time: time, commandBuffer: commandBuffer
            )
        case .xRay(let xRay):
            return renderXRay(
                xRay, sourceTexture: sourceTexture, masks: masks,
targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                pipelines: pipelines, cursorUV: cursorUV,
                pointerIsInside: pointerIsInside, commandBuffer: commandBuffer
            )
        case .blend(let blend):
            guard let blendPipeline = pipelines.blend else { return nil }
            return renderBlend(
                blend, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                dynamicValues: dynamicValues, sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline, blendPipeline: blendPipeline,
                dependencyEffect: dependencyEffect,
                commandBuffer: commandBuffer
            )
        case .transform:
            return renderTransform(
                stage, sourceTexture: sourceTexture, targets: targets,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                commandBuffer: commandBuffer
            )
        case .pulse(let pulse):
            guard let pulsePipeline = pipelines.pulse else { return nil }
            return renderPulse(
                pulse, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                dynamicValues: dynamicValues, sourceUniforms: sourceUniforms,
                pipeline: pipeline, pulsePipeline: pulsePipeline,
                time: time, audioSpectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        default:
            return nil
        }
    }
}
