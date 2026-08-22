import CoreGraphics
import Foundation
import Metal

/// One provider publication atom. The logical request is exact; all physical
/// resource facts stay on the canonical candidate for one content generation.
nonisolated struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64

    var texture: MTLTexture { candidate.texture }

    var isComplete: Bool {
        guard requestPurposeMatchesCandidate,
              SceneTextureSlotBinding(slotIndex: 0, candidate: candidate) != nil else {
            return false
        }
        switch (candidate.identity, candidate.generation) {
        case (.file, .file), (.builtIn, .immutable):
            return true
        case let (.provider, .provider(generation)):
            return generation == contentGeneration
        default:
            return false
        }
    }

    private var requestPurposeMatchesCandidate: Bool {
        switch requestIdentity {
        case let .asset(identity):
            return identity.purpose == candidate.purpose
        case let .materialUserProperty(identity):
            return identity.purpose == candidate.purpose
        case .layerSource, .namedLayerTarget, .sceneBackground, .graph,
             .userProperty, .system:
            return true
        }
    }

    func isSameAtom(as other: SceneTextureProviderPublication) -> Bool {
        requestIdentity == other.requestIdentity
            && contentGeneration == other.contentGeneration
            && candidate.texture === other.candidate.texture
            && candidate.identity == other.candidate.identity
            && candidate.generation == other.candidate.generation
            && candidate.purpose == other.candidate.purpose
            && candidate.content == other.candidate.content
            && candidate.physicalSize == other.candidate.physicalSize
            && candidate.mappedSize == other.candidate.mappedSize
            && candidate.uvTransform == other.candidate.uvTransform
            && candidate.sampling == other.candidate.sampling
            && candidate.sampling.rawFlags == other.candidate.sampling.rawFlags
            && candidate.authoredFormat == other.candidate.authoredFormat
    }

    var lifecycleIdentity: SceneTextureProviderLifecycleIdentity {
        switch candidate.identity {
        case let .provider(identity):
            return .provider(identity)
        case .file, .builtIn:
            return .versionedResource(
                identity: candidate.identity,
                generation: candidate.generation
            )
        }
    }

    func publication(
        for requestIdentity: SceneFrameTextureIdentity
    ) -> SceneTextureProviderPublication {
        SceneTextureProviderPublication(
            requestIdentity: requestIdentity,
            candidate: candidate,
            contentGeneration: contentGeneration
        )
    }
}

nonisolated enum SceneTextureProviderLifecycleIdentity: Hashable {
    case versionedResource(
        identity: SceneTextureResourceIdentity,
        generation: SceneTextureResourceGeneration
    )
    case provider(SceneTextureProviderIdentity)
}

/// One declared provider state for the current immutable snapshot. A missing
/// identity is therefore distinguishable from an explicitly unready source.
nonisolated enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication)
    case absent
    case pending
    case unavailable
}

/// Value-only launch view of an immutable asset provider state. Capability
/// admission needs absence and failure provenance as well as ready content so
/// it can apply the same candidate precedence as frame selection.
nonisolated enum SceneAssetTextureEffectLocalUnavailable: Hashable {
    case animatedFrameMetadataInvalid
}

nonisolated enum SceneAssetTextureLaunchState: Hashable {
    case ready(SceneTextureContent)
    case absent
    case pending
    case unavailable
    case effectLocalUnavailable(SceneAssetTextureEffectLocalUnavailable)
}

nonisolated struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64

    static func reservedNamedLayerTarget(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64,
        texture: MTLTexture
    ) -> Self? {
        guard frameEpoch > 0,
              reference.variant == .primary,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.mipmapLevelCount == 1,
              texture.usage.contains(.renderTarget),
              texture.usage.contains(.shaderRead),
              texture.pixelFormat == .bgra8Unorm
                || texture.pixelFormat == .rgba8Unorm else { return nil }
        let size = CGSize(width: texture.width, height: texture.height)
        let candidate = SceneTextureCandidate(
            texture: texture,
            identity: .provider(.namedLayerTarget(
                providerLayerID: reference.providerLayerID,
                variant: reference.variant.rawValue,
                frameEpoch: frameEpoch
            )),
            generation: .provider(contentGeneration: frameEpoch),
            purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)),
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: .linearClamp
        )
        let result = Self(
            publication: .init(
                requestIdentity: .namedLayerTarget(reference),
                candidate: candidate,
                contentGeneration: frameEpoch
            ),
            resourceGeneration: frameEpoch
        )
        return result.isCompleteNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch
        ) ? result : nil
    }

    static func sameFrameSceneBackground(
        consumerLayerID: Int,
        frameEpoch: UInt64,
        texture: MTLTexture
    ) -> Self? {
        guard consumerLayerID >= 0,
              frameEpoch > 0,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.mipmapLevelCount == 1,
              texture.usage.contains(.renderTarget),
              texture.usage.contains(.shaderRead),
              texture.pixelFormat == .bgra8Unorm
                || texture.pixelFormat == .rgba8Unorm else { return nil }
        let size = CGSize(width: texture.width, height: texture.height)
        let candidate = SceneTextureCandidate(
            texture: texture,
            identity: .provider(.sceneBackground(
                consumerLayerID: consumerLayerID,
                frameEpoch: frameEpoch
            )),
            generation: .provider(contentGeneration: frameEpoch),
            purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)),
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: .linearClamp
        )
        let result = Self(
            publication: .init(
                requestIdentity: .sceneBackground(consumerLayerID),
                candidate: candidate,
                contentGeneration: frameEpoch
            ),
            resourceGeneration: frameEpoch
        )
        return result.isCompleteSceneBackground(
            consumerLayerID: consumerLayerID,
            frameEpoch: frameEpoch
        ) ? result : nil
    }

    /// Rebinds one already validated graph allocation to another logical graph
    /// request. Swap changes only this request identity; the physical provider,
    /// texture and both generations remain the same immutable atom.
    func rewrappedForGraphIdentity(
        _ identity: SceneAuthoredEffectRenderPlan.TextureIdentity
    ) -> Self? {
        guard isCompleteGraphResource,
              identity.isValidGraphPublicationIdentity else { return nil }
        let result = Self(
            publication: publication.publication(for: .graph(identity)),
            resourceGeneration: resourceGeneration
        )
        return result.isCompleteGraphResource ? result : nil
    }

    var isCompleteGraphResource: Bool {
        guard resourceGeneration > 0,
              resourceGeneration == publication.contentGeneration,
              publication.isComplete,
              case .graph(let request) = publication.requestIdentity,
              request.isValidGraphPublicationIdentity,
              case let .provider(.graph(allocationGeneration, physicalToken)) =
                  publication.candidate.identity,
              allocationGeneration > 0,
              !physicalToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .provider(let generation) = publication.candidate.generation,
              generation == resourceGeneration,
              publication.candidate.physicalSize
                  == publication.candidate.mappedSize,
              publication.candidate.uvTransform == .identity,
              (publication.candidate.sampling == .linearClamp
                || publication.candidate.sampling == .linearRepeat),
              publication.candidate.sampling.rawFlags == nil,
              publication.candidate.texture.usage.contains(.renderTarget),
              publication.candidate.texture.usage.contains(.shaderRead),
              publication.candidate.texture.mipmapLevelCount == 1 else {
            return false
        }
        switch publication.candidate.content {
        case .color(.resolved(.opaque)),
             .color(.resolved(.premultipliedAlpha)),
             .color(.resolved(.independentAlphaSignal)):
            let format = publication.candidate.pixelFormat
            return publication.candidate.purpose == .premultipliedColor
                && (format == .bgra8Unorm || format == .rgba8Unorm)
                && publication.candidate.authoredFormat == nil
                && identityUVScale(expectedPurpose: .premultipliedColor)
        case .scalarRedUnorm:
            return request.kind == .framebuffer
                && publication.candidate.purpose == .preservedChannels
                && publication.candidate.pixelFormat == .r8Unorm
                && publication.candidate.authoredFormat == nil
                && identityUVScale(expectedPurpose: .preservedChannels)
        case .redGreenUnorm:
            return request.kind == .framebuffer
                && publication.candidate.purpose == .preservedChannels
                && publication.candidate.pixelFormat == .rg8Unorm
                && publication.candidate.authoredFormat == nil
                && identityUVScale(expectedPurpose: .preservedChannels)
        case .scalarRedFloat16:
            return request.kind == .framebuffer
                && publication.candidate.purpose == .preservedChannels
                && publication.candidate.pixelFormat == .r16Float
                && publication.candidate.authoredFormat == nil
                && identityUVScale(expectedPurpose: .preservedChannels)
        case .redGreenFloat16:
            return request.kind == .framebuffer
                && publication.candidate.purpose == .preservedChannels
                && publication.candidate.pixelFormat == .rg16Float
                && publication.candidate.authoredFormat == nil
                && identityUVScale(expectedPurpose: .preservedChannels)
        case .data:
            let format = publication.candidate.pixelFormat
            return request.kind == .framebuffer
                && publication.candidate.purpose == .preservedChannels
                && (format == .rgba8Unorm || format == .bgra8Unorm)
                && publication.candidate.authoredFormat == nil
                && identityUVScale(expectedPurpose: .preservedChannels)
        case .color(.resolved(.straightAlpha)), .color(.unresolved):
            return false
        }
    }

    func isCompleteNamedLayerTarget(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64
    ) -> Bool {
        guard frameEpoch > 0,
              reference.variant == .primary,
              resourceGeneration == frameEpoch,
              publication.contentGeneration == frameEpoch,
              publication.requestIdentity == .namedLayerTarget(reference),
              publication.isComplete,
              case let .provider(.namedLayerTarget(
                providerLayerID,
                variant,
                publicationEpoch
              )) = publication.candidate.identity,
              providerLayerID == reference.providerLayerID,
              variant == reference.variant.rawValue,
              publicationEpoch == frameEpoch,
              publication.candidate.purpose == .premultipliedColor,
              publication.candidate.content
                == .color(.resolved(.premultipliedAlpha)),
              publication.candidate.physicalSize
                == publication.candidate.mappedSize,
              publication.candidate.uvTransform == .identity,
              publication.candidate.sampling.isResolvedForMaterialProgram,
              publication.candidate.texture.textureType == .type2D,
              publication.candidate.texture.sampleCount == 1,
              publication.candidate.texture.mipmapLevelCount == 1,
              publication.candidate.texture.usage.contains(.renderTarget),
              publication.candidate.texture.usage.contains(.shaderRead),
              publication.candidate.pixelFormat == .bgra8Unorm
                || publication.candidate.pixelFormat == .rgba8Unorm,
              let scale = publication.candidate.axisAlignedMappedUVScale(
                expectedPurpose: .premultipliedColor
              ),
              scale.x == 1,
              scale.y == 1 else { return false }
        return true
    }

    func isCompleteSceneBackground(
        consumerLayerID: Int,
        frameEpoch: UInt64
    ) -> Bool {
        guard consumerLayerID >= 0,
              frameEpoch > 0,
              resourceGeneration == frameEpoch,
              publication.contentGeneration == frameEpoch,
              publication.requestIdentity == .sceneBackground(consumerLayerID),
              publication.isComplete,
              case let .provider(.sceneBackground(
                  publishedLayerID,
                  publicationEpoch
              )) = publication.candidate.identity,
              publishedLayerID == consumerLayerID,
              publicationEpoch == frameEpoch,
              publication.candidate.purpose == .premultipliedColor,
              publication.candidate.content
                == .color(.resolved(.premultipliedAlpha)),
              publication.candidate.physicalSize
                == publication.candidate.mappedSize,
              publication.candidate.uvTransform == .identity,
              publication.candidate.sampling == .linearClamp,
              publication.candidate.texture.textureType == .type2D,
              publication.candidate.texture.sampleCount == 1,
              publication.candidate.texture.mipmapLevelCount == 1,
              publication.candidate.texture.usage.contains(.renderTarget),
              publication.candidate.texture.usage.contains(.shaderRead),
              publication.candidate.pixelFormat == .bgra8Unorm
                || publication.candidate.pixelFormat == .rgba8Unorm else {
            return false
        }
        return identityUVScale(expectedPurpose: .premultipliedColor)
    }

    private func identityUVScale(
        expectedPurpose: SceneTextureLoadPurpose
    ) -> Bool {
        guard let scale = publication.candidate.axisAlignedMappedUVScale(
            expectedPurpose: expectedPurpose
        ) else { return false }
        return scale.x == 1 && scale.y == 1
    }
}

nonisolated enum SceneFrameTextureIncompleteResource {
    case bare(texture: MTLTexture, resourceGeneration: UInt64)
    case publication(
        SceneTextureProviderPublication,
        resourceGeneration: UInt64
    )
}

nonisolated enum SceneFrameTextureLookupStatus {
    case ready(SceneFrameTextureResource)
    case incomplete(SceneFrameTextureIncompleteResource)
    case absent
    case pending
    case unavailable
}

nonisolated struct SceneFrameTextureRegistrySnapshot {
    let frameEpoch: UInt64
    let frameIndex: UInt64
    let entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus]

    func lookup(_ identity: SceneFrameTextureIdentity) -> SceneFrameTextureLookupStatus? {
        entries[identity]
    }

    func resource(for identity: SceneFrameTextureIdentity) -> SceneFrameTextureResource? {
        guard case let .ready(resource) = entries[identity] else { return nil }
        return resource
    }

    /// Returns a value-only graph overlay. Every replacement is validated
    /// before the copied dictionary is changed, so one invalid graph atom
    /// cannot produce a partial snapshot.
    func overlayingGraphResources(
        _ resources: [
            SceneAuthoredEffectRenderPlan.TextureIdentity: SceneFrameTextureResource
        ]
    ) -> Self? {
        guard resources.allSatisfy({ identity, resource in
            identity.isValidGraphPublicationIdentity
                && resource.publication.requestIdentity == .graph(identity)
                && resource.isCompleteGraphResource
        }) else { return nil }

        var overlaid = entries
        for (identity, resource) in resources {
            overlaid[.graph(identity)] = .ready(resource)
        }
        return Self(
            frameEpoch: frameEpoch,
            frameIndex: frameIndex,
            entries: overlaid
        )
    }

    func overlayingNamedLayerTarget(
        _ reference: SceneNamedTextureReference,
        resource: SceneFrameTextureResource
    ) -> Self? {
        let identity = SceneFrameTextureIdentity.namedLayerTarget(reference)
        guard resource.isCompleteNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch
        ) else { return nil }
        var overlaid = entries
        overlaid[identity] = .ready(resource)
        return Self(
            frameEpoch: frameEpoch,
            frameIndex: frameIndex,
            entries: overlaid
        )
    }

    func overlayingSceneBackground(
        consumerLayerID: Int,
        resource: SceneFrameTextureResource
    ) -> Self? {
        let identity = SceneFrameTextureIdentity.sceneBackground(consumerLayerID)
        guard resource.isCompleteSceneBackground(
            consumerLayerID: consumerLayerID,
            frameEpoch: frameEpoch
        ) else { return nil }
        var overlaid = entries
        overlaid[identity] = .ready(resource)
        return Self(
            frameEpoch: frameEpoch,
            frameIndex: frameIndex,
            entries: overlaid
        )
    }
}

private nonisolated extension SceneAuthoredEffectRenderPlan.TextureIdentity {
    var isValidGraphPublicationIdentity: Bool {
        switch kind {
        case .layerSource:
            return effect == nil && name == nil
        case .effectOutput:
            return validEffect && name == nil
        case .framebuffer:
            return validEffect
                && name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .unresolved:
            return false
        }
    }

    var validEffect: Bool {
        effect?.layerID == layerID
            && (effect?.effectIndex ?? -1) >= 0
            && effect?.descriptorID.isEmpty == false
    }
}
