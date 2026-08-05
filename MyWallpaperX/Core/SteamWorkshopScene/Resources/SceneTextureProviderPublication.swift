import Foundation
import Metal

/// One provider publication atom. The logical request is exact; all physical
/// resource facts stay on the canonical candidate for one content generation.
struct SceneTextureProviderPublication {
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
        case .layerSource, .namedLayerTarget, .graph, .userProperty, .system:
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

enum SceneTextureProviderLifecycleIdentity: Hashable {
    case versionedResource(
        identity: SceneTextureResourceIdentity,
        generation: SceneTextureResourceGeneration
    )
    case provider(SceneTextureProviderIdentity)
}

/// One declared provider state for the current immutable snapshot. A missing
/// identity is therefore distinguishable from an explicitly unready source.
enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication)
    case absent
    case pending
    case unavailable
}

struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64

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
              publication.candidate.purpose == .premultipliedColor,
              publication.candidate.physicalSize
                  == publication.candidate.mappedSize,
              publication.candidate.uvTransform == .identity,
              publication.candidate.sampling == .directImageFallback,
              publication.candidate.sampling.rawFlags == nil,
              publication.candidate.texture.usage.contains(.renderTarget),
              publication.candidate.texture.mipmapLevelCount == 1,
              let uvScale = publication.candidate.axisAlignedMappedUVScale(
                  expectedPurpose: .premultipliedColor
              ), uvScale.x == 1, uvScale.y == 1 else {
            return false
        }
        switch publication.candidate.content {
        case .color(.resolved(.opaque)),
             .color(.resolved(.premultipliedAlpha)),
             .color(.resolved(.independentAlphaSignal)):
            return true
        case .color(.resolved(.straightAlpha)), .color(.unresolved), .data:
            return false
        }
    }
}

enum SceneFrameTextureIncompleteResource {
    case bare(texture: MTLTexture, resourceGeneration: UInt64)
    case publication(
        SceneTextureProviderPublication,
        resourceGeneration: UInt64
    )
}

enum SceneFrameTextureLookupStatus {
    case ready(SceneFrameTextureResource)
    case incomplete(SceneFrameTextureIncompleteResource)
    case absent
    case pending
    case unavailable
}

struct SceneFrameTextureRegistrySnapshot {
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
}

private extension SceneAuthoredEffectRenderPlan.TextureIdentity {
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
