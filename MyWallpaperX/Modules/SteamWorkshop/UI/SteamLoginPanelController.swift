//
//  SteamLoginPanelController.swift
//  MyWallpaperX
//

import AppKit
import CoreImage
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

    // 页面控件
    private let modeSegment = NSSegmentedControl(
        labels: ["二维码登录", "账号密码"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let containerStack = NSStackView()
    private let qrImageView = NSImageView()
    private let qrHintLabel = NSTextField(labelWithString: "使用 Steam 手机应用扫码确认")
    private let refreshQRButton = NSButton(title: "刷新二维码", target: nil, action: nil)
    private let usernameField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let rememberCheck = NSButton(checkboxWithTitle: "记住登录（下次打开自动恢复）", target: nil, action: nil)
    private let loginButton = NSButton(title: "登录", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "取消登录", target: nil, action: nil)

    private var zoomWindow: NSWindow?

    private override init(window: NSWindow?) {
        super.init(window: nil)
        modeSegment.target = self
        modeSegment.action = #selector(modeSwitched)
        refreshQRButton.target = self
        refreshQRButton.action = #selector(refreshQR)
        loginButton.target = self
        loginButton.action = #selector(submitPassword)
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
        window.isReleasedWhenClosed = false
        let imageView = NSImageView(frame: NSRect(x: 20, y: 12, width: 280, height: 280))
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "登录 Steam"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        buildContent()
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
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭面板 = 取消认证；迟到的成功回调不会再打开窗口（observe 中判断可见性）。
        // 不保存上次输入的秘密（§3.2）。
        passwordField.stringValue = ""
        codeField.stringValue = ""
        zoomWindow?.close()
        guard let auth else { return }
        loginTask?.cancel()
        if !auth.isOnline {
            Task { await auth.cancel() }
        }
    }

    @objc private func cancelAndClose() {
        window?.close()
    }

    // MARK: - 状态观察

    private func observe(auth: SteamAuthRoute) {
        auth.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self, let window = self.window, window.isVisible else { return }
                self.apply(phase: phase)
            }
            .store(in: &cancellables)
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
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
            setStatus(previousIncorrect ? "上一枚验证码被拒绝，请重新输入" : "已进入 Steam 令牌验证")
            if previousIncorrect {
                window?.makeFirstResponder(codeField)
            }
        case .awaitingEmailCode(let emailDomain, let previousIncorrect):
            showPage(.guardInput(.emailCode(emailDomain: emailDomain, previousIncorrect: previousIncorrect)))
            setStatus(previousIncorrect
                ? "上一枚验证码被拒绝，请重新输入"
                : "验证码已发送到邮箱 \(emailDomain ?? "(未知)")")
            if previousIncorrect {
                window?.makeFirstResponder(codeField)
            }
        case .online:
            // §3.3：Keychain 保存失败必须可见，不伪报已保存——面板不自动关闭。
            if auth?.tokenSaveResult == .failed {
                setStatus("登录成功，但 Keychain 保存失败——本次会话不会被记住，可关闭后重试登录。")
            } else {
                window?.close()
            }
        case .failed(let code, let message):
            setStatus("登录失败（\(code)）：\(message)")
            loginButton.isEnabled = true
        }
    }

    // MARK: - 动作

    @objc private func modeSwitched() {
        // 切换方式先取消旧 attempt（§3.2），取消收口后再进入新页面（串行化）。
        statusLabel.stringValue = ""
        switch modeSegment.selectedSegment {
        case 0:
            cancelThenStart { [weak self] in self?.startQRLogin() }
        default:
            cancelThenStart { [weak self] in self?.showPage(.password) }
        }
    }

    @objc private func refreshQR() {
        cancelThenStart { [weak self] in self?.startQRLogin() }
    }

    /// 取消旧 attempt 收口后再执行新动作，避免 cancel 的异步收尾落到新 attempt 之后。
    private func cancelThenStart(_ run: @escaping () -> Void) {
        loginTask?.cancel()
        guard let auth else { return }
        if auth.isOnline {
            run()
            return
        }
        loginTask = Task { [weak self] in
            await auth.cancel()
            guard !Task.isCancelled else { return }
            await MainActor.run { run() }
        }
    }

    @objc private func submitPassword() {
        guard let auth else { return }
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
        statusLabel.stringValue = ""
        loginButton.isEnabled = false
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            do {
                // 成功后不在此处关窗：由 apply(.online) 依据 tokenSaveResult 决定
                // 直接关闭还是提示"Keychain 保存失败"（§3.3 不伪报已保存）。
                _ = try await auth.loginPassword(username: username, password: password)
            } catch SteamServiceClient.RequestError.helperError(let code, let message) {
                await MainActor.run {
                    self?.loginButton.isEnabled = true
                    self?.setStatus("登录失败（\(code)）：\(message)")
                    self?.window?.makeFirstResponder(self?.passwordField)
                }
            } catch is CancellationError {
                await MainActor.run { self?.loginButton.isEnabled = true }
            } catch {
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
        rememberCheck.state = UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey)
            ? .on : .off
    }

    private func startQRLogin() {
        guard let auth else { return }
        modeSegment.setSelected(true, forSegment: 0)
        showPage(.qr)
        setStatus("正在生成二维码…")
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            do {
                _ = try await auth.loginQR()
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self?.setStatus("二维码登录未完成：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 页面构建（沿用系统控件风格）

    private enum Page {
        case qr
        case password
        case guardInput(GuardKind)

        enum GuardKind {
            case deviceConfirmation
            case deviceCode(previousIncorrect: Bool)
            case emailCode(emailDomain: String?, previousIncorrect: Bool)
        }

        var contentHeight: CGFloat {
            switch self {
            case .qr: return 470
            case .password: return 340
            case .guardInput: return 360
            }
        }
    }

    private func buildContent() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "登录 Steam")
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 3)

        containerStack.orientation = .vertical
        containerStack.alignment = .centerX
        containerStack.spacing = 12
        containerStack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: NSFont.systemFontSize - 1)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 340
        statusLabel.alignment = .center

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small

        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(modeSegment)
        content.addArrangedSubview(containerStack)
        content.addArrangedSubview(statusLabel)
        content.addArrangedSubview(cancelButton)

        window?.contentView = NSView()
        window?.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: window!.contentView!.topAnchor),
            content.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor),
        ])

        showPage(.qr)
    }

    private func showPage(_ page: Page) {
        containerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        window?.contentView?.subviews.first?.invalidateIntrinsicContentSize()

        switch page {
        case .qr:
            qrImageView.image = nil
            qrHintLabel.textColor = .secondaryLabelColor
            refreshQRButton.bezelStyle = .rounded
            refreshQRButton.controlSize = .small
            containerStack.addArrangedSubview(qrImageView)
            containerStack.addArrangedSubview(qrHintLabel)
            containerStack.addArrangedSubview(refreshQRButton)
        case .password:
            containerStack.addArrangedSubview(self.usernameField)
            containerStack.addArrangedSubview(passwordField)
            containerStack.addArrangedSubview(rememberCheck)
            containerStack.addArrangedSubview(loginButton)
        case .guardInput(let kind):
            let hint = NSTextField(labelWithString: guardHint(kind))
            hint.textColor = .secondaryLabelColor
            hint.preferredMaxLayoutWidth = 330
            hint.maximumNumberOfLines = 3
            hint.alignment = .center
            containerStack.addArrangedSubview(hint)
            switch kind {
            case .deviceConfirmation:
                break
            case .deviceCode, .emailCode:
                containerStack.addArrangedSubview(codeField)
                let submit = NSButton(title: "提交验证码", target: self, action: #selector(submitGuardCode))
                submit.bezelStyle = .rounded
                containerStack.addArrangedSubview(submit)
            }
        }

        window?.setContentSize(NSSize(width: 400, height: page.contentHeight))
    }

    private let codeField = NSTextField()

    private func guardHint(_ kind: Page.GuardKind) -> String {
        switch kind {
        case .deviceConfirmation:
            return "请在 Steam 手机应用中确认本次登录。"
        case .deviceCode:
            return "输入 Steam 手机令牌上显示的当前验证码。"
        case .emailCode(let domain, _):
            return "验证码已发送到邮箱 \(domain ?? "(未知)")，请输入邮件中的验证码。"
        }
    }

    @objc private func submitGuardCode() {
        guard let auth else { return }
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            setStatus("请输入验证码。")
            window?.makeFirstResponder(codeField)
            return
        }
        setStatus("正在提交验证码…")
        Task { await auth.submit(code: code) }
    }

    // MARK: - 二维码渲染（本机 Core Image，清晰缩放）

    private func renderQR(url: String) {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(Data(url.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return }
        let scale: CGFloat = 10
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return }
        let size = CGFloat(240)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSImage(cgImage: cgImage, size: NSSize(width: size - 16, height: size - 16))
            .draw(in: NSRect(x: 8, y: 8, width: size - 16, height: size - 16))
        image.unlockFocus()
        qrImageView.image = image
    }
}
