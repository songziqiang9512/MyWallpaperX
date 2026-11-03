extension Harness {
    static func currentAndPersistentCases(
        device: MTLDevice,
        registry: SceneFrameTextureRegistry,
        fallbackTexture: MTLTexture,
        replacementFallbackTexture: MTLTexture,
        propertyTexture: MTLTexture,
        replacementPropertyTexture: MTLTexture,
        systemTexture: MTLTexture,
        replacementSystemTexture: MTLTexture,
        namedTexture: MTLTexture,
        dynamicTexture: MTLTexture,
        replacementDynamicTexture: MTLTexture,
        staleDynamicTexture: MTLTexture
    ) -> (graphLayerSource: SceneFrameTextureIdentity, result: [String: Any]) {
        let optionalPropertyIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "cover",
            purpose: .premultipliedColor
        )!
        let optionalProperty = SceneFrameTextureIdentity.materialUserProperty(
            optionalPropertyIdentity
        )
        let persistentProperty = SceneFrameTextureIdentity.userProperty("persistent-cover")
        let systemProviderIdentity = SceneSystemProviderTextureIdentity(
            name: "$mediaThumbnail",
            purpose: .premultipliedColor
        )
        let system = SceneFrameTextureIdentity.system(systemProviderIdentity)
        let fallback = SceneFrameTextureIdentity.layerSource(7)
        let dynamic = SceneFrameTextureIdentity.layerSource(8)
        let firstEpoch = registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: [systemProviderIdentity: systemTexture]
        )
        let firstFallback = bareResolution(registry, fallback)!
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
        registry.set(.absent, for: optionalProperty)
        let absentIsExplicit: Bool
        if case .absent = registry.snapshot().lookup(optionalProperty) {
            absentIsExplicit = true
        } else {
            absentIsExplicit = false
        }
        registry.set(.pending, for: optionalProperty)
        let pending = registry.resource(for: optionalProperty)
        registry.set(.unavailable, for: optionalProperty)
        let unavailable = registry.resource(for: optionalProperty)
        registry.set(
            publication(
                propertyTexture,
                generation: 2,
                requestIdentity: optionalProperty,
                candidateGeneration: .provider(contentGeneration: 1)
            ),
            for: optionalProperty
        )
        let incomplete = registry.resource(for: optionalProperty)
        registry.set(.ready(propertyTexture), for: optionalProperty)
        let bareExactProperty = registry.resource(for: optionalProperty)
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
        let ready = typedResolution(registry, optionalProperty)

        let primary = SceneNamedTextureReference(providerLayerID: 42, variant: .primary)
        let secondary = SceneNamedTextureReference(providerLayerID: 42, variant: .secondary)
        let named = SceneFrameTextureIdentity.namedLayerTarget(primary)
        registry.set(.ready(namedTexture), for: named)
        let firstNamed = bareResolution(registry, named)!
        let primaryReady = registry.texture(for: named) === namedTexture
        let secondaryIsolated = registry.texture(
            for: .namedLayerTarget(secondary)
        ) == nil

        let namedResult = namedPublicationCases(
            device: device,
            primary: primary,
            secondary: secondary,
            named: named,
            fallbackTexture: fallbackTexture,
            propertyTexture: propertyTexture,
            systemProviderIdentity: systemProviderIdentity,
            systemTexture: systemTexture,
            namedTexture: namedTexture
        )
        let secondEpoch = registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: [systemProviderIdentity: systemTexture]
        )
        let secondFallback = bareResolution(registry, fallback)!
        let secondProperty = bareResolution(registry, persistentProperty)!
        let secondSystem = bareResolution(registry, system)!
        let namedCleared = registry.texture(for: named) == nil
        registry.set(.ready(namedTexture), for: named)
        let secondNamed = bareResolution(registry, named)!

        registry.beginFrame(
            layerSources: [7: replacementFallbackTexture],
            userPropertyTextures: ["persistent-cover": replacementPropertyTexture],
            systemTextures: [systemProviderIdentity: replacementSystemTexture]
        )
        let replacedFallback = bareResolution(registry, fallback)!
        let replacedProperty = bareResolution(registry, persistentProperty)!
        let replacedSystem = bareResolution(registry, system)!

        registry.beginFrame(layerSources: [:])
        let persistentEntriesCleared = registry.texture(for: fallback) == nil
            && registry.texture(for: persistentProperty) == nil
            && registry.texture(for: system) == nil

        registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: [systemProviderIdentity: systemTexture]
        )
        let restoredFallback = bareResolution(registry, fallback)!
        let restoredProperty = bareResolution(registry, persistentProperty)!
        let restoredSystem = bareResolution(registry, system)!

        registry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(dynamicTexture, generation: 10)
            ]
        )
        let firstDynamic = typedResolution(registry, dynamic)!
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
        let secondDynamic = typedResolution(registry, dynamic)!
        registry.beginFrame(
            layerSources: [8: dynamicTexture],
            explicitLayerSources: [
                8: publication(dynamicTexture, generation: 11)
            ]
        )
        let repeatedDynamic = typedResolution(registry, dynamic)!
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
        let sameGenerationDynamic = typedResolution(registry, dynamic)!
        registry.beginFrame(
            layerSources: [8: staleDynamicTexture],
            explicitLayerSources: [
                8: publication(staleDynamicTexture, generation: 9)
            ]
        )
        let lowerProducerGenerationDynamic = typedResolution(registry, dynamic)!
        registry.beginFrame(
            layerSources: [8: replacementDynamicTexture],
            explicitLayerSources: [
                8: publication(staleDynamicTexture, generation: 12)
            ]
        )
        let mismatchedPublicationRejected = registry.resource(for: dynamic) == nil

        registry.beginFrame(
            layerSources: [:],
            systemTextures: [systemProviderIdentity: systemTexture],
            explicitSystemTextures: [
                systemProviderIdentity: publication(
                    systemTexture,
                    generation: 20,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let firstExplicitSystem = typedResolution(registry, system)!
        registry.beginFrame(
            layerSources: [:],
            systemTextures: [systemProviderIdentity: systemTexture],
            explicitSystemTextures: [
                systemProviderIdentity: publication(
                    systemTexture,
                    generation: 21,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let secondExplicitSystem = typedResolution(registry, system)!
        registry.beginFrame(
            layerSources: [:],
            systemTextures: [systemProviderIdentity: replacementSystemTexture],
            explicitSystemTextures: [
                systemProviderIdentity: publication(
                    replacementSystemTexture,
                    generation: 21,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let replacedSameGenerationSystem = typedResolution(registry, system)!
        registry.beginFrame(
            layerSources: [:],
            systemTextures: [systemProviderIdentity: replacementSystemTexture],
            explicitSystemTextures: [
                systemProviderIdentity: publication(
                    replacementSystemTexture,
                    generation: 19,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                )
            ]
        )
        let lowerProducerGenerationSystem = typedResolution(registry, system)!

        let preservedSystemProviderIdentity = SceneSystemProviderTextureIdentity(
            name: "$mediaThumbnail",
            purpose: .preservedChannels
        )
        let preservedSystem = SceneFrameTextureIdentity.system(
            preservedSystemProviderIdentity
        )
        registry.beginFrame(
            layerSources: [:],
            systemTextures: [
                systemProviderIdentity: systemTexture,
                preservedSystemProviderIdentity: replacementSystemTexture,
            ],
            explicitSystemTextures: [
                systemProviderIdentity: publication(
                    systemTexture,
                    generation: 22,
                    requestIdentity: system,
                    identity: .provider(.mediaThumbnailCurrent)
                ),
                preservedSystemProviderIdentity: publication(
                    replacementSystemTexture,
                    generation: 22,
                    requestIdentity: preservedSystem,
                    identity: .provider(.mediaThumbnailCurrent),
                    purpose: .preservedChannels,
                    content: .data
                ),
            ]
        )
        let exactColorSystem = registry.resource(for: system)
        let exactPreservedSystem = registry.resource(for: preservedSystem)
        let systemPurposesDoNotAlias =
            exactColorSystem?.publication.texture === systemTexture
            && exactColorSystem?.publication.candidate.purpose
                == .premultipliedColor
            && exactPreservedSystem?.publication.texture
                === replacementSystemTexture
            && exactPreservedSystem?.publication.candidate.purpose
                == .preservedChannels
            && system.reportToken != preservedSystem.reportToken

        let purposeMismatchedSystemPublication = publication(
            systemTexture,
            generation: 23,
            requestIdentity: preservedSystem,
            identity: .provider(.mediaThumbnailCurrent)
        )
        registry.set(purposeMismatchedSystemPublication, for: preservedSystem)
        let systemPurposeMismatchRemainsTypedReady =
            registry.resource(for: preservedSystem)?.publication.candidate.purpose
                == .premultipliedColor

        let previousSystemProviderIdentity = SceneSystemProviderTextureIdentity(
            name: "$mediaPreviousThumbnail",
            purpose: .preservedChannels
        )
        let previousSystem = SceneFrameTextureIdentity.system(
            previousSystemProviderIdentity
        )
        registry.set(publication(
            replacementSystemTexture,
            generation: 24,
            requestIdentity: previousSystem,
            identity: .provider(.mediaThumbnailCurrent),
            purpose: .preservedChannels,
            content: .data
        ), for: previousSystem)
        let currentCandidateCannotSatisfyPreviousRequest: Bool
        if case .incomplete = registry.lookup(previousSystem) {
            currentCandidateCannotSatisfyPreviousRequest =
                registry.resource(for: previousSystem) == nil
        } else {
            currentCandidateCannotSatisfyPreviousRequest = false
        }
        registry.set(publication(
            replacementSystemTexture,
            generation: 25,
            requestIdentity: previousSystem,
            identity: .provider(.mediaThumbnailPrevious),
            purpose: .preservedChannels,
            content: .data
        ), for: previousSystem)
        let exactPreviousCandidateIsReady =
            registry.resource(for: previousSystem)?.publication.candidate.identity
                == .provider(.mediaThumbnailPrevious)
        var result: [String: Any] = [
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
            "missingIsNotAbsent": missingIsNotAbsent,
            "absentIsExplicit": absentIsExplicit,
            "pendingFailsClosed": pending == nil,
            "unavailableFailsClosed": unavailable == nil,
            "incompleteFailsClosed": incomplete == nil,
            "bareExactPropertyFailsClosed": bareExactProperty == nil,
            "readyOverride": ready?.texture === propertyTexture,
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
            "systemPurposesDoNotAlias": systemPurposesDoNotAlias,
            "systemPurposeMismatchRemainsTypedReady":
                systemPurposeMismatchRemainsTypedReady,
            "currentCandidateCannotSatisfyPreviousRequest":
                currentCandidateCannotSatisfyPreviousRequest,
            "exactPreviousCandidateIsReady": exactPreviousCandidateIsReady,
        ]
        result.merge(namedResult) { _, new in new }
        return (graphLayerSource, result)
    }
}
