//
//  MyWallpaperXApplication.swift
//  MyWallpaperX
//

import AppKit

@main
enum MyWallpaperXApplication {
#if DEBUG
    private static var runsIsolatedWebWorkshopSample: Bool {
        ProcessInfo.processInfo.arguments.contains("--mwx-debug-run-web-workshop-id")
    }
#endif

    @MainActor
    static func main() {
        // M5.2：daemon 模式（同二进制，契约
        // docs/scene/scene-runtime-daemon-contract.md §2）——accessory
        // App、跳过主 UI 装配、stdin 命令循环驱动 Scene 引擎。
        let runtime = SceneDaemonRuntime()
        if runtime.isDaemonModeRequested {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            _ = runtime.configureAndRun()
            runtime.loadSceneFromArguments()
            app.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
#if DEBUG
        if !runsIsolatedWebWorkshopSample
            && !DebugScenePlaybackRunner.runsIsolatedSceneSample {
            MainWindowCoordinator.configure(with: WallpaperManager.shared)
        }
#else
        MainWindowCoordinator.configure(with: WallpaperManager.shared)
#endif
        app.run()
    }
}
