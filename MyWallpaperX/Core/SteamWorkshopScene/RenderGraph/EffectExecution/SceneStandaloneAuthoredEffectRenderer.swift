import Metal

enum SceneStandaloneAuthoredEffectRenderer {
    static func render(
        plan: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        localContrastStrength: Float?,
        sourceUniforms: SceneLayerFragmentUniforms,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        sourcePipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        commandBuffer: MTLCommandBuffer,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> MTLTexture? {
        guard targets.encodeInitialTargetClear(commandBuffer: commandBuffer) else {
            executionTrace?.recordRouteOperation(
                layerID: plan.layerID,
                origin: executionOrigin,
                operation: "standalone-stage-preflight",
                outcome: .failed(reasonCode: "initial-clear-failed")
            )
            return nil
        }
        guard let effectKey = plan.renderGraph.effects.first?.key else {
            executionTrace?.recordRouteOperation(
                layerID: plan.layerID,
                origin: executionOrigin,
                operation: "standalone-stage-identity",
                outcome: .failed(reasonCode: "missing-effect-key")
            )
            return nil
        }
        let output: MTLTexture? = {
            switch plan.backend {
            case .preciseGaussian:
                guard let gaussianBlurPipeline = pipelines.gaussianBlur else {
                    return nil
                }
                return SceneOffscreenEffectRenderer.renderPreciseBlur(
                    executionPlan: plan,
                    sourceTexture: sourceTexture,
                    waterMaskTexture: masks.water,
                    foliageMaskTexture: masks.foliage,
                    auxMaskTexture: masks.iris ?? masks.opacity,
                    targets: targets,
                    sourceUniforms: sourceUniforms,
                    pipeline: sourcePipeline,
                    gaussianBlurPipeline: gaussianBlurPipeline,
                    commandBuffer: commandBuffer
                )
            case .standardBlur(let blur):
                guard let standardBlurPipeline = pipelines.standardBlur else {
                    return nil
                }
                return SceneOffscreenEffectRenderer.renderStandardBlur(
                    sourceTexture: sourceTexture,
                    masks: masks,
                    targets: targets,
                    plan: blur,
                    sourceUniforms: sourceUniforms,
                    pipeline: sourcePipeline,
                    standardBlurPipeline: standardBlurPipeline,
                    commandBuffer: commandBuffer
                )
            case .localContrast(let contrast):
                guard let localContrastPipeline = pipelines.localContrast else {
                    return nil
                }
                return SceneOffscreenEffectRenderer.renderLocalContrast(
                    sourceTexture: sourceTexture,
                    waterMaskTexture: masks.water,
                    foliageMaskTexture: masks.foliage,
                    auxMaskTexture: masks.iris ?? masks.opacity,
                    targets: targets,
                    plan: contrast,
                    strength: localContrastStrength
                        ?? contrast.staticOrFallbackStrength,
                    sourceUniforms: sourceUniforms,
                    pipeline: sourcePipeline,
                    localContrastPipeline: localContrastPipeline,
                    commandBuffer: commandBuffer
                )
            case .opacity(let opacity):
                let alpha = opacity.resolvedAlpha(in: dynamicValues)
                guard let opacityPipeline = pipelines.opacity,
                      targets.plan.logicalTargets.isEmpty,
                      SceneOffscreenEffectRenderer.captureSource(
                          sourceTexture: sourceTexture,
                          waterMaskTexture: masks.water,
                          foliageMaskTexture: masks.foliage,
                          auxMaskTexture: masks.iris ?? masks.opacity,
                          target: targets.inputTexture,
                          sourceUniforms: sourceUniforms,
                          pipeline: sourcePipeline,
                          commandBuffer: commandBuffer
                      ) else {
                    return nil
                }
                return SceneOpacityRenderer.render(
                    alpha: alpha,
                    // capture 已在 source shader 的 EFFECT_OPACITY_MASK 中乘过遮罩。
                    mask: nil,
                    maskUVScale: SIMD2(repeating: 1),
                    inputTexture: targets.inputTexture,
                    outputTexture: targets.outputTexture,
                    pipeline: opacityPipeline,
                    commandBuffer: commandBuffer
                )
            case .workshopShadow(let shadow):
                guard let workshopShadowPipeline = pipelines.workshopShadow else {
                    return nil
                }
                return SceneOffscreenEffectRenderer.renderWorkshopShadow(
                    sourceTexture: sourceTexture,
                    waterMaskTexture: masks.water,
                    foliageMaskTexture: masks.foliage,
                    auxMaskTexture: masks.iris ?? masks.opacity,
                    targets: targets,
                    plan: shadow,
                    sourceUniforms: sourceUniforms,
                    pipeline: sourcePipeline,
                    workshopShadowPipeline: workshopShadowPipeline,
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
                          auxMaskTexture: masks.iris ?? masks.opacity,
                          target: targets.inputTexture,
                          sourceUniforms: sourceUniforms,
                          pipeline: sourcePipeline,
                          commandBuffer: commandBuffer
                      ) else {
                    return nil
                }
                return SceneShakeRenderer.render(
                    plan: shake,
                    resources: resources,
                    time: sourceUniforms.time,
                    audioPulse: shake.audio.map {
                        SceneAudioResponse.evaluate(
                            spectrum: audioSpectrum,
                            parameters: $0
                        )
                    },
                    inputTexture: targets.inputTexture,
                    outputTexture: targets.outputTexture,
                    pipeline: shakePipeline,
                    commandBuffer: commandBuffer
                )
            case .waterWaves(let waterWaves):
                guard let waterWavesPipeline = pipelines.waterWaves else {
                    return nil
                }
                return SceneWaterWavesRenderer.renderCaptured(
                    plan: waterWaves,
                    sourceTexture: sourceTexture,
                    masks: masks,
                    targets: targets,
                    sourceUniforms: sourceUniforms,
                    sourcePipeline: sourcePipeline,
                    waterWavesPipeline: waterWavesPipeline,
                    time: sourceUniforms.time,
                    commandBuffer: commandBuffer
                )
            default:
                return nil
            }
        }()
        executionTrace?.recordExact(
            identity: SceneEffectExecutionIdentity(
                layerID: effectKey.layerID,
                effectIndex: effectKey.effectIndex,
                descriptorID: effectKey.descriptorID
            ),
            origin: executionOrigin,
            family: plan.executionFamilyStableName,
            backend: plan.backend.stableName,
            outcome: output == nil
                ? .failed(reasonCode: "backend-returned-no-output")
                : .encodedOutput
        )
        return output
    }
}
