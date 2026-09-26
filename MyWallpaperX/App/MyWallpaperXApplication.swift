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
        let videoPlaybackHandler = VideoPlaybackCommandHandler()
        PlaybackCommandMultiplexer.shared.register(videoPlaybackHandler)
        // E2c: web 与 video 共享 WallpaperEngine 执行端（按活跃 kind 路由），
        // 别名注册使定向 `to: .web` 可达；广播按 handler 身份去重。
        PlaybackCommandMultiplexer.shared.register(videoPlaybackHandler, as: .web)
        PlaybackCommandMultiplexer.shared.register(SceneDaemonClient.shared)
        // E2d: 热键动作由 App 装配注入——Core 的 GlobalHotkeyManager 不再
        // 直呼 Modules 的选择权威。
        GlobalHotkeyManager.shared.systemHotkeyActionHandler = { action in
            WallpaperManager.shared.performSystemHotkeyAction(action)
        }
        // E2c 站点 3: web host 的网络桥接白名单由 App 解析（Host 层不再
        // 直呼 SteamWorkshopService 单例）。
        // E2b: 系统暂停评估结果的跨 runtime 下发归控制层——引擎只上报。
        NotificationCenter.default.addObserver(
            forName: WallpaperEngine.playbackSystemPauseDidChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let paused = notification.userInfo?["paused"] as? Bool else {
                return
            }
            PlaybackCommandMultiplexer.shared.dispatch(
                paused ? .pause : .resume,
                to: .scene
            )
        }
        if let adapter = WallpaperEngine.shared.dedicatedWebHostAdapter
            as? DedicatedWebWallpaperHostPlaceholderAdapter {
            adapter.allowedNetworkBridgeHostsResolver = { recordID in
                guard let record = SteamWorkshopService.shared.latestDownloadRecord(for: recordID),
                      let descriptor = SteamWorkshopService.shared.resolvedWebProjectDescriptor(for: record) else {
                    return []
                }
                return Set(descriptor.staticContentSummary.externalDependencyHosts
                    .compactMap(DedicatedWebWallpaperHostPlaceholderAdapter.normalizedNetworkBridgeHost))
            }
        }
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
