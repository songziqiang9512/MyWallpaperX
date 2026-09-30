import Foundation
import AppKit
import AVFoundation
import CryptoKit

final class SteamWorkshopDownloadThumbnailPipeline {
    static let shared = SteamWorkshopDownloadThumbnailPipeline()

    private let workQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.download-thumbnail",
        qos: .utility
    )
    private let generationLimiter = DispatchSemaphore(value: 2)
    private let lock = NSLock()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    /// 已生成缩略图的内存缓存：卡片配置链路重复刷新时不再磁盘读+解码。
    private let memoryCache = NSCache<NSString, NSImage>()
    /// 失败负缓存：损坏/可疑视频记录一次结论，避免每次刷新重复 IO 与 AVAsset 重试。
    /// key 含文件 mtime+size，内容变化后自然换新 key，无需显式过期。
    private let failureCache = NSCache<NSString, NSNumber>()

    private init() {
        memoryCache.totalCostLimit = 64 * 1024 * 1024
        failureCache.countLimit = 256
    }

    /// 只读内存缓存与负缓存，不做磁盘 IO；磁盘读+解码统一挪到 generateThumbnail 的后台块。
    func cachedThumbnail(for videoURL: URL) -> NSImage? {
        let key = cacheKey(for: videoURL)
        if failureCache.object(forKey: key as NSString) != nil {
            return nil
        }
        return memoryCache.object(forKey: key as NSString)
    }

    func generateThumbnail(for videoURL: URL, completion: @escaping (NSImage?) -> Void) {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        let key = cacheKey(for: videoURL)
        if let cached = memoryCache.object(forKey: key as NSString) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        lock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[key] = [completion]
        lock.unlock()

        workQueue.async {
            // 已知失败的视频直接复用负缓存结论，不再重复磁盘 IO 与 3 帧 AVAsset 重试。
            if self.failureCache.object(forKey: key as NSString) != nil {
                self.finish(key: key, image: nil)
                return
            }
            // 优先复用已落盘缩略图：磁盘读+解码在本后台队列执行，不占主线程配置链路。
            if let cached = self.diskCachedThumbnail(for: videoURL, key: key) {
                self.finish(key: key, image: cached)
                return
            }

            self.generationLimiter.wait()
            defer { self.generationLimiter.signal() }

            let image = self.createThumbnail(for: videoURL)
            if let image {
                self.persistThumbnail(image, for: videoURL)
                self.memoryCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
            } else {
                self.failureCache.setObject(NSNumber(value: true), forKey: key as NSString)
            }
            self.finish(key: key, image: image)
        }
    }

    /// 从磁盘读取已生成缩略图并做可疑检测；命中时写入内存缓存。
    private func diskCachedThumbnail(for videoURL: URL, key: String) -> NSImage? {
        let outputURL = thumbnailOutputURL(for: videoURL)
        guard let image = NSImage(contentsOf: outputURL),
              !steamWorkshopPreviewImageLooksSuspicious(image) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
        return image
    }

    private static func memoryCost(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func finish(key: String, image: NSImage?) {
        lock.lock()
        let completions = inFlight.removeValue(forKey: key) ?? []
        lock.unlock()

        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
    }

    private func createThumbnail(for videoURL: URL) -> NSImage? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 960, height: 960)

        let candidateTimes = [
            CMTime(seconds: 1, preferredTimescale: 600),
            CMTime(seconds: 0.25, preferredTimescale: 600),
            CMTime.zero
        ]

        for time in candidateTimes {
            guard let cgImage = generateCGImage(using: imageGenerator, at: time) else { continue }
            let image = NSImage(cgImage: cgImage, size: .zero)
            if !steamWorkshopPreviewImageLooksSuspicious(image) {
                return image
            }
        }
        return nil
    }

    private func generateCGImage(
        using generator: AVAssetImageGenerator,
        at time: CMTime
    ) -> CGImage? {
        var result: CGImage?
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
            result = cgImage
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private func persistThumbnail(_ image: NSImage, for videoURL: URL) {
        let outputURL = thumbnailOutputURL(for: videoURL)
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }
        try? data.write(to: outputURL, options: [.atomic])
    }

    private func thumbnailOutputURL(for videoURL: URL) -> URL {
        Self.cacheRootURL
            .appendingPathComponent(cacheKey(for: videoURL))
            .appendingPathExtension("jpg")
    }

    private func cacheKey(for videoURL: URL) -> String {
        let normalizedPath = videoURL.standardizedFileURL.path
        let values = try? videoURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationStamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let rawKey = "\(normalizedPath)|\(modificationStamp)|\(fileSize)"
        return SHA256.hash(data: Data(rawKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static let cacheRootURL: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("GeneratedDownloadThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
