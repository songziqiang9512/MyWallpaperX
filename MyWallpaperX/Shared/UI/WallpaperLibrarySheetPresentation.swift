import AppKit

/// Presentation rules only. The App supplies its real main window; drafts,
/// selection, permissions and accepted asynchronous work stay with their owners.
@MainActor enum WallpaperLibrarySheetPresentation {
    static func present(_ panel: WallpaperLibraryModalPanel, in host: NSWindow?) -> Bool {
        guard let host, host.isVisible, host.canBecomeMain || host is WallpaperLibraryModalPanel,
              host.sheetParent == nil, permitsInput(in: host), panel.parent == nil, panel.sheetParent == nil else { return false }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.setAccessibilityModal(true)
        panel.contentView?.layoutSubtreeIfNeeded()
        host.addChildWindow(panel, ordered: .above)
        panel.setFrameOrigin(NSPoint(x: host.frame.midX - panel.frame.width / 2,
                                     y: host.frame.midY - panel.frame.height / 2))
        panel.observeHost(host)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    static func permitsInput(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        guard window.attachedSheet == nil, modalChild(in: window) == nil, NSApp.modalWindow == nil else { return false }
        var branch = window
        while let parent = branch.sheetParent ?? branch.parent {
            if let active = parent.attachedSheet ?? modalChild(in: parent), active !== branch { return false }
            branch = parent
        }
        return true
    }

    static func dismiss(_ panel: NSPanel) {
        panel.close()
    }

    static func topWindow(in window: NSWindow) -> NSWindow {
        if let sheet = window.attachedSheet { return topWindow(in: sheet) }
        if let child = modalChild(in: window) { return topWindow(in: child) }
        return window
    }

    private static func modalChild(in window: NSWindow) -> WallpaperLibraryModalPanel? {
        window.childWindows?.compactMap { $0 as? WallpaperLibraryModalPanel }.first { $0.isVisible && $0.parent === window }
    }

    static func dismissNestedSheets(in window: NSWindow) {
        guard let child = window.attachedSheet else { return }
        dismissNestedSheets(in: child)
        window.endSheet(child, returnCode: .cancel)
        child.orderOut(nil)
    }
}

/// A presentation lifetime, not a business permission or authentication owner.
/// Native parent/child relationships are the only source of modal identity.
@MainActor class WallpaperLibraryModalPanel: NSPanel {
    private var inputMonitor: Any?
    private var isClosing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    fileprivate func observeHost(_ host: NSWindow) {
        NotificationCenter.default.addObserver(self, selector: #selector(hostWillClose(_:)), name: NSWindow.willCloseNotification, object: host)
        // One monitor at the outer presentation covers its native descendants.
        // Held menu/AX actions still use permitsInput at their original owner.
        guard !(host is WallpaperLibraryModalPanel) else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .mouseEntered, .mouseExited,
            .scrollWheel, .keyDown, .keyUp, .flagsChanged, .magnify, .rotate, .swipe, .pressure
        ]) { [weak self, weak host] event in
            guard let self, self.isVisible, let host, let target = event.window else { return event }
            var current: NSWindow? = target
            while let window = current {
                if window === self {
                    return WallpaperLibrarySheetPresentation.permitsInput(in: target) ? event : nil
                }
                if window === host { return nil }
                current = window.sheetParent ?? window.parent
            }
            return event
        }
    }

    @objc private func hostWillClose(_ notification: Notification) { close() }

    override func performClose(_ sender: Any?) {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: self) else { return }
        if delegate?.windowShouldClose?(self) ?? true { close() }
    }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func close() {
        // willClose calls the original controller's exact-once cleanup, which
        // can in turn request dismiss. Only that synchronous reentry is skipped.
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        WallpaperLibrarySheetPresentation.dismissNestedSheets(in: self)
        childWindows?.compactMap { $0 as? WallpaperLibraryModalPanel }.forEach { $0.close() }
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: parent)
        setAccessibilityModal(false)
        parent?.removeChildWindow(self)
        super.close()
    }
}

/// Regular native glass shared by the three panels. No image
/// observation, thumbnail demand, color sampling or transition lives here.
@MainActor class WallpaperLibrarySheetSurface: NSView {
    private let glass = NSGlassEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        glass.style = .regular
        glass.cornerRadius = 20
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor), glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshMaterial),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        refreshMaterial()
    }

    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshMaterial() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshMaterial() }

    @objc private func refreshMaterial() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        glass.isHidden = opaque
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = opaque ? NSColor.windowBackgroundColor.cgColor : nil
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
