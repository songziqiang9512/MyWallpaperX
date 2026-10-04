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
            usesPerspective: cameraFrame.resolvesPerspective(for: provider)
        )
        let result = dependencyRuntime.captureGraphSourceFallbackIfRequired(
            layer: provider,
            sourceTexture: baseSource?.texture,
            sourceCandidate: baseSource?.candidate,
            usesAuthoredLayerColor:
                baseSource?.usesAuthoredLayerColor ?? true,
            layerMVP: cameraFrame.viewProjection(for: provider) * model,
            viewportSize: viewportSize,
            pipeline: imagePipeline,
            textureRegistry: textureRegistry,
            mainPass: mainPass,
            geometryProduct: imageTextures.geometryProducts[provider.id]
        )
        switch result {
        case .published?, .unavailable?:
            // The consumer localizes a missing color publication; an ordinary
            // resource miss must not discard unrelated scene content.
            return true
        case .invalid?, nil:
            return false
        }
    }
}
