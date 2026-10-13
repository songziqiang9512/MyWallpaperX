import AppKit

/// Retains the existing Scene entry point; all property windows share one glass host.
@MainActor
final class ScenePropertyWindowController {
    static let shared = ScenePropertyWindowController()
    func show(record: SteamWorkshopDownloadRecord, context: SteamWorkshopScenePropertyContext) {
        let editor = SteamWorkshopScenePropertyEditorView(record: record, context: context)
        SteamWorkshopPropertyPanelController.shared.show(title: "Scene 属性调节", subtitle: record.title, content: editor)
    }
}

@MainActor
final class SteamWorkshopPropertyPanelController: NSWindowController, NSWindowDelegate {
    static let shared = SteamWorkshopPropertyPanelController()
    private let card = InspectorHostCardView()
    private(set) var presentationID: UUID?
    private var retainedController: AnyObject?
    private var cardHeightConstraint: NSLayoutConstraint?

    private init() {
        let panel = PropertyPanel(contentRect: NSRect(x: 0, y: 0, width: InspectorHostRequest.defaultPreferredWidth, height: 620), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: InspectorHostRequest.defaultPreferredWidth, height: 620)
        panel.maxSize = panel.minSize
        card.drawsShadow = false
        card.stretchesHostedContent = true
        // Clip the window's backing surface as well as the inner glass. The
        // shadow belongs to NSWindow and is not clipped by this content layer.
        card.layer?.masksToBounds = true
        panel.contentView = card
        card.widthAnchor.constraint(equalToConstant: InspectorHostRequest.defaultPreferredWidth).isActive = true
        cardHeightConstraint = card.heightAnchor.constraint(equalToConstant: 620)
        cardHeightConstraint?.isActive = true
        card.compactHeader = true
        super.init(window: panel)
        panel.delegate = self
        card.onClose = { [weak self] in self?.close() }
    }
    required init?(coder: NSCoder) { nil }
    @discardableResult
    func show(title: String, subtitle: String, content: NSView, retaining controller: AnyObject? = nil) -> UUID {
        let id = UUID()
        presentationID = id
        retainedController = controller
        (window as? PropertyPanel)?.keyTraversal = content as? WorkshopPropertyKeyTraversal
        let body = NSStackView()
        body.orientation = .vertical
        body.distribution = .fill
        body.alignment = .leading
        body.spacing = 6
        let itemTitle = NSTextField(wrappingLabelWithString: subtitle)
        itemTitle.alignment = .center
        itemTitle.font = .systemFont(ofSize: 12)
        itemTitle.textColor = .secondaryLabelColor
        itemTitle.maximumNumberOfLines = 2
        itemTitle.setContentHuggingPriority(.required, for: .vertical)
        itemTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        body.addArrangedSubview(itemTitle)
        body.addArrangedSubview(content)
        for child in [itemTitle, content] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        card.headerTitleOverride = title
        card.configure(request: InspectorHostRequest(token: InspectorCardToken(module: .steamWorkshop, cardID: "properties"), title: title, subtitle: subtitle, chromeStyle: .infoPanel), hostedContentView: body)
        guard let window else { return id }
        window.title = title
        if !window.isVisible {
            let main = NSApp.windows.first { $0.identifier?.rawValue == "MainWindow" }
            func inspector(in view: NSView) -> InspectorHostCardView? {
                if let card = view as? InspectorHostCardView, !card.isHidden { return card }
                return view.subviews.lazy.compactMap { inspector(in: $0) }.first
            }
            if let main, let root = main.contentView, let detail = inspector(in: root) {
                let frame = main.convertToScreen(detail.convert(detail.bounds, to: nil))
                let size = frame.size
                cardHeightConstraint?.constant = size.height
                window.minSize = size
                window.maxSize = size
                let screen = main.screen?.visibleFrame ?? frame
                let origin = NSPoint(x: max(screen.minX, frame.minX - size.width - 12),
                                     y: max(screen.minY, min(frame.minY, screen.maxY - size.height)))
                window.setFrame(NSRect(origin: origin, size: size), display: true)
            } else {
                window.center()
            }
        }
        window.makeKeyAndOrderFront(nil)
        return id
    }
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        card.configure(request: nil, hostedContentView: nil)
        retainedController = nil
        presentationID = nil
        (window as? PropertyPanel)?.keyTraversal = nil
    }
    private final class PropertyPanel: NSPanel {
        weak var keyTraversal: WorkshopPropertyKeyTraversal?
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { close() }
        override func selectNextKeyView(_ sender: Any?) {
            if keyTraversal?.focusNextPropertyControl(from: firstResponder, reverse: false) != true {
                super.selectNextKeyView(sender)
            }
        }
        override func selectPreviousKeyView(_ sender: Any?) {
            if keyTraversal?.focusNextPropertyControl(from: firstResponder, reverse: true) != true {
                super.selectPreviousKeyView(sender)
            }
        }
    }
}
