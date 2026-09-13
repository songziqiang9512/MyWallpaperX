extension SceneMetalRenderer {
    func drawQuadLayer(
        layer: SceneRenderDescriptor.Layer,
        resolvedFramePlan: SceneResolvedMaterialFrameTargetPlan?,
        imagePipeline: SceneImageLayerPipeline?,
        frameContext: SceneFrameContext,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool {
        if let resolvedFramePlan {
            return drawResolvedDirectDrawQuad(
                layer: layer,
                framePlan: resolvedFramePlan,
                imagePipeline: imagePipeline,
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
        imagePipeline: SceneImageLayerPipeline?,
        frameContext: SceneFrameContext,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool {
        guard let imagePipeline else {
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
