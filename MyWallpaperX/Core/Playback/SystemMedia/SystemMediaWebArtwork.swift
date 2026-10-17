import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum SystemMediaWebArtwork {
    /// Prepared once on the utility queue. Scene retains the original bytes;
    /// only Web needs the small self-contained PNG accepted by img.src.
    static func dataURL(from data: Data) -> String? {
        guard data.count <= SystemMediaSnapshotStore.maximumEncodedByteCount,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8_192, height <= 8_192,
              width * height <= 16 * 1_024 * 1_024,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 1_024 * 1_024 else { return nil }
        return "data:image/png;base64," + (output as Data).base64EncodedString()
    }
}
