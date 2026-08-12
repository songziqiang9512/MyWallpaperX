import Metal

extension SceneEffectStageRenderer {
    static func renderGodrays(
        _ plan: SceneGodraysPlan,
        source: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        uniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let effectPipeline = pipelines.godrays else { return nil }
        return SceneGodraysRenderer.renderCaptured(
            plan: plan,
            sourceTexture: source,
            masks: masks,
            targets: targets,
            sourceUniforms: uniforms,
            sourcePipeline: sourcePipeline,
            godraysPipeline: effectPipeline,
            time: time,
            commandBuffer: commandBuffer
        )
    }

    static func renderShine(
        _ plan: SceneShineExecutionPlan,
        source: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        uniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let effectPipeline = pipelines.shine else { return nil }
        return SceneShineRenderer.renderCaptured(
            plan: plan,
            sourceTexture: source,
            masks: masks,
            targets: targets,
            sourceUniforms: uniforms,
            sourcePipeline: sourcePipeline,
            shinePipeline: effectPipeline,
            time: time,
            commandBuffer: commandBuffer
        )
    }
}
