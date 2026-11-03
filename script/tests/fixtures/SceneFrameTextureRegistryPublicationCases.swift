extension Harness {
    static func namedPublicationCases(
        device: MTLDevice,
        primary: SceneNamedTextureReference,
        secondary: SceneNamedTextureReference,
        named: SceneFrameTextureIdentity,
        fallbackTexture: MTLTexture,
        propertyTexture: MTLTexture,
        systemProviderIdentity: SceneSystemProviderTextureIdentity,
        systemTexture: MTLTexture,
        namedTexture: MTLTexture
    ) -> [String: Any] {
        let overlayRegistry = SceneFrameTextureRegistry()
        let overlayEpoch = overlayRegistry.beginFrame(layerSources: [:])
        let overlaySnapshot = overlayRegistry.snapshot()
        let reservedNamedResource = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: primary,
                frameEpoch: overlayEpoch,
                texture: namedTexture
            )!
        let namedOverlay = overlaySnapshot.overlayingNamedLayerTarget(
            primary,
            resource: reservedNamedResource
        )
        let exactNamedOverlayReady = namedOverlay?.resource(for: named)?
            .publication.texture === namedTexture
        let typedNamedPublicationRegistry = SceneFrameTextureRegistry()
        let typedNamedPublicationEpoch = typedNamedPublicationRegistry.beginFrame(
            layerSources: [:]
        )
        let typedNamedPublicationSucceeded =
            typedNamedPublicationRegistry.publishReservedNamedLayerTarget(
                reference: primary,
                frameEpoch: typedNamedPublicationEpoch,
                texture: namedTexture
            )
        let typedNamedPublicationIsComplete =
            typedNamedPublicationRegistry.resource(for: named)?
                .isCompleteNamedLayerTarget(
                    reference: primary,
                    frameEpoch: typedNamedPublicationEpoch
                ) == true
        let dataRegistry = SceneFrameTextureRegistry()
        let dataEpoch = dataRegistry.beginFrame(layerSources: [:])
        let typedDataPublication = dataRegistry.publishReservedNamedLayerTarget(
            reference: primary, frameEpoch: dataEpoch,
            texture: namedTexture, content: .data
        )
        let namedDataResource = dataRegistry.completeNamedLayerTargetResource(
            reference: primary, frameEpoch: dataEpoch
        )
        let typedNamedDataRetained = typedDataPublication
            && namedDataResource?.publication.candidate.content == .data
            && namedDataResource?.publication.candidate.purpose == .preservedChannels
            && namedDataResource?.publication.texture === namedTexture
            && dataRegistry.snapshot().overlayingNamedLayerTarget(
                primary, resource: namedDataResource!
            )?.resource(for: named)?.publication.candidate.content == .data
        let namedDataCannotBecomeColor = dataRegistry.completeNamedLayerTargetTexture(
            reference: primary, frameEpoch: dataEpoch
        ) == nil
        let staleNamedDataRejected = dataRegistry.completeNamedLayerTargetResource(
            reference: primary, frameEpoch: dataEpoch + 1
        ) == nil
        let unsupportedNamedContentRejected = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: primary, frameEpoch: dataEpoch,
                texture: namedTexture, content: .scalarRedUnorm
            ) == nil
        let namedPublicationAfterOtherResources = SceneFrameTextureRegistry()
        let namedPublicationAfterOtherResourcesEpoch =
            namedPublicationAfterOtherResources.beginFrame(
                layerSources: [7: fallbackTexture],
                userPropertyTextures: ["persistent-cover": propertyTexture],
                systemTextures: [systemProviderIdentity: systemTexture]
            )
        let namedPublicationAfterOtherResourcesSucceeded =
            namedPublicationAfterOtherResources
                .publishReservedNamedLayerTarget(
                    reference: primary,
                    frameEpoch: namedPublicationAfterOtherResourcesEpoch,
                    texture: namedTexture
                )
        let namedPublicationAfterOtherResourcesComplete =
            namedPublicationAfterOtherResources
                .completeNamedLayerTargetTexture(
                    reference: primary,
                    frameEpoch: namedPublicationAfterOtherResourcesEpoch
                ) === namedTexture
        let bareNamedConsumerRegistry = SceneFrameTextureRegistry()
        let bareNamedConsumerEpoch = bareNamedConsumerRegistry.beginFrame(
            layerSources: [:]
        )
        bareNamedConsumerRegistry.set(.ready(namedTexture), for: named)
        let bareNamedConsumerRejected =
            bareNamedConsumerRegistry.completeNamedLayerTargetTexture(
                reference: primary,
                frameEpoch: bareNamedConsumerEpoch
            ) == nil
        let staleTypedPublicationRegistry = SceneFrameTextureRegistry()
        let staleTypedPublicationEpoch = staleTypedPublicationRegistry.beginFrame(
            layerSources: [:]
        )
        let staleTypedPublicationRejected =
            !staleTypedPublicationRegistry.publishReservedNamedLayerTarget(
                reference: primary,
                frameEpoch: staleTypedPublicationEpoch + 1,
                texture: namedTexture
            ) && staleTypedPublicationRegistry.resource(for: named) == nil
        let secondaryNamedReservationRejected = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: secondary,
                frameEpoch: overlayEpoch,
                texture: namedTexture
            ) == nil
        let missingRenderTargetUsageRejected = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: primary,
                frameEpoch: overlayEpoch,
                texture: texture(device, usage: [.shaderRead])
            ) == nil
        let staleNamedResource = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: primary,
                frameEpoch: overlayEpoch + 1,
                texture: namedTexture
            )!
        let staleNamedOverlayRejected = overlaySnapshot.overlayingNamedLayerTarget(
            primary,
            resource: staleNamedResource
        ) == nil
        let wrongNamedReference = SceneNamedTextureReference(
            providerLayerID: 43,
            variant: .primary
        )
        let wrongNamedResource = SceneFrameTextureResource
            .reservedNamedLayerTarget(
                reference: wrongNamedReference,
                frameEpoch: overlayEpoch,
                texture: namedTexture
            )!
        let wrongNamedOverlayRejected = overlaySnapshot.overlayingNamedLayerTarget(
            primary,
            resource: wrongNamedResource
        ) == nil
        return [
            "exactNamedOverlayReady": exactNamedOverlayReady,
            "typedNamedDataRetained": typedNamedDataRetained,
            "namedDataCannotBecomeColor": namedDataCannotBecomeColor,
            "staleNamedDataRejected": staleNamedDataRejected,
            "unsupportedNamedContentRejected": unsupportedNamedContentRejected,
            "typedNamedPublicationSucceeded": typedNamedPublicationSucceeded,
            "typedNamedPublicationIsComplete": typedNamedPublicationIsComplete,
            "namedPublicationAfterOtherResourcesSucceeded":
                namedPublicationAfterOtherResourcesSucceeded,
            "namedPublicationAfterOtherResourcesComplete":
                namedPublicationAfterOtherResourcesComplete,
            "bareNamedConsumerRejected": bareNamedConsumerRejected,
            "staleTypedPublicationRejected": staleTypedPublicationRejected,
            "secondaryNamedReservationRejected": secondaryNamedReservationRejected,
            "missingRenderTargetUsageRejected": missingRenderTargetUsageRejected,
            "staleNamedOverlayRejected": staleNamedOverlayRejected,
            "wrongNamedOverlayRejected": wrongNamedOverlayRejected,
        ]
    }

    static func typedPublicationCases(
        registry: SceneFrameTextureRegistry,
        dynamicTexture: MTLTexture,
        replacementDynamicTexture: MTLTexture,
        graphLayerSource: SceneFrameTextureIdentity
    ) -> [String: Any] {
        let bareLayerSource = SceneFrameTextureIdentity.layerSource(9)
        registry.beginFrame(layerSources: [9: dynamicTexture])
        let bareLayerSourceIsIncomplete: Bool
        if case .incomplete(.bare) = registry.lookup(bareLayerSource) {
            bareLayerSourceIsIncomplete = registry.resource(for: bareLayerSource) == nil
        } else {
            bareLayerSourceIsIncomplete = false
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
            && SceneVFSAssetPath("/materials/mask.tex") == nil
            && SceneVFSAssetPath("file:///materials/mask.tex") == nil
            && SceneVFSAssetPath("materials/ma\u{7f}sk.tex") == nil
        let colonAssetIdentity = [
            ("Materials/Phase:Night.TEX", "materials/phase:night.tex"),
            ("./Images\\Tone:Dawn.PNG", "images/tone:dawn.png"),
            ("C:/Textures/Mask.PNG", "c:/textures/mask.png"),
            ("file:materials/mask.tex", "file:materials/mask.tex"),
        ].allSatisfy { authored, normalized in
            guard let mask = SceneAssetTextureIdentity(virtualPath: authored, purpose: .mask),
                  let color = SceneAssetTextureIdentity(virtualPath: authored, purpose: .premultipliedColor),
                  let canonical = SceneAssetTextureIdentity(virtualPath: normalized, purpose: .mask) else {
                return false
            }
            return mask == canonical && mask != color
                && mask.reportToken == "asset:\(normalized):mask"
                && Set([mask.reportToken, color.reportToken]).count == 2
        }
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
        let volumeSystemIdentity = SceneSystemProviderTextureIdentity(
            name: "fixture-lut",
            purpose: .lookupTable
        )
        let volumeIdentity = SceneFrameTextureIdentity.system(volumeSystemIdentity)
        let volumePurposeOn2D = publication(
            dynamicTexture,
            generation: 43,
            requestIdentity: volumeIdentity,
            identity: .builtIn(name: "fixture-lut"),
            candidateGeneration: .immutable(revision: 43),
            purpose: .lookupTable,
            content: .data
        )
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
            assetAbsentIsExplicit = stateSnapshot.lookup(.system(.init(
                name: "missing",
                purpose: .premultipliedColor
            ))) == nil
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
        return [
            "bareLayerSourceIsIncomplete": bareLayerSourceIsIncomplete,
            "bareLayerDoesNotPublishTypedGraph": bareLayerDoesNotPublishTypedGraph,
            "unresolvedColorIsIncomplete": unresolvedColorIsIncomplete,
            "dataPurposeAndSourceRevisionPreserved":
                dataPurposeAndSourceRevisionPreserved,
            "mismatchedContentRejected": mismatchedContentRejected,
            "normalizedAssetIdentity": normalizedAssetIdentity,
            "colonAssetIdentity": colonAssetIdentity,
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
        ]
    }
}
