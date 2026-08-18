import Metal

extension SceneEffectStageRenderer {
    static func renderSpecializedStage(
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
        case .shake(let shake):
            guard let resources = masks.shakeEffects[shake.effectKey.descriptorID],
                  let shakePipeline = pipelines.shake,
                  targets.plan.logicalTargets.isEmpty,
                  SceneOffscreenEffectRenderer.captureSource(
                      sourceTexture: sourceTexture,
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
        case .waterFlow(let waterFlow):
            return renderWaterFlow(
                waterFlow, sourceTexture: sourceTexture, masks: masks,
                targets: targets, sourceUniforms: sourceUniforms,
                pipeline: pipeline, pipelines: pipelines,
                time: time, commandBuffer: commandBuffer
            )
        case .waterWaves(let waterWaves):
            return renderWaterWaves(
                waterWaves, sourceTexture: sourceTexture, masks: masks,
                targets: targets, sourceUniforms: sourceUniforms,
                pipeline: pipeline, pipelines: pipelines,
                time: time, commandBuffer: commandBuffer
            )
        case .waterCaustics(let caustics):
            return renderWaterCaustics(
                caustics, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                sourceUniforms: sourceUniforms, sourcePipeline: pipeline,
                pipelines: pipelines, time: time, commandBuffer: commandBuffer
            )
        case .cursorRipple(let cursorRipple):
            return renderCursorRipple(
                cursorRipple, sourceTexture: sourceTexture, masks: masks,
                targets: targets, sourceUniforms: sourceUniforms,
                pipeline: pipeline, pipelines: pipelines,
                cursorUV: cursorUV, previousCursorUV: previousCursorUV,
                pointerIsInside: pointerIsInside,
                previousPointerIsInside: previousPointerIsInside,
                pointerMovement: pointerMovement,
                primaryButtonIsDown: primaryButtonIsDown,
                frameTime: frameTime, commandBuffer: commandBuffer
            )
        case .waterRipple(let ripple):
            return renderWaterRipple(
                ripple, sourceTexture: sourceTexture, masks: masks,
                targets: targets, pipelines: pipelines,
                time: time, commandBuffer: commandBuffer
            )
        case .depthParallax(let depthParallax):
            return renderDepthParallax(
                depthParallax, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                pipelines: pipelines, cursorUV: cursorUV,
                pointerIsInside: pointerIsInside, commandBuffer: commandBuffer
            )
        case .xRay(let xRay):
            return renderXRay(
                xRay, sourceTexture: sourceTexture, masks: masks,
targets: targets, dynamicValues: dynamicValues,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                pipelines: pipelines, cursorUV: cursorUV,
                pointerIsInside: pointerIsInside, commandBuffer: commandBuffer
            )
        case .blend(let blend):
            guard let blendPipeline = pipelines.blend else { return nil }
            return renderBlend(
                blend, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                dynamicValues: dynamicValues, sourceUniforms: sourceUniforms,
                sourcePipeline: pipeline, blendPipeline: blendPipeline,
                dependencyEffect: dependencyEffect,
                commandBuffer: commandBuffer
            )
        case .tint(let tint):
            guard let tintPipeline = pipelines.tint else { return nil }
            return renderTint(
                tint, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                dynamicValues: dynamicValues, sourceUniforms: sourceUniforms,
                pipeline: pipeline, tintPipeline: tintPipeline,
                commandBuffer: commandBuffer
            )
        case .transform:
            return renderTransform(
                stage, sourceTexture: sourceTexture, targets: targets,
                sourceUniforms: sourceUniforms, pipeline: pipeline,
                commandBuffer: commandBuffer
            )
        case .godrays(let godrays):
            return renderGodrays(
                godrays, source: sourceTexture, masks: masks, targets: targets,
                uniforms: sourceUniforms, sourcePipeline: pipeline,
                pipelines: pipelines, time: time, commandBuffer: commandBuffer
            )
        case .shine(let shine):
            return renderShine(
                shine, source: sourceTexture, masks: masks, targets: targets,
                uniforms: sourceUniforms, sourcePipeline: pipeline,
                pipelines: pipelines, time: time, commandBuffer: commandBuffer
            )
        case .pulse(let pulse):
            guard let pulsePipeline = pipelines.pulse else { return nil }
            return renderPulse(
                pulse, sourceTexture: sourceTexture, masks: masks,
targets: targets,
                dynamicValues: dynamicValues, sourceUniforms: sourceUniforms,
                pipeline: pipeline, pulsePipeline: pulsePipeline,
                time: time, audioSpectrum: audioSpectrum,
                commandBuffer: commandBuffer
            )
        default:
            return nil
        }
    }
}
