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
        qrImageView.toolTip = "点击放大二维码"
        qrImageView.setAccessibilityElement(true)
        qrImageView.setAccessibilityRole(.image)
        qrImageView.setAccessibilityLabel("Steam 登录二维码")
        qrImageView.setAccessibilityHelp("使用 Steam 手机应用扫码确认；也可按 Tab 移到“放大二维码”查看大图。")
    }

    /// 二维码放大窗：只复用当前挑战的图，独立关闭，不影响面板认证（§3.2）。
    @objc private func showZoomWindow() {
        guard let image = qrImageView.image else { return }
        if let existing = zoomWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 344),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "二维码"
        window.level = .floating
        self.window?.addChildWindow(window, ordered: .above)
        window.isReleasedWhenClosed = false
        let imageView = SteamLoginQRCodeImageView(frame: NSRect(x: 20, y: 12, width: 280, height: 280))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let hint = NSTextField(labelWithString: "使用 Steam 手机应用扫码确认")
        hint.frame = NSRect(x: 20, y: 300, width: 280, height: 20)
        hint.alignment = .center
        hint.textColor = .secondaryLabelColor
        let content = NSView()
        content.addSubview(imageView)
        content.addSubview(hint)
        window.contentView = content
        zoomWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func rememberToggled() {
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
            window.makeKeyAndOrderFront(nil)
            return
        }
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        self.auth = auth
        observe(auth: auth)

        let window = SteamLoginWindow(
            contentRect: NSRect(x: 0, y: 0, width: SteamLoginPanelView.width, height: SteamLoginPanelView.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.title = "登录 Steam"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.contentView = panelView
        resetForNewAttempt()
        if auth.isOnline {
            // 已在线的「切换账号」：进密码页（避免空白二维码页），说明会替换当前
            // 会话；新登录在 helper 侧顶替旧会话，成功后 steamId/accountName 更新。
            showPage(.password)
            setStatus("当前已登录 \(auth.accountName ?? "Steam 账号")；重新登录将切换账号。")
        } else {
            startQRLogin()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
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
        window?.close()
    }

    // MARK: - 状态观察

    private func observe(auth: SteamAuthRoute) {
        auth.$phase
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
            setStatus("正在连接 Steam…")
        case .authenticating:
            setStatus("正在验证凭据…")
        case .qrChallenge(let url):
            showPage(.qr)
            renderQR(url: url)
            setStatus("等待扫码确认…")
        case .awaitingDeviceConfirmation:
            showPage(.guardInput(.deviceConfirmation))
            setStatus("请在 Steam 手机应用中确认本次登录")
        case .awaitingDeviceCode(let previousIncorrect):
            showPage(.guardInput(.deviceCode(previousIncorrect: previousIncorrect)))
            panelView.guardSubmitButton.isEnabled = true
            setStatus(previousIncorrect ? "上一枚验证码被拒绝，请重新输入" : "已进入 Steam 令牌验证")
            window?.makeFirstResponder(codeField)
        case .awaitingEmailCode(let emailDomain, let previousIncorrect):
            showPage(.guardInput(.emailCode(emailDomain: emailDomain, previousIncorrect: previousIncorrect)))
            panelView.guardSubmitButton.isEnabled = true
            setStatus(previousIncorrect
                ? "上一枚验证码被拒绝，请重新输入"
                : "验证码已发送到邮箱 \(emailDomain ?? "(未知)")")
            window?.makeFirstResponder(codeField)
        case .online:
            // §3.3：Keychain 保存失败必须可见，不伪报已保存——面板不自动关闭。
            if auth?.tokenSaveResult == .failed {
                showPage(.completed)
                setStatus("本次会话可正常使用。")
            } else {
                window?.close()
            }
        case .failed(_, let message):
            if modeSegment.selectedSegment == 0 {
                zoomWindow?.close()
                panelView.setQRImage(nil)
                panelView.stopQRLoading()
            }
            setStatus("登录未完成：\(message)")
            loginButton.isEnabled = true
        }
    }

    // MARK: - 动作

    @objc private func modeSwitched() {
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
        cancelThenStart { [weak self] in self?.startQRLogin() }
    }

    /// 本地先失效，远端异步取消不会影响新 attempt。
    private func cancelThenStart(_ run: @escaping () -> Void) {
        loginTask?.cancel()
        guard let auth else { return }
        auth.cancelPendingAuthentication()
        run()
    }

    @objc private func submitPassword() {
        guard loginButton.isEnabled, let auth else { return }
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        if username.isEmpty {
            setStatus("请输入 Steam 账号。")
            window?.makeFirstResponder(usernameField)
            return
        }
        if password.isEmpty {
            setStatus("请输入密码。")
            window?.makeFirstResponder(passwordField)
            return
        }
        setStatus("")
        loginButton.isEnabled = false
        loginTask?.cancel()
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
                    self?.setStatus("登录失败（\(code)）：\(message)")
                    self?.window?.makeFirstResponder(self?.passwordField)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.loginButton.isEnabled = true
                    self?.setStatus("登录失败：\(error.localizedDescription)")
                    self?.window?.makeFirstResponder(self?.passwordField)
                }
            }
        }
    }

    // MARK: - 登录启动

    private func resetForNewAttempt() {
        setStatus("")
        loginButton.isEnabled = true
        rememberCheck.state = UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey)
            ? .on : .off
    }

    private func startQRLogin() {
        guard let auth else { return }
        modeSegment.setSelected(true, forSegment: 0)
        showPage(.qr)
        setStatus("正在生成二维码…")
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
                    self?.setStatus("二维码登录未完成：\(error.localizedDescription)")
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
        guard panelView.guardSubmitButton.isEnabled, let auth else { return }
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            setStatus("请输入验证码。")
            window?.makeFirstResponder(codeField)
            return
        }
        setStatus("正在提交验证码…")
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
