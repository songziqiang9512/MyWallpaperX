//
//  SteamLoginPanelController.swift
//  MyWallpaperX
//

import AppKit
import Combine

/// SK2.2：唯一登录面板（二维码 / 账号密码 / Guard），由模块持有而非浏览页。
///
/// 合同（§3.2）：
/// - 面板只由工具栏账号区域打开；重复点击聚焦唯一面板，不产生第二个认证流。
/// - 关闭面板即取消认证；面板关闭后迟到的成功/失败回调不持久化、不弹回。
/// - 切换登录方式先取消旧 attempt；二维码到期/刷新生成新挑战，不自动无限重启。
/// - 视觉沿用现有 AppKit 风格（系统字体/颜色/控件，中文文案）。
@MainActor
final class SteamLoginPanelController: NSWindowController, NSWindowDelegate {

    static let shared = SteamLoginPanelController()

    private var auth: SteamAuthRoute?
    private var cancellables = Set<AnyCancellable>()
    private var loginTask: Task<Void, Never>?
    /// steam-ux-1：本面板正在做「恢复上次登录」的静默尝试；用于把成功/失败
    /// 文案与普通扫码/密码登录区分。任何手动登录动作都会复位。
    private var isRestoringSavedSession = false

    private let panelView = SteamLoginPanelView()
    private var modeSegment: NSSegmentedControl { panelView.modeSegment }
    private var qrImageView: NSImageView { panelView.qrImageView }
    private var refreshQRButton: NSButton { panelView.refreshQRButton }
    private var zoomQRButton: NSButton { panelView.zoomQRButton }
    private var usernameField: NSTextField { panelView.usernameField }
    private var passwordField: NSSecureTextField { panelView.passwordField }
    private var rememberCheck: NSButton { panelView.rememberCheck }
    private var loginButton: NSButton { panelView.loginButton }
    private var statusLabel: NSTextField { panelView.statusLabel }
    private var cancelButton: NSButton { panelView.cancelButton }
    private var codeField: NSTextField { panelView.codeField }

    private var zoomWindow: NSWindow?
    private var acceptsInput: Bool {
        window?.isVisible == true && WallpaperLibrarySheetPresentation.permitsInput(in: window)
    }

    private override init(window: NSWindow?) {
        super.init(window: nil)
        modeSegment.target = self
        modeSegment.action = #selector(modeSwitched)
        refreshQRButton.target = self
        refreshQRButton.action = #selector(refreshQR)
        zoomQRButton.target = self
        zoomQRButton.action = #selector(showZoomWindow)
        loginButton.target = self
        loginButton.action = #selector(submitPassword)
        loginButton.keyEquivalent = "\r"
        usernameField.target = self
        usernameField.action = #selector(submitPassword)
        passwordField.target = self
        passwordField.action = #selector(submitPassword)
        panelView.guardSubmitButton.target = self
        panelView.guardSubmitButton.action = #selector(submitGuardCode)
        panelView.guardSubmitButton.keyEquivalent = "\r"
        codeField.target = self
        codeField.action = #selector(submitGuardCode)
        panelView.doneButton.target = self
        panelView.doneButton.action = #selector(cancelAndClose)
        panelView.doneButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelAndClose)
        // Esc = 取消并关闭（§9 可用性）。
        cancelButton.keyEquivalent = "\u{1b}"
        rememberCheck.target = self
        rememberCheck.action = #selector(rememberToggled)
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrImageView.addGestureRecognizer(NSClickGestureRecognizer(
            target: self,
            action: #selector(showZoomWindow)
        ))
        qrImageView.toolTip = String(localized: "Click to enlarge the QR code")
        qrImageView.setAccessibilityElement(true)
        qrImageView.setAccessibilityRole(.image)
        qrImageView.setAccessibilityLabel(String(localized: "Steam Sign-In QR Code"))
        qrImageView.setAccessibilityHelp(String(localized: "Scan the code with the Steam mobile app to confirm; you can also press Tab to move to “Enlarge QR Code” for a larger view."))
    }

    /// 二维码放大窗：只复用当前挑战的图，独立关闭，不影响面板认证（§3.2）。
    @objc private func showZoomWindow() {
        guard acceptsInput, let image = qrImageView.image else { return }
        if let existing = zoomWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = WallpaperLibraryModalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 344),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "QR Code")
        window.level = .normal
        window.isReleasedWhenClosed = false
        let imageView = SteamLoginQRCodeImageView(frame: NSRect(x: 20, y: 12, width: 280, height: 280))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let hint = NSTextField(wrappingLabelWithString: String(localized: "Scan with the Steam mobile app to confirm."))
        hint.frame = NSRect(x: 20, y: 286, width: 280, height: 44)
        hint.alignment = .center
        hint.maximumNumberOfLines = 2
        hint.textColor = .secondaryLabelColor
        let content = NSView()
        content.addSubview(imageView)
        content.addSubview(hint)
        window.contentView = content
        if WallpaperLibrarySheetPresentation.present(window, in: self.window) { zoomWindow = window }
    }

    @objc private func rememberToggled() {
        guard acceptsInput else { return }
        // 记住登录是偏好（非敏感），可存 UserDefaults；token 持久化在 TokenStore。
        UserDefaults.standard.set(
            rememberCheck.state == .on,
            forKey: SteamWorkshopTokenStore.rememberPreferenceKey
        )
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - 展示与关闭

    /// 唯一入口：未登录时面板已存在则聚焦，否则创建并打开。
    func show(auth: SteamAuthRoute) {
        if let window, window.isVisible {
            WallpaperLibrarySheetPresentation.topWindow(in: window).makeKeyAndOrderFront(nil)
            return
        }
        guard let parent = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "MainWindow" && $0.isVisible
        }), WallpaperLibrarySheetPresentation.permitsInput(in: parent) else { return }
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        self.auth = auth
        let savedSession = Self.restorableSavedSession(for: auth)
        observe(auth: auth, replacingInitialFailure: savedSession != nil)

        let window = WallpaperLibraryModalPanel(
            contentRect: NSRect(x: 0, y: 0, width: SteamLoginPanelView.width, height: SteamLoginPanelView.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.title = String(localized: "Sign In to Steam")
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.contentView = panelView
        resetForNewAttempt()
        guard WallpaperLibrarySheetPresentation.present(window, in: parent) else {
            self.window = nil; cancellables.removeAll(); self.auth = nil
            return
        }
        if auth.isOnline {
            // 已在线的「切换账号」：进密码页（避免空白二维码页），说明会替换当前
            // 会话；新登录在 helper 侧顶替旧会话，成功后 steamId/accountName 更新。
            showPage(.password)
            setStatus(String(localized: "Currently signed in as \(auth.accountName ?? String(localized: "Steam Account")); signing in again will switch accounts."))
        } else if let saved = savedSession {
            startSilentRestore(saved)
        } else {
            startQRLogin()
        }
        window.makeFirstResponder(auth.isOnline ? usernameField : refreshQRButton)
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭面板 = 取消认证；迟到的成功回调不会再打开窗口（observe 中判断可见性）。
        // 不保存上次输入的秘密（§3.2）。
        panelView.clearSecrets()
        zoomWindow?.close()
        guard let auth else { return }
        loginTask?.cancel()
        auth.cancelPendingAuthentication()
    }

    @objc private func cancelAndClose() {
        guard acceptsInput else { return }
        window?.close()
    }

    // MARK: - 状态观察

    private func observe(auth: SteamAuthRoute, replacingInitialFailure: Bool) {
        // show() already presents the password page for an existing account.
        // A saved-session restore also replaces its old network failure. Neither
        // initial terminal value completes this panel's new operation; retain
        // all other initial states and every subsequent auth transition.
        let initialTerminalReplay: Int
        if replacingInitialFailure { initialTerminalReplay = 1 }
        else if auth.isOnline, case .online = auth.phase { initialTerminalReplay = 1 }
        else { initialTerminalReplay = 0 }
        auth.$phase
            .dropFirst(initialTerminalReplay)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self, let window = self.window, window.isVisible,
                      self.auth?.phase == phase else { return }
                self.apply(phase: phase)
            }
            .store(in: &cancellables)
    }

    private func setStatus(_ text: String) {
        guard statusLabel.stringValue != text else { return }
        statusLabel.stringValue = text
        statusLabel.toolTip = text
        if !text.isEmpty, window?.isVisible == true {
            NSAccessibility.post(element: statusLabel, notification: .valueChanged)
        }
    }

    private func apply(phase: SteamAccountSession.AuthPhase) {
        switch phase {
        case .idle, .cancelled:
            break
        case .connecting:
            setStatus(String(localized: "Connecting to Steam…"))
        case .authenticating:
            setStatus(String(localized: "Verifying credentials…"))
        case .qrChallenge(let url):
            showPage(.qr)
            renderQR(url: url)
            setStatus(String(localized: "Waiting for QR code confirmation…"))
        case .awaitingDeviceConfirmation:
            showPage(.guardInput(.deviceConfirmation))
            setStatus(String(localized: "Confirm this sign-in in the Steam mobile app"))
        case .awaitingDeviceCode(let previousIncorrect):
            showPage(.guardInput(.deviceCode(previousIncorrect: previousIncorrect)))
            panelView.guardSubmitButton.isEnabled = true
            // 重新进入验证码页（被拒/重发/换方式）时旧码已失效，先清空再聚焦，
            // 避免残留输入诱导一键重提再次失败。
            codeField.stringValue = ""
            setStatus(previousIncorrect ? String(localized: "The previous code was rejected. Enter it again.") : String(localized: "Entered Steam Guard verification"))
            window?.makeFirstResponder(codeField)
        case .awaitingEmailCode(let emailDomain, let previousIncorrect):
            showPage(.guardInput(.emailCode(emailDomain: emailDomain, previousIncorrect: previousIncorrect)))
            panelView.guardSubmitButton.isEnabled = true
            // 同上：进入验证码页必须丢弃失效旧码。
            codeField.stringValue = ""
            let domainText = emailDomain ?? String(localized: "Unknown")
            setStatus(previousIncorrect
                ? String(localized: "The previous code was rejected. Enter it again.")
                : String(localized: "Verification code sent to \(domainText)"))
            window?.makeFirstResponder(codeField)
        case .online:
            // §3.3：Keychain 保存失败必须可见，不伪报已保存——面板不自动关闭。
            let wasSilentRestore = isRestoringSavedSession
            isRestoringSavedSession = false
            if auth?.tokenSaveResult == .failed {
                showPage(.completed)
                setStatus(wasSilentRestore ? String(localized: "Previous sign-in restored, but saving to the Keychain failed.") : String(localized: "This session is working normally."))
            } else {
                if wasSilentRestore {
                    // 与启动静默恢复同源的服务级状态提示（restore 不重写令牌，
                    // 正常不会进入 tokenSaveResult == .failed 分支）。
                    SteamWorkshopService.shared.statusMessage = String(localized: "Steam sign-in restored.")
                }
                window?.close()
            }
        case .failed(_, let message):
            let wasSilentRestore = isRestoringSavedSession
            isRestoringSavedSession = false
            if modeSegment.selectedSegment == 0 {
                zoomWindow?.close()
                panelView.setQRImage(nil)
                panelView.stopQRLoading()
            }
            if wasSilentRestore {
                setRestoreFailureStatus()
            } else {
                setStatus(String(localized: "Sign-in didn't finish: \(message)"))
            }
            loginButton.isEnabled = true
        }
    }

    // MARK: - 动作

    @objc private func modeSwitched() {
        guard acceptsInput else { return }
        // 先同步作废旧 attempt，再切页；远端取消只携带旧身份。
        setStatus("")
        loginButton.isEnabled = true
        switch modeSegment.selectedSegment {
        case 0:
            cancelThenStart { [weak self] in self?.startQRLogin() }
        default:
            cancelThenStart { [weak self] in
                self?.showPage(.password)
                self?.window?.makeFirstResponder(self?.usernameField)
            }
        }
    }

    @objc private func refreshQR() {
        guard acceptsInput else { return }
        cancelThenStart { [weak self] in self?.startQRLogin() }
    }

    /// 本地先失效，远端异步取消不会影响新 attempt。手动登录动作终止静默恢复。
    private func cancelThenStart(_ run: @escaping () -> Void) {
        loginTask?.cancel()
        isRestoringSavedSession = false
        guard let auth else { return }
        auth.cancelPendingAuthentication()
        run()
    }

    @objc private func submitPassword() {
        guard acceptsInput, loginButton.isEnabled, let auth else { return }
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        if username.isEmpty {
            setStatus(String(localized: "Enter your Steam account."))
            window?.makeFirstResponder(usernameField)
            return
        }
        if password.isEmpty {
            setStatus(String(localized: "Enter your password."))
            window?.makeFirstResponder(passwordField)
            return
        }
        setStatus("")
        loginButton.isEnabled = false
        loginTask?.cancel()
        isRestoringSavedSession = false
        auth.cancelPendingAuthentication()
        loginTask = Task { [weak self] in
            do {
                // 成功后不在此处关窗：由 apply(.online) 依据 tokenSaveResult 决定
                // 直接关闭还是提示"Keychain 保存失败"（§3.3 不伪报已保存）。
                _ = try await auth.loginPassword(username: username, password: password)
            } catch SteamServiceClient.RequestError.helperError(let code, let message) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.loginButton.isEnabled = true
                    self?.setStatus(String(localized: "Sign-in failed (\(code)): \(message)"))
                    self?.window?.makeFirstResponder(self?.passwordField)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.loginButton.isEnabled = true
                    self?.setStatus(String(localized: "Sign-in failed: \(error.localizedDescription)"))
                    self?.window?.makeFirstResponder(self?.passwordField)
                }
            }
        }
    }

    // MARK: - 登录启动

    /// steam-ux-1：断线后打开面板的一次性静默恢复资格。connectionLost 只清
    /// 内存 tokens、不删 Keychain；此后打开面板不再被迫从头扫码——检测
    /// 「未在线 + phase 为 network 失败 + 记住登录且 Keychain 仍持有已授权
    /// 令牌」，命中即复用既有 restore 路径。
    private static func restorableSavedSession(
        for auth: SteamAuthRoute
    ) -> SteamWorkshopTokenStore.Payload? {
        guard !auth.isOnline, !auth.expired,
              case .failed(let code, _) = auth.phase, code == "network",
              UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey),
              SteamWorkshopTokenStore.isRestoreAuthorized,
              let saved = SteamWorkshopTokenStore.load(),
              !saved.refreshToken.isEmpty,
              !saved.steamId.isEmpty else { return nil }
        return saved
    }

    /// 静默恢复挂 loginTask，继承「关闭面板即取消」合同（§3.2）。成功经
    /// apply(.online) 关窗；失败按既有 disposition 分流文案（明确拒绝已删
    /// 令牌 → 重新扫码；网络失败保留令牌 → 可手动扫码或稍后重试），不自动
    /// 无限重启。安全前提：显式传 saved.steamId，恢复到不同账号由 auth 层
    /// 拒绝并清理令牌。
    private func startSilentRestore(_ saved: SteamWorkshopTokenStore.Payload) {
        guard let auth else { return }
        isRestoringSavedSession = true
        modeSegment.setSelected(true, forSegment: 0)
        showPage(.qr)
        setStatus(String(localized: "Restoring previous sign-in…"))
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            do {
                _ = try await auth.restore(
                    refreshToken: saved.refreshToken,
                    accountName: saved.accountName,
                    expectedSteamId: saved.steamId
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let window = self.window, window.isVisible else { return }
                    self.panelView.stopQRLoading()
                    // 文案兜底：phase sink 的 apply(.failed) 已用同源文案时
                    // setStatus 幂等；该 sink 不再到达时由这里保证提示可见。
                    self.setRestoreFailureStatus()
                }
            }
        }
    }

    /// 恢复失败文案（按 disposition 分流）：expired = 明确拒绝（令牌已删）；
    /// 其余按 keepToken 处理（令牌保留，网络原因下次再试）。
    private func setRestoreFailureStatus() {
        if auth?.expired == true {
            setStatus(String(localized: "The saved sign-in has expired. Scan the QR code to sign in again."))
        } else {
            setStatus(String(localized: "Couldn’t restore your last sign-in (network issue). Your sign-in info was kept; scan the QR code to sign in or try again later."))
        }
    }

    private func resetForNewAttempt() {
        // 面板新会话一律清掉上一轮静默恢复残留（如恢复期间窗口被关闭、
        // phase sink 未消费标志的情况），避免普通登录误用恢复文案。
        isRestoringSavedSession = false
        setStatus("")
        loginButton.isEnabled = true
        rememberCheck.state = UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey)
            ? .on : .off
    }

    private func startQRLogin() {
        guard let auth else { return }
        modeSegment.setSelected(true, forSegment: 0)
        showPage(.qr)
        setStatus(String(localized: "Generating QR code…"))
        loginTask?.cancel()
        auth.cancelPendingAuthentication()
        loginTask = Task { [weak self] in
            do {
                _ = try await auth.loginQR()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.panelView.setQRImage(nil)
                    self?.panelView.stopQRLoading()
                    self?.setStatus(String(localized: "QR code sign-in wasn’t completed: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - 页面投影

    private typealias Page = SteamLoginPanelView.Page

    private func showPage(_ page: Page) {
        // A replaced challenge must never leave a scannable old enlarged image.
        zoomWindow?.close()
        panelView.setQRImage(nil)
        panelView.showPage(page)
        // All auth modes occupy the same window frame; only the body changes.
    }

    @objc private func submitGuardCode() {
        guard acceptsInput, panelView.guardSubmitButton.isEnabled, let auth else { return }
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            setStatus(String(localized: "Enter the verification code."))
            window?.makeFirstResponder(codeField)
            return
        }
        setStatus(String(localized: "Submitting verification code…"))
        panelView.guardSubmitButton.isEnabled = false
        Task { [weak self] in
            await auth.submit(code: code)
            self?.panelView.guardSubmitButton.isEnabled = true
        }
    }

    // MARK: - 二维码渲染（本机 Core Image，清晰缩放）

    private func renderQR(url: String) {
        panelView.setQRImage(SteamLoginQRCodeImageView.image(for: url))
    }
}
