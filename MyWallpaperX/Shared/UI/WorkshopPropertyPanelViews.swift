import AppKit

@MainActor
protocol WorkshopPropertyKeyTraversal: AnyObject {
    func focusNextPropertyControl(from responder: NSResponder?, reverse: Bool) -> Bool
}

/// Shared presentation only; each engine keeps its own values and action targets.
@MainActor
class WorkshopPropertyRowView: NSView {
    enum Style { case note, group, inline, choice, stacked, resource }
    let title = WorkshopPropertyTitleView()
    let content = NSStackView()
    let style: Style
    private var measuredWidth: CGFloat = 0

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        let isLabel = style == .note || style == .group
        title.font = Self.font(for: style)
        title.textColor = isLabel ? .secondaryLabelColor : .labelColor
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
        if style != .choice {
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: style == .inline ? -64 : -4).isActive = true
        }
        if isLabel {
            title.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        } else {
            addSubview(content)
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4).isActive = true
            if style == .choice {
                content.distribution = .fill
                let preferredWidth = content.widthAnchor.constraint(equalToConstant: 180)
                // Prefer a useful menu width without enlarging a fixed panel.
                preferredWidth.priority = .init(499)
                NSLayoutConstraint.activate([
                    title.trailingAnchor.constraint(equalTo: content.leadingAnchor, constant: -12),
                    title.centerYAnchor.constraint(equalTo: centerYAnchor),
                    content.centerYAnchor.constraint(equalTo: centerYAnchor),
                    content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5, constant: -4),
                    preferredWidth
                ])
            } else if style == .inline {
                NSLayoutConstraint.activate([
                    title.centerYAnchor.constraint(equalTo: centerYAnchor),
                    content.widthAnchor.constraint(equalToConstant: 44),
                    content.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                    content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                    content.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
                    content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
                ])
            }
        }
    }
    required init?(coder: NSCoder) { nil }

    static func font(for style: Style) -> NSFont {
        .systemFont(ofSize: style == .note || style == .group ? 12 : 13,
            weight: style == .group ? .semibold : .regular)
    }
    static func titleWidth(style: Style, rowWidth: CGFloat) -> CGFloat {
        if style == .choice { return max(1, rowWidth - 20 - min(180, max(1, (rowWidth - 8) / 2))) }
        return max(1, rowWidth - (style == .inline ? 68 : 8))
    }
    static func height(style: Style, text: String, rowWidth: CGFloat) -> CGFloat {
        height(style: style, content: .init(text: text), rowWidth: rowWidth)
    }
    static func height(style: Style, content: WorkshopPropertyTextContent, rowWidth: CGFloat) -> CGFloat {
        let textHeight = WorkshopPropertyTitleView.height(content: content,
            width: titleWidth(style: style, rowWidth: rowWidth), font: font(for: style))
        let controlsHeight: CGFloat = style == .resource ? 62 : (style == .stacked ? 34 : 0)
        return max(style == .note || style == .group ? 30 : 40, textHeight + 18 + controlsHeight)
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric,
            height: Self.height(style: style, content: title.presentation, rowWidth: bounds.width > 0 ? bounds.width : 324))
    }
    override func layout() {
        title.preferredMaxLayoutWidth = Self.titleWidth(style: style, rowWidth: bounds.width)
        if abs(measuredWidth - bounds.width) > 0.5 {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        super.layout()
    }
}

/// Text and authored horizontal rules share the same measurement in both lists.
@MainActor
final class WorkshopPropertyTitleView: NSView {
    private let stack = NSStackView()
    private(set) var presentation = WorkshopPropertyTextContent(text: "")
    var font: NSFont = .systemFont(ofSize: 13)
    var textColor: NSColor = .labelColor
    var stringValue: String {
        get { presentation.text }
        set { setPresentation(.init(text: newValue)) }
    }
    var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet {
            guard abs(oldValue - preferredMaxLayoutWidth) > 0.5 else { return }
            for label in stack.arrangedSubviews.compactMap({ $0 as? NSTextField }) {
                label.preferredMaxLayoutWidth = preferredMaxLayoutWidth
            }
            invalidateIntrinsicContentSize()
        }
    }
    init() {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }
    func setPresentation(_ content: WorkshopPropertyTextContent) {
        guard presentation != content else { return }
        presentation = content
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for segment in content.segments {
            let view: NSView
            switch segment {
            case let .text(text):
                let label = NSTextField(wrappingLabelWithString: text)
                label.font = font
                label.textColor = textColor
                label.preferredMaxLayoutWidth = preferredMaxLayoutWidth
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                view = label
            case .separator:
                let line = NSBox()
                line.boxType = .separator
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                view = line
            }
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        invalidateIntrinsicContentSize()
    }
    static func height(content: WorkshopPropertyTextContent, width: CGFloat, font: NSFont) -> CGFloat {
        content.segments.reduce(CGFloat(max(0, content.segments.count - 1)) * 6) { height, segment in
            switch segment {
            case .separator: return height + 1
            case let .text(text):
                let rect = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
                return height + ceil(rect.height)
            }
        }
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric,
            height: Self.height(content: presentation, width: preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : 324, font: font))
    }
}

@MainActor
final class WorkshopPropertyScrollView: InspectorFadingScrollView {
    init() {
        super.init(fadeRatio: 0)
        drawsBackground = false
        hasVerticalScroller = true
        let scroller = PropertyScroller()
        scroller.isHidden = true
        verticalScroller = scroller
        hasHorizontalScroller = false
    }
    required init?(coder: NSCoder) { nil }
    private final class PropertyScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }
        override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 0 }
        // Collection views require scrolling enabled for content sizing. Hide
        // only the scroller, including after content/clip or system-style changes.
        override var isHidden: Bool {
            get { super.isHidden }
            set { super.isHidden = true }
        }
    }
}

@MainActor
enum WorkshopPropertyPanelLayout {
    static let rowSpacing: CGFloat = 6

    static func resetRow(_ reset: NSButton) -> NSView {
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        reset.imagePosition = .imageLeading
        reset.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(reset)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 40),
            reset.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            reset.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }
    static func install(in view: NSView, status: NSTextField? = nil, scrollView: NSScrollView) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [scrollView] + (status.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
