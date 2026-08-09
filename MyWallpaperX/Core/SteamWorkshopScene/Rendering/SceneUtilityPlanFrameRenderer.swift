import CoreGraphics
import Metal
import simd

enum SceneUtilityPlanFrameRenderer {
    static func render(
        renderer: SceneMetalRenderer,
        plans: [SceneUtilityLayerRuntimePlan],
        dependencyRuntime: SceneDependencyFrameRuntime,
        imageCompositor: SceneImageLayerCompositor,
        utilityCaptureTelemetry: SceneGPUCompletionTelemetry,
        authoredEffectTelemetry: SceneGPUCompletionTelemetry,
        effectTextures: SceneLayerEffectTextureStore,
        imagePipeline: SceneImageLayerPipeline,
        offscreenTexturePool: SceneOffscreenTexturePool,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        time: Float,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        frameTransaction: SceneSourceUpdateTransaction,
        effectExecutionTrace: SceneEffectExecutionFrameTrace,
        resolvedMaterialFrameTargetPlans: [
            Int: SceneResolvedMaterialFrameTargetPlan
        ] = [:],
        legacyAuthoredFrameTables: [Int: SceneOffscreenTexturePool.LegacyAuthoredFrameTables] = [:]
    ) {
        for plan in plans {
            guard let layer = renderer.layersByID[plan.layerID] else { continue }
            let model = renderer.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
            let mvp = cameraFrame.orthographicViewProjection * model
            let cursorUV = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: mvp
            )
            let authoredEffectChain = renderer.authoredEffectChain(for: layer.id)
            let requiresDependencyEffect = dependencyRuntime.requiresEffect(
                for: layer.id
            )
            let dependencyEffect = dependencyRuntime.effectInput(
                for: layer.id,
                textureRegistry: renderer.textureRegistry
            )
            var selectedLegacyAuthoredRoute = false
            let captured: Bool
            if requiresDependencyEffect && dependencyEffect == nil {
                dependencyRuntime.recordBindingFailure(for: layer.id)
                captured = false
            } else {
                captured = SceneUtilityLayerRenderer.draw(
                    layer: layer,
                    plan: plan,
                    layerMVP: mvp,
                    viewportSize: viewportSize,
                    time: time,
                    finalCompositeAlpha: SceneDynamicLayerValues.alpha(
                        layerID: layer.id,
                        authoredValue: layer.alpha,
                        snapshot: frameContext.dynamicValues
                    ),
                    masks: renderer.effectMasks(
                        for: layer.id,
                        in: effectTextures
                    ).authoredEffectResourcesOnly,
                    cursorUV: cursorUV ?? .zero,
                    pointerIsInside: frameContext.pointer.isInside && cursorUV != nil,
                    authoredEffectChain: authoredEffectChain,
                    dynamicValues: frameContext.dynamicValues,
                    audioSpectrum: frameContext.audioSpectrum,
                    blocksLegacyGaussianBlur: renderer.blocksLegacyGaussianBlur(
                        for: layer.id
                    ),
                    dependencyEffect: dependencyEffect,
                    pipeline: imagePipeline,
                    compositor: imageCompositor,
                    offscreenTexturePool: offscreenTexturePool,
                    mainPass: mainPass,
                    frameTransaction: frameTransaction,
                    resolvedMaterialFrameTargetPlan:
                        resolvedMaterialFrameTargetPlans[layer.id],
                    executionTrace: effectExecutionTrace,
                    onLegacyAuthoredRouteSelected: {
                        selectedLegacyAuthoredRoute = true
                    },
                    legacyAuthoredFrameTables: legacyAuthoredFrameTables[layer.id]
                )
            }
            utilityCaptureTelemetry.record(
                layerID: layer.id,
                encoded: captured,
                on: commandBuffer
            )
            dependencyRuntime.recordBindingIfRequired(
                for: layer.id,
                encoded: captured,
                on: commandBuffer
            )
            if selectedLegacyAuthoredRoute {
                authoredEffectTelemetry.record(
                    layerID: layer.id,
                    encoded: captured,
                    on: commandBuffer
                )
            }
        }
    }
}
