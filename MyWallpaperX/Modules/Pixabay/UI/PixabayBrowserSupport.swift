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
