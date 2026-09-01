import CoreGraphics
import Metal
import simd

enum SceneUtilityLayerRenderer {
    @discardableResult
    static func draw(
        layer: SceneRenderDescriptor.Layer,
        plan: SceneUtilityLayerRuntimePlan,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        time: Float,
        finalCompositeAlpha: Float,
        masks: SceneImageLayerMasks,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        dynamicValues: SceneDynamicSnapshot,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        dependencyEffect: SceneDependencyEffectInput?,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        offscreenTexturePool: SceneOffscreenTexturePool,
        mainPass: SceneMainPassEncoder,
        resolvedMaterialFrameTargetPlan: SceneResolvedMaterialFrameTargetPlan? = nil,
        executionTrace: SceneEffectExecutionFrameTrace? = nil
    ) -> Bool {
        guard plan.shouldCapture,
              let geometry = SceneCaptureGeometryResolver.resolve(
                  kind: plan.kind,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ) else {
            return false
        }
        let executionOrigin: SceneEffectExecutionOrigin
        switch plan.kind {
        case .composition: executionOrigin = .utilityComposition
        case .project: executionOrigin = .utilityProject
        case .fullscreen: executionOrigin = .utilityFullscreen
        }
        return mainPass.withReadableTarget { sourceTexture, _ in
            var request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: sourceTexture,
                    masks: masks,
                    textureFrame: geometry.sourceUV,
                    mvp: geometry.outputMVP,
                    uniforms: SceneImageLayerUniformValues(
                        time: time,
                        alpha: 1,
                        cursorUV: cursorUV,
                        cursorIsInside: pointerIsInside
                    ),
                    offscreenTexturePool: offscreenTexturePool,
                    resolvedMaterialFrameTargetPlan:
                        resolvedMaterialFrameTargetPlan,
                    effectSourceExtent: SceneLayerEffectSourceExtent(
                        pixelSize: geometry.pixelSize
                    ),
                    requiresSourceCopy: true,
                    finalCompositeAlpha: finalCompositeAlpha,
                    dependencyEffect: dependencyEffect,
                    dynamicValues: dynamicValues,
                    audioSpectrum: audioSpectrum
                )
            return compositor.draw(
                request,
                pipeline: pipeline,
                mainPass: mainPass,
                executionTrace: executionTrace,
                executionOrigin: executionOrigin
            )
        } ?? false
    }
}
