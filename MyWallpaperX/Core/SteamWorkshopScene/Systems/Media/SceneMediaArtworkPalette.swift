import CoreGraphics
import Foundation
import ImageIO

/// A bounded, stateless artwork calculation. Sources own when to extract and
/// cache this value; the palette has no media session or publication authority.
nonisolated struct SceneMediaArtworkPalette: Equatable, Sendable {
    let primaryColor: SIMD3<Double>
    let secondaryColor: SIMD3<Double>
    let tertiaryColor: SIMD3<Double>
    let textColor: SIMD3<Double>
    let highContrastColor: SIMD3<Double>

    private static let maximumEncodedByteCount = 16 * 1_024 * 1_024
    private static let maximumDimension = 8_192
    private static let maximumPixelCount = 16_777_216

    private struct Bucket {
        var weight = 0
        var weightedColor = SIMD3<Double>.zero
    }

    static func extract(from data: Data) -> Self? {
        guard !data.isEmpty, data.count <= maximumEncodedByteCount,
              let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let originalWidth = dimension(properties[kCGImagePropertyPixelWidth]),
              let originalHeight = dimension(properties[kCGImagePropertyPixelHeight]),
              originalWidth <= maximumPixelCount / originalHeight else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              thumbnail.width > 0, thumbnail.width <= 32,
              thumbnail.height > 0, thumbnail.height <= 32,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let bytesPerRow = thumbnail.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * thumbnail.height)
        let drawn = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress, width: thumbnail.width, height: thumbnail.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
            return true
        }
        guard drawn else { return nil }

        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0 else { continue }
            // The context writes premultiplied RGBA8. Recover straight RGB
            // before quantizing so translucent colors retain their hue/value.
            let color = SIMD3<Double>(
                min(1, Double(pixels[offset]) / Double(alpha)),
                min(1, Double(pixels[offset + 1]) / Double(alpha)),
                min(1, Double(pixels[offset + 2]) / Double(alpha))
            )
            let key = (min(15, Int(color.x * 16)) << 8)
                | (min(15, Int(color.y * 16)) << 4)
                | min(15, Int(color.z * 16))
            var bucket = buckets[key, default: Bucket()]
            bucket.weight += alpha
            bucket.weightedColor += color * Double(alpha)
            buckets[key] = bucket
        }

        let ranked = buckets.sorted { lhs, rhs in
            lhs.value.weight == rhs.value.weight
                ? lhs.key < rhs.key : lhs.value.weight > rhs.value.weight
        }.prefix(3).map { $0.value.weightedColor / Double($0.value.weight) }
        // A decoded, fully transparent image is valid artwork. An explicit
        // black/white palette keeps the contrast contract valid in this case.
        let primary = ranked.first ?? .zero
        let secondary = ranked.count > 1 ? ranked[1] : primary
        let tertiary = ranked.count > 2 ? ranked[2] : primary
        let black = SIMD3<Double>.zero
        let white = SIMD3<Double>(repeating: 1)
        let highContrast = contrast(primary, white) > contrast(primary, black) ? white : black
        let text = [secondary, tertiary].first { contrast(primary, $0) >= 4.5 } ?? highContrast
        return Self(primaryColor: primary, secondaryColor: secondary, tertiaryColor: tertiary,
                    textColor: text, highContrastColor: highContrast)
    }

    private static func dimension(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let dimension = number.doubleValue
        guard dimension.isFinite, dimension > 0, dimension <= Double(maximumDimension),
              dimension.rounded(.down) == dimension else { return nil }
        return Int(dimension)
    }

    private static func contrast(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let first = luminance(lhs), second = luminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ color: SIMD3<Double>) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return linear(color.x) * 0.2126 + linear(color.y) * 0.7152 + linear(color.z) * 0.0722
    }
}
