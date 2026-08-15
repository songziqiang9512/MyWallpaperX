import Metal
import simd

extension SceneEffectStageRenderer {
    static func renderWaterFlow(
        _ plan: SceneWaterFlowExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              let resources = masks.waterFlowEffects[plan.effectKey.descriptorID],
              let effectPipeline = pipelines.waterFlow else { return nil }
        if targets.inputTexture === sourceTexture {
            return SceneWaterFlowRenderer.render(
                plan: plan,
                resources: resources,
                time: time,
                inputTexture: sourceTexture,
                outputTexture: targets.outputTexture,
                pipeline: effectPipeline,
                commandBuffer: commandBuffer
            )
        }
        return SceneWaterFlowRenderer.renderCaptured(
            plan: plan, sourceTexture: sourceTexture, masks: masks, targets: targets,
            sourceUniforms: sourceUniforms, sourcePipeline: pipeline,
            waterFlowPipeline: effectPipeline, time: time, commandBuffer: commandBuffer
        )
    }

    static func renderWaterWaves(
        _ plan: SceneWaterWavesExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let effectPipeline = pipelines.waterWaves else { return nil }
        return SceneWaterWavesRenderer.renderCaptured(
            plan: plan, sourceTexture: sourceTexture, masks: masks, targets: targets,
            sourceUniforms: sourceUniforms, sourcePipeline: pipeline,
            waterWavesPipeline: effectPipeline, time: time, commandBuffer: commandBuffer
        )
    }

    static func renderCursorRipple(
        _ plan: SceneCursorRippleExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
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
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let cursorRipplePipeline = pipelines.cursorRipple else { return nil }
        return SceneCursorRippleRenderer.renderCaptured(
            plan: plan,
            sourceTexture: sourceTexture,
            masks: masks,
            targets: targets,
            sourceUniforms: sourceUniforms,
            sourcePipeline: pipeline,
            cursorRipplePipeline: cursorRipplePipeline,
            currentCursorUV: cursorUV,
            previousCursorUV: previousCursorUV,
            pointerIsInside: pointerIsInside,
            previousPointerIsInside: previousPointerIsInside,
            pointerMovement: pointerMovement,
            primaryButtonIsDown: primaryButtonIsDown,
            frameTime: frameTime,
            commandBuffer: commandBuffer
        )
    }
}
