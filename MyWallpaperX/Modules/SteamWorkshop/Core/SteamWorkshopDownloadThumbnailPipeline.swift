import Foundation
import AppKit
import AVFoundation
import CryptoKit
import Darwin

final class SteamWorkshopDownloadThumbnailPipeline {
    static let shared = SteamWorkshopDownloadThumbnailPipeline()

    private let workQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.download-thumbnail",
        qos: .utility
    )
    private let lock = NSLock()
    private final class Job {
        var completions: [(NSImage?) -> Void]
        var cacheable = true
        init(_ completion: @escaping (NSImage?) -> Void) { completions = [completion] }
    }
    private var inFlight: [String: Job] = [:]
    /// 已生成缩略图的内存缓存：卡片配置链路重复刷新时不再磁盘读+解码。
    private let memoryCache = DecodedThumbnailMemoryCache(countLimit: 320, totalCostLimit: 64 * 1024 * 1024)
    /// 失败负缓存：损坏/可疑视频记录一次结论，避免每次刷新重复 IO 与 AVAsset 重试。
    /// key 含文件 mtime+size，内容变化后自然换新 key，无需显式过期。
    private let failureCache = NSCache<NSString, NSNumber>()

    private init() {
        failureCache.countLimit = 256
    }

    /// The service deletes its disk root after this invalidation. Admitted
    /// consumers still receive their result; old jobs cannot refill any cache.
    func invalidateCachedResults() {
        lock.lock()
        defer { lock.unlock() }
        for job in inFlight.values { job.cacheable = false }
        memoryCache.removeAllObjects()
        failureCache.removeAllObjects()
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
        if let job = inFlight[key] {
            job.completions.append(completion)
            lock.unlock()
            return
        }
        inFlight[key] = Job(completion)
        lock.unlock()

        workQueue.async {
            // 已知失败的视频直接复用负缓存结论，不再重复磁盘 IO 与 3 帧 AVAsset 重试。
            if self.failureCache.object(forKey: key as NSString) != nil {
                self.finish(key: key, image: nil)
                return
            }
            // 本次请求的内存、磁盘和生成结果共用入口已捕获的源文件身份。
            let outputURL = Self.cacheRootURL.appendingPathComponent(key).appendingPathExtension("jpg")
            // 优先复用已落盘缩略图：磁盘读+解码在本后台队列执行，不占主线程配置链路。
            if let cached = self.diskCachedThumbnail(at: outputURL) {
                self.finish(key: key, image: cached)
                return
            }


            let image = self.createThumbnail(for: videoURL)
            let staged = image.flatMap { self.stageThumbnail($0, at: outputURL) }
            self.finish(key: key, image: image, staged: staged, cachesFailure: true)
        }
    }

    /// 从磁盘读取已生成缩略图并做可疑检测，统一完成入口负责缓存发布。
    private func diskCachedThumbnail(at outputURL: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: outputURL),
              !steamWorkshopPreviewImageLooksSuspicious(image) else {
            return nil
        }
        return image
    }

    nonisolated private static func memoryCost(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func finish(key: String, image: NSImage?, staged: URL? = nil, cachesFailure: Bool = false) {
        let cost = image.map(Self.memoryCost) ?? 0
        let output = Self.cacheRootURL.appendingPathComponent(key).appendingPathExtension("jpg")
        var published = false
        lock.lock()
        let job = inFlight.removeValue(forKey: key)
        if job?.cacheable == true {
            if let image {
                if let staged { published = rename(staged.path, output.path) == 0 }
                memoryCache.setObject(image, forKey: key as NSString, cost: cost)
            } else if cachesFailure {
                failureCache.setObject(NSNumber(value: true), forKey: key as NSString)
            }
        }
        let completions = job?.completions ?? []
        lock.unlock()

        if let staged { try? FileManager.default.removeItem(at: staged) }
        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
        if published {
            ThumbnailCache.trimDiskCache(directory: Self.cacheRootURL, sizeLimit: 256 * 1024 * 1024)
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

    /// JPEG preparation stays on the original worker queue. Only the final
    /// rename and memory/failure publication consume the job under its lock.
    private func stageThumbnail(_ image: NSImage, at outputURL: URL) -> URL? {
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return nil }
        let staged = outputURL.deletingLastPathComponent().appendingPathComponent(".thumbnail-\(UUID().uuidString).pending")
        do { try data.write(to: staged); return staged }
        catch { try? FileManager.default.removeItem(at: staged); return nil }
    }

    private func cacheKey(for videoURL: URL) -> String {
        let rawKey = steamWorkshopLocalPreviewCacheKey(for: videoURL)
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
