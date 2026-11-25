import CoreGraphics
import Foundation
import ImageIO

/// A bounded, stateless artwork calculation. Sources own when to extract and
/// cache this value; the palette has no media session or publication authority.
nonisolated struct SystemMediaArtworkPalette: Equatable, Sendable {
    let primaryColor: SIMD3<Double>
    let secondaryColor: SIMD3<Double>
    let tertiaryColor: SIMD3<Double>
    let textColor: SIMD3<Double>
    let highContrastColor: SIMD3<Double>

    private static let maximumEncodedByteCount = 16 * 1_024 * 1_024
    private static let maximumDimension = 8_192
    private static let maximumPixelCount = 16_777_216
    private static let analysisEdge = 150
    private static let minimumRoleContrast = 2.5

    private struct HueBucket {
        var weight = 0
        var count = 0
        var saturationSum: Float = 0
        var valueSum: Float = 0

        mutating func add(saturation: Float, value: Float) {
            weight += Int(value * saturation * 100)
            count += 1
            saturationSum += saturation
            valueSum += value
        }

        func color(hue: Int) -> SIMD3<Double> {
            let saturation = Double(saturationSum / Float(count))
            let value = Double(valueSum / Float(count))
            let chroma = saturation * value
            let position = Double(hue) / 60
            let intermediate = chroma * (1 - abs(position.truncatingRemainder(dividingBy: 2) - 1))
            let components: SIMD3<Double>
            switch hue / 60 {
            case 0: components = .init(chroma, intermediate, 0)
            case 1: components = .init(intermediate, chroma, 0)
            case 2: components = .init(0, chroma, intermediate)
            case 3: components = .init(0, intermediate, chroma)
            case 4: components = .init(intermediate, 0, chroma)
            default: components = .init(chroma, 0, intermediate)
            }
            let rgb = (components + (value - chroma)) * 255
            return .init(rgb.x.rounded(.down) / 255, rgb.y.rounded(.down) / 255, rgb.z.rounded(.down) / 255)
        }
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
            kCGImageSourceThumbnailMaxPixelSize: analysisEdge,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              thumbnail.width > 0, thumbnail.width <= analysisEdge,
              thumbnail.height > 0, thumbnail.height <= analysisEdge,
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

        var buckets = Array(repeating: HueBucket(), count: 360)
        for x in 0..<thumbnail.width {
            for offset in stride(from: x * 4, to: pixels.count, by: bytesPerRow) {
                let alpha = pixels[offset + 3]
                guard alpha >= 16 else { continue }
                // The bitmap context stores premultiplied channels.
                let rgb = SIMD3<Float>(Float(pixels[offset]), Float(pixels[offset + 1]),
                                       Float(pixels[offset + 2])) / Float(alpha)
                let value = max(rgb.x, rgb.y, rgb.z)
                let chroma = value - min(rgb.x, rgb.y, rgb.z)
                let hue = hueBin(rgb, value: value, chroma: chroma)
                buckets[hue].add(saturation: chroma > 0 ? chroma / value : 0, value: value)
            }
        }

        let primaryHue = buckets.indices.max { buckets[$0].weight < buckets[$1].weight } ?? 0
        let secondaryHue = accent(in: buckets) { hueDistance($0, primaryHue) }
        let tertiaryHue = accent(in: buckets) {
            let distance = hueDistance($0, primaryHue) * hueDistance($0, secondaryHue ?? 0)
            return distance * distance
        }
        let primary = buckets[primaryHue].weight > 0 ? buckets[primaryHue].color(hue: primaryHue) : .zero
        let secondary = secondaryHue.map { buckets[$0].color(hue: $0) } ?? .zero
        let tertiary = tertiaryHue.map { buckets[$0].color(hue: $0) } ?? .zero
        let primaryLuminance = luminance(primary)
        let highContrast: SIMD3<Double> = contrast(primaryLuminance, 0) >= minimumRoleContrast
            ? .zero : .init(repeating: 1)
        let secondaryContrast = contrast(primaryLuminance, luminance(secondary))
        let tertiaryContrast = contrast(primaryLuminance, luminance(tertiary))
        let text: SIMD3<Double>
        if secondaryContrast >= minimumRoleContrast, secondaryContrast > tertiaryContrast {
            text = secondary
        } else if tertiaryContrast >= minimumRoleContrast {
            text = tertiary
        } else {
            text = highContrast
        }
        return Self(primaryColor: primary, secondaryColor: secondary, tertiaryColor: tertiary,
                    textColor: text, highContrastColor: highContrast)
    }

    private static func hueBin(_ rgb: SIMD3<Float>, value: Float, chroma: Float) -> Int {
        guard chroma > 0 else { return 0 }
        let section: Float
        if value == rgb.x {
            section = (rgb.y - rgb.z) / chroma
        } else if value == rgb.y {
            section = (rgb.z - rgb.x) / chroma + 2
        } else {
            section = (rgb.x - rgb.y) / chroma + 4
        }
        let fraction = section / 6
        return min(359, Int((fraction < 0 ? fraction + 1 : fraction) * 360))
    }

    private static func hueDistance(_ lhs: Int, _ rhs: Int) -> Float {
        let degrees = abs(lhs - rhs)
        return Float(min(degrees, 360 - degrees)) / 180
    }

    private static func accent(in buckets: [HueBucket], separation: (Int) -> Float) -> Int? {
        var bestScore = 0
        var bestHue: Int?
        for hue in buckets.indices {
            let score = Float(buckets[hue].weight) * separation(hue)
            if score > Float(bestScore) {
                // The observed ranking compares the new score with the prior truncated score.
                bestScore = Int(score)
                bestHue = hue
            }
        }
        return bestHue
    }

    private static func dimension(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let dimension = number.doubleValue
        guard dimension.isFinite, dimension > 0, dimension <= Double(maximumDimension),
              dimension.rounded(.down) == dimension else { return nil }
        return Int(dimension)
    }

    private static func contrast(_ lhs: Double, _ rhs: Double) -> Double {
        (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    private static func luminance(_ color: SIMD3<Double>) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return linear(color.x) * 0.2126 + linear(color.y) * 0.7152 + linear(color.z) * 0.0722
    }
}
