import Metal

enum SceneFrameLayerTextureAssembly {
    static func make(
        base: SceneBaseImageTextureStore,
        dynamicText: SceneDynamicTextTextureStore.Snapshot?,
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot? = nil,
        mediaBindings: SceneMediaThumbnailBindingProgram = .empty,
        videoSources: [Int: SceneVideoTextureSource],
        timing: SceneFrameTiming
    ) -> SceneBaseImageTextureSnapshot {
        var textures = base.textures
        var publications: [Int: SceneTextureProviderPublication] = [:]

        if let dynamicText {
            for (layerID, publication) in dynamicText.publications {
                textures[layerID] = publication.texture
                publications[layerID] = publication
            }
        }
        // System media remains a separate provider. Authored material slots may
        // consume it, but it must never overwrite a layer-source publication.
        _ = mediaThumbnail
        _ = mediaBindings
        for (layerID, source) in videoSources {
            guard let frame = source.currentFrame(for: timing) else { continue }
            textures[layerID] = frame.texture
            publications[layerID] = frame.publication
        }
        return base.snapshot(
            textures: textures,
            explicitLayerSources: publications
        )
    }
}
