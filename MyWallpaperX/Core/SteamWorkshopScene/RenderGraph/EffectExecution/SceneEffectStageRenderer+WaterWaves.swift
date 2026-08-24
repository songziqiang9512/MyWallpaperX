import Metal

extension SceneEffectStageRenderer {
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
            plan: plan,
            sourceTexture: sourceTexture,
            masks: masks,
            targets: targets,
            sourceUniforms: sourceUniforms,
            sourcePipeline: pipeline,
            waterWavesPipeline: effectPipeline,
            time: time,
            commandBuffer: commandBuffer
        )
    }
}
