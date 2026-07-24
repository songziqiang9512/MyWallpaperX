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
                time: sourceUniforms.time,
                commandBuffer: commandBuffer
            ) else {
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
        time: Float,
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
        case .opacity:
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
