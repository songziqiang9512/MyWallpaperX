//
//  InspectorFooterMetrics.swift
//  MyWallpaperX
//

import CoreGraphics
import AppKit

enum InspectorFooterMetrics {
    static let height: CGFloat = 38
    static let iconWidth: CGFloat = height
    static let textMinWidth: CGFloat = 96
}

enum InspectorFooterButtonKind {
    case primary
    case secondary
    case danger
}

final class InspectorFooterButton: NSControl {
    private let kind: InspectorFooterButtonKind
    private var rawTitle: String
    private var rawImage: NSImage?
    private let contentStack = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isPressed = false
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    init(
        title: String,
        image: NSImage?,
        kind: InspectorFooterButtonKind = .secondary,
        target: AnyObject?,
        action: Selector
    ) {
        self.kind = kind
        self.rawTitle = title
        self.rawImage = image
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isEnabled: Bool {
        didSet { updateStyle() }
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        if isEnabled, let key = event.charactersIgnoringModifiers, key == " " || key == "\r" {
            _ = accessibilityPerformPress()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let action else { return false }
        return NSApp.sendAction(action, to: target, from: self)
    }

    override var allowsVibrancy: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = rawTitle.isEmpty ? 0 : ceil(titleLabel.intrinsicContentSize.width + 40)
        return NSSize(
            width: rawTitle.isEmpty ? InspectorFooterMetrics.iconWidth : max(textWidth, InspectorFooterMetrics.textMinWidth),
            height: InspectorFooterMetrics.height
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateStyle()
    }

    private func setup() {
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        if !rawTitle.isEmpty {
            setAccessibilityLabel(rawTitle)
            toolTip = rawTitle
        }
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.7
        translatesAutoresizingMaskIntoConstraints = false
        setupContentViews()
        updateStyle()
    }

    private func setupContentViews() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        updateIconImage()
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addSubview(iconView)

        if rawTitle.isEmpty {
            titleLabel.isHidden = true
        } else {
            titleLabel.stringValue = rawTitle
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addSubview(titleLabel)
        }

        addSubview(contentStack)
        let inset: CGFloat = rawTitle.isEmpty ? 0 : 12
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.heightAnchor.constraint(equalToConstant: 22),
            iconView.centerYAnchor.constraint(equalTo: contentStack.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: rawTitle.isEmpty ? 18 : 16),
            iconView.heightAnchor.constraint(equalToConstant: rawTitle.isEmpty ? 18 : 16)
        ])
        if rawTitle.isEmpty {
            iconView.centerXAnchor.constraint(equalTo: contentStack.centerXAnchor).isActive = true
        } else {
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
                titleLabel.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: contentStack.centerYAnchor)
            ])
        }
    }

    func setSymbol(_ symbolName: String, accessibilityDescription: String?) {
        rawImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        updateIconImage()
        updateStyle()
    }

    func setTitle(_ title: String) {
        rawTitle = title
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
        toolTip = title
        invalidateIntrinsicContentSize()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { isHovering = true; updateStyle() }
    override func mouseExited(with event: NSEvent) { isHovering = false; updateStyle() }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateStyle()

        var shouldSendAction = false
        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let localPoint = convert(nextEvent.locationInWindow, from: nil)
            let inside = bounds.contains(localPoint)
            isPressed = inside
            updateStyle()

            if nextEvent.type == .leftMouseUp {
                shouldSendAction = inside
                break
            }
        }

        isPressed = false
        updateStyle()
        if shouldSendAction, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    private func updateStyle() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateStyle()
            }
            return
        }

        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.45
        let pressedFactor: CGFloat = isPressed ? 0.88 : 1
        let isDarkMode = resolvedIsDarkMode()
        let fill: NSColor
        let text: NSColor
        let border: NSColor

        switch kind {
        case .primary:
            fill = NSColor.systemBlue.withAlphaComponent((isDarkMode ? 0.95 : 0.88) * enabledAlpha * pressedFactor)
            text = .white.withAlphaComponent(enabledAlpha)
            border = NSColor.systemBlue.withAlphaComponent(0.42 * enabledAlpha)
        case .secondary:
            fill = isDarkMode
                ? NSColor.black.withAlphaComponent(0.26 * enabledAlpha * pressedFactor)
                : NSColor.black.withAlphaComponent(0.06 * enabledAlpha * pressedFactor)
            text = (isDarkMode ? NSColor.white : NSColor.black)
                .withAlphaComponent(enabledAlpha)
            border = (isDarkMode ? NSColor.white : NSColor.black)
                .withAlphaComponent((isDarkMode ? 0.16 : 0.08) * enabledAlpha)
        case .danger:
            fill = NSColor.systemRed.withAlphaComponent((isDarkMode ? 0.74 : 0.66) * enabledAlpha * pressedFactor)
            text = .white.withAlphaComponent(enabledAlpha)
            border = NSColor.systemRed.withAlphaComponent(0.26 * enabledAlpha)
        }

        iconView.contentTintColor = text
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: rawTitle.isEmpty ? 17 : 14,
            weight: .semibold
        )
        titleLabel.textColor = text
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = (isHovering && isEnabled ? NSColor.controlAccentColor.withAlphaComponent(0.5) : border).cgColor
    }

    private func updateIconImage() {
        iconView.image = rawImage?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: rawTitle.isEmpty ? 17 : 14,
                weight: rawTitle.isEmpty ? .regular : .semibold
            )
        )
        iconView.image?.isTemplate = true
    }

    private func resolvedIsDarkMode() -> Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
