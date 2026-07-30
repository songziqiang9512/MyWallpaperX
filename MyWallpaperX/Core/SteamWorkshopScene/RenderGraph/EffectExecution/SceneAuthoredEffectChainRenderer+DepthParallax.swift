import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderDepthParallax(
        _ depthParallax: SceneDepthParallaxExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
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
              let depthParallaxPipeline = pipelines.depthParallax,
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
