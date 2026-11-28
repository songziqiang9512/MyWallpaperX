//
//  SettingsWindowController.swift
//  MyWallpaperX
//

import AppKit
import Combine

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let contentController = SettingsContentViewController()
    private var hasShownWindow = false

    private init() {
        let window = NSWindow(contentViewController: contentController)
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.title = AppSettingsSection.system.title
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.contentMinSize = SettingsPanelLayout.minimumSize
        window.isOpaque = false
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal

        super.init(window: window)
        shouldCascadeWindows = false
        window.toolbar = NSToolbar(identifier: "SettingsWindowChrome")
        window.toolbarStyle = .unified
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showWindow() {
        contentController.loadViewIfNeeded()
        contentController.refresh()
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if !hasShownWindow {
            let size = SettingsPanelLayout.windowSize
            let screen = MainWindowCoordinator.mainWindow()?.screen ?? window.screen ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let width = min(size.width, visible.width - 24)
                let height = min(size.height, visible.height - 24)
                window.setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                                       width: width, height: height), display: false)
            } else {
                window.setContentSize(size)
            }
            hasShownWindow = true
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    /// The App supplies the same recovery owner used during startup/reset.
    func configurePersonalSettings(_ coordinator: PersonalSettingsImportCoordinator,
                                  reset: @escaping @MainActor () -> Void) {
        contentController.personalSettings = coordinator
        contentController.resetAction = reset
    }

}

extension AppSettingsSection {
    var title: String {
        switch self {
        case .playback: String(localized: "Playback")
        case .quality: String(localized: "Wallpaper Quality")
        case .display: String(localized: "Display")
        case .interface: String(localized: "Interface")
        case .system: String(localized: "General Settings")
        case .hotkeys: String(localized: "Shortcuts")
        case .efficiency: String(localized: "Energy Saving")
        case .maintenance: String(localized: "Maintenance")
        case .about: String(localized: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .playback: "play.circle"
        case .quality: "slider.horizontal.3"
        case .display: "photo.tv"
        case .interface: "macwindow"
        case .system: "gear"
        case .hotkeys: "keyboard"
        case .efficiency: "leaf"
        case .maintenance: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }

}

private final class SettingsContentViewController: NSSplitViewController {
    private let navigation = SettingsNavigationSidebar()

    private var cancellables = Set<AnyCancellable>()
    private var isSyncingSettings = false
    weak var personalSettings: PersonalSettingsImportCoordinator?
    var resetAction: (@MainActor () -> Void)?

    private lazy var settingsActions: AppSettingsActions = {
        let manager = WallpaperManager.shared
        return AppSettingsActions(
            applyEngineSettings: { manager.applyEngineSettings(reloadWallpaper: $0) },
            reapplySceneQuality: { manager.reapplySceneQuality() },
            reapplyEditedSceneQuality: { manager.reapplyEditedSceneQuality() },
            clearAllCaches: {
                await withCheckedContinuation { continuation in
                    manager.clearAllCaches { continuation.resume() }
                }
                // 清除缓存显式清单：逐 namespace 实例级清空（内存 + 磁盘），
                // 不再依赖共享目录整根互殃；Pixabay两份缩略图缓存一并纳入。
                for cache in [VideoLibraryThumbnailStore.sharedCache, SILThumbnailStore.sharedCache,
                              PixabayDownloadedThumbnailStore.sharedCache] {
                    await withCheckedContinuation { continuation in
                        cache.clearAll { continuation.resume() }
                    }
                }
                await withCheckedContinuation { continuation in
                    SteamWorkshopService.shared.clearAllCachedState { continuation.resume() }
                }
                await OnlineImageThumbnailCache.shared.clearAll()
                let preview = MainWindowCoordinator.mainWindowController?.closePreviewForCacheClear()
                await OnlineImageLibrary.shared.clearOriginalPreviewCache(after: preview).value
            },
            exportPersonalSettings: { [weak self] url in
                guard let coordinator = self?.personalSettings else { throw PersonalSettingsError.recoveryRequired(String(localized: "Settings export isn’t ready yet")) }
                return try await coordinator.exportPersonalSettings(to: url)
            },
            importPersonalSettings: { [weak self] url in
                guard let coordinator = self?.personalSettings else { throw PersonalSettingsError.recoveryRequired(String(localized: "Settings import isn’t ready yet")) }
                return try await coordinator.importPersonalSettings(from: url)
            },
            refreshAutoSwitchTimerIfNeeded: { manager.refreshAutoSwitchTimerIfNeeded() },
            resetToFreshInstallState: { [weak self] in
                ScreenSaverCoordinator.shared.cancel()
                self?.resetAction?()
            },
            setLoopPlaybackEnabled: { manager.setLoopPlaybackEnabled($0) },
            setRandomPlaybackEnabled: { manager.setRandomPlaybackEnabled($0) },
            setSequentialPlaybackEnabled: { manager.setSequentialPlaybackEnabled($0) },
            setSyncSystemWallpaperEnabled: { manager.setSyncSystemWallpaperEnabled($0) },
            startAutoSwitchTimer: { manager.startAutoSwitchTimer() },
            stopAutoSwitchTimer: { manager.stopAutoSwitchTimer() },
            updateLoginItemStatus: { manager.updateLoginItemStatus() },
            openScreenSaverSettings: { [weak self] in
                ScreenSaverWindowController.shared.show(relativeTo: self?.view.window)
            },
            updateVolume: { manager.updateVolume($0) },
            openProjectWebsite: {
                NSWorkspace.shared.open(URL(string: "https://github.com/songziqiang9512/MyWallpaperX")!)
            },
            checkForUpdates: { AppUpdateController.shared.checkForUpdates($0) },
            automaticUpdateChecksEnabled: { AppUpdateController.shared.automaticUpdateChecksEnabled },
            automaticUpdateDownloadsEnabled: { AppUpdateController.shared.automaticUpdateDownloadsEnabled },
            setAutomaticUpdateDownloadsEnabled: { AppUpdateController.shared.setAutomaticUpdateDownloadsEnabled($0) },
            setAutomaticUpdateChecksEnabled: { AppUpdateController.shared.setAutomaticUpdateChecksEnabled($0) }
        )
    }()

    // E2d: 单一装配（lazy settingsView 复用同一 actions），Steam 缓存
    // 清理由 App 动作层执行——Shared 视图不再直呼 Modules 单例。
    private lazy var settingsView = AppKitSettingsContainerView(
        dependency: AppSettingsPanelDependency(
            settings: WallpaperManager.shared.settings,
            actions: settingsActions
        ),
        visibleSection: .system
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebar = NSSplitViewItem(sidebarWithViewController: navigation)
        sidebar.minimumThickness = SettingsPanelLayout.sidebarWidth
        sidebar.maximumThickness = SettingsPanelLayout.sidebarWidth
        sidebar.canCollapse = false
        sidebar.allowsFullHeightLayout = true
        addSplitViewItem(sidebar)

        let body = NSViewController()
        body.view = settingsView
        let detail = NSSplitViewItem(viewController: body)
        detail.minimumThickness = 400
        addSplitViewItem(detail)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        navigation.onCategory = { [weak self] in self?.selectCategory($0) }
        navigation.select(settingsView.visibleSection)

        settingsView.interfaceForm.playlists = {
            MyWallpaperXApplication.libraryWorkspace?.relationships.playlists.map { ($0.id, $0.name) } ?? []
        }
        bindSettingsAuthority()
        let manager = WallpaperManager.shared
        settingsView.reapplySceneQualityButton.isEnabled = manager.canReapplySceneQuality
        MyWallpaperXApplication.libraryWorkspace?.playbackChanges
            .sink { [weak self] in self?.settingsView.reapplySceneQualityButton.isEnabled = manager.canReapplySceneQuality }
            .store(in: &cancellables)
    }

    private func selectCategory(_ category: AppSettingsSection) {
        guard settingsView.visibleSection != category else { return }
        if let window = view.window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            window.makeFirstResponder(nil)
        }
        if category == .interface { settingsView.interfaceForm.refreshStartupPages() }
        settingsView.showSection(category)
        view.window?.title = category.title
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
        if settingsView.visibleSection == .interface { settingsView.interfaceForm.refreshStartupPages() }
        settingsView.refreshFromState()
        settingsView.reapplySceneQualityButton.isEnabled = WallpaperManager.shared.canReapplySceneQuality
        settingsView.refreshUpdaterControls()
    }
}
