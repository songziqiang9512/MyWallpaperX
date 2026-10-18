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
        terminalMVP: simd_float4x4? = nil,
        terminalDepth: SceneImageLayerTerminalDepthBinding? = nil,
        isolatedGroupSource: MTLTexture? = nil,
        captureMVP: simd_float4x4? = nil,
        localCompositionSourceExtent: CGSize? = nil,
        executionTrace: SceneEffectExecutionFrameTrace? = nil
    ) -> Bool {
        guard plan.shouldCapture else {
            return false
        }
        let usesMaterialSource = layer.utilityLayer?.framebufferSource != nil
        if usesMaterialSource {
            guard resolvedMaterialFrameTargetPlan != nil, terminalMVP != nil,
                  terminalDepth != nil, pipeline.supportsReadOnlyDepth,
                  isolatedGroupSource == nil else { return false }
        }
        let executionOrigin: SceneEffectExecutionOrigin
        switch plan.kind {
        case .composition: executionOrigin = .utilityComposition
        case .project: executionOrigin = .utilityProject
        case .fullscreen: executionOrigin = .utilityFullscreen
        }
        guard let geometry = SceneCaptureGeometryResolver.resolve(
            kind: plan.kind,
            layerMVP: layerMVP,
            viewportSize: viewportSize,
            captureMVP: captureMVP,
            compositionSourceMemberLayerIDs: plan.isolatedGroupMembers,
            authoredRenderSizeWH: layer.renderSizeWH,
            localCompositionSourceExtent: localCompositionSourceExtent,
            usesMaterialSource: usesMaterialSource
        ) else { return false }
        // Only an already drawn member source uses viewport coordinates.
        // Empty transparent sources retain local effect and output geometry.
        if let isolatedGroupSource {
            guard let effectSourceExtent = SceneLayerEffectSourceExtent(
                pixelSize: geometry.pixelSize
            ) else { return false }
            let request = SceneImageLayerDrawRequest(
                layer: layer,
                texture: isolatedGroupSource,
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
        return mainPass.withReadableTarget { sourceTexture, _ in
            let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: sourceTexture,
                    masks: masks,
                    textureFrame: geometry.sourceUV,
                    mvp: terminalMVP ?? geometry.outputMVP,
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
                    audioSpectrum: audioSpectrum,
                    terminalDepth: terminalDepth
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
