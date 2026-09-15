import AppKit
import CoreImage

/// Presentation only. Authentication attempts and credentials remain owned by
/// SteamLoginPanelController and SteamAuthRoute.
@MainActor
final class SteamLoginPanelView: NSView, NSTextFieldDelegate {
    enum Page {
        case qr, password, guardInput(GuardKind), completed
        enum GuardKind {
            case deviceConfirmation
            case deviceCode(previousIncorrect: Bool)
            case emailCode(emailDomain: String?, previousIncorrect: Bool)
        }
    }

    static let width: CGFloat = 420
    static let height: CGFloat = 480

    let modeSegment = NSSegmentedControl(labels: ["二维码登录", "账号密码"], trackingMode: .selectOne, target: nil, action: nil)
    let qrImageView = SteamLoginQRCodeImageView()
    let refreshQRButton = NSButton(title: "刷新二维码", target: nil, action: nil)
    let zoomQRButton = NSButton(title: "放大查看", target: nil, action: nil)
    let usernameField = SteamLoginTextField()
    let passwordField = SteamLoginSecureField()
    private let revealedPasswordField = SteamLoginTextField()
    private let revealButton = NSButton(title: "", target: nil, action: nil)
    let codeField = SteamLoginTextField()
    let rememberCheck = NSButton(checkboxWithTitle: "记住登录，下次自动恢复", target: nil, action: nil)
    let loginButton = NSButton(title: "登录 Steam", target: nil, action: nil)
    let guardSubmitButton = NSButton(title: "提交验证码", target: nil, action: nil)
    let cancelButton = NSButton(title: "", target: nil, action: nil)
    let doneButton = NSButton(title: "完成", target: nil, action: nil)
    private let submitArea = NSStackView()
    private let qrActions = NSStackView()
    private let qrFailureLabel = NSTextField(wrappingLabelWithString: "二维码已失效\n请重新生成")
    let statusLabel = NSTextField(wrappingLabelWithString: "")

    private let glass = NSGlassEffectView()
    private let overlay = NSView()
    private let content = NSStackView()
    private let body = NSView()
    private let qrPage = NSStackView()
    private let passwordPage = NSStackView()
    private let guardPage = NSStackView()
    private let guardHint = NSTextField(wrappingLabelWithString: "")
    private let guardSymbol = NSImageView()
    private let qrPlaceholder = NSProgressIndicator()
    private let qrTile = NSView()
    private var codeGroup: NSView!
    private var fieldSurfaces: [NSView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 22
        glass.layer?.masksToBounds = true
        glass.cornerRadius = 22
        glass.style = .regular
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = 22
        overlay.layer?.borderWidth = 1
        for surface in [glass, overlay] {
            surface.translatesAutoresizingMaskIntoConstraints = false
            addSubview(surface)
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: trailingAnchor),
                surface.topAnchor.constraint(equalTo: topAnchor),
                surface.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        configureStack(content, spacing: 12)
        content.alignment = .centerX
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])
        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 14
        let icon = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 27, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 44), icon.heightAnchor.constraint(equalToConstant: 44)])
        let titles = NSStackView()
        configureStack(titles, spacing: 4)
        titles.alignment = .leading
        let title = NSTextField(labelWithString: "登录 Steam")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "连接你的创意工坊")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        titles.addArrangedSubview(title)
        titles.addArrangedSubview(subtitle)
        heading.addArrangedSubview(icon)
        heading.addArrangedSubview(titles)
        content.addArrangedSubview(heading)
        modeSegment.segmentStyle = .rounded
        modeSegment.controlSize = .large
        modeSegment.setAccessibilityLabel("Steam 登录方式")
        addFullWidth(modeSegment, to: content)
        addFullWidth(body, to: content)
        body.heightAnchor.constraint(equalToConstant: 196).isActive = true
        buildQRPage()
        buildPasswordPage()
        buildGuardPage()
        for page in [qrPage, passwordPage, guardPage] {
            body.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: body.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: body.trailingAnchor),
                page.centerYAnchor.constraint(equalTo: body.centerYAnchor),
                page.topAnchor.constraint(greaterThanOrEqualTo: body.topAnchor),
                page.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor)
            ])
        }

        rememberCheck.font = .systemFont(ofSize: 12)
        rememberCheck.toolTip = "仅将登录令牌保存在 macOS 钥匙串，不保存密码。"
        content.addArrangedSubview(rememberCheck)
        configureStack(submitArea, spacing: 0)
        addFullWidth(submitArea, to: content)
        submitArea.heightAnchor.constraint(equalToConstant: 38).isActive = true
        for button in [loginButton, guardSubmitButton, doneButton] {
            styleButton(button, primary: true)
            addFullWidth(button, to: submitArea)
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        }
        addFullWidth(qrActions, to: submitArea)
        qrActions.heightAnchor.constraint(equalToConstant: 38).isActive = true
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        statusLabel.setAccessibilityElement(true)
        statusLabel.setAccessibilityRole(.staticText)
        statusLabel.setAccessibilityLabel("Steam 登录状态")
        addFullWidth(statusLabel, to: content)
        statusLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭登录")
        cancelButton.isBordered = false
        cancelButton.toolTip = "关闭并取消本次登录（Esc）"
        cancelButton.setAccessibilityLabel("关闭登录")
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.widthAnchor.constraint(equalToConstant: 32),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cancelButton.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
        showPage(.qr)
        updateAppearance()
    }

    private func buildQRPage() {
        configureStack(qrPage, spacing: 8)
        qrPage.alignment = .centerX
        qrTile.wantsLayer = true
        qrTile.layer?.backgroundColor = NSColor.white.cgColor
        qrTile.layer?.cornerRadius = 16
        qrTile.layer?.masksToBounds = true
        qrTile.translatesAutoresizingMaskIntoConstraints = false
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrTile.addSubview(qrImageView)
        qrPlaceholder.style = .spinning
        qrPlaceholder.controlSize = .regular
        qrPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        qrTile.addSubview(qrPlaceholder)
        qrFailureLabel.font = .systemFont(ofSize: 13, weight: .medium)
        qrFailureLabel.textColor = .darkGray
        qrFailureLabel.alignment = .center
        qrFailureLabel.isHidden = true
        qrFailureLabel.translatesAutoresizingMaskIntoConstraints = false
        qrTile.addSubview(qrFailureLabel)
        NSLayoutConstraint.activate([
            qrFailureLabel.centerYAnchor.constraint(equalTo: qrTile.centerYAnchor),
            qrFailureLabel.leadingAnchor.constraint(equalTo: qrTile.leadingAnchor, constant: 12),
            qrFailureLabel.trailingAnchor.constraint(equalTo: qrTile.trailingAnchor, constant: -12)
        ])
        NSLayoutConstraint.activate([
            qrTile.widthAnchor.constraint(equalToConstant: 160), qrTile.heightAnchor.constraint(equalToConstant: 160),
            qrImageView.leadingAnchor.constraint(equalTo: qrTile.leadingAnchor, constant: 8),
            qrImageView.trailingAnchor.constraint(equalTo: qrTile.trailingAnchor, constant: -8),
            qrImageView.topAnchor.constraint(equalTo: qrTile.topAnchor, constant: 8),
            qrImageView.bottomAnchor.constraint(equalTo: qrTile.bottomAnchor, constant: -8),
            qrPlaceholder.centerXAnchor.constraint(equalTo: qrTile.centerXAnchor),
            qrPlaceholder.centerYAnchor.constraint(equalTo: qrTile.centerYAnchor)
        ])
        qrPage.addArrangedSubview(qrTile)
        let hint = NSTextField(labelWithString: "打开 Steam 手机应用，扫码并确认登录")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        qrPage.addArrangedSubview(hint)
        qrActions.orientation = .horizontal
        qrActions.distribution = .fillEqually
        qrActions.spacing = 10
        qrActions.addArrangedSubview(zoomQRButton)
        qrActions.addArrangedSubview(refreshQRButton)
        [refreshQRButton, zoomQRButton].forEach { styleButton($0) }

    }

    private func buildPasswordPage() {
        configureStack(passwordPage, spacing: 16)
        addFullWidth(fieldGroup(usernameField, title: "Steam 账号", placeholder: "输入账号名称", symbol: "person"), to: passwordPage)
        addFullWidth(fieldGroup(passwordField, title: "密码", placeholder: "输入 Steam 密码", symbol: "key"), to: passwordPage)
        if let surface = passwordField.superview {
            // Both editors occupy the same bounds; the secure editor owns the submitted value.
            revealedPasswordField.isBordered = false
            revealedPasswordField.drawsBackground = false
            revealedPasswordField.font = passwordField.font
            revealedPasswordField.placeholderString = passwordField.placeholderString
            revealedPasswordField.setAccessibilityLabel("密码（可见）")
            revealedPasswordField.isHidden = true
            revealedPasswordField.delegate = self
            passwordField.delegate = self
            revealedPasswordField.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(revealedPasswordField)
            revealButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "显示密码")
            revealButton.isBordered = false
            revealButton.target = self
            revealButton.action = #selector(togglePasswordVisibility)
            revealButton.toolTip = "显示密码"
            revealButton.setAccessibilityLabel("显示密码")
            revealButton.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(revealButton)
            for constraint in surface.constraints where constraint.firstItem as? NSView === passwordField && constraint.firstAttribute == .trailing { constraint.isActive = false }
            NSLayoutConstraint.activate([
                revealButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -4),
                revealButton.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                revealButton.widthAnchor.constraint(equalToConstant: 32),
                revealButton.heightAnchor.constraint(equalToConstant: 32),
                passwordField.trailingAnchor.constraint(equalTo: revealButton.leadingAnchor, constant: -4),
                revealedPasswordField.leadingAnchor.constraint(equalTo: passwordField.leadingAnchor),
                revealedPasswordField.trailingAnchor.constraint(equalTo: passwordField.trailingAnchor),
                revealedPasswordField.centerYAnchor.constraint(equalTo: passwordField.centerYAnchor)
            ])
        }

    }

    func clearSecrets() {
        passwordField.stringValue = ""
        revealedPasswordField.stringValue = ""
        codeField.stringValue = ""
        hidePassword()
    }

    private func hidePassword() {
        revealedPasswordField.isHidden = true
        passwordField.isHidden = false
        revealButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        revealButton.toolTip = "显示密码"
        revealButton.setAccessibilityLabel("显示密码")
    }

    @objc private func togglePasswordVisibility() {
        let reveal = revealedPasswordField.isHidden
        if reveal {
            revealedPasswordField.stringValue = passwordField.stringValue
            revealedPasswordField.target = passwordField.target
            revealedPasswordField.action = passwordField.action
            revealedPasswordField.isHidden = false
            passwordField.isHidden = true
            revealButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            revealButton.toolTip = "隐藏密码"
            revealButton.setAccessibilityLabel("隐藏密码")
            window?.makeFirstResponder(revealedPasswordField)
        } else {
            hidePassword()
            window?.makeFirstResponder(passwordField)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSTextField === revealedPasswordField {
            passwordField.stringValue = revealedPasswordField.stringValue
        }
    }

    private func buildGuardPage() {
        configureStack(guardPage, spacing: 16)
        guardPage.alignment = .centerX
        guardSymbol.image = NSImage(systemSymbolName: "iphone.badge.checkmark", accessibilityDescription: nil)
        guardSymbol.symbolConfiguration = .init(pointSize: 32, weight: .regular)
        guardSymbol.contentTintColor = .controlAccentColor
        guardPage.addArrangedSubview(guardSymbol)
        guardHint.font = .systemFont(ofSize: 13)
        guardHint.alignment = .center
        addFullWidth(guardHint, to: guardPage)
        codeGroup = fieldGroup(codeField, title: "Steam Guard 验证码", placeholder: "输入验证码", symbol: "lock.shield")
        codeField.alignment = .center
        codeField.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        addFullWidth(codeGroup, to: guardPage)

    }

    func showPage(_ page: Page) {
        hidePassword()
        qrPage.isHidden = true
        passwordPage.isHidden = true
        guardPage.isHidden = true
        loginButton.isHidden = true
        guardSubmitButton.isHidden = true
        doneButton.isHidden = true
        modeSegment.isHidden = false
        rememberCheck.isHidden = false
        qrActions.isHidden = true
        switch page {
        case .qr:
            qrPage.isHidden = false
            modeSegment.selectedSegment = 0
            qrActions.isHidden = false
        case .password:
            passwordPage.isHidden = false
            modeSegment.selectedSegment = 1
            loginButton.isHidden = false
        case .guardInput(let kind):
            guardPage.isHidden = false
            let needsCode: Bool
            switch kind {
            case .deviceConfirmation:
                needsCode = false
                guardHint.stringValue = "请在 Steam 手机应用中\n确认本次登录请求。"
            case .deviceCode:
                needsCode = true
                guardHint.stringValue = "输入 Steam 手机令牌上显示的当前验证码。"
            case .emailCode(let domain, _):
                needsCode = true
                guardHint.stringValue = "输入发送至 \(domain ?? "你的邮箱") 的验证码。"
            }
            codeGroup.isHidden = !needsCode
            guardSubmitButton.isHidden = !needsCode

        case .completed:
            guardPage.isHidden = false
            guardHint.stringValue = "已登录 Steam\n本次登录未能保存，下次需要重新登录。"
            codeGroup.isHidden = true
            modeSegment.isHidden = true
            rememberCheck.isHidden = true
            doneButton.isHidden = false
        }
    }

    func setQRImage(_ image: NSImage?) {
        qrFailureLabel.isHidden = true
        refreshQRButton.title = "刷新二维码"
        refreshQRButton.isEnabled = image != nil
        qrImageView.image = image
        zoomQRButton.isEnabled = image != nil
        qrPlaceholder.isHidden = image != nil
        if image == nil { qrPlaceholder.startAnimation(nil) } else { qrPlaceholder.stopAnimation(nil) }
    }

    func stopQRLoading() {
        qrPlaceholder.stopAnimation(nil)
        qrPlaceholder.isHidden = true
        qrFailureLabel.isHidden = false
        refreshQRButton.title = "重新生成"
        refreshQRButton.isEnabled = true
    }

    private func fieldGroup(_ field: NSTextField, title: String, placeholder: String, symbol: String) -> NSView {
        let group = NSStackView()
        configureStack(group, spacing: 7)
        group.alignment = .leading
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        group.addArrangedSubview(label)
        let surface = NSView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 10
        surface.layer?.borderWidth = 0.8
        fieldSurfaces.append(surface)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 14)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.setAccessibilityLabel(title)
        for view in [icon, field] { view.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(view) }
        NSLayoutConstraint.activate([
            surface.heightAnchor.constraint(equalToConstant: 40),
            icon.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: surface.centerYAnchor)
        ])
        addFullWidth(surface, to: group)
        return group
    }

    private func styleButton(_ button: NSButton, primary: Bool = false) {
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        if primary { button.bezelColor = .controlAccentColor }
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    private func configureStack(_ stack: NSStackView, spacing: CGFloat) {
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
    }
    private func addFullWidth(_ child: NSView, to stack: NSStackView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func updateAppearance() {
        let dark = InspectorGlassPalette.isDarkMode(for: self)
        glass.tintColor = InspectorGlassPalette.baseTint(isDark: dark)
        glass.layer?.backgroundColor = InspectorGlassPalette.innerFill(isDark: dark).cgColor
        overlay.layer?.backgroundColor = InspectorGlassPalette.panelFill(isDark: dark).cgColor
        overlay.layer?.borderColor = InspectorGlassPalette.panelStroke(isDark: dark).cgColor
        for surface in fieldSurfaces {
            surface.layer?.backgroundColor = NSColor.black.withAlphaComponent(dark ? 0.20 : 0.04).cgColor
            surface.layer?.borderColor = (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.16 : 0.10).cgColor
        }
    }
}

final class SteamLoginWindow: NSPanel {
    override func cancelOperation(_ sender: Any?) { close() }
    override func performClose(_ sender: Any?) { close() }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SteamLoginQRCodeImageView: NSImageView {
    static func image(for challenge: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(challenge.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Four quiet modules, opaque white backing, integer generation scale.
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor.white).cropped(to: extent)
        let padded = output.composited(over: white).cropped(to: extent)
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: image, size: scaled.extent.size)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        super.draw(dirtyRect)
    }
}

/// The focus ring follows the rounded input surface, not the text editor's
/// smaller rectangular bounds inside it.
final class SteamLoginTextField: NSTextField {
    override var focusRingMaskBounds: NSRect {
        superview.map { convert($0.bounds, from: $0) } ?? bounds
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 10, yRadius: 10).fill()
    }
}

final class SteamLoginSecureField: NSSecureTextField {
    override var focusRingMaskBounds: NSRect {
        superview.map { convert($0.bounds, from: $0) } ?? bounds
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 10, yRadius: 10).fill()
    }
}
