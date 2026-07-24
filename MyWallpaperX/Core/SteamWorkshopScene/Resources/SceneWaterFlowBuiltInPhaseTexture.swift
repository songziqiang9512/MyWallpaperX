import Metal

enum SceneWaterFlowBuiltInPhaseTexture {
    static let normalRingSmoothPath = "particle/normal_ring_smooth"

    static func make(path: String, device: MTLDevice) -> MTLTexture? {
        guard normalized(path) == normalRingSmoothPath else { return nil }
        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Scene Water Flow built-in normal_ring_smooth"

        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let normalizedX = (Float(x) + 0.5) / Float(size) * 2 - 1
                let normalizedY = (Float(y) + 0.5) / Float(size) * 2 - 1
                pixels[y * size + x] = phaseValue(
                    radius: min(hypot(normalizedX, normalizedY), 1)
                )
            }
        }
        pixels.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: address,
                bytesPerRow: size
            )
        }
        return texture
    }

    nonisolated static func phaseValue(radius: Float) -> UInt8 {
        let inner = 0.14 + 0.86 * smoothstep(edge0: 0, edge1: 0.68, value: radius)
        let outer = 1 - smoothstep(edge0: 0.60, edge1: 0.96, value: radius)
        let phase = min(max(0.8 * inner * outer, 0), 1)
        return UInt8((phase * 255).rounded())
    }

    private nonisolated static func smoothstep(
        edge0: Float,
        edge1: Float,
        value: Float
    ) -> Float {
        let amount = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return amount * amount * (3 - 2 * amount)
    }

    private static func normalized(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
    }
}
