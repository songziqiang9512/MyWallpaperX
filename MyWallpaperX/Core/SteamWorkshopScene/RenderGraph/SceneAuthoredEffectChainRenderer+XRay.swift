import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderXRay(
        _ xRay: SceneXRayExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
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
                  let xRayPipeline = pipelines.xRay,
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
    }
}
