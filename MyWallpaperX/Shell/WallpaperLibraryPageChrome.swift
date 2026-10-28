import AppKit

/// Standard native labels and buttons around the content. No media, query or
/// relationship owner lives here; every action is an injected fixed command.
final class WallpaperLibraryPageChrome: NSViewController {
    let content: NSViewController
    private let notice = WallpaperGridNoticeView()
    private let empty = WallpaperLibraryEmptyStackView()
    private let emptyIcon = NSImageView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let actions = NSStackView()
    private var handlers: [() -> Void] = []

    init(content: NSViewController) { self.content = content; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        addChild(content)
        let child = content.view
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        empty.orientation = .vertical
        empty.alignment = .centerX
        empty.spacing = 14
        empty.translatesAutoresizingMaskIntoConstraints = false
        emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyIcon.imageScaling = .scaleProportionallyUpOrDown
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        actions.spacing = 12
        empty.addArrangedSubview(emptyIcon)
        empty.addArrangedSubview(emptyLabel)
        empty.addArrangedSubview(actions)
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: view.topAnchor),
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor), child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: child.safeAreaLayoutGuide.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: child.safeAreaLayoutGuide.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualTo: child.safeAreaLayoutGuide.widthAnchor, constant: -48),
            emptyIcon.widthAnchor.constraint(equalToConstant: 44), emptyIcon.heightAnchor.constraint(equalToConstant: 44)
        ])
        notice.attach(to: view)
    }

    func update(notices messages: [String], empty message: String?, symbol: String = "photo.on.rectangle",
                noticeActions noticeCommands: [(String, () -> Void)] = [], actions commands: [(String, () -> Void)] = [], errorEvent: UInt64 = 0) {
        loadViewIfNeeded()
        notice.update(messages: messages, actions: noticeCommands, event: errorEvent)
        empty.isHidden = message == nil
        emptyLabel.stringValue = message ?? ""
        emptyIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        handlers = commands.map(\.1)
        replaceButtons(in: actions, commands: commands, action: #selector(invoke(_:)))
    }

    private func replaceButtons(in stack: NSStackView, commands: [(String, () -> Void)], action: Selector) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, command) in commands.enumerated() {
            let button = NSButton(title: command.0, target: self, action: action)
            button.bezelStyle = .rounded
            button.tag = index
            stack.addArrangedSubview(button)
        }
    }

    func setNoticeTrailingOcclusion(_ width: CGFloat) { notice.setTrailingOcclusion(width) }

    /// Only the current enabled notice controls may cross the Inspector's
    /// dimming surface. Content, empty-state actions and removed controls do not.
    func permitsNoticeInteraction(at windowPoint: NSPoint) -> Bool {
        notice.permitsInteraction(at: windowPoint)
    }

    @objc private func invoke(_ sender: NSButton) {
        guard view.window?.isVisible == true, !view.isHiddenOrHasHiddenAncestor, sender.isEnabled,
              !empty.isHidden, actions.arrangedSubviews.contains(where: { $0 === sender }), handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }

}

private final class WallpaperLibraryEmptyStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var current: NSView? = hit
        while let candidate = current, candidate !== self {
            if candidate is NSButton { return hit }
            current = candidate.superview
        }
        return nil
    }
}

final class WallpaperPlaylistHeaderView: NSView {
    private let cover = WallpaperPlaylistHeaderCoverView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let titleRow = NSStackView()
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let text = NSStackView()
    private let buttons = NSStackView()
    private let content = NSStackView()
    private var actions: [() -> Void] = []
    private var coverWidth: NSLayoutConstraint!
    private static let verticalInset: CGFloat = 16
    private static let imageTextSpacing: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.cornerRadius = 12
        cover.layer?.masksToBounds = true
        cover.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.cell?.truncatesLastVisibleLine = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.maximumNumberOfLines = 1
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8
        titleRow.setHuggingPriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(countLabel)
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 3
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.cell?.truncatesLastVisibleLine = true
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.isHidden = true
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 8
        text.translatesAutoresizingMaskIntoConstraints = false
        buttons.spacing = 10
        text.addArrangedSubview(titleRow)
        text.addArrangedSubview(descriptionLabel)
        text.addArrangedSubview(buttons)
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = Self.imageTextSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(cover)
        content.addArrangedSubview(text)
        addSubview(content)
        coverWidth = cover.widthAnchor.constraint(equalToConstant: 72)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WallpaperLibraryGridMetrics.edgeInset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WallpaperLibraryGridMetrics.edgeInset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalInset),
            coverWidth, cover.heightAnchor.constraint(equalTo: cover.widthAnchor),
            titleRow.widthAnchor.constraint(lessThanOrEqualTo: text.widthAnchor),
            descriptionLabel.widthAnchor.constraint(equalTo: text.widthAnchor)
        ])
        cover.updateBackground()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    /// The grid supplies its actual clip width before applying any new header
    /// geometry. Measuring the native stack avoids inheriting the old host's
    /// fixed height, and the image never contributes a changing intrinsic size.
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        coverWidth.constant = width < 600 ? 64 : 72
        let textWidth = max(1, width - WallpaperLibraryGridMetrics.edgeInset * 2
            - coverWidth.constant - Self.imageTextSpacing)
        title.preferredMaxLayoutWidth = max(1, textWidth - countLabel.intrinsicContentSize.width - titleRow.spacing)
        descriptionLabel.preferredMaxLayoutWidth = textWidth
        return ceil(content.fittingSize.height + Self.verticalInset * 2)
    }

    func update(name: String, summary: String, image: NSImage?, canPlay: Bool, canAdd: Bool,
                descriptionText: String? = nil, playableCount: Int? = nil,
                play: @escaping () -> Void, random: @escaping () -> Void, add: @escaping () -> Void) {
        title.stringValue = name
        title.toolTip = name
        countLabel.stringValue = summary
        countLabel.setAccessibilityLabel(summary)
        let description = descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        descriptionLabel.stringValue = description
        descriptionLabel.isHidden = description.isEmpty
        descriptionLabel.setAccessibilityLabel(description)
        cover.image = image ?? NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: "播放列表封面")
        cover.contentTintColor = image == nil ? .controlAccentColor : nil
        actions = [play, random, add]
        if buttons.arrangedSubviews.isEmpty {
            for (tag, label, symbol, accessible) in [(1, "", "shuffle", "随机播放"), (0, "播放", "play.fill", "播放"), (2, "", "plus", "添加壁纸")] {
                let button = NSButton(title: label, target: self, action: #selector(invoke(_:)))
                WallpaperLibraryControlStyle.capsule(button, bezelStyle: .flexiblePush)
                button.controlSize = .large
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                button.imagePosition = label.isEmpty ? .imageOnly : .imageLeading
                button.contentTintColor = .controlAccentColor
                button.setAccessibilityLabel(accessible)
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: tag == 0 ? 112 : 36).isActive = true
                button.heightAnchor.constraint(equalToConstant: 28).isActive = true
                button.tag = tag
                buttons.addArrangedSubview(button)
            }
        }
        for case let button as NSButton in buttons.arrangedSubviews {
            button.isEnabled = button.tag == 2 ? canAdd : canPlay
            let scope = playableCount.map { "当前显示结果中可播放的 \($0) 张壁纸" } ?? "当前显示的壁纸"
            let help = button.tag == 2 ? "从本地或已下载内容添加壁纸" : (button.tag == 1 ? "随机播放" : "播放") + scope
            button.toolTip = help
            button.setAccessibilityHelp(help)
        }
    }
    @objc private func invoke(_ sender: NSButton) { if actions.indices.contains(sender.tag) { actions[sender.tag]() } }
}

private final class WallpaperPlaylistHeaderCoverView: NSImageView {
    // A template symbol's alignment metrics must not grow the actual cover
    // beyond the square selected by the header's native layout.
    override var alignmentRectInsets: NSEdgeInsets { .init() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
}
