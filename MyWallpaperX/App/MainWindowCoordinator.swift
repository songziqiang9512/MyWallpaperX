//
//  MainWindowCoordinator.swift
//  MyWallpaperX
//

import AppKit

// 集中管理主窗口、Dock 图标和前台激活策略，避免窗口生命周期逻辑散落到多个入口。
// 菜单命令语义在 MainWindowMenuCommands，播放路由观察者在
// MainWindowCoordinator+PlaybackRouting.swift；本文件保留状态存储、
// 播放通知与窗口生命周期。
enum MainWindowCoordinator {
    // 供同类型 extension（+PlaybackRouting）与 MainWindowMenuCommands 读写，故为 internal。
    static var mainWindowController: MainWindowController?
    static var wallpaperManager: WallpaperManager = .shared
    static var observerTokens: [NSObjectProtocol] = []

    static func setDockIconVisible(_ visible: Bool, keepInDock: Bool? = nil) {
        let shouldShow = visible || (keepInDock ?? wallpaperManager.settings.keepDockIconVisible)
        let targetPolicy: NSApplication.ActivationPolicy = shouldShow ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }

    static func mainWindow() -> NSWindow? {
        mainWindowController?.window
    }

    static func activateMainWindow() {
        // 优先复用现有 controller / window，避免重复创建导致状态丢失。
        if let controller = mainWindowController {
            controller.showWindow(nil)
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
        // The window is hidden, not retired: keep its controller so the Dock or
        // an app reopen reuses the same live composition instead of reviving a
        // closed window whose subscriptions were already torn down.
        resetModuleStateForClosedMainWindow()
        setDockIconVisible(false)
    }

    private static func resetModuleStateForClosedMainWindow() {
        NotificationCenter.default.post(
            name: .pixabayModeDidChange,
            object: nil,
            userInfo: ["enabled": false]
        )
        NotificationCenter.default.post(
            name: .steamWorkshopModeDidChange,
            object: nil,
            userInfo: ["enabled": false]
        )
    }

    private static func makeMainWindowController() -> MainWindowController {
        let controller = MainWindowController(wallpaperManager: wallpaperManager)
        mainWindowController = controller
        return controller
    }

}
