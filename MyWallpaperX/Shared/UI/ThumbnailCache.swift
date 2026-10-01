//
//  ThumbnailCache.swift
//  MyWallpaperX
//
//  各模块共用的异步缩略图加载缓存。
//  合并相同键的并发请求（in-flight deduplication），
//  后台解码，主线程回调，NSCache 内存缓存 + 按 namespace 隔离的磁盘持久化缓存。
//

import AppKit
import CryptoKit

/// 异步缩略图加载缓存。
/// 线程安全：并发读写通过 NSLock 保护 in-flight 表，NSCache 本身线程安全。
nonisolated final class ThumbnailCache: @unchecked Sendable {

    /// 缓存容量（最大图片数量）
    private let countLimit: Int

    /// 内存缓存总字节上限（按已解码位图的像素字节数计）
    private let totalCostLimit: Int

    /// 磁盘缓存 namespace：同一缓存根目录下按 `<ns>/` 子目录隔离，
    /// 「清除缓存」可按 namespace 实例级清空，不再整根互殃。
    private let namespace: String

    /// 失败负缓存（可选，默认关闭，仅作用于 load(forKey:loader:completion:)）：
    /// loader 返回 nil 时记录结论，重复加载直接回 nil，避免损坏内容反复触发 IO/解码。
    /// 调用方需让键携带内容指纹（如 mtime+size），内容变化后自然换新键。
    private let failureCache: NSCache<NSString, NSNumber>?

    private let decodeQueue: DispatchQueue
    private let imageCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private var rawDataInFlight: [String: [(Data?) -> Void]] = [:]
    private var rawDataPrefetchInFlight = Set<String>()
    private let lock = NSLock()

    /// 磁盘缓存根目录：~/Library/Caches/<bundleID>/thumbnails/<namespace>/
    /// 放 Caches 与 OLThumbnailCache、Steam 下载管线两处磁盘缓存对齐（系统可回收、不进备份）。
    /// 旧的 Application Support/thumbnails 平铺目录是可再生缓存，迁移进 Caches 后一次性删除。
    private static let diskCacheRoot: URL = {
        let bundleID = Bundle.main.bundleIdentifier ?? "MyWallpaperX"
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleID)
            .appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let legacy = appSupport
                .appendingPathComponent(bundleID)
                .appendingPathComponent("thumbnails")
            try? FileManager.default.removeItem(at: legacy)
        }
        return caches
    }()

    /// 本实例 namespace 的磁盘缓存目录
    private var diskCacheDir: URL {
        Self.diskCacheRoot.appendingPathComponent(namespace, isDirectory: true)
    }

    /// 磁盘缓存总大小上限：超过后按最后使用时间惰性淘汰最旧文件
    private static let diskCacheSizeLimit: UInt64 = 512 * 1024 * 1024
    /// 惰性淘汰的目录扫描限频间隔，避免每次写盘都全量遍历
    private static let diskTrimInterval: TimeInterval = 60
    /// 限频钟按目录区分：多个目录接入同一 trim 机制时互不挤占扫描窗口
    private static let diskTrimStateLock = NSLock()
    private static var lastDiskTrimDates: [String: Date] = [:]

    /// - Parameters:
    ///   - label: decode queue 标识，建议用模块前缀区分
    ///   - countLimit: 内存缓存最大图片数，默认 360
    ///   - totalCostLimit: 内存缓存像素字节总和上限，默认 128MB，避免新实例复制出无上限形状。
    ///     各实例显式预算集中登记：Steam 预览 128MB（SteamWorkshopPreviewImageCache）、
    ///     视频库 128MB（VideoLibraryThumbnailStore）、SIL 64MB（SILThumbnailStore）、
    ///     在线库下载项 50MB（OLDownloadedThumbnailStore）
    ///   - namespace: 磁盘缓存子目录名，必填，新实例必须声明自己的隔离空间
    ///   - usesFailureCache: 是否启用失败负缓存（见 failureCache 注释）
    init(label: String = "com.mywallpaper.thumbnail.decode",
         countLimit: Int = 360,
         totalCostLimit: Int = 128 * 1024 * 1024,
         namespace: String,
         usesFailureCache: Bool = false) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.namespace = namespace
        self.failureCache = usesFailureCache ? NSCache<NSString, NSNumber>() : nil
        self.decodeQueue = DispatchQueue(label: label, qos: .utility)
        failureCache?.countLimit = 256
        imageCache.countLimit = countLimit
        imageCache.totalCostLimit = totalCostLimit
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
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
        // 2. 失败负缓存：已知失败的键直接回 nil，不重复 IO/解码
        if failureCache?.object(forKey: key as NSString) != nil {
            completion(nil)
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
            // 3. 磁盘缓存
            let diskURL = self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL),
               let image = NSImage(data: data) {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                self.finish(key: key, image: image)
                return
            }
            // 4. 解码原图
            let image = loader()
            if let image {
                self.imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
                // 写入磁盘缓存（JPEG，压缩质量 0.85）
                Self.writeToDisk(image: image, url: diskURL)
                Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
            } else {
                // 失败负缓存：记录结论，重复加载不再触发 loader
                self.failureCache?.setObject(NSNumber(value: true), forKey: key as NSString)
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
            let diskURL = self.diskCacheURL(for: key)
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
            Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
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
            let diskURL = self.diskCacheURL(for: key)
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
                Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
                self.finish(key: key, image: image)
            }
        }
    }

    /// 异步取回原始编码数据，但不把解码结果写进内存缓存。
    /// 磁盘命中直接返回；未命中走 loader 并回写磁盘。
    /// 用途：动画 GIF 的临时动画源——解码图随用随弃，内存缓存里只驻留
    /// 静态首帧，原始编码数据留在磁盘层。
    func loadRawDataAsync(
        forKey key: String,
        loader: @escaping @Sendable () async -> Data?,
        completion: @escaping (Data?) -> Void
    ) {
        lock.lock()
        if rawDataInFlight[key] != nil {
            rawDataInFlight[key]?.append(completion)
            lock.unlock()
            return
        }
        rawDataInFlight[key] = [completion]
        lock.unlock()

        decodeQueue.async { [weak self] in
            guard let self else { return }
            let diskURL = self.diskCacheURL(for: key)
            if let data = try? Data(contentsOf: diskURL) {
                self.finishRawData(key: key, data: data)
                return
            }
            Task { [weak self] in
                guard let self else { return }
                guard let data = await loader() else {
                    self.finishRawData(key: key, data: nil)
                    return
                }
                try? data.write(to: diskURL, options: .atomic)
                Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
                self.finishRawData(key: key, data: data)
            }
        }
    }

    private func finishRawData(key: String, data: Data?) {
        lock.lock()
        let completions = rawDataInFlight[key] ?? []
        rawDataInFlight[key] = nil
        lock.unlock()
        // 与 finish(key:image:) 相同的主线程交付契约：消费方直接操作
        // NSView/NSImage 属性，后台交付会跨线程改视图。
        DispatchQueue.main.async {
            completions.forEach { $0(data) }
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
            let diskURL = self.diskCacheURL(for: key)
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
                Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
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
            let diskURL = self.diskCacheURL(for: key)
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
            Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
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
            let diskURL = self.diskCacheURL(for: key)
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
                Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
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
            let diskURL = self.diskCacheURL(for: key)
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
                Self.trimDiskCache(directory: self.diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
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
        try? FileManager.default.removeItem(at: diskCacheURL(for: key))
    }

    /// 同步读取内存缓存，不触发磁盘 IO。
    func cachedImage(forKey key: String) -> NSImage? {
        imageCache.object(forKey: key as NSString)
    }

    /// 同步读取缓存，优先内存，其次磁盘。
    /// 适合需要避免首次占位闪烁的场景。
    /// 现存调用方：SteamWorkshopDownloadTasksPopover（清单外文件）；
    /// 新代码请优先使用 load 的异步管线，不要新增同步磁盘解码入口。
    func cachedOrDiskImage(
        forKey key: String,
        decoder: (Data) -> NSImage? = { NSImage(data: $0) }
    ) -> NSImage? {
        let cacheKey = key as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        let diskURL = diskCacheURL(for: key)
        guard let data = try? Data(contentsOf: diskURL),
              let image = decoder(data) else {
            return nil
        }
        imageCache.setObject(image, forKey: cacheKey, cost: Self.memoryCost(of: image))
        return image
    }

    /// 清空本实例 namespace 的磁盘缓存（实例级，「清除缓存」显式清单逐目录调用）。
    /// 不提供静态整根清除入口：整根删除会连带删掉其他 namespace 子目录，
    /// 而实例 init 每进程仅执行一次、无目录重建路径，清除后磁盘写入会静默失败。
    func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskCacheDir)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    /// 共享磁盘惰性淘汰：总量上限 + 限频扫描 + LRU 淘汰。
    /// ThumbnailCache 自身与 OLThumbnailCache、Steam 下载管线接入同一机制，不另起第二套；
    /// 限频钟按目录区分，多目录接入时互不挤占扫描窗口。
    /// 返回是否实际执行了扫描（限频窗口到点），调用方可顺带执行该目录的其他维护。
    @discardableResult
    static func trimDiskCache(
        directory: URL,
        sizeLimit: UInt64,
        interval: TimeInterval = ThumbnailCache.diskTrimInterval
    ) -> Bool {
        let now = Date()
        diskTrimStateLock.lock()
        let lastTrimDate = lastDiskTrimDates[directory.path] ?? .distantPast
        guard now.timeIntervalSince(lastTrimDate) >= interval else {
            diskTrimStateLock.unlock()
            return false
        }
        lastDiskTrimDates[directory.path] = now
        diskTrimStateLock.unlock()

        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return true }

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

        guard totalSize > Int64(sizeLimit) else { return true }

        let overflow = totalSize - Int64(sizeLimit)
        var reclaimed: Int64 = 0
        for entry in entries.sorted(by: { $0.lastUsed < $1.lastUsed }) {
            guard reclaimed < overflow else { break }
            try? fileManager.removeItem(at: entry.url)
            reclaimed += entry.size
        }
        return true
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

    private func diskCacheURL(for key: String) -> URL {
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
