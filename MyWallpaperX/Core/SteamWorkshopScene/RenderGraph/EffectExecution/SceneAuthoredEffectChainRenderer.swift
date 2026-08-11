import Metal

enum SceneAuthoredEffectChainRenderer {
    static func render(
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: [SceneGraphRenderTargetTable],
        chain: SceneAuthoredEffectExecutionChain,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        frameTime: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        dependencyEffect: SceneDependencyEffectInput?,
        commandBuffer: MTLCommandBuffer,
        executionTrace: SceneEffectExecutionFrameTrace? = nil,
        executionOrigin: SceneEffectExecutionOrigin = .image
    ) -> MTLTexture? {
        let executionStages = chain.executionStages
        guard !executionStages.isEmpty,
              executionStages.count == targets.count,
              validTopology(chain: chain, targets: targets),
              targets.allSatisfy({
                  $0.encodeInitialTargetClear(commandBuffer: commandBuffer)
              }) else {
            executionTrace?.recordRouteOperation(
                layerID: chain.layerID,
                origin: executionOrigin,
                operation: "authored-chain-preflight",
                outcome: .failed(reasonCode: "topology-target-or-clear")
            )
            return nil
        }

        var currentSource = sourceTexture
        for index in executionStages.indices {
            let stage = executionStages[index]
            let isFirstStage = index == executionStages.startIndex
            guard let effectKey = stage.renderGraph.effects.first?.key else {
                executionTrace?.recordRouteOperation(
                    layerID: chain.layerID,
                    origin: executionOrigin,
                    operation: "authored-stage-identity",
                    outcome: .failed(reasonCode: "missing-effect-key")
                )
                return nil
            }
            let output = renderStage(
                stage,
                sourceTexture: currentSource,
                masks: isFirstStage ? masks : masks.authoredEffectResourcesOnly,
                targets: targets[index],
                dynamicValues: dynamicValues,
                sourceUniforms: isFirstStage ? sourceUniforms : .neutral(),
                pipeline: pipeline,
                pipelines: pipelines,
                cursorUV: cursorUV,
                previousCursorUV: previousCursorUV,
                pointerIsInside: pointerIsInside,
                previousPointerIsInside: previousPointerIsInside,
                frameTime: frameTime,
                time: sourceUniforms.time,
                audioSpectrum: audioSpectrum,
                dependencyEffect: dependencyEffect,
                commandBuffer: commandBuffer
            )
            executionTrace?.recordExact(
                identity: SceneEffectExecutionIdentity(
                    layerID: effectKey.layerID,
                    effectIndex: effectKey.effectIndex,
                    descriptorID: effectKey.descriptorID
                ),
                origin: executionOrigin,
                family: stage.executionFamilyStableName,
                backend: stage.backend.stableName,
                outcome: output == nil
                    ? .failed(reasonCode: "backend-returned-no-output")
                    : .encodedOutput
            )
            guard let output else {
#if DEBUG
                print(
                    "MWX authored effect chain stage failed layer=\(chain.layerID) "
                        + "index=\(index) backend=\(stage.backend)"
                )
#endif
                return nil
            }
            currentSource = output
        }
        return currentSource
    }

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
