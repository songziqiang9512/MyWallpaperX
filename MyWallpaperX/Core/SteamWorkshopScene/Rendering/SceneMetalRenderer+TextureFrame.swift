import Metal

extension SceneMetalRenderer {
    func commitResolvedMaterialAssetFrame() {
        imageCompositor.commitResolvedMaterialAssetFrame()
    }

    func discardResolvedMaterialAssetFrame() {
        imageCompositor.discardResolvedMaterialAssetFrame()
    }

    func commitFrameTexturePublication() {
        textureRegistry.commitFramePublication()
    }

    func discardFrameTexturePublication() {
        textureRegistry.discardFramePublication()
    }

    func discardUnsubmittedFrameResources() {
        discardResolvedMaterialAssetFrame()
        discardFrameTexturePublication()
    }

    func beginTextureFrame(
        _ imageTextures: SceneBaseImageTextureSnapshot,
        _ userPropertyTextures: [String: MTLTexture],
        _ userPropertyStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ],
        _ mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        _ frameContext: SceneFrameContext
    ) {
        textureRegistry.beginFrame(
            frameIndex: frameContext.frameIndex,
            layerSources: imageTextures.textures,
            explicitLayerSources: imageTextures.explicitLayerSources,
            assetStates: imageCompositor.resolvedMaterialAssetStates(
                sceneTime: frameContext.sceneTime
            ),
            userPropertyTextures: userPropertyTextures,
            userPropertyStates: userPropertyStates,
            systemProviderStates: mediaThumbnail.providerStates
        )
        for identity in baseMaterialProviderBindings.orderedSystemProviderDemands
            where mediaThumbnail.providerStates[identity] == nil {
            textureRegistry.set(.unavailable, for: .system(identity))
        }
        for (identity, status) in imageCompositor
            .resolvedMaterialSystemProviderBlocks(mediaThumbnail) {
            textureRegistry.set(status, for: .system(identity))
        }
        imageCompositor.beginResolvedMaterialFrame(
            textureSnapshot: textureRegistry.snapshot(),
            dynamicSnapshot: frameContext.dynamicValues,
            frameInputs: .init(frameContext: frameContext)
        )
    }
}
