//
//  OnlineLibraryBrowserSupport.swift
//  MyWallpaperX
//

import AppKit

enum OnlineLibraryBrowserContentState: Equatable {
    case apiKeyPrompt
    case loadingInitial
    case initialError(String)
    case emptyLoaded
    case startPrompt
    case grid
}

enum OnlineLibraryBrowserViews {
    static func makeCenteredStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func makeCenteredStateView(symbolName: String, title: String, message: String?) -> NSStackView {
        let outer = makeCenteredStack(spacing: 12)
        outer.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)

        let spacerTop = NSView()
        spacerTop.translatesAutoresizingMaskIntoConstraints = false
        let spacerBottom = NSView()
        spacerBottom.translatesAutoresizingMaskIntoConstraints = false

        let content = makeCenteredStack(spacing: 12)
        content.addArrangedSubview(makeSymbol(symbolName, pointSize: 36, color: .secondaryLabelColor))

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 0
        content.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true

        if let message {
            let messageLabel = makeLabel(message, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
            messageLabel.alignment = .center
            messageLabel.maximumNumberOfLines = 0
            content.addArrangedSubview(messageLabel)
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        }

        outer.addArrangedSubview(spacerTop)
        outer.addArrangedSubview(content)
        outer.addArrangedSubview(spacerBottom)
        spacerTop.heightAnchor.constraint(equalTo: spacerBottom.heightAnchor).isActive = true
        return outer
    }

    static func makeLoadingState(title: String) -> NSView {
        let stack = makeCenteredStack(spacing: 12)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(makeLabel(title, font: .systemFont(ofSize: 13), color: .secondaryLabelColor))

        let wrapper = makeCenteredStateView(symbolName: "play.rectangle.on.rectangle", title: "", message: nil)
        wrapper.arrangedSubviews.forEach {
            wrapper.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let top = NSView()
        let bottom = NSView()
        top.translatesAutoresizingMaskIntoConstraints = false
        bottom.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addArrangedSubview(top)
        wrapper.addArrangedSubview(stack)
        wrapper.addArrangedSubview(bottom)
        top.heightAnchor.constraint(equalTo: bottom.heightAnchor).isActive = true
        return wrapper
    }

    static func makeSymbol(_ symbolName: String, pointSize: CGFloat, color: NSColor) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imageView.contentTintColor = color
        imageView.symbolConfiguration = .init(pointSize: pointSize, weight: .medium)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: pointSize + 12),
            imageView.heightAnchor.constraint(equalToConstant: pointSize + 12)
        ])
        return imageView
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

    static func makeButton(title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func makeErrorBanner(message: String, target: AnyObject?, action: Selector) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.1).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = makeSymbol("exclamationmark.triangle.fill", pointSize: 13, color: .systemOrange)
        let label = makeLabel(message, font: .systemFont(ofSize: 12), color: .labelColor)
        label.tag = 11
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let retry = makeButton(title: "重试", target: target, action: action)

        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(retry)
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }
}

final class OnlineLibraryDownloadToastView: NSVisualEffectView {
    private let onSetAsWallpaper: () -> Void
    private let onDismiss: () -> Void
    private let onHoverChange: (Bool) -> Void

    init(
        message: String,
        onSetAsWallpaper: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onDismiss = onDismiss
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
        setup(message: message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }

    private func setup(message: String) {
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let badge = OnlineLibraryBrowserViews.makeSymbol("checkmark", pointSize: 16, color: .systemGreen)
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(
            OnlineLibraryBrowserViews.makeLabel("下载完成", font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        )
        let messageLabel = OnlineLibraryBrowserViews.makeLabel(message, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.maximumNumberOfLines = 1
        textStack.addArrangedSubview(messageLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let setButton = OnlineLibraryBrowserViews.makeButton(title: "设为壁纸", target: self, action: #selector(setAsWallpaper))
        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭") ?? NSImage(), target: self, action: #selector(dismiss))
        closeButton.bezelStyle = .inline
        closeButton.toolTip = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(badge)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(setButton)
        row.addArrangedSubview(closeButton)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc private func setAsWallpaper() {
        onSetAsWallpaper()
    }

    @objc private func dismiss() {
        onDismiss()
    }
}
