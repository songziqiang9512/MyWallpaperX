import Metal

enum SceneFrameLayerTextureAssembly {
    static func make(
        base: SceneBaseImageTextureStore,
        dynamicText: SceneDynamicTextTextureStore.Snapshot?,
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot? = nil,
        mediaBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        videoSources: [Int: SceneVideoTextureSource],
        timing: SceneFrameTiming
    ) -> SceneBaseImageTextureSnapshot {
        var textures = base.textures
        var publications: [Int: SceneTextureProviderPublication] = [:]
        var layerSourcePublications: [Int: SceneLayerSourcePublication] = [:]
        var pendingLayerSourceIDs: Set<Int> = []

        if let dynamicText {
            for (layerID, layerSource) in dynamicText.layerSources {
                textures[layerID] = layerSource.texture
                layerSourcePublications[layerID] = layerSource
            }
        }
        // System media remains a separate provider. Authored material slots may
        // consume it, but it must never overwrite a layer-source publication.
        _ = mediaThumbnail
        _ = mediaBindings
        for (layerID, source) in videoSources {
            guard let frame = source.currentFrame(for: timing) else {
                pendingLayerSourceIDs.insert(layerID)
                continue
            }
            textures[layerID] = frame.texture
            if let layerSource = SceneLayerSourcePublication(
                layerID: layerID,
                publication: frame.publication
            ) {
                layerSourcePublications[layerID] = layerSource
            } else {
                publications[layerID] = frame.publication
            }
        }
        return base.snapshot(
            textures: textures,
            explicitLayerSources: publications,
            layerSourcePublications: layerSourcePublications,
            pendingLayerSourceIDs: pendingLayerSourceIDs
        )
    }
}
