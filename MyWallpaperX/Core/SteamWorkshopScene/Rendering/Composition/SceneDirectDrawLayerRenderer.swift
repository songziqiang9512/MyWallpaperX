extension SceneMetalRenderer {
    func drawQuadLayer(
        layer: SceneRenderDescriptor.Layer,
        resolvedFramePlan: SceneResolvedMaterialFrameTargetPlan?,
        frameContext: SceneFrameContext,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?
    ) -> Bool {
        if let resolvedFramePlan {
            return drawResolvedDirectDrawQuad(
                layer: layer,
                framePlan: resolvedFramePlan,
                frameContext: frameContext,
                mainPass: mainPass,
                executionTrace: executionTrace
            )
        }

        return true
    }

    func drawResolvedDirectDrawQuad(
        layer: SceneRenderDescriptor.Layer,
        framePlan: SceneResolvedMaterialFrameTargetPlan,
        frameContext: SceneFrameContext,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?
    ) -> Bool {
        guard let imagePipeline = pipelineRepository.directDraw else {
            return false
        }
        return imageCompositor.drawResolvedDirectDrawQuad(
            layer: layer,
            alpha: SceneDynamicLayerValues.alpha(
                layerID: layer.id,
                authoredValue: layer.alpha,
                snapshot: frameContext.dynamicValues
            ),
            framePlan: framePlan,
            pipeline: imagePipeline,
            mainPass: mainPass,
            executionTrace: executionTrace
        )
    }
}
