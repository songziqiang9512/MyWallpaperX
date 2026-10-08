import CoreGraphics
import Metal

// Real frame registry and base-source selection, with prepared authored pixels.
func checkSolidInstanceProviderFallback(
    device: MTLDevice,
    absent: SceneMediaThumbnailTextureStore.Snapshot,
    pending: SceneMediaThumbnailTextureStore.Snapshot,
    ready: SceneMediaThumbnailTextureStore.Snapshot,
    cleared: SceneMediaThumbnailTextureStore.Snapshot
) -> [String: Bool] {
    let fallbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    fallbackDescriptor.usage = .shaderRead
    let fallbackTexture = device.makeTexture(descriptor: fallbackDescriptor)!
    fallbackTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
        withBytes: [UInt8(10),20,30,255], bytesPerRow: 4)
    let fixtureGeneration = SceneTextureResourceGeneration.file(byteCount:4, modifiedAtBits:1,
        revision:.init(fileSystemID:1,fileID:2,statusChangedAtSeconds:3,statusChangedAtNanoseconds:4))
    // A solid's procedural white carrier is deliberately the wrong fallback here.
    // The real selector must choose the prepared authored asset atom instead.
    let solidWhite = device.makeTexture(descriptor: fallbackDescriptor)!
    solidWhite.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
        withBytes: [UInt8(255), 255, 255, 255], bytesPerRow: 4)
    let fallbackAsset = SceneAssetTextureIdentity(virtualPath: "music", purpose: .premultipliedColor)!
    let assetCandidate = SceneTextureCandidate(texture: fallbackTexture,
        identity: .file(path: "/fixture/music.tex"), generation: fixtureGeneration,
        purpose: .premultipliedColor, content: .color(.resolved(.opaque)),
        physicalSize: .init(width: 1, height: 1), mappedSize: .init(width: 1, height: 1),
        uvTransform: .identity, sampling: .linearClamp)
    let assetPublication = SceneTextureProviderPublication(requestIdentity: .asset(fallbackAsset),
        candidate: assetCandidate, contentGeneration: 1)
    func solidAssetSelection(
        system: [SceneSystemProviderTextureIdentity: SceneTextureProviderState],
        asset: SceneTextureProviderState?,
        bare: Bool = false
    ) -> SceneBaseMaterialTextureSelection {
        let registry = SceneFrameTextureRegistry()
        registry.beginFrame(frameIndex: 1, layerSources: [:],
            assetStates: asset.map { [fallbackAsset: $0] } ?? [:], systemProviderStates: system)
        if bare { registry.set(.ready(fallbackTexture), for: .asset(fallbackAsset)) }
        return SceneMetalRenderer(baseMaterialProviderBindings: .init(baseMaterialBindings: [1001:
            .init(layerID: 1001, source: .layerInstance, slotIndex: 0, fallbackAsset: fallbackAsset)]),
            textureRegistry: registry).baseMaterialTextureSelection(
                for: .init(id: 1001, contentKind: "solid"),
                imageTextures: .init(textures: [1001: solidWhite], candidates: [:]))
    }
    let solidAbsent = solidAssetSelection(system: absent.providerStates, asset: .ready(assetPublication))
    let solidPending = solidAssetSelection(system: pending.providerStates, asset: .ready(assetPublication))
    let solidReady = solidAssetSelection(system: ready.providerStates, asset: .ready(assetPublication))
    let solidClear = solidAssetSelection(system: cleared.providerStates, asset: .ready(assetPublication))
    var solidAssetChecks: [String: Bool] = [
        "absentUsesAuthoredPixels": pixel(solidAbsent.source?.texture) == [10,20,30,255],
        "pendingUsesAuthoredPixels": pixel(solidPending.source?.texture) == [10,20,30,255],
        "readyUsesCurrentPixels": pixel(solidReady.source?.texture) == [255,0,0,255],
        "readyUsesExactCurrent": solidReady.source?.texture === ready.current?.texture
            && solidReady.source?.usesSystemProvider == true,
        "clearRestoresExactAuthored": solidClear.source?.texture === fallbackTexture
            && pixel(solidClear.source?.texture) == [10,20,30,255]
            && solidClear.source?.candidate?.identity == assetCandidate.identity
            && solidClear.source?.usesAuthoredLayerColor == true
            && solidClear.source?.usesSystemProvider == false,
    ]
    for (name,state) in [("absent",SceneTextureProviderState.absent),("pending",.pending),("unavailable",.unavailable)] {
        let selected = solidAssetSelection(system: cleared.providerStates, asset: state)
        solidAssetChecks["unsafeFallback-"+name] = selected.source == nil
            && selected.rejectedProviderReason != nil
    }
    let missingAsset = solidAssetSelection(system: cleared.providerStates, asset: nil)
    let bareAsset = solidAssetSelection(system: cleared.providerStates, asset: .ready(assetPublication), bare: true)
    solidAssetChecks["missingAssetRejectsWhite"] = missingAsset.source == nil
        && missingAsset.rejectedProviderReason != nil
    solidAssetChecks["bareAssetRejectsWhite"] = bareAsset.source == nil
        && bareAsset.rejectedProviderReason != nil
    for (name,purpose,content,uv) in [
        ("purpose",SceneTextureLoadPurpose.preservedChannels,SceneTextureContent.data,SceneTextureUVTransform.identity),
        ("UV",.premultipliedColor,.color(.resolved(.opaque)),.init(origin:.zero,xAxis:SIMD2(1,0),yAxis:SIMD2(0.5,1))),
    ] {
        let candidate = SceneTextureCandidate(texture: fallbackTexture, identity: assetCandidate.identity,
            generation: assetCandidate.generation, purpose: purpose, content: content,
            physicalSize: assetCandidate.physicalSize, mappedSize: assetCandidate.mappedSize,
            uvTransform: uv, sampling: .linearClamp)
        let publication = SceneTextureProviderPublication(requestIdentity: .asset(fallbackAsset),
            candidate: candidate, contentGeneration: 1)
        let selected = solidAssetSelection(system: cleared.providerStates, asset: .ready(publication))
        solidAssetChecks["unsafeFallback-"+name] = selected.source == nil
            && selected.rejectedProviderReason != nil
    }
    let providerAsAsset = SceneTextureProviderPublication(requestIdentity: .asset(fallbackAsset),
        candidate: ready.current!.candidate, contentGeneration: ready.current!.contentGeneration)
    let wrongLifecycle = solidAssetSelection(system: cleared.providerStates, asset: .ready(providerAsAsset))
    solidAssetChecks["providerCannotAliasAsset"] = wrongLifecycle.source == nil
        && wrongLifecycle.rejectedProviderReason != nil
    return solidAssetChecks
}
