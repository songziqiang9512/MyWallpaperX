import Metal

enum SceneFrameLayerTextureAssembly {
    static func make(
        base: SceneBaseImageTextureStore,
        dynamicImage: SceneDynamicImageTextureProviderSnapshot? = nil,
        dynamicText: SceneDynamicTextTextureStore.Snapshot?,
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot? = nil,
        mediaBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        videoSources: [Int: SceneVideoTextureSource],
        retiredLayerIDs: Set<Int> = [],
        timing: SceneFrameTiming,
        collectsInitialVideoReadiness: Bool = false
    ) -> SceneBaseImageTextureSnapshot {
        var textures = base.textures
        var publications: [Int: SceneTextureProviderPublication] = [:]
        var layerSourcePublications: [Int: SceneLayerSourcePublication] = [:]
        var pendingLayerSourceIDs: Set<Int> = []
        var initialVideoReadiness: [Int: SceneOrdinaryVideoFrameReadiness]? = collectsInitialVideoReadiness
            ? Dictionary(uniqueKeysWithValues: base.unavailableOrdinaryVideoLayerIDs.subtracting(retiredLayerIDs).map { ($0, .unavailable) })
            : nil

        if let dynamicImage {
            for (layerID, layerSource) in dynamicImage.layerSources {
                textures[layerID] = layerSource.texture
                layerSourcePublications[layerID] = layerSource
            }
            pendingLayerSourceIDs.formUnion(
                dynamicImage.pendingLayerSourceIDs
            )
            for layerID in dynamicImage.videoLayerRenderSizesWH.keys where videoSources[layerID] == nil {
                pendingLayerSourceIDs.insert(layerID)
                initialVideoReadiness?[layerID] = .unavailable
            }
        }

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
        for (layerID, source) in videoSources where !retiredLayerIDs.contains(layerID) {
            let preparedFrame = source.prepareFrame(for: timing)
            if collectsInitialVideoReadiness {
                initialVideoReadiness?[layerID] = source.initialFrameReadiness(preparedFrame: preparedFrame)
            }
            guard let frame = preparedFrame,
                  let publication = frame.layerPublication(for: layerID) else {
                pendingLayerSourceIDs.insert(layerID)
                continue
            }
            textures[layerID] = frame.texture
            if let layerSource = SceneLayerSourcePublication(
                layerID: layerID,
                publication: publication,
                renderSizeWH: dynamicImage?.videoLayerRenderSizesWH[layerID]
            ) {
                layerSourcePublications[layerID] = layerSource
            } else {
                publications[layerID] = publication
            }
        }
        return base.snapshot(
            textures: textures,
            explicitLayerSources: publications,
            layerSourcePublications: layerSourcePublications,
            pendingLayerSourceIDs: pendingLayerSourceIDs,
            initialVideoReadiness: initialVideoReadiness
        )
    }
}

/// Both typed material consumers and the legacy key lookup read the same atom.
/// A prepared video file alone cannot satisfy a surface's first-frame gate.
enum SceneFrameUserPropertyTextureAssembly {
    struct Snapshot {
        let textures: [String: MTLTexture]
        let states: [SceneUserPropertyTextureIdentity: SceneTextureProviderState]
    }

    static func make(
        prepared: SceneUserPropertyTextureLoadResult,
        videoSources: [SceneUserPropertyTextureIdentity: SceneVideoTextureSource],
        timing: SceneFrameTiming
    ) -> Snapshot? {
        var textures = prepared.textures
        var states = prepared.providerStates
        for declaration in prepared.videoDeclarations.values {
            let identity = declaration.identity
            guard let frame = videoSources[identity]?.prepareFrame(for: timing),
                  let publication = frame.userPropertyPublication(for: identity),
                  publication.isComplete, publication.generationIsCurrent else { return nil }
            states[identity] = .ready(publication)
            textures[identity.propertyKey] = publication.texture
        }
        return Snapshot(textures: textures, states: states)
    }
}
