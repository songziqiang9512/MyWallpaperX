import Foundation
import Metal

nonisolated struct SceneParticleLayerImageEmissionMap: Sendable {
    private static let maximumPixelCount = 1_048_576
    let positions: [SIMD3<Double>]

    nonisolated init?(texture: MTLTexture, sourceSize: SIMD2<Double>) {
        guard texture.textureType == .type2D,
              texture.depth == 1, texture.arrayLength == 1, texture.sampleCount == 1,
              texture.width > 0, texture.height > 0,
              texture.width * texture.height <= Self.maximumPixelCount,
              texture.storageMode == .shared || texture.storageMode == .managed,
              sourceSize.x.isFinite, sourceSize.y.isFinite,
              sourceSize.x > 0, sourceSize.y > 0 else { return nil }
        switch texture.pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb:
            break
        default:
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        var points: [SIMD3<Double>] = []
        for y in 0..<texture.height {
            for x in 0..<texture.width where bytes[(y * texture.width + x) * 4 + 3] > 0 {
                points.append(SIMD3(
                    (Double(x) + 0.5) / Double(texture.width) * sourceSize.x
                        - sourceSize.x * 0.5,
                    sourceSize.y * 0.5
                        - (Double(y) + 0.5) / Double(texture.height) * sourceSize.y,
                    0
                ))
            }
        }
        guard !points.isEmpty else { return nil }
        positions = points
    }

    nonisolated init(positions: [SIMD3<Double>]) {
        self.positions = positions.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    }

    nonisolated func sample(using random: inout SceneParticleRandomGenerator) -> SIMD3<Double>? {
        guard !positions.isEmpty else { return nil }
        return positions[min(Int(random.unit() * Double(positions.count)), positions.count - 1)]
    }
}
