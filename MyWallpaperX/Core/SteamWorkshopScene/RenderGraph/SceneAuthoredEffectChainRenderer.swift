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
            return SceneOffscreenEffectRenderer.renderPreciseBlur(
                executionPlan: stage,
                sourceTexture: sourceTexture,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                gaussianBlurPipeline: pipelines.gaussianBlur,
                commandBuffer: commandBuffer
            )
        case .standardBlur(let blur):
            return SceneOffscreenEffectRenderer.renderStandardBlur(
                sourceTexture: sourceTexture,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
                targets: targets,
                plan: blur,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                standardBlurPipeline: pipelines.standardBlur,
                commandBuffer: commandBuffer
            )
        case .localContrast(let contrast):
            guard let strength = stage.localContrastStrength(in: dynamicValues) else {
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
                localContrastPipeline: pipelines.localContrast,
                commandBuffer: commandBuffer
            )
        case .opacity(let opacity):
            return renderOpacity(
                opacity, stage: stage, sourceTexture: sourceTexture, masks: masks,
                auxMask: auxMask, targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                opacityPipeline: pipelines.opacity, commandBuffer: commandBuffer
            )
        case .colorKey(let colorKey):
            return renderColorKey(
                colorKey,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                colorKeyPipeline: pipelines.colorKey,
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
            return SceneOffscreenEffectRenderer.renderWorkshopShadow(
                sourceTexture: sourceTexture,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: auxMask,
                targets: targets,
                plan: shadow,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                workshopShadowPipeline: pipelines.workshopShadow,
                commandBuffer: commandBuffer
            )
        case .spin(let spin):
            return renderSpin(
                spin,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                spinPipeline: pipelines.spin,
                time: time,
                commandBuffer: commandBuffer
            )
        case .proceduralNoise(let noise):
            return renderProceduralNoise(
                noise,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                noisePipeline: pipelines.proceduralNoise,
                time: time,
                commandBuffer: commandBuffer
            )
        case .filmGrain(let filmGrain):
            return renderFilmGrain(
                filmGrain, sourceTexture: sourceTexture, masks: masks, auxMask: auxMask,
                targets: targets, sourceUniforms: sourceUniforms, pipeline: pipeline,
                filmGrainPipeline: pipelines.filmGrain, time: time,
                commandBuffer: commandBuffer
            )
        case .shake(let shake):
            guard let resources = masks.shakeEffects[shake.effectKey.descriptorID],
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
                pipeline: pipelines.shake,
                commandBuffer: commandBuffer
            )
        case .waterFlow(let waterFlow):
            return SceneWaterFlowRenderer.renderCaptured(
                plan: waterFlow,
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                waterFlowPipeline: pipelines.waterFlow,
                time: time,
                commandBuffer: commandBuffer
            )
        case .waterWaves(let waterWaves):
            return SceneWaterWavesRenderer.renderCaptured(
                plan: waterWaves,
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                waterWavesPipeline: pipelines.waterWaves,
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
                  pipelines.waterRipple.encode(
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
            guard targets.plan.logicalTargets.isEmpty,
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
            switch SceneXRayRuntimePlanner.resolve(
                declaration: xRay.declaration,
                resources: masks.xRay,
                snapshot: dynamicValues,
                pointerIsInside: pointerIsInside
            ) {
            case .identity:
                return targets.inputTexture
            case .unsupported:
                return nil
            case .render(let runtime):
                guard let resources = masks.xRay,
                      pipelines.xRay.encode(
                          source: targets.inputTexture,
                          resources: resources,
                          target: targets.outputTexture,
                          plan: runtime,
                          cursorUV: cursorUV,
                          commandBuffer: commandBuffer
                      ) else {
                    return nil
                }
                return targets.outputTexture
            }
        case .tint(let tint):
            return renderTint(
                tint,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                tintPipeline: pipelines.tint,
                commandBuffer: commandBuffer
            )
        case .godrays(let godrays):
            return SceneGodraysRenderer.renderCaptured(
                plan: godrays,
                sourceTexture: sourceTexture,
                masks: masks,
                targets: targets,
                sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline,
                godraysPipeline: pipelines.godrays,
                time: time,
                commandBuffer: commandBuffer
            )
        case .pulse(let pulse):
            return renderPulse(
                pulse,
                sourceTexture: sourceTexture,
                masks: masks,
                auxMask: auxMask,
                targets: targets,
                dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                pulsePipeline: pipelines.pulse,
                time: time,
                audioSpectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        case .authoredShader(let shader):
            return renderAuthoredShader(
                shader, sourceTexture: sourceTexture, masks: masks, auxMask: auxMask,
                targets: targets, sourceUniforms: sourceUniforms,
                frame: authoredShaderFrameInputs, pipeline: pipeline,
                pipelineCache: pipelines.authoredShader, commandBuffer: commandBuffer
            )
        }
    }

}
