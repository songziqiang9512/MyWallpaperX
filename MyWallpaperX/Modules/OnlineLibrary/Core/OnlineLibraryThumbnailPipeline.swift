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

nonisolated private final class OLThumbnailPriorityState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: OLThumbnailRequestPriority
    init(_ value: OLThumbnailRequestPriority) { self.value = value }
    func current() -> OLThumbnailRequestPriority { lock.lock(); defer { lock.unlock() }; return value }
    func promote() { lock.lock(); value = .visible; lock.unlock() }
}

actor OLThumbnailRequestCoordinator {
    private struct InFlightRequest {
        let id: UUID
        let task: Task<Void, Never>
        let priority: OLThumbnailPriorityState
        var consumers: [UUID: CheckedContinuation<Data?, Never>]
    }

    static let shared = OLThumbnailRequestCoordinator()
    private let session: URLSession
    private let scheduler = OLThumbnailRequestScheduler()
    private var inFlight: [String: InFlightRequest] = [:]

    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    func loadData(from url: URL, priority: OLThumbnailRequestPriority) async -> Data? {
        let consumerID = UUID()
        let key = url.absoluteString
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                if var request = inFlight[key] {
                    request.consumers[consumerID] = continuation
                    if priority == .visible, request.priority.current() == .prefetch {
                        request.priority.promote()
                        let requestID = request.id
                        Task { await scheduler.promote(requestID) }
                    }
                    inFlight[key] = request
                    return
                }
                let requestID = UUID()
                let priorityState = OLThumbnailPriorityState(priority)
                let task = Task { [session, scheduler] in
                    let result = await scheduler.run(id: requestID, priority: priority,
                        currentPriority: { priorityState.current() }) {
                        do {
                            var request = URLRequest(url: url)
                            request.timeoutInterval = priorityState.current().timeoutInterval
                            request.networkServiceType = priorityState.current().networkServiceType
                            let (data, response) = try await session.data(for: request)
                            guard !Task.isCancelled,
                                  let http = response as? HTTPURLResponse,
                                  (200..<300).contains(http.statusCode) else { return nil as Data? }
                            return data
                        } catch { return nil as Data? }
                    }
                    finish(key: key, requestID: requestID, data: result ?? nil)
                }
                inFlight[key] = InFlightRequest(id: requestID, task: task, priority: priorityState,
                    consumers: [consumerID: continuation])
            }
        } onCancel: {
            Task { await self.cancelConsumer(consumerID, forKey: key) }
        }
    }

    private func cancelConsumer(_ id: UUID, forKey key: String) {
        guard var request = inFlight[key], let continuation = request.consumers.removeValue(forKey: id) else { return }
        continuation.resume(returning: nil)
        if request.consumers.isEmpty {
            inFlight.removeValue(forKey: key)
            request.task.cancel()
        } else { inFlight[key] = request }
    }

    private func finish(key: String, requestID: UUID, data: Data?) {
        guard let request = inFlight[key], request.id == requestID else { return }
        inFlight.removeValue(forKey: key)
        request.consumers.values.forEach { $0.resume(returning: data) }
    }
}

/// Owns permits only; the request/cache actors remain the owners of consumers and results.
actor OLThumbnailRequestScheduler {
    private struct Waiter {
        let id: UUID
        var priority: OLThumbnailRequestPriority
        let continuation: CheckedContinuation<OLThumbnailRequestPriority?, Never>
    }
    private var active: [UUID: OLThumbnailRequestPriority] = [:]
    private var waiting: [Waiter] = []

    func run<T: Sendable>(id: UUID = UUID(), priority: OLThumbnailRequestPriority,
        currentPriority: (@Sendable () -> OLThumbnailRequestPriority)? = nil,
        operation: @Sendable () async -> T) async -> T? {
        await withTaskCancellationHandler {
            guard await acquire(id: id, priority: currentPriority?() ?? priority) != nil else { return nil }
            defer { release(id: id) }
            guard !Task.isCancelled else { return nil }
            return await operation()
        } onCancel: { Task { await self.cancel(id: id) } }
    }

    func promote(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting[index].priority = .visible
        resumeNextIfPossible()
    }

    private func acquire(id: UUID, priority: OLThumbnailRequestPriority) async -> OLThumbnailRequestPriority? {
        guard !Task.isCancelled else { return nil }
        if canAcquire(priority: priority) { active[id] = priority; return priority }
        return await withCheckedContinuation { waiting.append(Waiter(id: id, priority: priority, continuation: $0)) }
    }

    private func cancel(id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: nil)
        resumeNextIfPossible()
    }

    private func release(id: UUID) {
        active.removeValue(forKey: id)
        resumeNextIfPossible()
    }

    private func canAcquire(priority: OLThumbnailRequestPriority) -> Bool {
        let visible = active.values.filter { $0 == .visible }.count
        switch priority {
        case .visible: return visible < 2
        case .prefetch:
            return active.isEmpty && !waiting.contains { $0.priority == .visible }
        }
    }

    private func resumeNextIfPossible() {
        while let index = waiting.firstIndex(where: { $0.priority == .visible }), canAcquire(priority: .visible) {
            let waiter = waiting.remove(at: index)
            active[waiter.id] = .visible
            waiter.continuation.resume(returning: .visible)
        }
        if canAcquire(priority: .prefetch), let index = waiting.firstIndex(where: { $0.priority == .prefetch }) {
            let waiter = waiting.remove(at: index)
            active[waiter.id] = .prefetch
            waiter.continuation.resume(returning: .prefetch)
        }
    }
}

// MARK: - 缩略图磁盘缓存

/// Only accessed after Operation has finished; OperationQueue publishes completion after main.
nonisolated private final class OLThumbnailDecodeOperation: Operation, @unchecked Sendable {
    let data: Data
    let maxPixelSize: Int
    private(set) var image: NSImage?
    init(data: Data, maxPixelSize: Int) { self.data = data; self.maxPixelSize = maxPixelSize }
    override func main() {
        guard !isCancelled else { return }
        image = autoreleasepool { GridThumbnailDecoder.decode(data, maxPixelSize: maxPixelSize) }
    }
}

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
    /// 磁盘缓存字节上限：超过后由 ThumbnailCache 共享 trim 按 LRU 淘汰最旧文件
    private let diskSizeLimit: UInt64 = 128 * 1024 * 1024
    /// 内存缓存（NSCache，自动响应内存压力，上限 60MB / 300 条）
    private let memCache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 300
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()
    /// 解码结果缓存：网格卡片每次进入视口都会对同一 URL 请求缩略图，
    /// 缓存解码后的 NSImage 避免重复解析 JPEG（压缩数据仍由 memCache/磁盘缓存）
    private nonisolated let decodedImageCache = DecodedThumbnailMemoryCache(
        countLimit: 120, totalCostLimit: 64 * 1024 * 1024)

    /// Ready pixels only; safe for a synchronous main-thread card reuse.
    nonisolated func readyImage(for url: URL, maxPixelSize: Int) -> NSImage? {
        decodedImageCache.object(forKey: "\(url.absoluteString)@\(maxPixelSize)" as NSString)
    }

    private let requestCoordinator: OLThumbnailRequestCoordinator
    private var cacheGeneration = 0
    private struct DecodeKey: Hashable, Sendable {
        let url: URL
        let pixelSize: Int
        let generation: Int
        let data: Data
    }
    private struct DecodeRequest {
        let id: UUID
        let operation: OLThumbnailDecodeOperation
        var persistsSourceData: Bool
        var consumers: [UUID: CheckedContinuation<NSImage?, Never>]
    }
    private var decoding: [DecodeKey: DecodeRequest] = [:]
    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.mywallpaper.onlinelibrary.thumbnail.decode"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(requestCoordinator: OLThumbnailRequestCoordinator = .shared) {
        self.requestCoordinator = requestCoordinator
        Task { await self.evictExpired() }
    }

    /// 取缓存（内存 → 磁盘），返回 nil 表示无缓存
    func cachedData(for url: URL) -> Data? {
        let key = url.absoluteString as NSString
        if let data = memCache.object(forKey: key) { return data as Data }
        let file = cacheFile(for: url)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: file)
        else { return nil }
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    func publicationGeneration() -> Int { cacheGeneration }

    /// Requests capture this generation before waiting for the network.
    func store(data: Data, for url: URL, generation: Int) {
        guard generation == cacheGeneration else { return }
        let key = url.absoluteString as NSString
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        let file = cacheFile(for: url)
        try? data.write(to: file, options: .atomic)
        // 同次限频扫描先删除过期文件，再对剩余缓存执行原容量淘汰。
        ThumbnailCache.trimDiskCache(directory: cacheDir, sizeLimit: diskSizeLimit,
            expireBefore: Date().addingTimeInterval(-maxAge))
    }

    /// 清空缓存（内存 + 磁盘）：设置「清除缓存」统一入口调用
    func clearAll() {
        cacheGeneration &+= 1
        let requests = Array(decoding.values)
        decoding.removeAll()
        for request in requests {
            request.operation.cancel()
            request.consumers.values.forEach { $0.resume(returning: nil) }
        }
        memCache.removeAllObjects()
        decodedImageCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: 解码结果缓存

    /// Captures the clear epoch before either disk or network work begins.
    func image(for url: URL, maxPixelSize: Int, priority: OLThumbnailRequestPriority) async -> NSImage? {
        let generation = cacheGeneration
        if let image = await cachedImage(for: url, maxPixelSize: maxPixelSize, priority: priority) {
            return !Task.isCancelled && generation == cacheGeneration ? image : nil
        }
        guard !Task.isCancelled, generation == cacheGeneration,
              let data = await requestCoordinator.loadData(from: url, priority: priority),
              !Task.isCancelled, generation == cacheGeneration else { return nil }
        return await storeAndDecode(data: data, for: url, maxPixelSize: maxPixelSize,
            generation: generation, priority: priority)
    }

    func cachedImage(for url: URL, maxPixelSize: Int = 800,
        priority: OLThumbnailRequestPriority = .visible) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(url.absoluteString)@\(maxPixelSize)" as NSString
        if let image = decodedImageCache.object(forKey: key) { return image }
        let generation = cacheGeneration
        guard let data = cachedData(for: url),
              let image = await decode(data, for: url, maxPixelSize: maxPixelSize,
                generation: generation, priority: priority, persistsSourceData: false),
              !Task.isCancelled, generation == cacheGeneration else { return nil }
        return image
    }

    func storeAndDecode(data: Data, for url: URL, maxPixelSize: Int = 800,
        generation: Int, priority: OLThumbnailRequestPriority = .visible) async -> NSImage? {
        guard !Task.isCancelled, generation == cacheGeneration,
              let image = await decode(data, for: url, maxPixelSize: maxPixelSize,
                generation: generation, priority: priority, persistsSourceData: true),
              !Task.isCancelled, generation == cacheGeneration else { return nil }
        return image
    }

    private func decode(_ data: Data, for url: URL, maxPixelSize: Int, generation: Int,
        priority: OLThumbnailRequestPriority, persistsSourceData: Bool) async -> NSImage? {
        let key = DecodeKey(url: url, pixelSize: maxPixelSize, generation: generation, data: data)
        let consumerID = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled, generation == cacheGeneration else { return nil }
            return await withCheckedContinuation { continuation in
                if var request = decoding[key] {
                    request.consumers[consumerID] = continuation
                    request.persistsSourceData = request.persistsSourceData || persistsSourceData
                    if priority == .visible {
                        request.operation.queuePriority = .veryHigh
                        if !request.operation.isExecuting { request.operation.qualityOfService = .userInitiated }
                    }
                    decoding[key] = request
                    return
                }
                let requestID = UUID()
                let operation = OLThumbnailDecodeOperation(data: data, maxPixelSize: maxPixelSize)
                operation.queuePriority = priority == .visible ? .veryHigh : .low
                operation.qualityOfService = priority == .visible ? .userInitiated : .utility
                operation.completionBlock = { [weak self, weak operation] in
                    let image = operation?.isCancelled == false ? operation?.image : nil
                    Task { await self?.finishDecode(key: key, requestID: requestID, image: image) }
                }
                decoding[key] = DecodeRequest(id: requestID, operation: operation,
                    persistsSourceData: persistsSourceData, consumers: [consumerID: continuation])
                decodeQueue.addOperation(operation)
            }
        } onCancel: { Task { await self.cancelDecodeConsumer(consumerID, key: key) } }
    }

    private func cancelDecodeConsumer(_ id: UUID, key: DecodeKey) {
        guard var request = decoding[key], let continuation = request.consumers.removeValue(forKey: id) else { return }
        continuation.resume(returning: nil)
        if request.consumers.isEmpty {
            decoding.removeValue(forKey: key)
            request.operation.cancel()
        } else { decoding[key] = request }
    }

    private func finishDecode(key: DecodeKey, requestID: UUID, image: NSImage?) {
        guard let request = decoding[key], request.id == requestID else { return }
        let result = key.generation == cacheGeneration ? image : nil
        if let result {
            // Publish once before resuming any consumer. This closes the gap in
            // which a new card could start the same decode before its first
            // consumer had resumed and populated the ready tier.
            decodedImageCache.setObject(result, forKey: "\(key.url.absoluteString)@\(key.pixelSize)" as NSString,
                cost: Self.decodedImageCost(result))
            if request.persistsSourceData { store(data: key.data, for: key.url, generation: key.generation) }
        }
        decoding.removeValue(forKey: key)
        request.consumers.values.forEach { $0.resume(returning: result) }
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
