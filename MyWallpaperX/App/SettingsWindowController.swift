//
//  SettingsWindowController.swift
//  MyWallpaperX
//

import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let targetWindowSize = NSSize(width: 500, height: 560)
    private let contentController = SettingsContentViewController()
    private var hasShownWindow = false

    private init() {
        let window = MainAppWindow(contentViewController: contentController)
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(targetWindowSize)
        window.minSize = targetWindowSize
        window.maxSize = targetWindowSize
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal

        let toolbar = NSToolbar(identifier: "SettingsWindowToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        super.init(window: window)
        shouldCascadeWindows = false
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showWindow() {
        contentController.refresh()
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if !hasShownWindow {
            window.center()
            hasShownWindow = true
        }
        window.makeKeyAndOrderFront(nil)
    }
}

private final class SettingsContentViewController: NSViewController {
    private lazy var settingsActions: AppSettingsActions = {
        let manager = WallpaperManager.shared
        return AppSettingsActions(
            applyEngineSettings: { manager.applyEngineSettings(reloadWallpaper: $0) },
            applyPlaybackRateToEngine: { manager.applyPlaybackRateToEngine() },
            applySystemAudioSpectrumToEngine: { manager.applySystemAudioSpectrumToEngine() },
            clearAllCaches: { manager.clearAllCaches() },
            exportPersonalSettings: { try manager.exportPersonalSettings(to: $0) },
            importPersonalSettings: { try manager.importPersonalSettings(from: $0) },
            refreshAutoSwitchTimerIfNeeded: { manager.refreshAutoSwitchTimerIfNeeded() },
            resetToFreshInstallState: { manager.resetToFreshInstallState() },
            setLoopPlaybackEnabled: { manager.setLoopPlaybackEnabled($0) },
            setRandomPlaybackEnabled: { manager.setRandomPlaybackEnabled($0) },
            setSequentialPlaybackEnabled: { manager.setSequentialPlaybackEnabled($0) },
            setSyncSystemWallpaperEnabled: { manager.setSyncSystemWallpaperEnabled($0) },
            startAutoSwitchTimer: { manager.startAutoSwitchTimer() },
            stopAutoSwitchTimer: { manager.stopAutoSwitchTimer() },
            updateLoginItemStatus: { manager.updateLoginItemStatus() },
            updateVolume: { manager.updateVolume($0) }
        )
    }()

    private let settingsView = AppKitSettingsContainerView(
        dependency: AppSettingsPanelDependency(
            settings: WallpaperManager.shared.settings,
            actions: AppSettingsActions(
                applyEngineSettings: { WallpaperManager.shared.applyEngineSettings(reloadWallpaper: $0) },
                applyPlaybackRateToEngine: { WallpaperManager.shared.applyPlaybackRateToEngine() },
                applySystemAudioSpectrumToEngine: { WallpaperManager.shared.applySystemAudioSpectrumToEngine() },
                clearAllCaches: { WallpaperManager.shared.clearAllCaches() },
                exportPersonalSettings: { try WallpaperManager.shared.exportPersonalSettings(to: $0) },
                importPersonalSettings: { try WallpaperManager.shared.importPersonalSettings(from: $0) },
                refreshAutoSwitchTimerIfNeeded: { WallpaperManager.shared.refreshAutoSwitchTimerIfNeeded() },
                resetToFreshInstallState: { WallpaperManager.shared.resetToFreshInstallState() },
                setLoopPlaybackEnabled: { WallpaperManager.shared.setLoopPlaybackEnabled($0) },
                setRandomPlaybackEnabled: { WallpaperManager.shared.setRandomPlaybackEnabled($0) },
                setSequentialPlaybackEnabled: { WallpaperManager.shared.setSequentialPlaybackEnabled($0) },
                setSyncSystemWallpaperEnabled: { WallpaperManager.shared.setSyncSystemWallpaperEnabled($0) },
                startAutoSwitchTimer: { WallpaperManager.shared.startAutoSwitchTimer() },
                stopAutoSwitchTimer: { WallpaperManager.shared.stopAutoSwitchTimer() },
                updateLoginItemStatus: { WallpaperManager.shared.updateLoginItemStatus() },
                updateVolume: { WallpaperManager.shared.updateVolume($0) }
            )
        ),
        visibleSections: Set(AppSettingsSection.allCases),
        topContentInset: 24
    )

    override func loadView() {
        let rootView = SettingsRootBackgroundView()
        rootView.translatesAutoresizingMaskIntoConstraints = false

        settingsView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(settingsView)
        NSLayoutConstraint.activate([
            settingsView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            settingsView.topAnchor.constraint(equalTo: rootView.topAnchor),
            settingsView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        view = rootView
    }

    func refresh() {
        settingsView.updateVisibleSections(Set(AppSettingsSection.allCases))
        settingsView.refreshFromState()
    }
}

private final class SettingsRootBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        var backgroundColor = NSColor.windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .windowBackgroundColor
        }
        layer?.backgroundColor = backgroundColor.cgColor
        window?.backgroundColor = backgroundColor
    }
}
