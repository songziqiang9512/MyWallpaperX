//
//  SettingsWindowController.swift
//  MyWallpaperX
//

import AppKit
import Combine

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
    private var cancellables = Set<AnyCancellable>()
    private var isSyncingSettings = false

    private lazy var settingsActions: AppSettingsActions = {
        let manager = WallpaperManager.shared
        return AppSettingsActions(
            applyEngineSettings: { manager.applyEngineSettings(reloadWallpaper: $0) },
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

        bindSettingsAuthority()
    }

    /// M0.3 回归修复：`WallpaperSettings` 是值类型，面板写 dependency 快照
    /// 必须回到 `WallpaperManager.settings` 单点权威（引擎/策略控制器/持久化
    /// 读它）；manager 侧变更（播放模式互斥、音量、导入、重置）必须同步回填
    /// dependency，否则下一次面板写会把整快照旧值推回 manager。两个方向都
    /// 同步投递（不经调度器），handler 随后调用的 actions 才能读到新值；
    /// `@Published` 在 willSet 期属性尚未落盘，朴素的双向相等守卫会读到
    /// 滞后值互相触发，所以用 `isSyncingSettings` 挡住镜像回声。
    private func bindSettingsAuthority() {
        let manager = WallpaperManager.shared
        settingsView.dependency.$settings
            .dropFirst()
            .sink { [weak self] settings in
                dispatchPrecondition(condition: .onQueue(.main))
                guard let self, !self.isSyncingSettings,
                      manager.settings != settings else { return }
                self.isSyncingSettings = true
                manager.settings = settings
                self.isSyncingSettings = false
            }
            .store(in: &cancellables)
        manager.$settings
            .sink { [weak self] settings in
                dispatchPrecondition(condition: .onQueue(.main))
                guard let self, !self.isSyncingSettings else { return }
                let dependency = self.settingsView.dependency
                guard dependency.settings != settings else { return }
                self.isSyncingSettings = true
                dependency.settings = settings
                self.isSyncingSettings = false
            }
            .store(in: &cancellables)
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
