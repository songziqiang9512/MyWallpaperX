import Foundation
import WebKit

// Only the library identity leaf is outside this source's tested responsibility.
nonisolated enum WallpaperProvider: String, Codable, Sendable { case wallhaven, pixiv, videoLibrary }
nonisolated struct WallpaperReference: Hashable, Codable, Sendable {
    let provider: WallpaperProvider
    let sourceID: String
}
nonisolated struct WallpaperSourceScanStatus: Equatable, Sendable {
    static let initial = Self()
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, String, String))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var holdNext = false
    nonisolated(unsafe) static var held: FixtureProtocol?
    nonisolated(unsafe) static var onHold: ((FixtureProtocol) -> Void)?
    nonisolated(unsafe) static var stoppedURLs: [URL] = []
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if Self.holdNext {
            Self.holdNext = false; Self.held = self
            let onHold = Self.onHold; Self.onHold = nil; onHold?(self)
            return
        }
        complete()
    }
    func complete() {
        let output = Self.responder?(request) ?? (500, "application/json", "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: output.0,
            httpVersion: "HTTP/1.1", headerFields: Self.responseHeaders.merging(["Content-Type": output.1], uniquingKeysWith: { _, new in new }))!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(output.2.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { if let url = request.url { Self.stoppedURLs.append(url) } }
}

@main
private struct Checks {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func item(_ id: String = "100", type: String = "0", extra: String = "") -> String {
        "{\"id\":\"\(id)\",\"title\":\"Fixture\",\"illustType\":\(type),\"url\":\"https://i.pximg.net/thumb.jpg\",\"userId\":\"200\",\"userName\":\"Author\"\(extra)}"
    }
    static func session() -> WallpaperNetworkSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return WallpaperNetworkSession(URLSession(configuration: configuration))
    }

    static func checkQueuedCancellation(client: PixivClient) async throws {
        FixtureProtocol.responder = { request in
            (200, "application/json", "{\"error\":false,\"body\":\(item(request.url!.lastPathComponent))}")
        }
        let before = FixtureProtocol.requests.count
        var active: Task<OnlineImageArtwork, Error>?
        let held: FixtureProtocol = await withCheckedContinuation { continuation in
            FixtureProtocol.holdNext = true
            FixtureProtocol.onHold = { continuation.resume(returning: $0) }
            active = Task { try await client.detail(id: "801") }
        }
        expect(held.request.url?.lastPathComponent == "801", "slow A really holds the transport")

        var queued: Task<OnlineImageArtwork, Error>?
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
            queued = Task {
                entered.resume()
                return try await client.detail(id: "802")
            }
        }
        // Let the actor accept B's call while A remains held. This synchronous
        // actor operation does not release A or create another HTTP request.
        await client.invalidateAuthorSnapshot()
        let cancellationDeadline = Task {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            fatalError("queued B cancellation waited for slow A")
        }
        defer { cancellationDeadline.cancel() }
        queued!.cancel()
        do { _ = try await queued!.value; fatalError("queued canceled B succeeded") }
        catch is CancellationError {}
        catch let error as URLError { expect(error.code == .cancelled, "queued B returns cancellation") }
        cancellationDeadline.cancel()
        expect(FixtureProtocol.requests.count == before + 1, "canceled queued B never reaches HTTP")
        expect(FixtureProtocol.held === held && !FixtureProtocol.stoppedURLs.contains(held.request.url!),
            "B returns before A finishes without canceling A")

        var following: Task<OnlineImageArtwork, Error>?
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
            following = Task {
                entered.resume()
                return try await client.detail(id: "803")
            }
        }
        await client.invalidateAuthorSnapshot()
        expect(FixtureProtocol.requests.count == before + 1, "C also waits for the single active transport")
        held.complete()
        FixtureProtocol.held = nil
        let first = try await active!.value
        let last = try await following!.value
        expect(first.artworkID == "801", "slow A succeeds after B cancellation")
        expect(last.artworkID == "803", "C succeeds after the canceled waiter")
        expect(FixtureProtocol.requests.dropFirst(before).map { $0.url!.lastPathComponent } == ["801", "803"],
            "queue sends only A then C")
    }

    static func checkNetworkCookieBridge() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let isolated = PixivSession(websiteDataStore: .nonPersistent(), networkConfiguration: configuration)
        FixtureProtocol.responder = { _ in (200, "application/json", "{}") }
        FixtureProtocol.responseHeaders = ["Set-Cookie": "fixture_network=network-only; Domain=.pixiv.net; Path=/; Secure; HttpOnly"]
        defer { FixtureProtocol.responseHeaders = [:] }
        let handle = isolated.urlSession
        _ = try await handle.data(for: URLRequest(url: URL(string: "https://www.pixiv.net/fixture-network-cookie")!))
        if handle.configuration.httpCookieStorage?.cookies?.contains(where: { $0.name == "fixture_network" }) == true {
            var reachedWebKit = false
            for _ in 0..<100 {
                let values = await isolated.websiteDataStore.httpCookieStore.allCookies()
                if values.contains(where: { $0.name == "fixture_network" }) { reachedWebKit = true; break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            expect(reachedWebKit, "real Foundation Set-Cookie completion bridges to the isolated WebKit store")
            print("Pixiv HTTP Set-Cookie to WebKit bridge passed")
        } else {
            print("Fixture limitation: URLProtocol did not install Set-Cookie in Foundation; automatic HTTP-to-WebKit bridge remains unverified")
        }
        let previousStorage = isolated.urlSession.configuration.httpCookieStorage
        await isolated.logout()
        expect(previousStorage !== isolated.urlSession.configuration.httpCookieStorage,
            "injected protocol configuration still creates a private cookie jar per epoch")
    }

    static func waitForControlledCookie(_ value: String?, in isolated: PixivSession) async throws {
        for _ in 0..<100 {
            let cookies = await isolated.websiteDataStore.httpCookieStore.allCookies()
            if cookies.first(where: { $0.name == "fixture_controlled" })?.value == value { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("controlled cookie bridge did not reach WebKit")
    }

    static func checkControlledCookieBridge() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let isolated = PixivSession(websiteDataStore: .nonPersistent(), networkConfiguration: configuration)
        let store = isolated.websiteDataStore.httpCookieStore
        let changes = CookieChangeProbe()
        store.add(changes)
        defer { store.remove(changes) }
        let cookie: (String) -> HTTPCookie = { value in
            HTTPCookie(properties: [.domain: ".pixiv.net", .path: "/", .name: "fixture_controlled", .value: value])!
        }
        FixtureProtocol.responseHeaders = [:]
        FixtureProtocol.responder = { _ in (200, "application/json", "{}") }
        // URLProtocol does not install Set-Cookie on this platform. Seed the
        // isolated jar explicitly, then let a real handle completion alone
        // trigger the bridge. This proves jar -> hook -> WK, not HTTP parsing.
        isolated.urlSession.configuration.httpCookieStorage?.setCookie(cookie("network-1"))
        _ = try await isolated.urlSession.data(for: URLRequest(url: URL(string: "https://www.pixiv.net/fixture-controlled-cookie")!))
        try await waitForControlledCookie("network-1", in: isolated)
        await isolated.synchronizeCookies()
        expect(isolated.state.phase == .unknown && isolated.sessionEpoch == 1,
            "first network cookie establishes one candidate scope without authentication")
        let scope = isolated.scopeID
        let epoch = isolated.sessionEpoch

        // The browser still holds network-1 when the jar rotates. Two callers
        // share one bridge; neither may replay that old browser value into it.
        isolated.urlSession.configuration.httpCookieStorage?.setCookie(cookie("network-2"))
        let first = Task { await isolated.synchronizeCookies() }
        let second = Task { await isolated.synchronizeCookies() }
        await first.value
        await second.value
        try await waitForControlledCookie("network-2", in: isolated)
        expect(isolated.urlSession.configuration.httpCookieStorage?.cookies?.first { $0.name == "fixture_controlled" }?.value == "network-2",
            "old WebKit snapshot does not overwrite a newer same-epoch jar cookie")

        await store.setCookie(cookie("browser-3"))
        await isolated.synchronizeCookies()
        expect(isolated.urlSession.configuration.httpCookieStorage?.cookies?.first { $0.name == "fixture_controlled" }?.value == "browser-3",
            "a browser-only delta still updates Foundation")
        await store.setCookie(cookie("browser-4"))
        isolated.urlSession.configuration.httpCookieStorage?.setCookie(cookie("network-5"))
        await isolated.synchronizeCookies()
        try await waitForControlledCookie("network-5", in: isolated)
        expect(isolated.urlSession.configuration.httpCookieStorage?.cookies?.first { $0.name == "fixture_controlled" }?.value == "network-5",
            "a concurrently newer jar value wins over the browser snapshot")
        expect(isolated.scopeID == scope && isolated.sessionEpoch == epoch,
            "ordinary rotations and the bridge's own observer echoes preserve the candidate scope")

        // Give observer delivery a bounded settling interval, then demonstrate
        // that repeated unchanged requests do not issue more WebKit writes.
        await isolated.synchronizeCookies()
        try await Task.sleep(nanoseconds: 30_000_000)
        let settledChanges = changes.count
        for _ in 0..<3 { await isolated.synchronizeCookies() }
        try await Task.sleep(nanoseconds: 30_000_000)
        expect(changes.count == settledChanges, "the bridge's observer echoes settle without unchanged writes")

        let storage = isolated.urlSession.configuration.httpCookieStorage
        for value in storage?.cookies ?? [] where value.name == "fixture_controlled" { storage?.deleteCookie(value) }
        _ = try await isolated.urlSession.data(for: URLRequest(url: URL(string: "https://www.pixiv.net/fixture-controlled-deletion")!))
        try await waitForControlledCookie(nil, in: isolated)
        await isolated.synchronizeCookies()
        expect(isolated.state.phase == .anonymous && isolated.sessionEpoch == epoch + 1,
            "network jar deletion reaches WebKit and revokes the candidate scope once")
        await isolated.logout()
        print("Controlled Pixiv jar -> actual completion hook -> WebKit checks passed; HTTP Set-Cookie remains a separate fixture limitation")
    }

    static func main() async throws {
        let transport = session()
        let client = PixivClient(session: transport, minimumRequestInterval: 0)
        var query = PixivQuery()
        FixtureProtocol.responder = { _ in (200, "application/json", "{\"contents\":[{\"illust_id\":100,\"illust_type\":\"0\",\"illust_page_count\":\"2\",\"title\":\"Fixture\",\"is_masked\":false}],\"next\":2,\"date\":\"20261025\",\"rank_total\":500}") }
        let ranking = try await client.page(query: query)
        expect(ranking.items.count == 1 && ranking.items[0].pageCount == 2, "ranking int/string schema")
        expect(ranking.next?.page == 2 && ranking.next?.date == "20261025", "ranking continuation freezes date")
        expect(ranking.items[0].originalURL == nil, "listing never invents original URL")
        FixtureProtocol.responder = { _ in (200, "application/json", "{\"contents\":[],\"next\":false,\"date\":\"20261025\",\"rank_total\":500}") }
        let end = try await client.page(query: query, request: ranking.next!)
        expect(end.next == nil, "false is terminal, including empty page")
        expect(URLComponents(url: FixtureProtocol.requests.last!.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "date", value: "20261025")) == true, "date carried to request")

        query.search = "风景 / #100% OR 空"
        FixtureProtocol.responder = { _ in (200, "application/json", "{\"error\":false,\"body\":{\"illustManga\":{\"data\":[\(item(type: "1")),\(item("101", type: "7")),{\"title\":\"bad\"}],\"total\":999,\"lastPage\":2}}}") }
        let search = try await client.page(query: query)
        expect(search.items.count == 1 && search.items[0].kind == .unknown, "filter known other type; unknown is not image")
        expect(search.items[0].rating == .unknown && search.items[0].isMasked == nil, "missing rating and mask stay unknown")
        expect(search.next?.page == 2 && search.notice != nil, "source continuation survives local filtering and malformed row")
        let searchURL = FixtureProtocol.requests.last!.url!
        expect(searchURL.path.hasSuffix("风景 / #100% OR 空"), "word is one encoded path segment")
        expect(searchURL.absoluteString.contains("%2F") && searchURL.absoluteString.contains("%23"), "path metacharacters encoded")
        let decodedQuery = try JSONDecoder().decode(PixivQuery.self, from: JSONEncoder().encode(query))
        expect(decodedQuery == query, "typed query Codable round trip")

        let detailJSON = "{\"error\":false,\"body\":\(item(extra: ",\"pageCount\":2,\"xRestrict\":0,\"sl\":2,\"locationMask\":false,\"urls\":{\"regular\":\"https://i.pximg.net/regular.png\",\"original\":\"https://i.pximg.net/original.png\"}"))}"
        FixtureProtocol.responder = { request in
            if request.url!.path.hasSuffix("/pages") {
                return (200, "application/json", "{\"error\":false,\"body\":[{\"urls\":{\"original\":\"https://i.pximg.net/first.png\",\"regular\":\"https://i.pximg.net/first-small.png\"},\"width\":640,\"height\":480},{\"urls\":{\"original\":\"https://i.pximg.net/second.jpg\",\"small\":null},\"width\":\"800\",\"height\":null}]}")
            }
            return (200, "application/json", detailJSON)
        }
        let detail = try await client.detail(id: "100")
        let assets = try await client.assets(for: detail)
        expect(assets.map { $0.id.reference.sourceID } == ["100:p0", "100:p1"], "actual page identity and zero base")
        expect(assets[1].originalURL.lastPathComponent == "second.jpg" && assets[1].width == 800, "page URLs and dimensions are authoritative")
        expect(detail.rating == .unknown && detail.isMasked == nil, "xRestrict zero does not invent sensitive classification")
        var unsupported = detail; unsupported.kind = .animation
        do { _ = try await client.assets(for: unsupported); fatalError("ugoira treated as image") }
        catch OnlineImageError.unsupported {}
        var masked = detail; masked.isMasked = true
        do { _ = try await client.assets(for: masked); fatalError("masked original accepted") }
        catch OnlineImageError.forbidden {}

        FixtureProtocol.responder = { _ in (200, "application/json", detailJSON) }
        FixtureProtocol.holdNext = true
        let stale = Task { try await client.detail(id: "100") }
        for _ in 0..<100 where FixtureProtocol.held == nil { try await Task.sleep(nanoseconds: 1_000_000) }
        expect(FixtureProtocol.held != nil, "old request really started")
        let replacement = session()
        await client.replaceSession(replacement)
        do { _ = try await stale.value; fatalError("old session result survived replacement") }
        catch is CancellationError {}
        catch let error as URLError { expect(error.code == .cancelled, "transport cancellation") }
        FixtureProtocol.held = nil
        _ = try await client.detail(id: "100")
        try await checkQueuedCancellation(client: client)

        query = PixivQuery(authorID: "200")
        FixtureProtocol.responder = { request in
            if request.url!.path.hasSuffix("/all") {
                let ids = (100...125).map { "\"\($0)\":null" }.joined(separator: ",")
                return (200, "application/json", "{\"error\":false,\"body\":{\"illusts\":{\(ids)},\"manga\":null}}")
            }
            let ids = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.filter { $0.name == "ids[]" }.compactMap(\.value)
            let works = ids.reversed().map { "\"\($0)\":\($0 == "102" ? "null" : item($0))" }.joined(separator: ",")
            return (200, "application/json", "{\"error\":false,\"body\":{\"works\":{\(works)}}}")
        }
        let beforeAuthor = FixtureProtocol.requests.count
        let author1 = try await client.page(query: query)
        let author2 = try await client.page(query: query, request: author1.next!)
        expect(author1.items.count == 23 && author1.items.first?.artworkID == "125" && author1.items.last?.artworkID == "103", "author restores ID slice order with a missing row")
        expect(author2.items.map(\.artworkID) == ["101", "100"] && author2.next == nil, "author cursor consumes snapshot")
        expect(FixtureProtocol.requests.count - beforeAuthor == 3, "author snapshot fetched once")

        FixtureProtocol.responder = { _ in (200, "text/html", "<html>challenge</html>") }
        do { _ = try await client.detail(id: "100"); fatalError("HTML treated as JSON") }
        catch OnlineImageError.invalidResponse {}
        FixtureProtocol.responder = { _ in (403, "application/json", "{\"error\":true,\"body\":[]}") }
        do { _ = try await client.detail(id: "100"); fatalError("403 accepted") }
        catch OnlineImageError.forbidden {}
        FixtureProtocol.responder = { _ in (200, "application/json", "{\"error\":true,\"body\":[]}") }
        do { _ = try await client.detail(id: "100"); fatalError("error array decoded as success") }
        catch OnlineImageError.forbidden {}
        FixtureProtocol.responseHeaders = ["Retry-After": "60"]
        FixtureProtocol.responder = { _ in (429, "application/json", "{}") }
        do { _ = try await client.detail(id: "100"); fatalError("429 accepted") }
        catch OnlineImageError.rateLimited {}
        let afterRateLimit = FixtureProtocol.requests.count
        do { _ = try await client.detail(id: "100"); fatalError("Retry-After ignored") }
        catch OnlineImageError.rateLimited {}
        expect(FixtureProtocol.requests.count == afterRateLimit, "cooldown does not send an immediate retry")
        FixtureProtocol.responseHeaders = [:]

        let isolated = PixivSession(websiteDataStore: .nonPersistent())
        await isolated.refresh()
        expect(isolated.state.phase == .anonymous, "empty isolated store is anonymous")
        expect(isolated.urlSession.configuration.httpCookieStorage !== HTTPCookieStorage.shared, "Foundation cookie store is private")
        let cookie = HTTPCookie(properties: [.domain: ".pixiv.net", .path: "/", .name: "PHPSESSID", .value: "fixture_only"])!
        let evil = HTTPCookie(properties: [.domain: "evilpixiv.net", .path: "/", .name: "unrelated", .value: "fixture_only"])!
        await isolated.websiteDataStore.httpCookieStore.setCookie(cookie)
        await isolated.websiteDataStore.httpCookieStore.setCookie(evil)
        await isolated.refresh()
        expect(isolated.state.phase == .unknown, "cookie existence does not authenticate")
        expect(isolated.urlSession.configuration.httpCookieStorage?.cookies?.contains { $0.name == "PHPSESSID" } == true, "isolated cookie bridges")
        expect(isolated.urlSession.configuration.httpCookieStorage?.cookies?.contains { $0.name == "unrelated" } != true, "exact domain boundary")
        let candidateScope = isolated.scopeID
        let candidateEpoch = isolated.sessionEpoch
        let rotated = HTTPCookie(properties: [.domain: ".pixiv.net", .path: "/", .name: "PHPSESSID", .value: "fixture_rotated"])!
        await isolated.websiteDataStore.httpCookieStore.setCookie(rotated)
        await isolated.refresh()
        expect(isolated.scopeID == candidateScope && isolated.sessionEpoch == candidateEpoch, "ordinary unknown cookie rotation does not reset the grid")
        await isolated.refresh(afterExplicitAccountAction: true)
        expect(isolated.scopeID != candidateScope && isolated.sessionEpoch > candidateEpoch, "explicit login/settings action always revokes an unverified account scope")
        let beforeDelete = isolated.sessionEpoch
        await isolated.websiteDataStore.httpCookieStore.deleteCookie(rotated)
        await isolated.refresh()
        expect(isolated.state.phase == .anonymous && isolated.sessionEpoch > beforeDelete, "empty Pixiv cookie snapshot revokes the previous scope")
        await isolated.websiteDataStore.httpCookieStore.setCookie(cookie)
        await isolated.refresh()
        let oldEpoch = isolated.sessionEpoch
        let oldSession = isolated.urlSession
        await isolated.logout()
        expect(isolated.sessionEpoch > oldEpoch && isolated.state.phase == .anonymous && oldSession !== isolated.urlSession, "logout revokes scope and rotates transport")
        let clearedCookies = await isolated.websiteDataStore.httpCookieStore.allCookies()
        expect(clearedCookies.isEmpty, "isolated WebKit data cleared")
        let proof = IdentityProof()
        isolated.setIdentityVerifier { _ in await proof.verify() }
        let pendingIdentity = Task { await isolated.refresh() }
        for _ in 0..<100 {
            if await proof.isWaiting { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let verifierWaiting = await proof.isWaiting
        expect(verifierWaiting, "identity verifier really pending")
        await isolated.logout()
        await proof.finish()
        await pendingIdentity.value
        expect(isolated.state.phase == .anonymous && isolated.state.identity == nil, "late identity cannot undo logout")
        try await checkNetworkCookieBridge()
        try await checkControlledCookieBridge()
        transport.retire()
        replacement.retire()
        print("Pixiv behavior checks passed")
    }
}

@MainActor
private final class CookieChangeProbe: NSObject, WKHTTPCookieStoreObserver {
    private(set) var count = 0
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { count += 1 }
}

private actor IdentityProof {
    private var continuation: CheckedContinuation<PixivSession.Identity?, Never>?
    var isWaiting: Bool { continuation != nil }
    func verify() async -> PixivSession.Identity? {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning: .init(userID: "999", displayName: "Fixture identity"))
        continuation = nil
    }
}
