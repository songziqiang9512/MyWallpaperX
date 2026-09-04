import AppKit
import WebKit

@MainActor
final class SteamCommunitySessionController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = SteamCommunitySessionController()

    struct Account: Equatable {
        let id: String
        let displayName: String
    }

    enum SessionError: LocalizedError {
        case loginRequired
        case navigationFailed(String)

        var errorDescription: String? {
            switch self {
            case .loginRequired: return "需要登录 Steam 社区。"
            case .navigationFailed(let message): return message
            }
        }
    }

    private enum LoadPurpose {
        case page
        case login
    }

    private let dataStore: WKWebsiteDataStore
    private let webView: WKWebView
    private var windowController: NSWindowController?
    private var account: Account?
    private var purpose: LoadPurpose?
    private var pageContinuation: CheckedContinuation<String, Error>?
    private var loginContinuation: CheckedContinuation<Account, Error>?

    private override init() {
        if #available(macOS 14.0, *) {
            dataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "8ED08F8C-9DC7-45E8-8F71-1EDDA4DD29C5")!)
        } else {
            dataStore = .default()
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func ensureAuthenticated() async throws -> Account {
        if let account { return account }
        let probeURL = SteamWorkshopService.makePersonalWorkshopURL(
            browserContentMode: .video,
            source: .mySubscriptions,
            query: "",
            themeFilter: .all,
            ageRatingFilter: .all,
            resolutionFilter: .all,
            categoryFilter: .all,
            page: 1
        )
        do {
            _ = try await loadHTML(from: probeURL, purpose: .page)
        } catch SessionError.loginRequired {
            return try await presentLogin()
        }
        guard let account else { throw SessionError.loginRequired }
        return account
    }

    func renderedHTML(for url: URL) async throws -> String {
        _ = try await ensureAuthenticated()
        return try await loadHTML(from: url, purpose: .page)
    }

    func presentLogin() async throws -> Account {
        if let account { return account }
        configureLoginWindowIfNeeded()
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        let loginURL = URL(string: "https://steamcommunity.com/login/home/?goto=my%2Fmyworkshopfiles%2F")!
        return try await withCheckedThrowingContinuation { continuation in
            loginContinuation = continuation
            purpose = .login
            webView.load(URLRequest(url: loginURL))
        }
    }

    func clearSession() async {
        account = nil
        pageContinuation?.resume(throwing: CancellationError())
        pageContinuation = nil
        loginContinuation?.resume(throwing: CancellationError())
        loginContinuation = nil
        purpose = nil
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    private func loadHTML(from url: URL, purpose: LoadPurpose) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pageContinuation?.resume(throwing: CancellationError())
            pageContinuation = continuation
            self.purpose = purpose
            webView.load(URLRequest(url: url))
        }
    }

    private func configureLoginWindowIfNeeded() {
        guard windowController == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "登录 Steam 社区"
        window.minSize = NSSize(width: 460, height: 560)
        window.delegate = self
        webView.frame = window.contentView?.bounds ?? .zero
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)
        windowController = NSWindowController(window: window)
    }

    private func finishPage(with html: String) {
        let detectedAccount = Self.account(from: html)
        if purpose == .page {
            account = detectedAccount
        } else if let detectedAccount {
            account = detectedAccount
        }
        if purpose == .login, Self.isSteamErrorPage(html) {
            loginContinuation?.resume(
                throwing: SessionError.navigationFailed("Steam 社区暂时拒绝了登录请求，请稍后重试。")
            )
            loginContinuation = nil
            purpose = nil
            return
        }
        if purpose == .login, let account {
            loginContinuation?.resume(returning: account)
            loginContinuation = nil
            purpose = nil
            windowController?.close()
            return
        }
        guard let continuation = pageContinuation else { return }
        pageContinuation = nil
        purpose = nil
        guard account != nil else {
            continuation.resume(throwing: SessionError.loginRequired)
            return
        }
        continuation.resume(returning: html)
    }

    private static func account(from html: String) -> Account? {
        guard let id = SteamWorkshopService.firstCapture(pattern: #"g_steamID\s*=\s*\"(\d{17})\""#, in: html)
            ?? SteamWorkshopService.firstCapture(pattern: #"steamid\"\s*:\s*\"(\d{17})\""#, in: html) else {
            return nil
        }
        let name = SteamWorkshopService.firstCapture(pattern: #"account_pulldown[^>]*>([^<]+)<"#, in: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Account(id: id, displayName: name?.isEmpty == false ? name! : "Steam 用户")
    }

    private static func isSteamErrorPage(_ html: String) -> Bool {
        html.localizedCaseInsensitiveContains("Something Went Wrong")
            || html.localizedCaseInsensitiveContains("We were unable to service your request")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.fail(error)
                } else if let html = value as? String {
                    self.finishPage(with: html)
                } else {
                    self.fail(SessionError.navigationFailed("Steam 社区页面内容无法读取。"))
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard purpose == .login else { return }
        loginContinuation?.resume(throwing: SessionError.loginRequired)
        loginContinuation = nil
        purpose = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let allowed = ["steamcommunity.com", "steampowered.com", "steamstatic.com", "steamcdn-a.akamaihd.net"]
        let isSteamHost = allowed.contains { url.host?.hasSuffix($0) == true }
        guard isSteamHost else {
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func fail(_ error: Error) {
        if (error as? URLError)?.code == .cancelled { return }
        if purpose == .login {
            loginContinuation?.resume(
                throwing: SessionError.navigationFailed("Steam 社区页面加载失败：\(error.localizedDescription)")
            )
            loginContinuation = nil
            purpose = nil
            return
        }
        pageContinuation?.resume(throwing: error)
        pageContinuation = nil
        purpose = nil
    }
}
