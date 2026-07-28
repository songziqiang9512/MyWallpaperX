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
        pointerIsInside: Bool,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        authoredShaderFrameInputs: SceneAuthoredShaderFrameInputs?,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard !chain.stages.isEmpty,
              chain.stages.count == targets.count,
              validTopology(chain: chain, targets: targets),
              targets.allSatisfy({
                  $0.encodeInitialHistoryClear(commandBuffer: commandBuffer)
              }) else {
            return nil
        }

        var currentSource = sourceTexture
        for index in chain.stages.indices {
            let stage = chain.stages[index]
            let isFirstStage = index == chain.stages.startIndex
            guard let output = renderStage(
                stage,
                sourceTexture: currentSource,
                masks: isFirstStage ? masks : masks.authoredEffectResourcesOnly,
                targets: targets[index],
                dynamicValues: dynamicValues,
                sourceUniforms: isFirstStage ? sourceUniforms : .neutral(),
                pipeline: pipeline,
                pipelines: pipelines,
                cursorUV: cursorUV,
                pointerIsInside: pointerIsInside,
                time: sourceUniforms.time,
                audioSpectrum: audioSpectrum,
                authoredShaderFrameInputs: authoredShaderFrameInputs,
                commandBuffer: commandBuffer
            ) else {
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

    private static func renderStage(
        _ stage: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        authoredShaderFrameInputs: SceneAuthoredShaderFrameInputs?,
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
                pipeline: pipeline,
                gaussianBlurPipeline: gaussianBlurPipeline,
                commandBuffer: commandBuffer
            )
        case .standardBlur(let blur):
            guard let standardBlurPipeline = pipelines.standardBlur else { return nil }
            return SceneOffscreenEffectRenderer.renderStandardBlur(
                sourceTexture: sourceTexture,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
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
        case .colorKey(let colorKey):
            guard let colorKeyPipeline = pipelines.colorKey else { return nil }
            return renderColorKey(
                colorKey,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                colorKeyPipeline: colorKeyPipeline,
                commandBuffer: commandBuffer
            )
        case .workshopShiftHue, .workshopAudioBars, .workshopGradient,
             .workshopAudioHueShift:
            return renderWorkshopStage(
                stage,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
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
        case .spin(let spin):
            guard let spinPipeline = pipelines.spin else { return nil }
            return renderSpin(
                spin,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                spinPipeline: spinPipeline,
                time: time,
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
        case .shake(let shake):
            guard let resources = masks.shakeEffects[shake.effectKey.descriptorID],
                  let shakePipeline = pipelines.shake,
                  targets.plan.logicalTargets.isEmpty,
                  SceneOffscreenEffectRenderer.captureSource(
                      sourceTexture: sourceTexture,
                      waterMaskTexture: masks.water,
                      foliageMaskTexture: masks.foliage,
                      auxMaskTexture: auxMask,
                      target: targets.inputTexture,
                      sourceUniforms: sourceUniforms,
                      pipeline: pipeline,
                      commandBuffer: commandBuffer
                  ) else {
                return nil
            }
            return SceneShakeRenderer.render(
                plan: shake,
                resources: resources,
                time: time,
                audioPulse: shake.audio.map {
                    SceneAudioResponse.evaluate(spectrum: audioSpectrum, parameters: $0)
                },
                inputTexture: targets.inputTexture,
                outputTexture: targets.outputTexture,
                pipeline: shakePipeline,
                commandBuffer: commandBuffer
            )
        case .waterFlow(let waterFlow):
            guard let waterFlowPipeline = pipelines.waterFlow else { return nil }
            return SceneWaterFlowRenderer.renderCaptured(
                plan: waterFlow,
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                waterFlowPipeline: waterFlowPipeline,
                time: time,
                commandBuffer: commandBuffer
            )
        case .waterWaves(let waterWaves):
            guard let waterWavesPipeline = pipelines.waterWaves else { return nil }
            return SceneWaterWavesRenderer.renderCaptured(
                plan: waterWaves,
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                waterWavesPipeline: waterWavesPipeline,
                time: time,
                commandBuffer: commandBuffer
            )
        case .foliageSway(let foliage):
            guard targets.plan.logicalTargets.isEmpty,
                  let mask = masks.foliage else {
                return nil
            }
            return SceneFoliageSwayRenderer.render(
                plan: foliage,
                sourceTexture: sourceTexture,
                maskTexture: mask,
                maskUVScale: masks.foliageUVScale,
                target: targets.outputTexture,
                time: time,
                sourcePipeline: pipeline,
                commandBuffer: commandBuffer
            )
        case .waterRipple(let ripple):
            guard targets.plan.logicalTargets.isEmpty,
                  let mask = masks.water,
                  let normal = masks.waterRippleNormal,
                  let waterRipplePipeline = pipelines.waterRipple,
                  waterRipplePipeline.encode(
                      source: sourceTexture,
                      normalMap: normal,
                      target: targets.outputTexture,
                      plan: ripple.runtimePlan,
                      time: time,
                      maskTexture: mask,
                      maskUVScale: masks.waterUVScale,
                      commandBuffer: commandBuffer
                  ) else {
                return nil
            }
            return targets.outputTexture
        case .xRay(let xRay):
            return renderXRay(
                xRay, sourceTexture: sourceTexture, masks: masks, auxMask: auxMask,
                targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                pipelines: pipelines, cursorUV: cursorUV,
                pointerIsInside: pointerIsInside, commandBuffer: commandBuffer
            )
        case .blend(let blend):
            guard let blendPipeline = pipelines.blend else { return nil }
            return renderBlend(
                blend,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                blendPipeline: blendPipeline,
                commandBuffer: commandBuffer
            )
        case .tint(let tint):
            guard let tintPipeline = pipelines.tint else { return nil }
            return renderTint(
                tint,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                tintPipeline: tintPipeline,
                commandBuffer: commandBuffer
            )
        case .transform(let transform):
            return renderTransform(
                transform,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                commandBuffer: commandBuffer
            )
        case .godrays(let godrays):
            guard let godraysPipeline = pipelines.godrays else { return nil }
            return SceneGodraysRenderer.renderCaptured(
                plan: godrays,
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                godraysPipeline: godraysPipeline,
                time: time,
                commandBuffer: commandBuffer
            )
        case .pulse(let pulse):
            guard let pulsePipeline = pipelines.pulse else { return nil }
            return renderPulse(
                pulse,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                pulsePipeline: pulsePipeline,
                time: time,
                audioSpectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        case .authoredShader(let shader):
            guard let authoredShaderPipeline = pipelines.authoredShader else { return nil }
            return renderAuthoredShader(
                shader, sourceTexture: sourceTexture, masks: masks, auxMask: auxMask,
                targets: targets, sourceUniforms: sourceUniforms,
                frame: authoredShaderFrameInputs, pipeline: pipeline,
                pipelineCache: authoredShaderPipeline, commandBuffer: commandBuffer
            )
        }
    }

}
