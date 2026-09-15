//
//  SteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class SteamWorkshopLoginOverlayView: NSView, NSTextFieldDelegate {
    private enum Metrics {
        static let panelWidth: CGFloat = 390
        static let panelHeight: CGFloat = 544
        static let panelCornerRadius: CGFloat = 22
        static let fieldHeight: CGFloat = 34
        static let fieldGroupSpacing: CGFloat = 6
    }

    private let service = SteamWorkshopService.shared
    private var cancellables = Set<AnyCancellable>()

    private let panelView = NSGlassEffectView()
    private let panelOverlayView = NSView()
    private let contentStack = NSStackView()
    private let iconContainer = NSView()
    private let iconView = NSImageView()
    private let modeBadge = NSView()
    private let modeBadgeLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let pendingCallout = NSView()
    private let pendingCalloutLabel = NSTextField(wrappingLabelWithString: "")
    private let usernameGroup = NSStackView()
    private let passwordGroup = NSStackView()
    private let guardGroup = NSStackView()
    private let usernameFieldContainer = NSView()
    private let passwordFieldContainer = NSView()
    private let guardFieldContainer = NSView()
    private let usernameField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let guardField = NSTextField()
    private let actionRow = NSStackView()
    private let primaryButton = InspectorFooterButton(
        title: "发送登录请求",
        image: NSImage(systemSymbolName: "arrow.right.circle.fill", accessibilityDescription: "发送登录请求"),
        kind: .primary,
        target: nil,
        action: #selector(performPrimaryAction)
    )
    private let closeButton = InspectorFooterButton(
        title: "关闭",
        image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭"),
        kind: .secondary,
        target: nil,
        action: #selector(closeLogin)
    )
    private let footnoteLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        observeService()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? (bounds.contains(point) ? self : nil)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        refreshAppearance()
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else { return }
            window?.makeFirstResponder(self.isAwaitingGuard ? self.guardField : self.usernameField)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === usernameField {
            service.steamUsername = field.stringValue
        } else if field === passwordField {
            service.steamPassword = field.stringValue
        } else if field === guardField {
            service.steamGuardCode = field.stringValue
        }
    }

    private var isAwaitingGuard: Bool {
        service.authPhase == .awaitingGuardCode
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        panelView.cornerRadius = Metrics.panelCornerRadius
        panelView.style = .regular
        panelView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panelView)

        panelOverlayView.wantsLayer = true
        panelOverlayView.layer?.cornerRadius = Metrics.panelCornerRadius
        panelOverlayView.layer?.masksToBounds = true
        panelOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panelOverlayView)

        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.distribution = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        setupHeader()
        setupFields()
        setupActions()

        NSLayoutConstraint.activate([
            panelView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -95),
            panelView.centerYAnchor.constraint(equalTo: centerYAnchor),
            panelView.widthAnchor.constraint(equalToConstant: Metrics.panelWidth),
            panelView.heightAnchor.constraint(equalToConstant: Metrics.panelHeight),

            panelOverlayView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            panelOverlayView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            panelOverlayView.topAnchor.constraint(equalTo: panelView.topAnchor),
            panelOverlayView.bottomAnchor.constraint(equalTo: panelView.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            contentStack.centerYAnchor.constraint(equalTo: panelView.centerYAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: panelView.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: panelView.bottomAnchor, constant: -20)
        ])
    }

    private func setupHeader() {
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 29
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 58),
            iconContainer.heightAnchor.constraint(equalToConstant: 58),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26)
        ])
        contentStack.addArrangedSubview(iconContainer)

        modeBadge.wantsLayer = true
        modeBadge.layer?.cornerRadius = 13
        modeBadge.translatesAutoresizingMaskIntoConstraints = false
        modeBadgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        modeBadgeLabel.alignment = .center
        modeBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeBadge.addSubview(modeBadgeLabel)
        NSLayoutConstraint.activate([
            modeBadgeLabel.leadingAnchor.constraint(equalTo: modeBadge.leadingAnchor, constant: 12),
            modeBadgeLabel.trailingAnchor.constraint(equalTo: modeBadge.trailingAnchor, constant: -12),
            modeBadgeLabel.topAnchor.constraint(equalTo: modeBadge.topAnchor, constant: 6),
            modeBadgeLabel.bottomAnchor.constraint(equalTo: modeBadge.bottomAnchor, constant: -6)
        ])
        contentStack.addArrangedSubview(modeBadge)

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        contentStack.addArrangedSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.widthAnchor.constraint(equalToConstant: 330).isActive = true
        contentStack.addArrangedSubview(subtitleLabel)

        pendingCallout.wantsLayer = true
        pendingCallout.layer?.cornerRadius = 13
        pendingCallout.translatesAutoresizingMaskIntoConstraints = false
        pendingCalloutLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        pendingCalloutLabel.alignment = .center
        pendingCalloutLabel.maximumNumberOfLines = 2
        pendingCalloutLabel.translatesAutoresizingMaskIntoConstraints = false
        pendingCallout.addSubview(pendingCalloutLabel)
        NSLayoutConstraint.activate([
            pendingCallout.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
            pendingCalloutLabel.leadingAnchor.constraint(equalTo: pendingCallout.leadingAnchor, constant: 14),
            pendingCalloutLabel.trailingAnchor.constraint(equalTo: pendingCallout.trailingAnchor, constant: -14),
            pendingCalloutLabel.topAnchor.constraint(equalTo: pendingCallout.topAnchor, constant: 9),
            pendingCalloutLabel.bottomAnchor.constraint(equalTo: pendingCallout.bottomAnchor, constant: -9)
        ])
        contentStack.addArrangedSubview(pendingCallout)
    }

    private func setupFields() {
        configureField(usernameField, in: usernameFieldContainer, placeholder: "请输入用户名")
        configureField(passwordField, in: passwordFieldContainer, placeholder: "请输入密码")
        configureField(guardField, in: guardFieldContainer, placeholder: "请输入邮件或手机 App 收到的令牌")

        configureFieldGroup(usernameGroup, title: "Steam 用户名", symbolName: "person", fieldContainer: usernameFieldContainer)
        configureFieldGroup(passwordGroup, title: "Steam 密码", symbolName: "key", fieldContainer: passwordFieldContainer)
        configureFieldGroup(guardGroup, title: "Steam Guard 令牌", symbolName: "lock.shield", fieldContainer: guardFieldContainer)

        contentStack.addArrangedSubview(usernameGroup)
        contentStack.addArrangedSubview(passwordGroup)
        contentStack.addArrangedSubview(guardGroup)
    }

    private func configureField(_ field: NSTextField, in container: NSView, placeholder: String) {
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 0.8
        container.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.alignment = .center
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 320),
            container.heightAnchor.constraint(equalToConstant: Metrics.fieldHeight),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func configureFieldGroup(
        _ group: NSStackView,
        title: String,
        symbolName: String,
        fieldContainer: NSView
    ) {
        group.orientation = .vertical
        group.alignment = .centerX
        group.distribution = .fill
        group.spacing = Metrics.fieldGroupSpacing
        group.translatesAutoresizingMaskIntoConstraints = false
        group.setHuggingPriority(.required, for: .vertical)
        group.setContentCompressionResistancePriority(.required, for: .vertical)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6
        titleRow.setHuggingPriority(.required, for: .vertical)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(label)

        group.addArrangedSubview(titleRow)
        group.addArrangedSubview(fieldContainer)
    }

    private func setupActions() {
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.distribution = .fillEqually
        actionRow.spacing = 10
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        primaryButton.target = self
        closeButton.target = self
        actionRow.addArrangedSubview(primaryButton)
        actionRow.addArrangedSubview(closeButton)
        NSLayoutConstraint.activate([
            actionRow.widthAnchor.constraint(equalToConstant: 320),
            primaryButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            closeButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height)
        ])
        contentStack.addArrangedSubview(actionRow)

        footnoteLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        footnoteLabel.textColor = .secondaryLabelColor
        footnoteLabel.alignment = .center
        footnoteLabel.maximumNumberOfLines = 3
        footnoteLabel.widthAnchor.constraint(equalToConstant: 340).isActive = true
        contentStack.addArrangedSubview(footnoteLabel)
    }

    private func observeService() {
        let publishers: [AnyPublisher<Void, Never>] = [
            service.$authPhase.map { _ in () }.eraseToAnyPublisher(),
            service.$authStatusMessage.map { _ in () }.eraseToAnyPublisher(),
            service.$isAuthenticating.map { _ in () }.eraseToAnyPublisher(),
            service.$isPreparingRuntime.map { _ in () }.eraseToAnyPublisher()
        ]
        publishers.forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.refresh() }
                .store(in: &cancellables)
        }
    }

    private func refresh() {
        let awaitingGuard = isAwaitingGuard
        iconView.image = NSImage(
            systemSymbolName: awaitingGuard ? "shield.lefthalf.filled.badge.checkmark" : "person.crop.circle.badge.plus",
            accessibilityDescription: nil
        )
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        iconView.contentTintColor = .labelColor
        modeBadgeLabel.stringValue = awaitingGuard ? "Steam Guard 验证" : "Steam 账号登录"
        titleLabel.stringValue = awaitingGuard ? "继续完成 Steam 验证" : "登录 Steam 以启用创意工坊下载"
        subtitleLabel.stringValue = service.authStatusMessage

        usernameField.stringValue = service.steamUsername
        passwordField.stringValue = service.steamPassword
        guardField.stringValue = service.steamGuardCode
        usernameGroup.isHidden = awaitingGuard
        passwordGroup.isHidden = awaitingGuard
        guardGroup.isHidden = !awaitingGuard

        // §1 规则 3：不提示"登录后自动继续下载"——未登录点击不创建待续接任务。
        pendingCallout.isHidden = true

        let primaryTitle: String
        let symbolName: String
        if awaitingGuard {
            primaryTitle = service.isAuthenticating ? "验证中…" : "验证令牌"
            symbolName = "lock.shield.fill"
        } else if service.isPreparingRuntime {
            primaryTitle = "准备中…"
            symbolName = "hourglass"
        } else {
            primaryTitle = service.isAuthenticating ? "登录中…" : "发送登录请求"
            symbolName = "arrow.right.circle.fill"
        }
        primaryButton.setTitle(primaryTitle)
        primaryButton.setSymbol(symbolName, accessibilityDescription: primaryTitle)
        primaryButton.isEnabled = awaitingGuard
            ? !service.isAuthenticating
            : !(service.isAuthenticating || service.isPreparingRuntime)

        footnoteLabel.stringValue = awaitingGuard
            ? "这里是在续接当前登录流程，不会重新提交账号密码。"
            : "已保存凭据时，下载前会先验证当前会话；只有会话失效时才会要求继续登录或输入 Guard。"
        refreshAppearance()
    }

    private var pendingDownloadTitle: String? {
        // SK4.1：待续接下载意图已随 JobStore 移除；保留占位避免旧调用点崩溃。
        nil
    }

    private func refreshAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        panelView.tintColor = isDark
            ? NSColor.black.withAlphaComponent(0.10)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.15)
        panelView.layer?.backgroundColor = (isDark
            ? NSColor.black.withAlphaComponent(0.04)
            : NSColor.windowBackgroundColor.withAlphaComponent(0.05)).cgColor

        panelOverlayView.layer?.backgroundColor = (isDark
            ? NSColor.black.withAlphaComponent(0.18)
            : NSColor.white.withAlphaComponent(0.82)).cgColor
        panelOverlayView.layer?.borderWidth = 0.8
        panelOverlayView.layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.16)).cgColor

        let controlFill = isDark
            ? NSColor.black.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.035)
        let controlStroke = isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.14)
        [iconContainer, modeBadge, pendingCallout].forEach {
            $0.layer?.backgroundColor = controlFill.cgColor
            $0.layer?.borderWidth = 0.8
            $0.layer?.borderColor = controlStroke.cgColor
        }
        [usernameFieldContainer, passwordFieldContainer, guardFieldContainer].forEach {
            $0.layer?.backgroundColor = controlFill.cgColor
            $0.layer?.borderColor = controlStroke.cgColor
        }
        [usernameField, passwordField, guardField].forEach {
            $0.backgroundColor = .clear
            $0.textColor = .labelColor
        }
        modeBadgeLabel.textColor = .labelColor
        pendingCalloutLabel.textColor = .labelColor
        titleLabel.textColor = .labelColor
        subtitleLabel.textColor = .secondaryLabelColor
    }

    @objc private func performPrimaryAction() {
        service.steamUsername = usernameField.stringValue
        service.steamPassword = passwordField.stringValue
        service.steamGuardCode = guardField.stringValue
        if isAwaitingGuard {
            service.submitSteamGuardCode()
        } else {
            service.authenticateUser()
        }
    }

    @objc private func closeLogin() {
        service.isLoginSheetPresented = false
    }
}
