import Metal

nonisolated struct SceneTextureSampling: Equatable, Sendable {
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

    static let directImageFallback = SceneTextureSampling(
        filter: .linear,
        addressMode: .clampToEdge,
        usesClampBorderFallback: false
    )
    static let linearClamp = directImageFallback
    static let linearRepeat = SceneTextureSampling(
        filter: .linear,
        addressMode: .repeatWrap,
        usesClampBorderFallback: false
    )

    init(texFlags: UInt32) {
        filter = texFlags & 1 == 0 ? .linear : .nearest
        usesClampBorderFallback = texFlags & 8 != 0
        addressMode = usesClampBorderFallback || texFlags & 2 != 0
            ? .clampToEdge
            : .repeatWrap
    }

    private init(
        filter: Filter,
        addressMode: AddressMode,
        usesClampBorderFallback: Bool
    ) {
        self.filter = filter
        self.addressMode = addressMode
        self.usesClampBorderFallback = usesClampBorderFallback
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
