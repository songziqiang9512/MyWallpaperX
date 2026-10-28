import Foundation

actor PixivClient {
    private var session: WallpaperNetworkSession
    private var generation: UInt64 = 0
    private var requestActive = false
    private var waitingRequests: [(UUID, CheckedContinuation<Void, Error>)] = []
    private var operations: [UUID: Task<Data, Error>] = [:]
    private var lastRequestStart: TimeInterval = -.infinity
    private var retryNotBefore: TimeInterval = 0
    private let minimumRequestInterval: TimeInterval
    private var authorSnapshot: (author: String, type: PixivWorkType, ids: [String])?

    init(session: WallpaperNetworkSession? = nil, minimumRequestInterval: TimeInterval = 1) {
        self.session = session ?? Self.anonymousSession()
        self.minimumRequestInterval = max(0, minimumRequestInterval)
    }

    /// A session scope change revokes results even if Foundation finishes an old task.
    func replaceSession(_ session: WallpaperNetworkSession) {
        generation &+= 1
        for operation in operations.values { operation.cancel() }
        self.session = session
        authorSnapshot = nil
    }

    func invalidateAuthorSnapshot() { authorSnapshot = nil }

    func page(query: PixivQuery, request: OnlineImagePageRequest = .init()) async throws -> OnlineImagePage {
        guard request.page > 0 else { throw OnlineImageError.invalidResponse }
        if let author = query.authorID, !author.isEmpty {
            return try await authorPage(author: author, query: query, request: request)
        }
        if !query.searchWord.isEmpty {
            let url = try PixivRequestURL.search(query.searchWord, type: query.workType, page: request.page,
                order: query.order, ai: query.ai, content: query.content)
            let response: PixivSearchBody = try await envelope(url)
            let block = response.block
            let next = block.lastPage.map { request.page < $0 } == true
                ? OnlineImagePageRequest(page: request.page + 1) : nil
            return OnlineImagePage(items: artworks(block.data.values, query: query), next: next,
                total: block.total, notice: rejectedNotice(block.data.rejectedCount))
        }
        var parameters: [URLQueryItem] = [
            .init(name: "mode", value: query.ranking.rawValue), .init(name: "content", value: query.workType.rawValue),
            .init(name: "format", value: "json"), .init(name: "p", value: String(request.page))
        ]
        if let date = request.date { parameters.append(.init(name: "date", value: date)) }
        let data = try await fetch(try PixivRequestURL.make(path: "/ranking.php", query: parameters))
        let response = try decode(PixivRankingResponse.self, from: data)
        let nextPage = response.next?.value
        let next = nextPage.flatMap { $0 > request.page ? OnlineImagePageRequest(page: $0, date: request.date ?? response.date) : nil }
        return OnlineImagePage(items: artworks(response.contents.values, query: query),
            next: next, total: response.total, notice: rejectedNotice(response.contents.rejectedCount))
    }

    func detail(id: String) async throws -> OnlineImageArtwork {
        let value: PixivArtworkDTO = try await envelope(PixivRequestURL.artwork(id))
        guard value.id == id else { throw OnlineImageError.invalidResponse }
        return value.artwork()
    }

    func assets(for artwork: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        guard artwork.source == .pixiv, artwork.kind == .image else { throw OnlineImageError.unsupported }
        guard artwork.isMasked != true else { throw OnlineImageError.forbidden }
        let resolved = artwork.originalURL == nil ? try await detail(id: artwork.artworkID) : artwork
        guard resolved.kind == .image else { throw OnlineImageError.unsupported }
        guard resolved.isMasked != true, resolved.originalURL != nil else { throw OnlineImageError.forbidden }
        // Even p0 comes from the real page response; a listing cover never grants
        // an original URL or manufactures the other pages by string replacement.
        let pages: [PixivPageDTO] = try await envelope(PixivRequestURL.artwork(artwork.artworkID, suffix: "/pages"))
        guard !pages.isEmpty else { throw OnlineImageError.invalidResponse }
        return try pages.enumerated().map { index, page in
            guard let original = PixivRequestURL.imageURL(page.urls["original"]) else { throw OnlineImageError.invalidResponse }
            return OnlineImageAsset(id: .init(source: .pixiv, artworkID: artwork.artworkID, pageIndex: index),
                title: pages.count == 1 ? resolved.title : "\(resolved.title) · 第\(index + 1)张",
                sourceURL: resolved.sourceURL, originalURL: original,
                previewURL: PixivRequestURL.imageURL(page.urls["regular"]), author: resolved.author, authorID: resolved.authorID,
                tags: resolved.tags, width: page.width.flatMap { $0 > 0 ? $0 : nil },
                height: page.height.flatMap { $0 > 0 ? $0 : nil }, rating: resolved.rating)
        }
    }

    private func authorPage(author: String, query: PixivQuery, request: OnlineImagePageRequest) async throws -> OnlineImagePage {
        guard PixivRequestURL.validID(author), (request.offset ?? 0) >= 0 else { throw OnlineImageError.invalidResponse }
        let capturedGeneration = generation
        let snapshotIDs: [String]
        if let snapshot = authorSnapshot, snapshot.author == author, snapshot.type == query.workType { snapshotIDs = snapshot.ids }
        else {
            let response: PixivAuthorProfile = try await envelope(PixivRequestURL.make(path: "/ajax/user/\(author)/profile/all"))
            try requireCurrent(capturedGeneration)
            let values = query.workType == .manga ? response.manga : response.illustrations
            // IDs are opaque: order numeric decimal strings without converting
            // them to a machine-width integer or changing their identity.
            snapshotIDs = Array(Set(values)).sorted {
                $0.count == $1.count ? $0 > $1 : $0.count > $1.count
            }
            authorSnapshot = (author, query.workType, snapshotIDs)
        }
        let total = snapshotIDs.count
        let offset = request.offset ?? 0
        guard offset < total else { return OnlineImagePage(items: [], next: nil, total: total) }
        let end = offset + min(24, total - offset)
        let currentIDs = query.order == .newest ? Array(snapshotIDs[offset..<end])
            : Array(snapshotIDs[(total - end)..<(total - offset)].reversed())
        var parameters: [URLQueryItem] = [
            .init(name: "work_category", value: query.workType == .manga ? "manga" : "illustManga"),
            .init(name: "is_first_page", value: offset == 0 ? "1" : "0")
        ]
        parameters += currentIDs.map { .init(name: "ids[]", value: $0) }
        let response: PixivAuthorWorks = try await envelope(PixivRequestURL.make(path: "/ajax/user/\(author)/profile/illusts", query: parameters))
        try requireCurrent(capturedGeneration)
        let items = artworks(currentIDs.compactMap { id in
            guard let value = response.works[id], value.id == id else { return nil }
            return value
        }, query: query, authorBatch: true)
        return OnlineImagePage(items: items,
            next: end < total ? .init(page: request.page + 1, offset: end) : nil, total: total)
    }

    private func artworks(_ values: [PixivArtworkDTO], query: PixivQuery, authorBatch: Bool = false) -> [OnlineImageArtwork] {
        // The source may return unsupported/unknown works; keep those visible as
        // unsupported cards rather than converting them into image assets.
        values.compactMap { value in
            if value.type?.value == 0, query.workType == .manga { return nil }
            if value.type?.value == 1, query.workType == .illustrations { return nil }
            let artwork = value.artwork()
            if query.ai == .hide, artwork.isAIGenerated != false { return nil }
            // Search/ranking supply the requested source scope. The author
            // batch has no mode parameter, so only explicit non-adult metadata
            // can satisfy this local narrowing; unknown is never called safe.
            if authorBatch, query.content == .safe, value.xRestrict?.value != 0 { return nil }
            return artwork
        }
    }

    private func envelope<T: Decodable>(_ url: URL) async throws -> T {
        let response = try decode(PixivEnvelope<T>.self, from: await fetch(url))
        guard !response.error, let body = response.body else { throw OnlineImageError.forbidden }
        return body
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw OnlineImageError.invalidResponse }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let expectedGeneration = generation
        let activeSession = session
        let operation = Task { () throws -> Data in
            try await self.acquireRequest()
            defer { self.releaseRequest() }
            try Task.checkCancellation()
            return try await self.perform(url, session: activeSession, expectedGeneration: expectedGeneration)
        }
        let operationID = UUID()
        operations[operationID] = operation
        defer { operations[operationID] = nil }
        return try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
    }

    private func acquireRequest() async throws {
        try Task.checkCancellation()
        if !requestActive { requestActive = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waitingRequests.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelWaitingRequest(id) } }
        // A canceled waiter may have just received the active slot. Hand it on
        // instead of leaving the next request blocked or starting canceled I/O.
        if Task.isCancelled { releaseRequest(); throw CancellationError() }
    }

    private func cancelWaitingRequest(_ id: UUID) {
        guard let index = waitingRequests.firstIndex(where: { $0.0 == id }) else { return }
        waitingRequests.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func releaseRequest() {
        if waitingRequests.isEmpty { requestActive = false }
        else { waitingRequests.removeFirst().1.resume() }
    }

    private func perform(_ url: URL, session: WallpaperNetworkSession, expectedGeneration: UInt64) async throws -> Data {
        try requireCurrent(expectedGeneration)
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= retryNotBefore else { throw OnlineImageError.rateLimited }
        let delay = lastRequestStart + minimumRequestInterval - now
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        try requireCurrent(expectedGeneration)
        lastRequestStart = ProcessInfo.processInfo.systemUptime
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer")
        request.setValue("MyWallpaperX", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        try requireCurrent(expectedGeneration)
        guard let http = response as? HTTPURLResponse else { throw OnlineImageError.invalidResponse }
        if http.url?.host == "accounts.pixiv.net" { throw OnlineImageError.loginRequired }
        guard http.url?.host == "www.pixiv.net" else { throw OnlineImageError.forbidden }
        switch http.statusCode {
        case 200...299: break
        case 401: throw OnlineImageError.loginRequired
        case 403: throw OnlineImageError.forbidden
        case 429:
            if let raw = http.value(forHTTPHeaderField: "Retry-After"), let seconds = Self.retryDelay(raw), seconds > 0 {
                retryNotBefore = ProcessInfo.processInfo.systemUptime + seconds
            }
            throw OnlineImageError.rateLimited
        default: throw OnlineImageError.message("Pixiv 请求失败（HTTP \(http.statusCode)）。")
        }
        guard http.mimeType == "application/json" else { throw OnlineImageError.invalidResponse }
        return data
    }

    private func requireCurrent(_ expected: UInt64) throws {
        guard expected == generation else { throw CancellationError() }
    }

    private func rejectedNotice(_ count: Int) -> String? {
        count > 0 ? "有\(count)项作品信息暂时无法识别。" : nil
    }

    private nonisolated static func retryDelay(_ value: String) -> TimeInterval? {
        if let seconds = Double(value), seconds.isFinite { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)?.timeIntervalSinceNow
    }

    private nonisolated static func anonymousSession() -> WallpaperNetworkSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["Referer": "https://www.pixiv.net/"]
        return WallpaperNetworkSession(configuration: configuration)
    }
}
