import Metal

/// Alpha representation carried by texture publications and authored shader
/// boundaries. Storage format alone never determines this value.
nonisolated enum SceneShaderColorRepresentation: String, Codable, Hashable, Sendable {
    case opaque
    case straightAlpha = "straight-alpha"
    case premultipliedAlpha = "premultiplied-alpha"
    case independentAlphaSignal = "independent-alpha-signal"
}

nonisolated enum SceneShaderColorRepresentationResolution: Codable, Hashable, Sendable {
    case unresolved
    case resolved(SceneShaderColorRepresentation)

    var isResolved: Bool {
        guard case .resolved = self else { return false }
        return true
    }
}

nonisolated struct SceneTextureSampling: Equatable, Hashable, Sendable {
    enum Filter: String, Equatable, Sendable {
        case linear
        case nearest
    }

    enum AddressMode: String, Equatable, Sendable {
        case clampToEdge
        case repeatWrap
    }

    let filter: Filter
    let addressMode: AddressMode
    let usesClampBorderFallback: Bool
    /// Exact authored TEX flags. Direct image uploads have no authored flag word.
    let rawFlags: UInt32?

    /// R3 Program admission is intentionally narrower than the legacy sampler.
    /// Only the proven no-interpolation and clamp-UV bits are executable.
    var isResolvedForMaterialProgram: Bool {
        guard let rawFlags else { return true }
        return rawFlags & ~UInt32(0b11) == 0
    }

    /// Preserve the legacy effective-sampler equality used by existing image
    /// routes. Program admission inspects `rawFlags` separately before use.
    static func == (lhs: SceneTextureSampling, rhs: SceneTextureSampling) -> Bool {
        lhs.filter == rhs.filter
            && lhs.addressMode == rhs.addressMode
            && lhs.usesClampBorderFallback == rhs.usesClampBorderFallback
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(filter)
        hasher.combine(addressMode)
        hasher.combine(usesClampBorderFallback)
    }

    static let directImageFallback = SceneTextureSampling(
        filter: .linear,
        addressMode: .clampToEdge,
        usesClampBorderFallback: false,
        rawFlags: nil
    )
    static let linearClamp = directImageFallback
    static let linearRepeat = SceneTextureSampling(
        filter: .linear,
        addressMode: .repeatWrap,
        usesClampBorderFallback: false,
        rawFlags: nil
    )

    init(texFlags: UInt32) {
        rawFlags = texFlags
        filter = texFlags & 1 == 0 ? .linear : .nearest
        usesClampBorderFallback = texFlags & 8 != 0
        addressMode = usesClampBorderFallback || texFlags & 2 != 0
            ? .clampToEdge
            : .repeatWrap
    }

    private init(
        filter: Filter,
        addressMode: AddressMode,
        usesClampBorderFallback: Bool,
        rawFlags: UInt32?
    ) {
        self.filter = filter
        self.addressMode = addressMode
        self.usesClampBorderFallback = usesClampBorderFallback
        self.rawFlags = rawFlags
    }
}

struct SceneTextureSamplerStateSet {
    private let linearClamp: MTLSamplerState
    private let linearRepeat: MTLSamplerState
    private let nearestClamp: MTLSamplerState
    private let nearestRepeat: MTLSamplerState

    init?(device: MTLDevice) {
        guard let linearClamp = Self.makeState(
            device: device,
            filter: .linear,
            addressMode: .clampToEdge
        ), let linearRepeat = Self.makeState(
            device: device,
            filter: .linear,
            addressMode: .repeatWrap
        ), let nearestClamp = Self.makeState(
            device: device,
            filter: .nearest,
            addressMode: .clampToEdge
        ), let nearestRepeat = Self.makeState(
            device: device,
            filter: .nearest,
            addressMode: .repeatWrap
        ) else {
            return nil
        }
        self.linearClamp = linearClamp
        self.linearRepeat = linearRepeat
        self.nearestClamp = nearestClamp
        self.nearestRepeat = nearestRepeat
    }

    func state(for sampling: SceneTextureSampling) -> MTLSamplerState {
        switch (sampling.filter, sampling.addressMode) {
        case (.linear, .clampToEdge): linearClamp
        case (.linear, .repeatWrap): linearRepeat
        case (.nearest, .clampToEdge): nearestClamp
        case (.nearest, .repeatWrap): nearestRepeat
        }
    }

    private static func makeState(
        device: MTLDevice,
        filter: SceneTextureSampling.Filter,
        addressMode: SceneTextureSampling.AddressMode
    ) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.normalizedCoordinates = true
        let metalFilter: MTLSamplerMinMagFilter = filter == .nearest ? .nearest : .linear
        descriptor.minFilter = metalFilter
        descriptor.magFilter = metalFilter
        descriptor.mipFilter = filter == .nearest ? .nearest : .linear
        let metalAddress: MTLSamplerAddressMode = addressMode == .repeatWrap
            ? .repeat
            : .clampToEdge
        descriptor.sAddressMode = metalAddress
        descriptor.tAddressMode = metalAddress
        descriptor.rAddressMode = metalAddress
        return device.makeSamplerState(descriptor: descriptor)
    }
}
