import CoreGraphics
import Metal
import simd

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
              !path.contains(":"),
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

nonisolated enum SceneTextureProviderIdentity: Hashable, Sendable {
    case dynamicText(layerID: Int)
    case graph(allocationGeneration: UInt64, physicalToken: String)
    case mediaThumbnailCurrent
    case video(layerID: Int, lifecycleEpoch: UInt64)

    var reportToken: String {
        switch self {
        case let .dynamicText(layerID):
            return "dynamic-text:\(layerID)"
        case let .graph(allocationGeneration, physicalToken):
            return "graph:allocation:\(allocationGeneration):"
                + "physical:\(physicalToken.utf8.count)#\(physicalToken)"
        case .mediaThumbnailCurrent:
            return "media-thumbnail:current"
        case let .video(layerID, lifecycleEpoch):
            return "video:\(layerID):epoch:\(lifecycleEpoch)"
        }
    }
}

nonisolated enum SceneTextureResourceIdentity: Hashable, Sendable {
    case file(path: String)
    case builtIn(name: String)
    case provider(SceneTextureProviderIdentity)
}

nonisolated struct SceneTextureFileRevision: Hashable, Sendable {
    let fileSystemID: UInt64
    let fileID: UInt64
    let statusChangedAtSeconds: Int64
    let statusChangedAtNanoseconds: Int64
}

nonisolated enum SceneTextureResourceGeneration: Hashable, Sendable {
    case file(
        byteCount: UInt64,
        modifiedAtBits: UInt64,
        revision: SceneTextureFileRevision
    )
    case immutable(revision: UInt64)
    case provider(contentGeneration: UInt64)
}

nonisolated enum SceneTextureContent: Hashable, Sendable {
    case color(SceneShaderColorRepresentationResolution)
    /// One normalized red component stored by a graph-owned R8 target.
    /// Metal exposes unspecified sampled components as G=0, B=0, A=1, but
    /// those backend defaults are not part of this scalar graph semantic.
    case scalarRedUnorm
    case data

    var isResolved: Bool {
        switch self {
        case let .color(resolution):
            return resolution.isResolved
        case .scalarRedUnorm, .data:
            return true
        }
    }
}

/// Immutable texture and slot metadata published as one value. Consumers must
/// validate the expected purpose and UV shape before splitting the binding into
/// Metal arguments, so generation, sampler, and mapped extent cannot drift
/// independently from the texture.
nonisolated struct SceneTextureCandidate {
    let texture: MTLTexture
    let identity: SceneTextureResourceIdentity
    let generation: SceneTextureResourceGeneration
    let purpose: SceneTextureLoadPurpose
    let content: SceneTextureContent
    let physicalSize: CGSize
    let mappedSize: CGSize
    let uvTransform: SceneTextureUVTransform
    let sampling: SceneTextureSampling
    let authoredFormat: SceneShaderTextureFormat?

    init(
        texture: MTLTexture,
        identity: SceneTextureResourceIdentity,
        generation: SceneTextureResourceGeneration,
        purpose: SceneTextureLoadPurpose,
        content: SceneTextureContent,
        physicalSize: CGSize,
        mappedSize: CGSize,
        uvTransform: SceneTextureUVTransform,
        sampling: SceneTextureSampling,
        authoredFormat: SceneShaderTextureFormat? = nil
    ) {
        self.texture = texture
        self.identity = identity
        self.generation = generation
        self.purpose = purpose
        self.content = content
        self.physicalSize = physicalSize
        self.mappedSize = mappedSize
        self.uvTransform = uvTransform
        self.sampling = sampling
        self.authoredFormat = authoredFormat
    }

    var pixelFormat: MTLPixelFormat { texture.pixelFormat }

    func axisAlignedMappedUVScale(
        expectedPurpose: SceneTextureLoadPurpose
    ) -> SIMD2<Float>? {
        guard purpose == expectedPurpose,
              valid(physicalSize),
              valid(mappedSize),
              mappedSize.width <= physicalSize.width,
              mappedSize.height <= physicalSize.height,
              Int(physicalSize.width.rounded()) == texture.width,
              Int(physicalSize.height.rounded()) == texture.height else {
            return nil
        }
        let expected = SIMD2<Float>(
            Float(mappedSize.width / physicalSize.width),
            Float(mappedSize.height / physicalSize.height)
        )
        guard finite(uvTransform.origin),
              finite(uvTransform.xAxis),
              finite(uvTransform.yAxis),
              near(uvTransform.origin, .zero),
              near(uvTransform.xAxis, SIMD2(expected.x, 0)),
              near(uvTransform.yAxis, SIMD2(0, expected.y)),
              expected.x > 0,
              expected.y > 0,
              expected.x <= 1,
              expected.y <= 1 else {
            return nil
        }
        return expected
    }

    var diagnosticSummary: String {
        let scale = axisAlignedMappedUVScale(expectedPurpose: purpose) ?? .zero
        return "purpose=\(purpose.diagnosticName)"
            + " content=\(content.diagnosticName)"
            + " physical=\(Int(physicalSize.width))x\(Int(physicalSize.height))"
            + " mapped=\(Int(mappedSize.width))x\(Int(mappedSize.height))"
            + " uvScale=\(scale.x),\(scale.y)"
            + " sampling=\(sampling.filter.rawValue)/\(sampling.addressMode.rawValue)"
            + " pixelFormat=\(pixelFormat.rawValue)"
            + " authoredFormat=\(authoredFormat.map { String($0.rawValue) } ?? "none")"
    }

    private func valid(_ size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
            && size.width.rounded() == size.width
            && size.height.rounded() == size.height
    }

    private func finite(_ value: SIMD2<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite
    }

    private func near(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
        abs(lhs.x - rhs.x) <= 0.000_001
            && abs(lhs.y - rhs.y) <= 0.000_001
    }
}

private nonisolated extension SceneTextureContent {
    var diagnosticName: String {
        switch self {
        case .color(.unresolved):
            return "color/unresolved"
        case let .color(.resolved(representation)):
            return "color/\(representation.rawValue)"
        case .scalarRedUnorm:
            return "scalar-red-unorm"
        case .data:
            return "data"
        }
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

private nonisolated extension SceneTextureLoadPurpose {
    var diagnosticName: String {
        switch self {
        case .premultipliedColor: "premultipliedColor"
        case .straightAlbedo: "straightAlbedo"
        case .preservedChannels: "preservedChannels"
        case .mask: "mask"
        case .noise: "noise"
        case .flow: "flow"
        case .phase: "phase"
        case .normal: "normal"
        case .depth: "depth"
        default: "unsupported"
        }
    }
}
