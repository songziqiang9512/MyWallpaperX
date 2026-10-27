import Foundation

nonisolated private struct Reply: Sendable {
    var status = 200
    var data = Data()
    var delay: TimeInterval = 0
    var headers: [String: String] = ["Content-Type": "application/json"]
}

/// URLProtocol invokes this recording leaf on Foundation's threads; all mutable state is locked.
nonisolated private final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Reply] = []
    private var recorded: [URLRequest] = []
    private var started: [TimeInterval] = []
    private var stoppedCount = 0

    func reset(_ values: [Reply]) { lock.lock(); defer { lock.unlock() }; replies = values; recorded = []; started = []; stoppedCount = 0 }
    func next(_ request: URLRequest) -> Reply {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        started.append(ProcessInfo.processInfo.systemUptime)
        return replies.isEmpty ? Reply(status: 500) : replies.removeFirst()
    }
    func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func startTimes() -> [TimeInterval] { lock.lock(); defer { lock.unlock() }; return started }
    func stop() { lock.lock(); defer { lock.unlock() }; stoppedCount += 1 }
    func stops() -> Int { lock.lock(); defer { lock.unlock() }; return stoppedCount }
}

nonisolated private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.state.next(request)
        let work = DispatchWorkItem { [self] in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                 headerFields: reply.headers) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: work)
    }
    override func stopLoading() { work?.cancel(); Self.state.stop() }
}

@main struct WallhavenClientHarness {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func item(_ id: String = "a1b2c3", original: Bool = true) -> [String: Any] {
        var value: [String: Any] = ["id": id, "url": "https://wallhaven.cc/w/\(id)", "purity": "sfw",
            "file_type": "image/png", "dimension_x": 3840, "dimension_y": 2160, "file_size": 123456,
            "thumbs": ["large": "https://th.wallhaven.cc/lg/\(id).jpg", "original": "https://th.wallhaven.cc/orig/\(id).jpg"],
            "uploader": ["username": "fixture author"], "tags": [["name": "mountains"]],
            "source": "https://artist.example/work"]
        if original { value["path"] = "https://w.wallhaven.cc/full/\(id).png" }
        return value
    }

    static func body(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    static func page(_ number: Int = 1, last: Int = 2, query: Any = NSNull(),
                     rows: [[String: Any]]? = nil, seed: String? = "new123") throws -> Data {
        try body(["data": rows ?? [item()], "meta": ["current_page": number, "last_page": last,
            "per_page": 24, "total": 25, "query": query, "seed": seed.map { $0 as Any } ?? NSNull()]])
    }

    static func parameters(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
    }

    static func main() async throws {
        var checks: [String: Bool] = [:]
        StubProtocol.state.reset([Reply(data: try page(query: ["id": 328, "tag": "mountains"])),
                                  Reply(data: try page(2, last: 2, query: "landscape", rows: [item("z9y8x7")]))])
        let pagingSession = session()
        let client = WallhavenClient(session: pagingSession)
        var query = WallhavenQuery()
        query.search = "+mountains -people & tree"
        query.sorting = .popular
        query.minimumResolution = "1920x1080"
        query.ratios = ["16x9"]
        query.color = "#424153"
        let first = try await client.page(query: query)
        let second = try await client.page(query: query, request: first.next!)
        let requests = StubProtocol.state.requests()
        let encoded = requests[0].url!.absoluteString
        let parameters = Self.parameters(requests[0])
        checks["search_operators_and_filters_survive_encoding"] = encoded.contains("%2Bmountains")
            && parameters["q"] == query.search && parameters["topRange"] == "1M"
            && parameters["atleast"] == "1920x1080" && parameters["ratios"] == "16x9" && parameters["colors"] == "424153"
        checks["no_undocumented_page_size_or_fields"] = parameters["per_page"] == nil && parameters["include_fields"] == nil
        checks["anonymous_headers_and_api_origin"] = requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-API-Key") == nil && $0.url?.host == "wallhaven.cc" && $0.url?.scheme == "https"
        }
        checks["unused_tag_object_and_text_query_metadata_do_not_reject_pages"] = first.next?.page == 2 && second.next == nil
            && first.total == 25 && second.items.first?.artworkID == "z9y8x7"
        let starts = StubProtocol.state.startTimes()
        checks["single_owner_spaces_api_starts"] = starts.count == 2 && starts[1] - starts[0] >= 0.95
        let artwork = first.items[0]
        let assets = try await client.assets(for: artwork)
        checks["original_asset_preserves_identity_metadata_without_network"] = assets.count == 1
            && assets[0].id.reference == WallpaperReference(provider: .wallhaven, sourceID: "a1b2c3")
            && assets[0].originalURL.absoluteString == "https://w.wallhaven.cc/full/a1b2c3.png"
            && assets[0].author == "fixture author" && assets[0].authorID == "fixture author"
            && assets[0].expectedBytes == 123456
            && artwork.rating == .safe && artwork.kind == .image && StubProtocol.state.requests().count == 2
        pagingSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try page(query: ["username": "FixturE_Artist-01"], seed: nil))])
        let authorSession = session(), authorClient = WallhavenClient(session: authorSession)
        var authorQuery = WallhavenQuery()
        authorQuery.authorUsername = "FixturE_Artist-01"
        authorQuery.search = "id:328"
        authorQuery.categories = "101"; authorQuery.purity = "110"
        authorQuery.sorting = .favorites; authorQuery.order = .asc
        authorQuery.resolutions = ["1920x1080", "2560x1440"]
        authorQuery.ratios = ["16x9", "21x9"]; authorQuery.color = "#660000"
        let authorPage = try await authorClient.page(query: authorQuery)
        let authorParameters = Self.parameters(StubProtocol.state.requests()[0])
        checks["author_query_preserves_username_and_combines_all_supported_filters"] = authorParameters["q"] == "@FixturE_Artist-01"
            && authorParameters["categories"] == "101" && authorParameters["purity"] == "110"
            && authorParameters["sorting"] == "favorites" && authorParameters["order"] == "asc"
            && authorParameters["resolutions"] == "1920x1080,2560x1440"
            && authorParameters["ratios"] == "16x9,21x9" && authorParameters["colors"] == "660000"
            && authorParameters["atleast"] == nil && authorParameters["topRange"] == nil
            && authorPage.next?.page == 2 && authorPage.next?.seed == nil
        authorSession.invalidateAndCancel()

        authorQuery.sorting = .popular; authorQuery.topRange = .sixMonths; authorQuery.order = .desc
        authorQuery.minimumResolution = "3840x2160"; authorQuery.resolutions = []
        let popularParameters = Dictionary(uniqueKeysWithValues: try authorQuery.queryItems(page: 3)
            .map { ($0.name, $0.value ?? "") })
        authorQuery.sorting = .views; authorQuery.authorUsername = nil
        let viewsParameters = Dictionary(uniqueKeysWithValues: try authorQuery.queryItems(page: 3, seed: "abc123")
            .map { ($0.name, $0.value ?? "") })
        checks["author_popular_range_and_minimum_resolution_keep_the_same_query"] = popularParameters["q"] == "@FixturE_Artist-01"
            && popularParameters["topRange"] == "6M" && popularParameters["order"] == "desc"
            && popularParameters["atleast"] == "3840x2160" && popularParameters["resolutions"] == nil
            && popularParameters["page"] == "3"
        checks["views_and_text_search_do_not_send_inactive_toprange_or_seed"] = viewsParameters["sorting"] == "views"
            && viewsParameters["q"] == "id:328" && viewsParameters["topRange"] == nil && viewsParameters["seed"] == nil

        let anonymousAuthor = try JSONDecoder().decode(WallhavenDetailResponse.self,
            from: body(["data": item()])).data.artwork()!
        var missingUploader = item(); missingUploader.removeValue(forKey: "uploader")
        var blankUploader = item(); blankUploader["uploader"] = ["username": "  "]
        let missingAuthor = try JSONDecoder().decode(WallhavenDetailResponse.self,
            from: body(["data": missingUploader])).data.artwork()!
        let blankAuthor = try JSONDecoder().decode(WallhavenDetailResponse.self,
            from: body(["data": blankUploader])).data.artwork()!
        checks["author_identity_comes_only_from_nonempty_uploader_username"] = anonymousAuthor.authorID == "fixture author"
            && missingAuthor.author == nil && missingAuthor.authorID == nil
            && blankAuthor.author == nil && blankAuthor.authorID == nil

        StubProtocol.state.reset([Reply(data: try page(rows: [item("")])), Reply(data: try page(2, rows: [item("last01")]))])
        let filteredSession = session(), filteredClient = WallhavenClient(session: filteredSession)
        let filteredPage = try await filteredClient.page(query: .init())
        let afterFiltered = try await filteredClient.page(query: .init(), request: filteredPage.next!)
        checks["projection_empty_page_keeps_server_continuation"] = filteredPage.items.isEmpty
            && filteredPage.next?.page == 2 && filteredPage.total == 25 && filteredPage.notice != nil
            && afterFiltered.items.first?.artworkID == "last01" && afterFiltered.next == nil
        filteredSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try page(rows: [item(""), item("valid1")]))])
        let partialSession = session(), partialClient = WallhavenClient(session: partialSession)
        let partialPage = try await partialClient.page(query: .init())
        checks["projection_skips_only_unreadable_items_and_reports_local_degradation"] = partialPage.items.map(\.artworkID) == ["valid1"]
            && partialPage.next?.page == 2 && partialPage.notice != nil && StubProtocol.state.requests().count == 1
        partialSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try page(last: 3, seed: "abc123")),
                                  Reply(data: try page(2, last: 3, rows: [item("rand02")], seed: "abc123")),
                                  Reply(data: try page(3, last: 3, rows: [item("rand03")], seed: "abc123"))])
        let randomSession = session()
        let randomClient = WallhavenClient(session: randomSession)
        var random = WallhavenQuery(); random.sorting = .random
        let randomFirst = try await randomClient.page(query: random)
        let randomSecond = try await randomClient.page(query: random, request: randomFirst.next!)
        let randomLast = try await randomClient.page(query: random, request: randomSecond.next!)
        let randomRequests = StubProtocol.state.requests().map(Self.parameters)
        checks["random_continuation_preserves_first_seed_until_server_last_page"] = randomFirst.next == OnlineImagePageRequest(page: 2, seed: "abc123")
            && randomSecond.next == OnlineImagePageRequest(page: 3, seed: "abc123") && randomLast.next == nil
            && randomSecond.items.first?.artworkID == "rand02" && randomLast.items.first?.artworkID == "rand03"
            && randomFirst.notice == nil && randomSecond.notice == nil && randomLast.notice == nil
            && randomRequests.count == 3 && randomRequests[0]["seed"] == nil
            && randomRequests[1]["seed"] == "abc123" && randomRequests[2]["seed"] == "abc123"
        randomSession.invalidateAndCancel()

        for (suffix, responseSeed) in [("changed", String?("def456")), ("missing", String?.none)] {
            StubProtocol.state.reset([Reply(data: try page(seed: "abc123")),
                                      Reply(data: try page(2, rows: [item("wrong1")], seed: responseSeed))])
            let changedSession = session(), changedClient = WallhavenClient(session: changedSession)
            let accepted = try await changedClient.page(query: random)
            let stopped = try await changedClient.page(query: random, request: accepted.next!)
            checks["random_\(suffix)_response_seed_stops_without_appending_or_retrying"] = accepted.items.first?.artworkID == "a1b2c3"
                && stopped.items.isEmpty && stopped.next == nil && stopped.notice != nil
                && StubProtocol.state.requests().count == 2
            changedSession.invalidateAndCancel()
        }

        StubProtocol.state.reset([Reply(data: try page(seed: nil))])
        let seedlessSession = session(), seedlessClient = WallhavenClient(session: seedlessSession)
        let seedlessFirst = try await seedlessClient.page(query: random)
        let seedlessNext = try await seedlessClient.page(query: random, request: .init(page: 2))
        checks["random_missing_initial_seed_shows_one_batch_and_missing_continuation_never_requests"] = seedlessFirst.items.count == 1
            && seedlessFirst.next == nil && seedlessFirst.notice != nil
            && seedlessNext.items.isEmpty && seedlessNext.next == nil && seedlessNext.notice != nil
            && StubProtocol.state.requests().count == 1
        seedlessSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try body(["data": item("d4e5f6")]))])
        let detailSession = session()
        let detailClient = WallhavenClient(session: detailSession)
        let remote = try JSONDecoder().decode(WallhavenDetailResponse.self,
            from: body(["data": item("d4e5f6", original: false)])).data.artwork()!
        let resolved = try await detailClient.assets(for: remote)
        checks["missing_original_resolves_detail_without_url_guessing"] = resolved[0].id.artworkID == "d4e5f6"
            && StubProtocol.state.requests().first?.url?.path == "/api/v1/w/d4e5f6"
        detailSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try body(["data": item("other1")]))])
        let mismatchSession = session(), mismatchClient = WallhavenClient(session: mismatchSession)
        do { _ = try await mismatchClient.detail(id: "a1b2c3"); checks["detail_rejects_wrong_identity"] = false }
        catch { checks["detail_rejects_wrong_identity"] = true }
        mismatchSession.invalidateAndCancel()

        for code in [401, 403, 404, 429, 503] {
            StubProtocol.state.reset([Reply(status: code)])
            let failureSession = session(), failureClient = WallhavenClient(session: failureSession)
            do { _ = try await failureClient.page(query: .init()); checks["http_\(code)_is_failure_without_retry"] = false }
            catch { checks["http_\(code)_is_failure_without_retry"] = StubProtocol.state.requests().count == 1 }
            failureSession.invalidateAndCancel()
        }
        StubProtocol.state.reset([Reply(data: Data("<html>challenge</html>".utf8))])
        let htmlSession = session(), htmlClient = WallhavenClient(session: htmlSession)
        do { _ = try await htmlClient.page(query: .init()); checks["html_is_failure_not_empty_results"] = false }
        catch { checks["html_is_failure_not_empty_results"] = true }
        htmlSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(status: 429, headers: ["Retry-After": "2"]), Reply(data: try page())])
        let cooldownSession = session(), cooldownClient = WallhavenClient(session: cooldownSession)
        do { _ = try await cooldownClient.page(query: .init()) } catch {}
        _ = try await cooldownClient.page(query: .init())
        let cooldownStarts = StubProtocol.state.startTimes()
        checks["retry_after_delays_next_explicit_request_without_retrying"] = cooldownStarts.count == 2
            && cooldownStarts[1] - cooldownStarts[0] >= 1.95
        cooldownSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try body(["data": [], "meta": ["current_page": 1,
            "last_page": 1, "total": 0, "query": NSNull(), "seed": NSNull()]]))])
        let emptySession = session(), emptyClient = WallhavenClient(session: emptySession)
        let empty = try await emptyClient.page(query: .init())
        checks["successful_empty_page_is_terminal"] = empty.items.isEmpty && empty.total == 0 && empty.next == nil
        emptySession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try page(2))])
        let wrongPageSession = session(), wrongPageClient = WallhavenClient(session: wrongPageSession)
        do { _ = try await wrongPageClient.page(query: .init()); checks["wrong_response_page_is_not_appended"] = false }
        catch { checks["wrong_response_page_is_not_appended"] = true }
        wrongPageSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try page(), delay: 3)])
        let cancellationSession = session(), cancellationClient = WallhavenClient(session: cancellationSession, apiKey: " fixture-key ")
        let active = Task { try await cancellationClient.page(query: .init()) }
        try await Task.sleep(for: .milliseconds(80))
        let queued = Task { try await cancellationClient.detail(id: "d4e5f6") }
        try await Task.sleep(for: .milliseconds(80))
        queued.cancel()
        var queueCancelled = false
        do { _ = try await queued.value } catch is CancellationError { queueCancelled = true } catch {}
        await cancellationClient.setAPIKey(nil)
        var keyRevoked = false
        do { _ = try await active.value } catch { keyRevoked = true }
        let credentialRequests = StubProtocol.state.requests()
        checks["queued_cancellation_never_starts_request"] = queueCancelled && credentialRequests.count == 1
        checks["key_change_cancels_active_result_and_uses_header_only"] = keyRevoked && StubProtocol.state.stops() > 0
            && credentialRequests[0].value(forHTTPHeaderField: "X-API-Key") == "fixture-key"
            && credentialRequests[0].url?.absoluteString.contains("fixture-key") == false
        cancellationSession.invalidateAndCancel()

        StubProtocol.state.reset([Reply(data: try page(), delay: 3)])
        let explicitSession = session(), explicitClient = WallhavenClient(session: explicitSession)
        let explicit = Task { try await explicitClient.page(query: .init()) }
        try await Task.sleep(for: .milliseconds(80)); explicit.cancel()
        do { _ = try await explicit.value; checks["active_cancellation_stops_transport"] = false }
        catch {
            // URLSession may finish the Swift continuation just before delivering stopLoading.
            for _ in 0..<50 where StubProtocol.state.stops() == 0 { try await Task.sleep(for: .milliseconds(10)) }
            checks["active_cancellation_stops_transport"] = StubProtocol.state.stops() > 0
        }
        explicitSession.invalidateAndCancel()

        var invalid = WallhavenQuery(); invalid.categories = "000"
        do { _ = try invalid.queryItems(page: 1); checks["invalid_filter_rejected_before_request"] = false }
        catch { checks["invalid_filter_rejected_before_request"] = true }

        if CommandLine.arguments.count == 2 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("anonymous-") && $0.pathExtension == "body" }
            var count = 0
            for file in files {
                let data = try Data(contentsOf: file)
                if file.lastPathComponent.hasPrefix("anonymous-detail-") {
                    let decoded = try JSONDecoder().decode(WallhavenDetailResponse.self, from: data)
                    guard decoded.data.artwork() != nil else { throw OnlineImageError.invalidResponse }
                } else {
                    let decoded = try JSONDecoder().decode(WallhavenSearchResponse.self, from: data)
                    guard decoded.data.allSatisfy({ $0.artwork() != nil }) else { throw OnlineImageError.invalidResponse }
                }
                count += 1
            }
            checks["captured_anonymous_api_responses_decode_with_production_dto"] = count >= 7
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
