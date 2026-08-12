import Metal

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(String)

    var reportToken: String {
        switch self {
        case let .layerSource(layerID):
            return "layer:\(layerID)"
        case let .namedLayerTarget(reference):
            return "named:\(reference.providerLayerID):\(reference.variant.rawValue)"
        case let .graph(identity):
            let effect = identity.effect.map {
                "\($0.layerID):\($0.effectIndex):\($0.descriptorID.utf8.count)#\($0.descriptorID)"
            } ?? "-"
            let name = identity.name.map { "\($0.utf8.count)#\($0)" } ?? "-"
            return "graph:\(identity.kind.rawValue):\(identity.layerID):\(effect):\(name)"
        case let .asset(identity):
            return identity.reportToken
        case let .userProperty(key):
            return "property:\(key)"
        case let .materialUserProperty(identity):
            return identity.reportToken
        case let .system(name):
            return "system:\(name)"
        }
    }
}

/// Transitional ordered selection retained for generic legacy provider
/// resolution until R5 cleanup. A producer must explicitly publish `absent`
/// before resolution may advance to the next authored candidate.
nonisolated struct SceneFrameTextureSelection: Hashable {
    let candidates: [SceneFrameTextureIdentity]

    init(candidates: [SceneFrameTextureIdentity]) {
        self.candidates = candidates
    }
}

final class SceneFrameTextureRegistry {
    /// Transitional bare-texture status. Typed providers publish a complete
    /// SceneTextureProviderPublication instead.
    enum ProviderStatus {
        case ready(MTLTexture)
        case absent
        case pending
        case unavailable
    }

    /// Transitional candidate-resolution result retained for the legacy binder.
    struct Resolution {
        let identity: SceneFrameTextureIdentity
        let texture: MTLTexture
        let generation: UInt64
        let candidateIndex: Int

        var usedFallback: Bool { candidateIndex > 0 }
    }

    private enum StoredResource {
        case bare(MTLTexture)
        case publication(SceneTextureProviderPublication)

        var texture: MTLTexture {
            switch self {
            case let .bare(texture):
                return texture
            case let .publication(publication):
                return publication.texture
            }
        }

    }

    private struct Entry {
        let status: ProviderStatus
        let generation: UInt64
        let resource: PersistentEntry?
    }

    private struct PersistentEntry {
        let stored: StoredResource
        let generation: UInt64

        var lookupStatus: SceneFrameTextureLookupStatus {
            switch stored {
            case let .bare(texture):
                return .incomplete(.bare(
                    texture: texture,
                    resourceGeneration: generation
                ))
            case let .publication(publication):
                guard publication.isComplete else {
                    return .incomplete(.publication(
                        publication,
                        resourceGeneration: generation
                    ))
                }
                return .ready(SceneFrameTextureResource(
                    publication: publication,
                    resourceGeneration: generation
                ))
            }
        }
    }

    private var entries: [SceneFrameTextureIdentity: Entry] = [:]
    private var persistentEntries: [SceneFrameTextureIdentity: PersistentEntry] = [:]
    private var priorFrameEntries: [SceneFrameTextureIdentity: PersistentEntry] = [:]
    private var committedPublications: [
        SceneFrameTextureIdentity: PersistentEntry
    ] = [:]
    private var resourceGeneration: UInt64 = 0
    private(set) var frameEpoch: UInt64 = 0
    private(set) var frameIndex: UInt64 = 0

    @discardableResult
    func beginFrame(
        frameIndex: UInt64,
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
        frameEpoch &+= 1
        self.frameIndex = frameIndex
        entries.removeAll(keepingCapacity: true)
        priorFrameEntries = persistentEntries
        persistentEntries.removeAll(keepingCapacity: true)
        for layerID in layerSources.keys.sorted() {
            guard let texture = layerSources[layerID] else { continue }
            let identity = SceneFrameTextureIdentity.layerSource(layerID)
            if let publication = explicitLayerSources[layerID] {
                guard publication.texture === texture,
                      publication.requestIdentity == identity else { continue }
                publishExplicit(publication, for: identity)
                let graphIdentity = SceneAuthoredEffectRenderPlan.TextureIdentity(
                    kind: .layerSource,
                    layerID: layerID,
                    effect: nil,
                    name: nil
                )
                let graphRequest = SceneFrameTextureIdentity.graph(graphIdentity)
                publishExplicit(
                    publication.publication(for: graphRequest),
                    for: graphRequest
                )
            } else {
                publishPersistent(texture, for: identity)
            }
        }
        for identity in assetStates.keys.sorted(by: {
            $0.reportToken < $1.reportToken
        }) {
            guard let state = assetStates[identity] else { continue }
            publish(state, for: .asset(identity))
        }
        for key in userPropertyTextures.keys.sorted() {
            guard let texture = userPropertyTextures[key] else { continue }
            publishPersistent(texture, for: .userProperty(key))
        }
        for identity in userPropertyStates.keys.sorted(by: {
            $0.reportToken < $1.reportToken
        }) {
            guard let state = userPropertyStates[identity] else { continue }
            publish(state, for: .materialUserProperty(identity))
        }
        for name in systemTextures.keys.sorted() {
            guard let texture = systemTextures[name] else { continue }
            let identity = SceneFrameTextureIdentity.system(name)
            if let publication = explicitSystemTextures[name] {
                guard publication.texture === texture else { continue }
                publishExplicit(publication, for: identity)
            } else {
                publishPersistent(texture, for: identity)
            }
        }
        return frameEpoch
    }

    func set(
        _ status: ProviderStatus,
        for identity: SceneFrameTextureIdentity
    ) {
        let resource: PersistentEntry?
        switch status {
        case let .ready(texture):
            resource = PersistentEntry(
                stored: .bare(texture),
                generation: frameEpoch
            )
        case .absent, .pending, .unavailable:
            resource = nil
        }
        entries[identity] = Entry(
            status: status,
            generation: frameEpoch,
            resource: resource
        )
    }

    func set(
        _ publication: SceneTextureProviderPublication,
        for identity: SceneFrameTextureIdentity
    ) {
        publishExplicit(publication, for: identity)
    }

    func lookup(_ identity: SceneFrameTextureIdentity) -> SceneFrameTextureLookupStatus? {
        guard let entry = entries[identity] else { return nil }
        switch entry.status {
        case .ready:
            return entry.resource?.lookupStatus
        case .absent:
            return .absent
        case .pending:
            return .pending
        case .unavailable:
            return .unavailable
        }
    }

    func resource(for identity: SceneFrameTextureIdentity) -> SceneFrameTextureResource? {
        guard case let .ready(resource) = lookup(identity) else { return nil }
        return resource
    }

    func snapshot() -> SceneFrameTextureRegistrySnapshot {
        SceneFrameTextureRegistrySnapshot(
            frameEpoch: frameEpoch,
            frameIndex: frameIndex,
            entries: entries.reduce(into: [:]) { result, pair in
                if let status = lookup(pair.key) {
                    result[pair.key] = status
                }
            }
        )
    }

    func texture(for identity: SceneFrameTextureIdentity) -> MTLTexture? {
        guard case let .ready(texture) = entries[identity]?.status else { return nil }
        return texture
    }

    func resolve(_ selection: SceneFrameTextureSelection) -> Resolution? {
        for (index, identity) in selection.candidates.enumerated() {
            guard let entry = entries[identity] else { return nil }
            switch entry.status {
            case .absent:
                continue
            case .pending, .unavailable:
                return nil
            case let .ready(texture):
                guard let resource = entry.resource else { return nil }
                switch resource.lookupStatus {
                case .ready:
                    break
                case .incomplete(.bare):
                    guard case .layerSource = identity else { return nil }
                case .incomplete(.publication):
                    return nil
                case .absent, .pending, .unavailable:
                    return nil
                }
                return Resolution(
                    identity: identity,
                    texture: texture,
                    generation: entry.generation,
                    candidateIndex: index
                )
            }
        }
        return nil
    }

    private func publishPersistent(
        _ texture: MTLTexture,
        for identity: SceneFrameTextureIdentity
    ) {
        let generation: UInt64
        if let previous = priorFrameEntries[identity],
           case let .bare(previousTexture) = previous.stored,
           previousTexture === texture {
            generation = previous.generation
        } else {
            resourceGeneration &+= 1
            generation = resourceGeneration
        }
        let resource = PersistentEntry(
            stored: .bare(texture),
            generation: generation
        )
        publish(resource, for: identity)
    }

    private func publishExplicit(
        _ publication: SceneTextureProviderPublication,
        for identity: SceneFrameTextureIdentity
    ) {
        guard publication.requestIdentity == identity else { return }
        if let previous = committedPublications[identity],
           case let .publication(previousPublication) = previous.stored {
            let sameLifecycle = publication.lifecycleIdentity
                == previousPublication.lifecycleIdentity
            if sameLifecycle,
               publication.contentGeneration <= previousPublication.contentGeneration {
                publish(previous, for: identity)
                return
            }
            if obsoleteVideoLifecycle(publication, previous: previousPublication) {
                publish(previous, for: identity)
                return
            }
        }

        resourceGeneration &+= 1
        let resource = PersistentEntry(
            stored: .publication(publication),
            generation: resourceGeneration
        )
        committedPublications[identity] = resource
        publish(resource, for: identity)
    }

    private func publish(
        _ state: SceneTextureProviderState,
        for identity: SceneFrameTextureIdentity
    ) {
        switch state {
        case let .ready(publication):
            publishExplicit(publication, for: identity)
        case .absent:
            set(.absent, for: identity)
        case .pending:
            set(.pending, for: identity)
        case .unavailable:
            set(.unavailable, for: identity)
        }
    }

    private func obsoleteVideoLifecycle(
        _ publication: SceneTextureProviderPublication,
        previous: SceneTextureProviderPublication
    ) -> Bool {
        guard case let .provider(.video(incomingLayer, incomingEpoch)) =
                publication.lifecycleIdentity,
              case let .provider(.video(previousLayer, previousEpoch)) =
                previous.lifecycleIdentity,
              incomingLayer == previousLayer else {
            return false
        }
        return incomingEpoch < previousEpoch
    }

    private func publish(
        _ resource: PersistentEntry,
        for identity: SceneFrameTextureIdentity
    ) {
        persistentEntries[identity] = resource
        entries[identity] = Entry(
            status: .ready(resource.stored.texture),
            generation: resource.generation,
            resource: resource
        )
    }
}
