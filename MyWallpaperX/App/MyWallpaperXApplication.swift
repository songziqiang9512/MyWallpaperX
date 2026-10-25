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
            || DebugWebPlaybackRunner.isStartupMeasurementRequested
    }
#endif

    @MainActor
    static func main() {
#if DEBUG
        var debugStartupPrefixUptimes: [String: UInt64]? = nil
        if SceneDaemonRuntime.isRequested,
           ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-startup-prefix") {
            debugStartupPrefixUptimes = [
                "entryObserved": UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
            ]
        }
        let startupMeasurementRequested = DebugWebPlaybackRunner.isStartupMeasurementRequested
            || DebugSceneProductEntryPolicy.isStartupMeasurementRequested(
                arguments: ProcessInfo.processInfo.arguments)
        let dedicatedStartupMain = Bundle.main.bundleIdentifier
            == "com.songziqiang.MyWallpaperX.Debug.Startup"
            && !WebDaemonRuntime.isRequested && !SceneDaemonRuntime.isRequested
        if (startupMeasurementRequested || dedicatedStartupMain)
            && !DebugWebPlaybackRunner.hasIsolatedStartupEnvironment {
            NSLog("MWX STARTUP: dedicated test bundle identity, standard-defaults token and isolated HOME/Library/cache/workshop/report required")
            return
        }
#endif
        if WebDaemonRuntime.isRequested || SceneDaemonRuntime.isRequested {
            _ = DaemonParentLifetime.shared
        }
#if DEBUG
        if debugStartupPrefixUptimes != nil {
            debugStartupPrefixUptimes?["appKitBegin"] = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
        }
#endif
        let app = NSApplication.shared
#if DEBUG
        if debugStartupPrefixUptimes != nil {
            debugStartupPrefixUptimes?["appKitReturned"] = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
        }
#endif
        if WebDaemonRuntime.isRequested {
            guard let runtime = WebDaemonRuntime() else { return }
            runtime.configure()
            withExtendedLifetime(runtime) { app.run() }
            return
        }
        if SceneDaemonRuntime.isRequested {
#if DEBUG
            if debugStartupPrefixUptimes != nil {
                debugStartupPrefixUptimes?["runtimeBegin"] = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
            }
#endif
            let runtime = SceneDaemonRuntime()
#if DEBUG
            if debugStartupPrefixUptimes != nil {
                debugStartupPrefixUptimes?["runtimeReturned"] = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
                runtime.debugStartupPrefixUptimes = debugStartupPrefixUptimes
                debugStartupPrefixUptimes = nil
            }
#endif
            runtime.configure()
            runtime.loadSceneFromArgumentsIfPresent()
            withExtendedLifetime(runtime) { app.run() }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
#if DEBUG
        let usesDirectPlaybackHarness = (DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample
            && !DebugWebPlaybackRunner.requiresProductCoordinator)
            || (DebugScenePlaybackRunner.runsIsolatedSceneSample && !DebugSceneDaemonClientRunner.requiresProductCoordinator)
            || (DebugSceneDaemonClientRunner.isRequested && !DebugSceneDaemonClientRunner.requiresProductCoordinator)
            || DebugSystemMediaRunner.isRequested
#else
        let usesDirectPlaybackHarness = false
#endif
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
        // Prepare the optional empty Web process through the product intent owner.
        if let adapter = WallpaperEngine.shared.dedicatedWebHostAdapter
            as? WebDaemonHostAdapter {
            adapter.mayPrepareIdleProcess = {
                !SceneDaemonClient.shared.hasRetainedOrRetiringTransport
            }
            SteamWorkshopService.shared.prepareWebPlaybackProcess = { [weak adapter] in
                let id = adapter?.availablePreparedRequestID ?? UUID()
                let epoch = WallpaperManager.shared.beginPlaybackIntent(runtime: .web)
                WallpaperEngine.shared.adoptIntentEpoch(epoch)
                adapter?.prepareProcess(requestID: id)
                return (
                    requestID: id,
                    cancel: { [weak adapter] in
                        adapter?.cancelPreparedProcess(requestID: id)
                        if WallpaperManager.shared.playbackIntentEpoch == epoch,
                           !WallpaperManager.shared.hasTransferredWebPreparation(epoch: epoch) {
                            WallpaperManager.shared.restoreCommittedPlaybackIntent()
                        }
                    },
                    isCurrent: { WallpaperManager.shared.playbackIntentEpoch == epoch },
                    intentEpoch: epoch
                )
            }
        }
        SteamWorkshopService.shared.prepareScenePlaybackIntent = { recordID, newSelection in
            let manager = WallpaperManager.shared
            guard let ticket = manager.claimScenePlaybackIntent(recordID: recordID, newSelection: newSelection) else { return nil }
            return (intentEpoch: ticket.epoch,
                isCurrent: { manager.playbackSwitch.pending?.selection.ticket == ticket
                    || (!newSelection && manager.playbackSwitch.committed?.ticket == ticket && manager.playbackSwitch.pending == nil) },
                cancel: { manager.switchFailed(ticket, reason: "Scene 资源准备失败") })
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
        WallpaperManager.shared.playbackIntentDidAdvance = { runtime in
            if runtime != .web {
                (WallpaperEngine.shared.dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.cancelIdlePreparation()
            }
            SceneDaemonClient.shared.invalidateRetainedTransport(for: runtime)
            SteamWorkshopService.shared.advanceWebLaunchIntentGeneration()
        }
#if DEBUG
        if (!runsIsolatedWebWorkshopSample || DebugWebPlaybackRunner.requiresProductCoordinator)
            && (!DebugScenePlaybackRunner.runsIsolatedSceneSample
                || DebugSceneDaemonClientRunner.requiresProductCoordinator) {
            MainWindowCoordinator.configure(with: WallpaperManager.shared)
        }
#else
        MainWindowCoordinator.configure(with: WallpaperManager.shared)
#endif
#if DEBUG
        if DebugWebPlaybackRunner.isStartupMeasurementRequested
            || DebugSceneProductEntryPolicy.isStartupMeasurementRequested(
                arguments: ProcessInfo.processInfo.arguments) {
            // Product transaction stays enabled, but a fresh HOME must not
            // start bundled Video before the measured Workshop selection.
            WallpaperManager.shared.settings.restorePlaybackOnLaunch = false
            NSLog("MWX STARTUP: launch replay suppressed for isolated product-entry measurement")
        }
#endif
        if !usesDirectPlaybackHarness { WallpaperManager.shared.configureRuntimeSwitching() }
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
            as? WebDaemonHostAdapter
        return WebWallpaperDataStoreReclaimer.LiveUsage(
            activeRecordIDs: webHostAdapter?.activeRecordIDs ?? [],
            inUsePersistentDataStoreIdentifiers: webHostAdapter?.inUsePersistentDataStoreIdentifiers ?? []
        )
    }

    /// Project current root candidates without parsing author content. The
    /// reclaimer keeps these input facts; UUID expansion runs only for deletion.
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
