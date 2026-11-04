import AppKit
import Combine

/// Native controls only; the task presentation retains its leases across reuse.
@MainActor final class DownloadTaskRowView: NSView {
    private static let placeholder = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = NSLevelIndicator()
    private let actionsStack = NSStackView()
    private var buttons: [DownloadTaskAction: NSButton] = [:]
    private var presentation: DownloadTaskRowPresentation?
    private var presentationSubscription: AnyCancellable?
    var displayedTask: DownloadTaskRow? { presentation?.row }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.16).cgColor
        thumbnailView.image = Self.placeholder
        thumbnailView.contentTintColor = .tertiaryLabelColor
        thumbnailView.setAccessibilityElement(false)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.levelIndicatorStyle = .continuousCapacity
        progressBar.fillColor = .controlAccentColor
        progressBar.warningValue = 2
        progressBar.criticalValue = 2
        progressBar.drawsTieredCapacityLevels = false
        progressBar.controlSize = .small
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.setAccessibilityElement(true)
        progressBar.setAccessibilityRole(.progressIndicator)
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .centerY
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        for child in [thumbnailView, titleLabel, statusLabel, progressBar, actionsStack] { addSubview(child) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 76),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: DownloadTaskRowPresentation.thumbnailSide),
            thumbnailView.heightAnchor.constraint(equalToConstant: DownloadTaskRowPresentation.thumbnailSide),
            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            progressBar.trailingAnchor.constraint(equalTo: actionsStack.leadingAnchor, constant: -8),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 5),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    convenience init(bindings: DownloadTaskRowPresentation.Bindings) {
        self.init(frame: .zero)
        bind(DownloadTaskRowPresentation(bindings: bindings))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(_ next: DownloadTaskRow) {
        presentation?.configure(next, request: window.flatMap { DownloadTaskRowPresentation.thumbnailRequest(for: $0) })
    }

    func bind(_ presentation: DownloadTaskRowPresentation?) {
        presentationSubscription = nil
        self.presentation = presentation
        guard let presentation else { clearContent(); return }
        presentationSubscription = presentation.changes.sink { [weak self] change in
            guard let self else { return }
            switch change {
            case .content: self.renderContent(); self.prepareThumbnail()
            case .progress: self.renderStatus()
            case .thumbnail: self.renderThumbnail()
            }
        }
        renderContent()
        prepareThumbnail()
    }

    private func renderContent() {
        guard let row = presentation?.row else { clearContent(); return }
        titleLabel.stringValue = row.title
        progressBar.setAccessibilityLabel("下载进度：\(row.title)")
        for action in DownloadTaskAction.allCases where row.actions.contains(action) { _ = button(for: action) }
        for (action, button) in buttons {
            button.isHidden = !row.actions.contains(action)
            button.isEnabled = row.actions.contains(action)
            button.toolTip = Self.title(action)
            button.setAccessibilityLabel("\(Self.title(action))：\(row.title)")
        }
        renderStatus()
        renderThumbnail()
    }

    private func clearContent() {
        titleLabel.stringValue = ""
        statusLabel.stringValue = ""
        statusLabel.toolTip = nil
        statusLabel.textColor = .secondaryLabelColor
        progressBar.isHidden = true
        progressBar.doubleValue = 0
        progressBar.setAccessibilityLabel("")
        progressBar.setAccessibilityValue("")
        thumbnailView.image = Self.placeholder
        for button in buttons.values { button.isHidden = true; button.isEnabled = false }
    }

    private func renderThumbnail() {
        thumbnailView.image = presentation?.image ?? Self.placeholder
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { prepareThumbnail() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        prepareThumbnail()
    }

    private func prepareThumbnail() {
        guard let presentation, let window,
              let request = DownloadTaskRowPresentation.thumbnailRequest(for: window) else { return }
        presentation.prepareThumbnail(request)
    }

    private func button(for action: DownloadTaskAction) -> NSButton {
        if let existing = buttons[action] { return existing }
        let button = NSButton(title: Self.title(action), target: self, action: #selector(invoke(_:)))
        button.controlSize = .small
        button.bezelStyle = .rounded
        if [.cancel, .removeHistory].contains(action) {
            button.title = ""
            button.isBordered = false
            button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: Self.title(action))?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
            button.contentTintColor = .secondaryLabelColor
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        } else if action == .revealFile {
            button.title = ""
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: Self.title(action))
        }
        let preceding = DownloadTaskAction.allCases.prefix { $0 != action }.filter { buttons[$0] != nil }.count
        buttons[action] = button
        actionsStack.insertArrangedSubview(button, at: preceding)
        return button
    }

    func unbind() {
        presentation?.unbind()
    }

    private func renderStatus() {
        guard let status = presentation?.status else { return }
        statusLabel.stringValue = status.text
        statusLabel.toolTip = status.text
        statusLabel.textColor = status.phase == .failed ? .systemRed : .secondaryLabelColor
        progressBar.isHidden = status.fraction == nil
        progressBar.doubleValue = status.fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
        progressBar.setAccessibilityValue(status.text)
    }

    @objc private func invoke(_ sender: NSButton) {
        guard let action = buttons.first(where: { $0.value === sender })?.key else { return }
        presentation?.perform(action)
    }

    private static func title(_ action: DownloadTaskAction) -> String {
        switch action {
        case .promote: return "优先下载"
        case .pause: return "暂停"
        case .resume: return "继续"
        case .retry: return "重试"
        case .revealFile: return "在访达中显示"
        case .cancel: return "取消下载"
        case .removeHistory: return "清除记录"
        }
    }
}
