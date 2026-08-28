import Metal

enum SceneEffectStageRenderer {
    static func renderStage(
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
        case .standardBlur(let blur):
            guard let standardBlurPipeline = pipelines.standardBlur else { return nil }
            return SceneOffscreenEffectRenderer.renderStandardBlur(
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                plan: blur,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                standardBlurPipeline: standardBlurPipeline,
                commandBuffer: commandBuffer
            )
        case .pulse:
            return renderSpecializedStage(
                stage, sourceTexture: sourceTexture, masks: masks,
targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                pipelines: pipelines, cursorUV: cursorUV,
                previousCursorUV: previousCursorUV,
                pointerIsInside: pointerIsInside,
                previousPointerIsInside: previousPointerIsInside,
                pointerMovement: pointerMovement,
                primaryButtonIsDown: primaryButtonIsDown,
                frameTime: frameTime, time: time, audioSpectrum: audioSpectrum,
                dependencyEffect: dependencyEffect, commandBuffer: commandBuffer
            )
        }
    }
}
