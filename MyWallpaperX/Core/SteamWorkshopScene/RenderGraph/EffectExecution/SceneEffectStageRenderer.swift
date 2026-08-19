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
        preciseBlurSampleExtent: SIMD2<Float>? = nil,
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
                sampleNormalizationExtent: preciseBlurSampleExtent,
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
        case .opacity(let opacity):
            guard let opacityPipeline = pipelines.opacity else { return nil }
            return renderOpacity(
                opacity, stage: stage, sourceTexture: sourceTexture, masks: masks,
targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                opacityPipeline: opacityPipeline, commandBuffer: commandBuffer
            )
        case .colorGrading:
            return renderColorStage(
                stage, sourceTexture: sourceTexture, masks: masks,
                targets: targets, sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline, pipelines: pipelines,
                commandBuffer: commandBuffer
            )
        case .workshopShiftHue, .workshopAudioBars, .workshopGradient:
            return renderWorkshopStage(
                stage,
                sourceTexture: sourceTexture,
                masks: masks,
targets: targets,
                dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                pipelines: pipelines,
                time: time,
                audioSpectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        case .workshopShadow(let shadow):
            guard let workshopShadowPipeline = pipelines.workshopShadow else { return nil }
            return SceneOffscreenEffectRenderer.renderWorkshopShadow(
                sourceTexture: sourceTexture,
                targets: targets,
                plan: shadow,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                workshopShadowPipeline: workshopShadowPipeline,
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
        case .lightShafts(let lightShafts):
            guard let resources = masks.lightShaftsEffects[
                      lightShafts.effectKey.descriptorID
                  ], let lightShaftsPipeline = pipelines.lightShafts else {
                return nil
            }
            return lightShaftsPipeline.renderOffscreen(
                plan: lightShafts,
                resources: resources,
                target: targets.outputTexture,
                time: time,
                commandBuffer: commandBuffer
            )
        case .shake, .waterFlow, .waterWaves, .waterCaustics,
             .cursorRipple, .waterRipple, .depthParallax,
             .xRay, .blend, .tint, .transform,
             .godrays, .shine, .pulse:
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
