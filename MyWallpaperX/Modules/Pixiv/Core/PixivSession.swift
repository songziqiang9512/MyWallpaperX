import Combine
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
    /// A real, verified current-identity response may be installed after login
    /// investigation. No public author endpoint or cookie value qualifies.
    typealias IdentityVerifier = @Sendable (WallpaperNetworkSession) async throws -> Identity?

    @Published private(set) var state = State()
    let websiteDataStore: WKWebsiteDataStore
    private(set) var urlSession: WallpaperNetworkSession
    var scopeID: String { state.scopeID }
    var sessionEpoch: UInt64 { state.sessionEpoch }
    private var verifier: IdentityVerifier?
    private var observedCookies: [CookieKey: HTTPCookie] = [:]
    private var bridgeTask: Task<Void, Never>?
    private var bridgeID: UUID?
    private var bridgeAgain = false
    private var isLoggingOut = false
    private let networkConfiguration: URLSessionConfiguration?

    init(websiteDataStore: WKWebsiteDataStore? = nil, identityVerifier: IdentityVerifier? = nil,
         networkConfiguration: URLSessionConfiguration? = nil) {
        self.websiteDataStore = websiteDataStore ?? WKWebsiteDataStore(forIdentifier: Self.storeIdentifier())
        verifier = identityVerifier
        let injected = networkConfiguration?.copy() as? URLSessionConfiguration
        self.networkConfiguration = injected
        urlSession = WallpaperNetworkSession(configuration: Self.configuration(from: injected))
        super.init()
        let unusedInitialSession = urlSession
        installTransport()
        unusedInitialSession.retire()
        self.websiteDataStore.httpCookieStore.add(self)
    }

    /// Called on entry/login completion, never from normal playback or a timer.
    func refresh(afterExplicitAccountAction: Bool = false) async {
        guard !isLoggingOut else { return }
        // Unknown identities cannot distinguish A->B from token rotation. A
        // completed user login/settings action therefore always starts a scope.
        if afterExplicitAccountAction { invalidateVisibility() }
        await synchronizeCookies()
        guard !isLoggingOut else { return }
        guard let verifier else {
            // Current anonymous P0 does not establish an authenticated response
            // schema. Cookie presence can only establish a candidate session.
            if observedCookies.isEmpty { transition(identity: nil) }
            else if state.phase != .unknown { revokeScope(phase: .unknown) }
            return
        }
        let epoch = state.sessionEpoch
        let activeSession = urlSession
        state.phase = .checking
        do {
            let identity = try await verifier(activeSession)
            guard epoch == state.sessionEpoch, activeSession === urlSession, !isLoggingOut else { return }
            if let identity, PixivRequestURL.validID(identity.userID) {
                transition(identity: identity)
            } else { transition(identity: nil) }
        } catch {
            guard epoch == state.sessionEpoch, activeSession === urlSession, !isLoggingOut else { return }
            state.phase = .unknown
        }
    }

    func setIdentityVerifier(_ verifier: IdentityVerifier?) { self.verifier = verifier }

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
        } else if !merged.isEmpty, state.phase == .anonymous {
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
        let pendingBridge = bridgeTask
        pendingBridge?.cancel(); bridgeTask = nil; bridgeID = nil; bridgeAgain = false
        observedCookies = [:]
        let next = State(phase: .anonymous, scopeID: "pixiv-anonymous", sessionEpoch: state.sessionEpoch &+ 1)
        let oldSession = urlSession
        installTransport(epoch: next.sessionEpoch)
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
        if identity?.userID != state.identity?.userID || (identity == nil && state.scopeID != "pixiv-anonymous") {
            revokeScope(phase: phase, identity: identity)
        } else { state.identity = identity; state.phase = phase }
    }

    private func revokeScope(phase: Phase, identity: Identity? = nil) {
        let next = State(phase: phase, scopeID: phase == .anonymous ? "pixiv-anonymous" : UUID().uuidString,
            sessionEpoch: state.sessionEpoch &+ 1, identity: identity)
        let oldSession = urlSession
        installTransport(epoch: next.sessionEpoch)
        state = next
        oldSession.retire()
    }

    private func installTransport(epoch explicitEpoch: UInt64? = nil) {
        let epoch = explicitEpoch ?? state.sessionEpoch
        urlSession = WallpaperNetworkSession(configuration: Self.configuration(from: networkConfiguration), onCompletion: { [weak self] session in
            Task { @MainActor [weak self] in self?.networkCookiesDidChange(from: session, epoch: epoch) }
        })
        for cookie in observedCookies.values { urlSession.configuration.httpCookieStorage?.setCookie(cookie) }
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
}
