import AppKit

/// Layout for the caller's NSAlert value. The original caller keeps the
/// business decision, accessory controls and exact response/completion contract.
@MainActor final class AppCenteredAlertPresentation: NSObject, NSWindowDelegate {
    private let alert: NSAlert
    private let panel = CenteredAlertPanel(contentRect: NSRect(x: 0, y: 0, width: 368, height: 280),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private var completion: ((NSApplication.ModalResponse) -> Void)?
    private var hasFinished = false
    private var isResponding = false
    private var isAppModal = false
    private var cancelResponse = NSApplication.ModalResponse.alertFirstButtonReturn
    private var buttonResponses: [ObjectIdentifier: NSApplication.ModalResponse] = [:]
    private weak var presentingHost: NSWindow?
    var window: NSWindow { panel }

    init(alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)?) {
        self.alert = alert; self.completion = completion
        super.init()
        configure()
    }

    func beginSheet(in host: NSWindow) {
        presentingHost = host
        NotificationCenter.default.addObserver(self, selector: #selector(hostWillClose(_:)), name: NSWindow.willCloseNotification, object: host)
        // AppKit retains this completion until the real native sheet ends.
        host.beginSheet(panel) { [self] response in finish(response) }
    }

    func runModal() -> NSApplication.ModalResponse {
        isAppModal = true
        panel.center()
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        finish(response)
        return response
    }

    private func configure() {
        panel.delegate = self
        panel.onCancel = { [weak self] in guard let self else { return }; self.respond(self.cancelResponse) }
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.setAccessibilityLabel(alert.messageText)
        let root = NSView()
        panel.contentView = root
        let contentWidth = max(320, min(520, alert.accessoryView.map { max($0.frame.width, $0.fittingSize.width) } ?? 0))
        let body = NSStackView()
        body.orientation = .vertical; body.alignment = .centerX; body.spacing = 14
        body.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            body.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        let icon = CenteredAlertIcon()
        icon.image = alert.icon ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)])
        body.addArrangedSubview(icon)
        let title = NSTextField(wrappingLabelWithString: alert.messageText)
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center; title.maximumNumberOfLines = 3
        title.preferredMaxLayoutWidth = contentWidth
        title.toolTip = alert.messageText
        body.addArrangedSubview(title)
        title.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        if !alert.informativeText.isEmpty { body.addArrangedSubview(messageView(width: contentWidth)) }
        if let accessory = alert.accessoryView { body.addArrangedSubview(accessoryHost(accessory, width: contentWidth)) }
        if alert.showsSuppressionButton, let suppression = alert.suppressionButton {
            body.addArrangedSubview(accessoryHost(suppression, width: contentWidth))
        }
        let responseButtons = alert.buttons.isEmpty ? [alert.addButton(withTitle: "确定")] : alert.buttons
        // AppKit assigns Escape to English "Cancel"; this App's existing
        // Chinese cancellation labels do not receive that key automatically.
        // Keep every caller key unchanged and never infer cancellation from
        // the second position: it can be a download or deletion action.
        let cancelIndex = responseButtons.firstIndex { $0.keyEquivalent == "\u{1b}" }
            ?? responseButtons.firstIndex { $0.title == "取消" }
        cancelResponse = cancelIndex.map {
            NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + $0)
        } ?? (responseButtons.count == 1 ? .alertFirstButtonReturn : .cancel)
        let footer = NSStackView()
        footer.orientation = .horizontal; footer.spacing = 12
        if alert.showsHelp {
            let help = NSButton(title: "", target: self, action: #selector(showHelp(_:)))
            help.bezelStyle = .helpButton; help.setAccessibilityLabel("帮助")
            footer.addArrangedSubview(help)
        }
        for (index, button) in responseButtons.enumerated().reversed() {
            let response = NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)
            buttonResponses[ObjectIdentifier(button)] = response
            button.target = self; button.action = #selector(chooseResponse(_:))
            if index == 0 {
                if button.keyEquivalent.isEmpty { button.keyEquivalent = "\r" }
                panel.defaultButtonCell = button.cell as? NSButtonCell
            }
            footer.addArrangedSubview(button)
        }
        if footer.fittingSize.width > contentWidth { footer.orientation = .vertical; footer.alignment = .centerX }
        body.addArrangedSubview(footer)
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: contentWidth + 48, height: body.fittingSize.height + 44))
        body.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24).isActive = true
        panel.initialFirstResponder = alert.accessoryView as? NSControl ?? responseButtons.first
        root.layoutSubtreeIfNeeded()
    }

    private func messageView(width: CGFloat) -> NSView {
        let message = NSTextView()
        message.isEditable = false; message.isSelectable = true
        message.isRichText = false; message.drawsBackground = false
        message.font = .systemFont(ofSize: 13); message.textColor = .labelColor
        message.alignment = .center; message.string = alert.informativeText
        message.textContainerInset = .zero
        message.textContainer?.lineFragmentPadding = 0
        message.textContainer?.widthTracksTextView = true
        message.isHorizontallyResizable = false; message.isVerticallyResizable = true
        message.autoresizingMask = [.width]
        let measured = (alert.informativeText as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)]).height
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = message
        message.frame = NSRect(x: 0, y: 0, width: width, height: max(22, ceil(measured)))
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: width),
            scroll.heightAnchor.constraint(equalToConstant: min(160, max(22, ceil(measured))))])
        return scroll
    }

    private func accessoryHost(_ accessory: NSView, width: CGFloat) -> NSView {
        let wrapper = NSView()
        let size = accessory.fittingSize
        let height = max(24, max(accessory.frame.height, size.height))
        accessory.removeFromSuperview()
        accessory.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(accessory)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: width), wrapper.heightAnchor.constraint(equalToConstant: height),
            accessory.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor), accessory.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            accessory.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor),
            accessory.heightAnchor.constraint(equalToConstant: height)
        ])
        if size.width <= 0 { accessory.widthAnchor.constraint(equalToConstant: min(width, accessory.frame.width)).isActive = true }
        return wrapper
    }

    @objc private func chooseResponse(_ sender: NSButton) {
        guard let response = buttonResponses[ObjectIdentifier(sender)], sender.isEnabled else { return }
        respond(response)
    }
    @objc private func showHelp(_ sender: Any?) {
        if alert.delegate?.alertShowHelp?(alert) == true { return }
        if let anchor = alert.helpAnchor { NSHelpManager.shared.openHelpAnchor(anchor, inBook: nil) }
    }
    private func respond(_ response: NSApplication.ModalResponse) {
        guard panel.attachedSheet == nil, !hasFinished, !isResponding else { return }
        isResponding = true
        if let host = panel.sheetParent { host.endSheet(panel, returnCode: response); panel.orderOut(nil) }
        else if isAppModal { NSApp.stopModal(withCode: response) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { respond(cancelResponse); return false }
    @objc private func hostWillClose(_ notification: Notification) {
        guard !hasFinished else { return }
        if let host = presentingHost, panel.sheetParent === host {
            host.endSheet(panel, returnCode: .cancel)
        }
        panel.orderOut(nil)
        finish(.cancel)
    }
    private func finish(_ response: NSApplication.ModalResponse) {
        guard !hasFinished else { return }
        hasFinished = true
        panel.orderOut(nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: presentingHost)
        presentingHost = nil
        let callback = completion; completion = nil
        callback?(response)
    }
}

private final class CenteredAlertIcon: NSImageView {
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
}

private final class CenteredAlertPanel: NSPanel {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
