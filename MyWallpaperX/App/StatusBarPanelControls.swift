import AppKit

/// Standard buttons retain AppKit keyboard/AX behavior; only their surface and
/// SF Symbol sizing are customized to match the compact control panel.
final class StatusBarPanelSymbolButton: NSButton {
    enum Surface { case plain, favorite, subtle, overlay, primary }
    let surface: Surface

    init(symbol: String, help: String, surface: Surface = .plain, size: CGFloat = 16) {
        self.surface = surface
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size * StatusBarPanelPresentation.scale, weight: .medium)
        toolTip = help
        setAccessibilityLabel(help)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch surface {
        case .plain:
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = .labelColor
        case .favorite:
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = state == .on ? .systemRed : .labelColor
        case .subtle:
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
            contentTintColor = .labelColor
        case .overlay:
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.50).cgColor
            contentTintColor = .white
        case .primary:
            layer?.backgroundColor = (dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.18, alpha: 1)).cgColor
            contentTintColor = dark ? .black : .white
        }
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.opacity = isEnabled ? 1 : 0.38
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class StatusBarPanelCoverView: NSView {
    static let transitionKey = kCATransition
    private let imageView = NSImageView()
    private let placeholder = NSImageView()
    let properties = StatusBarPanelSymbolButton(symbol: "paintbrush", help: "属性调节", surface: .overlay, size: 14)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10 * StatusBarPanelPresentation.scale
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = false
        imageView.wantsLayer = true
        placeholder.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "暂无壁纸预览")
        placeholder.contentTintColor = .tertiaryLabelColor
        placeholder.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28 * StatusBarPanelPresentation.scale, weight: .light)
        addSubview(imageView)
        addSubview(placeholder)
        addSubview(properties)
    }

    required init?(coder: NSCoder) { nil }

    func setImage(_ image: NSImage?) {
        guard imageView.image !== image else { return }
        let crossfade = image != nil && imageView.image != nil && window?.isVisible == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        imageView.layer?.removeAnimation(forKey: Self.transitionKey)
        if crossfade {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(transition, forKey: Self.transitionKey)
        }
        imageView.image = image
        placeholder.isHidden = image != nil
        needsLayout = true
        // Commit the new AppKit contents within this transition, rather than
        // leaving a later display pass to replace an independently animated layer.
        layoutSubtreeIfNeeded()
        imageView.displayIfNeeded()
    }

    override func layout() {
        super.layout()
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                     width: size.width, height: size.height)
        } else { imageView.frame = bounds }
        placeholder.frame = bounds
        let scale = StatusBarPanelPresentation.scale
        properties.frame = NSRect(x: bounds.width - 42 * scale, y: bounds.height - 42 * scale,
                                  width: 30 * scale, height: 30 * scale)
        properties.needsDisplay = true
    }
}
