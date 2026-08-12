import Metal

enum SceneAuthoredEffectChainRenderer {
    static func renderStage(
        _ stage: SceneAuthoredEffectExecutionPlan,
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
        frameTime: Float,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        dependencyEffect: SceneDependencyEffectInput?,
        preciseBlurSampleExtent: SIMD2<Float>? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let auxMask = masks.iris ?? masks.opacity
        switch stage.backend {
        case .preciseGaussian:
            guard let gaussianBlurPipeline = pipelines.gaussianBlur else { return nil }
            return SceneOffscreenEffectRenderer.renderPreciseBlur(
                executionPlan: stage,
                sourceTexture: sourceTexture,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
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
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
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
                auxMask: auxMask, targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                opacityPipeline: opacityPipeline, commandBuffer: commandBuffer
            )
        case .colorGrading:
            return renderColorStage(
                stage, sourceTexture: sourceTexture, masks: masks, auxMask: auxMask,
                targets: targets, sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline, pipelines: pipelines,
                commandBuffer: commandBuffer
            )
        case .workshopShiftHue, .workshopAudioBars, .workshopGradient:
            return renderWorkshopStage(
                stage,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
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
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
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
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                noisePipeline: noisePipeline,
                dependencyEffect: dependencyEffect,
                time: time,
                commandBuffer: commandBuffer
            )
        case .filmGrain(let filmGrain):
            guard let filmGrainPipeline = pipelines.filmGrain else { return nil }
            return renderFilmGrain(
                filmGrain, sourceTexture: sourceTexture, masks: masks, auxMask: auxMask,
                targets: targets, sourceUniforms: sourceUniforms, pipeline: pipeline,
                filmGrainPipeline: filmGrainPipeline, time: time,
                commandBuffer: commandBuffer
            )
        case .lightShafts:
            return nil
        case .shake, .waterFlow, .waterWaves, .waterCaustics,
             .cursorRipple, .foliageSway, .waterRipple, .depthParallax,
             .xRay, .clippingMask, .blend, .tint, .transform,
             .fisheyeZeroDistortion, .godrays, .shine, .pulse:
            return renderSpecializedStage(
                stage, sourceTexture: sourceTexture, masks: masks,
                auxMask: auxMask, targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                pipelines: pipelines, cursorUV: cursorUV,
                previousCursorUV: previousCursorUV,
                pointerIsInside: pointerIsInside,
                previousPointerIsInside: previousPointerIsInside,
                frameTime: frameTime, time: time, audioSpectrum: audioSpectrum,
                dependencyEffect: dependencyEffect, commandBuffer: commandBuffer
            )
        }
    }
}
