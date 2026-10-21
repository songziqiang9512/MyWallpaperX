import AppKit
import ImageIO

/// Decode the pixels a grid can display before publishing its image to AppKit.
/// The existing cache continues to own fetches, eviction and source identity.
nonisolated enum GridThumbnailDecoder {
    static func pixelLimit(width: CGFloat, scale: CGFloat) -> Int {
        let pixels = width * scale
        guard pixels.isFinite, pixels > 0 else { return 800 }
        return [256, 512, 800, 1200, 1600, 2400, 3200, 4096].first {
            CGFloat($0) >= pixels
        } ?? 4096
    }

    /// `maxPixelSize` is the target width tier of the existing 16:9 online
    /// card, which stretches its source. Preserve enough pixels on both axes,
    /// including portrait/panorama sources and their authored orientation.
    static func decode(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return NSImage(data: data) }
        let targetWidth = max(1, min(4096, maxPixelSize))
        guard let longestSide = longestSide(for: source, targetWidth: targetWidth,
            targetHeight: targetWidth * 9 / 16) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// ImageIO limits the longest source axis. Aspect-fill consumers need
    /// sufficient pixels on both oriented axes, subject to their existing cap.
    static func longestSide(for source: CGImageSource, targetWidth: Int, targetHeight: Int, maximum: Int = Int.max) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let orientedWidth = (5...8).contains(orientation) ? height : width
        let orientedHeight = (5...8).contains(orientation) ? width : height
        let scale = min(1, max(Double(max(1, targetWidth)) / orientedWidth, Double(max(1, targetHeight)) / orientedHeight))
        // Never decode more pixels than the original path did; preserve the
        // original when an extreme aspect ratio needs its entire short axis.
        let side = ceil(max(width, height) * scale)
        guard side.isFinite, side < Double(Int.max) else { return nil }
        return Int(min(Double(max(1, maximum)), side))
    }
}
