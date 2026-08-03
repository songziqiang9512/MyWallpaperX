import Metal

extension SceneMetalRenderer {
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
            assetStates: imageCompositor.resolvedMaterialAssetStates,
            userPropertyTextures: userPropertyTextures,
            userPropertyStates: userPropertyStates,
            systemTextures: mediaThumbnail.systemTextures,
            explicitSystemTextures: mediaThumbnail.publications
        )
        for (name, status) in imageCompositor
            .resolvedMaterialSystemProviderBlocks(mediaThumbnail) {
            textureRegistry.set(status, for: .system(name))
        }
        imageCompositor.beginResolvedMaterialFrame(
            textureSnapshot: textureRegistry.snapshot(),
            dynamicSnapshot: frameContext.dynamicValues,
            frameInputs: .init(frameContext: frameContext)
        )
    }
}
