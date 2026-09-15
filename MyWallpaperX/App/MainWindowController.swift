//
//  MainWindowController.swift
//  MyWallpaperX
//

import AppKit
import QuickLookUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let wallpaperManager: WallpaperManager
    let toolbarController: VideoLibraryToolbarController
    private var hasShownWindow = false
    private let quickLookPreviewController = QuickLookPreviewController.shared
    /// 当前激活的模块，由 Shell 模块切换通知更新，供 performZoom 路由使用
    private var activeModule: ActiveModule = .videoLibrary
    private var observerTokens: [NSObjectProtocol] = []

    enum ActiveModule: Equatable, Sendable {
        case videoLibrary
        case staticImageLibrary
        case onlineLibrary
        case steamWorkshop
    }

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        let splitController = AppKitMainSplitViewController(wallpaperManager: wallpaperManager)

        let window = MainAppWindow(contentViewController: splitController)
        window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        window.title = "MyWallpaperX"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .shadow
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = true
        window.isRestorable = false
        // 主窗口保持普通桌面窗口语义，避免被系统当成辅助浮层窗口处理。
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        // 关闭窗口自动恢复链路，避免 restoreWindowWithIdentifier 相关噪音警告和误恢复。

        self.toolbarController = VideoLibraryToolbarController(window: window, wallpaperManager: wallpaperManager)
        super.init(window: window)
        shouldCascadeWindows = false
        self.window?.delegate = self
        configureQuickLookKeyHandling()
        observeModuleModeChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        // 只在首次显隐时居中；后续保持用户手动调整后的窗口位置。
        if !hasShownWindow {
            window.center()
            hasShownWindow = true
        }
        MainWindowCoordinator.activate(window: window)
    }

    func windowWillClose(_ notification: Notification) {
        (window as? MainAppWindow)?.quickLookKeyDownHandler = nil
        MainWindowCoordinator.handleWindowWillClose(self)
    }

    func performZoom(delta: Int) {
        switch activeModule {
        case .videoLibrary:
            toolbarController.performZoom(delta: delta)
        case .staticImageLibrary:
            toolbarController.staticImageLibraryToolbarController.performZoom(delta: delta)
        case .onlineLibrary:
            toolbarController.onlineLibraryToolbarController.performZoom(delta: delta)
        case .steamWorkshop:
            toolbarController.steamWorkshopToolbarController.performZoom(delta: delta)
        }
    }

    private func observeModuleModeChanges() {
        let staticEnableObserver = NotificationCenter.default.addObserver(
            forName: .staticImageLibraryModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
            if enabled {
                self?.activeModule = .staticImageLibrary
                MainWindowCoordinator.setActiveModule(.staticImageLibrary)
            }
        }
        observerTokens.append(staticEnableObserver)

        let onlineEnableObserver = NotificationCenter.default.addObserver(
            forName: .onlineLibraryModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
            if enabled {
                self?.activeModule = .onlineLibrary
                MainWindowCoordinator.setActiveModule(.onlineLibrary)
            }
        }
        observerTokens.append(onlineEnableObserver)

        let steamEnableObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
            if enabled {
                self?.activeModule = .steamWorkshop
                MainWindowCoordinator.setActiveModule(.steamWorkshop)
            }
        }
        observerTokens.append(steamEnableObserver)
        // 两个模块都不激活时恢复视频库
        // 同时通知 MainWindowCoordinator 回退，保证菜单路由状态一致。
        let staticDisableObserver = NotificationCenter.default.addObserver(
            forName: .staticImageLibraryModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool, !enabled else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeModule == .staticImageLibrary else { return }
                self.activeModule = .videoLibrary
                MainWindowCoordinator.clearActiveModuleIfMatches(.staticImageLibrary)
            }
        }
        observerTokens.append(staticDisableObserver)

        let onlineDisableObserver = NotificationCenter.default.addObserver(
            forName: .onlineLibraryModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool, !enabled else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeModule == .onlineLibrary else { return }
                self.activeModule = .videoLibrary
                MainWindowCoordinator.clearActiveModuleIfMatches(.onlineLibrary)
            }
        }
        observerTokens.append(onlineDisableObserver)

        let steamDisableObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool, !enabled else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeModule == .steamWorkshop else { return }
                self.activeModule = .videoLibrary
                MainWindowCoordinator.clearActiveModuleIfMatches(.steamWorkshop)
            }
        }
        observerTokens.append(steamDisableObserver)
    }

    private func configureQuickLookKeyHandling() {
        guard let window = window as? MainAppWindow else { return }
        // Quick Look 的键盘入口只放在窗口级别拦截，避免影响文本输入与集合视图默认键行为。
        window.quickLookKeyDownHandler = { [weak self] event in
            self?.handleQuickLookKeyDown(event) ?? false
        }
    }

    private func handleQuickLookKeyDown(_ event: NSEvent) -> Bool {
        // 只接管无修饰键的 Space / ESC，其余按键保持系统与控件默认分发。
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return false
        }
        if isEditingTextInput() {
            return false
        }

        // SIL 模式下将 Space / ESC 代理给图片库键盘处理器
        if activeModule == .staticImageLibrary {
            switch event.keyCode {
            case 49: return SILKeyboardHandler.shared.handleSpace()
            case 53: return SILKeyboardHandler.shared.handleEsc()
            default: return false
            }
        }

        // 在线库：已下载项页面支持 Space 预览
        if activeModule == .onlineLibrary && OnlineDownloadsBridge.shared.isActive {
            switch event.keyCode {
            case 49: OnlineDownloadsBridge.shared.previewSelected(); return true
            case 53: OLDownloadsQuickLookController.shared.close(); return true
            default: return false
            }
        }

        if activeModule == .steamWorkshop && SteamWorkshopDownloadsBridge.shared.isActive {
            switch event.keyCode {
            case 49: SteamWorkshopDownloadsBridge.shared.previewSelected(); return true
            case 53:
                guard SteamWorkshopDownloadsQuickLookController.shared.isVisible else { return false }
                SteamWorkshopDownloadsQuickLookController.shared.close()
                return true
            default: return false
            }
        }
        if activeModule == .steamWorkshop {
            // 浏览页没有 Quick Look 语义；把 Space/Esc 留给当前 Steam 控件，
            // 不得回落到此前本地壁纸选择的通用预览。
            return false
        }

        switch event.keyCode {
        case 49: // Space
            if event.isARepeat {
                return true
            }
            if quickLookPreviewController.isVisible {
                return true
            }
            return quickLookPreviewController.openPreview(for: wallpaperManager.selectedWallpaperForQuickLook)
        case 53: // ESC
            if quickLookPreviewController.isVisible {
                quickLookPreviewController.closePreview()
                return true
            }
            return false
        default:
            return false
        }
    }

    private func isEditingTextInput() -> Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        if let textView = keyWindow.firstResponder as? NSTextView, textView.isEditable {
            return true
        }
        return false
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        if activeModule == .staticImageLibrary {
            SILQuickLookController.shared.attach(to: panel)
        } else if activeModule == .onlineLibrary && OnlineDownloadsBridge.shared.isActive {
            OLDownloadsQuickLookController.shared.attach(to: panel)
        } else if activeModule == .steamWorkshop && SteamWorkshopDownloadsBridge.shared.isActive {
            SteamWorkshopDownloadsQuickLookController.shared.attach(to: panel)
        } else {
            QuickLookPreviewController.shared.attach(to: panel)
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        if activeModule == .staticImageLibrary {
            SILQuickLookController.shared.detach(from: panel)
        } else if activeModule == .onlineLibrary && OnlineDownloadsBridge.shared.isActive {
            OLDownloadsQuickLookController.shared.detach(from: panel)
        } else if activeModule == .steamWorkshop && SteamWorkshopDownloadsBridge.shared.isActive {
            SteamWorkshopDownloadsQuickLookController.shared.detach(from: panel)
        } else {
            QuickLookPreviewController.shared.detach(from: panel)
        }
    }
}

final class MainAppWindow: NSWindow {
    var quickLookKeyDownHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let quickLookKeyDownHandler,
           quickLookKeyDownHandler(event) {
            return
        }
        super.sendEvent(event)
    }
}
