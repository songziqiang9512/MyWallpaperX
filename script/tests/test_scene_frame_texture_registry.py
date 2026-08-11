#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
REGISTRY_SOURCE = SOURCE_ROOT / "Resources/SceneFrameTextureRegistry.swift"
BASE_IMAGE_SOURCE = SOURCE_ROOT / "Rendering/SceneBaseImageTextureLoad.swift"
FRAME_ASSEMBLY_SOURCE = SOURCE_ROOT / "Rendering/SceneFrameLayerTextureAssembly.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SOURCE_ROOT / "Resources/SceneImageTextureUploader.swift",
    REGISTRY_SOURCE,
]

TEST_ACCESS_SOURCE = r'''
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
        systemTextures: [String: MTLTexture] = [:],
        explicitSystemTextures: [String: SceneTextureProviderPublication] = [:]
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
'''

HARNESS_SOURCE = r'''
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "SceneFrameTextureRegistryTests", code: 1)
        }
        func texture() -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 4,
                height: 4,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            return device.makeTexture(descriptor: descriptor)!
        }
        func publication(
            _ texture: MTLTexture,
            generation: UInt64,
            requestIdentity: SceneFrameTextureIdentity = .layerSource(8),
            identity: SceneTextureResourceIdentity =
                .provider(.dynamicText(layerID: 8)),
            candidateGeneration: SceneTextureResourceGeneration? = nil,
            purpose: SceneTextureLoadPurpose = .premultipliedColor,
            content: SceneTextureContent =
                .color(.resolved(.premultipliedAlpha))
        ) -> SceneTextureProviderPublication {
            let size = CGSize(width: texture.width, height: texture.height)
            return SceneTextureProviderPublication(
                requestIdentity: requestIdentity,
                candidate: SceneTextureCandidate(
                    texture: texture,
                    identity: identity,
                    generation: candidateGeneration
                        ?? .provider(contentGeneration: generation),
                    purpose: purpose,
                    content: content,
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp
                ),
                contentGeneration: generation
            )
        }
        func bareResolution(
            _ registry: SceneFrameTextureRegistry,
            _ identity: SceneFrameTextureIdentity
        ) -> (texture: MTLTexture, generation: UInt64)? {
            guard let texture = registry.texture(for: identity),
                  case let .incomplete(.bare(_, generation))? = registry.lookup(identity)
            else { return nil }
            return (texture, generation)
        }

        let registry = SceneFrameTextureRegistry()
        let fallbackTexture = texture()
        let replacementFallbackTexture = texture()
        let propertyTexture = texture()
        let replacementPropertyTexture = texture()
        let systemTexture = texture()
        let replacementSystemTexture = texture()
        let namedTexture = texture()
        let dynamicTexture = texture()
        let replacementDynamicTexture = texture()
        let staleDynamicTexture = texture()
        let optionalPropertyIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "cover",
            purpose: .premultipliedColor
        )!
        let optionalProperty = SceneFrameTextureIdentity.materialUserProperty(
            optionalPropertyIdentity
        )
        let persistentProperty = SceneFrameTextureIdentity.userProperty("persistent-cover")
        let system = SceneFrameTextureIdentity.system("$mediaThumbnail")
        let fallback = SceneFrameTextureIdentity.layerSource(7)
        let dynamic = SceneFrameTextureIdentity.layerSource(8)
        let selection = SceneFrameTextureSelection(candidates: [optionalProperty, fallback])
        let firstEpoch = registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: ["$mediaThumbnail": systemTexture]
        )
        let firstFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let firstProperty = bareResolution(registry, persistentProperty)!
        let firstSystem = bareResolution(registry, system)!
        let bareLookupIsIncomplete: Bool
        if case .incomplete = registry.lookup(fallback) {
            bareLookupIsIncomplete = true
        } else {
            bareLookupIsIncomplete = false
        }
        let bareTypedLookupRejected = registry.resource(for: fallback) == nil
        let missingIsNotAbsent = registry.lookup(optionalProperty) == nil
        let missing = registry.resolve(selection)
        registry.set(.absent, for: optionalProperty)
        let absent = registry.resolve(selection)
        let absentIsExplicit: Bool
        if case .absent = registry.snapshot().lookup(optionalProperty) {
            absentIsExplicit = true
        } else {
            absentIsExplicit = false
        }
        registry.set(.pending, for: optionalProperty)
        let pending = registry.resolve(selection)
        registry.set(.unavailable, for: optionalProperty)
        let unavailable = registry.resolve(selection)
        registry.set(
            publication(
                propertyTexture,
                generation: 2,
                requestIdentity: optionalProperty,
                candidateGeneration: .provider(contentGeneration: 1)
            ),
            for: optionalProperty
        )
        let incomplete = registry.resolve(selection)
        registry.set(.ready(propertyTexture), for: optionalProperty)
        let bareExactProperty = registry.resolve(selection)
        registry.set(
            publication(
                propertyTexture,
                generation: 3,
                requestIdentity: optionalProperty,
                identity: .builtIn(name: "fixture-property-cover"),
                candidateGeneration: .immutable(revision: 1)
            ),
            for: optionalProperty
        )
        let ready = registry.resolve(selection)

        let primary = SceneNamedTextureReference(providerLayerID: 42, variant: .primary)
        let secondary = SceneNamedTextureReference(providerLayerID: 42, variant: .secondary)
        let named = SceneFrameTextureIdentity.namedLayerTarget(primary)
        registry.set(.ready(namedTexture), for: named)
        let firstNamed = bareResolution(registry, named)!
        let primaryReady = registry.texture(for: named) === namedTexture
        let secondaryIsolated = registry.texture(
            for: .namedLayerTarget(secondary)
        ) == nil

        let secondEpoch = registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: ["$mediaThumbnail": systemTexture]
        )
        let secondFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let secondProperty = bareResolution(registry, persistentProperty)!
        let secondSystem = bareResolution(registry, system)!
        let namedCleared = registry.texture(for: named) == nil
        registry.set(.ready(namedTexture), for: named)
        let secondNamed = bareResolution(registry, named)!

        registry.beginFrame(
            layerSources: [7: replacementFallbackTexture],
            userPropertyTextures: ["persistent-cover": replacementPropertyTexture],
            systemTextures: ["$mediaThumbnail": replacementSystemTexture]
        )
        let replacedFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let replacedProperty = bareResolution(registry, persistentProperty)!
        let replacedSystem = bareResolution(registry, system)!

        registry.beginFrame(layerSources: [:])
        let persistentEntriesCleared = registry.texture(for: fallback) == nil
            && registry.texture(for: persistentProperty) == nil
            && registry.texture(for: system) == nil

        registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: ["$mediaThumbnail": systemTexture]
        )
        let restoredFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let restoredProperty = bareResolution(registry, persistentProperty)!
        let restoredSystem = bareResolution(registry, system)!

        registry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(dynamicTexture, generation: 10)
            ]
        )
        let firstDynamic = registry.resolve(
            SceneFrameTextureSelection(candidates: [dynamic])
        )!
        let firstDynamicResource = registry.resource(for: dynamic)
        let firstDynamicSnapshot = registry.snapshot()
        let firstDynamicCandidate = firstDynamicResource?.publication.candidate
        let typedPublicationIsAtomic =
            firstDynamicResource?.publication.texture === dynamicTexture
            && firstDynamicResource?.publication.contentGeneration == 10
            && firstDynamicResource?.resourceGeneration == firstDynamic.generation
            && firstDynamicCandidate?.identity
                == .provider(.dynamicText(layerID: 8))
            && firstDynamicCandidate?.generation
                == .provider(contentGeneration: 10)
            && firstDynamicCandidate?.purpose == .premultipliedColor
            && firstDynamicCandidate?.content
                == .color(.resolved(.premultipliedAlpha))
            && firstDynamicCandidate?.physicalSize == CGSize(width: 4, height: 4)
            && firstDynamicCandidate?.mappedSize == CGSize(width: 4, height: 4)
            && firstDynamicCandidate?.pixelFormat == .bgra8Unorm
            && firstDynamicCandidate?.texture.mipmapLevelCount == 1
            && firstDynamicCandidate?.sampling == .linearClamp
        let snapshotUsesDirectIdentity = firstDynamicSnapshot
            .resource(for: dynamic)?.publication.texture === dynamicTexture
        let graphLayerSource = SceneFrameTextureIdentity.graph(
            SceneAuthoredEffectRenderPlan.TextureIdentity(
                kind: .layerSource,
                layerID: 8,
                effect: nil,
                name: nil
            )
        )
        let explicitLayerPublishesExactGraphIdentity = firstDynamicSnapshot
            .resource(for: graphLayerSource)?.publication.requestIdentity
                == graphLayerSource
            && firstDynamicSnapshot.resource(
                for: graphLayerSource
            )?.publication.candidate.texture === dynamicTexture
        registry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(dynamicTexture, generation: 11)
            ]
        )
        let secondDynamic = registry.resolve(
            SceneFrameTextureSelection(candidates: [dynamic])
        )!
        registry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(dynamicTexture, generation: 11)
            ]
        )
        let repeatedDynamic = registry.resolve(
            SceneFrameTextureSelection(candidates: [dynamic])
        )!
        registry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(
                    dynamicTexture,
                    generation: 11,
                    content: .color(.unresolved)
                )
            ]
        )
        let sameGenerationMetadataMutationPreservesAtom =
            registry.resource(for: dynamic)?.resourceGeneration
                == repeatedDynamic.generation
            && registry.resource(for: dynamic)?.publication.candidate.content
                == .color(.resolved(.premultipliedAlpha))
        registry.beginFrame(
            layerSources: [8: replacementDynamicTexture],
            explicitLayerSources: [
                8: publication(replacementDynamicTexture, generation: 11)
            ]
        )
        let sameGenerationDynamic = registry.resolve(
            SceneFrameTextureSelection(candidates: [dynamic])
        )!
        registry.beginFrame(
            layerSources: [8: staleDynamicTexture],
            explicitLayerSources: [
                8: publication(staleDynamicTexture, generation: 9)
            ]
        )
        let lowerProducerGenerationDynamic = registry.resolve(
            SceneFrameTextureSelection(candidates: [dynamic])
        )!
        registry.beginFrame(
            layerSources: [8: replacementDynamicTexture],
            explicitLayerSources: [
                8: publication(staleDynamicTexture, generation: 12)
            ]
        )
        let mismatchedPublicationRejected = registry.resolve(
            SceneFrameTextureSelection(candidates: [dynamic])
        ) == nil

        registry.beginFrame(
            layerSources: [:],
            systemTextures: ["$mediaThumbnail": systemTexture],
            explicitSystemTextures: [
                "$mediaThumbnail": publication(
                    systemTexture,
                    generation: 20,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let firstExplicitSystem = registry.resolve(
            SceneFrameTextureSelection(candidates: [system])
        )!
        registry.beginFrame(
            layerSources: [:],
            systemTextures: ["$mediaThumbnail": systemTexture],
            explicitSystemTextures: [
                "$mediaThumbnail": publication(
                    systemTexture,
                    generation: 21,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let secondExplicitSystem = registry.resolve(
            SceneFrameTextureSelection(candidates: [system])
        )!
        registry.beginFrame(
            layerSources: [:],
            systemTextures: ["$mediaThumbnail": replacementSystemTexture],
            explicitSystemTextures: [
                "$mediaThumbnail": publication(
                    replacementSystemTexture,
                    generation: 21,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let replacedSameGenerationSystem = registry.resolve(
            SceneFrameTextureSelection(candidates: [system])
        )!
        registry.beginFrame(
            layerSources: [:],
            systemTextures: ["$mediaThumbnail": replacementSystemTexture],
            explicitSystemTextures: [
                "$mediaThumbnail": publication(
                    replacementSystemTexture,
                    generation: 19,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let lowerProducerGenerationSystem = registry.resolve(
            SceneFrameTextureSelection(candidates: [system])
        )!

        let legacyBare = SceneFrameTextureIdentity.layerSource(9)
        registry.beginFrame(layerSources: [9: dynamicTexture])
        let legacyBareIsIncomplete: Bool
        if case .incomplete(.bare) = registry.lookup(legacyBare) {
            legacyBareIsIncomplete = registry.resource(for: legacyBare) == nil
        } else {
            legacyBareIsIncomplete = false
        }
        let bareGraphIdentity = SceneFrameTextureIdentity.graph(
            SceneAuthoredEffectRenderPlan.TextureIdentity(
                kind: .layerSource,
                layerID: 9,
                effect: nil,
                name: nil
            )
        )
        let bareLayerDoesNotPublishTypedGraph =
            registry.lookup(bareGraphIdentity) == nil

        let unresolvedVideo = SceneFrameTextureIdentity.layerSource(10)
        registry.beginFrame(
            layerSources: [10: dynamicTexture],
            explicitLayerSources: [
                10: publication(
                    dynamicTexture,
                    generation: 31,
                    requestIdentity: unresolvedVideo,
                    content: .color(.unresolved)
                )
            ]
        )
        let unresolvedColorIsIncomplete: Bool
        if case .incomplete = registry.lookup(unresolvedVideo) {
            unresolvedColorIsIncomplete = registry.resource(for: unresolvedVideo) == nil
        } else {
            unresolvedColorIsIncomplete = false
        }

        let dataIdentity = SceneFrameTextureIdentity.layerSource(11)
        let sourceIdentity = SceneTextureResourceIdentity.builtIn(name: "fixture-mask")
        let sourceGeneration = SceneTextureResourceGeneration.immutable(revision: 4)
        let dataPublication = publication(
            dynamicTexture,
            generation: 32,
            requestIdentity: dataIdentity,
            identity: sourceIdentity,
            candidateGeneration: sourceGeneration,
            purpose: .mask,
            content: .data
        )
        registry.beginFrame(
            layerSources: [11: dynamicTexture],
            explicitLayerSources: [11: dataPublication]
        )
        let dataResource = registry.resource(for: dataIdentity)
        let dataPurposeAndSourceRevisionPreserved =
            dataResource?.publication.candidate.purpose == .mask
            && dataResource?.publication.candidate.content == .data
            && dataResource?.publication.candidate.identity == sourceIdentity
            && dataResource?.publication.candidate.generation == sourceGeneration

        let mismatchedContent = SceneFrameTextureIdentity.layerSource(12)
        registry.beginFrame(
            layerSources: [12: dynamicTexture],
            explicitLayerSources: [
                12: publication(
                    dynamicTexture,
                    generation: 33,
                    requestIdentity: mismatchedContent,
                    identity: sourceIdentity,
                    candidateGeneration: sourceGeneration,
                    purpose: .mask,
                    content: .color(.resolved(.premultipliedAlpha))
                )
            ]
        )
        let mismatchedContentRejected = registry.resource(for: mismatchedContent) == nil
        let normalizedMask = SceneAssetTextureIdentity(
            virtualPath: "./Materials\\Mask.TEX",
            purpose: .mask
        )!
        let canonicalMask = SceneAssetTextureIdentity(
            virtualPath: "materials/mask.tex",
            purpose: .mask
        )!
        let samePathColor = SceneAssetTextureIdentity(
            virtualPath: "materials/mask.tex",
            purpose: .premultipliedColor
        )!
        let normalizedAssetIdentity =
            SceneFrameTextureIdentity.asset(normalizedMask)
                == SceneFrameTextureIdentity.asset(canonicalMask)
            && SceneFrameTextureIdentity.asset(normalizedMask).reportToken
                == "asset:materials/mask.tex:mask"
            && SceneFrameTextureIdentity.asset(canonicalMask)
                != SceneFrameTextureIdentity.asset(samePathColor)
            && SceneAssetTextureIdentity(
                virtualPath: "../materials/mask.tex",
                purpose: .mask
            ) == nil
            && SceneVFSAssetPath("materials//mask.tex") == nil
            && SceneVFSAssetPath("file:materials/mask.tex") == nil
            && SceneVFSAssetPath("materials/ma\u{7f}sk.tex") == nil
        let assetRegistryIdentity = SceneFrameTextureIdentity.asset(canonicalMask)
        let assetPublication = dataPublication.publication(
            for: assetRegistryIdentity
        )

        let transitionRegistry = SceneFrameTextureRegistry()
        transitionRegistry.beginFrame(layerSources: [:])
        transitionRegistry.set(assetPublication, for: assetRegistryIdentity)
        let typedTransitionGeneration = transitionRegistry.resource(
            for: assetRegistryIdentity
        )!.resourceGeneration
        transitionRegistry.beginFrame(layerSources: [:])
        transitionRegistry.testPublishPersistent(
            dynamicTexture,
            for: assetRegistryIdentity
        )
        let typedToBareGeneration: UInt64
        if case let .incomplete(.bare(_, resourceGeneration)) =
            transitionRegistry.lookup(assetRegistryIdentity) {
            typedToBareGeneration = resourceGeneration
        } else {
            typedToBareGeneration = 0
        }
        let typedToBareAdvancesGeneration =
            typedToBareGeneration > typedTransitionGeneration

        transitionRegistry.beginFrame(layerSources: [:])
        transitionRegistry.testPublishPersistent(
            dynamicTexture,
            for: assetRegistryIdentity
        )
        let repeatedBareGeneration: UInt64
        if case let .incomplete(.bare(_, resourceGeneration)) =
            transitionRegistry.lookup(assetRegistryIdentity) {
            repeatedBareGeneration = resourceGeneration
        } else {
            repeatedBareGeneration = 0
        }
        let bareToBareKeepsGeneration =
            repeatedBareGeneration == typedToBareGeneration

        let purposeMismatchPublication = publication(
            dynamicTexture,
            generation: 46
        )
        transitionRegistry.beginFrame(layerSources: [:])
        transitionRegistry.set(
            purposeMismatchPublication,
            for: assetRegistryIdentity
        )
        let exactIdentityMismatchRejectedWithoutEntry =
            transitionRegistry.lookup(assetRegistryIdentity) == nil
        transitionRegistry.beginFrame(layerSources: [:])
        transitionRegistry.testPublishPersistent(
            dynamicTexture,
            for: assetRegistryIdentity
        )
        let mismatchToBareGeneration: UInt64
        if case let .incomplete(.bare(_, resourceGeneration)) =
            transitionRegistry.lookup(assetRegistryIdentity) {
            mismatchToBareGeneration = resourceGeneration
        } else {
            mismatchToBareGeneration = 0
        }
        let mismatchToBareAdvancesGeneration =
            mismatchToBareGeneration > repeatedBareGeneration

        registry.beginFrame(layerSources: [:])
        registry.set(assetPublication, for: assetRegistryIdentity)
        let firstSetGeneration = registry.resource(
            for: assetRegistryIdentity
        )!.resourceGeneration
        registry.set(assetPublication, for: assetRegistryIdentity)
        let repeatedSetGeneration = registry.resource(
            for: assetRegistryIdentity
        )!.resourceGeneration
        registry.set(
            publication(
                replacementDynamicTexture,
                generation: 32,
                requestIdentity: assetRegistryIdentity,
                identity: sourceIdentity,
                candidateGeneration: sourceGeneration,
                purpose: .mask,
                content: .data
            ),
            for: assetRegistryIdentity
        )
        let replacedSetResource = registry.resource(for: assetRegistryIdentity)!
        let typedSetIdentityIsStable =
            repeatedSetGeneration == firstSetGeneration
            && replacedSetResource.resourceGeneration == repeatedSetGeneration
            && replacedSetResource.publication.texture === dynamicTexture

        let crossFrameAtom = replacedSetResource.publication
        let crossFrameGeneration = replacedSetResource.resourceGeneration
        registry.beginFrame(layerSources: [:])
        registry.set(crossFrameAtom, for: assetRegistryIdentity)
        let typedSetStableAcrossFrames = registry.resource(
            for: assetRegistryIdentity
        )?.resourceGeneration == crossFrameGeneration
        let alternateAtom = publication(
            dynamicTexture,
            generation: 45,
            requestIdentity: assetRegistryIdentity,
            identity: sourceIdentity,
            candidateGeneration: sourceGeneration,
            purpose: .mask,
            content: .data
        )
        registry.set(alternateAtom, for: assetRegistryIdentity)
        let alternateGeneration = registry.resource(
            for: assetRegistryIdentity
        )!.resourceGeneration
        registry.set(crossFrameAtom, for: assetRegistryIdentity)
        let sameFrameStaleABAPreservesNewest = registry.resource(
            for: assetRegistryIdentity
        )!.resourceGeneration == alternateGeneration
            && registry.resource(
                for: assetRegistryIdentity
            )!.publication.contentGeneration == 45

        registry.beginFrame(layerSources: [:])
        registry.set(
            assetPublication.publication(for: .asset(samePathColor)),
            for: .asset(samePathColor)
        )
        let purposeMismatchedAssetIncomplete: Bool
        if case .incomplete = registry.lookup(.asset(samePathColor)) {
            purposeMismatchedAssetIncomplete =
                registry.resource(for: .asset(samePathColor)) == nil
        } else {
            purposeMismatchedAssetIncomplete = false
        }
        registry.set(assetPublication, for: assetRegistryIdentity)
        let validBeforePurposeMismatch = registry.resource(
            for: assetRegistryIdentity
        ) != nil
        let colorPublication = publication(
            dynamicTexture,
            generation: 44,
            requestIdentity: assetRegistryIdentity
        )
        registry.set(colorPublication, for: assetRegistryIdentity)
        let purposeMismatchReplacesOldReady: Bool
        if case .incomplete = registry.lookup(assetRegistryIdentity) {
            purposeMismatchReplacesOldReady =
                validBeforePurposeMismatch
                && registry.resource(for: assetRegistryIdentity) == nil
        } else {
            purposeMismatchReplacesOldReady = false
        }

        let mismatchedIdentityGeneration = publication(
            dynamicTexture,
            generation: 40,
            requestIdentity: assetRegistryIdentity,
            identity: .file(path: "/fixture/mask.tex"),
            candidateGeneration: .immutable(revision: 40),
            purpose: .mask,
            content: .data
        )
        registry.set(mismatchedIdentityGeneration, for: assetRegistryIdentity)
        let mismatchedIdentityGenerationIncomplete =
            registry.resource(for: assetRegistryIdentity) == nil
        let providerGenerationMismatch = publication(
            dynamicTexture,
            generation: 42,
            requestIdentity: .layerSource(42),
            candidateGeneration: .provider(contentGeneration: 41)
        )
        let providerMismatchIdentity = SceneFrameTextureIdentity.layerSource(42)
        registry.set(providerGenerationMismatch, for: providerMismatchIdentity)
        let providerGenerationMismatchIncomplete =
            registry.resource(for: providerMismatchIdentity) == nil
        let volumePurposeOn2D = publication(
            dynamicTexture,
            generation: 43,
            requestIdentity: .system("fixture-lut"),
            identity: .builtIn(name: "fixture-lut"),
            candidateGeneration: .immutable(revision: 43),
            purpose: .lookupTable,
            content: .data
        )
        let volumeIdentity = SceneFrameTextureIdentity.system("fixture-lut")
        registry.set(volumePurposeOn2D, for: volumeIdentity)
        let volumePurposeOn2DIncomplete = registry.resource(for: volumeIdentity) == nil

        let maskProperty = SceneUserPropertyTextureIdentity(
            propertyKey: "cover",
            purpose: .mask
        )!
        let colorProperty = SceneUserPropertyTextureIdentity(
            propertyKey: "cover",
            purpose: .premultipliedColor
        )!
        registry.beginFrame(
            layerSources: [:],
            userPropertyStates: [
                maskProperty: .ready(assetPublication.publication(
                    for: .materialUserProperty(maskProperty)
                )),
                colorProperty: .ready(assetPublication.publication(
                    for: .materialUserProperty(colorProperty)
                )),
            ]
        )
        let purposeQualifiedUserPropertyReady = registry.resource(
            for: .materialUserProperty(maskProperty)
        )?.publication.candidate.purpose == .mask
        let purposeMismatchedUserPropertyIncomplete: Bool
        if case .incomplete = registry.lookup(.materialUserProperty(colorProperty)) {
            purposeMismatchedUserPropertyIncomplete =
                registry.resource(for: .materialUserProperty(colorProperty)) == nil
        } else {
            purposeMismatchedUserPropertyIncomplete = false
        }
        registry.set(.pending, for: .materialUserProperty(colorProperty))
        let typedPendingIsExplicit: Bool
        if case .pending = registry.snapshot().lookup(
            .materialUserProperty(colorProperty)
        ) {
            typedPendingIsExplicit = true
        } else {
            typedPendingIsExplicit = false
        }
        registry.set(.unavailable, for: .materialUserProperty(colorProperty))
        let typedUnavailableIsExplicit: Bool
        if case .unavailable = registry.snapshot().lookup(
            .materialUserProperty(colorProperty)
        ) {
            typedUnavailableIsExplicit = true
        } else {
            typedUnavailableIsExplicit = false
        }
        registry.set(.absent, for: .materialUserProperty(colorProperty))
        let typedAbsentIsExplicit: Bool
        if case .absent = registry.snapshot().lookup(
            .materialUserProperty(colorProperty)
        ) {
            typedAbsentIsExplicit = true
        } else {
            typedAbsentIsExplicit = false
        }

        let stateRegistry = SceneFrameTextureRegistry()
        stateRegistry.beginFrame(
            frameIndex: 9_001,
            layerSources: [:],
            assetStates: [
                canonicalMask: .ready(assetPublication),
                samePathColor: .absent,
            ]
        )
        let stateSnapshot = stateRegistry.snapshot()
        let frameIndexIsFrozen = stateSnapshot.frameIndex == 9_001
        let assetStatePublishesExactRequest = stateSnapshot.resource(
            for: assetRegistryIdentity
        )?.publication.requestIdentity == assetRegistryIdentity
        let assetAbsentIsExplicit: Bool
        if case .absent = stateSnapshot.lookup(.asset(samePathColor)) {
            assetAbsentIsExplicit = stateSnapshot.lookup(.system("missing")) == nil
        } else {
            assetAbsentIsExplicit = false
        }

        let requestMismatchRegistry = SceneFrameTextureRegistry()
        requestMismatchRegistry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(
                    dynamicTexture,
                    generation: 50,
                    requestIdentity: .layerSource(7)
                )
            ]
        )
        let exactRequestMismatchRejected =
            requestMismatchRegistry.lookup(.layerSource(8)) == nil
            && requestMismatchRegistry.lookup(graphLayerSource) == nil

        let videoRegistry = SceneFrameTextureRegistry()
        let videoRequest = SceneFrameTextureIdentity.layerSource(13)
        func videoPublication(
            _ texture: MTLTexture,
            generation: UInt64,
            epoch: UInt64
        ) -> SceneTextureProviderPublication {
            publication(
                texture,
                generation: generation,
                requestIdentity: videoRequest,
                identity: .provider(.video(
                    layerID: 13,
                    lifecycleEpoch: epoch
                ))
            )
        }
        videoRegistry.beginFrame(
            layerSources: [13: dynamicTexture],
            explicitLayerSources: [
                13: videoPublication(dynamicTexture, generation: 10, epoch: 100)
            ]
        )
        let initialVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: replacementDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(
                    replacementDynamicTexture,
                    generation: 10,
                    epoch: 100
                )
            ]
        )
        let sameGenerationVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: staleDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(staleDynamicTexture, generation: 9, epoch: 100)
            ]
        )
        let staleVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: replacementDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(
                    replacementDynamicTexture,
                    generation: 1,
                    epoch: 101
                )
            ]
        )
        let rebuiltVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: staleDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(staleDynamicTexture, generation: 11, epoch: 100)
            ]
        )
        let oldLifecycleVideo = videoRegistry.resource(for: videoRequest)!
        let videoLifecycleGenerationIsAtomic =
            sameGenerationVideo.resourceGeneration == initialVideo.resourceGeneration
            && sameGenerationVideo.publication.texture === dynamicTexture
            && staleVideo.resourceGeneration == initialVideo.resourceGeneration
            && staleVideo.publication.texture === dynamicTexture
            && rebuiltVideo.resourceGeneration > initialVideo.resourceGeneration
            && rebuiltVideo.publication.contentGeneration == 1
            && rebuiltVideo.publication.texture === replacementDynamicTexture
            && oldLifecycleVideo.resourceGeneration == rebuiltVideo.resourceGeneration
            && oldLifecycleVideo.publication.texture === replacementDynamicTexture

        let directSampling = SceneTextureSampling.linearClamp
        let programSamplerAdmissionIsBounded =
            directSampling.rawFlags == nil
            && directSampling.isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 0).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 1).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 2).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 3).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 2) == .linearClamp
            && !SceneTextureSampling(texFlags: 4).isResolvedForMaterialProgram
            && !SceneTextureSampling(texFlags: 8).isResolvedForMaterialProgram
            && !SceneTextureSampling(texFlags: 16).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 8).rawFlags == 8

        let result: [String: Any] = [
            "frameEpochAdvanced": secondEpoch == firstEpoch + 1,
            "persistentGenerationsStable": secondFallback.generation == firstFallback.generation
                && secondProperty.generation == firstProperty.generation
                && secondSystem.generation == firstSystem.generation,
            "replacementGenerationsAdvanced": replacedFallback.generation > secondFallback.generation
                && replacedProperty.generation > secondProperty.generation
                && replacedSystem.generation > secondSystem.generation,
            "restoredGenerationsAdvanced": restoredFallback.generation > replacedFallback.generation
                && restoredProperty.generation > replacedProperty.generation
                && restoredSystem.generation > replacedSystem.generation,
            "absentFallback": absent?.usedFallback == true && absent?.texture === fallbackTexture,
            "missingIsNotAbsent": missingIsNotAbsent,
            "missingFailsClosed": missing == nil,
            "absentIsExplicit": absentIsExplicit,
            "pendingFailsClosed": pending == nil,
            "unavailableFailsClosed": unavailable == nil,
            "incompleteFailsClosed": incomplete == nil,
            "bareExactPropertyFailsClosed": bareExactProperty == nil,
            "readyOverride": ready?.usedFallback == false && ready?.texture === propertyTexture,
            "primaryReady": primaryReady,
            "secondaryIsolated": secondaryIsolated,
            "namedCleared": namedCleared,
            "namedGenerationAdvanced": secondNamed.generation == firstNamed.generation + 1,
            "persistentEntriesCleared": persistentEntriesCleared,
            "bareLookupIsIncomplete": bareLookupIsIncomplete,
            "bareTypedLookupRejected": bareTypedLookupRejected,
            "typedPublicationIsAtomic": typedPublicationIsAtomic,
            "snapshotUsesDirectIdentity": snapshotUsesDirectIdentity,
            "explicitLayerPublishesExactGraphIdentity":
                explicitLayerPublishesExactGraphIdentity,
            "sameGenerationMetadataMutationPreservesAtom":
                sameGenerationMetadataMutationPreservesAtom,
            "legacyBareIsIncomplete": legacyBareIsIncomplete,
            "bareLayerDoesNotPublishTypedGraph": bareLayerDoesNotPublishTypedGraph,
            "unresolvedColorIsIncomplete": unresolvedColorIsIncomplete,
            "dataPurposeAndSourceRevisionPreserved":
                dataPurposeAndSourceRevisionPreserved,
            "mismatchedContentRejected": mismatchedContentRejected,
            "normalizedAssetIdentity": normalizedAssetIdentity,
            "typedToBareAdvancesGeneration": typedToBareAdvancesGeneration,
            "exactIdentityMismatchRejectedWithoutEntry":
                exactIdentityMismatchRejectedWithoutEntry,
            "mismatchToBareAdvancesGeneration": mismatchToBareAdvancesGeneration,
            "bareToBareKeepsGeneration": bareToBareKeepsGeneration,
            "typedSetIdentityIsStable": typedSetIdentityIsStable,
            "typedSetStableAcrossFrames": typedSetStableAcrossFrames,
            "sameFrameStaleABAPreservesNewest": sameFrameStaleABAPreservesNewest,
            "purposeMismatchedAssetIncomplete": purposeMismatchedAssetIncomplete,
            "purposeMismatchReplacesOldReady": purposeMismatchReplacesOldReady,
            "mismatchedIdentityGenerationIncomplete":
                mismatchedIdentityGenerationIncomplete,
            "providerGenerationMismatchIncomplete":
                providerGenerationMismatchIncomplete,
            "volumePurposeOn2DIncomplete": volumePurposeOn2DIncomplete,
            "purposeQualifiedUserPropertyReady": purposeQualifiedUserPropertyReady,
            "purposeMismatchedUserPropertyIncomplete":
                purposeMismatchedUserPropertyIncomplete,
            "typedPendingIsExplicit": typedPendingIsExplicit,
            "typedUnavailableIsExplicit": typedUnavailableIsExplicit,
            "typedAbsentIsExplicit": typedAbsentIsExplicit,
            "frameIndexIsFrozen": frameIndexIsFrozen,
            "assetStatePublishesExactRequest": assetStatePublishesExactRequest,
            "assetAbsentIsExplicit": assetAbsentIsExplicit,
            "exactRequestMismatchRejected": exactRequestMismatchRejected,
            "videoLifecycleGenerationIsAtomic": videoLifecycleGenerationIsAtomic,
            "programSamplerAdmissionIsBounded": programSamplerAdmissionIsBounded,
            "explicitContentGenerationAdvanced":
                secondDynamic.generation > firstDynamic.generation,
            "sameExplicitGenerationStable":
                repeatedDynamic.generation == secondDynamic.generation
                    && repeatedDynamic.texture === dynamicTexture,
            "sameGenerationReplacementRejected":
                sameGenerationDynamic.generation == repeatedDynamic.generation
                    && sameGenerationDynamic.texture === dynamicTexture,
            "lowerProducerGenerationRejected":
                lowerProducerGenerationDynamic.generation
                    == sameGenerationDynamic.generation
                    && lowerProducerGenerationDynamic.texture === dynamicTexture,
            "mismatchedPublicationRejected": mismatchedPublicationRejected,
            "explicitSystemGenerationAdvanced":
                secondExplicitSystem.generation > firstExplicitSystem.generation,
            "sameExplicitSystemGenerationReplacementRejected":
                replacedSameGenerationSystem.generation == secondExplicitSystem.generation
                    && replacedSameGenerationSystem.texture === systemTexture,
            "lowerExplicitSystemGenerationRejected":
                lowerProducerGenerationSystem.generation
                    == replacedSameGenerationSystem.generation
                    && lowerProducerGenerationSystem.texture === systemTexture,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFrameTextureRegistryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-texture-registry-")
        root = Path(cls.temporary_directory.name)
        test_registry_source = root / REGISTRY_SOURCE.name
        test_registry_source.write_text(
            REGISTRY_SOURCE.read_text(encoding="utf-8") + TEST_ACCESS_SOURCE,
            encoding="utf-8",
        )
        swift_sources = [
            test_registry_source if source == REGISTRY_SOURCE else source
            for source in SWIFT_SOURCES
        ]
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "texture-registry"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in swift_sources),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_ready_provider_wins_and_only_explicit_absent_falls_back(self) -> None:
        for key in (
            "absentFallback",
            "missingIsNotAbsent",
            "absentIsExplicit",
            "missingFailsClosed",
            "pendingFailsClosed",
            "unavailableFailsClosed",
            "incompleteFailsClosed",
            "bareExactPropertyFailsClosed",
            "readyOverride",
        ):
            self.assertTrue(self.result[key], key)

    def test_named_target_identity_and_frame_lifetime_are_preserved(self) -> None:
        for key in (
            "frameEpochAdvanced",
            "primaryReady",
            "secondaryIsolated",
            "namedCleared",
            "namedGenerationAdvanced",
        ):
            self.assertTrue(self.result[key], key)

    def test_persistent_resource_generations_change_only_with_publication(self) -> None:
        for key in (
            "persistentGenerationsStable",
            "replacementGenerationsAdvanced",
            "restoredGenerationsAdvanced",
            "persistentEntriesCleared",
        ):
            self.assertTrue(self.result[key], key)

    def test_registry_rejects_stale_or_mutated_atoms_within_one_lifecycle(
        self,
    ) -> None:
        for key in (
            "explicitContentGenerationAdvanced",
            "sameExplicitGenerationStable",
            "sameGenerationReplacementRejected",
            "lowerProducerGenerationRejected",
            "mismatchedPublicationRejected",
            "explicitSystemGenerationAdvanced",
            "sameExplicitSystemGenerationReplacementRejected",
            "lowerExplicitSystemGenerationRejected",
            "typedSetIdentityIsStable",
            "typedSetStableAcrossFrames",
            "sameFrameStaleABAPreservesNewest",
            "videoLifecycleGenerationIsAtomic",
        ):
            self.assertTrue(self.result[key], key)

    def test_bare_generation_changes_when_typed_metadata_is_removed(self) -> None:
        for key in (
            "typedToBareAdvancesGeneration",
            "exactIdentityMismatchRejectedWithoutEntry",
            "mismatchToBareAdvancesGeneration",
            "bareToBareKeepsGeneration",
        ):
            self.assertTrue(self.result[key], key)

    def test_typed_lookup_is_atomic_identity_based_and_fail_closed(self) -> None:
        for key in (
            "bareLookupIsIncomplete",
            "bareTypedLookupRejected",
            "typedPublicationIsAtomic",
            "snapshotUsesDirectIdentity",
            "explicitLayerPublishesExactGraphIdentity",
            "sameGenerationMetadataMutationPreservesAtom",
            "legacyBareIsIncomplete",
            "bareLayerDoesNotPublishTypedGraph",
            "unresolvedColorIsIncomplete",
            "dataPurposeAndSourceRevisionPreserved",
            "mismatchedContentRejected",
            "normalizedAssetIdentity",
            "purposeMismatchedAssetIncomplete",
            "purposeMismatchReplacesOldReady",
            "mismatchedIdentityGenerationIncomplete",
            "providerGenerationMismatchIncomplete",
            "volumePurposeOn2DIncomplete",
            "purposeQualifiedUserPropertyReady",
            "purposeMismatchedUserPropertyIncomplete",
            "typedPendingIsExplicit",
            "typedUnavailableIsExplicit",
            "typedAbsentIsExplicit",
            "frameIndexIsFrozen",
            "assetStatePublishesExactRequest",
            "assetAbsentIsExplicit",
            "exactRequestMismatchRejected",
            "programSamplerAdmissionIsBounded",
        ):
            self.assertTrue(self.result[key], key)

    def test_layer_publishers_bind_each_logical_request_exactly(self) -> None:
        base = BASE_IMAGE_SOURCE.read_text(encoding="utf-8")
        assembly = FRAME_ASSEMBLY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("requestIdentity: .layerSource(layerID)", base)
        self.assertIn("publication.requestIdentity == .layerSource(layerID)", base)
        self.assertIn("for: .layerSource(layerID)", assembly)


if __name__ == "__main__":
    unittest.main()
