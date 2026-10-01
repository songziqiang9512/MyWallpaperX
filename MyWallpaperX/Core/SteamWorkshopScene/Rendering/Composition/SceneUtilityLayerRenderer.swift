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
        dependencyEffects: [SceneDependencyEffectInput] = [],
        requiresDependencyEffect: Bool = false,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        offscreenTexturePool: SceneOffscreenTexturePool,
        mainPass: SceneMainPassEncoder,
        resolvedMaterialFrameTargetPlan: SceneResolvedMaterialFrameTargetPlan? = nil,
        isolatedGroupSource: (texture: MTLTexture, pixelSize: CGSize)? = nil,
        executionTrace: SceneEffectExecutionFrameTrace? = nil
    ) -> Bool {
        guard plan.shouldCapture else {
            return false
        }
        let executionOrigin: SceneEffectExecutionOrigin
        switch plan.kind {
        case .composition: executionOrigin = .utilityComposition
        case .project: executionOrigin = .utilityProject
        case .fullscreen: executionOrigin = .utilityFullscreen
        }
        // D1 isolated group: the group's own transparent-clear target is the
        // effect-chain source. Members already encoded their content there
        // in authored relative order; the composite is a single 1:1 blit of
        // that target through the root effect chain into the enclosing pass,
        // so no main-target capture and no source copy apply.
        if let isolatedGroupSource {
            guard isolatedGroupSource.pixelSize.width.isFinite,
                  isolatedGroupSource.pixelSize.width > 0,
                  isolatedGroupSource.pixelSize.height.isFinite,
                  isolatedGroupSource.pixelSize.height > 0,
                  let effectSourceExtent = SceneLayerEffectSourceExtent(
                      pixelSize: isolatedGroupSource.pixelSize
                  ) else {
                return false
            }
            let request = SceneImageLayerDrawRequest(
                layer: layer,
                texture: isolatedGroupSource.texture,
                masks: masks,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: time,
                    alpha: 1,
                    cursorUV: cursorUV,
                    cursorIsInside: pointerIsInside
                ),
                offscreenTexturePool: offscreenTexturePool,
                resolvedMaterialFrameTargetPlan:
                    resolvedMaterialFrameTargetPlan,
                effectSourceExtent: effectSourceExtent,
                requiresSourceCopy: false,
                finalCompositeAlpha: finalCompositeAlpha,
                dependencyEffects: dependencyEffects,
                requiresDependencyEffect: requiresDependencyEffect,
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
        }
        guard let geometry = SceneCaptureGeometryResolver.resolve(
                  kind: plan.kind,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ) else {
            return false
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
                    dependencyEffects: dependencyEffects,
                    requiresDependencyEffect: requiresDependencyEffect,
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
