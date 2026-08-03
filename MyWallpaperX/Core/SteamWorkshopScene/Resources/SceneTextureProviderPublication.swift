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
}
