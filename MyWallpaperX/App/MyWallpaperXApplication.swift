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
