import AppKit
import CoreImage

/// Presentation only. Authentication attempts and credentials remain owned by
/// SteamLoginPanelController and SteamAuthRoute.
@MainActor
final class SteamLoginPanelView: WallpaperPanelSurface, NSTextFieldDelegate {
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

    let modeSegment = NSSegmentedControl(labels: [String(localized: "QR Code Login"), String(localized: "Account & Password")], trackingMode: .selectOne, target: nil, action: nil)
    let qrImageView = SteamLoginQRCodeImageView()
    let refreshQRButton = NSButton(title: String(localized: "Refresh QR Code"), target: nil, action: nil)
    let zoomQRButton = NSButton(title: String(localized: "Enlarge"), target: nil, action: nil)
    let usernameField = WallpaperFormTextField()
    let passwordField = WallpaperFormSecureField()
    private let revealedPasswordField = WallpaperFormTextField()
    private let revealButton = NSButton(title: "", target: nil, action: nil)
    let codeField = WallpaperFormTextField()
    let rememberCheck = NSButton(checkboxWithTitle: String(localized: "Remember sign-in and restore it next time"), target: nil, action: nil)
    let loginButton = NSButton(title: String(localized: "Sign In to Steam"), target: nil, action: nil)
    let guardSubmitButton = NSButton(title: String(localized: "Submit Verification Code"), target: nil, action: nil)
    let cancelButton = WallpaperPanelCloseButton()
    let doneButton = NSButton(title: String(localized: "Done"), target: nil, action: nil)
    private let submitArea = NSStackView()
    private let qrActions = NSStackView()
    private let qrFailureLabel = NSTextField(wrappingLabelWithString: String(localized: "QR code expired\nGenerate a new one"))
    let statusLabel = NSTextField(wrappingLabelWithString: "")

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

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    private func setup() {
        configureStack(content, spacing: 12)
        content.alignment = .centerX
        bodyView.addSubview(content)
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
        let title = NSTextField(labelWithString: String(localized: "Sign In to Steam"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: String(localized: "Connect Your Workshop"))
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        titles.addArrangedSubview(title)
        titles.addArrangedSubview(subtitle)
        heading.addArrangedSubview(icon)
        heading.addArrangedSubview(titles)
        content.addArrangedSubview(heading)
        modeSegment.segmentStyle = .rounded
        modeSegment.controlSize = .large
        modeSegment.setAccessibilityLabel(String(localized: "Steam Sign-In Method"))
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
        rememberCheck.toolTip = String(localized: "Only the sign-in token is stored in the macOS keychain, never your password.")
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
        statusLabel.setAccessibilityLabel(String(localized: "Steam Sign-In Status"))
        addFullWidth(statusLabel, to: content)
        statusLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close Sign-In"))
        cancelButton.toolTip = String(localized: "Close and Cancel Sign-In (Esc)")
        cancelButton.setAccessibilityLabel(String(localized: "Close Sign-In"))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        bodyView.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cancelButton.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
        showPage(.qr)
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
        let hint = NSTextField(wrappingLabelWithString: String(localized: "Open the Steam mobile app, scan the code, and confirm the sign-in"))
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
        addFullWidth(fieldGroup(usernameField, title: String(localized: "Steam Account"), placeholder: String(localized: "Enter Account Name"), symbol: "person"), to: passwordPage)
        addFullWidth(fieldGroup(passwordField, title: String(localized: "Password"), placeholder: String(localized: "Enter Steam Password"), symbol: "key"), to: passwordPage)
        if let surface = passwordField.superview {
            // Both editors occupy the same bounds; the secure editor owns the submitted value.
            WallpaperFormFieldStyle.configure(revealedPasswordField)
            revealedPasswordField.font = passwordField.font
            revealedPasswordField.placeholderString = passwordField.placeholderString
            revealedPasswordField.setAccessibilityLabel(String(localized: "Password (Visible)"))
            revealedPasswordField.isHidden = true
            revealedPasswordField.delegate = self
            passwordField.delegate = self
            revealedPasswordField.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(revealedPasswordField)
            revealButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: String(localized: "Show Password"))
            revealButton.isBordered = false
            revealButton.target = self
            revealButton.action = #selector(togglePasswordVisibility)
            revealButton.toolTip = String(localized: "Show Password")
            revealButton.setAccessibilityLabel(String(localized: "Show Password"))
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
        revealButton.toolTip = String(localized: "Show Password")
        revealButton.setAccessibilityLabel(String(localized: "Show Password"))
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
            revealButton.toolTip = String(localized: "Hide Password")
            revealButton.setAccessibilityLabel(String(localized: "Hide Password"))
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
        codeGroup = fieldGroup(codeField, title: String(localized: "Steam Guard Code"), placeholder: String(localized: "Enter Verification Code"), symbol: "lock.shield")
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
                guardHint.stringValue = String(localized: "Confirm this sign-in request\nin the Steam mobile app.")
            case .deviceCode:
                needsCode = true
                guardHint.stringValue = String(localized: "Enter the current code shown in the Steam mobile authenticator.")
            case .emailCode(let domain, _):
                needsCode = true
                let addressText = domain ?? String(localized: "your email")
                guardHint.stringValue = String(localized: "Enter the code sent to \(addressText) as the verification code.")
            }
            codeGroup.isHidden = !needsCode
            guardSubmitButton.isHidden = !needsCode

        case .completed:
            guardPage.isHidden = false
            guardHint.stringValue = String(localized: "Signed in to Steam\nThis sign-in couldn’t be saved; you’ll need to sign in again next time.")
            codeGroup.isHidden = true
            modeSegment.isHidden = true
            rememberCheck.isHidden = true
            doneButton.isHidden = false
        }
    }

    func setQRImage(_ image: NSImage?) {
        qrFailureLabel.isHidden = true
        refreshQRButton.title = String(localized: "Refresh QR Code")
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
        refreshQRButton.title = String(localized: "Regenerate")
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
        let surface = WallpaperFormFieldSurface()
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 14)
        WallpaperFormFieldStyle.configure(field)
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
        WallpaperLibraryControlStyle.sheetCapsule(button)
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
