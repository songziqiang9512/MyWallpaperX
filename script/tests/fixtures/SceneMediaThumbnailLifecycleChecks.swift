import Foundation
import Metal

// Exercise the real decode store, atomic current/previous publication, and
// base-source selection through ready, failure, recovery, and clear transitions.
func checkMediaThumbnailLifecycle(
    device: MTLDevice,
    firstImage a: Data,
    nextImage b: Data
) -> [String: Any] {
    let inbox = SceneMediaThumbnailInbox()
    let decodingQueue = DispatchQueue(label: "fixture.media-thumbnail")
    decodingQueue.suspend()
    let decodeCounter = DecodeCounter()
    let store = SceneMediaThumbnailTextureStore(
        device: device,
        decodingQueue: decodingQueue,
        imageDecoder: decodeCounter.decode
    )
    // Fixed RGBA PNG scanlines retain hidden RGB; ImageIO encoders may zero it.
    let c = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAYAAAC56t6BAAAAEUlEQVR4nGN4LjiVAYQZMBgAhEsJT05cFgAAAAAASUVORK5CYII=")!
    let initialEmpty = store.snapshot()

    _ = inbox.publish(a)
    store.update(from: inbox.latest())
    _ = inbox.publish(b)
    store.update(from: inbox.latest())
    _ = inbox.publish(c)
    store.update(from: inbox.latest())
    let initialPending = store.snapshot()
    decodingQueue.resume()
    let third = waitFor(store, generation: 3)
    let colorOnlyInbox = SceneMediaThumbnailInbox()
    let colorOnlyCounter = DecodeCounter()
    let colorOnlyStore = SceneMediaThumbnailTextureStore(
        device: device,
        decodingQueue: DispatchQueue(label: "fixture.media-thumbnail-color-only"),
        imageDecoder: colorOnlyCounter.decode
    )
    _ = colorOnlyInbox.publish(c)
    colorOnlyStore.update(from: colorOnlyInbox.latest())
    let colorOnlyFirst = waitFor(colorOnlyStore, generation: 1)
    let colorOnlyTexture = colorOnlyFirst.current?.texture
    _ = colorOnlyInbox.publish(c, primaryColor: SIMD3(0.2, 0.3, 0.4))
    colorOnlyStore.update(from: colorOnlyInbox.latest())
    let colorOnlySecond = colorOnlyStore.snapshot()
    let colorSystemIdentity = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.currentIdentity,
        purpose: .premultipliedColor
    )
    let preservedSystemIdentity = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.currentIdentity,
        purpose: .preservedChannels
    )
    let previousColorSystemIdentity = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.previousIdentity,
        purpose: .premultipliedColor
    )
    let previousPreservedSystemIdentity = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.previousIdentity,
        purpose: .preservedChannels
    )
    let currentMaskIdentity = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.currentIdentity, purpose: .mask)
    let previousMaskIdentity = SceneSystemProviderTextureIdentity(
        name: SceneBaseMaterialProviderBindingProgram.previousIdentity, purpose: .mask)
    let allTransitionSystemIdentities: Set<SceneSystemProviderTextureIdentity> = [
        colorSystemIdentity, preservedSystemIdentity,
        previousColorSystemIdentity, previousPreservedSystemIdentity,
        currentMaskIdentity, previousMaskIdentity,
    ]
    let baseBinding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(
        layerID: 3588, source: .layerInstance, slotIndex: 0
    )
    let readyRegistry = SceneFrameTextureRegistry()
    _ = readyRegistry.beginFrame(
        frameIndex: 1,
        layerSources: [:],
        systemProviderStates: third.providerStates
    )
    let readyResolution = SceneBaseMaterialTextureResolver.resolve(
        binding: baseBinding,
        registry: readyRegistry
    )
    let readyProviderExact: Bool
    switch readyResolution {
    case let .ready(candidate):
        readyProviderExact = candidate.texture === third.current?.texture
    case .authoredFallback, .rejected:
        readyProviderExact = false
    }
    let fallbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
    )
    fallbackDescriptor.usage = [.shaderRead]
    let fallbackTexture = device.makeTexture(descriptor: fallbackDescriptor)!
    fallbackTexture.replace(
        region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
        withBytes: [UInt8(10), 20, 30, 255], bytesPerRow: 4
    )
    let propertyTexture = device.makeTexture(descriptor: fallbackDescriptor)!
    propertyTexture.replace(
        region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
        withBytes: [UInt8(201), 32, 155, 255], bytesPerRow: 4
    )
    let propertyIdentity = SceneUserPropertyTextureIdentity(
        propertyKey: "customCover", purpose: .premultipliedColor
    )!
    let propertyRequest = SceneFrameTextureIdentity.materialUserProperty(
        propertyIdentity
    )
    let propertyCandidate = SceneTextureCandidate(
        texture: propertyTexture,
        identity: .file(path: "/fixture/custom-cover.png"),
        generation: .file(
            byteCount: 4,
            modifiedAtBits: 1,
            revision: .init(
                fileSystemID: 1, fileID: 2,
                statusChangedAtSeconds: 3, statusChangedAtNanoseconds: 4
            )
        ),
        purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)),
        physicalSize: CGSize(width: 1, height: 1),
        mappedSize: CGSize(width: 1, height: 1),
        uvTransform: .identity,
        sampling: .linearClamp
    )
    let propertyPublication = SceneTextureProviderPublication(
        requestIdentity: propertyRequest,
        candidate: propertyCandidate,
        contentGeneration: 1
    )
    let propertyBinding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(
        layerID: 900, source: .materialPass, slotIndex: 0,
        provider: .userProperty(propertyIdentity)
    )
    let propertyProgram = SceneBaseMaterialProviderBindingProgram(
        baseMaterialBindings: [900: propertyBinding]
    )
    let propertyBaseSnapshot = SceneBaseImageTextureSnapshot(
        textures: [900: fallbackTexture], candidates: [:]
    )
    let propertyReadyRegistry = SceneFrameTextureRegistry()
    _ = propertyReadyRegistry.beginFrame(
        frameIndex: 1,
        layerSources: [:],
        userPropertyStates: [propertyIdentity: .ready(propertyPublication)]
    )
    let propertyReadyRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: propertyProgram,
        textureRegistry: propertyReadyRegistry
    )
    let propertyReadySource = propertyReadyRenderer.baseMaterialTextureSource(
        for: .init(id: 900, contentKind: "image"),
        imageTextures: propertyBaseSnapshot
    )
    let propertyAbsentRegistry = SceneFrameTextureRegistry()
    _ = propertyAbsentRegistry.beginFrame(
        frameIndex: 1, layerSources: [:],
        userPropertyStates: [propertyIdentity: .absent]
    )
    let propertyAbsentSource = SceneMetalRenderer(
        baseMaterialProviderBindings: propertyProgram,
        textureRegistry: propertyAbsentRegistry
    ).baseMaterialTextureSource(
        for: .init(id: 900, contentKind: "image"),
        imageTextures: propertyBaseSnapshot
    )
    let propertyUnavailableRegistry = SceneFrameTextureRegistry()
    _ = propertyUnavailableRegistry.beginFrame(
        frameIndex: 1, layerSources: [:],
        userPropertyStates: [propertyIdentity: .unavailable]
    )
    let propertyUnavailableSource = SceneMetalRenderer(
        baseMaterialProviderBindings: propertyProgram,
        textureRegistry: propertyUnavailableRegistry
    ).baseMaterialTextureSource(
        for: .init(id: 900, contentKind: "image"),
        imageTextures: propertyBaseSnapshot
    )
    let propertyIncompleteRegistry = SceneFrameTextureRegistry()
    _ = propertyIncompleteRegistry.beginFrame(frameIndex: 1, layerSources: [:])
    propertyIncompleteRegistry.set(.ready(propertyTexture), for: propertyRequest)
    let propertyIncompleteSource = SceneMetalRenderer(
        baseMaterialProviderBindings: propertyProgram,
        textureRegistry: propertyIncompleteRegistry
    ).baseMaterialTextureSource(
        for: .init(id: 900, contentKind: "image"),
        imageTextures: propertyBaseSnapshot
    )
    let propertyWrongCandidate = SceneTextureCandidate(
        texture: propertyTexture,
        identity: .provider(.mediaThumbnailCurrent),
        generation: .provider(contentGeneration: 1),
        purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)),
        physicalSize: CGSize(width: 1, height: 1),
        mappedSize: CGSize(width: 1, height: 1),
        uvTransform: .identity,
        sampling: .linearClamp
    )
    let propertyWrongPublication = SceneTextureProviderPublication(
        requestIdentity: propertyRequest,
        candidate: propertyWrongCandidate,
        contentGeneration: 1
    )
    let propertyWrongRegistry = SceneFrameTextureRegistry()
    _ = propertyWrongRegistry.beginFrame(
        frameIndex: 1, layerSources: [:],
        userPropertyStates: [propertyIdentity: .ready(propertyWrongPublication)]
    )
    let propertyWrongSource = SceneMetalRenderer(
        baseMaterialProviderBindings: propertyProgram,
        textureRegistry: propertyWrongRegistry
    ).baseMaterialTextureSource(
        for: .init(id: 900, contentKind: "image"),
        imageTextures: propertyBaseSnapshot
    )
    let baseSnapshot = SceneBaseImageTextureSnapshot(
        textures: [3588: fallbackTexture], candidates: [:]
    )
    let bindingProgram = SceneBaseMaterialProviderBindingProgram(
        baseMaterialBindings: [3588: baseBinding]
    )
    let readyRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: bindingProgram,
        textureRegistry: readyRegistry
    )
    let readyBaseSource = readyRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "solid"),
        imageTextures: baseSnapshot
    )
    let readyTintedBaseSource = readyRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "solid"),
        imageTextures: baseSnapshot,
        readyProviderUsesAuthoredLayerColor: true
    )
    let emptyBaseSnapshot = SceneBaseImageTextureSnapshot(textures: [:], candidates: [:])
    let readyWithoutFallback = readyRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "image"),
        imageTextures: emptyBaseSnapshot
    )
    let readyImageBaseSource = readyRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "image"),
        imageTextures: baseSnapshot,
        readyProviderUsesAuthoredLayerColor: true
    )
    let missingRegistry = SceneFrameTextureRegistry()
    _ = missingRegistry.beginFrame(frameIndex: 1, layerSources: [:])
    let missingRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: bindingProgram,
        textureRegistry: missingRegistry
    )
    let missingBaseSource = missingRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "solid"),
        imageTextures: baseSnapshot
    )
    let missingWithoutFallback = missingRenderer.baseMaterialTextureSelection(
        for: .init(id: 3588, contentKind: "solid"),
        imageTextures: emptyBaseSnapshot
    )
    let unavailableRegistry = SceneFrameTextureRegistry()
    _ = unavailableRegistry.beginFrame(frameIndex: 1, layerSources: [:])
    unavailableRegistry.set(.unavailable, for: .system(colorSystemIdentity))
    let unavailableRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: bindingProgram,
        textureRegistry: unavailableRegistry
    )
    let unavailableBaseSource = unavailableRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "solid"),
        imageTextures: baseSnapshot
    )
    let incompleteRegistry = SceneFrameTextureRegistry()
    _ = incompleteRegistry.beginFrame(
        frameIndex: 1,
        layerSources: [:],
        systemTextures: [colorSystemIdentity: third.current!.texture]
    )
    let incompleteRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: bindingProgram,
        textureRegistry: incompleteRegistry
    )
    let incompleteBaseSource = incompleteRenderer.baseMaterialTextureSource(
        for: .init(id: 3588, contentKind: "solid"),
        imageTextures: baseSnapshot
    )
    let layerRequest = SceneFrameTextureIdentity.layerSource(77)
    let layerPublication = third.current?.publication(for: layerRequest)
    let rapidDecodeCount = decodeCounter.value
    let duplicateAccepted = inbox.publish(c)
    let duplicateGeneration = inbox.latest().generation
    let oversizedRejected = !inbox.publish(
        Data(count: SceneMediaThumbnailInbox.maximumEncodedByteCount + 1)
    )

    decodingQueue.suspend()
    _ = inbox.publish(a)
    store.update(from: inbox.latest())
    let retainedDuringPending = store.snapshot()
    decodingQueue.resume()
    let fourth = waitFor(store, generation: 4)
    let previousBaseBinding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(
        layerID: 702, source: .materialPass, slotIndex: 0, provider: .previous
    )
    let previousReadyRegistry = SceneFrameTextureRegistry()
    _ = previousReadyRegistry.beginFrame(
        frameIndex: 4,
        layerSources: [:],
        systemProviderStates: fourth.providerStates
    )
    let previousReadyResolution = SceneBaseMaterialTextureResolver.resolve(
        binding: previousBaseBinding,
        registry: previousReadyRegistry
    )
    let previousReadyExact: Bool
    switch previousReadyResolution {
    case let .ready(candidate):
        previousReadyExact = candidate.texture === fourth.previous?.texture
            && candidate.identity == .provider(.mediaThumbnailPrevious)
    case .authoredFallback, .rejected:
        previousReadyExact = false
    }
    let previousBindingProgram = SceneBaseMaterialProviderBindingProgram(
        baseMaterialBindings: [702: previousBaseBinding]
    )
    let previousReadyRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: previousBindingProgram,
        textureRegistry: previousReadyRegistry
    )
    let previousBaseSnapshot = SceneBaseImageTextureSnapshot(
        textures: [702: fallbackTexture], candidates: [:]
    )
    let previousReadySource = previousReadyRenderer.baseMaterialTextureSource(
        for: .init(id: 702, contentKind: "image"),
        imageTextures: previousBaseSnapshot
    )
    let previousUnavailableRegistry = SceneFrameTextureRegistry()
    _ = previousUnavailableRegistry.beginFrame(frameIndex: 4, layerSources: [:])
    previousUnavailableRegistry.set(
        .unavailable,
        for: .system(previousColorSystemIdentity)
    )
    let previousUnavailableRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: previousBindingProgram,
        textureRegistry: previousUnavailableRegistry
    )
    let previousUnavailableSource = previousUnavailableRenderer
        .baseMaterialTextureSource(
            for: .init(id: 702, contentKind: "image"),
            imageTextures: previousBaseSnapshot
        )
    let previousWrongIdentityRegistry = SceneFrameTextureRegistry()
    _ = previousWrongIdentityRegistry.beginFrame(
        frameIndex: 4,
        layerSources: [:],
        systemTextures: [previousColorSystemIdentity: fourth.current!.texture],
        explicitSystemTextures: [
            previousColorSystemIdentity: fourth.current!.publication(
                for: .system(previousColorSystemIdentity)
            )
        ]
    )
    let previousWrongIdentityRenderer = SceneMetalRenderer(
        baseMaterialProviderBindings: previousBindingProgram,
        textureRegistry: previousWrongIdentityRegistry
    )
    let previousWrongIdentitySource = previousWrongIdentityRenderer
        .baseMaterialTextureSource(
            for: .init(id: 702, contentKind: "image"),
            imageTextures: previousBaseSnapshot
        )

    decodingQueue.suspend()
    _ = inbox.publish(Data([0, 1, 2, 3]))
    store.update(from: inbox.latest())
    let retainedDuringDecodeFailure = store.snapshot()
    decodingQueue.resume()
    let failed = waitFor(store, generation: 5)

    decodingQueue.suspend()
    _ = inbox.publish(b)
    store.update(from: inbox.latest())
    let retainedDuringRecovery = store.snapshot()
    decodingQueue.resume()
    let recovered = waitFor(store, generation: 6)

    inbox.clear()
    store.update(from: inbox.latest())
    let cleared = waitFor(store, generation: 7)

    let oversizedSourceInbox = SceneMediaThumbnailInbox()
    let oversizedSourceQueue = DispatchQueue(label: "fixture.media-thumbnail-oversized")
    let oversizedSourceStore = SceneMediaThumbnailTextureStore(
        device: device,
        decodingQueue: oversizedSourceQueue
    )
    _ = oversizedSourceInbox.publish(a)
    oversizedSourceStore.update(from: oversizedSourceInbox.latest())
    let beforeOversizedSource = waitFor(oversizedSourceStore, generation: 1)
    oversizedSourceQueue.suspend()
    _ = oversizedSourceInbox.publish(
        png(red: 12, green: 34, blue: 56, width: 257)
    )
    oversizedSourceStore.update(from: oversizedSourceInbox.latest())
    let pendingOversizedSource = oversizedSourceStore.snapshot()
    oversizedSourceQueue.resume()
    let oversizedSource = waitFor(oversizedSourceStore, generation: 2)

    let firstFailureInbox = SceneMediaThumbnailInbox()
    let firstFailureQueue = DispatchQueue(label: "fixture.media-thumbnail-first-failure")
    let firstFailureStore = SceneMediaThumbnailTextureStore(
        device: device,
        decodingQueue: firstFailureQueue
    )
    _ = firstFailureInbox.publish(Data([0, 1, 2, 3]))
    firstFailureStore.update(from: firstFailureInbox.latest())
    let firstFailure = waitFor(firstFailureStore, generation: 1)
    firstFailureQueue.suspend()
    _ = firstFailureInbox.publish(a)
    firstFailureStore.update(from: firstFailureInbox.latest())
    let firstRecoveryPending = firstFailureStore.snapshot()
    firstFailureQueue.resume()
    let firstRecovery = waitFor(firstFailureStore, generation: 2)

    let solidAssetChecks = checkSolidInstanceProviderFallback(device: device,
        absent: initialEmpty, pending: initialPending, ready: fourth, cleared: cleared)

    return [
        "maskPublications": checkMediaThumbnailMasks(device: device, snapshots: [
            "empty": initialEmpty, "initialPending": initialPending, "first": third,
            "replacementPending": retainedDuringPending, "rotated": fourth,
            "failed": failed, "recoveryPending": retainedDuringRecovery,
            "recovered": recovered, "clear": cleared, "firstFailure": firstFailure,
            "firstRecoveryPending": firstRecoveryPending, "firstRecovery": firstRecovery,
            "colorOnlyFirst": colorOnlyFirst, "colorOnlySecond": colorOnlySecond,
        ]),
        "solidAssetFallback": solidAssetChecks,
        "initialEmptyStatesAbsent": allTransitionSystemIdentities.allSatisfy {
            providerStateIsAbsent(initialEmpty, $0)
        },
        "initialPendingGeneration": initialPending.pendingGeneration.map(Int.init) ?? -1,
        "initialPendingExact":
            initialPending.generation == 0
            && initialPending.current == nil
            && initialPending.preservedCurrent == nil
            && initialPending.previous == nil
            && initialPending.preservedPrevious == nil
            && initialPending.pendingIdentities
                == [colorSystemIdentity, preservedSystemIdentity, currentMaskIdentity],
        "initialPendingStatesExact":
            providerStateIsPending(initialPending, colorSystemIdentity)
            && providerStateIsPending(initialPending, preservedSystemIdentity)
            && providerStateIsAbsent(initialPending, previousColorSystemIdentity)
            && providerStateIsAbsent(initialPending, previousPreservedSystemIdentity),
        "generation": third.generation,
        "currentPixel": pixel(third.current?.texture),
        "preservedCurrentPixel": pixel(third.preservedCurrent?.texture),
        "currentPublicationComplete": third.current?.isComplete == true,
        "preservedPublicationComplete": third.preservedCurrent?.isComplete == true,
        "initialPreviousUnavailable":
            third.previous == nil && third.preservedPrevious == nil,
        "firstReadyStatesExact":
            providerStateIsReady(
                third, colorSystemIdentity, matching: third.current?.texture
            )
            && providerStateIsReady(
                third,
                preservedSystemIdentity,
                matching: third.preservedCurrent?.texture
            )
            && providerStateIsAbsent(third, previousColorSystemIdentity)
            && providerStateIsAbsent(third, previousPreservedSystemIdentity),
        "currentRequestExact": third.current?.requestIdentity
            == .system(colorSystemIdentity),
        "preservedRequestExact": third.preservedCurrent?.requestIdentity
            == .system(preservedSystemIdentity),
        "purposeQualifiedSystemAtoms":
            third.systemTextures.count == 3
            && third.publications.count == 3
            && third.systemTextures[colorSystemIdentity] === third.current?.texture
            && third.systemTextures[preservedSystemIdentity]
                === third.preservedCurrent?.texture
            && third.publications[colorSystemIdentity]?.requestIdentity
                == .system(colorSystemIdentity)
            && third.publications[preservedSystemIdentity]?.requestIdentity
                == .system(preservedSystemIdentity)
            && third.current?.texture !== third.preservedCurrent?.texture,
        "baseMaterialReadyProviderExact": readyProviderExact
            && readyBaseSource?.texture === third.current?.texture
            && readyBaseSource?.candidate?.identity
                == .provider(.mediaThumbnailCurrent)
            && readyBaseSource?.usesSystemProvider == true
            && readyBaseSource?.usesAuthoredLayerColor == false
            && readyBaseSource?.rejectedProviderReason == nil,
        "baseMaterialReadyImageProviderOwnsExtent":
            readyImageBaseSource?.texture.width == 2
            && readyImageBaseSource?.texture.height == 3
            && readyWithoutFallback?.texture === third.current?.texture,
        "baseMaterialReadyPreservesDynamicTint":
            readyTintedBaseSource?.texture === third.current?.texture
            && readyTintedBaseSource?.usesSystemProvider == true
            && readyTintedBaseSource?.usesAuthoredLayerColor == true
            && readyTintedBaseSource?.rejectedProviderReason == nil,
        "baseMaterialMissingRegistryRejectsOnlyProvider":
            missingBaseSource?.texture === fallbackTexture
            && missingBaseSource?.usesSystemProvider == false
            && missingBaseSource?.usesAuthoredLayerColor == true
            && missingBaseSource?.rejectedProviderReason
                == "base-material-current-registry-missing",
        "baseMaterialMissingRegistryWithoutFallbackKeepsReason":
            missingWithoutFallback.rejectedProviderReason
                == "base-material-current-registry-missing"
            && missingWithoutFallback.source == nil,
        "baseMaterialUnavailableKeepsAuthoredFallback":
            unavailableBaseSource?.texture === fallbackTexture
            && unavailableBaseSource?.candidate == nil
            && unavailableBaseSource?.usesSystemProvider == false
            && unavailableBaseSource?.usesAuthoredLayerColor == true
            && unavailableBaseSource?.rejectedProviderReason == nil,
        "baseMaterialIncompleteRejectsOnlyProvider":
            incompleteBaseSource?.texture === fallbackTexture
            && incompleteBaseSource?.usesSystemProvider == false
            && incompleteBaseSource?.usesAuthoredLayerColor == true
            && incompleteBaseSource?.rejectedProviderReason
                == "base-material-current-publication-incomplete",
        "baseMaterialUserPropertyReadyExact":
            propertyReadySource?.texture === propertyTexture
            && propertyReadySource?.candidate?.identity
                == .file(path: "/fixture/custom-cover.png")
            && propertyReadySource?.usesSystemProvider == false
            && propertyReadySource?.usesUserPropertyProvider == true
            && propertyReadySource?.usesAuthoredLayerColor == true
            && propertyReadySource?.rejectedProviderReason == nil,
        "baseMaterialUserPropertyAbsentKeepsAuthoredFallback":
            propertyAbsentSource?.texture === fallbackTexture
            && propertyAbsentSource?.usesUserPropertyProvider == false
            && propertyAbsentSource?.rejectedProviderReason == nil,
        "baseMaterialUserPropertyUnavailableRejectsOnlyReplacement":
            propertyUnavailableSource?.texture === fallbackTexture
            && propertyUnavailableSource?.usesUserPropertyProvider == false
            && propertyUnavailableSource?.rejectedProviderReason
                == "base-material-user-property-unavailable",
        "baseMaterialUserPropertyIncompleteRejectsOnlyReplacement":
            propertyIncompleteSource?.texture === fallbackTexture
            && propertyIncompleteSource?.rejectedProviderReason
                == "base-material-user-property-publication-incomplete",
        "baseMaterialUserPropertyCannotConsumeSystemProvider":
            propertyWrongSource?.texture === fallbackTexture
            && propertyWrongSource?.rejectedProviderReason
                == "base-material-user-property-publication-invalid",
        "systemAndLayerRequestsAreDistinctAtoms":
            layerPublication?.requestIdentity == layerRequest
            && layerPublication?.requestIdentity != third.current?.requestIdentity
            && layerPublication?.texture === third.current?.texture
            && layerPublication?.contentGeneration == third.current?.contentGeneration,
        "currentPublicationPremultiplied":
            third.current?.candidate.purpose == .premultipliedColor
            && third.current?.candidate.content
                == .color(.resolved(.premultipliedAlpha))
            && third.current?.candidate.identity
                == .provider(.mediaThumbnailCurrent)
            && third.current?.candidate.generation
                == .provider(contentGeneration: third.generation),
        "preservedPublicationData":
            third.preservedCurrent?.candidate.purpose == .preservedChannels
            && third.preservedCurrent?.candidate.content == .data
            && third.preservedCurrent?.candidate.identity
                == .provider(.mediaThumbnailCurrent)
            && third.preservedCurrent?.candidate.generation
                == .provider(contentGeneration: third.generation),
        "rapidDecodeCount": rapidDecodeCount,
        "colorOnlyGeneration": colorOnlySecond.generation,
        "colorOnlyNoPending": colorOnlySecond.pendingGeneration == nil
            && colorOnlySecond.pendingIdentities.isEmpty,
        "colorOnlyRetainsTexture": colorOnlySecond.current?.texture === colorOnlyTexture
            && colorOnlySecond.preservedCurrent != nil,
        "colorOnlyDecodeCount": colorOnlyCounter.value,
        "duplicateAccepted": duplicateAccepted,
        "duplicateGenerationStable": duplicateGeneration == 3,
        "oversizedRejected": oversizedRejected,
        "pendingGeneration": retainedDuringPending.generation,
        "pendingRequestGeneration":
            retainedDuringPending.pendingGeneration.map(Int.init) ?? -1,
        "pendingIdentitiesExact": retainedDuringPending.pendingIdentities
            == allTransitionSystemIdentities,
        "pendingCurrentPixel": pixel(retainedDuringPending.current?.texture),
        "pendingPreservedPixel": pixel(retainedDuringPending.preservedCurrent?.texture),
        "pendingPreviousUnavailable":
            retainedDuringPending.previous == nil
            && retainedDuringPending.preservedPrevious == nil,
        "replacementPendingStatesExact":
            providerStateIsReady(
                retainedDuringPending,
                colorSystemIdentity,
                matching: retainedDuringPending.current?.texture
            )
            && providerStateIsReady(
                retainedDuringPending,
                preservedSystemIdentity,
                matching: retainedDuringPending.preservedCurrent?.texture
            )
            && providerStateIsPending(
                retainedDuringPending, previousColorSystemIdentity
            )
            && providerStateIsPending(
                retainedDuringPending, previousPreservedSystemIdentity
            ),
        "fourthCurrentPixel": pixel(fourth.current?.texture),
        "fourthPreservedPixel": pixel(fourth.preservedCurrent?.texture),
        "fourthPreviousPixel": pixel(fourth.previous?.texture),
        "fourthPreservedPreviousPixel": pixel(fourth.preservedPrevious?.texture),
        "fourthPreviousExact":
            fourth.previous?.requestIdentity == .system(previousColorSystemIdentity)
            && fourth.preservedPrevious?.requestIdentity
                == .system(previousPreservedSystemIdentity)
            && fourth.previous?.candidate.identity
                == .provider(.mediaThumbnailPrevious)
            && fourth.preservedPrevious?.candidate.identity
                == .provider(.mediaThumbnailPrevious)
            && fourth.previous?.candidate.generation
                == .provider(contentGeneration: fourth.generation)
            && fourth.preservedPrevious?.candidate.generation
                == .provider(contentGeneration: fourth.generation),
        "replacementReadyStatesExact": allTransitionSystemIdentities.allSatisfy {
            switch $0 {
            case colorSystemIdentity:
                providerStateIsReady(fourth, $0, matching: fourth.current?.texture)
            case preservedSystemIdentity, currentMaskIdentity:
                providerStateIsReady(
                    fourth, $0, matching: fourth.preservedCurrent?.texture
                )
            case previousColorSystemIdentity:
                providerStateIsReady(fourth, $0, matching: fourth.previous?.texture)
            default:
                providerStateIsReady(
                    fourth, $0, matching: fourth.preservedPrevious?.texture
                )
            }
        },
        "baseMaterialPreviousReadyExact":
            previousReadyExact
            && previousReadySource?.texture === fourth.previous?.texture
            && previousReadySource?.candidate?.identity
                == .provider(.mediaThumbnailPrevious)
            && previousReadySource?.usesSystemProvider == true
            && previousReadySource?.usesAuthoredLayerColor == false
            && previousReadySource?.rejectedProviderReason == nil,
        "baseMaterialPreviousUnavailableKeepsAuthoredFallback":
            previousUnavailableSource?.texture === fallbackTexture
            && previousUnavailableSource?.usesSystemProvider == false
            && previousUnavailableSource?.usesAuthoredLayerColor == true
            && previousUnavailableSource?.rejectedProviderReason == nil,
        "baseMaterialCurrentCannotMasqueradeAsPrevious":
            previousWrongIdentitySource?.texture === fallbackTexture
            && previousWrongIdentitySource?.usesSystemProvider == false
            && previousWrongIdentitySource?.usesAuthoredLayerColor == true
            && previousWrongIdentitySource?.rejectedProviderReason
                == "base-material-previous-publication-incomplete",
        "failurePendingGeneration": retainedDuringDecodeFailure.generation,
        "failurePendingCurrentPixel": pixel(retainedDuringDecodeFailure.current?.texture),
        "failurePendingPreservedPixel": pixel(
            retainedDuringDecodeFailure.preservedCurrent?.texture
        ),
        "failurePendingPreviousPixel": pixel(
            retainedDuringDecodeFailure.previous?.texture
        ),
        "failurePendingPreservedPreviousPixel": pixel(
            retainedDuringDecodeFailure.preservedPrevious?.texture
        ),
        "failedGeneration": failed.generation,
        "failedCurrent": failed.current == nil,
        "failedPreserved": failed.preservedCurrent == nil,
        "failedPrevious": failed.previous == nil,
        "failedPreservedPrevious": failed.preservedPrevious == nil,
        "decodeFailureStatesUnavailable": allTransitionSystemIdentities.allSatisfy {
            providerStateIsUnavailable(failed, $0)
        },
        "recoveryPendingGeneration":
            retainedDuringRecovery.pendingGeneration.map(Int.init) ?? -1,
        "recoveryPendingExact":
            retainedDuringRecovery.generation == 5
            && retainedDuringRecovery.current == nil
            && retainedDuringRecovery.preservedCurrent == nil
            && retainedDuringRecovery.previous == nil
            && retainedDuringRecovery.preservedPrevious == nil
            && retainedDuringRecovery.pendingIdentities
                == allTransitionSystemIdentities,
        "recoveryPendingStatesExact": allTransitionSystemIdentities.allSatisfy {
            providerStateIsPending(retainedDuringRecovery, $0)
        },
        "recoveredCurrentPixel": pixel(recovered.current?.texture),
        "recoveredPreservedPixel": pixel(recovered.preservedCurrent?.texture),
        "recoveredPreviousPixel": pixel(recovered.previous?.texture),
        "recoveredPreservedPreviousPixel": pixel(
            recovered.preservedPrevious?.texture
        ),
        "recoveredStatesExact": allTransitionSystemIdentities.allSatisfy {
            switch $0 {
            case colorSystemIdentity:
                providerStateIsReady(recovered, $0, matching: recovered.current?.texture)
            case preservedSystemIdentity, currentMaskIdentity:
                providerStateIsReady(
                    recovered, $0, matching: recovered.preservedCurrent?.texture
                )
            case previousColorSystemIdentity:
                providerStateIsReady(recovered, $0, matching: recovered.previous?.texture)
            default:
                providerStateIsReady(
                    recovered, $0, matching: recovered.preservedPrevious?.texture
                )
            }
        },
        "clearedGeneration": cleared.generation,
        "clearedCurrent": cleared.current == nil,
        "clearedPreserved": cleared.preservedCurrent == nil,
        "clearedPrevious": cleared.previous == nil,
        "clearedPreservedPrevious": cleared.preservedPrevious == nil,
        "clearStatesAbsent": allTransitionSystemIdentities.allSatisfy {
            providerStateIsAbsent(cleared, $0)
        },
        "oversizedSourceColorReady": oversizedSource.current != nil,
        "oversizedSourceRetainsBothWhilePending":
            beforeOversizedSource.current != nil
            && beforeOversizedSource.preservedCurrent != nil
            && pendingOversizedSource.generation == 1
            && pendingOversizedSource.current?.texture
                === beforeOversizedSource.current?.texture
            && pendingOversizedSource.preservedCurrent?.texture
                === beforeOversizedSource.preservedCurrent?.texture,
        "oversizedSourcePreservedReady":
            oversizedSource.generation == 2
            && oversizedSource.pendingGeneration == nil
            && oversizedSource.pendingIdentities.isEmpty
            && oversizedSource.preservedCurrent != nil
            && oversizedSource.preservedCurrent?.texture.width == 256
            && oversizedSource.preservedCurrent?.texture.height == 1
            && pixel(oversizedSource.preservedCurrent?.texture)
                == [12, 34, 56, 255]
            && oversizedSource.systemTextures[colorSystemIdentity] != nil
            && oversizedSource.systemTextures[preservedSystemIdentity]
                === oversizedSource.preservedCurrent?.texture
            && oversizedSource.publications[preservedSystemIdentity]?.isComplete == true,
        "partialPurposeStatesExact":
            providerStateIsReady(
                oversizedSource,
                colorSystemIdentity,
                matching: oversizedSource.current?.texture
            )
            && providerStateIsReady(
                oversizedSource,
                preservedSystemIdentity,
                matching: oversizedSource.preservedCurrent?.texture
            )
            && providerStateIsReady(
                oversizedSource,
                previousColorSystemIdentity,
                matching: oversizedSource.previous?.texture
            )
            && providerStateIsReady(
                oversizedSource,
                previousPreservedSystemIdentity,
                matching: oversizedSource.preservedPrevious?.texture
            ),
        "firstMalformedHasNoInventedPrevious":
            providerStateIsUnavailable(firstFailure, colorSystemIdentity)
            && providerStateIsUnavailable(firstFailure, preservedSystemIdentity)
            && providerStateIsAbsent(firstFailure, previousColorSystemIdentity)
            && providerStateIsAbsent(
                firstFailure, previousPreservedSystemIdentity
            ),
        "firstRecoveryPendingKeepsPreviousAbsent":
            providerStateIsPending(firstRecoveryPending, colorSystemIdentity)
            && providerStateIsPending(
                firstRecoveryPending, preservedSystemIdentity
            )
            && providerStateIsAbsent(
                firstRecoveryPending, previousColorSystemIdentity
            )
            && providerStateIsAbsent(
                firstRecoveryPending, previousPreservedSystemIdentity
            ),
        "firstRecoveryKeepsPreviousAbsent":
            providerStateIsReady(
                firstRecovery,
                colorSystemIdentity,
                matching: firstRecovery.current?.texture
            )
            && providerStateIsReady(
                firstRecovery,
                preservedSystemIdentity,
                matching: firstRecovery.preservedCurrent?.texture
            )
            && providerStateIsAbsent(firstRecovery, previousColorSystemIdentity)
            && providerStateIsAbsent(
                firstRecovery, previousPreservedSystemIdentity
            ),
        "oversizedSourceRotatesPreviousAtomically":
            oversizedSource.previous != nil
            && oversizedSource.preservedPrevious != nil
            && pixel(oversizedSource.previous?.texture) == [255, 0, 0, 255]
            && pixel(oversizedSource.preservedPrevious?.texture)
                == [255, 0, 0, 255]
            && oversizedSource.publications[previousColorSystemIdentity]?
                .candidate.identity == .provider(.mediaThumbnailPrevious)
            && oversizedSource.publications[previousPreservedSystemIdentity]?
                .candidate.identity == .provider(.mediaThumbnailPrevious)
            && oversizedSource.previous?.contentGeneration
                == oversizedSource.generation
            && oversizedSource.preservedPrevious?.contentGeneration
                == oversizedSource.generation,
    ]
}
