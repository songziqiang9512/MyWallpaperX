import Metal

extension SceneMetalRenderer {
    func beginTextureFrame(
        _ imageTextures: SceneBaseImageTextureSnapshot,
        _ userPropertyTextures: [String: MTLTexture],
        _ mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot
    ) {
        textureRegistry.beginFrame(
            layerSources: imageTextures.textures,
            explicitLayerSources: imageTextures.explicitLayerSources,
            userPropertyTextures: userPropertyTextures,
            systemTextures: mediaThumbnail.systemTextures,
            explicitSystemTextures: mediaThumbnail.publications
        )
    }
}
