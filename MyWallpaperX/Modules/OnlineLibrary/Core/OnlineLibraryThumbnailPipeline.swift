//
//  OnlineLibraryThumbnailPipeline.swift
//  MyWallpaperX — Modules/OnlineLibrary/Core
//

import AppKit
import Foundation

nonisolated enum OLThumbnailRequestPriority: Sendable {
    case visible
    case prefetch

    var timeoutInterval: TimeInterval {
        switch self {
        case .visible:
            return 12
        case .prefetch:
            return 8
        }
    }

    var networkServiceType: URLRequest.NetworkServiceType {
        switch self {
        case .visible:
            return .responsiveData
        case .prefetch:
            return .background
        }
    }
}

actor OLThumbnailRequestCoordinator {
    private struct InFlightRequest {
        let id: UUID
        let task: Task<Data?, Never>
    }

    static let shared = OLThumbnailRequestCoordinator()

    private let session: URLSession
    private let scheduler = OLThumbnailRequestScheduler()
    private var inFlight: [String: InFlightRequest] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func loadData(from url: URL, priority: OLThumbnailRequestPriority) async -> Data? {
        let key = url.absoluteString
        if let request = inFlight[key] {
            return await request.task.value
        }

        let requestID = UUID()
        let task = Task<Data?, Never> { [session, scheduler] in
            return await scheduler.run(priority: priority) {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = priority.timeoutInterval
                    request.networkServiceType = priority.networkServiceType
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        return nil
                    }
                    return data
                } catch {
                    return nil
                }
            }
        }
        inFlight[key] = InFlightRequest(id: requestID, task: task)

        let data = await task.value
        removeInFlightTask(forKey: key, requestID: requestID)
        return data
    }

    private func removeInFlightTask(forKey key: String, requestID: UUID) {
        guard inFlight[key]?.id == requestID else { return }
        inFlight.removeValue(forKey: key)
    }
}

actor OLThumbnailRequestScheduler {
    private var activeVisibleRequests = 0
    private var activePrefetchRequests = 0
    private var waitingVisibleRequests: [CheckedContinuation<Void, Never>] = []
    private var waitingPrefetchRequests: [CheckedContinuation<Void, Never>] = []

    func run<T>(
        priority: OLThumbnailRequestPriority,
        operation: @Sendable () async -> T
    ) async -> T {
        await acquire(priority: priority)
        defer { release(priority: priority) }
        return await operation()
    }

    private func acquire(priority: OLThumbnailRequestPriority) async {
        while !canAcquire(priority: priority) {
            await withCheckedContinuation { continuation in
                switch priority {
                case .visible:
                    waitingVisibleRequests.append(continuation)
                case .prefetch:
                    waitingPrefetchRequests.append(continuation)
                }
            }
        }

        switch priority {
        case .visible:
            activeVisibleRequests += 1
        case .prefetch:
            activePrefetchRequests += 1
        }
    }

    private func canAcquire(priority: OLThumbnailRequestPriority) -> Bool {
        switch priority {
        case .visible:
            return activeVisibleRequests < 2
        case .prefetch:
            return activeVisibleRequests == 0
                && activePrefetchRequests == 0
                && waitingVisibleRequests.isEmpty
        }
    }

    private func release(priority: OLThumbnailRequestPriority) {
        switch priority {
        case .visible:
            activeVisibleRequests = max(0, activeVisibleRequests - 1)
        case .prefetch:
            activePrefetchRequests = max(0, activePrefetchRequests - 1)
        }
        resumeNextIfPossible()
    }

    private func resumeNextIfPossible() {
        while canAcquire(priority: .visible), !waitingVisibleRequests.isEmpty {
            let continuation = waitingVisibleRequests.removeFirst()
            continuation.resume()
        }

        if canAcquire(priority: .prefetch), let continuation = waitingPrefetchRequests.first {
            waitingPrefetchRequests.removeFirst()
            continuation.resume()
        }
    }
}

// MARK: - 缩略图磁盘缓存

actor OLThumbnailCache {
    static let shared = OLThumbnailCache()

    /// 缓存目录：~/Library/Caches/com.MyWallpaperX.OnlineLibrary/thumbnails/
    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("com.MyWallpaperX.OnlineLibrary/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 缓存有效期：7 天
    private let maxAge: TimeInterval = 7 * 24 * 3600
    /// 内存缓存（NSCache，自动响应内存压力，上限 60MB / 300 条）
    private let memCache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 300
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()
    /// 解码结果缓存：网格卡片每次进入视口都会对同一 URL 请求缩略图，
    /// 缓存解码后的 NSImage 避免重复解析 JPEG（压缩数据仍由 memCache/磁盘缓存）
    private let decodedImageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 120
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    private init() {
        Task { await self.evictExpired() }
    }

    /// 取缓存（内存 → 磁盘），返回 nil 表示无缓存
    func cachedData(for url: URL) -> Data? {
        let key = url.absoluteString as NSString
        if let data = memCache.object(forKey: key) { return data as Data }
        let file = cacheFile(for: url)
        guard FileManager.default.fileExists(atPath: file.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: file)
        else { return nil }
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    /// 写入缓存
    func store(data: Data, for url: URL) {
        let key = url.absoluteString as NSString
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        let file = cacheFile(for: url)
        try? data.write(to: file, options: .atomic)
    }

    // MARK: 解码结果缓存

    /// 取解码后的缩略图（解码缓存 → 数据缓存后台解码）；返回 nil 表示无可用数据或解码失败
    func cachedImage(for url: URL) async -> NSImage? {
        let key = url.absoluteString as NSString
        if let img = decodedImageCache.object(forKey: key) { return img }
        guard let data = cachedData(for: url),
              let img = await Self.decode(data) else { return nil }
        decodedImageCache.setObject(img, forKey: key, cost: Self.decodedImageCost(img))
        return img
    }

    /// 写入数据缓存并返回后台解码结果；解码失败不写缓存（与旧「先解码后入缓存」行为一致）
    func storeAndDecode(data: Data, for url: URL) async -> NSImage? {
        guard let img = await Self.decode(data) else { return nil }
        store(data: data, for: url)
        decodedImageCache.setObject(img, forKey: url.absoluteString as NSString, cost: Self.decodedImageCost(img))
        return img
    }

    /// 解码统一放后台，避免占住调用方线程（主线程或 actor 执行器）
    private static func decode(_ data: Data) async -> NSImage? {
        await Task.detached(priority: .utility, operation: { NSImage(data: data) }).value
    }

    private static func decodedImageCost(_ image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 0 }
        return max(1, rep.pixelsWide * rep.pixelsHigh * 4)
    }

    /// 删除 7 天前的缓存文件
    func evictExpired() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap { $0.contentModificationDate } ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func cacheFile(for url: URL) -> URL {
        // URL → 安全文件名（用 base64 编码避免特殊字符）
        let name = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return cacheDir.appendingPathComponent(name)
    }
}
