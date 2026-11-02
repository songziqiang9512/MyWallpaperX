
extension SceneFrameTextureRegistry {
    @discardableResult
    func beginFrame(
        layerSources: [Int: MTLTexture],
        explicitLayerSources: [Int: SceneTextureProviderPublication] = [:],
        assetStates: [SceneAssetTextureIdentity: SceneTextureProviderState] = [:],
        userPropertyTextures: [String: MTLTexture] = [:],
        userPropertyStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:],
        systemTextures: [SceneSystemProviderTextureIdentity: MTLTexture] = [:],
        explicitSystemTextures: [
            SceneSystemProviderTextureIdentity: SceneTextureProviderPublication
        ] = [:]
    ) -> UInt64 {
        beginFrame(
            frameIndex: frameEpoch + 1,
            layerSources: layerSources,
            explicitLayerSources: explicitLayerSources,
            assetStates: assetStates,
            userPropertyTextures: userPropertyTextures,
            userPropertyStates: userPropertyStates,
            systemTextures: systemTextures,
            explicitSystemTextures: explicitSystemTextures
        )
    }

    func testPublishPersistent(
        _ texture: MTLTexture,
        for identity: SceneFrameTextureIdentity
    ) {
        publishPersistent(texture, for: identity)
    }
}
