import Metal
import simd

enum SceneLightShaftsLayerRenderer {
    static func draw(
        plan: SceneLightShaftsExecutionPlan,
        resources: SceneLightShaftsEffectTextures,
        model: simd_float4x4,
        viewProjection: simd_float4x4,
        time: Float,
        alpha: Float,
        pipeline: SceneLightShaftsPipeline,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool {
        guard let encoder = mainPass.encoder() else {
            executionTrace.recordRouteOperation(
                layerID: plan.effectKey.layerID,
                origin: .quad,
                operation: "light-shafts-main-pass",
                outcome: .failed(reasonCode: "encoder-unavailable")
            )
            return false
        }
        let encoded = pipeline.draw(
            plan: plan,
            resources: resources,
            mvp: viewProjection * model,
            time: time,
            alpha: alpha,
            encoder: encoder
        )
        let key = plan.effectKey
        executionTrace.recordExact(
            identity: SceneEffectExecutionIdentity(
                layerID: key.layerID,
                effectIndex: key.effectIndex,
                descriptorID: key.descriptorID
            ),
            origin: .quad,
            family: "light-shafts",
            backend: "light-shafts",
            outcome: encoded
                ? .encodedOutput
                : .failed(reasonCode: "backend-returned-false")
        )
        return encoded
    }
}

extension SceneMetalRenderer {
    func drawQuadLayer(
        layer: SceneRenderDescriptor.Layer,
        resolvedFramePlan: SceneResolvedMaterialFrameTargetPlan?,
        imagePipeline: SceneImageLayerPipeline?,
        effectTextures: SceneLayerEffectTextureStore,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        time: Float,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        executionTrace: SceneEffectExecutionFrameTrace,
        makeLightShaftsPipeline: () -> SceneLightShaftsPipeline?
    ) -> Bool {
        if let resolvedFramePlan {
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

        guard let plan = authoredEffectChain(for: layer.id)?.singleStage?.lightShafts,
              let resources = effectTextures.lightShaftsEffects[plan.effectKey.descriptorID],
              let pipeline = makeLightShaftsPipeline(),
              let model = lightShaftsModelMatrix(
                  for: layer,
                  worldFramesByLayerID: worldFramesByLayerID,
                  parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                  configuration: parallaxConfiguration
              ) else {
            return true
        }
        let encoded = SceneLightShaftsLayerRenderer.draw(
            plan: plan,
            resources: resources,
            model: model,
            viewProjection: cameraFrame.orthographicViewProjection,
            time: time,
            alpha: SceneDynamicLayerValues.alpha(
                layerID: layer.id,
                authoredValue: layer.alpha,
                snapshot: frameContext.dynamicValues
            ),
            pipeline: pipeline,
            mainPass: mainPass,
            executionTrace: executionTrace
        )
        authoredEffectTelemetry.record(
            layerID: layer.id,
            encoded: encoded,
            on: commandBuffer
        )
        return true
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
              let model = lightShaftsModelMatrix(
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
