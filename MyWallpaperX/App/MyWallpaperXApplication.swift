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
        if SceneDaemonRuntime.isRequested {
            let runtime = SceneDaemonRuntime()
            runtime.configure()
            runtime.loadSceneFromArgumentsIfPresent()
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        PlaybackCommandMultiplexer.shared.register(VideoPlaybackCommandHandler())
        PlaybackCommandMultiplexer.shared.register(SceneDaemonClient.shared)
        // M0.2：公共静音权威启动种子（上次会话音量 ≤0 → 公共意图静音）。
        if WallpaperManager.shared.isMuted {
            PlaybackMuteState.shared.setMuted(true)
        }
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
