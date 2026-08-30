#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RENDERER = SCENE / "Rendering/SceneMetalRenderer.swift"
SOURCES = [
    SCENE / "Runtime/SceneMediaThumbnailInbox.swift",
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE / "Resources/SceneTextureSampling.swift",
    SCENE / "Resources/SceneTextureUVTransform.swift",
    SCENE / "Resources/SceneTextureCandidate.swift",
    SCENE / "Resources/SceneNamedTextureReference.swift",
    SCENE / "Resources/SceneTextureSlotBinding.swift",
    SCENE / "Resources/SceneTextureProviderPublication.swift",
    SCENE / "Resources/SceneFrameTextureRegistry.swift",
    SCENE / "Rendering/SceneBaseImageTextureCandidateSupport.swift",
    SCENE / "Rendering/SceneBaseMaterialTextureResolver.swift",
    SCENE / "Resources/SceneImageTextureUploader.swift",
    SCENE / "Resources/SceneMediaThumbnailTextureStore.swift",
]

HARNESS = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct SceneMediaThumbnailBindingProgram {
    struct BaseMaterialBinding: Hashable {
        enum Source: Hashable { case layerInstance, materialPass }
        let layerID: Int
        let source: Source
        let slotIndex: Int
        var providerIdentity: SceneSystemProviderTextureIdentity {
            .init(name: SceneMediaThumbnailBindingProgram.currentIdentity,
                  purpose: .premultipliedColor)
        }
    }
    static let currentIdentity = "$mediaThumbnail"
    static let previousIdentity = "$mediaPreviousThumbnail"
    let currentBaseMaterialBindings: [Int: BaseMaterialBinding]
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        var isImageRenderable: Bool {
            contentKind == "image" || contentKind == "solid"
        }
    }
}

struct SceneBaseImageTextureSnapshot {
    let textures: [Int: MTLTexture]
    let candidates: [Int: SceneTextureCandidate]

    subscript(layerID: Int) -> MTLTexture? { textures[layerID] }

    func candidate(for layerID: Int, matching texture: MTLTexture) -> SceneTextureCandidate? {
        guard let candidate = candidates[layerID], candidate.texture === texture else {
            return nil
        }
        return candidate
    }
}

struct SceneMetalRenderer {
    let mediaThumbnailBindings: SceneMediaThumbnailBindingProgram
    let textureRegistry: SceneFrameTextureRegistry
}

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

func png(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    alpha: UInt8 = 255,
    width: Int = 1,
    height: Int = 1
) -> Data {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for _ in 0 ..< width * height {
        bytes.append(contentsOf: [red, green, blue, alpha])
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

func pixel(_ texture: MTLTexture?) -> [UInt8] {
    guard let texture else { return [] }
    var bytes = [UInt8](repeating: 0, count: 4)
    texture.getBytes(
        &bytes,
        bytesPerRow: 4,
        from: MTLRegionMake2D(0, 0, 1, 1),
        mipmapLevel: 0
    )
    return bytes
}

func waitFor(_ store: SceneMediaThumbnailTextureStore, generation: UInt64) -> SceneMediaThumbnailTextureStore.Snapshot {
    for _ in 0..<200 {
        let snapshot = store.snapshot()
        if snapshot.generation == generation { return snapshot }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return store.snapshot()
}

final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func decode(_ data: Data) -> CGImage? {
        lock.lock()
        count += 1
        lock.unlock()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal unavailable")
}
let inbox = SceneMediaThumbnailInbox()
let decodingQueue = DispatchQueue(label: "fixture.media-thumbnail")
decodingQueue.suspend()
let decodeCounter = DecodeCounter()
let store = SceneMediaThumbnailTextureStore(
    device: device,
    decodingQueue: decodingQueue,
    imageDecoder: decodeCounter.decode
)
let a = png(red: 255, green: 0, blue: 0)
let b = png(red: 0, green: 255, blue: 0)
let c = png(red: 231, green: 17, blue: 149, alpha: 0, width: 2, height: 3)

_ = inbox.publish(a)
store.update(from: inbox.latest())
_ = inbox.publish(b)
store.update(from: inbox.latest())
_ = inbox.publish(c)
store.update(from: inbox.latest())
let initialPending = store.snapshot()
decodingQueue.resume()
let third = waitFor(store, generation: 3)
let colorSystemIdentity = SceneSystemProviderTextureIdentity(
    name: SceneMediaThumbnailBindingProgram.currentIdentity,
    purpose: .premultipliedColor
)
let preservedSystemIdentity = SceneSystemProviderTextureIdentity(
    name: SceneMediaThumbnailBindingProgram.currentIdentity,
    purpose: .preservedChannels
)
let previousColorSystemIdentity = SceneSystemProviderTextureIdentity(
    name: SceneMediaThumbnailBindingProgram.previousIdentity,
    purpose: .premultipliedColor
)
let previousPreservedSystemIdentity = SceneSystemProviderTextureIdentity(
    name: SceneMediaThumbnailBindingProgram.previousIdentity,
    purpose: .preservedChannels
)
let allTransitionSystemIdentities: Set<SceneSystemProviderTextureIdentity> = [
    colorSystemIdentity, preservedSystemIdentity,
    previousColorSystemIdentity, previousPreservedSystemIdentity,
]
let baseBinding = SceneMediaThumbnailBindingProgram.BaseMaterialBinding(
    layerID: 3588, source: .layerInstance, slotIndex: 0
)
let readyRegistry = SceneFrameTextureRegistry()
_ = readyRegistry.beginFrame(
    frameIndex: 1,
    layerSources: [:],
    systemTextures: third.systemTextures,
    explicitSystemTextures: third.publications
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
let baseSnapshot = SceneBaseImageTextureSnapshot(
    textures: [3588: fallbackTexture], candidates: [:]
)
let bindingProgram = SceneMediaThumbnailBindingProgram(
    currentBaseMaterialBindings: [3588: baseBinding]
)
let readyRenderer = SceneMetalRenderer(
    mediaThumbnailBindings: bindingProgram,
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
    mediaThumbnailBindings: bindingProgram,
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
    mediaThumbnailBindings: bindingProgram,
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
    mediaThumbnailBindings: bindingProgram,
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

let eventInbox = SceneMediaThumbnailInbox()
let primaryColor = SIMD3(0.125, 0.5, 1.0)
let secondaryColor = SIMD3(0.75, 0.25, 0.5)
let tertiaryColor = SIMD3(0.2, 0.4, 0.6)
let textColor = SIMD3(0.9, 0.8, 0.7)
let highContrastColor = SIMD3(1.0, 1.0, 1.0)
let replacementColor = SIMD3(0.05, 0.15, 0.25)
let eventInitial = eventInbox.latest()
let propertiesAccepted = eventInbox.publishMediaProperties(
    title: "Fixture Song",
    artist: "Fixture Artist"
)
let afterProperties = eventInbox.latest()
let duplicatePropertiesAccepted = eventInbox.publishMediaProperties(
    title: "Fixture Song",
    artist: "Fixture Artist"
)
let afterDuplicateProperties = eventInbox.latest()
let titleChangeAccepted = eventInbox.publishMediaProperties(
    title: "Replacement Song",
    artist: "Fixture Artist"
)
let afterTitleChange = eventInbox.latest()
let artistChangeAccepted = eventInbox.publishMediaProperties(
    title: "Replacement Song",
    artist: "Replacement Artist"
)
let afterArtistChange = eventInbox.latest()
let controlPropertyRejected = !eventInbox.publishMediaProperties(
    title: "Line\nBreak",
    artist: "Replacement Artist"
)
let oversizedPropertyRejected = !eventInbox.publishMediaProperties(
    title: String(repeating: "界", count: 1_366),
    artist: "Replacement Artist"
)
let afterInvalidProperties = eventInbox.latest()
let imageColorAccepted = eventInbox.publish(
    a,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
    tertiaryColor: tertiaryColor,
    textColor: textColor,
    highContrastColor: highContrastColor
)
let afterImageColor = eventInbox.latest()
let duplicateImageColorAccepted = eventInbox.publish(
    a,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
    tertiaryColor: tertiaryColor,
    textColor: textColor,
    highContrastColor: highContrastColor
)
let afterDuplicateImageColor = eventInbox.latest()
let replacementColorAccepted = eventInbox.publish(
    a,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
    tertiaryColor: replacementColor,
    textColor: textColor,
    highContrastColor: highContrastColor
)
let afterReplacementColor = eventInbox.latest()
let nanColorRejected = !eventInbox.publish(
    b,
    primaryColor: SIMD3(.nan, 0.25, 0.5)
)
let negativeColorRejected = !eventInbox.publish(
    b,
    textColor: SIMD3(-0.01, 0.25, 0.5)
)
let oversizedColorRejected = !eventInbox.publish(
    b,
    highContrastColor: SIMD3(0.75, 1.01, 0.5)
)
let emptyImageWithColorRejected = !eventInbox.publish(
    Data(),
    tertiaryColor: replacementColor
)
let afterInvalidColors = eventInbox.latest()
let playbackAccepted = eventInbox.publishPlaybackState(1)
let afterPlayback = eventInbox.latest()
let duplicatePlaybackAccepted = eventInbox.publishPlaybackState(1)
let afterDuplicatePlayback = eventInbox.latest()
let pausedAccepted = eventInbox.publishPlaybackState(2)
let afterPaused = eventInbox.latest()
let negativePlaybackRejected = !eventInbox.publishPlaybackState(-1)
let oversizedPlaybackRejected = !eventInbox.publishPlaybackState(3)
let afterInvalidPlayback = eventInbox.latest()
let nextImageAccepted = eventInbox.publish(
    b,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
    tertiaryColor: tertiaryColor,
    textColor: textColor,
    highContrastColor: highContrastColor
)
let afterNextImage = eventInbox.latest()
eventInbox.clear()
let afterEventClear = eventInbox.latest()
eventInbox.clear()
let afterDuplicateEventClear = eventInbox.latest()
let emptyPropertiesAccepted = eventInbox.publishMediaProperties(
    title: "",
    artist: ""
)
let afterEmptyProperties = eventInbox.latest()
let duplicateEmptyPropertiesAccepted = eventInbox.publishMediaProperties(
    title: "",
    artist: ""
)
let afterDuplicateEmptyProperties = eventInbox.latest()

let result: [String: Any] = [
    "initialPendingGeneration": initialPending.pendingGeneration.map(Int.init) ?? -1,
    "initialPendingExact":
        initialPending.generation == 0
        && initialPending.current == nil
        && initialPending.preservedCurrent == nil
        && initialPending.previous == nil
        && initialPending.preservedPrevious == nil
        && initialPending.pendingIdentities
            == [colorSystemIdentity, preservedSystemIdentity],
    "generation": third.generation,
    "currentPixel": pixel(third.current?.texture),
    "preservedCurrentPixel": pixel(third.preservedCurrent?.texture),
    "currentPublicationComplete": third.current?.isComplete == true,
    "preservedPublicationComplete": third.preservedCurrent?.isComplete == true,
    "initialPreviousUnavailable":
        third.previous == nil && third.preservedPrevious == nil,
    "currentRequestExact": third.current?.requestIdentity
        == .system(colorSystemIdentity),
    "preservedRequestExact": third.preservedCurrent?.requestIdentity
        == .system(preservedSystemIdentity),
    "purposeQualifiedSystemAtoms":
        third.systemTextures.count == 2
        && third.publications.count == 2
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
    "recoveredCurrentPixel": pixel(recovered.current?.texture),
    "recoveredPreservedPixel": pixel(recovered.preservedCurrent?.texture),
    "recoveredPreviousPixel": pixel(recovered.previous?.texture),
    "recoveredPreservedPreviousPixel": pixel(
        recovered.preservedPrevious?.texture
    ),
    "clearedGeneration": cleared.generation,
    "clearedCurrent": cleared.current == nil,
    "clearedPreserved": cleared.preservedCurrent == nil,
    "clearedPrevious": cleared.previous == nil,
    "clearedPreservedPrevious": cleared.preservedPrevious == nil,
    "oversizedSourceColorReady": oversizedSource.current != nil,
    "oversizedSourceRetainsBothWhilePending":
        beforeOversizedSource.current != nil
        && beforeOversizedSource.preservedCurrent != nil
        && pendingOversizedSource.generation == 1
        && pendingOversizedSource.current?.texture
            === beforeOversizedSource.current?.texture
        && pendingOversizedSource.preservedCurrent?.texture
            === beforeOversizedSource.preservedCurrent?.texture,
    "oversizedSourcePreservedUnavailable":
        oversizedSource.generation == 2
        && oversizedSource.pendingGeneration == nil
        && oversizedSource.pendingIdentities.isEmpty
        && oversizedSource.preservedCurrent == nil
        && oversizedSource.systemTextures[colorSystemIdentity] != nil
        && oversizedSource.systemTextures[preservedSystemIdentity] == nil
        && oversizedSource.publications[preservedSystemIdentity] == nil,
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
    "eventInitialEmpty": eventInitial == .empty,
    "propertiesAccepted": propertiesAccepted,
    "propertiesGeneration": afterProperties.propertiesGeneration,
    "propertiesPreserveOtherGenerations":
        afterProperties.generation == 0
        && afterProperties.playbackGeneration == 0,
    "propertiesExact":
        afterProperties.properties?.title == "Fixture Song"
        && afterProperties.properties?.artist == "Fixture Artist",
    "duplicatePropertiesAccepted": duplicatePropertiesAccepted,
    "duplicatePropertiesStable": afterDuplicateProperties == afterProperties,
    "titleChangeAccepted": titleChangeAccepted,
    "titleChangeAtomic":
        afterTitleChange.propertiesGeneration == 2
        && afterTitleChange.properties?.title == "Replacement Song"
        && afterTitleChange.properties?.artist == "Fixture Artist",
    "artistChangeAccepted": artistChangeAccepted,
    "artistChangeAtomic":
        afterArtistChange.propertiesGeneration == 3
        && afterArtistChange.properties?.title == "Replacement Song"
        && afterArtistChange.properties?.artist == "Replacement Artist",
    "controlPropertyRejected": controlPropertyRejected,
    "oversizedPropertyRejected": oversizedPropertyRejected,
    "invalidPropertiesPreserveSnapshot": afterInvalidProperties == afterArtistChange,
    "imageColorAccepted": imageColorAccepted,
    "imageColorGeneration": afterImageColor.generation,
    "imageColorPlaybackGeneration": afterImageColor.playbackGeneration,
    "imageColorPreservesProperties":
        afterImageColor.properties == afterArtistChange.properties
        && afterImageColor.propertiesGeneration
            == afterArtistChange.propertiesGeneration,
    "imageColorExact":
        afterImageColor.primaryColor == primaryColor
        && afterImageColor.secondaryColor == secondaryColor
        && afterImageColor.tertiaryColor == tertiaryColor
        && afterImageColor.textColor == textColor
        && afterImageColor.highContrastColor == highContrastColor,
    "duplicateImageColorAccepted": duplicateImageColorAccepted,
    "duplicateImageColorGenerationStable":
        afterDuplicateImageColor.generation == afterImageColor.generation,
    "replacementColorAccepted": replacementColorAccepted,
    "replacementColorGeneration": afterReplacementColor.generation,
    "replacementColorExact":
        afterReplacementColor.primaryColor == primaryColor
        && afterReplacementColor.secondaryColor == secondaryColor
        && afterReplacementColor.tertiaryColor == replacementColor
        && afterReplacementColor.textColor == textColor
        && afterReplacementColor.highContrastColor == highContrastColor,
    "nanColorRejected": nanColorRejected,
    "negativeColorRejected": negativeColorRejected,
    "oversizedColorRejected": oversizedColorRejected,
    "emptyImageWithColorRejected": emptyImageWithColorRejected,
    "invalidColorsPreserveSnapshot": afterInvalidColors == afterReplacementColor,
    "playbackAccepted": playbackAccepted,
    "playbackState": afterPlayback.playbackState ?? -1,
    "playbackGeneration": afterPlayback.playbackGeneration,
    "playbackPreservesImageGeneration":
        afterPlayback.generation == afterReplacementColor.generation,
    "duplicatePlaybackAccepted": duplicatePlaybackAccepted,
    "duplicatePlaybackGenerationStable":
        afterDuplicatePlayback.playbackGeneration == afterPlayback.playbackGeneration,
    "pausedAccepted": pausedAccepted,
    "pausedState": afterPaused.playbackState ?? -1,
    "pausedGeneration": afterPaused.playbackGeneration,
    "negativePlaybackRejected": negativePlaybackRejected,
    "oversizedPlaybackRejected": oversizedPlaybackRejected,
    "invalidPlaybackPreservesSnapshot": afterInvalidPlayback == afterPaused,
    "nextImageAccepted": nextImageAccepted,
    "nextImageGeneration": afterNextImage.generation,
    "nextImagePreservesPlaybackGeneration":
        afterNextImage.playbackGeneration == afterPaused.playbackGeneration,
    "eventClearGeneration": afterEventClear.generation,
    "eventClearColorIsZero":
        afterEventClear.primaryColor == .zero
        && afterEventClear.secondaryColor == .zero
        && afterEventClear.tertiaryColor == .zero
        && afterEventClear.textColor == .zero
        && afterEventClear.highContrastColor == .zero,
    "eventClearPreservesPlayback":
        afterEventClear.playbackState == afterPaused.playbackState
        && afterEventClear.playbackGeneration == afterPaused.playbackGeneration,
    "eventClearPreservesProperties":
        afterEventClear.properties == afterArtistChange.properties
        && afterEventClear.propertiesGeneration
            == afterArtistChange.propertiesGeneration,
    "duplicateEventClearStable": afterDuplicateEventClear == afterEventClear,
    "emptyPropertiesAccepted": emptyPropertiesAccepted,
    "emptyPropertiesClearOldValues":
        afterEmptyProperties.properties?.title == ""
        && afterEmptyProperties.properties?.artist == "",
    "emptyPropertiesGeneration": afterEmptyProperties.propertiesGeneration,
    "emptyPropertiesPreserveOtherGenerations":
        afterEmptyProperties.generation == afterEventClear.generation
        && afterEmptyProperties.playbackGeneration
            == afterEventClear.playbackGeneration,
    "duplicateEmptyPropertiesAccepted": duplicateEmptyPropertiesAccepted,
    "duplicateEmptyPropertiesStable":
        afterDuplicateEmptyProperties == afterEmptyProperties,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class SceneMediaThumbnailProviderTests(unittest.TestCase):
    def test_base_material_route_reports_ready_and_rejected_provider(self) -> None:
        renderer = RENDERER.read_text(encoding="utf-8")
        dependency = (
            SCENE / "RenderGraph/LayerDependencies/SceneDependencyFrameRuntime.swift"
        ).read_text(encoding="utf-8")
        self.assertIn('operation: "base-material-system-provider"', renderer)
        self.assertIn(
            'operation: "base-material-system-provider-rejected"', renderer
        )
        self.assertIn("} else if baseSource?.usesSystemProvider == true {", renderer)
        self.assertIn("usesAuthoredLayerColor:", renderer)
        self.assertIn("let color = usesAuthoredLayerColor", dependency)
        selection = renderer.index("let baseSelection: SceneBaseMaterialTextureSelection")
        rejection = renderer.index(
            "if let reasonCode = baseSelection.rejectedProviderReason", selection
        )
        graph_provider = renderer.index(
            "executeDependencyGraphProviderIfRequired", rejection
        )
        dependency_capture = renderer.index(
            "dependencyRuntime.requiresCapture", graph_provider
        )
        visibility_gate = renderer.index(
            "guard frameVisibleLayerIDs.contains(layer.id)", dependency_capture
        )
        self.assertLess(selection, rejection)
        self.assertLess(rejection, graph_provider)
        self.assertLess(graph_provider, dependency_capture)
        self.assertLess(dependency_capture, visibility_gate)

        preflight = (
            SCENE / "Rendering/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        begin = preflight.index("beginTextureFrame(")
        target_preflight = preflight.index(
            "switch preflightResolvedMaterialFrameTargets(", begin
        )
        self.assertLess(begin, target_preflight)
        self.assertIn('if layer.contentKind != "solid" {', preflight)
        self.assertIn("width: selectedSource.texture.width", preflight)
        self.assertIn("height: selectedSource.texture.height", preflight)
        deferred = preflight.index("case .deferred:", target_preflight)
        defer_frame = preflight.index(
            "imageCompositor.deferResolvedMaterialFrame()", deferred
        )
        deferred_end = preflight.index(
            "imageCompositor.endResolvedMaterialFrame(on: commandBuffer)",
            defer_frame,
        )
        rejected = preflight.index("case .rejected(let reasonCode):", deferred_end)
        rejected_end = preflight.index(
            "imageCompositor.endResolvedMaterialFrame(on: commandBuffer)", rejected
        )
        self.assertLess(deferred, defer_frame)
        self.assertLess(defer_frame, deferred_end)
        self.assertLess(deferred_end, rejected)
        self.assertLess(rejected, rejected_end)

    def test_current_provider_stale_rejection_last_ready_and_clear(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-media-provider-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "provider"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            subprocess.run(
                ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
                check=True,
                cwd=ROOT,
                env=environment,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        self.assertEqual(result["generation"], 3)
        self.assertEqual(result["initialPendingGeneration"], 3)
        self.assertTrue(result["initialPendingExact"])
        self.assertEqual(result["currentPixel"], [0, 0, 0, 0])
        self.assertEqual(result["preservedCurrentPixel"], [231, 17, 149, 0])
        self.assertTrue(result["currentPublicationComplete"])
        self.assertTrue(result["preservedPublicationComplete"])
        self.assertTrue(result["initialPreviousUnavailable"])
        self.assertTrue(result["currentRequestExact"])
        self.assertTrue(result["preservedRequestExact"])
        self.assertTrue(result["purposeQualifiedSystemAtoms"])
        self.assertTrue(result["baseMaterialReadyProviderExact"])
        self.assertTrue(result["baseMaterialReadyImageProviderOwnsExtent"])
        self.assertTrue(result["baseMaterialReadyPreservesDynamicTint"])
        self.assertTrue(result["baseMaterialMissingRegistryRejectsOnlyProvider"])
        self.assertTrue(
            result["baseMaterialMissingRegistryWithoutFallbackKeepsReason"]
        )
        self.assertTrue(result["baseMaterialUnavailableKeepsAuthoredFallback"])
        self.assertTrue(result["baseMaterialIncompleteRejectsOnlyProvider"])
        self.assertTrue(result["systemAndLayerRequestsAreDistinctAtoms"])
        self.assertTrue(result["currentPublicationPremultiplied"])
        self.assertTrue(result["preservedPublicationData"])
        self.assertEqual(result["rapidDecodeCount"], 1)
        self.assertTrue(result["duplicateAccepted"])
        self.assertTrue(result["duplicateGenerationStable"])
        self.assertTrue(result["oversizedRejected"])
        self.assertEqual(result["pendingGeneration"], 3)
        self.assertEqual(result["pendingRequestGeneration"], 4)
        self.assertTrue(result["pendingIdentitiesExact"])
        self.assertEqual(result["pendingCurrentPixel"], [0, 0, 0, 0])
        self.assertEqual(result["pendingPreservedPixel"], [231, 17, 149, 0])
        self.assertTrue(result["pendingPreviousUnavailable"])
        self.assertEqual(result["fourthCurrentPixel"], [255, 0, 0, 255])
        self.assertEqual(result["fourthPreservedPixel"], [255, 0, 0, 255])
        self.assertEqual(result["fourthPreviousPixel"], [0, 0, 0, 0])
        self.assertEqual(
            result["fourthPreservedPreviousPixel"], [231, 17, 149, 0]
        )
        self.assertTrue(result["fourthPreviousExact"])
        self.assertEqual(result["failurePendingGeneration"], 4)
        self.assertEqual(result["failurePendingCurrentPixel"], [255, 0, 0, 255])
        self.assertEqual(result["failurePendingPreservedPixel"], [255, 0, 0, 255])
        self.assertEqual(result["failurePendingPreviousPixel"], [0, 0, 0, 0])
        self.assertEqual(
            result["failurePendingPreservedPreviousPixel"], [231, 17, 149, 0]
        )
        self.assertEqual(result["failedGeneration"], 5)
        self.assertTrue(result["failedCurrent"])
        self.assertTrue(result["failedPreserved"])
        self.assertTrue(result["failedPrevious"])
        self.assertTrue(result["failedPreservedPrevious"])
        self.assertEqual(result["recoveryPendingGeneration"], 6)
        self.assertTrue(result["recoveryPendingExact"])
        self.assertEqual(result["recoveredCurrentPixel"], [0, 255, 0, 255])
        self.assertEqual(result["recoveredPreservedPixel"], [0, 255, 0, 255])
        self.assertEqual(result["recoveredPreviousPixel"], [255, 0, 0, 255])
        self.assertEqual(
            result["recoveredPreservedPreviousPixel"], [255, 0, 0, 255]
        )
        self.assertEqual(result["clearedGeneration"], 7)
        self.assertTrue(result["clearedCurrent"])
        self.assertTrue(result["clearedPreserved"])
        self.assertTrue(result["clearedPrevious"])
        self.assertTrue(result["clearedPreservedPrevious"])
        self.assertTrue(result["oversizedSourceColorReady"])
        self.assertTrue(result["oversizedSourceRetainsBothWhilePending"])
        self.assertTrue(result["oversizedSourcePreservedUnavailable"])
        self.assertTrue(result["oversizedSourceRotatesPreviousAtomically"])
        self.assertTrue(result["eventInitialEmpty"])
        self.assertTrue(result["propertiesAccepted"])
        self.assertEqual(result["propertiesGeneration"], 1)
        self.assertTrue(result["propertiesPreserveOtherGenerations"])
        self.assertTrue(result["propertiesExact"])
        self.assertTrue(result["duplicatePropertiesAccepted"])
        self.assertTrue(result["duplicatePropertiesStable"])
        self.assertTrue(result["titleChangeAccepted"])
        self.assertTrue(result["titleChangeAtomic"])
        self.assertTrue(result["artistChangeAccepted"])
        self.assertTrue(result["artistChangeAtomic"])
        self.assertTrue(result["controlPropertyRejected"])
        self.assertTrue(result["oversizedPropertyRejected"])
        self.assertTrue(result["invalidPropertiesPreserveSnapshot"])
        self.assertTrue(result["imageColorAccepted"])
        self.assertEqual(result["imageColorGeneration"], 1)
        self.assertEqual(result["imageColorPlaybackGeneration"], 0)
        self.assertTrue(result["imageColorPreservesProperties"])
        self.assertTrue(result["imageColorExact"])
        self.assertTrue(result["duplicateImageColorAccepted"])
        self.assertTrue(result["duplicateImageColorGenerationStable"])
        self.assertTrue(result["replacementColorAccepted"])
        self.assertEqual(result["replacementColorGeneration"], 2)
        self.assertTrue(result["replacementColorExact"])
        self.assertTrue(result["nanColorRejected"])
        self.assertTrue(result["negativeColorRejected"])
        self.assertTrue(result["oversizedColorRejected"])
        self.assertTrue(result["emptyImageWithColorRejected"])
        self.assertTrue(result["invalidColorsPreserveSnapshot"])
        self.assertTrue(result["playbackAccepted"])
        self.assertEqual(result["playbackState"], 1)
        self.assertEqual(result["playbackGeneration"], 1)
        self.assertTrue(result["playbackPreservesImageGeneration"])
        self.assertTrue(result["duplicatePlaybackAccepted"])
        self.assertTrue(result["duplicatePlaybackGenerationStable"])
        self.assertTrue(result["pausedAccepted"])
        self.assertEqual(result["pausedState"], 2)
        self.assertEqual(result["pausedGeneration"], 2)
        self.assertTrue(result["negativePlaybackRejected"])
        self.assertTrue(result["oversizedPlaybackRejected"])
        self.assertTrue(result["invalidPlaybackPreservesSnapshot"])
        self.assertTrue(result["nextImageAccepted"])
        self.assertEqual(result["nextImageGeneration"], 3)
        self.assertTrue(result["nextImagePreservesPlaybackGeneration"])
        self.assertEqual(result["eventClearGeneration"], 4)
        self.assertTrue(result["eventClearColorIsZero"])
        self.assertTrue(result["eventClearPreservesPlayback"])
        self.assertTrue(result["eventClearPreservesProperties"])
        self.assertTrue(result["duplicateEventClearStable"])
        self.assertTrue(result["emptyPropertiesAccepted"])
        self.assertTrue(result["emptyPropertiesClearOldValues"])
        self.assertEqual(result["emptyPropertiesGeneration"], 4)
        self.assertTrue(result["emptyPropertiesPreserveOtherGenerations"])
        self.assertTrue(result["duplicateEmptyPropertiesAccepted"])
        self.assertTrue(result["duplicateEmptyPropertiesStable"])


if __name__ == "__main__":
    unittest.main()
