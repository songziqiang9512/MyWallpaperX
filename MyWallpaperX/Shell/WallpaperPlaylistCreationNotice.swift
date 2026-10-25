import AppKit

/// A native, dismissible success receipt. Navigation remains an injected command;
/// dismissing the popover never changes the page or selection.
@MainActor final class WallpaperPlaylistCreationNotice: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var openButton: NSButton?
    private var closeButton: NSButton?
    private var openAction: (() -> Void)?

    func show(name: String, in window: NSWindow, open: @escaping () -> Void) {
        dismiss()
        guard window.isVisible, !window.isMiniaturized, let anchor = window.contentView else { return }
        let controller = NSViewController()
        let content = NSView()
        controller.view = content
        let label = NSTextField(wrappingLabelWithString: "已创建“\(name)”")
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = label.stringValue
        label.setAccessibilityLabel(label.stringValue)
        let openButton = NSButton(title: "打开列表", target: self, action: #selector(openPlaylist(_:)))
        openButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeNotice(_:)))
        closeButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [openButton, closeButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [label, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            content.widthAnchor.constraint(equalToConstant: min(340, max(220, anchor.bounds.width - 32)))
        ])
        content.layoutSubtreeIfNeeded()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: content.fittingSize.width, height: content.fittingSize.height)
        popover.delegate = self
        self.popover = popover
        self.openButton = openButton
        self.closeButton = closeButton
        self.openAction = open
        let rect = NSRect(x: max(0, anchor.bounds.maxX - 44),
                          y: anchor.isFlipped ? 8 : max(0, anchor.bounds.maxY - 8), width: 1, height: 1)
        popover.show(relativeTo: rect, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }

    func dismiss() {
        let previous = popover
        popover = nil
        openButton = nil
        closeButton = nil
        openAction = nil
        previous?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        popover = nil
        openButton = nil
        closeButton = nil
        openAction = nil
    }

    @objc private func openPlaylist(_ sender: NSButton) {
        guard sender === openButton, popover?.isShown == true else { return }
        let action = openAction
        dismiss()
        action?()
    }

    @objc private func closeNotice(_ sender: NSButton) {
        guard sender === closeButton else { return }
        dismiss()
    }
}
