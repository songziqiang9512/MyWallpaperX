import Combine
import CryptoKit
import Foundation
import WebKit

/// WebKit owns persistence; Foundation receives only this store's Pixiv cookies.
@MainActor
final class PixivSession: NSObject, ObservableObject, WKHTTPCookieStoreObserver {
    enum Phase: Equatable { case anonymous, checking, unknown, authenticated }
    nonisolated struct Identity: Equatable, Sendable {
        let userID: String
        var displayName: String? = nil
    }
    struct State: Equatable {
        var phase: Phase = .anonymous
        var scopeID: String = "pixiv-anonymous"
        var sessionEpoch: UInt64 = 0
        var identity: Identity? = nil
    }
    @Published private(set) var state = State()
    let websiteDataStore: WKWebsiteDataStore
    private(set) lazy var urlSession: WallpaperNetworkSession = makeTransport(epoch: state.sessionEpoch)
    var scopeID: String { state.scopeID }
    /// Session cookies survive App restarts; transient request epochs do not.
    /// This namespace is consumed only when an original image is cached/read.
    var originalCacheScope: String {
        let values = observedCookies.values.filter { $0.name == "PHPSESSID" }.map { $0.value }.sorted().joined(separator: ":")
        return values.isEmpty ? "pixiv-anonymous" : SHA256.hash(data: Data(values.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var sessionEpoch: UInt64 { state.sessionEpoch }
    private var observedCookies: [CookieKey: HTTPCookie] = [:]
    private var bridgeTask: Task<Void, Never>?
    private var bridgeID: UUID?
    private var bridgeAgain = false
    private var isLoggingOut = false
    private let networkConfiguration: URLSessionConfiguration?
    private var identityTask: Task<Void, Never>?
    private var identityAttemptedEpoch: UInt64?

    init(websiteDataStore: WKWebsiteDataStore? = nil, networkConfiguration: URLSessionConfiguration? = nil) {
        self.websiteDataStore = websiteDataStore ?? WKWebsiteDataStore(forIdentifier: Self.storeIdentifier())
        let injected = networkConfiguration?.copy() as? URLSessionConfiguration
        self.networkConfiguration = injected
        super.init()
        self.websiteDataStore.httpCookieStore.add(self)
    }

    /// Called on entry/login completion, never from normal playback or a timer.
    func refresh(afterExplicitAccountAction: Bool = false, officialMetadata: PixivOfficialMetadata = .unknown) async {
        guard !isLoggingOut else { return }
        // Unknown identities cannot distinguish A->B from token rotation. A
        // completed user login/settings action therefore always starts a scope.
        if afterExplicitAccountAction { invalidateVisibility() }
        let epoch = state.sessionEpoch
        await synchronizeCookies()
        guard !isLoggingOut else { return }
        if officialMetadata != .unknown {
            guard epoch == state.sessionEpoch else { return }
            identityTask?.cancel(); identityTask = nil
            applyMetadata(officialMetadata)
            identityAttemptedEpoch = state.sessionEpoch
            return
        }
        if observedCookies.isEmpty { transition(identity: nil) }
        else { restoreIdentityInBackground() }
    }

    /// A user-triggered read reuses the current session and never revokes an
    /// existing account merely to refresh its optional display metadata.
    func refreshAccountInformation() async {
        if identityTask == nil { identityAttemptedEpoch = nil }
        await refresh()
    }

    private func applyMetadata(_ metadata: PixivOfficialMetadata) {
        switch metadata {
        case .authenticated(let id, let name): transition(identity: .init(userID: id, displayName: name))
        case .anonymous: transition(identity: nil)
        case .unknown: state.phase = .unknown
        }
    }

    /// Account display is optional. Cookie preparation returns immediately;
    /// ordinary source requests do not wait for or require this one response.
    private func restoreIdentityInBackground() {
        let epoch = state.sessionEpoch
        guard identityTask == nil, identityAttemptedEpoch != epoch else { return }
        identityAttemptedEpoch = epoch
        let activeSession = urlSession
        state.phase = .checking
        identityTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if epoch == state.sessionEpoch { identityTask = nil }
            }
            var request = URLRequest(url: URL(string: "https://www.pixiv.net/")!)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer")
            request.setValue("MyWallpaperX", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await activeSession.data(for: request)
                guard !Task.isCancelled, epoch == state.sessionEpoch, activeSession === urlSession, !isLoggingOut else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.mimeType == "text/html", let url = http.url,
                      let html = String(data: data, encoding: .utf8) else {
                    applyMetadata(.unknown); return
                }
                applyMetadata(PixivOfficialMetadata.parse(raw: Self.metadataContent(in: html), url: url))
            } catch {
                guard !Task.isCancelled, epoch == state.sessionEpoch, activeSession === urlSession, !isLoggingOut else { return }
                applyMetadata(.unknown)
            }
        }
    }

    func synchronizeCookies() async {
        await requestCookieBridge()?.value
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        _ = requestCookieBridge()
    }

    private func requestCookieBridge() -> Task<Void, Never>? {
        guard !isLoggingOut else { return nil }
        if let bridgeTask { bridgeAgain = true; return bridgeTask }
        let identifier = UUID()
        bridgeID = identifier
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                bridgeAgain = false
                await bridgeCookieStores()
                guard bridgeID == identifier else { return }
            } while bridgeAgain && !Task.isCancelled
            bridgeTask = nil; bridgeID = nil
        }
        bridgeTask = task
        return task
    }

    private func bridgeCookieStores() async {
        let epoch = state.sessionEpoch
        let activeSession = urlSession
        let values = await websiteDataStore.httpCookieStore.allCookies()
        guard epoch == state.sessionEpoch, activeSession === urlSession, !isLoggingOut, !Task.isCancelled else { return }
        let browser = Dictionary(values.filter(Self.isPixivCookie).map { (CookieKey($0), $0) }, uniquingKeysWith: { _, new in new })
        let storage = activeSession.configuration.httpCookieStorage
        let network = Dictionary((storage?.cookies ?? []).filter(Self.isPixivCookie).map { (CookieKey($0), $0) }, uniquingKeysWith: { _, new in new })
        let baseline = observedCookies
        var merged = network
        // A stale WebKit snapshot must not undo a newer response cookie. Only
        // WebKit changes whose network value still equals our baseline win.
        for key in Set(baseline.keys).union(browser.keys)
            where !Self.sameCookie(browser[key], baseline[key]) && Self.sameCookie(network[key], baseline[key]) {
            merged[key] = browser[key]
            if let cookie = browser[key] { storage?.setCookie(cookie) }
            else if let cookie = network[key] { storage?.deleteCookie(cookie) }
        }
        observedCookies = merged
        if merged.isEmpty, !baseline.isEmpty {
            revokeScope(phase: .anonymous)
        } else if !merged.isEmpty, baseline.isEmpty, state.phase == .anonymous {
            revokeScope(phase: .unknown)
        }
        let targetEpoch = state.sessionEpoch
        let targetSession = urlSession
        let store = websiteDataStore.httpCookieStore
        for (key, cookie) in browser where merged[key] == nil {
            guard targetEpoch == state.sessionEpoch, targetSession === urlSession, !isLoggingOut, !Task.isCancelled else { return }
            await store.deleteCookie(cookie)
        }
        for (key, cookie) in merged where !Self.sameCookie(cookie, browser[key]) {
            guard targetEpoch == state.sessionEpoch, targetSession === urlSession, !isLoggingOut, !Task.isCancelled else { return }
            await store.setCookie(cookie)
        }
    }

    /// The UI must close its login/settings WebView before logout. Only this
    /// isolated store is cleared; already-published image files are unrelated.
    func logout() async {
        isLoggingOut = true
        identityTask?.cancel(); identityTask = nil
        let pendingBridge = bridgeTask
        pendingBridge?.cancel(); bridgeTask = nil; bridgeID = nil; bridgeAgain = false
        observedCookies = [:]
        let next = State(phase: .anonymous, scopeID: "pixiv-anonymous", sessionEpoch: state.sessionEpoch &+ 1)
        let oldSession = urlSession
        urlSession = makeTransport(epoch: next.sessionEpoch)
        state = next
        oldSession.retire()
        // A WebKit mutation already being awaited cannot be canceled. Drain it
        // before clearing the store so it cannot repopulate a logged-out store.
        await pendingBridge?.value
        let store = websiteDataStore.httpCookieStore
        for cookie in await store.allCookies() { await store.deleteCookie(cookie) }
        await websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        isLoggingOut = false
    }

    /// Account display settings changed in the official page. This revokes old
    /// browse/download consumers without guessing or changing the site's settings.
    func invalidateVisibility() {
        revokeScope(phase: .unknown)
    }

    private func transition(identity: Identity?) {
        let phase: Phase = identity == nil ? .anonymous : .authenticated
        let changesKnownAccount = state.identity != nil && identity?.userID != state.identity?.userID
        if changesKnownAccount || (identity == nil && state.scopeID != "pixiv-anonymous")
            || (identity != nil && state.scopeID == "pixiv-anonymous") {
            revokeScope(phase: phase, identity: identity)
        } else { state.identity = identity; state.phase = phase }
    }

    private func revokeScope(phase: Phase, identity: Identity? = nil) {
        identityTask?.cancel(); identityTask = nil
        let next = State(phase: phase, scopeID: phase == .anonymous ? "pixiv-anonymous" : UUID().uuidString,
            sessionEpoch: state.sessionEpoch &+ 1, identity: identity)
        let oldSession = urlSession
        urlSession = makeTransport(epoch: next.sessionEpoch)
        state = next
        oldSession.retire()
    }

    private func makeTransport(epoch: UInt64) -> WallpaperNetworkSession {
        let transport = WallpaperNetworkSession(configuration: Self.configuration(from: networkConfiguration), onCompletion: { [weak self] session in
            Task { @MainActor [weak self] in self?.networkCookiesDidChange(from: session, epoch: epoch) }
        })
        for cookie in observedCookies.values { transport.configuration.httpCookieStorage?.setCookie(cookie) }
        return transport
    }

    private func networkCookiesDidChange(from session: WallpaperNetworkSession, epoch: UInt64) {
        guard epoch == state.sessionEpoch, session === urlSession, !isLoggingOut else { return }
        _ = requestCookieBridge()
    }

    private struct CookieKey: Hashable {
        let domain: String, path: String, name: String
        init(_ cookie: HTTPCookie) { domain = cookie.domain; path = cookie.path; name = cookie.name }
    }

    private nonisolated static func isPixivCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (domain == "pixiv.net" || domain.hasSuffix(".pixiv.net"))
            && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }

    private nonisolated static func sameCookie(_ left: HTTPCookie?, _ right: HTTPCookie?) -> Bool {
        if left == nil, right == nil { return true }
        guard let left, let right else { return false }
        return left.value == right.value && left.expiresDate == right.expiresDate
            && left.isSecure == right.isSecure && left.isHTTPOnly == right.isHTTPOnly
    }

    private nonisolated static func configuration(from injected: URLSessionConfiguration? = nil) -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.urlCache = nil
        value.timeoutIntervalForRequest = 30
        value.httpAdditionalHeaders = ["Referer": "https://www.pixiv.net/"]
        if let injected, let configured = injected.copy() as? URLSessionConfiguration {
            // Protocol/timeout injection never shares an old epoch's cookie jar.
            configured.httpCookieStorage = value.httpCookieStorage
            return configured
        }
        return value
    }

    private static func storeIdentifier() -> UUID {
        let key = "PixivWebsiteDataStoreIdentifier"
        if let stored = UserDefaults.standard.string(forKey: key), let value = UUID(uuidString: stored) { return value }
        let value = UUID()
        UserDefaults.standard.set(value.uuidString, forKey: key)
        return value
    }

    private nonisolated static func metadataContent(in html: String) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: #"<meta\b[^>]*\bid\s*=\s*(["'])meta-global-data\1[^>]*>"#,
            options: .caseInsensitive), let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return nil }
        let tag = String(html[range]).dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let document = tag.hasSuffix("/") ? tag + ">" : tag + "/>"
        // The isolated tag is valid XML and decodes quoted/numeric entities
        // without interpreting the surrounding HTML or executing page scripts.
        let delegate = PixivMetadataTagParser()
        let parser = XMLParser(data: Data(document.utf8))
        parser.delegate = delegate
        return parser.parse() ? delegate.content : nil
    }
}

nonisolated private final class PixivMetadataTagParser: NSObject, XMLParserDelegate {
    var content: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName.lowercased() == "meta", attributeDict["id"] == "meta-global-data" { content = attributeDict["content"] }
    }
}
