//
//  MyWallpaperXApplication.swift
//  MyWallpaperX
//

import AppKit
import Combine

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
        // 直呼 Modules 的选择权威。previous/next 走跨引擎统一轮换
        // （视频库 + 工坊 web/scene）；其余动作仍由 Manager 分发。
        GlobalHotkeyManager.shared.systemHotkeyActionHandler = { action in
            switch action {
            case .previous, .next:
                CrossRuntimeWallpaperNavigator.navigate(
                    action == .next ? .next : .previous
                )
            default:
                WallpaperManager.shared.performSystemHotkeyAction(action)
            }
        }
        // E2c 站点 3: web host 的网络桥接白名单由 App 解析（Host 层不再
        // 直呼 SteamWorkshopService 单例）。
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
        // 工坊 web 记录删除/退订后回收其持久化 WKWebsiteDataStore：装配层把
        // downloads 投影与模块自身的删除意图一同翻译成 Host 事实（Host 不直呼
        // Modules 单例），派生算法、删除判定、宽限期复核与孤儿退役都留在 Host 层。
        // 订阅同步投递（不用 receive(on:)）：删除意图只在删除期间存在
        // （SteamWorkshopService.deleteDownloads 的 defer 会撤下它），延迟投递会
        // 让真删除被当成"无意图的投影缺席"而永不回收。
        // 宽限期末的复核现读在用事实（provider 在 work item 执行时调用）：30s 内
        // 新建的 surface / 新起播的记录只有在删除时刻仍被排除，WebKit 的
        // "WKWebView 仍在使用该 store 时不得删除" 契约才按实时状态成立。
        WebWallpaperDataStoreReclaimer.shared.liveUsageProvider = {
            liveWebDataStoreUsage()
        }
        webDataStoreReclaimerSubscription = SteamWorkshopService.shared.$downloads
            .sink { records in
                MainActor.assumeIsolated {
                    let liveUsage = liveWebDataStoreUsage()
                    WebWallpaperDataStoreReclaimer.shared.updateLiveRecords(
                        records
                            .filter { $0.contentType == .web }
                            .map(webPersistentDataStoreRecord(for:)),
                        screenIDs: NSScreen.screens.compactMap(
                            DedicatedWebWallpaperHostPlaceholderAdapter.screenID(for:)
                        ),
                        removalIntent: SteamWorkshopService.shared.removingDownloadIDs,
                        activeRecordIDs: liveUsage.activeRecordIDs,
                        inUsePersistentDataStoreIdentifiers: liveUsage.inUsePersistentDataStoreIdentifiers
                    )
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

    /// downloads 投影订阅（工坊 web 持久化 store 回收）：生命周期与进程一致。
    @MainActor
    private static var webDataStoreReclaimerSubscription: AnyCancellable?

    /// 回收复核与投影回调共用的在用事实：在播记录与在播 surface 实际持有的
    /// store 标识。投影回调把它当兜底快照投递，复核回调（liveUsageProvider）
    /// 用它现读删除时刻的事实——同一来源避免两处推导漂移。
    @MainActor
    private static func liveWebDataStoreUsage() -> WebWallpaperDataStoreReclaimer.LiveUsage {
        let webHostAdapter = WallpaperEngine.shared.dedicatedWebHostAdapter
            as? DedicatedWebWallpaperHostPlaceholderAdapter
        return WebWallpaperDataStoreReclaimer.LiveUsage(
            activeRecordIDs: Set([WallpaperEngine.shared.currentWebRecordID].compactMap { $0 }),
            inUsePersistentDataStoreIdentifiers: webHostAdapter?.inUsePersistentDataStoreIdentifiers ?? []
        )
    }

    /// 工坊 web 记录 → Host 层 store 身份。`rootPaths` 与创建侧同源：创建用的
    /// launch rootURL 就是 descriptor.effectiveRootURL，而它由
    /// `effectiveWebRootURL(for:entryURL:)` 求得（SteamWorkshopWebResolvedRuntimeModels.swift:18）。
    /// 这里只用 record 字段入口候选调用同一函数——缓存命中路径不构成第二个来源：
    /// 缓存有效期门强制 `manifest.execution.resolvedEntryPath == record.webEntryURL`
    /// 且 `effectiveRootPath == effectiveWebRootURL(record, record.webEntryURL)`
    /// （SteamWorkshopService+WebRuntimeCacheValidation.swift:76-88），record 入口候选
    /// 因此覆盖创建侧全部四个分支（webHostRootURL / projectFileURL 父目录 / 记录目录 /
    /// 入口父目录）。刻意不读运行时缓存：`loadCachedWebPlaybackContext` 会付
    /// project.json 解析与资源签名扫描（最多 120 文件 stat + 读取）的主线程同步代价，
    /// 而它对本集合逐字节冗余。再并上解析根 / 依赖宿主目录 / 记录目录作为宽集合——
    /// 宽集合只让在用 store 更不可能被误判为孤儿。
    @MainActor
    private static func webPersistentDataStoreRecord(
        for record: SteamWorkshopDownloadRecord
    ) -> DedicatedWebWallpaperHostPlaceholderAdapter.WebPersistentDataStoreRecord {
        var rootPaths: [String] = []
        func appendRoot(_ url: URL?) {
            guard let url else { return }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            if !rootPaths.contains(path) { rootPaths.append(path) }
        }
        let entryCandidates = [
            record.webEntryURL,
            record.webOwnEntryURL,
            record.webDependencyHostEntryURL
        ].compactMap { $0 }
        for entry in entryCandidates {
            appendRoot(SteamWorkshopService.shared.effectiveWebRootURL(for: record, entryURL: entry))
        }
        for root in [record.webHostRootURL, record.dependencyHostFolderURL, record.folderURL] {
            appendRoot(root)
        }
        return DedicatedWebWallpaperHostPlaceholderAdapter.WebPersistentDataStoreRecord(
            recordID: record.id,
            rootPaths: rootPaths
        )
    }
}
