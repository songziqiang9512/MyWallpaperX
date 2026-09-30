//
//  MainWindowCoordinator.swift
//  MyWallpaperX
//

import AppKit

// 集中管理主窗口、Dock 图标和前台激活策略，避免窗口生命周期逻辑散落到多个入口。
// 菜单命令语义在 MainWindowMenuCommands，播放路由观察者在
// MainWindowCoordinator+PlaybackRouting.swift；本文件保留状态存储、
// 菜单门面（AppDelegate 调用点不变）与窗口生命周期。
enum MainWindowCoordinator {
    // 供同类型 extension（+PlaybackRouting）与 MainWindowMenuCommands 读写，故为 internal。
    static var mainWindowController: MainWindowController?
    static var wallpaperManager: WallpaperManager = .shared
    static var isSteamDownloadsMode = false
    static var observerTokens: [NSObjectProtocol] = []

    // MARK: - 当前激活模块

    /// 当前激活的模块，由 MainWindowController 通过通知更新。
    /// MyWallpaperApp 的菜单命令通过此属性决定路由目标和启用状态。
    private(set) static var activeModule: MainWindowController.ActiveModule = .videoLibrary

    static func setActiveModule(_ module: MainWindowController.ActiveModule) {
        activeModule = module
    }

    /// 模块退出时，如果当前激活的正是该模块，则回退到视频库。
    static func clearActiveModuleIfMatches(_ module: MainWindowController.ActiveModule) {
        if activeModule == module {
            activeModule = .videoLibrary
        }
    }

    // MARK: - 菜单命令分发（门面；实现见 MainWindowMenuCommands）

    static var canUseVideoLibraryOnlyCommands: Bool { MainWindowMenuCommands.canUseVideoLibraryOnlyCommands }

    /// 「进入/退出多选」菜单项是否可用
    static var canToggleMultiSelect: Bool { MainWindowMenuCommands.canToggleMultiSelect }

    /// 「全选」菜单项是否可用
    static var canSelectAll: Bool { MainWindowMenuCommands.canSelectAll }

    static var revealInFinderMenuTitle: String { MainWindowMenuCommands.revealInFinderMenuTitle }

    /// 「设为壁纸」- 仅视频库
    static func menuSetAsWallpaper() { MainWindowMenuCommands.menuSetAsWallpaper() }

    /// 「切换上一张/下一张」——跨引擎统一轮换
    static func menuNavigate(_ direction: ManualNavigationDirection) { MainWindowMenuCommands.menuNavigate(direction) }

    /// 「收藏 / 取消收藏」- 仅视频库
    static func menuToggleFavorite() { MainWindowMenuCommands.menuToggleFavorite() }

    /// 「导入」- Cmd+O
    static func menuImport() { MainWindowMenuCommands.menuImport() }

    /// 「新建标签」- Cmd+N
    static func menuCreateTag() { MainWindowMenuCommands.menuCreateTag() }

    /// 「添加标签」
    static func menuAddTag() { MainWindowMenuCommands.menuAddTag() }

    /// 「添加标签」菜单项是否可用
    static var canAddTag: Bool { MainWindowMenuCommands.canAddTag }

    /// 「查看信息」
    static func menuShowInfo() { MainWindowMenuCommands.menuShowInfo() }

    /// 「查看信息」菜单项是否可用
    static var canShowInfo: Bool { MainWindowMenuCommands.canShowInfo }

    /// 「进入/退出多选」
    static func menuToggleMultiSelect() { MainWindowMenuCommands.menuToggleMultiSelect() }

    /// 「全选」
    static func menuSelectAll() { MainWindowMenuCommands.menuSelectAll() }

    /// 「删除选中」
    static func menuDeleteSelected() { MainWindowMenuCommands.menuDeleteSelected() }

    static var canDeleteSelected: Bool { MainWindowMenuCommands.canDeleteSelected }

    /// 「搜索」- 各模块聚焦搜索框
    static func menuFocusSearch() { MainWindowMenuCommands.menuFocusSearch() }

    /// 「查看文件」
    static func menuRevealInFinder() { MainWindowMenuCommands.menuRevealInFinder() }

    /// 「查看文件」菜单项是否可用
    static var canRevealInFinder: Bool { MainWindowMenuCommands.canRevealInFinder }

    /// 「预览」菜单项是否可用
    static var canPreview: Bool { MainWindowMenuCommands.canPreview }

    /// 菜单命令：预览选中项（QuickLook）
    static func menuPreview() { MainWindowMenuCommands.menuPreview() }

    static func setDockIconVisible(_ visible: Bool) {
        // Dock 图标显示状态必须和主窗口显隐同步，否则会出现“窗口关了但进程看起来还在前台”的错觉。
        let targetPolicy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }

    static func mainWindow() -> NSWindow? {
        if let window = mainWindowController?.window {
            return window
        }
        return NSApp.windows.first { window in
            window.identifier?.rawValue == "MainWindow"
        }
    }

    static func activateMainWindow(select category: Category? = nil) {
        if category == .settings {
            DispatchQueue.main.async {
                SettingsWindowController.shared.showWindow()
            }
            return
        }

        if let category {
            wallpaperManager.selectCategory(category)
        }

        // 优先复用现有 controller / window，避免重复创建导致状态丢失。
        if let controller = mainWindowController {
            controller.showWindow(nil)
            return
        }

        if let existingWindow = mainWindow() {
            activate(window: existingWindow)
            return
        }

        let controller = makeMainWindowController()
        controller.showWindow(nil)
    }

    static func activate(window: NSWindow) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                activate(window: window)
            }
            return
        }

        // 激活顺序固定：先恢复 Dock / App 激活态，再把窗口拉到最前并刷新播放状态。
        setDockIconVisible(true)
        window.level = .normal
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFront(nil)
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WallpaperEngine.shared.refreshPlaybackState()
        }
    }

    static func handleWindowWillClose(_ controller: MainWindowController) {
        if mainWindowController === controller {
            mainWindowController = nil
        }
        resetModuleStateForClosedMainWindow()
        // 关闭主窗口时隐藏 Dock 图标，维持“窗口即应用入口”的表现。
        setDockIconVisible(false)
    }

    private static func resetModuleStateForClosedMainWindow() {
        activeModule = .videoLibrary
        isSteamDownloadsMode = false

        NotificationCenter.default.post(
            name: .staticImageLibraryModeDidChange,
            object: nil,
            userInfo: ["enabled": false]
        )
        NotificationCenter.default.post(
            name: .onlineLibraryModeDidChange,
            object: nil,
            userInfo: ["enabled": false, "isDownloads": false]
        )
        NotificationCenter.default.post(
            name: .steamWorkshopModeDidChange,
            object: nil,
            userInfo: ["enabled": false, "isDownloads": false]
        )
    }

    private static func makeMainWindowController() -> MainWindowController {
        let controller = MainWindowController(wallpaperManager: wallpaperManager)
        mainWindowController = controller
        return controller
    }

    static func performZoom(delta: Int) {
        mainWindowController?.performZoom(delta: delta)
    }
}
