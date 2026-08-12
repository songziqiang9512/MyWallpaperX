import Metal

extension SceneEffectStageRenderer {
    static func renderDepthParallax(
        _ depthParallax: SceneDepthParallaxExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              let resources = masks.depthParallaxEffects[
                  depthParallax.effectKey.descriptorID
              ],
              let depthParallaxPipeline = pipelines.depthParallax else {
            return nil
        }
        if targets.inputTexture === sourceTexture {
            return SceneDepthParallaxRenderer.render(
                plan: depthParallax,
                resources: resources,
                sourceTexture: sourceTexture,
                target: targets.outputTexture,
                cursorUV: cursorUV,
                pointerIsInside: pointerIsInside,
                pipeline: depthParallaxPipeline,
                commandBuffer: commandBuffer
            )
        }
        guard SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return SceneDepthParallaxRenderer.render(
            plan: depthParallax,
            resources: resources,
            sourceTexture: targets.inputTexture,
            target: targets.outputTexture,
            cursorUV: cursorUV,
            pointerIsInside: pointerIsInside,
            pipeline: depthParallaxPipeline,
            commandBuffer: commandBuffer
        )
    }
}
