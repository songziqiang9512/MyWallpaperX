import AppKit

/// Shared native geometry and symbols; actions, state and source color stay with their owners.
@MainActor enum WallpaperLibraryControlStyle {
    static let toolbarSearchWidth: CGFloat = 220
    static let toolbarAccountSize: CGFloat = 32
    static let sortSymbol = "line.3.horizontal.decrease"
    static let filterSymbol = "line.3.horizontal.decrease.circle"

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
