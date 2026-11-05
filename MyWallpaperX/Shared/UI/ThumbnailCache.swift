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

    /// 磁盘缓存 namespace：同一缓存根目录下按 `<ns>/` 子目录隔离，
    /// 「清除缓存」可按 namespace 实例级清空，不再整根互殃。
    private let namespace: String
    private let writeEncodedData: @Sendable (Data, URL) throws -> Void

    /// 失败负缓存（可选，默认关闭）：输入解码或异步图像生成失败后复用 nil，避免重复 IO/解码。
    /// 指纹键随内容变化失效；SIL 使用路径键，由 Provider 核对失败来源签名。
    /// 源变化或原失败来源未知时，Provider 撤销旧失败，使实际需求重新解码。
    private let failureCache: NSCache<NSString, NSNumber>?

    private let decodeQueue: DispatchQueue
    private let generationQueue: DispatchQueue
    private let sourceQueue: DispatchQueue
    private let maintenanceQueue: DispatchQueue
    private let imageCache: DecodedThumbnailMemoryCache
    private enum RequestKey: Hashable { case image(String, ThumbnailRequest? = nil, Data? = nil), raw(String) }
    private enum SourcePublication {
        case none, required(@Sendable () async -> Bool), published
    }
    private final class Request: @unchecked Sendable {
        var sourcePublication = SourcePublication.none
        var consumers: [UUID: ThumbnailCacheRequestPriority] = [:]
        var pinnedPriority: ThumbnailCacheRequestPriority?
        var priority: ThumbnailCacheRequestPriority {
            max(pinnedPriority ?? .prefetch, consumers.values.max() ?? .prefetch)
        }
        // Invalidation revokes this request's cache permission; joining cannot restore it.
        var allowsCaching = true
        var sourceDataKey: String?
        var onPriorityPromotion: (@Sendable () -> Void)?
        var task: Task<Void, Never>?
        var publishedImage: NSImage?
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
    /// 放 Caches 与 OnlineImageThumbnailCache、Steam 下载管线两处磁盘缓存对齐（系统可回收、不进备份）。
    private static let diskCacheRoot: URL = {
        let bundleID = Bundle.main.bundleIdentifier ?? "MyWallpaperX"
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleID)
            .appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
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
    ///     视频库 128MB（VideoLibraryThumbnailStore）、SIL 192MB（SILThumbnailStore）、
    ///     Pixabay下载项 50MB（PixabayDownloadedThumbnailStore）
    ///   - namespace: 磁盘缓存子目录名，必填，新实例必须声明自己的隔离空间
    ///   - usesFailureCache: 是否启用失败负缓存（见 failureCache 注释）
    init(label: String = "com.mywallpaper.thumbnail.decode",
         countLimit: Int = 360,
         totalCostLimit: Int = 128 * 1024 * 1024,
         namespace: String,
         usesFailureCache: Bool = false,
         writeEncodedData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }) {
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
    /// media generation. A nil cancellation pins its shared work.
    /// cachesFailure controls negative lookup/creation; a successful cached
    /// image still retires an older failure for the same key.
    func load(
        forKey key: String,
        request target: ThumbnailRequest? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        cachesFailure: Bool = true,
        input: ThumbnailInput,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let request = beginImageRequest(key: key, target: target, priority: priority,
                cancellation: cancellation, checksFailure: cachesFailure, completion: completion) else { return }
        enqueue(key: .image(key, target), request: request, lane: .decode) { [self] done in
            defer { done() }
            let outputURL = diskCacheURL(for: key)
            if let image = storedImage(at: outputURL, decoder: { GridThumbnailDecoder.decodeStoredImage($0, request: target) }) {
                finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target)
                return
            }
            enqueue(key: .image(key, target), request: request, lane: .source) { [self] sourceFinished in
                defer { sourceFinished() }
                guard isCurrent(request, key: .image(key, target)) else { return }
                let image = GridThumbnailDecoder.decodeInput(input, request: target)
                finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target,
                    encodedData: input.persistsImage ? image.flatMap { Self.jpegData($0.image) } : nil,
                    cachesFailure: cachesFailure)
            }
        }
    }

    /// The hook is one successful-source publication action, shared by joiners.
    /// Registration is synchronous; preparation never acquires a source slot.
    func prepare(
        _ data: Data,
        forKey key: String,
        request target: ThumbnailRequest? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        beforePublication: (@Sendable () async -> Bool)? = nil
    ) -> AsyncStream<NSImage?> {
        let signature = Data(SHA256.hash(data: data))
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellation = ThumbnailCacheRequestCancellation()
            continuation.onTermination = { _ in cancellation.cancel() }
            let complete: (NSImage?) -> Void = { image in
                cancellation.clearCancellationHandler()
                if !cancellation.cancelled { continuation.yield(image); continuation.finish() }
            }
            let cached = imageCache.object(forKey: key as NSString, request: target, signature: signature)
                ?? inFlightReadyImage(key: key, target: target, signature: signature)
            if let cached, beforePublication == nil { complete(cached); return }
            guard let request = registerImageRequest(key: key, target: target, signature: signature,
                priority: priority, cancellation: cancellation, beforePublication: beforePublication,
                completion: complete) else { return }
            let requestKey = RequestKey.image(key, target, signature)
            if let cached {
                publishPreparation(request, key: requestKey, hasImage: true) { accepted in
                    self.finishCachedImageRequest(request, key: requestKey, image: accepted ? cached : nil)
                }
            } else {
                enqueue(key: requestKey, request: request, lane: .decode) { [self] done in
                    let image = autoreleasepool { GridThumbnailDecoder.decodeInput(.sourceData(data), request: target) }
                    publishPreparation(request, key: requestKey, hasImage: image != nil, done: done) { accepted in
                        self.finishImageRequest(request, key: key, outputURL: nil,
                            image: accepted ? image : nil, target: target, signature: signature)
                    }
                }
            }
        }
    }

    private func publishPreparation(_ request: Request, key: RequestKey, hasImage: Bool,
                                    done: @escaping @Sendable () -> Void = {},
                                    finish: @escaping (Bool) -> Bool) {
        let task = Task { [self] in
            defer { done() }
            var accepted = true
            // none can upgrade to required once; taking it marks published.
            // finish atomically rejects a late upgrade, so at most two passes run.
            while !Task.isCancelled, isCurrent(request, key: key) {
                if hasImage, let publish = takeSourcePublication(request, key: key) { accepted = await publish() }
                if finish(accepted) { return }
            }
        }
        install(task: task, request: request, key: key)
    }

    private func takeSourcePublication(_ request: Request, key: RequestKey) -> (@Sendable () async -> Bool)? {
        lock.lock(); defer { lock.unlock() }
        guard requests[key] === request, case .required(let publish) = request.sourcePublication else { return nil }
        request.sourcePublication = .published
        return publish
    }

    private func finishCachedImageRequest(_ request: Request, key: RequestKey, image: NSImage?) -> Bool {
        lock.lock()
        guard requests[key] === request else { lock.unlock(); return false }
        if image != nil, case .required = request.sourcePublication { lock.unlock(); return false }
        let completions = retireImageLocked(request, key: key)
        lock.unlock()
        completions.forEach { $0(image) }
        return true
    }

    /// One generation slot spans the source callback, composition and publication.
    func loadImageAsync(
        forKey key: String,
        request target: ThumbnailRequest? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        loader: @escaping @Sendable () async -> ThumbnailInput?,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let request = beginImageRequest(key: key, target: target, priority: priority,
                cancellation: cancellation, checksFailure: true, completion: completion) else { return }
        enqueue(key: .image(key, target), request: request, lane: .decode) { [self] done in
            defer { done() }
            let outputURL = diskCacheURL(for: key)
            if let image = storedImage(at: outputURL, decoder: { GridThumbnailDecoder.decodeStoredImage($0, request: target) }) {
                finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target)
                return
            }
            enqueue(key: .image(key, target), request: request, lane: .generation) { [self] generated in
                let task = Task { [self] in
                    guard !Task.isCancelled, self.isCurrent(request, key: .image(key, target)) else { generated(); return }
                    let input = await loader()
                    guard !Task.isCancelled, self.isCurrent(request, key: .image(key, target)) else { generated(); return }
                    let priority = self.currentPriority(request, key: .image(key, target))
                    self.generationQueue.async(qos: priority == .visible ? .userInitiated : .utility) { [self] in
                        // This handoff always runs, including after the final consumer cancels.
                        defer { generated() }
                        guard isCurrent(request, key: .image(key, target)) else { return }
                        let image = input.flatMap { GridThumbnailDecoder.decodeInput($0, request: target) }
                        finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target,
                            encodedData: input?.persistsImage == true ? image.flatMap { Self.jpegData($0.image) } : nil,
                            cachesFailure: true)
                    }
                }
                install(task: task, request: request, key: .image(key, target))
            }
        }
    }

    /// Network waiting is asynchronous; returned data enters the bounded short
    /// decode lane, so an actor/Task hop cannot silently create unbounded decode.
    func loadImageDataAsync(
        forKey key: String,
        request target: ThumbnailRequest? = nil,
        sourceDataKey: String? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        loader: @escaping @Sendable () async -> Data?,
        decoder: @escaping @Sendable (Data) -> NSImage? = { NSImage(data: $0) },
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) {
        loadImageDataAsync(forKey: key, request: target, sourceDataKey: sourceDataKey, priority: priority,
            onPriorityPromotion: onPriorityPromotion, loader: { _ in await loader() },
            decoder: decoder, cancellation: cancellation, completion: completion)
    }

    /// The provider must be read by a downstream scheduler at registration,
    /// without suspending between that read and insertion. The promotion hook
    /// covers visible consumers joining after downstream registration.
    func loadImageDataAsync(
        forKey key: String,
        request target: ThumbnailRequest? = nil,
        sourceDataKey: String? = nil,
        priority: ThumbnailCacheRequestPriority = .visible,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        loader: @escaping @Sendable (@escaping @Sendable () -> ThumbnailCacheRequestPriority) async -> Data?,
        decoder: @escaping @Sendable (Data) -> NSImage? = { NSImage(data: $0) },
        cancellation: (any ThumbnailCacheLoadCancellation)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let request = beginImageRequest(key: key, target: target, priority: priority,
                cancellation: cancellation, sourceDataKey: sourceDataKey,
                onPriorityPromotion: onPriorityPromotion, completion: completion) else { return }
        enqueue(key: .image(key, target), request: request, lane: .decode) { [self] done in
            defer { done() }
            let outputURL = diskCacheURL(for: key)
            if let image = storedImage(at: outputURL, decoder: { decoder($0).flatMap { GridThumbnailDecoder.Image($0, nativeSize: nil) } }) {
                finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target)
                return
            }
            let sourceDataURL = sourceDataKey.map { diskCacheURL(for: $0) }
            if let sourceDataURL, let image = storedImage(at: sourceDataURL, decoder: { decoder($0).flatMap { GridThumbnailDecoder.Image($0, nativeSize: nil) } }) {
                finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target, encodedData: Self.pngData(image.image))
                return
            }
            enqueue(key: .image(key, target), request: request, lane: .source) { [self] sourceFinished in
                let task = Task { [self] in
                    var transferred = false
                    defer { if !transferred { sourceFinished() } }
                    guard !Task.isCancelled else { return }
                    let data = await loader { [weak self, request] in
                        self?.currentPriority(request, key: .image(key, target)) ?? .prefetch
                    }
                    guard !Task.isCancelled, self.isCurrent(request, key: .image(key, target)) else { return }
                    transferred = true
                    self.enqueue(key: .image(key, target), request: request, lane: .decode,
                            onAbandon: sourceFinished) { [self] decoded in
                        defer { decoded(); sourceFinished() }
                        let image = data.flatMap(decoder).flatMap { GridThumbnailDecoder.Image($0, nativeSize: nil) }
                        finishImageRequest(request, key: key, outputURL: outputURL, image: image, target: target,
                            encodedData: sourceDataKey == nil ? nil : image.flatMap { Self.pngData($0.image) },
                            sourceData: image == nil ? nil : data, sourceDataURL: sourceDataURL ?? outputURL)
                    }
                }
                install(task: task, request: request, key: .image(key, target))
            }
        }
    }

    /// Registers every image path with the same request owner. Only the creator
    /// receives a request to start; joining consumers update its pending priority.
    private func beginImageRequest(
        key: String, target: ThumbnailRequest? = nil, priority: ThumbnailCacheRequestPriority,
        cancellation: (any ThumbnailCacheLoadCancellation)?,
        sourceDataKey: String? = nil, checksFailure: Bool = false,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) -> Request? {
        guard cancellation?.cancelled != true else { return nil }
        if let cached = cachedImage(forKey: key, request: target) { completion(cached); return nil }
        if checksFailure, failureCache?.object(forKey: key as NSString) != nil { completion(nil); return nil }
        let deliver: (NSImage?) -> Void = { image in
            DispatchQueue.main.async {
                cancellation?.clearCancellationHandler()
                if cancellation?.cancelled != true { completion(image) }
            }
        }
        return registerImageRequest(key: key, target: target, priority: priority,
            cancellation: cancellation, sourceDataKey: sourceDataKey,
            onPriorityPromotion: onPriorityPromotion, completion: deliver)
    }

    private func registerImageRequest(
        key: String, target: ThumbnailRequest?, signature: Data? = nil, priority: ThumbnailCacheRequestPriority,
        cancellation: (any ThumbnailCacheLoadCancellation)?, sourceDataKey: String? = nil,
        onPriorityPromotion: (@Sendable () -> Void)? = nil,
        beforePublication: (@Sendable () async -> Bool)? = nil,
        completion: @escaping (NSImage?) -> Void
    ) -> Request? {
        let consumer = UUID()
        let requestKey = RequestKey.image(key, target, signature)
        lock.lock()
        if let previous = requests[requestKey], previous.publishedImage != nil {
            _ = retireImageLocked(previous, key: requestKey)
        }
        let startsProducer = requests[requestKey] == nil
        let request = requests[requestKey] ?? Request()
        if startsProducer {
            request.sourceDataKey = sourceDataKey
            request.onPriorityPromotion = onPriorityPromotion
            requests[requestKey] = request
        }
        if let beforePublication, case .none = request.sourcePublication {
            request.sourcePublication = .required(beforePublication)
        }
        let previousPriority = request.priority
        request.imageCompletions[consumer] = completion
        register(consumer: consumer, priority: priority, cancellation: cancellation, request: request)
        let promotion = !startsProducer && previousPriority == .prefetch && request.priority == .visible
            ? request.onPriorityPromotion : nil
        lock.unlock()
        promotion?()
        cancellation?.installCancellationHandler { [weak self] in
            self?.detachConsumer(consumer, key: requestKey, request: request)
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
        request.publishedImage = nil
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

    /// Two short IO/decode slots, one media-generation slot, and four sources
    /// (known inputs or async acquisition, at most two admitted as
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

    private func storedImage(at url: URL, decoder: (Data) -> GridThumbnailDecoder.Image?) -> GridThumbnailDecoder.Image? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decoder(data)
    }

    @discardableResult
    private func finishImageRequest(_ request: Request, key: String, outputURL: URL?,
                                    image: GridThumbnailDecoder.Image?, target: ThumbnailRequest? = nil, signature: Data? = nil,
                                    encodedData: @autoclosure () -> Data? = nil, sourceData: Data? = nil, sourceDataURL: URL? = nil,
                                    cachesFailure: Bool = false) -> Bool {
        let requestKey = RequestKey.image(key, target, signature)
        lock.lock()
        guard requests[requestKey] === request else { lock.unlock(); return false }
        if image != nil, case .required = request.sourcePublication { lock.unlock(); return false }
        let allowsCaching = request.allowsCaching
        lock.unlock()
        let display = image.flatMap { GridThumbnailDecoder.render($0, request: target) }
        let displayImage = display?.image
        let rawStaged = allowsCaching ? stageEncodedData(sourceDataURL == nil ? nil : sourceData) : nil
        var staged = display == nil && allowsCaching ? stageEncodedData(encodedData()) : nil
        defer {
            if let staged { try? FileManager.default.removeItem(at: staged) }
            if let rawStaged { try? FileManager.default.removeItem(at: rawStaged) }
        }
        lock.lock()
        guard requests[requestKey] === request else { lock.unlock(); return false }
        if display != nil, case .required = request.sourcePublication { lock.unlock(); return false }
        if request.allowsCaching {
            if let rawStaged, let sourceDataURL { _ = rename(rawStaged.path, sourceDataURL.path) }
            if let staged, let outputURL { _ = rename(staged.path, outputURL.path) }
            if let display {
                failureCache?.removeObject(forKey: key as NSString)
                imageCache.setObject(display.image, forKey: key as NSString, cost: display.cost,
                    pixels: display.pixels, nativeSize: display.nativeSize, crop: display.crop, signature: signature,
                    preservingCompatibleResults: true)
            } else if cachesFailure { failureCache?.setObject(NSNumber(value: true), forKey: key as NSString) }
        }
        let completions: [(NSImage?) -> Void]
        if display != nil {
            request.publishedImage = displayImage
            completions = Array(request.imageCompletions.values)
            request.imageCompletions.removeAll()
        } else {
            completions = retireImageLocked(request, key: requestKey)
        }
        lock.unlock()
        completions.forEach { $0(displayImage) }
        if display != nil {
            lock.lock()
            let allowsPersistence = requests[requestKey] === request && request.allowsCaching
            lock.unlock()
            if allowsPersistence { staged = stageEncodedData(encodedData()) }
            lock.lock()
            if requests[requestKey] === request {
                if request.allowsCaching, let staged, let outputURL { _ = rename(staged.path, outputURL.path) }
                _ = retireImageLocked(request, key: requestKey)
            }
            lock.unlock()
        }
        if staged != nil || rawStaged != nil { DispatchQueue.main.async { self.scheduleMaintenance() } }
        return true
    }

    private func retireImageLocked(_ request: Request, key: RequestKey) -> [(NSImage?) -> Void] {
        let completions = Array(request.imageCompletions.values)
        request.imageCompletions.removeAll()
        requests.removeValue(forKey: key)
        request.task = nil
        request.publishedImage = nil
        return completions
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
            let outputURL = diskCacheURL(for: key)
            if let data = try? Data(contentsOf: outputURL) {
                finishRawData(request, key: key, outputURL: outputURL, data: data, persist: false)
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
                        finishRawData(request, key: key, outputURL: outputURL, data: data, persist: true)
                    }
                }
                install(task: task, request: request, key: .raw(key))
            }
        }
    }

    private func finishRawData(_ request: Request, key: String, outputURL: URL, data: Data?, persist: Bool) {
        lock.lock()
        guard requests[.raw(key)] === request else { lock.unlock(); return }
        let allowsCaching = request.allowsCaching
        lock.unlock()
        let staged = allowsCaching ? stageEncodedData(persist ? data : nil) : nil
        defer { if let staged { try? FileManager.default.removeItem(at: staged) } }
        lock.lock()
        guard requests[.raw(key)] === request else { lock.unlock(); return }
        if request.allowsCaching, let staged { _ = rename(staged.path, outputURL.path) }
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

    /// Explicitly clear this namespace as one transaction. Existing consumers
    /// still finish, while their old producers cannot refill any cache tier.
    func clearAll(cancelInFlight: Bool = false, completion: (@Sendable () -> Void)? = nil) {
        lock.lock()
        for request in requests.values { request.allowsCaching = false }
        let retire = cancelInFlight ? retireRequestsLocked(Array(requests.keys)) : {}
        imageCache.removeAllObjects()
        failureCache?.removeAllObjects()
        // Only constant-time same-volume metadata changes share publication's
        // lock. Recursive deletion cannot hold that lock or delete new writes.
        let retired = diskCacheDir.appendingPathExtension("clear-" + UUID().uuidString)
        let detached = rename(diskCacheDir.path, retired.path) == 0
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
        lock.unlock()
        retire()
        maintenanceQueue.async {
            if detached { try? FileManager.default.removeItem(at: retired) }
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        // Existing consumers may finish their shared fetch, but it cannot
        // repopulate an explicitly invalidated cache after this deletion.
        for (requestKey, request) in requests {
            switch requestKey {
            case .image(let source, _, _), .raw(let source):
                if source == key || request.sourceDataKey == key { request.allowsCaching = false }
            }
        }
        imageCache.removeObject(forKey: key as NSString)
        failureCache?.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: diskCacheURL(for: key))
    }

    /// Scope invalidation only retires matching image requests and ready pixels.
    func removeImages(withKeyPrefix prefix: String, cancelInFlight: Bool = false) {
        lock.lock()
        let keys = requests.keys.filter {
            if case .image(let source, _, _) = $0 { return source.hasPrefix(prefix) }
            return false
        }
        for key in keys { requests[key]?.allowsCaching = false }
        let retire = cancelInFlight ? retireRequestsLocked(keys) : {}
        imageCache.removeObjects(withKeyPrefix: prefix)
        lock.unlock()
        retire()
    }

    /// Called under the request lock; callbacks and cancellation run outside it.
    private func retireRequestsLocked(_ keys: [RequestKey]) -> () -> Void {
        let retired = keys.compactMap { requests.removeValue(forKey: $0) }
        let identities = Set(retired.map { ObjectIdentifier($0) })
        var abandoned: [@Sendable () -> Void] = []
        func remove(_ queue: inout [Work]) {
            queue.removeAll {
                guard identities.contains(ObjectIdentifier($0.request)) else { return false }
                if let handler = $0.onAbandon { abandoned.append(handler) }
                return true
            }
        }
        remove(&pendingDecode); remove(&pendingGeneration); remove(&pendingSource)
        let tasks = retired.compactMap { $0.task }
        let images = retired.flatMap { $0.imageCompletions.values }
        let raw = retired.flatMap { $0.rawCompletions.values }
        for request in retired {
            request.task = nil; request.publishedImage = nil
            request.imageCompletions.removeAll(); request.rawCompletions.removeAll()
        }
        return {
            tasks.forEach { $0.cancel() }; abandoned.forEach { $0() }
            images.forEach { $0(nil) }
            DispatchQueue.main.async { raw.forEach { $0(nil) } }
        }
    }

    /// 同步读取内存缓存，不触发磁盘 IO。
    func cachedImage(forKey key: String, request: ThumbnailRequest? = nil) -> NSImage? {
        imageCache.object(forKey: key as NSString, request: request)
            ?? inFlightReadyImage(key: key, target: request)
    }

    private func inFlightReadyImage(key: String, target: ThumbnailRequest?, signature: Data? = nil) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let request = requests[.image(key, target, signature)], request.allowsCaching else { return nil }
        return request.publishedImage
    }

    /// A completed image or negative result is warm; an invalidated producer's
    /// uncached nil is retryable. This query never reads disk or starts work.
    func hasCachedResult(forKey key: String, request: ThumbnailRequest? = nil) -> Bool {
        imageCache.containsObject(forKey: key as NSString, request: request)
            || inFlightReadyImage(key: key, target: request) != nil
            || failureCache?.object(forKey: key as NSString) != nil
    }

    func hasCachedFailure(forKey key: String) -> Bool {
        failureCache?.object(forKey: key as NSString) != nil
    }

    /// 共享磁盘惰性淘汰：总量上限 + 限频扫描 + LRU 淘汰。
    /// ThumbnailCache 自身与 OnlineImageThumbnailCache、Steam 下载管线接入同一机制，不另起第二套；
    /// 限频钟按目录区分，多目录接入时互不挤占扫描窗口。
    /// 可在同次扫描先删除过期文件，再按剩余大小淘汰；返回是否实际执行了扫描。
    @discardableResult
    static func trimDiskCache(
        directory: URL,
        sizeLimit: UInt64,
        interval: TimeInterval = ThumbnailCache.diskTrimInterval,
        expireBefore: Date? = nil
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
            if let expireBefore,
               (values?.contentModificationDate ?? .distantPast) < expireBefore {
                do {
                    try fileManager.removeItem(at: fileURL)
                    continue
                } catch { /* A failed removal still occupies its original LRU bytes. */ }
            }
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
            do {
                try fileManager.removeItem(at: entry.url)
                reclaimed += entry.size
            } catch { /* Keep failed removals charged while trying remaining entries. */ }
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

    private static func pngData(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private static func jpegData(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
