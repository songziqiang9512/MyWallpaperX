import AppKit

enum SettingsPanelLayout {
    static let windowSize = NSSize(width: 648, height: 664)
    static let minimumSize = NSSize(width: 600, height: 480)
    static let sidebarWidth: CGFloat = 184
    static let pageInset: CGFloat = 12
    static let bottomInset: CGFloat = 20
    static let groupSpacing: CGFloat = 16
    static let controlSpacing: CGFloat = 6
    static let subordinateInset: CGFloat = 38
}

final class SettingsToggle: NSSwitch {
    var symbolName: String?
    var title = "" { didSet { setAccessibilityLabel(title) } }
}

final class SettingsFormView: NSStackView {
    private let isNested: Bool
    private var card: SettingsCard?

    init(rowSpacing: CGFloat = SettingsPanelLayout.groupSpacing) {
        isNested = rowSpacing == SettingsPanelLayout.controlSpacing
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = rowSpacing
        detachesHiddenViews = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func addSection(_ title: String) {
        card = nil
        let heading = Self.heading(title, size: 14, color: .secondaryLabelColor)
        addArrangedSubview(heading)
        setCustomSpacing(12, after: heading)
    }

    @discardableResult
    func addGroup(_ title: String, controls: [NSView], symbol: String? = nil) -> NSView {
        let rows = Self.controls([], horizontal: false)
        rows.spacing = 0
        rows.detachesHiddenViews = true
        var firstSetting = true
        for control in controls {
            let toggle = control as? SettingsToggle
            let isSupplement = control is NSStackView && !firstSetting
            let row: NSView
            if isSupplement {
                row = control
            } else {
                let name = toggle?.title ?? (firstSetting ? title : "")
                let rowSymbol = toggle?.symbolName ?? (firstSetting ? symbol : nil)
                row = SettingsCardRow(title: name, control: control, symbol: rowSymbol, compact: isNested)
                if !firstSetting && !isNested { SettingsCard.addSeparator(to: rows) }
            }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            firstSetting = false
        }
        if isNested {
            addArrangedSubview(rows)
            rows.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        } else {
            let container: SettingsCard
            if let card {
                container = card
                SettingsCard.addSeparator(to: rows, at: 0)
            } else {
                container = SettingsCard()
                addArrangedSubview(container)
                container.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
                card = container
            }
            container.stack.addArrangedSubview(rows)
            rows.widthAnchor.constraint(equalTo: container.stack.widthAnchor).isActive = true
        }
        return rows
    }

    func addDivider() { card = nil }

    static func controls(_ views: [NSView], horizontal: Bool = false, indent: CGFloat = 0) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = horizontal ? .horizontal : .vertical
        stack.alignment = horizontal ? .centerY : .leading
        stack.spacing = horizontal ? 8 : SettingsPanelLayout.controlSpacing
        stack.edgeInsets.left = indent
        stack.detachesHiddenViews = true
        return stack
    }

    static func subordinateRow(_ title: String, control: NSView) -> NSView {
        let row = SettingsCardRow(title: title, control: control, symbol: nil, compact: true)
        let container = controls([row], indent: SettingsPanelLayout.subordinateInset)
        row.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -SettingsPanelLayout.subordinateInset).isActive = true
        return container
    }

    static func detail(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let detail = controls([label])
        detail.edgeInsets = NSEdgeInsets(top: 0, left: 36, bottom: 10, right: 10)
        label.widthAnchor.constraint(equalTo: detail.widthAnchor, constant: -46).isActive = true
        return detail
    }

    private static func heading(_ text: String, size: CGFloat, color: NSColor) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: .bold)
        label.textColor = color
        return controls([label], horizontal: true, indent: 8)
    }
}

private final class SettingsCard: NSBox {
    let stack = SettingsFormView.controls([])

    override init(frame: NSRect) {
        super.init(frame: frame)
        boxType = .custom
        titlePosition = .noTitle
        cornerRadius = 12
        contentViewMargins = .zero
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        let body = contentView!
        body.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            stack.topAnchor.constraint(equalTo: body.topAnchor),
            stack.bottomAnchor.constraint(equalTo: body.bottomAnchor)
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    static func addSeparator(to stack: NSStackView, at index: Int? = nil) {
        let divider = NSBox()
        divider.boxType = .separator
        divider.setAccessibilityElement(false)
        let container = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)
        if let index { stack.insertArrangedSubview(container, at: index) }
        else { stack.addArrangedSubview(container) }
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 36),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        fillColor = dark ? .underPageBackgroundColor : .black.withAlphaComponent(0.02)
        borderColor = dark ? .separatorColor : .black.withAlphaComponent(0.05)
    }
}

private final class SettingsCardRow: NSView {
    init(title: String, control: NSView, symbol: String?, compact: Bool) {
        super.init(frame: .zero)
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        if let toggle = control as? SettingsToggle { toggle.controlSize = .mini }
        if let popup = control as? NSPopUpButton {
            popup.cell?.lineBreakMode = .byTruncatingTail
            popup.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        }
        for child in [label, control] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        let padding: CGFloat = compact ? 6 : 12
        let labelLeading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 6 : 36)
        if let symbol, let artwork = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let image = NSImageView(image: artwork)
            image.contentTintColor = .secondaryLabelColor
            image.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            image.setAccessibilityElement(false)
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                image.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 24),
                image.heightAnchor.constraint(equalToConstant: 20)
            ])
        }
        NSLayoutConstraint.activate([
            labelLeading,
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: padding),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: compact ? 4 : 7),
            heightAnchor.constraint(greaterThanOrEqualToConstant: compact ? 30 : 39)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
