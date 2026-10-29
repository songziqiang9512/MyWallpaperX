import AppKit

/// One transient grid notice. Re-rendering the same source message does not
/// restart its lifetime; source commands remain with the caller.
@MainActor final class WallpaperGridNoticeView: NSGlassEffectView {
    private let row = NSStackView()
    private let labels = NSStackView()
    private let buttons = NSStackView()
    private let closeButton = NSButton()
    private var shownMessages: [String] = []
    private var actionTitles: [String] = []
    private var event: UInt64 = 0
    private var centerConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var commands: [() -> Void] = []
    private var onDismiss: (() -> Void)?
    private var dismissal: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        style = .regular
        cornerRadius = 24
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        buttons.spacing = 8
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭提示")
        closeButton.bezelStyle = .inline
        closeButton.target = self
        closeButton.action = #selector(closeNotice)
        closeButton.toolTip = "关闭"
        row.addArrangedSubview(labels)
        row.addArrangedSubview(buttons)
        row.addArrangedSubview(closeButton)
        let content = NSView()
        content.addSubview(row)
        contentView = content
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    isolated deinit { dismissal?.cancel() }

    func attach(to host: NSView) {
        host.addSubview(self)
        centerConstraint = centerXAnchor.constraint(equalTo: host.centerXAnchor)
        trailingConstraint = trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -24)
        NSLayoutConstraint.activate([
            centerConstraint!, trailingConstraint!,
            bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 24),
            widthAnchor.constraint(lessThanOrEqualToConstant: 600)
        ])
    }

    func setTrailingOcclusion(_ width: CGFloat) {
        centerConstraint?.constant = -width / 2
        trailingConstraint?.constant = -24 - width
    }

    func update(messages: [String], actions: [(String, () -> Void)] = [], showsClose: Bool = false,
                event: UInt64 = 0, onDismiss: (() -> Void)? = nil) {
        let messages = messages.filter { !$0.isEmpty }
        commands = actions.map(\.1)
        self.onDismiss = onDismiss
        closeButton.isHidden = !showsClose
        let titles = actions.map(\.0)
        guard messages != shownMessages || titles != actionTitles || event != self.event else { return }
        self.event = event
        shownMessages = messages
        actionTitles = titles
        labels.arrangedSubviews.forEach { labels.removeArrangedSubview($0); $0.removeFromSuperview() }
        for message in messages {
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = message
            label.setAccessibilityLabel(message)
            labels.addArrangedSubview(label)
        }
        buttons.arrangedSubviews.forEach { buttons.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.0, target: self, action: #selector(invoke(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            buttons.addArrangedSubview(button)
        }
        isHidden = messages.isEmpty && actions.isEmpty
        dismissal?.cancel()
        if !isHidden { scheduleDismissal(after: 5) }
    }

    func clear(message: String) {
        guard shownMessages.first == message else { return }
        update(messages: [])
    }

    func permitsInteraction(at windowPoint: NSPoint) -> Bool {
        guard window?.isVisible == true, !isHiddenOrHasHiddenAncestor else { return false }
        return (buttons.arrangedSubviews + [closeButton]).contains { child in
            guard let button = child as? NSButton, button.isEnabled, !button.isHiddenOrHasHiddenAncestor else { return false }
            return button.bounds.intersection(button.visibleRect).contains(button.convert(windowPoint, from: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) { dismissal?.cancel() }
    override func mouseExited(with event: NSEvent) { if !isHidden { scheduleDismissal(after: 1.5) } }

    private func scheduleDismissal(after seconds: Double) {
        dismissal?.cancel()
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.closeNotice()
        }
    }
    @objc private func closeNotice() {
        dismissal?.cancel(); dismissal = nil
        isHidden = true
        let finished = onDismiss
        onDismiss = nil
        finished?()
    }
    @objc private func invoke(_ button: NSButton) {
        guard window?.isVisible == true, !isHiddenOrHasHiddenAncestor, button.isEnabled,
              buttons.arrangedSubviews.contains(where: { $0 === button }), commands.indices.contains(button.tag) else { return }
        commands[button.tag]()
    }
}
