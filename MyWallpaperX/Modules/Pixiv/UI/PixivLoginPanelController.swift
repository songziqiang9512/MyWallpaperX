import AppKit
import WebKit

/// Owns one official-page presentation, never the account's authentication state.
@MainActor
final class PixivLoginPanelController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let session: PixivSession
    private var panel: WallpaperLibraryModalPanel?
    private var webView: WKWebView?
    private var onClose: (() -> Void)?
    private var closingTask: Task<Void, Never>?
    private var originLabel: NSTextField?
    private var statusLabel: NSTextField?

    init(session: PixivSession) { self.session = session; super.init() }

    func present(in host: NSWindow, settings: Bool = false, onClose: @escaping () -> Void) {
        if let panel {
            WallpaperLibrarySheetPresentation.topWindow(in: panel).makeKeyAndOrderFront(nil)
            return
        }
        guard closingTask == nil, WallpaperLibrarySheetPresentation.permitsInput(in: host) else {
            onClose()
            return
        }
        let panel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0,
            width: max(520, min(860, host.frame.width - 40)),
            height: max(480, min(740, host.frame.height - 40))),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = settings ? "Pixiv 账号设置" : "登录 Pixiv"
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.websiteDataStore
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self
        browser.uiDelegate = self
        browser.allowsBackForwardNavigationGestures = true
        browser.translatesAutoresizingMaskIntoConstraints = false
        browser.wantsLayer = true
        browser.layer?.cornerRadius = 12
        browser.layer?.masksToBounds = true

        let surface = WallpaperLibrarySheetSurface()
        let icon = NSImageView(image: NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 27, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: panel.title)
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let origin = NSTextField(labelWithString: settings ? "www.pixiv.net" : "accounts.pixiv.net")
        origin.font = .systemFont(ofSize: 12)
        origin.textColor = .secondaryLabelColor
        origin.lineBreakMode = .byTruncatingMiddle
        origin.setAccessibilityLabel("Pixiv 官方页面地址")
        let titleStack = NSStackView(views: [heading, origin])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4
        let header = NSStackView(views: [icon, titleStack])
        header.alignment = .centerY
        header.spacing = 14
        header.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: "", target: self, action: #selector(closeFromButton))
        cancel.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭 Pixiv 页面")
        cancel.isBordered = false
        cancel.keyEquivalent = "\u{1b}"
        cancel.toolTip = "关闭 Pixiv 页面（Esc）"
        cancel.setAccessibilityLabel("关闭 Pixiv 页面")
        cancel.translatesAutoresizingMaskIntoConstraints = false
        let done = NSButton(title: "完成", target: self, action: #selector(closeFromButton))
        // Enter belongs to the site's login forms, not to the panel's Done button.
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.font = .systemFont(ofSize: 13, weight: .semibold)
        done.bezelColor = .controlAccentColor
        done.setAccessibilityHelp("关闭官方页面，返回壁纸库并检查 Pixiv 账号状态。")
        done.translatesAutoresizingMaskIntoConstraints = false
        let status = NSTextField(wrappingLabelWithString: "在 Pixiv 官方页面完成操作后，点击“完成”返回并检查账号状态。")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.setAccessibilityElement(true)
        status.setAccessibilityRole(.staticText)
        status.setAccessibilityLabel("Pixiv 页面状态")
        status.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(header)
        surface.addSubview(browser)
        surface.addSubview(status)
        surface.addSubview(done)
        surface.addSubview(cancel)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            header.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -8),
            header.topAnchor.constraint(equalTo: surface.topAnchor, constant: 20),
            cancel.widthAnchor.constraint(equalToConstant: 32),
            cancel.heightAnchor.constraint(equalToConstant: 32),
            cancel.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            cancel.topAnchor.constraint(equalTo: surface.topAnchor, constant: 10),
            browser.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            browser.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            browser.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            browser.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            status.leadingAnchor.constraint(equalTo: browser.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: browser.trailingAnchor),
            status.topAnchor.constraint(equalTo: browser.bottomAnchor, constant: 12),
            status.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            done.leadingAnchor.constraint(equalTo: browser.leadingAnchor),
            done.trailingAnchor.constraint(equalTo: browser.trailingAnchor),
            done.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            done.heightAnchor.constraint(equalToConstant: 38),
            done.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -20)
        ])
        panel.contentView = surface
        self.panel = panel
        webView = browser
        originLabel = origin
        statusLabel = status
        self.onClose = onClose
        guard WallpaperLibrarySheetPresentation.present(panel, in: host) else { close(); return }
        // The account-settings root is the known official entry; no unverified
        // settings subroute or settings mutation is embedded in native code.
        let url = URL(string: settings ? "https://www.pixiv.net/settings/" : "https://accounts.pixiv.net/login")!
        browser.load(URLRequest(url: url))
        panel.makeFirstResponder(browser)
    }

    func close() {
        guard let panel else { return }
        WallpaperLibrarySheetPresentation.dismiss(panel)
        finishClose()
    }

    @objc private func closeFromButton() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return false }
        close()
        return false
    }

    func windowWillClose(_ notification: Notification) { finishClose() }

    private func finishClose() {
        guard let panel else { return }
        let completion = onClose
        onClose = nil
        panel.delegate = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        panel.contentView = nil
        self.panel = nil
        originLabel = nil
        statusLabel = nil
        let session = session
        closingTask = Task { @MainActor [weak self] in
            await session.refresh(afterExplicitAccountAction: true)
            self?.closingTask = nil
            completion?()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard self.webView === webView, let url = navigationAction.request.url else {
            decisionHandler(.cancel); return
        }
        // Embedded challenge frames/resources stay under WebKit's normal origin
        // rules. External user links/main-frame redirects never share our cookies.
        if navigationAction.targetFrame?.isMainFrame == false, navigationAction.navigationType != .linkActivated {
            decisionHandler(.allow)
        } else if Self.isOfficial(url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted {
                openExternal(url)
            } else { statusLabel?.stringValue = "官方页面跳转到了外部网站。请通过页面中的链接在浏览器中打开。" }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard self.webView === webView, let url = navigationAction.request.url else { return nil }
        if Self.isOfficial(url) { webView.load(navigationAction.request) }
        else if navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted { openExternal(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        originLabel?.stringValue = webView.url?.host ?? "Pixiv"
        // Navigation completion is presentation feedback, never login evidence.
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showNavigationError(webView, error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(webView, error)
    }

    private func showNavigationError(_ browser: WKWebView, _ error: Error) {
        guard webView === browser, (error as NSError).code != NSURLErrorCancelled else { return }
        statusLabel?.stringValue = "官方页面暂时无法加载，请检查网络后重新打开。"
    }

    private func openExternal(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        NSWorkspace.shared.open(url)
        statusLabel?.stringValue = "外部链接已在系统浏览器中打开；浏览器会话不会导入 MyWallpaperX。"
    }

    private static func isOfficial(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "pixiv.net" || host == "www.pixiv.net" || host == "accounts.pixiv.net"
    }
}
