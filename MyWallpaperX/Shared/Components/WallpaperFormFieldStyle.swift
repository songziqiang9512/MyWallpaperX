import AppKit

/// Presentation only. Native editors retain their delegates, formatters,
/// marked text, selection, Undo, and secure-input behavior.
@MainActor enum WallpaperFormFieldStyle {
    static func configure(_ field: NSTextField) {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .exterior
    }

    static func wrapping(_ field: NSTextField, height: CGFloat? = nil) -> WallpaperFormFieldSurface {
        let outerHeight = height ?? max(field.frame.height, field.intrinsicContentSize.height)
        let surface = WallpaperFormFieldSurface(frame: NSRect(x: 0, y: 0, width: field.frame.width, height: outerHeight))
        surface.translatesAutoresizingMaskIntoConstraints = false
        configure(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(field)
        NSLayoutConstraint.activate([
            surface.heightAnchor.constraint(equalToConstant: outerHeight),
            field.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: surface.centerYAnchor)
        ])
        return surface
    }

    static func colors(in appearance: NSAppearance, reduceTransparency: Bool, increaseContrast: Bool) -> (fill: NSColor, border: NSColor) {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if reduceTransparency || increaseContrast {
            return (.controlBackgroundColor, increaseContrast ? .labelColor : .separatorColor)
        }
        return (.black.withAlphaComponent(dark ? 0.20 : 0.04),
            (dark ? NSColor.white : .black).withAlphaComponent(dark ? 0.16 : 0.10))
    }
}

@MainActor final class WallpaperFormFieldSurface: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.8
        setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshAppearance),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        refreshAppearance()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAppearance() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshAppearance() }
    @objc private func refreshAppearance() {
        let colors = WallpaperFormFieldStyle.colors(in: effectiveAppearance,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = colors.fill.cgColor
            layer?.borderColor = colors.border.cgColor
        }
    }
}

@MainActor final class WallpaperFormTextField: NSTextField {
    override var focusRingMaskBounds: NSRect { superview.map { convert($0.bounds, from: $0) } ?? bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 10, yRadius: 10).fill()
    }
}

@MainActor final class WallpaperFormSecureField: NSSecureTextField {
    override var focusRingMaskBounds: NSRect { superview.map { convert($0.bounds, from: $0) } ?? bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 10, yRadius: 10).fill()
    }
}

@MainActor final class WallpaperFormTextView: NSTextView {
    override var focusRingMaskBounds: NSRect {
        guard let scroll = enclosingScrollView, let surface = scroll.superview as? WallpaperFormFieldSurface else { return bounds }
        return convert(surface.bounds, from: surface)
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 10, yRadius: 10).fill()
    }
}
