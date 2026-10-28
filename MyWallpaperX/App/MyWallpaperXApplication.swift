//
//  MyWallpaperXApplication.swift
//  MyWallpaperX
//

import AppKit
import Combine

@main
enum MyWallpaperXApplication {
    /// App owns this one launch result. Shell receives it explicitly after
    /// startup; it is never inferred from an empty relationship snapshot.
    @MainActor private(set) static var libraryWorkspace: WallpaperLibraryWorkspace?
    @MainActor private(set) static var downloadTasks: DownloadTasksController?
    @MainActor private(set) static var personalSettings: PersonalSettingsImportCoordinator?
    @MainActor private static var personalSettingsSubscriptions = Set<AnyCancellable>()
    @MainActor private static var personalSettingsRecoveryURL: URL?
    @MainActor private static var isPreparingLibraryTermination = false
    @MainActor private(set) static var userCollectionsStartup: LibraryCollectionsStartupOutcome?
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
#if DEBUG
        let usesDirectPlaybackHarness = (DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample
            && !DebugWebPlaybackRunner.requiresProductCoordinator)
            || (DebugScenePlaybackRunner.runsIsolatedSceneSample && !DebugSceneDaemonClientRunner.requiresProductCoordinator)
            || (DebugSceneDaemonClientRunner.isRequested && !DebugSceneDaemonClientRunner.requiresProductCoordinator)
            || DebugSystemMediaRunner.isRequested
#else
        let usesDirectPlaybackHarness = false
#endif
        if !usesDirectPlaybackHarness {
            do {
                let paths = try LibraryCollectionsStartupPaths.applicationPaths()
                let needsViewPreferencesSeed = UserDefaults.standard.object(forKey: WallpaperLibraryPresentation.settingsKey) == nil
                userCollectionsStartup = try LibraryCollectionsStartupAdmission.waitForResult {
                    try await LibraryCollectionsStartupAdmission.prepare(paths: paths, needsViewPreferencesSeed: needsViewPreferencesSeed)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "资料库启动未完成"
                alert.informativeText = error.localizedDescription
                _ = runAppAlert(alert)
                return
            }
        }
        if !usesDirectPlaybackHarness, let paths = try? LibraryCollectionsStartupPaths.applicationPaths() {
            let recoveryURL = paths.publication.finalDatabaseURL.deletingLastPathComponent().appendingPathComponent("personal-settings-import.json")
            personalSettingsRecoveryURL = recoveryURL
            let pending = FileManager.default.fileExists(atPath: recoveryURL.path)
            // Before either singleton can run destructive missing-file cleanup.
            WallpaperManager.defersMissingFileCleanupForPersonalSettingsRecovery = pending
            SILService.defersMissingFileCleanupForPersonalSettingsRecovery = pending
        }
        let recoveryMessage = userCollectionsStartup?.recoveryMessage
        WallpaperManager.startupMigrationRecoveryMessage = recoveryMessage
        WallpaperIndexStore.startupMigrationReadOnly = recoveryMessage != nil
        SILService.startupMigrationRecoveryMessage = recoveryMessage
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
        // Prepare the optional empty Web process through the product intent owner.
        if let adapter = WallpaperEngine.shared.dedicatedWebHostAdapter
            as? WebDaemonHostAdapter {
            adapter.mayPrepareIdleProcess = {
                !SceneDaemonClient.shared.hasRetainedOrRetiringTransport
            }
            SteamWorkshopService.shared.prepareWebPlaybackProcess = { [weak adapter] pending in
                let manager = WallpaperManager.shared
                guard pending.ticket.runtime == .web, manager.acceptsLibraryPlayback(pending) else { return nil }
                let id = adapter?.availablePreparedRequestID ?? UUID()
                let epoch = pending.ticket.epoch
                WallpaperEngine.shared.adoptIntentEpoch(epoch)
                adapter?.prepareProcess(requestID: id)
                return (
                    requestID: id,
                    cancel: { [weak adapter] in
                        adapter?.cancelPreparedProcess(requestID: id)
                        if WallpaperManager.shared.playbackIntentEpoch == epoch,
                           !WallpaperManager.shared.hasTransferredWebPreparation(epoch: epoch) {
                            manager.switchFailed(pending.ticket, reason: "Web 资源准备失败，已保留原壁纸")
                        }
                    },
                    isCurrent: { manager.acceptsLibraryPlayback(pending) },
                    intentEpoch: epoch
                )
            }
        }
        let prepareImportedVideo: (WallpaperReference, WallpaperPlaybackSequence.Pending?) -> ImportedVideoPlaybackAdmission? = { reference, pending in
            WallpaperManager.shared.admitImportedVideoPlayback(reference: reference, libraryPending: pending)
        }
        SteamWorkshopService.shared.prepareVideoPlaybackIntent = prepareImportedVideo
        PixabayService.shared.prepareVideoPlaybackIntent = prepareImportedVideo
        // Terminal history remains active when the main library window is
        // closed. Sources publish facts; this one App-owned consumer saves them.
        downloadTasks = DownloadTasksController(steam: .shared, pixabay: .shared, images: .shared)
        let requestLibraryPlayback: (WallpaperReference) -> Void = { reference in
            libraryWorkspace?.requestSingle(reference)
        }
        SteamWorkshopService.shared.requestLibraryPlayback = requestLibraryPlayback
        PixabayService.shared.requestLibraryPlayback = requestLibraryPlayback
        let prepareLibraryRestoration: (WallpaperReference) -> (() -> Void)? = { reference in
            guard let workspace = libraryWorkspace else { return nil }
            return WallpaperLibraryCommands.makeExplicitLibraryRestorationReceipt(for: reference, in: workspace)
        }
        SteamWorkshopService.shared.prepareExplicitLibraryRestoration = prepareLibraryRestoration
        PixabayService.shared.prepareExplicitLibraryRestoration = prepareLibraryRestoration
        SteamWorkshopService.shared.prepareSceneDownloadRemoval = { recordID, completion in
            WallpaperManager.shared.prepareSceneDownloadRemoval(recordID: recordID, completion: completion)
        }
        SteamWorkshopService.shared.prepareScenePlaybackIntent = { recordID, newSelection, pending in
            let manager = WallpaperManager.shared
            guard let ticket = manager.claimScenePlaybackIntent(recordID: recordID, newSelection: newSelection, libraryPending: pending) else { return nil }
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
        if !usesDirectPlaybackHarness, let startup = userCollectionsStartup {
            WallpaperManager.shared.configureRuntimeSwitching()
            libraryWorkspace = WallpaperLibraryWorkspace(startup: startup, manager: .shared, images: .shared,
                                                         steam: .shared, pixabay: .shared, defaults: .standard)
            configurePersonalSettings()
        }
        app.run()
    }

    @MainActor private static func configurePersonalSettings() {
        guard let workspace = libraryWorkspace, let collections = workspace.collections, let url = personalSettingsRecoveryURL else { return }
        let coordinator = PersonalSettingsImportCoordinator(manager: .shared, images: .shared, collections: collections,
            recoveryURL: url,
            readVideoSort: { [weak workspace] in
                guard let workspace else { throw UserCollectionsError.staleResetEpoch }
                return try workspace.presentation.videoSortPreference()
            }, validateVideoSort: { [weak workspace] patch, epoch in
                guard let workspace else { throw UserCollectionsError.staleResetEpoch }
                try workspace.presentation.validateVideoSortPatch(patch, resetEpoch: epoch)
            }, applyVideoSort: { [weak workspace] patch, epoch in
                guard let workspace else { throw UserCollectionsError.staleResetEpoch }
                try workspace.presentation.applyVideoSortPatch(patch, resetEpoch: epoch)
            }, beforeApply: { WallpaperManager.shared.stopCurrentPlayback() })
        personalSettings = coordinator
        workspace.setPersonalSettingsReady(coordinator.allowsEditing)
        coordinator.$isApplying.combineLatest(coordinator.$recoveryMessage).receive(on: DispatchQueue.main)
            .sink { [weak workspace] applying, recovery in workspace?.setPersonalSettingsReady(!applying && recovery == nil && !isPreparingLibraryTermination) }
            .store(in: &personalSettingsSubscriptions)
        SettingsWindowController.shared.configurePersonalSettings(coordinator, reset: { resetLibrary() })
        WallpaperManager.shared.$didFinishInitialIndexLoad.filter { $0 }.prefix(1)
            .sink { [weak coordinator, weak workspace] _ in
                Task { @MainActor in
                    do {
                        guard let coordinator, let collections = workspace?.collections else { return }
                        let epoch = collections.snapshot.resetEpoch
                        _ = try await coordinator.resumeIfNeeded()
                        guard coordinator.allowsEditing, collections.snapshot.resetEpoch == epoch else { return }
                        try await collections.pruneUnreferencedPlaylistCoverAssets(expectedEpoch: epoch)
                    }
                    catch { workspace?.presentation.report(error) }
                }
            }.store(in: &personalSettingsSubscriptions)
    }

    @MainActor private static func resetLibrary() {
        guard let workspace = libraryWorkspace, let collections = workspace.collections, let profile = personalSettings else { return }
        workspace.presentation.setEditingAllowed(false)
        Task { @MainActor in
            do {
                try await collections.reset(beforeStoreReset: {
                    profile.cancelForReset()
                    // The existing owner revokes source/ticket callbacks and
                    // tells restoration while the OLD relationship epoch exists.
                    WallpaperManager.shared.resetToFreshInstallState()
                })
                try profile.clearRecoveryAfterReset()
                workspace.presentation.resetViewState()
                workspace.setPersonalSettingsReady(true)
            } catch {
                workspace.setPersonalSettingsReady(profile.allowsEditing)
                workspace.presentation.report(error)
                presentAppAlert(makeAppAlert(title: "重置未完成", message: error.localizedDescription), in: MainWindowCoordinator.mainWindow())
            }
        }
    }

    @MainActor static func prepareLibraryForTermination() {
        isPreparingLibraryTermination = true
        personalSettings?.prepareForTermination()
        libraryWorkspace?.setPersonalSettingsReady(false)
    }

    @MainActor static func cancelLibraryTermination() {
        isPreparingLibraryTermination = false
        libraryWorkspace?.setPersonalSettingsReady(personalSettings?.allowsEditing ?? true)
    }

    @MainActor static func flushLibraryBeforeTermination() async -> String? {
        return await libraryWorkspace?.flush()
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
