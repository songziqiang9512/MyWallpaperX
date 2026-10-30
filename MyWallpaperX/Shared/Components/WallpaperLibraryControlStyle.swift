import AppKit

/// Shared native geometry and symbols; actions, state and source color stay with their owners.
@MainActor enum WallpaperLibraryControlStyle {
    static let toolbarSearchWidth: CGFloat = 220
    static let toolbarAccountSize: CGFloat = 32
    static let sortSymbol = "line.3.horizontal.decrease"
    static let filterSymbol = "line.3.horizontal.decrease.circle"
    static let cardSelectionBorderWidth: CGFloat = 1.6

    static func cardOutlineColor(selected: Bool, in appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return selected ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.92 : 0.84)
            : NSColor.white.withAlphaComponent(dark ? 0.56 : 0.72)
    }

    static func selectionCheckmark() -> NSImageView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyDown
        icon.isHidden = true
        return icon
    }

    static func selectionBadge(_ badge: NSView, selected: Bool) {
        badge.layer?.backgroundColor = (selected ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        badge.layer?.borderWidth = selected ? 0 : 1
    }

    static func thumbnailPlaceholder(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
    }

    static func gridState(symbol: String? = nil, label: NSTextField, message: String? = nil) -> NSStackView {
        let stack = WallpaperLibraryEmptyStackView()
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let symbol {
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
            icon.contentTintColor = .tertiaryLabelColor
            icon.symbolConfiguration = .init(pointSize: 32, weight: .regular)
            icon.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(icon)
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 44), icon.heightAnchor.constraint(equalToConstant: 44)])
        }
        let labels = [label] + (message.map { [NSTextField(wrappingLabelWithString: $0)] } ?? [])
        for (index, text) in labels.enumerated() {
            text.font = .systemFont(ofSize: index == 0 ? 13 : 12)
            text.textColor = .secondaryLabelColor; text.alignment = .center
            text.maximumNumberOfLines = 0; text.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(text)
            text.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        }
        return stack
    }

    static func inspectorFact(label title: String, value: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = .secondaryLabelColor
        let text = NSTextField(wrappingLabelWithString: value)
        text.font = .systemFont(ofSize: 13, weight: .semibold); text.textColor = .labelColor
        text.maximumNumberOfLines = 0; text.isSelectable = true
        stack.addArrangedSubview(label); stack.addArrangedSubview(text)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    static func inspectorFacts(_ facts: [(String, String)]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for index in stride(from: 0, to: facts.count, by: 2) {
            let row = NSStackView()
            row.orientation = .horizontal; row.alignment = .top; row.spacing = 12; row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(inspectorFact(label: facts[index].0, value: facts[index].1))
            row.addArrangedSubview(index + 1 < facts.count
                ? inspectorFact(label: facts[index + 1].0, value: facts[index + 1].1) : NSView())
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    static func authorPill(_ button: NSControl) {
        button.wantsLayer = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.layer?.cornerRadius = 18
    }

    /// One native, appearance-aware divider for glass-backed Inspectors.
    static func sectionDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .custom
        divider.borderWidth = 0
        divider.contentViewMargins = .zero
        divider.fillColor = NSColor.separatorColor.withAlphaComponent(0.25)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        divider.setAccessibilityElement(false)
        return divider
    }

    static func addSectionDivider(to stack: NSStackView) {
        let divider = sectionDivider()
        stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    static func capsule(_ button: NSButton, bezelStyle: NSButton.BezelStyle = .push) {
        button.bezelStyle = bezelStyle
        button.borderShape = .capsule
        button.isBordered = true
    }

    static func toolbarAccountButton(_ button: NSButton) {
        button.controlSize = .regular
        button.frame.size = NSSize(width: toolbarAccountSize, height: toolbarAccountSize)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .center
    }

    /// Sheet forms have their own native size; Header, toolbar and card bar
    /// callers keep the existing compact style above.
    static func sheetCapsule(_ button: NSButton) {
        button.controlSize = .large
        button.bezelStyle = .glass
        button.borderShape = .capsule
        button.isBordered = true
    }
}

final class WallpaperLibraryEmptyStackView: NSStackView {
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

@MainActor final class WallpaperPanelCloseButton: NSButton {
    var showsBackground = true { didSet { refreshAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32), heightAnchor.constraint(equalToConstant: 18)
        ])
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        contentTintColor = .labelColor
        layer?.backgroundColor = (showsBackground
            ? (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.05)) : .clear).cgColor
        layer?.borderColor = (showsBackground
            ? (dark ? NSColor.white.withAlphaComponent(0.20) : NSColor.black.withAlphaComponent(0.07)) : .clear).cgColor
        layer?.borderWidth = showsBackground ? 0.5 : 0
    }
}
