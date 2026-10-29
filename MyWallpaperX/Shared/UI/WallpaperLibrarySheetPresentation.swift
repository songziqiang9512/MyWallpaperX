import AppKit

/// Presentation rules only. AppKit owns the sheet's modal input and backdrop;
/// drafts, accepted asynchronous work and source permissions stay with their owners.
@MainActor enum WallpaperLibrarySheetPresentation {
    static func present(_ panel: WallpaperLibraryModalPanel, in host: NSWindow?) -> Bool {
        guard let host, host.isVisible, host.canBecomeMain || host is WallpaperLibraryModalPanel,
              permitsInput(in: host), panel.parent == nil, panel.sheetParent == nil else { return false }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.setAccessibilityModal(true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.observeHost(host)
        host.beginSheet(panel)
        return true
    }

    static func permitsInput(in window: NSWindow?) -> Bool {
        guard let window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        var branch = window
        while let parent = branch.sheetParent ?? branch.parent {
            if let active = parent.attachedSheet, active !== branch { return false }
            branch = parent
        }
        return true
    }

    static func dismiss(_ panel: NSPanel) { panel.close() }

    static func topWindow(in window: NSWindow) -> NSWindow {
        if let sheet = window.attachedSheet { return topWindow(in: sheet) }
        return window
    }

    static func dismissNestedSheets(in window: NSWindow) {
        guard let sheet = window.attachedSheet else { return }
        if let panel = sheet as? WallpaperLibraryModalPanel {
            panel.close()
        } else {
            dismissNestedSheets(in: sheet)
            window.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
    }
}

/// Owns the lifetime of one native sheet, without a second input monitor.
@MainActor class WallpaperLibraryModalPanel: NSPanel {
    private var isClosing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    fileprivate func observeHost(_ host: NSWindow) {
        NotificationCenter.default.addObserver(self, selector: #selector(hostWillClose(_:)), name: NSWindow.willCloseNotification, object: host)
    }

    @objc private func hostWillClose(_ notification: Notification) { close() }

    override func performClose(_ sender: Any?) {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: self) else { return }
        if delegate?.windowShouldClose?(self) ?? true { close() }
    }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func close() {
        // Controller cleanup may synchronously dismiss this same sheet again.
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        let host = sheetParent
        WallpaperLibrarySheetPresentation.dismissNestedSheets(in: self)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: host)
        setAccessibilityModal(false)
        host?.endSheet(self, returnCode: .cancel)
        super.close()
    }
}

/// Native glass owns the shape; the presenting owner controls window transparency and shadow.
@MainActor class WallpaperPanelSurface: NSGlassEffectView {
    let bodyView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cornerRadius = 20
        setup()
    }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        self.cornerRadius = cornerRadius
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        style = .regular
        bodyView.wantsLayer = true
        contentView = bodyView
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshMaterial),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        refreshMaterial()
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshMaterial() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshMaterial() }

    @objc private func refreshMaterial() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            tintColor = dark ? .black.withAlphaComponent(0.10) : .controlBackgroundColor.withAlphaComponent(0.15)
            bodyView.layer?.backgroundColor = (opaque ? NSColor.windowBackgroundColor
                : (dark ? NSColor.black.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.82))).cgColor
        }
    }
}
