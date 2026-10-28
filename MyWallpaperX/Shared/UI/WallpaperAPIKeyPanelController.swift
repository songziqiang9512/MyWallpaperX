import AppKit

/// One presentation per source. Storage and credential validity belong to the
/// injected service; this panel never reads back or verifies a saved secret.
@MainActor
final class WallpaperAPIKeyPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let title: String
    private let message: String
    private let helpURL: URL
    private let hasStoredKey: Bool?
    private let saveKey: @MainActor (String?) async throws -> Void
    private var panel: WallpaperLibraryModalPanel?
    private var keyField: WallpaperFormSecureField?
    private var saveButton: NSButton?
    private var removeButton: NSButton?
    private var statusLabel: NSTextField?
    private var onClose: (() -> Void)?
    private var saveTask: Task<Void, Never>?
    private var closingTask: Task<Void, Never>?

    init(title: String, message: String, helpURL: URL, hasStoredKey: Bool? = nil,
         saveKey: @escaping @MainActor (String?) async throws -> Void) {
        self.title = title
        self.message = message
        self.helpURL = helpURL
        self.hasStoredKey = hasStoredKey
        self.saveKey = saveKey
        super.init()
    }

    func present(in host: NSWindow, onClose: @escaping () -> Void) {
        if let panel {
            WallpaperLibrarySheetPresentation.topWindow(in: panel).makeKeyAndOrderFront(nil)
            return
        }
        guard closingTask == nil else { return }
        guard WallpaperLibrarySheetPresentation.permitsInput(in: host) else { onClose(); return }
        let panel = WallpaperLibraryModalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 390),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.contentView = makeContent()
        self.panel = panel
        self.onClose = onClose
        panel.initialFirstResponder = keyField
        guard WallpaperLibrarySheetPresentation.present(panel, in: host) else { close(); return }
    }

    func close() {
        guard let panel else { return }
        WallpaperLibrarySheetPresentation.dismiss(panel)
        finishClose()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return false }
        close()
        return false
    }

    func windowWillClose(_ notification: Notification) { finishClose() }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === keyField else { return }
        updateSaveAvailability()
    }

    private func makeContent() -> NSView {
        let surface = WallpaperLibrarySheetSurface()
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: surface.topAnchor, constant: 20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: surface.bottomAnchor, constant: -20)
        ])

        let icon = NSImageView(image: NSImage(systemSymbolName: "key", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 27, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "管理 API Key")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [heading, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 4
        let header = NSStackView(views: [icon, titles])
        header.alignment = .centerY
        header.spacing = 14
        content.addArrangedSubview(header)

        let cancel = NSButton(title: "", target: self, action: #selector(closeFromButton))
        cancel.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭 API Key 面板")
        cancel.isBordered = false
        cancel.keyEquivalent = "\u{1b}"
        cancel.toolTip = "关闭（Esc）"
        cancel.setAccessibilityLabel("关闭 API Key 面板")
        cancel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(cancel)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            header.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -8),
            cancel.widthAnchor.constraint(equalToConstant: 32),
            cancel.heightAnchor.constraint(equalToConstant: 32),
            cancel.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            cancel.topAnchor.constraint(equalTo: surface.topAnchor, constant: 10)
        ])

        let explanation = NSTextField(wrappingLabelWithString: message)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        addFullWidth(explanation, to: content)

        let fieldTitle = NSTextField(labelWithString: "新的 API Key")
        fieldTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        fieldTitle.textColor = .secondaryLabelColor
        let field = WallpaperFormSecureField()
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "粘贴 API Key"
        field.setAccessibilityLabel("新的 API Key")
        field.delegate = self
        field.target = self
        field.action = #selector(saveFromButton)
        let fieldSurface = WallpaperFormFieldStyle.wrapping(field, height: 40)
        let fieldGroup = NSStackView(views: [fieldTitle, fieldSurface])
        fieldGroup.orientation = .vertical
        fieldGroup.alignment = .leading
        fieldGroup.spacing = 7
        fieldSurface.widthAnchor.constraint(equalTo: fieldGroup.widthAnchor).isActive = true
        addFullWidth(fieldGroup, to: content)
        keyField = field

        let status = NSTextField(wrappingLabelWithString: initialStatus)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.maximumNumberOfLines = 3
        status.setAccessibilityElement(true)
        status.setAccessibilityRole(.staticText)
        status.setAccessibilityLabel("API Key 保存状态")
        addFullWidth(status, to: content)
        status.heightAnchor.constraint(equalToConstant: 44).isActive = true
        statusLabel = status

        let save = NSButton(title: "保存 API Key", target: self, action: #selector(saveFromButton))
        save.bezelStyle = .rounded
        save.controlSize = .large
        save.font = .systemFont(ofSize: 13, weight: .semibold)
        save.bezelColor = .controlAccentColor
        save.keyEquivalent = "\r"
        save.isEnabled = false
        addFullWidth(save, to: content)
        save.heightAnchor.constraint(equalToConstant: 38).isActive = true
        saveButton = save

        let remove = NSButton(title: "移除 API Key", target: self, action: #selector(removeFromButton))
        remove.bezelStyle = .rounded
        remove.font = .systemFont(ofSize: 12)
        remove.isEnabled = hasStoredKey != false
        remove.setAccessibilityHelp("移除当前来源已保存的 API Key，不会影响其他来源。")
        let help = NSButton(title: "获取 API Key", target: self, action: #selector(openHelp))
        help.bezelStyle = .rounded
        help.font = .systemFont(ofSize: 12)
        help.setAccessibilityHelp("在系统浏览器中打开官方 API Key 说明。")
        let actions = NSStackView(views: [remove, NSView(), help])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        addFullWidth(actions, to: content)
        removeButton = remove
        return surface
    }

    private var initialStatus: String {
        switch hasStoredKey {
        case .some(true): return "已保存 API Key，内容不会回显。留空不会更改当前设置。"
        case .some(false): return "尚未保存 API Key。输入后点击保存。"
        case nil: return "已保存的 Key 不会回显。留空不会更改当前设置。"
        }
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @objc private func closeFromButton() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        close()
    }

    @objc private func saveFromButton() {
        guard let value = keyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        save(value)
    }

    @objc private func removeFromButton() {
        guard hasStoredKey != false else { return }
        save(nil)
    }

    @objc private func openHelp() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: panel),
              helpURL.scheme == "https" || helpURL.scheme == "http" else { return }
        NSWorkspace.shared.open(helpURL)
    }

    private func save(_ value: String?) {
        guard saveTask == nil, let panel, panel.isVisible,
              WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        keyField?.isEnabled = false
        saveButton?.isEnabled = false
        removeButton?.isEnabled = false
        setStatus(value == nil ? "正在移除 API Key…" : "正在保存 API Key…")
        let saveKey = saveKey
        saveTask = Task { @MainActor [weak self, weak panel] in
            do {
                try await saveKey(value)
                guard let self else { return }
                self.saveTask = nil
                guard let panel, self.panel === panel else { return }
                self.close()
            } catch {
                guard let self else { return }
                self.saveTask = nil
                guard let panel, self.panel === panel else { return }
                self.keyField?.isEnabled = true
                self.removeButton?.isEnabled = self.hasStoredKey != false
                self.updateSaveAvailability()
                self.setStatus(error.localizedDescription, failed: true)
            }
        }
    }

    private func updateSaveAvailability() {
        saveButton?.isEnabled = saveTask == nil && !(keyField?.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func setStatus(_ text: String, failed: Bool = false) {
        statusLabel?.stringValue = text
        statusLabel?.toolTip = text
        statusLabel?.textColor = failed ? .systemRed : .secondaryLabelColor
        if let statusLabel, panel?.isVisible == true {
            NSAccessibility.post(element: statusLabel, notification: .valueChanged)
        }
    }

    private func finishClose() {
        guard let panel else { return }
        let completion = onClose
        onClose = nil
        panel.delegate = nil
        panel.endEditing(for: nil)
        keyField?.stringValue = ""
        keyField?.delegate = nil
        keyField = nil
        saveButton = nil
        removeButton = nil
        statusLabel = nil
        panel.contentView = nil
        self.panel = nil
        // Closing discards the editor, not a storage operation already accepted
        // by the service. Notify the owner after that operation has settled.
        if let saveTask {
            closingTask = Task { @MainActor [weak self] in
                await saveTask.value
                self?.closingTask = nil
                completion?()
            }
        } else { completion?() }
    }
}
