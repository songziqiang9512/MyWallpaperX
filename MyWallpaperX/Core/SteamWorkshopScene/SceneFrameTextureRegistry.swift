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

    private var entries: [SceneFrameTextureIdentity: Entry] = [:]
    private(set) var generation: UInt64 = 0

    @discardableResult
    func beginFrame(
        layerSources: [Int: MTLTexture],
        userPropertyTextures: [String: MTLTexture] = [:],
        systemTextures: [String: MTLTexture] = [:]
    ) -> UInt64 {
        generation &+= 1
        entries.removeAll(keepingCapacity: true)
        layerSources.forEach { layerID, texture in
            set(.ready(texture), for: .layerSource(layerID))
        }
        userPropertyTextures.forEach { key, texture in
            set(.ready(texture), for: .userProperty(key))
        }
        systemTextures.forEach { name, texture in
            set(.ready(texture), for: .system(name))
        }
        return generation
    }

    func set(
        _ status: ProviderStatus,
        for identity: SceneFrameTextureIdentity
    ) {
        entries[identity] = Entry(status: status, generation: generation)
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
}
