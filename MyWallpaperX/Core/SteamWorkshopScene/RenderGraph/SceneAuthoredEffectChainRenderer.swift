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
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        standardBlurPipeline: SceneStandardBlurPipeline,
        localContrastPipeline: SceneLocalContrastPipeline,
        opacityPipeline: SceneOpacityPipeline,
        workshopShadowPipeline: SceneWorkshopShadowPipeline,
        shakePipeline: SceneShakePipeline,
        waterFlowPipeline: SceneWaterFlowPipeline,
        waterWavesPipeline: SceneWaterWavesPipeline,
        waterRipplePipeline: SceneWaterRipplePipeline,
        xRayPipeline: SceneXRayPipeline,
        tintPipeline: SceneTintPipeline,
        pulsePipeline: ScenePulsePipeline,
        godraysPipeline: SceneGodraysPipeline,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        audioSpectrum: SceneAudioSpectrumSnapshot,
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
                gaussianBlurPipeline: gaussianBlurPipeline,
                standardBlurPipeline: standardBlurPipeline,
                localContrastPipeline: localContrastPipeline,
                opacityPipeline: opacityPipeline,
                workshopShadowPipeline: workshopShadowPipeline,
                shakePipeline: shakePipeline,
                waterFlowPipeline: waterFlowPipeline,
                waterWavesPipeline: waterWavesPipeline,
                waterRipplePipeline: waterRipplePipeline,
                xRayPipeline: xRayPipeline,
                tintPipeline: tintPipeline,
                pulsePipeline: pulsePipeline,
                godraysPipeline: godraysPipeline,
                cursorUV: cursorUV,
                pointerIsInside: pointerIsInside,
                time: sourceUniforms.time,
                audioSpectrum: audioSpectrum,
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
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        standardBlurPipeline: SceneStandardBlurPipeline,
        localContrastPipeline: SceneLocalContrastPipeline,
        opacityPipeline: SceneOpacityPipeline,
        workshopShadowPipeline: SceneWorkshopShadowPipeline,
        shakePipeline: SceneShakePipeline,
        waterFlowPipeline: SceneWaterFlowPipeline,
        waterWavesPipeline: SceneWaterWavesPipeline,
        waterRipplePipeline: SceneWaterRipplePipeline,
        xRayPipeline: SceneXRayPipeline,
        tintPipeline: SceneTintPipeline,
        pulsePipeline: ScenePulsePipeline,
        godraysPipeline: SceneGodraysPipeline,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
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
                gaussianBlurPipeline: gaussianBlurPipeline,
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
                standardBlurPipeline: standardBlurPipeline,
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
                localContrastPipeline: localContrastPipeline,
                commandBuffer: commandBuffer
            )
        case .opacity(let opacity):
            // 官方 opacity.frag 的遮罩挂在 effect 实例上（同一层可以有多个 opacity 各绑一张），
            // 所以按 descriptorID 取，且声明了遮罩却取不到贴图时整段拒绝，不静默降级成无遮罩。
            var opacityMask: MTLTexture?
            var opacityMaskUVScale = SIMD2<Float>(repeating: 1)
            if opacity.maskTexturePath != nil {
                guard let resources = masks.opacityEffects[opacity.effectKey.descriptorID],
                      resources.matches(opacity),
                      let texture = resources.mask else {
                    return nil
                }
                opacityMask = texture
                opacityMaskUVScale = resources.maskUVScale
            }
            guard let alpha = stage.opacityAlpha(in: dynamicValues),
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
            return SceneOpacityRenderer.render(
                alpha: alpha,
                mask: opacityMask,
                maskUVScale: opacityMaskUVScale,
                inputTexture: targets.inputTexture,
                outputTexture: targets.outputTexture,
                pipeline: opacityPipeline,
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
                workshopShadowPipeline: workshopShadowPipeline,
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
                pipeline: shakePipeline,
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
                waterFlowPipeline: waterFlowPipeline,
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
                      xRayPipeline.encode(
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
                tintPipeline: tintPipeline,
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
                godraysPipeline: godraysPipeline,
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
                pulsePipeline: pulsePipeline,
                time: time,
                audioSpectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        }
    }

    private static func validTopology(
        chain: SceneAuthoredEffectExecutionChain,
        targets: [SceneGraphRenderTargetTable]
    ) -> Bool {
        var previousOutput: SceneAuthoredEffectRenderPlan.TextureIdentity?
        for index in chain.stages.indices {
            let stage = chain.stages[index]
            let table = targets[index]
            guard stage.layerID == chain.layerID,
                  table.plan.layerID == chain.layerID,
                  table.plan.inputRole == stage.inputRole,
                  table.plan.input == stage.renderGraph.effects.first?.input,
                  table.plan.output == stage.renderGraph.finalOutput else {
                return false
            }
            if index == chain.stages.startIndex {
                guard stage.inputRole == .layerSource else { return false }
            } else {
                guard stage.inputRole == .priorEffectOutput,
                      stage.renderGraph.effects.first?.input == previousOutput else {
                    return false
                }
            }
            previousOutput = stage.renderGraph.finalOutput
        }
        return previousOutput == chain.renderGraph.finalOutput
    }
}
