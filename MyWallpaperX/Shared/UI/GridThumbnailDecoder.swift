import AppKit
import ImageIO

nonisolated enum ThumbnailInput: @unchecked Sendable {
    case sourceFile(URL, onFailure: (() -> Void)? = nil)
    case preparedFile(URL, nativeSize: CGSize?)
    case image(NSImage, nativeSize: CGSize? = nil)
    case sourceData(Data)

    var persistsImage: Bool {
        if case .preparedFile = self { return false }
        return true
    }
}

nonisolated enum GridThumbnailDecoder {
    nonisolated struct Image: @unchecked Sendable {
        let image: NSImage
        let pixels: CGSize
        let cost: Int
        let nativeSize: CGSize?
        let crop: ThumbnailRequest?

        init?(_ image: NSImage, nativeSize: CGSize?, crop: ThumbnailRequest? = nil) {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            self.image = image
            self.pixels = CGSize(width: cg.width, height: cg.height)
            self.cost = cg.bytesPerRow * cg.height
            self.nativeSize = nativeSize
            self.crop = crop
        }
    }

    static func pixelLimit(width: CGFloat, scale: CGFloat) -> Int {
        let pixels = width * scale
        guard pixels.isFinite, pixels > 0 else { return 800 }
        return [256, 512, 800, 1200, 1600, 2400, 3200, 4096].first { CGFloat($0) >= pixels } ?? 4096
    }

    static func decodeInput(_ input: ThumbnailInput, request: ThumbnailRequest?) -> Image? {
        switch input {
        case .sourceFile(let url, let onFailure):
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = sourceImage(source, request: request, minimumLongestSide: 512) else {
                onFailure?()
                return nil
            }
            return image
        case .preparedFile(let url, let nativeSize):
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            return sourceImage(source, request: request, nativeSize: nativeSize, isOriginal: false)
        case .sourceData(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary) else {
                return NSImage(data: data).flatMap { Image($0, nativeSize: nil) }
            }
            return sourceImage(source, request: request)
        case .image(let image, let nativeSize):
            guard let decoded = Image(image, nativeSize: nativeSize),
                  request.map({ $0.isCovered(by: decoded.pixels, nativeSize: nativeSize) }) ?? true else { return nil }
            return decoded
        }
    }

    static func decodeStoredImage(_ data: Data, request: ThumbnailRequest?) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return sourceImage(source, request: request, isOriginal: false)
    }

    private static func nativeSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func sourceImage(_ source: CGImageSource, request: ThumbnailRequest?,
                                    minimumLongestSide: Int = 0, nativeSize: CGSize? = nil,
                                    isOriginal: Bool = true) -> Image? {
        guard let storedSize = self.nativeSize(of: source) else { return nil }
        let native = isOriginal ? storedSize : nativeSize
        guard request.map({ $0.isCovered(by: storedSize, nativeSize: native) }) ?? true else { return nil }
        let size = request?.decodedSize(for: storedSize, minimumLongestSide: minimumLongestSide)
            ?? (minimumLongestSide > 0
                ? ThumbnailRequest(width: minimumLongestSide, height: minimumLongestSide, mode: .fit).decodedSize(for: storedSize)
                : storedSize)
        let longest = max(size.width, size.height)
        guard longest.isFinite, longest < CGFloat(Int.max),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(longest),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return Image(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), nativeSize: native)
    }

    /// Fill owns only the requested pixels; fit preserves the complete source frame.
    static func render(_ input: Image, request: ThumbnailRequest?) -> Image? {
        guard let request else { return input }
        guard request.isCovered(by: input.pixels, nativeSize: input.nativeSize) else { return nil }
        guard let source = input.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = source.colorSpace else { return input }
        let size: CGSize
        if request.mode == .fill {
            let scale = min(1, min(input.pixels.width / CGFloat(request.width), input.pixels.height / CGFloat(request.height)))
            size = CGSize(width: max(1, floor(CGFloat(request.width) * scale)),
                          height: max(1, floor(CGFloat(request.height) * scale)))
        } else {
            size = request.decodedSize(for: input.pixels)
            if size == input.pixels { return input }
        }
        var bitmapInfo = source.bitmapInfo
        if space.model == .rgb {
            let alpha: CGImageAlphaInfo
            switch source.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: alpha = .noneSkipLast
            default: alpha = .premultipliedLast
            }
            bitmapInfo = CGBitmapInfo(rawValue: (bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue) | alpha.rawValue)
        }
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: source.bitsPerComponent, bytesPerRow: 0,
            space: space, bitmapInfo: bitmapInfo.rawValue) else { return input }
        let scale = request.mode == .fill
            ? max(size.width / input.pixels.width, size.height / input.pixels.height)
            : min(size.width / input.pixels.width, size.height / input.pixels.height)
        let drawn = CGSize(width: input.pixels.width * scale, height: input.pixels.height * scale)
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.setRenderingIntent(source.renderingIntent)
        context.draw(source, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
        guard let output = context.makeImage() else { return input }
        let cropped = request.mode == .fill
            && Double(input.pixels.width) * Double(request.height) != Double(input.pixels.height) * Double(request.width)
        return Image(NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height)),
                     nativeSize: input.nativeSize, crop: cropped ? request : nil)
    }

    // Steam still-frame selection retains its existing limit until that caller migrates.
    static func longestSide(for source: CGImageSource, targetWidth: Int, targetHeight: Int,
                            maximum: Int = Int.max) -> Int? {
        guard let native = nativeSize(of: source) else { return nil }
        let size = ThumbnailRequest(width: max(1, targetWidth), height: max(1, targetHeight), mode: .fill).decodedSize(for: native)
        let longest = max(size.width, size.height)
        guard longest < CGFloat(Int.max) else { return nil }
        return min(max(1, maximum), Int(longest))
    }
}
