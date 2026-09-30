import AppKit
import CoreGraphics
import ImageIO

enum SteamWorkshopPreviewImageCache {
    // 网格/详情/下载弹窗共用一份解码缓存：按像素字节设 128MB 上限，
    // 防止长会话浏览时已解码位图驻留膨胀到数百 MB 以上。
    static let shared = ThumbnailCache(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.preview.decode",
        countLimit: 320,
        totalCostLimit: 128 * 1024 * 1024,
        namespace: "steamworkshop-preview"
    )
}

func steamWorkshopPreviewCacheKey(for url: URL) -> String {
    let host = (url.host ?? "").lowercased()
    let normalizedPath: String = {
        let path = url.path.isEmpty ? "/" : url.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }()

    if host.hasSuffix("steamusercontent.com"),
       normalizedPath.contains("/ugc/") {
        return "steam-preview:\(host)\(normalizedPath)"
    }

    return "steam-preview:\(url.absoluteString)"
}

func steamWorkshopLocalPreviewCacheKey(for url: URL) -> String {
    let fileURL = url.standardizedFileURL
    let resourceValues = try? fileURL.resourceValues(forKeys: [
        .contentModificationDateKey,
        .fileSizeKey
    ])
    let modificationTime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
    let fileSize = resourceValues?.fileSize ?? 0
    return "steam-local-preview:\(fileURL.path):\(fileSize):\(modificationTime)"
}

func steamWorkshopLoadLocalPreviewImage(
    from url: URL,
    completion: @escaping (NSImage?) -> Void
) {
    SteamWorkshopPreviewImageCache.shared.loadImageData(
        forKey: steamWorkshopLocalPreviewCacheKey(for: url),
        loader: { try? Data(contentsOf: url) },
        decoder: steamWorkshopPreviewImage(from:),
        completion: completion
    )
}

func steamWorkshopPreviewImageLooksSuspicious(_ image: NSImage) -> Bool {
    guard image.size.width > 0, image.size.height > 0 else { return true }
    if image.size.width <= 4 || image.size.height <= 4 {
        return true
    }
    if steamWorkshopPreviewImageIsAnimated(image) {
        return false
    }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return false
    }

    let sampleWidth = 8
    let sampleHeight = 8
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
    guard let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: sampleWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return false
    }

    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    var luminances: [CGFloat] = []
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = CGFloat(pixels[index + 3]) / 255.0
        guard alpha > 0.05 else { continue }
        let red = CGFloat(pixels[index]) / 255.0
        let green = CGFloat(pixels[index + 1]) / 255.0
        let blue = CGFloat(pixels[index + 2]) / 255.0
        luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    }

    guard !luminances.isEmpty else { return true }
    let minLuma = luminances.min() ?? 0
    let maxLuma = luminances.max() ?? 0
    let meanLuma = luminances.reduce(0, +) / CGFloat(luminances.count)
    return meanLuma < 0.03 && (maxLuma - minLuma) < 0.025
}

func steamWorkshopPreviewImageIsUsable(_ image: NSImage) -> Bool {
    image.size.width > 4 && image.size.height > 4
}

func steamWorkshopPreviewImage(from data: Data) -> NSImage? {
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
        return NSImage(data: data)
    }
    if CGImageSourceGetCount(source) > 1 {
        return NSImage(data: data)
    }
    return steamWorkshopStaticPreviewImage(from: source) ?? NSImage(data: data)
}

func steamWorkshopPreviewImage(from url: URL) -> NSImage? {
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
        return NSImage(contentsOf: url)
    }
    if CGImageSourceGetCount(source) > 1 {
        return NSImage(contentsOf: url)
    }
    return steamWorkshopStaticPreviewImage(from: source) ?? NSImage(contentsOf: url)
}

private func steamWorkshopPreviewImageIsAnimated(_ image: NSImage) -> Bool {
    image.representations.contains { representation in
        guard let bitmap = representation as? NSBitmapImageRep else { return false }
        let frameCount = bitmap.value(forProperty: .frameCount) as? Int ?? 1
        return frameCount > 1
    }
}

/// 共享解码上限取网格卡片实际显示所需尺寸；详情预览区高度仅 156pt（2x 下 312px），
/// 800px 源图已覆盖，不再为共享缓存解码 1600px 大图。
private func steamWorkshopStaticPreviewImage(from source: CGImageSource, maxPixelSize: Int = 800) -> NSImage? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    return steamWorkshopRGBAImage(from: cgImage)
}

private func steamWorkshopRGBAImage(from cgImage: CGImage) -> NSImage? {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let decodedImage = context.makeImage() else { return nil }
    return NSImage(
        cgImage: decodedImage,
        size: NSSize(width: decodedImage.width, height: decodedImage.height)
    )
}
