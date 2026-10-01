//
//  SILInspectorSupport.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

enum SILInspectorViews {
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
            NSLayoutConstraint.activate([row.widthAnchor.constraint(equalTo: stack.widthAnchor)])
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

    static func makeBadge(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.layer?.borderWidth = 0.6
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])

        return container
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
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([divider.heightAnchor.constraint(equalToConstant: 1)])
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
}

final class SILInspectorPreviewSurfaceView: NSView {
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
            starting: NSColor.white.withAlphaComponent(0.22),
            ending: NSColor(calibratedRed: 0.84, green: 0.91, blue: 1, alpha: 0.20)
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

        placeholderView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
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
