import Metal

struct SceneParticleSamplerStateSet {
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

    func state(for sampling: SceneParticleTextureSampling) -> MTLSamplerState {
        switch (sampling.filter, sampling.addressMode) {
        case (.linear, .clampToEdge): return linearClamp
        case (.linear, .repeatWrap): return linearRepeat
        case (.nearest, .clampToEdge): return nearestClamp
        case (.nearest, .repeatWrap): return nearestRepeat
        }
    }

    private static func makeState(
        device: MTLDevice,
        filter: SceneParticleTextureSampling.Filter,
        addressMode: SceneParticleTextureSampling.AddressMode
    ) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.normalizedCoordinates = true
        let metalFilter: MTLSamplerMinMagFilter = filter == .nearest ? .nearest : .linear
        descriptor.minFilter = metalFilter
        descriptor.magFilter = metalFilter
        descriptor.mipFilter = .notMipmapped
        let metalAddress: MTLSamplerAddressMode = addressMode == .repeatWrap
            ? .repeat
            : .clampToEdge
        descriptor.sAddressMode = metalAddress
        descriptor.tAddressMode = metalAddress
        descriptor.rAddressMode = metalAddress
        return device.makeSamplerState(descriptor: descriptor)
    }
}
