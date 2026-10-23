//
//  VideoLibraryInspectorSupport.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

enum VideoLibraryInspectorViews {
    static func makeVerticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func makeSectionTitle(_ text: String) -> NSTextField {
        makeLabel(text, font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
    }

    static func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.backgroundColor = .clear
        label.isBordered = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    static func makeLoadingView(_ text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        indicator.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(indicator)
        row.addArrangedSubview(makeLabel(text, font: .systemFont(ofSize: 13), color: .secondaryLabelColor))
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 16),
            indicator.heightAnchor.constraint(equalToConstant: 16)
        ])
        return row
    }

    static func makeFactsGrid(_ facts: [(String, String)]) -> NSView {
        let stack = makeVerticalStack(spacing: 12)
        var index = 0
        while index < facts.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(makeFactView(label: facts[index].0, value: facts[index].1))
            if index + 1 < facts.count {
                row.addArrangedSubview(makeFactView(label: facts[index + 1].0, value: facts[index + 1].1))
            } else {
                row.addArrangedSubview(NSView())
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            index += 2
        }
        return stack
    }

    static func makeFactView(label: String, value: String) -> NSView {
        let stack = makeVerticalStack(spacing: 6)
        stack.addArrangedSubview(makeLabel(label, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor))
        let valueLabel = makeLabel(value, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        valueLabel.maximumNumberOfLines = 2
        valueLabel.isSelectable = true
        stack.addArrangedSubview(valueLabel)
        return stack
    }

    static func makeNotice(icon: String, text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: text)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(imageView)

        let label = makeLabel(text, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
        label.maximumNumberOfLines = 0
        row.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    static func makeDivider() -> NSView {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    static func makeFooterButton(
        title: String,
        symbolName: String,
        target: AnyObject?,
        action: Selector,
        kind: InspectorFooterButtonKind = .secondary
    ) -> InspectorFooterButton {
        let button = InspectorFooterButton(
            title: title,
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title),
            kind: kind,
            target: target,
            action: action
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func makeIconButton(
        symbolName: String,
        title: String,
        target: AnyObject?,
        action: Selector
    ) -> InspectorFooterButton {
        let button = InspectorFooterButton(
            title: "",
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title),
            kind: .secondary,
            target: target,
            action: action
        )
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

final class VideoLibraryInspectorPreviewSurfaceView: NSView {
    private let image: NSImage?
    private let placeholderView = NSImageView()

    init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGradient(
            starting: .windowBackgroundColor,
            ending: .controlBackgroundColor
        )?.draw(in: bounds, angle: -45)

        guard let image else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let targetSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let targetRect = NSRect(
            x: bounds.midX - targetSize.width / 2,
            y: bounds.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        layer?.borderWidth = 0.45

        placeholderView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        placeholderView.contentTintColor = .secondaryLabelColor
        placeholderView.symbolConfiguration = .init(pointSize: 28, weight: .medium)
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.isHidden = image != nil

        addSubview(placeholderView)
        NSLayoutConstraint.activate([
            placeholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderView.widthAnchor.constraint(equalToConstant: 36),
            placeholderView.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
}
