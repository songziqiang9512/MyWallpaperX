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
        // M0.2：公共静音权威从自身持久化值恢复；仅对旧版本 volume=0 做一次迁移。
        PlaybackMuteState.shared.migrateLegacyVolumeMuteIfNeeded(
            volume: WallpaperManager.shared.settings.volume
        )
#if DEBUG
        if !runsIsolatedWebWorkshopSample
            && (!DebugScenePlaybackRunner.runsIsolatedSceneSample
                || DebugSceneDaemonClientRunner.requiresProductCoordinator) {
            MainWindowCoordinator.configure(with: WallpaperManager.shared)
        }
#else
        MainWindowCoordinator.configure(with: WallpaperManager.shared)
#endif
        app.run()
    }
}
