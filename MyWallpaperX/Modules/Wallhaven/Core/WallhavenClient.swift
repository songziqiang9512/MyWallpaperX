import Foundation

/// One Wallhaven API queue. Browsing generation and local publication remain with their callers.
actor WallhavenClient {
    private let session: URLSession
    private let ownsSession: Bool
    private let redirectPolicy = WallhavenAPIRedirectPolicy()
    private var apiKey: String?
    private var keyRevision: UInt64 = 0
    private var activeNetworkTask: Task<(Data, URLResponse), Error>?
    private var busy = false
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    private let clock = ContinuousClock()
    private var nextStart: ContinuousClock.Instant?

    init(session: URLSession? = nil, apiKey: String? = nil) {
        if let session { self.session = session; ownsSession = false }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
            ownsSession = true
        }
        self.apiKey = Self.normalizedKey(apiKey)
    }

    deinit {
        activeNetworkTask?.cancel()
        if ownsSession { session.invalidateAndCancel() }
    }

    func setAPIKey(_ value: String?) {
        let value = Self.normalizedKey(value)
        guard value != apiKey else { return }
        apiKey = value
        keyRevision &+= 1
        activeNetworkTask?.cancel()
    }

    func page(query: WallhavenQuery, request: OnlineImagePageRequest = .init()) async throws -> OnlineImagePage {
        if query.purity.last == "1", apiKey == nil {
            throw OnlineImageError.message("访问 NSFW 内容需要填写 Wallhaven API Key。")
        }
        let items = try query.queryItems(page: request.page, seed: request.seed)
        let random = query.sorting == .random
        if random, request.page > 1, request.seed?.isEmpty != false {
            return OnlineImagePage(items: [], next: nil,
                notice: "缺少随机分页种子，已停止连续翻页；请刷新获取新一批。")
        }
        let data = try await fetch(path: "/api/v1/search", items: items)
        let response: WallhavenSearchResponse = try decode(data)
        guard response.meta.currentPage == request.page, response.meta.lastPage > 0,
              response.meta.total >= 0 else { throw OnlineImageError.invalidResponse }
        let seed = response.meta.seed.flatMap { $0.isEmpty ? nil : $0 }
        // W0 observed the service ignoring seeds. Never append a different random batch.
        if random, request.page > 1, seed != request.seed {
            return OnlineImagePage(items: [], next: nil, total: response.meta.total,
                notice: "Wallhaven 未保持随机分页种子，已停止连续翻页；请刷新获取新一批。")
        }
        let artworks = response.data.compactMap { $0.artwork() }
        var notice = artworks.count < response.data.count ? "本页部分作品暂不可读取。" : nil
        if random, seed == nil {
            notice = (notice.map { $0 + " " } ?? "") + "Wallhaven 未提供随机分页种子；刷新可获取新一批。"
        }
        return OnlineImagePage(items: artworks,
            next: (!random || seed != nil) && request.page < response.meta.lastPage
                ? .init(page: request.page + 1, seed: random ? seed : nil) : nil,
            total: response.meta.total,
            notice: notice)
    }

    /// Official authenticated collections endpoint. A successful empty array
    /// describes an account with no collections; it does not invent a username.
    func collections() async throws -> [WallhavenCollection] {
        guard apiKey != nil else { throw OnlineImageError.message("请先配置 Wallhaven API Key。") }
        let response: WallhavenCollectionsResponse = try decode(await fetch(path: "/api/v1/collections", items: []))
        return response.data
    }

    func detail(id: String) async throws -> OnlineImageArtwork {
        guard !id.isEmpty, !id.contains(where: { "/?#".contains($0) }) else {
            throw OnlineImageError.invalidResponse
        }
        let data = try await fetch(path: "/api/v1/w/" + id, items: [])
        let response: WallhavenDetailResponse = try decode(data)
        guard response.data.id.utf8.elementsEqual(id.utf8), let artwork = response.data.artwork() else {
            throw OnlineImageError.invalidResponse
        }
        return artwork
    }

    func assets(for artwork: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        guard artwork.source == .wallhaven else { throw OnlineImageError.unsupported }
        let resolved = artwork.originalURL == nil ? try await detail(id: artwork.artworkID) : artwork
        guard resolved.kind == .image, let original = resolved.originalURL else {
            throw OnlineImageError.unsupported
        }
        return [OnlineImageAsset(id: resolved.firstAssetID, title: resolved.title, sourceURL: resolved.sourceURL,
            originalURL: original, previewURL: resolved.previewURL, author: resolved.author,
            authorID: resolved.authorID, tags: resolved.tags, width: resolved.width, height: resolved.height,
            expectedBytes: resolved.fileSizeBytes, rating: resolved.rating)]
    }

    private func fetch(path: String, items: [URLQueryItem]) async throws -> Data {
        let revision = keyRevision
        let key = apiKey
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard revision == keyRevision else { throw CancellationError() }
        if let nextStart, clock.now < nextStart { try await clock.sleep(until: nextStart) }
        try Task.checkCancellation()
        guard revision == keyRevision else { throw CancellationError() }
        var components = URLComponents()
        components.scheme = "https"; components.host = "wallhaven.cc"; components.path = path
        if !items.isEmpty {
            components.queryItems = items
            // Preserve Wallhaven's literal +tag operator through form-style query decoding.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw OnlineImageError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key { request.setValue(key, forHTTPHeaderField: "X-API-Key") }
        nextStart = clock.now.advanced(by: .seconds(1))
        let session = session, policy = redirectPolicy
        let network = Task { try await session.data(for: request, delegate: policy) }
        activeNetworkTask = network
        defer { activeNetworkTask = nil }
        let (data, response) = try await withTaskCancellationHandler {
            try await network.value
        } onCancel: { network.cancel() }
        try Task.checkCancellation()
        guard revision == keyRevision else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw OnlineImageError.invalidResponse }
        switch http.statusCode {
        case 200: return data
        case 401: throw OnlineImageError.message("Wallhaven API Key 无效或此内容需要 API Key。")
        case 403: throw OnlineImageError.forbidden
        case 404: throw OnlineImageError.message("此 Wallhaven 壁纸已不存在或不可访问。")
        case 429:
            if let delay = Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After")) {
                nextStart = clock.now.advanced(by: .seconds(delay))
            }
            throw OnlineImageError.rateLimited
        default: throw OnlineImageError.message("Wallhaven 请求失败（HTTP \(http.statusCode)）。")
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !busy { busy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelWaiting(id) } }
        if Task.isCancelled { release(); throw CancellationError() }
    }

    private func cancelWaiting(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if waiting.isEmpty { busy = false }
        else { waiting.removeFirst().1.resume() }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw OnlineImageError.invalidResponse }
    }

    private static func normalizedKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func retryDelay(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite { return max(1, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(1, $0.timeIntervalSinceNow) }
    }
}

/// API credentials never follow a redirect to a CDN, source site or sign-in page.
nonisolated private final class WallhavenAPIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
