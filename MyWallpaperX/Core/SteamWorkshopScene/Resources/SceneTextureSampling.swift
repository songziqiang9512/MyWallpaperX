import Metal

/// Authored Wallpaper Engine texture-format value preserved from a TEX
/// container. This is intentionally separate from a decoded GPU pixel format:
/// decoding may change physical representation while shader variants still
/// branch on the source container format.
nonisolated enum SceneShaderTextureFormat: UInt32, Codable, CaseIterable,
    Hashable, Sendable {
    case rgba8888 = 0
    case rgb888 = 1
    case rgb565 = 2
    case etc1 = 3
    case dxt5 = 4
    case etc2 = 5
    case dxt3 = 6
    case dxt1 = 7
    case rg88 = 8
    case r8 = 9
    case rg1616f = 10
    case r16f = 11
    case bc7 = 12

    var macroValue: Int { Int(rawValue) }
}

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

    /// Program admission accepts filter/address plus the known TEX animation
    /// metadata bit after frame-provider lowering. All other bits fail closed.
    var isResolvedForMaterialProgram: Bool {
        guard let rawFlags else { return true }
        return rawFlags & ~UInt32(0b111) == 0
    }

    /// Preserve the effective-sampler equality used by direct image
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
