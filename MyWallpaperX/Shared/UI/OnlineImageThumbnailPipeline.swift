//
//  OnlineImageThumbnailPipeline.swift
//  MyWallpaperX — Shared/UI
//

import AppKit
import CryptoKit
import Foundation

/// Shared Pixabay, Wallhaven and Pixiv thumbnail transport/cache.
/// An opaque scope follows one source/session lifetime. Credentials never form cache keys.
nonisolated struct OnlineImageThumbnailRequest: Sendable {
    let url: URL
    let scopeID: String?
    let session: WallpaperNetworkSession?
    let referer: URL?
    let cacheURL: URL

    init(url: URL, scopeID: String? = nil, session: WallpaperNetworkSession? = nil, referer: URL? = nil) {
        self.url = url; self.scopeID = scopeID; self.session = session; self.referer = referer
        if let scopeID {
            let scope = SHA256.hash(data: Data(scopeID.utf8)).map { String(format: "%02x", $0) }.joined()
            let resource = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            cacheURL = URL(string: "mwx-thumbnail://\(scope)/\(resource)")!
        } else { cacheURL = url }
    }

    var hasValidTransport: Bool {
        if let scopeID { return !scopeID.isEmpty && session != nil }
        return session == nil && referer == nil
    }
}

/// Scoped transports may redirect only inside their original origin.
nonisolated private final class OnlineImageThumbnailRedirectPolicy: NSObject, URLSessionTaskDelegate {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let target = request.url
        let originPort = origin.port ?? (origin.scheme == "https" ? 443 : 80)
        let targetPort = target?.port ?? (target?.scheme == "https" ? 443 : 80)
        let sameOrigin = target?.scheme == origin.scheme && target?.host?.lowercased() == origin.host?.lowercased()
            && targetPort == originPort
        completionHandler(sameOrigin ? request : nil)
    }
}

nonisolated enum OnlineImageThumbnailRequestPriority: Sendable {
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

nonisolated private final class OnlineImageThumbnailPriorityState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: OnlineImageThumbnailRequestPriority
    init(_ value: OnlineImageThumbnailRequestPriority) { self.value = value }
    func current() -> OnlineImageThumbnailRequestPriority { lock.lock(); defer { lock.unlock() }; return value }
    func promote() { lock.lock(); value = .visible; lock.unlock() }
}

actor OnlineImageThumbnailRequestCoordinator {
    private struct InFlightRequest {
        let id: UUID
        let task: Task<Void, Never>
        let priority: OnlineImageThumbnailPriorityState
        let scopeID: String?
        var consumers: [UUID: CheckedContinuation<Data?, Never>]
    }

    static let shared = OnlineImageThumbnailRequestCoordinator()
    private let session: WallpaperNetworkSession
    private let scheduler = OnlineImageThumbnailRequestScheduler()
    private var inFlight: [String: InFlightRequest] = [:]

    init(session: WallpaperNetworkSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        configuration.waitsForConnectivity = false
        self.session = WallpaperNetworkSession(configuration: configuration)
    }

    func loadData(from url: URL, priority: OnlineImageThumbnailRequestPriority) async -> Data? {
        await loadData(for: OnlineImageThumbnailRequest(url: url), priority: priority)
    }

    func loadData(for source: OnlineImageThumbnailRequest, priority: OnlineImageThumbnailRequestPriority) async -> Data? {
        guard source.hasValidTransport else { return nil }
        let consumerID = UUID()
        let key = source.cacheURL.absoluteString
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
                let priorityState = OnlineImageThumbnailPriorityState(priority)
                let transport = source.session ?? session
                let task = Task { [scheduler] in
                    let result = await scheduler.run(id: requestID, priority: priority,
                        currentPriority: { priorityState.current() }) {
                        do {
                            var request = URLRequest(url: source.url)
                            request.timeoutInterval = priorityState.current().timeoutInterval
                            request.networkServiceType = priorityState.current().networkServiceType
                            if let referer = source.referer {
                                request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
                            }
                            let policy = source.scopeID == nil ? nil : OnlineImageThumbnailRedirectPolicy(origin: source.url)
                            let (data, response) = try await transport.data(for: request, delegate: policy)
                            guard !Task.isCancelled,
                                  let http = response as? HTTPURLResponse,
                                  (200..<300).contains(http.statusCode) else { return nil as Data? }
                            return data
                        } catch { return nil as Data? }
                    }
                    finish(key: key, requestID: requestID, data: result ?? nil)
                }
                inFlight[key] = InFlightRequest(id: requestID, task: task, priority: priorityState, scopeID: source.scopeID,
                    consumers: [consumerID: continuation])
            }
        } onCancel: {
            Task { await self.cancelConsumer(consumerID, forKey: key) }
        }
    }

    func invalidate(scopeID: String) {
        let keys = inFlight.compactMap { $0.value.scopeID == scopeID ? $0.key : nil }
        for key in keys {
            guard let request = inFlight.removeValue(forKey: key) else { continue }
            request.task.cancel()
            request.consumers.values.forEach { $0.resume(returning: nil) }
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
actor OnlineImageThumbnailRequestScheduler {
    private struct Waiter {
        let id: UUID
        var priority: OnlineImageThumbnailRequestPriority
        let continuation: CheckedContinuation<OnlineImageThumbnailRequestPriority?, Never>
    }
    private var active: [UUID: OnlineImageThumbnailRequestPriority] = [:]
    private var waiting: [Waiter] = []

    func run<T: Sendable>(id: UUID = UUID(), priority: OnlineImageThumbnailRequestPriority,
        currentPriority: (@Sendable () -> OnlineImageThumbnailRequestPriority)? = nil,
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

    private func acquire(id: UUID, priority: OnlineImageThumbnailRequestPriority) async -> OnlineImageThumbnailRequestPriority? {
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

    private func canAcquire(priority: OnlineImageThumbnailRequestPriority) -> Bool {
        let visible = active.values.filter { $0 == .visible }.count
        switch priority {
        case .visible: return visible < 2
        case .prefetch:
            return active.count < 2 && !active.values.contains(.prefetch) && !waiting.contains { $0.priority == .visible }
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

actor OnlineImageThumbnailCache {
    static let shared = OnlineImageThumbnailCache()

    /// Preserve the installed disk-cache namespace across the module rename.
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
    private nonisolated let preparedImages = ThumbnailCache(
        label: "com.mywallpaper.onlineimages.thumbnail.decode", countLimit: 120,
        totalCostLimit: 64 * 1024 * 1024, namespace: "online-image-preparation")

    /// Ready pixels only; membership checks do not promote the LRU entry.
    nonisolated func readyImage(for url: URL, request: ThumbnailRequest) -> NSImage? {
        preparedImages.cachedImage(forKey: url.absoluteString, request: request)
    }

    nonisolated func readyImage(for source: OnlineImageThumbnailRequest, request: ThumbnailRequest) -> NSImage? {
        guard source.hasValidTransport else { return nil }
        return readyImage(for: source.cacheURL, request: request)
    }

    nonisolated func hasReadyImage(for url: URL, request: ThumbnailRequest) -> Bool {
        preparedImages.hasCachedResult(forKey: url.absoluteString, request: request)
    }

    nonisolated func hasReadyImage(for source: OnlineImageThumbnailRequest, request: ThumbnailRequest) -> Bool {
        source.hasValidTransport && hasReadyImage(for: source.cacheURL, request: request)
    }

    private let requestCoordinator: OnlineImageThumbnailRequestCoordinator
    private var cacheGeneration = 0
    private struct ScopeStamp: Hashable, Sendable { let id: String; let revision: UUID }
    private struct ScopeState {
        let revision = UUID()
        let keyPrefix: String
        var urls: Set<URL> = []
    }
    private var scopes: [String: ScopeState] = [:]
    private var invalidatingScopes: [String: Int] = [:]
    init(requestCoordinator: OnlineImageThumbnailRequestCoordinator = .shared) {
        self.requestCoordinator = requestCoordinator
        Task { await self.evictExpired() }
    }

    /// 取缓存（内存 → 磁盘），返回 nil 表示无缓存
    func cachedData(for url: URL, scopeID: String? = nil) -> Data? {
        let key = url.absoluteString as NSString
        if let data = memCache.object(forKey: key) { registerRaw(url, scopeID: scopeID); return data as Data }
        let file = cacheFile(for: url)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: file)
        else { return nil }
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        registerRaw(url, scopeID: scopeID)
        return data
    }

    func publicationGeneration() -> Int { cacheGeneration }

    /// Only URLs registered by this scope are removed; other sources keep their cache and leases.
    func invalidate(scopeID: String) async {
        invalidatingScopes[scopeID, default: 0] += 1
        if let scope = scopes.removeValue(forKey: scopeID) {
            for url in scope.urls {
                memCache.removeObject(forKey: url.absoluteString as NSString)
            }
            preparedImages.removeImages(withKeyPrefix: scope.keyPrefix, cancelInFlight: true)
            // Disk eviction already bounds these files. Inspect names once on
            // account change instead of retaining every URL ever requested.
            for file in (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? [] {
                let name = file.lastPathComponent.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
                guard let data = Data(base64Encoded: name), let key = String(data: data, encoding: .utf8),
                      key.hasPrefix(scope.keyPrefix) else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
        await requestCoordinator.invalidate(scopeID: scopeID)
        if let count = invalidatingScopes[scopeID], count > 1 { invalidatingScopes[scopeID] = count - 1 }
        else { invalidatingScopes.removeValue(forKey: scopeID) }
    }

    private func register(_ request: OnlineImageThumbnailRequest) -> ScopeStamp? {
        guard let id = request.scopeID else { return nil }
        if scopes[id] == nil { scopes[id] = ScopeState(keyPrefix: "mwx-thumbnail://\(request.cacheURL.host!)/") }
        return ScopeStamp(id: id, revision: scopes[id]!.revision)
    }

    private func registerRaw(_ url: URL, scopeID: String?) {
        guard let id = scopeID, scopes[id] != nil else { return }
        scopes[id]?.urls.insert(url)
        // NSCache is configured for 300 entries. Compact receipts only after a
        // second working set, using memory facts without filesystem polling.
        if let urls = scopes[id]?.urls, urls.count > 600 {
            scopes[id]?.urls = Set(urls.filter { memCache.object(forKey: $0.absoluteString as NSString) != nil })
        }
    }

    private func isCurrent(_ scope: ScopeStamp?) -> Bool {
        scope.map { scopes[$0.id]?.revision == $0.revision } ?? true
    }

    /// Requests capture this generation before waiting for the network.
    func store(data: Data, for url: URL, generation: Int, scopeID: String? = nil) {
        guard generation == cacheGeneration else { return }
        let key = url.absoluteString as NSString
        memCache.setObject(data as NSData, forKey: key, cost: data.count)
        registerRaw(url, scopeID: scopeID)
        let file = cacheFile(for: url)
        try? data.write(to: file, options: .atomic)
        // 同次限频扫描先删除过期文件，再对剩余缓存执行原容量淘汰。
        ThumbnailCache.trimDiskCache(directory: cacheDir, sizeLimit: diskSizeLimit,
            expireBefore: Date().addingTimeInterval(-maxAge))
    }

    /// 清空缓存（内存 + 磁盘）：设置「清除缓存」统一入口调用
    func clearAll() {
        cacheGeneration &+= 1
        memCache.removeAllObjects()
        preparedImages.clearAll(cancelInFlight: true)
        scopes.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Captures the clear epoch before either disk or network work begins.
    func image(for url: URL, request: ThumbnailRequest, priority: OnlineImageThumbnailRequestPriority) async -> NSImage? {
        await image(for: OnlineImageThumbnailRequest(url: url), request: request, priority: priority)
    }

    func image(for source: OnlineImageThumbnailRequest, request: ThumbnailRequest,
               priority: OnlineImageThumbnailRequestPriority) async -> NSImage? {
        guard source.hasValidTransport, source.scopeID.map({ invalidatingScopes[$0] == nil }) ?? true else { return nil }
        let scope = register(source)
        let url = source.cacheURL
        let generation = cacheGeneration
        guard !Task.isCancelled else { return nil }
        if let image = readyImage(for: source, request: request) { return image }
        if let data = cachedData(for: url, scopeID: scope?.id),
           let image = await prepare(data, for: url, request: request, generation: generation,
               priority: priority, scope: scope, persistsSourceData: false) { return image }
        guard !Task.isCancelled, generation == cacheGeneration, isCurrent(scope),
              let data = await requestCoordinator.loadData(for: source, priority: priority) else { return nil }
        return await prepare(data, for: url, request: request, generation: generation,
            priority: priority, scope: scope, persistsSourceData: true)
    }

    private func prepare(_ data: Data, for url: URL, request: ThumbnailRequest, generation: Int,
                         priority: OnlineImageThumbnailRequestPriority, scope: ScopeStamp?,
                         persistsSourceData: Bool) async -> NSImage? {
        guard !Task.isCancelled, generation == cacheGeneration, isCurrent(scope) else { return nil }
        let publish: (@Sendable () async -> Bool)?
        if persistsSourceData {
            publish = { [weak self] in
                await self?.publishSource(data, for: url, generation: generation, scope: scope) ?? false
            }
        } else { publish = nil }
        // No actor suspension separates the freshness check and registration.
        let images = preparedImages.prepare(data, forKey: url.absoluteString, request: request,
            priority: priority == .visible ? .visible : .prefetch, beforePublication: publish)
        for await image in images {
            return !Task.isCancelled && generation == cacheGeneration && isCurrent(scope) ? image : nil
        }
        return nil
    }

    private func publishSource(_ data: Data, for url: URL, generation: Int, scope: ScopeStamp?) -> Bool {
        guard !Task.isCancelled, generation == cacheGeneration, isCurrent(scope) else { return false }
        store(data: data, for: url, generation: generation, scopeID: scope?.id)
        return true
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
