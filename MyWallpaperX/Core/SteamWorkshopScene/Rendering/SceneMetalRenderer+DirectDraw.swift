import Metal
import simd

extension SceneMetalRenderer {
    func drawQuadLayer(
        layer: SceneRenderDescriptor.Layer,
        resolvedFramePlan: SceneResolvedMaterialFrameTargetPlan?,
        imagePipeline: SceneImageLayerPipeline?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool {
        guard let resolvedFramePlan else { return true }
        return drawResolvedDirectDrawQuad(
            layer: layer,
            framePlan: resolvedFramePlan,
            imagePipeline: imagePipeline,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            mainPass: mainPass,
            executionTrace: executionTrace
        )
    }

    func drawResolvedDirectDrawQuad(
        layer: SceneRenderDescriptor.Layer,
        framePlan: SceneResolvedMaterialFrameTargetPlan,
        imagePipeline: SceneImageLayerPipeline?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool {
        guard let imagePipeline,
              let model = directDrawModelMatrix(
                  for: layer,
                  worldFramesByLayerID: worldFramesByLayerID,
                  parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                  configuration: parallaxConfiguration
              ) else {
            return false
        }
        return imageCompositor.drawResolvedDirectDrawQuad(
            layer: layer,
            modelViewProjection: cameraFrame.orthographicViewProjection * model,
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
