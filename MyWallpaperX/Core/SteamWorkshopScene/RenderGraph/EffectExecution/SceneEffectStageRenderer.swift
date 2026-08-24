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
        case .preciseGaussian:
            guard let gaussianBlurPipeline = pipelines.gaussianBlur else { return nil }
            return SceneOffscreenEffectRenderer.renderPreciseBlur(
                executionPlan: stage,
                sourceTexture: sourceTexture,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                gaussianBlurPipeline: gaussianBlurPipeline,
                commandBuffer: commandBuffer
            )
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
        case .localContrast(let contrast):
            guard let strength = stage.localContrastStrength(in: dynamicValues),
                  let localContrastPipeline = pipelines.localContrast else {
                return nil
            }
            return SceneOffscreenEffectRenderer.renderLocalContrast(
                sourceTexture: sourceTexture,
                targets: targets,
                plan: contrast,
                strength: strength,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                localContrastPipeline: localContrastPipeline,
                commandBuffer: commandBuffer
            )
        case .proceduralNoise(let noise):
            guard let noisePipeline = pipelines.proceduralNoise else { return nil }
            return renderProceduralNoise(
                noise,
                sourceTexture: sourceTexture,
                masks: masks,
targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                noisePipeline: noisePipeline,
                dependencyEffect: dependencyEffect,
                time: time,
                commandBuffer: commandBuffer
            )
        case .waterWaves, .waterCaustics,
             .xRay, .blend, .transform,
             .godrays, .pulse:
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
