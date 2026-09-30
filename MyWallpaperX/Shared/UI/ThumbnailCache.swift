//
//  ThumbnailCache.swift
//  MyWallpaperX
//
//  三模块共用的异步缩略图加载缓存。
//  合并相同路径的并发请求（in-flight deduplication），
//  后台解码，主线程回调，NSCache 内存缓存 + 磁盘持久化缓存。
//

import AppKit
import CryptoKit

/// 异步缩略图加载缓存。
/// 线程安全：并发读写通过 NSLock 保护 in-flight 表，NSCache 本身线程安全。
nonisolated final class ThumbnailCache: @unchecked Sendable {

    /// 缓存容量（最大图片数量）
    private let countLimit: Int

    /// 内存缓存总字节上限（按已解码位图的像素字节数计），0 表示不限制
    private let totalCostLimit: Int

    private let decodeQueue: DispatchQueue
    private let imageCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private var rawDataPrefetchInFlight = Set<String>()
    private let lock = NSLock()

    /// 磁盘缓存目录
    private static let diskCacheDir: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyWallpaperX")
            .appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    /// 磁盘缓存总大小上限：超过后按最后使用时间惰性淘汰最旧文件
    private static let diskCacheSizeLimit: UInt64 = 512 * 1024 * 1024
    /// 惰性淘汰的目录扫描限频间隔，避免每次写盘都全量遍历
    private static let diskTrimInterval: TimeInterval = 60
    private static let diskTrimLock = NSLock()
    private static var lastDiskTrimDate = Date.distantPast

    /// - Parameters:
    ///   - label: decode queue 标识，建议用模块前缀区分
    ///   - countLimit: 内存缓存最大图片数，默认 360
    ///   - totalCostLimit: 内存缓存像素字节总和上限，默认 0（不限制）
    init(label: String = "com.mywallpaper.thumbnail.decode",
         countLimit: Int = 360,
         totalCostLimit: Int = 0) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.decodeQueue = DispatchQueue(label: label, qos: .utility)
        imageCache.countLimit = countLimit
        imageCache.totalCostLimit = totalCostLimit
    }

    // MARK: - 公开接口

    /// 加载缩略图。内存缓存命中则同步回调，磁盘缓存命中则异步快速读取，否则后台解码。
    func load(
        forKey key: String,
        loader: @escaping () -> NSImage?,
        completion: @escaping (NSImage?) -> Void
    ) {
        // 1. 内存缓存
        if let cached = imageCache.object(forKey: key as NSString) {
            completion(cached)
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

        decodeQueue.async { [weak self] in
            guard let self else { return }
            // 2. 磁盘缓存
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }
            // 3. 解码原图
            let image = loader()
            if let image {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                // 写入磁盘缓存（JPEG，压缩质量 0.85）
                Self.writeToDisk(image: image, url: diskURL)
                Self.trimDiskCacheIfNeeded()
            }
            self.finish(key: key, image: image)
        }
    }

    /// 加载原始图片数据并保留其编码格式。
    /// 适合 GIF 等需要保留动画信息的资源。
    func loadImageData(
        forKey key: String,
        loader: @escaping () -> Data?,
        decoder: @escaping (Data) -> NSImage? = { NSImage(data: $0) },
        completion: @escaping (NSImage?) -> Void
    ) {
        if let cached = imageCache.object(forKey: key as NSString) {
            completion(cached)
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

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = decoder(data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }

            guard let data = loader(),
                  let image = decoder(data) else {
                self.finish(key: key, image: nil)
                return
            }

            self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
            try? data.write(to: diskURL, options: .atomic)
            Self.trimDiskCacheIfNeeded()
            self.finish(key: key, image: image)
        }
    }

    /// 异步加载原始图片数据并保留其编码格式。
    /// 适合网络资源，避免在缓存队列里同步等待请求返回。
    func loadImageDataAsync(
        forKey key: String,
        loader: @escaping @Sendable () async -> Data?,
        decoder: @escaping @Sendable (Data) -> NSImage? = { NSImage(data: $0) },
        completion: @escaping (NSImage?) -> Void
    ) {
        if let cached = imageCache.object(forKey: key as NSString) {
            completion(cached)
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

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = decoder(data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }

            Task { [weak self] in
                guard let self else { return }
                guard let data = await loader(),
                      let image = decoder(data) else {
                    self.finish(key: key, image: nil)
                    return
                }

                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                try? data.write(to: diskURL, options: .atomic)
                Self.trimDiskCacheIfNeeded()
                self.finish(key: key, image: image)
            }
        }
    }

    /// 预取：触发后台加载但不注册回调。
    func prefetch(forKey key: String, loader: @escaping () -> NSImage?) {
        guard imageCache.object(forKey: key as NSString) == nil else { return }

        lock.lock()
        guard inFlight[key] == nil else { lock.unlock(); return }
        inFlight[key] = []
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }
            let image = loader()
            if let image {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                Self.writeToDisk(image: image, url: diskURL)
                Self.trimDiskCacheIfNeeded()
            }
            self.finish(key: key, image: image)
        }
    }

    /// 预取原始图片数据并保留原编码格式。
    /// 适合 GIF 等动态缩略图，避免在预取阶段被转成静态 JPEG。
    func prefetchImageData(forKey key: String, loader: @escaping () -> Data?) {
        guard imageCache.object(forKey: key as NSString) == nil else { return }

        lock.lock()
        guard inFlight[key] == nil else { lock.unlock(); return }
        inFlight[key] = []
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }

            guard let data = loader() else {
                self.finish(key: key, image: nil)
                return
            }

            let image = NSImage(data: data)
            if let image {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
            }
            try? data.write(to: diskURL, options: .atomic)
            Self.trimDiskCacheIfNeeded()
            self.finish(key: key, image: image)
        }
    }

    /// 异步预取原始图片数据并保留原编码格式。
    func prefetchImageDataAsync(
        forKey key: String,
        loader: @escaping @Sendable () async -> Data?
    ) {
        guard imageCache.object(forKey: key as NSString) == nil else { return }

        lock.lock()
        guard inFlight[key] == nil else { lock.unlock(); return }
        inFlight[key] = []
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }

            Task { [weak self] in
                guard let self else { return }
                guard let data = await loader() else {
                    self.finish(key: key, image: nil)
                    return
                }

                let image = NSImage(data: data)
                if let image {
                    self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                }
                try? data.write(to: diskURL, options: .atomic)
                Self.trimDiskCacheIfNeeded()
                self.finish(key: key, image: image)
            }
        }
    }

    /// 异步预取原始图片数据，只写入磁盘，不解码进内存缓存。
    /// 适合可见区域外的预热，避免 GIF 等资源在后台产生持续动画/解码压力。
    func prefetchRawDataAsync(
        forKey key: String,
        loader: @escaping @Sendable () async -> Data?
    ) {
        guard imageCache.object(forKey: key as NSString) == nil else { return }

        lock.lock()
        guard !rawDataPrefetchInFlight.contains(key) else { lock.unlock(); return }
        rawDataPrefetchInFlight.insert(key)
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = Self.diskCacheURL(for: key)
            if FileManager.default.fileExists(atPath: diskURL.path) {
                self.finishRawDataPrefetch(key: key)
                return
            }

            Task { [weak self] in
                guard let self else { return }
                guard let data = await loader() else {
                    self.finishRawDataPrefetch(key: key)
                    return
                }

                try? data.write(to: diskURL, options: .atomic)
                Self.trimDiskCacheIfNeeded()
                self.finishRawDataPrefetch(key: key)
            }
        }
    }

    /// 清空内存缓存（磁盘缓存保留）
    func removeAll() {
        imageCache.removeAllObjects()
    }

    func remove(forKey key: String) {
        imageCache.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: Self.diskCacheURL(for: key))
    }

    /// 同步读取内存缓存，不触发磁盘 IO。
    func cachedImage(forKey key: String) -> NSImage? {
        imageCache.object(forKey: key as NSString)
    }

    /// 同步读取缓存，优先内存，其次磁盘。
    /// 适合需要避免首次占位闪烁的场景。
    func cachedOrDiskImage(
        forKey key: String,
        decoder: (Data) -> NSImage? = { NSImage(data: $0) }
    ) -> NSImage? {
        let cacheKey = key as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        let diskURL = Self.diskCacheURL(for: key)
        guard let data = try? Data(contentsOf: diskURL),
              let image = decoder(data) else {
            return nil
        }
        imageCache.setObject(image, forKey: cacheKey, cost: Self.memoryCost(of: image))
        return image
    }

    /// 清空磁盘缓存
    static func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskCacheDir)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    /// 写入后的磁盘惰性淘汰：总量超过 diskCacheSizeLimit 时按最后使用时间清理最旧文件。
    /// 扫描按 diskTrimInterval 限频（各实例共享同一磁盘目录，用静态锁串行化）。
    private static func trimDiskCacheIfNeeded() {
        diskTrimLock.lock()
        defer { diskTrimLock.unlock() }

        let now = Date()
        guard now.timeIntervalSince(lastDiskTrimDate) >= diskTrimInterval else { return }
        lastDiskTrimDate = now

        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: diskCacheDir,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        struct DiskEntry {
            let url: URL
            let size: Int64
            let lastUsed: Date
        }

        var entries: [DiskEntry] = []
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            // APFS 下访问时间可能不严格更新，回退到修改时间保证排序稳定。
            let lastUsed = values?.contentAccessDate
                ?? values?.contentModificationDate
                ?? .distantPast
            entries.append(DiskEntry(url: fileURL, size: size, lastUsed: lastUsed))
            totalSize += size
        }

        guard totalSize > Int64(diskCacheSizeLimit) else { return }

        let overflow = totalSize - Int64(diskCacheSizeLimit)
        var reclaimed: Int64 = 0
        for entry in entries.sorted(by: { $0.lastUsed < $1.lastUsed }) {
            guard reclaimed < overflow else { break }
            try? fileManager.removeItem(at: entry.url)
            reclaimed += entry.size
        }
    }

    // MARK: - 内部

    private func finish(key: String, image: NSImage?) {
        lock.lock()
        let completions = inFlight.removeValue(forKey: key) ?? []
        lock.unlock()
        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
    }

    private func finishRawDataPrefetch(key: String) {
        lock.lock()
        rawDataPrefetchInFlight.remove(key)
        lock.unlock()
    }

    private static func diskCacheURL(for key: String) -> URL {
        // 用 SHA256 哈希作为文件名，避免路径中的特殊字符
        let hash = SHA256.hash(data: Data(key.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    /// NSCache 的 cost：按已解码位图的像素字节数计，totalCostLimit 据此执行字节上限淘汰。
    private static func memoryCost(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func writeToDisk(image: NSImage, url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        try? jpegData.write(to: url, options: .atomic)
    }
}
