import Metal

final class SceneParticleBuiltInTextureRegistry {
    private let device: MTLDevice
    private var dropTexture: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
    }

    func texture(for builtInTexture: SceneParticleBuiltInTexture) -> MTLTexture? {
        switch builtInTexture {
        case .drop:
            if let dropTexture {
                return dropTexture
            }
            let texture = makeDropTexture()
            dropTexture = texture
            return texture
        }
    }

    private func makeDropTexture() -> MTLTexture? {
        let size = 32
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "Scene particle built-in drop"

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let normalizedX = (Float(x) + 0.5) / Float(size) * 2 - 1
                let normalizedY = (Float(y) + 0.5) / Float(size) * 2 - 1
                let radiusSquared = normalizedX * normalizedX + normalizedY * normalizedY
                let remaining = min(max(1 - radiusSquared, 0), 1)
                let alpha = remaining * remaining * (3 - 2 * remaining)
                let component = UInt8((alpha * 255).rounded())
                let offset = (y * size + x) * 4
                pixels[offset] = component
                pixels[offset + 1] = component
                pixels[offset + 2] = component
                pixels[offset + 3] = component
            }
        }

        pixels.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: address,
                bytesPerRow: size * 4
            )
        }
        return texture
    }
}
