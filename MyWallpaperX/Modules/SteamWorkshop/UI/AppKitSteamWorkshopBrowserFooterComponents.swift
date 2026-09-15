//
//  AppKitSteamWorkshopBrowserFooterComponents.swift
//  MyWallpaperX
//

import AppKit

final class AppKitSteamWorkshopBrowserFooterItem: NSCollectionViewItem {
    override func loadView() {
        view = AppKitSteamWorkshopBrowserFooterView(frame: .zero)
    }

    func configure(
        text: String,
        showsProgress: Bool,
        showsRetry: Bool,
        retryTitle: String = "重试",
        symbolName: String,
        symbolAccessibilityDescription: String,
        onRetry: @escaping () -> Void
    ) {
        (view as? AppKitSteamWorkshopBrowserFooterView)?.configure(
            text: text,
            showsProgress: showsProgress,
            showsRetry: showsRetry,
            retryTitle: retryTitle,
            symbolName: symbolName,
            symbolAccessibilityDescription: symbolAccessibilityDescription,
            onRetry: onRetry
        )
    }
}

final class AppKitSteamWorkshopBrowserFooterView: NSView {
    private let stackView = NSStackView()
    private let progressIndicator = NSProgressIndicator()
    private let statusIconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private var retryHandler: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        text: String,
        showsProgress: Bool,
        showsRetry: Bool,
        retryTitle: String = "重试",
        symbolName: String,
        symbolAccessibilityDescription: String,
        onRetry: @escaping () -> Void
    ) {
        textField.stringValue = text
        progressIndicator.isHidden = !showsProgress
        statusIconView.isHidden = showsProgress
        statusIconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: symbolAccessibilityDescription
        )
        retryButton.isHidden = !showsRetry
        retryButton.title = retryTitle
        retryButton.setAccessibilityLabel("\(retryTitle)更多项目")
        retryHandler = showsRetry ? onRetry : nil
        if showsProgress {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        identifier = NSUserInterfaceItemIdentifier("SteamWorkshopBrowserFooterView")

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        statusIconView.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "没有更多内容")
        statusIconView.contentTintColor = .secondaryLabelColor

        textField.font = .systemFont(ofSize: 12)
        textField.textColor = .secondaryLabelColor
        textField.alignment = .center
        textField.lineBreakMode = .byTruncatingTail

        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.target = self
        retryButton.action = #selector(retryLoadMore)
        retryButton.setAccessibilityLabel("重试加载更多项目")
        retryButton.isHidden = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(progressIndicator)
        stackView.addArrangedSubview(statusIconView)
        stackView.addArrangedSubview(textField)
        stackView.addArrangedSubview(retryButton)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24)
        ])
    }

    @objc private func retryLoadMore() {
        retryHandler?()
    }
}
