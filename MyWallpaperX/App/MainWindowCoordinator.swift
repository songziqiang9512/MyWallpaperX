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

    static func activateMainWindow() {
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

}
