//
//  SettingsWindowController.swift
//  MyWallpaperX
//

import AppKit
import Combine

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private static let windowWidth: CGFloat = 500
    private let contentController = SettingsContentViewController()
    private var hasShownWindow = false
    private var mainWindowTint: NSColor?

    private init() {
        let window = NSWindow(contentViewController: contentController)
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
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
        updateWindowSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showWindow() {
        contentController.loadViewIfNeeded()
        contentController.refresh()
        updateWindowSize()
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if !hasShownWindow {
            window.center()
            hasShownWindow = true
        }
        window.makeKeyAndOrderFront(nil)
        contentController.updateMainWindowTint(mainWindowTint, animated: false)
    }

    func updateMainWindowTint(_ tint: NSColor?, animated: Bool) {
        mainWindowTint = tint
        contentController.updateMainWindowTint(tint, animated: animated)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        contentController.updateMainWindowTint(mainWindowTint, animated: false)
    }

    func windowWillMiniaturize(_ notification: Notification) {
        contentController.updateMainWindowTint(mainWindowTint, animated: false)
    }

    func windowWillClose(_ notification: Notification) {
        contentController.updateMainWindowTint(mainWindowTint, animated: false)
    }

    /// The App supplies the same recovery owner used during startup/reset.
    func configurePersonalSettings(_ coordinator: PersonalSettingsImportCoordinator,
                                  reset: @escaping @MainActor () -> Void) {
        contentController.personalSettings = coordinator
        contentController.resetAction = reset
    }

    private func updateWindowSize() {
        guard let window else { return }
        let mainWindow = MainWindowCoordinator.mainWindow()
        // Detail height follows the main window's safe content area, rather than
        // a fixed ratio. Scale that shape to Settings' existing 500-point width.
        let hostHeight = mainWindow?.contentLayoutRect.height ?? MainWindowController.defaultContentSize.height
        let detailHeight = hostHeight - InspectorHostViewController.cardVerticalInset
        let preferredHeight = (Self.windowWidth * detailHeight / InspectorHostRequest.defaultPreferredWidth).rounded()
        let preferredScreen = hasShownWindow ? window.screen : mainWindow?.screen
        let screen = preferredScreen ?? mainWindow?.screen ?? window.screen ?? NSScreen.main
        let fittedHeight = min(preferredHeight, screen.map { $0.visibleFrame.height - 32 } ?? preferredHeight)
        let height = (fittedHeight * 0.92).rounded()
        let size = NSSize(width: Self.windowWidth, height: height)
        var frame = NSRect(x: window.frame.minX, y: window.frame.maxY - height, width: size.width, height: size.height)
        if let visibleFrame = screen?.visibleFrame {
            frame.origin.x = max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width))
            frame.origin.y = max(visibleFrame.minY, min(frame.minY, visibleFrame.maxY - frame.height))
        }
        window.minSize = size
        window.maxSize = size
        window.setFrame(frame, display: window.isVisible)
    }
}

private final class SettingsContentViewController: NSViewController {
    private var cancellables = Set<AnyCancellable>()
    private var isSyncingSettings = false
    weak var personalSettings: PersonalSettingsImportCoordinator?
    var resetAction: (@MainActor () -> Void)?

    private lazy var settingsActions: AppSettingsActions = {
        let manager = WallpaperManager.shared
        return AppSettingsActions(
            applyEngineSettings: { manager.applyEngineSettings(reloadWallpaper: $0) },
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
                guard let coordinator = self?.personalSettings else { throw PersonalSettingsError.recoveryRequired("设置导出尚未就绪") }
                return try await coordinator.exportPersonalSettings(to: url)
            },
            importPersonalSettings: { [weak self] url in
                guard let coordinator = self?.personalSettings else { throw PersonalSettingsError.recoveryRequired("设置导入尚未就绪") }
                return try await coordinator.importPersonalSettings(from: url)
            },
            refreshAutoSwitchTimerIfNeeded: { manager.refreshAutoSwitchTimerIfNeeded() },
            resetToFreshInstallState: { [weak self] in self?.resetAction?() },
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
        WallpaperManager.shared.$settings.map(\.libraryBackgroundStyle).removeDuplicates()
            .sink { [weak rootView] in rootView?.usesListTint = $0 == .listCoverTint }
            .store(in: &cancellables)
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

    func updateMainWindowTint(_ tint: NSColor?, animated: Bool) {
        guard isViewLoaded, let window = view.window, window.isVisible,
              !window.isMiniaturized, !NSApp.isHidden else { return }
        (view as? SettingsRootBackgroundView)?.setListTint(tint, animated: animated)
    }
}

private final class SettingsRootBackgroundView: NSView {
    private let tintLayer = CALayer()
    var usesListTint = false { didSet { updateBackground() } }
    private(set) var listTint: NSColor?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(tintLayer)
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

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
    }

    func setListTint(_ tint: NSColor?, animated: Bool) {
        listTint = tint
        updateBackground(animated: animated)
    }

    private func updateBackground(animated: Bool = false) {
        var backgroundColor = NSColor.windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .windowBackgroundColor
        }
        layer?.backgroundColor = backgroundColor.cgColor
        window?.backgroundColor = backgroundColor
        AppKitListBackgroundTint.apply(usesListTint ? listTint : nil, to: tintLayer,
            appearance: effectiveAppearance, animated: animated && usesListTint)
    }
}
