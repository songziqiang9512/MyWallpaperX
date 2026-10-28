//
//  AboutWindowController.swift
//  MyWallpaperX
//

import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private static let repositoryURL = URL(string: "https://github.com/songziqiang9512/MyWallpaperX")!
    private var hasShownWindow = false

    private init() {
        let window = AboutPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 250),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 MyWallpaperX"
        window.identifier = NSUserInterfaceItemIdentifier("AboutWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.collectionBehavior = [.auxiliary]
        window.tabbingMode = .disallowed
        window.isExcludedFromWindowsMenu = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        super.init(window: window)
        shouldCascadeWindows = false
        window.contentView = AboutContentView(target: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !hasShownWindow {
            window.center()
            hasShownWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openGitHub(_ sender: Any?) {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        AppUpdateController.shared.checkForUpdates(sender)
    }

    private final class AboutPanel: NSPanel {
        override func cancelOperation(_ sender: Any?) {
            performClose(sender)
        }
    }
}

private final class AboutContentView: NSView {
    private let appName = "MyWallpaperX"
    private weak var target: AboutWindowController?

    init(target: AboutWindowController) {
        self.target = target
        super.init(frame: .zero)
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildInterface() {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = .systemFont(ofSize: 34, weight: .regular)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = wrappingLabel(informationText)
        descriptionLabel.textColor = .secondaryLabelColor

        let githubButton = NSButton(
            title: "GitHub",
            target: target,
            action: #selector(AboutWindowController.openGitHub(_:))
        )
        githubButton.bezelStyle = .rounded
        githubButton.controlSize = .large
        githubButton.toolTip = "查看项目、反馈问题或在 GitHub 点 Star"

        let updateButton = NSButton(
            title: "检查更新",
            target: target,
            action: #selector(AboutWindowController.checkForUpdates(_:))
        )
        updateButton.bezelStyle = .rounded
        updateButton.controlSize = .large

        let buttonStack = NSStackView(views: [githubButton, updateButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 10
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        for view in [iconView, titleLabel, versionLabel, descriptionLabel, buttonStack] {
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 104),
            iconView.heightAnchor.constraint(equalToConstant: 104),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 30),
            versionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            descriptionLabel.topAnchor.constraint(greaterThanOrEqualTo: versionLabel.bottomAnchor, constant: 28),
            descriptionLabel.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -24),
            buttonStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private var informationText: String {
        "初心至简，保持纯粹。\n为MacOS设计的原生壁纸管理应用。"
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(shortVersion) (\(buildVersion))"
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
