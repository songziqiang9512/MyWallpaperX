import CoreGraphics
import simd

extension SceneMetalRenderer {
    /// Preserves a graph provider's exact current source when its visible
    /// effects have no executable Program. The existing dependency runtime
    /// remains the sole named-target reservation and publication owner.
    func captureForwardGraphSourceFallback(
        provider: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        let baseSource = baseMaterialTextureSelection(
            for: provider,
            imageTextures: imageTextures,
            readyProviderUsesAuthoredLayerColor:
                baseMaterialReadyProviderUsesAuthoredLayerColor(
                    for: provider,
                    dynamicValues: frameContext.dynamicValues
                )
        ).source
        let model = imageModelMatrix(
            for: provider,
            worldFramesByLayerID: worldFramesByLayerID,
            renderSizeOverride: imageTextures.layerSourceRenderSize(
                for: provider.id
            ),
            parallaxMouseNormalized: frameContext.cameraParallaxPosition,
            configuration: parallaxConfiguration,
            visibleHalfExtents: cameraFrame.coverHalfExtents,
            usesPerspective: cameraFrame.resolvesPerspective(
                layerOverride: provider.usesPerspective
            )
        )
        return dependencyRuntime.captureGraphSourceFallbackIfRequired(
            layer: provider,
            sourceTexture: baseSource?.texture,
            sourceCandidate: baseSource?.candidate,
            usesAuthoredLayerColor:
                baseSource?.usesAuthoredLayerColor ?? true,
            layerMVP: cameraFrame.viewProjection(for: provider) * model,
            viewportSize: viewportSize,
            pipeline: imagePipeline,
            textureRegistry: textureRegistry,
            mainPass: mainPass
        ) == true
    }
}
