import Metal

extension SceneEffectStageRenderer {
    static func renderXRay(
        _ xRay: SceneXRayExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty else {
            return nil
        }
        if sourceTexture !== targets.inputTexture {
            guard SceneOffscreenEffectRenderer.captureSource(
                sourceTexture: sourceTexture,
                target: targets.inputTexture,
                sourceUniforms: sourceUniforms,
                pipeline: pipeline,
                commandBuffer: commandBuffer
            ) else { return nil }
        }
        switch SceneXRayRuntimePlanner.resolve(
            declaration: xRay.declaration,
            resources: masks.xRay,
            snapshot: dynamicValues,
            pointerIsInside: pointerIsInside
        ) {
        case .identity:
            guard copyIdentityOutput(
                source: targets.inputTexture,
                target: targets.outputTexture,
                commandBuffer: commandBuffer
            ) else { return nil }
            return targets.outputTexture
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

    private static func copyIdentityOutput(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard source !== target,
              source.width == target.width,
              source.height == target.height,
              source.pixelFormat == target.pixelFormat,
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }
        encoder.label = "Scene X-Ray identity output"
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: source.width, height: source.height, depth: 1),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        return true
    }
}
