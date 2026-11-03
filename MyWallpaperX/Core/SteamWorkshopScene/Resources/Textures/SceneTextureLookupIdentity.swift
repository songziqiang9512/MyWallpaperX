import Foundation

/// Canonical identity for one safe relative path in the Scene virtual resource
/// namespace. It is an identity value only; resolving it to an URL remains the
/// responsibility of `SceneResourceView`.
nonisolated struct SceneVFSAssetPath: Hashable, Sendable {
    let value: String

    init?(_ rawValue: String) {
        var path = rawValue.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        value = components.joined(separator: "/").lowercased()
    }
}

/// Purpose is part of the lookup identity because one authored asset may be
/// decoded into different representations for color and data consumers.
nonisolated struct SceneAssetTextureIdentity: Hashable, Sendable {
    let path: SceneVFSAssetPath
    let purpose: SceneTextureLoadPurpose

    init(path: SceneVFSAssetPath, purpose: SceneTextureLoadPurpose) {
        self.path = path
        self.purpose = purpose
    }

    init?(virtualPath: String, purpose: SceneTextureLoadPurpose) {
        guard let path = SceneVFSAssetPath(virtualPath) else { return nil }
        self.init(path: path, purpose: purpose)
    }

    var reportToken: String {
        "asset:\(path.value):\(purpose.reportToken)"
    }
}

/// A user-authored property key is qualified by the representation requested
/// by the consumer. The same source URL may therefore publish more than one
/// non-aliasing resource atom.
nonisolated struct SceneUserPropertyTextureIdentity: Hashable, Sendable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose

    init?(propertyKey rawKey: String, purpose: SceneTextureLoadPurpose) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !key.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            return nil
        }
        propertyKey = key
        self.purpose = purpose
    }

    var reportToken: String {
        "property:\(propertyKey.utf8.count)#\(propertyKey):\(purpose.reportToken)"
    }
}

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var isDataPurpose: Bool {
        switch self {
        case .preservedChannels, .mask, .noise, .flow, .phase, .normal,
             .depth, .lookupTable:
            true
        case .premultipliedColor, .straightAlbedo:
            false
        }
    }

    var preservesSourceChannels: Bool {
        switch self {
        case .premultipliedColor:
            false
        case .straightAlbedo, .preservedChannels, .mask, .noise, .flow, .phase,
             .normal, .depth, .lookupTable:
            true
        }
    }

    var requiresVolumeTexture: Bool {
        self == .lookupTable
    }
}

nonisolated extension SceneTextureLoadPurpose {
    init?(reportToken: String) {
        switch reportToken {
        case "premultiplied-color": self = .premultipliedColor
        case "straight-albedo": self = .straightAlbedo
        case "preserved-channels": self = .preservedChannels
        case "mask": self = .mask
        case "noise": self = .noise
        case "flow": self = .flow
        case "phase": self = .phase
        case "normal": self = .normal
        case "depth": self = .depth
        case "lookup-table": self = .lookupTable
        default: return nil
        }
    }

    var reportToken: String {
        switch self {
        case .premultipliedColor: "premultiplied-color"
        case .straightAlbedo: "straight-albedo"
        case .preservedChannels: "preserved-channels"
        case .mask: "mask"
        case .noise: "noise"
        case .flow: "flow"
        case .phase: "phase"
        case .normal: "normal"
        case .depth: "depth"
        case .lookupTable: "lookup-table"
        }
    }

}

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
