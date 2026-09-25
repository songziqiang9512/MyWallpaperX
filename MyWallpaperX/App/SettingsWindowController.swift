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
            clearAllCaches: {
                manager.clearAllCaches()
                SteamWorkshopService.shared.clearAllCachedState()
            },
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

    // E2d: 单一装配（lazy settingsView 复用同一 actions），Steam 缓存
    // 清理由 App 动作层执行——Shared 视图不再直呼 Modules 单例。
    private lazy var settingsView = AppKitSettingsContainerView(
        dependency: AppSettingsPanelDependency(
            settings: WallpaperManager.shared.settings,
            actions: settingsActions
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
