//
//  ThumbnailCache.swift
//  MyWallpaperX
//
//  各模块共用的异步缩略图加载缓存。
//  合并相同键的并发请求（in-flight deduplication），
//  后台解码，主线程回调，有界 LRU 内存缓存 + 按 namespace 隔离的磁盘持久化缓存。
//

import AppKit
import CryptoKit
import Darwin
import ImageIO

/// A consumer cancellation, distinct from the shared producer's task lifetime.
nonisolated protocol ThumbnailCacheLoadCancellation: Sendable {
    var cancelled: Bool { get }
    func installCancellationHandler(_ handler: @escaping @Sendable () -> Void)
    func clearCancellationHandler()
}

/// Concrete per-consumer interest, shared by local module adapters.
nonisolated final class ThumbnailCacheRequestCancellation: ThumbnailCacheLoadCancellation, @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var handler: (@Sendable () -> Void)?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return isCancelled }
    func cancel() {
        lock.lock()
        guard !isCancelled else { lock.unlock(); return }
        isCancelled = true
        let action = handler; handler = nil
        lock.unlock()
        action?()
    }
    func installCancellationHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        guard !isCancelled else { lock.unlock(); handler(); return }
        self.handler = handler
        lock.unlock()
    }
    func clearCancellationHandler() { lock.lock(); handler = nil; lock.unlock() }
}

nonisolated enum ThumbnailCacheRequestPriority: Int, Comparable, Sendable {
    case prefetch, visible
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 异步缩略图加载缓存。
/// 线程安全：并发读写通过 NSLock 保护 in-flight 表，解码图 LRU 自身线程安全。
nonisolated final class ThumbnailCache: @unchecked Sendable {

    /// 缓存容量（最大图片数量）
    private let countLimit: Int

    /// 内存缓存总字节上限（按已解码位图的像素字节数计）
    private let totalCostLimit: Int

    /// 磁盘缓存 namespace：同一缓存根目录下按 `<ns>/` 子目录隔离，
    /// 「清除缓存」可按 namespace 实例级清空，不再整根互殃。
    private let namespace: String
    private let writeEncodedData: @Sendable (Data, URL) throws -> Void

    /// 失败负缓存（可选，默认关闭，仅作用于 load(forKey:loader:completion:)）：
    /// loader 返回 nil 时记录结论，重复加载直接回 nil，避免损坏内容反复触发 IO/解码。
    /// 调用方需让键携带内容指纹（如 mtime+size），内容变化后自然换新键。
    private let failureCache: NSCache<NSString, NSNumber>?

    private let decodeQueue: DispatchQueue
    private let generationQueue: DispatchQueue
    private let sourceQueue: DispatchQueue
    private let maintenanceQueue: DispatchQueue
    private let imageCache: DecodedThumbnailMemoryCache
    private enum RequestKey: Hashable { case image(String), raw(String) }
    private final class Request: @unchecked Sendable {
        var consumers: [UUID: ThumbnailCacheRequestPriority] = [:]
        var pinnedPriority: ThumbnailCacheRequestPriority?
        var priority: ThumbnailCacheRequestPriority {
            max(pinnedPriority ?? .prefetch, consumers.values.max() ?? .prefetch)
        }
        var allowsCaching = true
        var sourceDataKey: String?
        var onPriorityPromotion: (@Sendable () -> Void)?
        var task: Task<Void, Never>?
        var imageCompletions: [UUID: (NSImage?) -> Void] = [:]
        var rawCompletions: [UUID: (Data?) -> Void] = [:]
    }
    private enum WorkLane { case decode, generation, source }
    private final class Work: @unchecked Sendable {
        let key: RequestKey
        let request: Request
        let body: (@escaping @Sendable () -> Void) -> Void
        let onAbandon: (@Sendable () -> Void)?
        init(key: RequestKey, request: Request, onAbandon: (@Sendable () -> Void)?,
             body: @escaping (@escaping @Sendable () -> Void) -> Void) {
            self.key = key; self.request = request
            self.body = body; self.onAbandon = onAbandon
        }
    }
    private var requests: [RequestKey: Request] = [:]
    private var pendingDecode: [Work] = []
    private var pendingGeneration: [Work] = []
    private var pendingSource: [Work] = []
    private var runningDecode = 0
    private var runningGeneration = 0
    private var runningSource = 0
    private var prefetchSourceAdmissions = Set<ObjectIdentifier>()
    private var maintenanceScheduled = false
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
         usesFailureCache: Bool = false,
         writeEncodedData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.namespace = namespace
        self.writeEncodedData = writeEncodedData
        self.failureCache = usesFailureCache ? NSCache<NSString, NSNumber>() : nil
        self.decodeQueue = DispatchQueue(label: label, qos: .utility, attributes: .concurrent)
        self.generationQueue = DispatchQueue(label: label + ".generation", qos: .utility)
        self.sourceQueue = DispatchQueue(label: label + ".source", qos: .utility, attributes: .concurrent)
        self.maintenanceQueue = DispatchQueue(label: label + ".maintenance", qos: .utility)
        failureCache?.countLimit = 256
        imageCache = DecodedThumbnailMemoryCache(countLimit: countLimit, totalCostLimit: totalCostLimit)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 公开接口

    /// Memory hits deliver synchronously. Short disk reads never wait behind
    /// a slow synchronous video generator. A nil cancellation pins legacy work.
    func load(
        forKey key: String,
        priority: ThumbnailCacheRequestPriority = .visible,
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        loader: @escaping () -> NSImage?,
        completion: @escaping (NSImage?) -> Void
    ) {
        loadSynchronously(forKey: key, priority: priority, cancellation: cancellation,
            cachesFailure: true, decoder: Self.decodeStoredImage, generate: {
                let image = loader()
                return (image, image.flatMap(Self.jpegData))
            }, completion: completion)
    }

    /// One media-generation slot spans callback, encoding and publication. A
    /// decoded image is never parked outside that slot in a congested decode lane.
    func loadImageAsync(
        forKey key: String,
        priority: ThumbnailCacheRequestPriority = .visible,
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        loader: @escaping @Sendable () async -> NSImage?,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let request = beginImageRequest(key: key, priority: priority,
                cancellation: cancellation, checksFailure: true, completion: completion) else { return }
        enqueue(key: .image(key), request: request, lane: .decode) { [self] done in
            defer { done() }
            if let image = storedImage(for: key, decoder: Self.decodeStoredImage) {
                finishImageRequest(request, key: key, image: image)
                return
            }
            enqueue(key: .image(key), request: request, lane: .generation) { [self] generated in
                let task = Task { [self] in
                    guard !Task.isCancelled, self.isCurrent(request, key: .image(key)) else { generated(); return }
                    let image = await loader()
                    guard !Task.isCancelled, self.isCurrent(request, key: .image(key)) else { generated(); return }
                    let priority = self.currentPriority(request, key: .image(key))
                    self.generationQueue.async(qos: priority == .visible ? .userInitiated : .utility) { [self] in
                        // This handoff is not removable from pendingDecode.
                        // Even after cancellation it runs and returns its slot.
                        defer { generated() }
                        guard isCurrent(request, key: .image(key)) else { return }
                        finishImageRequest(request, key: key, image: image,
                            encodedData: image.flatMap(Self.jpegData), cachesFailure: true)
                    }
                }
                install(task: task, request: request, key: .image(key))
            }
        }
    }

    /// Retains encoded animation bytes rather than converting them to JPEG.
    func loadImageData(
        forKey key: String,
        priority: ThumbnailCacheRequestPriority = .visible,
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        loader: @escaping () -> Data?,
        decoder: @escaping (Data) -> NSImage? = { NSImage(data: $0) },
        completion: @escaping (NSImage?) -> Void
    ) {
        loadSynchronously(forKey: key, priority: priority, cancellation: cancellation,
            cachesFailure: false, decoder: decoder, generate: {
                guard let data = loader(), let image = decoder(data) else { return (nil, nil) }
                return (image, data)
            }, completion: completion)
    }

    private func loadSynchronously(
        forKey key: String, priority: ThumbnailCacheRequestPriority,
        cancellation: (any ThumbnailCacheLoadCancellation)?, cachesFailure: Bool,
        decoder: @escaping (Data) -> NSImage?,
        generate: @escaping () -> (NSImage?, Data?),
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let request = beginImageRequest(key: key, priority: priority,
                cancellation: cancellation, checksFailure: cachesFailure, completion: completion) else { return }
        enqueue(key: .image(key), request: request, lane: .decode) { [self] done in
            defer { done() }
            if let image = storedImage(for: key, decoder: decoder) {
                finishImageRequest(request, key: key, image: image)
                return
            }
            enqueue(key: .image(key), request: request, lane: .generation) { [self] generated in
                defer { generated() }
                guard isCurrent(request, key: .image(key)) else { return }
                let (image, data) = generate()
                finishImageRequest(request, key: key, image: image,
                    encodedData: data, cachesFailure: cachesFailure)
            }
        }
    }

    /// Network waiting is asynchronous; returned data enters the bounded short
    /// decode lane, so an actor/Task hop cannot silently create unbounded decode.
    func loadImageDataAsync(
        forKey key: String,
        sourceDataKey: String? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        loader: @escaping @Sendable () async -> Data?,
        decoder: @escaping @Sendable (Data) -> NSImage? = { NSImage(data: $0) },
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) {
        loadImageDataAsync(forKey: key, sourceDataKey: sourceDataKey, priority: priority,
            onPriorityPromotion: onPriorityPromotion, loader: { _ in await loader() },
            decoder: decoder, cancellation: cancellation, completion: completion)
    }

    /// The provider must be read by a downstream scheduler at registration,
    /// without suspending between that read and insertion. The promotion hook
    /// covers visible consumers joining after downstream registration.
    func loadImageDataAsync(
        forKey key: String,
        sourceDataKey: String? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        loader: @escaping @Sendable (@escaping @Sendable () -> ThumbnailCacheRequestPriority) async -> Data?,
        decoder: @escaping @Sendable (Data) -> NSImage? = { NSImage(data: $0) },
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let request = beginImageRequest(key: key, priority: priority,
                cancellation: cancellation, sourceDataKey: sourceDataKey,
                onPriorityPromotion: onPriorityPromotion, completion: completion) else { return }
        enqueue(key: .image(key), request: request, lane: .decode) { [self] done in
            defer { done() }
            if let image = storedImage(for: key, decoder: decoder) {
                finishImageRequest(request, key: key, image: image)
                return
            }
            if let sourceDataKey, let image = storedImage(for: sourceDataKey, decoder: decoder) {
                finishImageRequest(request, key: key, image: image, encodedData: Self.pngData(image))
                return
            }
            enqueue(key: .image(key), request: request, lane: .source) { [self] sourceFinished in
                let task = Task { [self] in
                    var transferred = false
                    defer { if !transferred { sourceFinished() } }
                    guard !Task.isCancelled else { return }
                    let data = await loader { [weak self, request] in
                        self?.currentPriority(request, key: .image(key)) ?? .prefetch
                    }
                    guard !Task.isCancelled, self.isCurrent(request, key: .image(key)) else { return }
                    transferred = true
                    self.enqueue(key: .image(key), request: request, lane: .decode,
                            onAbandon: sourceFinished) { [self] decoded in
                        defer { decoded(); sourceFinished() }
                        let image = data.flatMap(decoder)
                        finishImageRequest(request, key: key, image: image,
                            encodedData: sourceDataKey == nil ? (image == nil ? nil : data) : image.flatMap(Self.pngData),
                            sourceData: image == nil ? nil : data, sourceDataKey: sourceDataKey)
                    }
                }
                install(task: task, request: request, key: .image(key))
            }
        }
    }

    /// Registers every image path with the same request owner. Only the creator
    /// receives a request to start; joining consumers update its pending priority.
    private func beginImageRequest(
        key: String, priority: ThumbnailCacheRequestPriority,
        cancellation: (any ThumbnailCacheLoadCancellation)?,
        sourceDataKey: String? = nil, checksFailure: Bool = false,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) -> Request? {
        guard cancellation?.cancelled != true else { return nil }
        if let cached = imageCache.object(forKey: key as NSString) { completion(cached); return nil }
        if checksFailure, failureCache?.object(forKey: key as NSString) != nil { completion(nil); return nil }
        let consumer = UUID()
        let deliver: (NSImage?) -> Void = { image in
            cancellation?.clearCancellationHandler()
            if cancellation?.cancelled != true { completion(image) }
        }
        lock.lock()
        let startsProducer = requests[.image(key)] == nil
        let request = requests[.image(key)] ?? Request()
        if startsProducer {
            request.sourceDataKey = sourceDataKey
            request.onPriorityPromotion = onPriorityPromotion
            requests[.image(key)] = request
        }
        let previousPriority = request.priority
        request.imageCompletions[consumer] = deliver
        register(consumer: consumer, priority: priority, cancellation: cancellation, request: request)
        let promotion = !startsProducer && previousPriority == .prefetch && request.priority == .visible
            ? request.onPriorityPromotion : nil
        lock.unlock()
        promotion?()
        cancellation?.installCancellationHandler { [weak self] in
            self?.detachConsumer(consumer, key: .image(key), request: request)
        }
        return startsProducer ? request : nil
    }

    private func register(consumer: UUID, priority: ThumbnailCacheRequestPriority,
                          cancellation: (any ThumbnailCacheLoadCancellation)?, request: Request) {
        if cancellation != nil { request.consumers[consumer] = priority }
        else { request.pinnedPriority = max(priority, request.pinnedPriority ?? .prefetch) }
        // A promoted source may use reserved visible capacity immediately.
        dispatchPendingLocked(.source)
    }

    private func detachConsumer(_ consumer: UUID, key: RequestKey, request: Request) {
        lock.lock()
        guard requests[key] === request else { lock.unlock(); return }
        request.consumers.removeValue(forKey: consumer)
        request.imageCompletions.removeValue(forKey: consumer)
        request.rawCompletions.removeValue(forKey: consumer)
        guard request.consumers.isEmpty, request.pinnedPriority == nil else { lock.unlock(); return }
        requests.removeValue(forKey: key)
        var abandoned: [@Sendable () -> Void] = []
        pendingDecode.removeAll { work in
            guard work.request === request else { return false }
            if let handler = work.onAbandon { abandoned.append(handler) }
            return true
        }
        pendingGeneration.removeAll { $0.request === request }
        pendingSource.removeAll { $0.request === request }
        let task = request.task
        request.task = nil
        lock.unlock()
        task?.cancel()
        abandoned.forEach { $0() }
    }

    private func isCurrent(_ request: Request, key: RequestKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return requests[key] === request
    }

    private func currentPriority(_ request: Request, key: RequestKey) -> ThumbnailCacheRequestPriority {
        lock.lock(); defer { lock.unlock() }
        return requests[key] === request ? request.priority : .prefetch
    }

    private func install(task: Task<Void, Never>, request: Request, key: RequestKey) {
        lock.lock()
        if requests[key] === request { request.task = task; lock.unlock() }
        else { lock.unlock(); task.cancel() }
    }

    /// Two short IO/decode slots, one media-generation slot, and four async
    /// sources (matching Steam's visible HTTP cap, at most two admitted as
    /// prefetch). Admission class stays fixed when consumer priority changes;
    /// running work is not preempted if its visible consumer leaves. Pending
    /// selection uses current priority. Slots span decode/publication too.
    private func enqueue(key: RequestKey, request: Request, lane: WorkLane,
                         onAbandon: (@Sendable () -> Void)? = nil,
                         body: @escaping (@escaping @Sendable () -> Void) -> Void) {
        lock.lock()
        guard requests[key] === request else { lock.unlock(); onAbandon?(); return }
        let work = Work(key: key, request: request, onAbandon: onAbandon, body: body)
        switch lane {
        case .decode: pendingDecode.append(work)
        case .generation: pendingGeneration.append(work)
        case .source: pendingSource.append(work)
        }
        dispatchPendingLocked(lane)
        lock.unlock()
    }

    private func dispatchPendingLocked(_ lane: WorkLane) {
        while true {
            let work: Work
            switch lane {
            case .decode:
                guard runningDecode < 2, let next = nextWorkIndex(pendingDecode) else { return }
                work = pendingDecode.remove(at: next); runningDecode += 1
            case .generation:
                guard runningGeneration < 1, let next = nextWorkIndex(pendingGeneration) else { return }
                work = pendingGeneration.remove(at: next); runningGeneration += 1
            case .source:
                guard runningSource < 4, let next = nextWorkIndex(pendingSource) else { return }
                if pendingSource[next].request.priority == .prefetch,
                   prefetchSourceAdmissions.count >= 2 { return }
                work = pendingSource.remove(at: next); runningSource += 1
                if work.request.priority == .prefetch {
                    prefetchSourceAdmissions.insert(ObjectIdentifier(work.request))
                }
            }
            let queue: DispatchQueue
            switch lane {
            case .decode: queue = decodeQueue
            case .generation: queue = generationQueue
            case .source: queue = sourceQueue
            }
            queue.async(qos: work.request.priority == .visible ? .userInitiated : .utility) { [self, work] in
                let done: @Sendable () -> Void = { [self] in
                    lock.lock()
                    switch lane {
                    case .decode: runningDecode -= 1
                    case .generation: runningGeneration -= 1
                    case .source:
                        runningSource -= 1
                        prefetchSourceAdmissions.remove(ObjectIdentifier(work.request))
                    }
                    dispatchPendingLocked(lane)
                    lock.unlock()
                }
                guard isCurrent(work.request, key: work.key) else { work.onAbandon?(); done(); return }
                work.body(done)
            }
        }
    }

    private func nextWorkIndex(_ work: [Work]) -> Int? {
        work.indices.max { lhs, rhs in
            let left = work[lhs].request.priority, right = work[rhs].request.priority
            return left == right ? lhs > rhs : left < right
        }
    }

    private func storedImage(for key: String, decoder: (Data) -> NSImage?) -> NSImage? {
        guard let data = try? Data(contentsOf: diskCacheURL(for: key)) else { return nil }
        return decoder(data)
    }

    @discardableResult
    private func finishImageRequest(_ request: Request, key: String, image: NSImage?, encodedData: Data? = nil,
                                    sourceData: Data? = nil, sourceDataKey: String? = nil,
                                    cachesFailure: Bool = false) -> Bool {
        guard isCurrent(request, key: .image(key)) else { return false }
        let staged = stageEncodedData(encodedData)
        let rawStaged = stageEncodedData(sourceDataKey == nil ? nil : sourceData)
        defer {
            if let staged { try? FileManager.default.removeItem(at: staged) }
            if let rawStaged { try? FileManager.default.removeItem(at: rawStaged) }
        }
        lock.lock()
        guard requests[.image(key)] === request else { lock.unlock(); return false }
        if request.allowsCaching {
            if let staged { _ = rename(staged.path, diskCacheURL(for: key).path) }
            if let rawStaged, let sourceDataKey { _ = rename(rawStaged.path, diskCacheURL(for: sourceDataKey).path) }
            if let image { imageCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image)) }
            else if cachesFailure { failureCache?.setObject(NSNumber(value: true), forKey: key as NSString) }
        }
        let completions = Array(request.imageCompletions.values)
        request.imageCompletions.removeAll()
        requests.removeValue(forKey: .image(key))
        request.task = nil
        lock.unlock()
        DispatchQueue.main.async { [self] in
            completions.forEach { $0(image) }
            if staged != nil || rawStaged != nil { scheduleMaintenance() }
        }
        return true
    }

    /// Original animated bytes stay on disk and are not retained as NSImage.
    func loadRawDataAsync(
        forKey key: String,
        priority: ThumbnailCacheRequestPriority = .visible,
        loader: @escaping @Sendable () async -> Data?,
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        completion: @escaping (Data?) -> Void
    ) {
        guard cancellation?.cancelled != true else { return }
        let consumer = UUID()
        let deliver: (Data?) -> Void = { data in
            cancellation?.clearCancellationHandler()
            if cancellation?.cancelled != true { completion(data) }
        }
        lock.lock()
        let startsProducer = requests[.raw(key)] == nil
        let request = requests[.raw(key)] ?? Request()
        if startsProducer { requests[.raw(key)] = request }
        request.rawCompletions[consumer] = deliver
        register(consumer: consumer, priority: priority, cancellation: cancellation, request: request)
        lock.unlock()
        cancellation?.installCancellationHandler { [weak self] in
            self?.detachConsumer(consumer, key: .raw(key), request: request)
        }
        guard startsProducer else { return }
        enqueue(key: .raw(key), request: request, lane: .decode) { [self] done in
            defer { done() }
            if let data = try? Data(contentsOf: diskCacheURL(for: key)) {
                finishRawData(request, key: key, data: data, persist: false)
                return
            }
            enqueue(key: .raw(key), request: request, lane: .source) { [self] sourceFinished in
                let task = Task { [self] in
                    var transferred = false
                    defer { if !transferred { sourceFinished() } }
                    guard !Task.isCancelled else { return }
                    let data = await loader()
                    guard !Task.isCancelled, self.isCurrent(request, key: .raw(key)) else { return }
                    transferred = true
                    self.enqueue(key: .raw(key), request: request, lane: .decode,
                            onAbandon: sourceFinished) { [self] finished in
                        defer { finished(); sourceFinished() }
                        finishRawData(request, key: key, data: data, persist: true)
                    }
                }
                install(task: task, request: request, key: .raw(key))
            }
        }
    }

    private func finishRawData(_ request: Request, key: String, data: Data?, persist: Bool) {
        guard isCurrent(request, key: .raw(key)) else { return }
        let staged = stageEncodedData(persist ? data : nil)
        defer { if let staged { try? FileManager.default.removeItem(at: staged) } }
        lock.lock()
        guard requests[.raw(key)] === request else { lock.unlock(); return }
        if request.allowsCaching, let staged { _ = rename(staged.path, diskCacheURL(for: key).path) }
        let completions = Array(request.rawCompletions.values)
        request.rawCompletions.removeAll()
        requests.removeValue(forKey: .raw(key))
        request.task = nil
        lock.unlock()
        DispatchQueue.main.async { [self] in
            completions.forEach { $0(data) }
            if staged != nil { scheduleMaintenance() }
        }
    }

    /// Expensive staging is outside the request lock; current identity and cache
    /// permission are checked again before publishing either raw or still file.
    private func stageEncodedData(_ data: Data?) -> URL? {
        guard let data else { return nil }
        let staged = diskCacheDir.appendingPathComponent(".thumbnail-\(UUID().uuidString).pending")
        do { try writeEncodedData(data, staged); return staged }
        catch { try? FileManager.default.removeItem(at: staged); return nil }
    }

    private func scheduleMaintenance() {
        lock.lock()
        guard !maintenanceScheduled else { lock.unlock(); return }
        maintenanceScheduled = true
        lock.unlock()
        maintenanceQueue.async { [self] in
            Self.trimDiskCache(directory: diskCacheDir, sizeLimit: Self.diskCacheSizeLimit)
            lock.lock(); maintenanceScheduled = false; lock.unlock()
        }
    }

    /// 清空内存缓存（磁盘缓存保留）
    func removeAll() {
        imageCache.removeAllObjects()
    }

    func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        // Existing consumers may finish their shared fetch, but it cannot
        // repopulate an explicitly invalidated cache after this deletion.
        requests[.image(key)]?.allowsCaching = false
        requests[.raw(key)]?.allowsCaching = false
        for request in requests.values where request.sourceDataKey == key { request.allowsCaching = false }
        imageCache.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: diskCacheURL(for: key))
    }

    /// 同步读取内存缓存，不触发磁盘 IO。
    func cachedImage(forKey key: String) -> NSImage? {
        imageCache.object(forKey: key as NSString)
    }

    /// 清空本实例 namespace 的磁盘缓存（实例级，「清除缓存」显式清单逐目录调用）。
    /// 不提供静态整根清除入口：整根删除会连带删掉其他 namespace 子目录，
    /// 而实例 init 每进程仅执行一次、无目录重建路径，清除后磁盘写入会静默失败。
    func clearDiskCache() {
        lock.lock()
        defer { lock.unlock() }
        for request in requests.values { request.allowsCaching = false }
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

    private func diskCacheURL(for key: String) -> URL {
        // 用 SHA256 哈希作为文件名，避免路径中的特殊字符
        let hash = SHA256.hash(data: Data(key.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    /// 按已解码位图的像素字节数执行 LRU 字节上限淘汰。
    private static func memoryCost(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func decodeStoredImage(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private static func jpegData(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
