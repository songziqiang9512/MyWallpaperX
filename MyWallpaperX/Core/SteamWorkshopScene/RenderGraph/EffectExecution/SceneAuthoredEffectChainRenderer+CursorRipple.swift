import Metal
import simd

extension SceneAuthoredEffectChainRenderer {
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
        guard let effectPipeline = pipelines.waterFlow else { return nil }
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
            frameTime: frameTime,
            commandBuffer: commandBuffer
        )
    }
}
