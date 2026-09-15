import AppKit

/// One pinned row: primary task, external page and property editor.
final class SteamWorkshopDetailFooterView: NSView {
    static let height = InspectorFooterMetrics.height

    func configure(primary: NSView, webpage: NSView, properties: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        for view in [primary, webpage, properties] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.topAnchor.constraint(equalTo: topAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            primary.leadingAnchor.constraint(equalTo: leadingAnchor),
            webpage.leadingAnchor.constraint(equalTo: primary.trailingAnchor, constant: 8),
            properties.leadingAnchor.constraint(equalTo: webpage.trailingAnchor, constant: 8),
            properties.trailingAnchor.constraint(equalTo: trailingAnchor),
            webpage.widthAnchor.constraint(equalToConstant: Self.height),
            properties.widthAnchor.constraint(equalToConstant: Self.height)
        ])
    }
}

/// A single clipped, horizontally scrollable row; labels keep their full natural width.
final class SteamWorkshopTagStripView: NSScrollView {
    private let document = NSView()
    private let labels: [NSTextField]
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 34) }

    init(tags: [String]) {
        labels = tags.map {
            let label = NSTextField(labelWithString: $0)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.lineBreakMode = .byClipping
            return label
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        drawsBackground = false
        toolTip = "左右滑动或滚动鼠标滚轮查看全部标签"
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none
        documentView = document
        for label in labels {
            let chip = NSView()
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 13
            chip.layer?.borderWidth = 0.7
            chip.addSubview(label)
            document.addSubview(chip)
        }
        updateAppearance()
    }
    required init?(coder: NSCoder) { nil }
    override func scrollWheel(with event: NSEvent) {
        // A narrow tag strip owns either wheel axis: diagonal trackpad gestures
        // and an ordinary mouse wheel must not escape into the vertical detail.
        let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.25 : 18
        let maximum = max(0, document.bounds.width - contentView.bounds.width)
        let x = min(maximum, max(0, contentView.bounds.origin.x - delta * scale))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
    private func updateAppearance() {
        for chip in document.subviews {
            chip.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
            chip.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        }
    }
    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for (chip, label) in zip(document.subviews, labels) {
            let textWidth = ceil((label.stringValue as NSString).size(withAttributes: [.font: label.font!]).width) + 8
            let width = textWidth + 20
            chip.frame = NSRect(x: x, y: 4, width: width, height: 26)
            label.frame = NSRect(x: 10, y: 5, width: textWidth, height: 16)
            x += width + 6
        }
        document.frame = NSRect(x: 0, y: 0, width: max(contentView.bounds.width, x - 6), height: 34)
    }
}
