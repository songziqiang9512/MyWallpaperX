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
    return steamWorkshopSampledLumaIsSuspicious(cgImage)
}

/// 8×8 亮度采样：近全黑（均值 <0.03 且极差 <0.025，即几乎无内容起伏）
/// 判为可疑。这是"首帧黑底"GIF 的判定核心，静态解码与可疑检测共用。
func steamWorkshopSampledLumaIsSuspicious(_ cgImage: CGImage) -> Bool {
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
    // 动画 GIF 也只进静态首帧：共享缓存按像素字节记账，原分辨率多帧
    // NSImage 连同全部帧编码数据驻留会让预算实际膨胀数倍。动画重放由
    // steamWorkshopLoadAnimatedPreview 在悬停/详情打开时按需临时提供。
    return steamWorkshopStaticPreviewImage(from: source) ?? NSImage(data: data)
}

func steamWorkshopPreviewImage(from url: URL) -> NSImage? {
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
        return NSImage(contentsOf: url)
    }
    return steamWorkshopStaticPreviewImage(from: source) ?? NSImage(contentsOf: url)
}

/// 动画变体解码：仅当数据确实是多帧动画时成功，否则返回 nil。
/// 结果不进共享内存缓存——由调用方短生命周期持有。
func steamWorkshopAnimatedPreviewImage(from data: Data) -> NSImage? {
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
          CGImageSourceGetCount(source) > 1 else {
        return nil
    }
    return NSImage(data: data)
}

/// 按需加载动画预览：磁盘缓存命中原始编码数据；远程未命中时经
/// coordinator 取数并回写磁盘。解码结果不进共享内存缓存。
func steamWorkshopLoadAnimatedPreview(
    from url: URL,
    cacheKey: String,
    completion: @escaping (NSImage?) -> Void
) {
    let loader: @Sendable () async -> Data? = {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        return await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
            from: url,
            priority: .visible
        )
    }
    SteamWorkshopPreviewImageCache.shared.loadRawDataAsync(
        forKey: cacheKey,
        loader: loader
    ) { data in
        completion(data.flatMap(steamWorkshopAnimatedPreviewImage(from:)))
    }
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
///
/// 动画 GIF 常见"首帧黑底"（作者首帧占位/录制工具从黑场起始）。静态缩略图
/// 默认取第 0 帧，会整卡显示黑色。这里复用视频缩略图管线的多候选模式：
/// 首帧采样为近全黑时顺序前进（8 帧封顶）取第一个非黑帧；全部可疑时保留
/// 首帧（忠实于源）。悬停动画路径不受影响，仍从原始数据完整重放。
private func steamWorkshopStaticPreviewImage(from source: CGImageSource, maxPixelSize: Int = 800) -> NSImage? {
    let frameCount = CGImageSourceGetCount(source)
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let first = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    guard frameCount > 1, steamWorkshopSampledLumaIsSuspicious(first) else {
        return steamWorkshopRGBAImage(from: first)
    }
    // 顺序前进的帧扫描成本有界：缩略图解码 ×8 封顶，且只在后台解码队列执行。
    for index in 1..<min(frameCount, 8) {
        guard let candidate = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            continue
        }
        if !steamWorkshopSampledLumaIsSuspicious(candidate) {
            return steamWorkshopRGBAImage(from: candidate)
        }
    }
    return steamWorkshopRGBAImage(from: first)
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
