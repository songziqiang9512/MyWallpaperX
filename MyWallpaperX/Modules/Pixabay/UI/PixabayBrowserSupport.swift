//
//  PixabayBrowserSupport.swift
//  MyWallpaperX
//

import AppKit

enum PixabayBrowserContentState: Equatable {
    case apiKeyPrompt
    case loadingInitial
    case initialError(String)
    case emptyLoaded
    case startPrompt
    case grid
}

enum PixabayBrowserViews {
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


}
