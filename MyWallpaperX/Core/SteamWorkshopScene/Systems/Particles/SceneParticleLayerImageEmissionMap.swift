import Foundation
import Metal

// 发射点按 alpha 加权抽取（构建期前缀和 + 采样期二分查找）。按 alpha 加权为 project-owned
// bounded approximation：官方像素权重语义未定案（alpha 加权 / 等权 / alpha×亮度三候选），
// 黑盒三贴图实验待判别，合同与退役条件见 client-runtime-static-forensics.md §5.13；
// 若判别为等权/亮度加权，本实现整体替换。
nonisolated struct SceneParticleLayerImageEmissionMap: Sendable {
    private static let maximumPixelCount = 1_048_576
    let positions: [SIMD3<Double>]
    private let cumulativeWeights: [Double]

    nonisolated init?(texture: MTLTexture, sourceSize: SIMD2<Double>) {
        guard texture.textureType == .type2D,
              texture.depth == 1, texture.arrayLength == 1, texture.sampleCount == 1,
              texture.width > 0, texture.height > 0,
              texture.width <= Self.maximumPixelCount / texture.height,
              texture.storageMode == .shared || texture.storageMode == .managed,
              sourceSize.x.isFinite, sourceSize.y.isFinite,
              sourceSize.x > 0, sourceSize.y > 0 else { return nil }
        let bytes: Data
        switch texture.pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb:
            var pixels = Data(count: texture.width * texture.height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                texture.getBytes(
                    buffer.baseAddress!, bytesPerRow: texture.width * 4,
                    from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                    mipmapLevel: 0
                )
            }
            bytes = pixels
        case .bc1_rgba, .bc2_rgba, .bc3_rgba:
            // Only this bounded CPU consumer needs RGBA. Keep the published
            // source compressed and reuse the loader's decoder at preparation.
            let format: SceneBCTextureDecoder.Format = texture.pixelFormat == .bc1_rgba
                ? .bc1 : (texture.pixelFormat == .bc2_rgba ? .bc2 : .bc3)
            let blocksWide = (texture.width + 3) / 4
            let blocksHigh = (texture.height + 3) / 4
            var blocks = Data(count: blocksWide * blocksHigh * format.bytesPerBlock)
            blocks.withUnsafeMutableBytes { buffer in
                texture.getBytes(
                    buffer.baseAddress!, bytesPerRow: blocksWide * format.bytesPerBlock,
                    from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                    mipmapLevel: 0
                )
            }
            guard let decoded = SceneBCTextureDecoder.decode(
                blockData: blocks, storedWidth: texture.width, storedHeight: texture.height,
                imageWidth: texture.width, imageHeight: texture.height, format: format
            ) else { return nil }
            bytes = decoded.rgba
        default:
            return nil
        }
        var points: [SIMD3<Double>] = []
        var cumulativeWeights: [Double] = []
        var cumulativeWeight = 0.0
        bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for y in 0..<texture.height {
                for x in 0..<texture.width {
                    let alpha = buffer[(y * texture.width + x) * 4 + 3]
                    guard alpha > 0 else { continue }
                    points.append(SIMD3(
                        (Double(x) + 0.5) / Double(texture.width) * sourceSize.x
                            - sourceSize.x * 0.5,
                        sourceSize.y * 0.5
                            - (Double(y) + 0.5) / Double(texture.height) * sourceSize.y,
                        0
                    ))
                    cumulativeWeight += Double(alpha)
                    cumulativeWeights.append(cumulativeWeight)
                }
            }
        }
        guard !points.isEmpty else { return nil }
        positions = points
        self.cumulativeWeights = cumulativeWeights
    }

    nonisolated init(positions: [SIMD3<Double>]) {
        self.positions = positions.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        cumulativeWeights = self.positions.indices.map { Double($0 + 1) }
    }

    nonisolated func sample(using random: inout SceneParticleRandomGenerator) -> SIMD3<Double>? {
        guard let totalWeight = cumulativeWeights.last else { return nil }
        let target = random.unit() * totalWeight
        var low = 0
        var high = cumulativeWeights.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulativeWeights[mid] <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return positions[low]
    }
}
