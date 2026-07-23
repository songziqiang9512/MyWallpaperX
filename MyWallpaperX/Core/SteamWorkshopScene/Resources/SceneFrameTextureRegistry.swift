import Metal

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case userProperty(String)
    case system(String)

    var reportToken: String {
        switch self {
        case let .layerSource(layerID):
            return "layer:\(layerID)"
        case let .namedLayerTarget(reference):
            return "named:\(reference.providerLayerID):\(reference.variant.rawValue)"
        case let .userProperty(key):
            return "property:\(key)"
        case let .system(name):
            return "system:\(name)"
        }
    }
}

nonisolated struct SceneFrameTextureSelection: Hashable {
    let candidates: [SceneFrameTextureIdentity]

    init(candidates: [SceneFrameTextureIdentity]) {
        self.candidates = candidates
    }
}

final class SceneFrameTextureRegistry {
    enum ProviderStatus {
        case ready(MTLTexture)
        case pending
        case unavailable
    }

    struct Resolution {
        let identity: SceneFrameTextureIdentity
        let texture: MTLTexture
        let generation: UInt64
        let candidateIndex: Int

        var usedFallback: Bool { candidateIndex > 0 }
    }

    private struct Entry {
        let status: ProviderStatus
        let generation: UInt64
    }

    private struct PersistentEntry {
        let texture: MTLTexture
        let generation: UInt64
    }

    private var entries: [SceneFrameTextureIdentity: Entry] = [:]
    private var persistentEntries: [SceneFrameTextureIdentity: PersistentEntry] = [:]
    private var resourceGeneration: UInt64 = 0
    private(set) var frameEpoch: UInt64 = 0

    @discardableResult
    func beginFrame(
        layerSources: [Int: MTLTexture],
        userPropertyTextures: [String: MTLTexture] = [:],
        systemTextures: [String: MTLTexture] = [:]
    ) -> UInt64 {
        frameEpoch &+= 1
        entries.removeAll(keepingCapacity: true)
        let previousPersistentEntries = persistentEntries
        persistentEntries.removeAll(keepingCapacity: true)
        layerSources.forEach { layerID, texture in
            publishPersistent(
                texture,
                for: .layerSource(layerID),
                previousEntries: previousPersistentEntries
            )
        }
        userPropertyTextures.forEach { key, texture in
            publishPersistent(
                texture,
                for: .userProperty(key),
                previousEntries: previousPersistentEntries
            )
        }
        systemTextures.forEach { name, texture in
            publishPersistent(
                texture,
                for: .system(name),
                previousEntries: previousPersistentEntries
            )
        }
        return frameEpoch
    }

    func set(
        _ status: ProviderStatus,
        for identity: SceneFrameTextureIdentity
    ) {
        entries[identity] = Entry(status: status, generation: frameEpoch)
    }

    func texture(for identity: SceneFrameTextureIdentity) -> MTLTexture? {
        guard case let .ready(texture) = entries[identity]?.status else { return nil }
        return texture
    }

    func resolve(_ selection: SceneFrameTextureSelection) -> Resolution? {
        for (index, identity) in selection.candidates.enumerated() {
            guard let entry = entries[identity],
                  case let .ready(texture) = entry.status else { continue }
            return Resolution(
                identity: identity,
                texture: texture,
                generation: entry.generation,
                candidateIndex: index
            )
        }
        return nil
    }

    private func publishPersistent(
        _ texture: MTLTexture,
        for identity: SceneFrameTextureIdentity,
        previousEntries: [SceneFrameTextureIdentity: PersistentEntry]
    ) {
        let generation: UInt64
        if let previous = previousEntries[identity], previous.texture === texture {
            generation = previous.generation
        } else {
            resourceGeneration &+= 1
            generation = resourceGeneration
        }
        persistentEntries[identity] = PersistentEntry(
            texture: texture,
            generation: generation
        )
        entries[identity] = Entry(status: .ready(texture), generation: generation)
    }
}
