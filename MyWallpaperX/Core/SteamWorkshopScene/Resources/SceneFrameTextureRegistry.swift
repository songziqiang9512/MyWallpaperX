import Metal

/// Exact frame lookup identity for one system-owned texture representation.
/// Purpose is part of the identity because one provider source may publish
/// independent color and data representations for different consumers.
nonisolated struct SceneSystemProviderTextureIdentity: Hashable, Sendable {
    let name: String
    let purpose: SceneTextureLoadPurpose

    var reportToken: String {
        "system:\(name.utf8.count)#\(name):\(purpose.reportToken)"
    }
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(SceneSystemProviderTextureIdentity)

    var reportToken: String {
        switch self {
        case let .layerSource(layerID):
            return "layer:\(layerID)"
        case let .namedLayerTarget(reference):
            return "named:\(reference.providerLayerID):\(reference.variant.rawValue)"
        case let .sceneBackground(consumerLayerID):
            return "scene-background:\(consumerLayerID)"
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
        case let .system(identity):
            return identity.reportToken
        }
    }
}

final class SceneFrameTextureRegistry {
    /// Bare status is reserved for layer sources and named render targets.
    /// Material providers publish a complete SceneTextureProviderPublication.
    enum ProviderStatus {
        case ready(MTLTexture)
        case absent
        case pending
        case unavailable
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

    /// Launch/topology-stable dictionary key order. Provider status and
    /// publication values remain frame-live; only the sorting work is reused
    /// while the identity set is unchanged.
    private struct OrderedKeyCache<Key: Hashable> {
        private var keySet: Set<Key> = []
        private var orderedKeys: [Key] = []

        mutating func resolve(
            _ current: Set<Key>,
            by areInIncreasingOrder: (Key, Key) -> Bool
        ) -> [Key] {
            guard keySet != current else { return orderedKeys }
            keySet = current
            orderedKeys = current.sorted(by: areInIncreasingOrder)
            return orderedKeys
        }
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
    private var orderedLayerSourceIDs = OrderedKeyCache<Int>()
    private var orderedAssetIdentities = OrderedKeyCache<SceneAssetTextureIdentity>()
    private var orderedUserPropertyTextureKeys = OrderedKeyCache<String>()
    private var orderedUserPropertyIdentities = OrderedKeyCache<SceneUserPropertyTextureIdentity>()
    private var orderedSystemTextureIdentities = OrderedKeyCache<SceneSystemProviderTextureIdentity>()
    private var orderedSystemProviderIdentities = OrderedKeyCache<SceneSystemProviderTextureIdentity>()
    private var resourceGeneration: UInt64 = 0
    private struct FramePublicationBaseline {
        let persistentEntries: [SceneFrameTextureIdentity: PersistentEntry]
        let priorFrameEntries: [SceneFrameTextureIdentity: PersistentEntry]
        let committedPublications: [SceneFrameTextureIdentity: PersistentEntry]
        let resourceGeneration: UInt64
    }
    private var framePublicationBaseline: FramePublicationBaseline?
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
        systemTextures: [SceneSystemProviderTextureIdentity: MTLTexture] = [:],
        explicitSystemTextures: [
            SceneSystemProviderTextureIdentity: SceneTextureProviderPublication
        ] = [:],
        systemProviderStates: [
            SceneSystemProviderTextureIdentity: SceneTextureProviderState
        ] = [:]
    ) -> UInt64 {
        if framePublicationBaseline != nil {
            commitFramePublication()
        }
        framePublicationBaseline = FramePublicationBaseline(
            persistentEntries: persistentEntries,
            priorFrameEntries: priorFrameEntries,
            committedPublications: committedPublications,
            resourceGeneration: resourceGeneration
        )
        frameEpoch &+= 1
        self.frameIndex = frameIndex
        entries.removeAll(keepingCapacity: true)
        priorFrameEntries = persistentEntries
        persistentEntries.removeAll(keepingCapacity: true)
        for layerID in orderedLayerSourceIDs.resolve(
            Set(layerSources.keys), by: <
        ) {
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
        for identity in orderedAssetIdentities.resolve(
            Set(assetStates.keys), by: { $0.reportToken < $1.reportToken }
        ) {
            guard let state = assetStates[identity] else { continue }
            publish(state, for: .asset(identity))
        }
        for key in orderedUserPropertyTextureKeys.resolve(
            Set(userPropertyTextures.keys), by: <
        ) {
            guard let texture = userPropertyTextures[key] else { continue }
            publishPersistent(texture, for: .userProperty(key))
        }
        for identity in orderedUserPropertyIdentities.resolve(
            Set(userPropertyStates.keys), by: { $0.reportToken < $1.reportToken }
        ) {
            guard let state = userPropertyStates[identity] else { continue }
            publish(state, for: .materialUserProperty(identity))
        }
        for systemIdentity in orderedSystemTextureIdentities.resolve(
            Set(systemTextures.keys), by: { $0.reportToken < $1.reportToken }
        ) {
            guard let texture = systemTextures[systemIdentity] else { continue }
            let identity = SceneFrameTextureIdentity.system(systemIdentity)
            if let publication = explicitSystemTextures[systemIdentity] {
                guard publication.texture === texture else { continue }
                publishExplicit(publication, for: identity)
            } else {
                publishPersistent(texture, for: identity)
            }
        }
        for systemIdentity in orderedSystemProviderIdentities.resolve(
            Set(systemProviderStates.keys), by: { $0.reportToken < $1.reportToken }
        ) {
            guard let state = systemProviderStates[systemIdentity] else {
                continue
            }
            publish(state, for: .system(systemIdentity))
        }
        return frameEpoch
    }

    /// Keeps the current frame's provider publications visible to the next
    /// frame only after the host accepts every surface submission.
    func commitFramePublication() {
        framePublicationBaseline = nil
    }

    /// Restores the last accepted publication set after a local or host-level
    /// frame failure. The frame epoch remains monotonic, so stale candidates
    /// cannot cross the next frame's identity boundary.
    func discardFramePublication() {
        guard let baseline = framePublicationBaseline else { return }
        persistentEntries = baseline.persistentEntries
        priorFrameEntries = baseline.priorFrameEntries
        committedPublications = baseline.committedPublications
        resourceGeneration = baseline.resourceGeneration
        entries.removeAll(keepingCapacity: true)
        framePublicationBaseline = nil
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

    /// Publishes a graph-owned named target as a complete typed provider atom.
    /// Graph output is copied into the frame reservation before this method is
    /// called; the reservation identity, epoch and Metal resource contract are
    /// therefore validated once at the registry boundary instead of falling
    /// back to an incomplete bare texture entry.
    @discardableResult
    func publishReservedNamedLayerTarget(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64,
        texture: MTLTexture
    ) -> Bool {
        guard frameEpoch == self.frameEpoch,
              let resource = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch,
            texture: texture
        ) else { return false }
        let identity = SceneFrameTextureIdentity.namedLayerTarget(reference)
        set(resource.publication, for: identity)
        return self.resource(for: identity)?.isCompleteNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch
        ) == true
    }

    /// Returns a named-target texture only when the current frame contains a
    /// complete typed publication for the exact reference. Bare entries stay
    /// visible to layer-source plumbing but cannot cross a material/provider
    /// consumer boundary.
    func completeNamedLayerTargetTexture(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64
    ) -> MTLTexture? {
        guard frameEpoch == self.frameEpoch,
              let resource = resource(
                  for: .namedLayerTarget(reference)
              ),
              resource.isCompleteNamedLayerTarget(
                  reference: reference,
                  frameEpoch: frameEpoch
              ) else { return nil }
        return resource.publication.texture
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
