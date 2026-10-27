//
//  WallpaperManager+Persistence.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperManager {
    var defaults: UserDefaults { .standard }
    private var wallpaperIndexStore: WallpaperIndexStore { .shared }

    func scheduleSettingsAutoPersist() {
        // 设置项合并短延迟写盘，避免滑块和连续切换造成高频 UserDefaults 写入。
        settingsAutoSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveSettings()
        }
        settingsAutoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func scheduleWallpapersAutoPersist() {
        guard !preservesLegacyMigrationInputs else { return }
        // Initial publication already commits one complete snapshot explicitly.
        guard !initialIndexInternalPublication else { return }
        wallpapersAutoSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wallpapersAutoSaveWorkItem = nil
            self.saveWallpapers()
            // 库内容变化（导入/删除/SQLite 回填）后重臂自动切换 timer。
            // $wallpapers sink 在 @Published willSet 期触发，当时读到
            // 的还是旧库，必须等本 workItem 执行（新库已生效）再评估，
            // 否则"空库开启自动切换→导入壁纸"后 timer 继续静默死亡
            // 仅刷新已提交来源的时钟，不从初载/空库制造新播放来源。
            self.refreshAutoSwitchTimerIfNeeded()
        }
        wallpapersAutoSaveWorkItem = workItem
        // 合并短时间内大量 wallpaper 变更（尤其是缩略图补齐），减少重复全量写入。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }


    func loadSavedState() {
        // App restoration resolves the saved runtime after source publication.
        loadCurrentWallpaper()

        // 加载播放状态
        loadPlaybackState()
        loadActiveWallpaperRuntime()
        loadLastWorkshopPlaybackRecordID()
    }


    func loadWallpapers() {
        beginInitialIndexLoad()
        if let fallback: [VideoWallpaper] = loadCodableValue(forKey: wallpapersKey) {
            // A complete failed-save snapshot (including []) supersedes SQLite.
            didFinishInitialIndexLoad = true
            wallpapers = deduplicatedWallpapersByPath(fallback.map(migratedBundledVideoWallpaper))
            scheduleMissingIndexedSourceFilesScan()
            return
        }
        didFinishInitialIndexLoad = false
        wallpapers = initialIndexChanges.merged(with: initialIndexSeedWallpapers, materializePatches: true, normalize: normalizedPath)
        retryInitialIndexLoadIfNeeded()
    }

    func scheduleMissingIndexedSourceFilesScan() {
        missingIndexedSourceScanWorkItem?.cancel()
        guard !preservesLegacyMigrationInputs,
              !Self.defersMissingFileCleanupForPersonalSettingsRecovery else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !Self.defersMissingFileCleanupForPersonalSettingsRecovery else { return }
            let snapshot = self.wallpapers
            guard !snapshot.isEmpty else { return }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let missingWallpapers = snapshot.filter { !self.normalizedSourcePathExists($0.path) }
                guard !missingWallpapers.isEmpty else { return }

                DispatchQueue.main.async { [weak self] in
                    guard let self, !Self.defersMissingFileCleanupForPersonalSettingsRecovery else { return }
                    self.purgeMissingIndexedWallpapersFromLibrary(
                        missingWallpapers,
                        notifyUser: true
                    )
                }
            }
        }

        missingIndexedSourceScanWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func deduplicatedWallpapersByPath(_ source: [VideoWallpaper]) -> [VideoWallpaper] {
        // 旧索引或迁移数据可能带重复项，启动时先按标准化路径去重。
        var loaded: [VideoWallpaper] = []
        loaded.reserveCapacity(source.count)
        var seenPaths = Set<String>()
        for wallpaper in source {
            let dedupePath = URL(fileURLWithPath: wallpaper.path).standardizedFileURL.path
            if seenPaths.insert(dedupePath).inserted {
                loaded.append(wallpaper)
            }
        }
        return loaded
    }

    func hasPersistedWallpaperIndex() -> Bool {
        // 启动时判断是否已有壁纸索引，决定要不要注入内置示例。
        // #11 修复：不再在主线程同步查询 SQLite（queue.sync 会阻塞）。
        // 用两个轻量判断替代：内存中已有壁纸 OR UserDefaults 旧 key 存在。
        // SQLite 异步回填后 wallpapers 会被替换，loadSampleData 的去重逻辑保证不重复注入。
        if !wallpapers.isEmpty { return true }
        return defaults.object(forKey: wallpapersKey) != nil || defaults.data(forKey: initialIndexChangesKey) != nil
    }

    func saveWallpapers() {
        guard !preservesLegacyMigrationInputs else { return }
        guard didFinishInitialIndexLoad else {
            persistInitialIndexChanges()
            retryInitialIndexLoadIfNeeded()
            return
        }
        wallpaperIndexSaveRevision &+= 1
        pendingWallpaperIndexSave = WallpaperIndexSaveSnapshot(
            wallpapers: wallpapers, revision: wallpaperIndexSaveRevision, epoch: wallpaperIndexSaveEpoch
        )
        submitPendingWallpaperIndexSave()
    }

    private func submitPendingWallpaperIndexSave() {
        guard !preservesLegacyMigrationInputs else { return }
        guard wallpaperIndexSaveInFlight == nil, let request = pendingWallpaperIndexSave else { return }
        pendingWallpaperIndexSave = nil
        wallpaperIndexSaveInFlight = request
        wallpaperIndexStore.saveWallpapersAsync(request.wallpapers) { [weak self] result in
            guard let self, self.wallpaperIndexSaveInFlight?.revision == request.revision,
                  self.wallpaperIndexSaveInFlight?.epoch == request.epoch else { return }
            self.wallpaperIndexSaveInFlight = nil
            if self.wallpaperIndexSaveEpoch == request.epoch,
               self.wallpaperIndexSaveRevision == request.revision {
                self.applyWallpaperIndexSaveResult(result, snapshot: request.wallpapers)
            }
            self.submitPendingWallpaperIndexSave()
        }
    }

    private func applyWallpaperIndexSaveResult(_ result: Result<Void, Error>, snapshot: [VideoWallpaper]) {
        switch result {
        case .success:
            defaults.removeObject(forKey: wallpapersKey)
            clearInitialIndexRecoveryAfterSave()
        case .failure:
            saveCodableValue(snapshot, forKey: wallpapersKey)
        }
    }

    private func flushWallpaperIndex() {
        guard !preservesLegacyMigrationInputs else { return }
        // Settled saves need no second full-table write at exit. Retain the
        // original barrier for a debounced edit, unfinished write or recovery.
        guard !didFinishInitialIndexLoad || wallpapersAutoSaveWorkItem != nil
            || wallpaperIndexSaveInFlight != nil || pendingWallpaperIndexSave != nil
            || defaults.object(forKey: wallpapersKey) != nil else { return }
        wallpapersAutoSaveWorkItem?.cancel()
        wallpapersAutoSaveWorkItem = nil
        // A failed read retains the old DB and a versioned delta, never a partial full snapshot.
        guard settleInitialIndexForFlush() else { return }
        let snapshot = wallpapers
        do {
            try persistWallpaperIndexNow(snapshot)
        } catch {
            applyWallpaperIndexSaveResult(.failure(error), snapshot: snapshot)
        }
    }

    /// Explicit profile import and exit share the original serial SQLite owner.
    /// Revoke the old MainActor completion slots before the synchronous queue
    /// barrier, so an older pending snapshot cannot overwrite the imported one.
    func persistWallpaperIndexNow(_ snapshot: [VideoWallpaper]) throws {
        guard allowsLibraryMutation else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: migrationRecoveryMessage ?? "资料库需要恢复"])
        }
        guard didFinishInitialIndexLoad else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "资料库仍在载入，请载入完成后再保存完整索引。"])
        }
        wallpapersAutoSaveWorkItem?.cancel()
        wallpapersAutoSaveWorkItem = nil
        // 最新值排在已提交事务之后；退出不能等回主队列的旧 completion。
        wallpaperIndexSaveRevision &+= 1
        pendingWallpaperIndexSave = nil
        wallpaperIndexSaveInFlight = nil
        try wallpaperIndexStore.saveWallpapers(snapshot)
        applyWallpaperIndexSaveResult(.success(()), snapshot: snapshot)
    }

    private func invalidateWallpaperIndexPersistence() {
        wallpaperIndexSaveEpoch &+= 1
        invalidateInitialIndexLoad()
        didFinishInitialIndexLoad = true
        pendingWallpaperIndexSave = nil
        // 旧事务仍占原槽直至完成，避免连续 reset 堆积并行保存。
    }


    func loadSettings() {
        // 设置是轻量配置，优先从 UserDefaults 读取；没有就使用默认值。
        if let loadedSettings: WallpaperSettings = loadCodableValue(forKey: settingsKey) {
            settings = loadedSettings
            if loadedSettings.volume > 0 {
                previousAudibleVolume = loadedSettings.volume
            }
        }
        PlaybackPolicyController.shared.updateSettings(settings)
    }

    func saveSettings() {
        saveCodableValue(settings, forKey: settingsKey)
        PlaybackPolicyController.shared.updateSettings(settings)
    }

    /// Explicit import needs an acknowledgement, unlike the normal debounced
    /// writer. It uses the same UserDefaults key and cancels the old work item.
    func persistSettingsNow(_ snapshot: WallpaperSettings) throws {
        let data = try JSONEncoder().encode(snapshot)
        settingsAutoSaveWorkItem?.cancel()
        settingsAutoSaveWorkItem = nil
        defaults.set(data, forKey: settingsKey)
        guard defaults.synchronize(), defaults.data(forKey: settingsKey) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func loadCurrentWallpaper() {
        // A legacy success snapshot is a replay hint, never an import command.
        // The App waits for the authoritative index before resolving its ID.
        guard let savedWallpaper: VideoWallpaper = loadCodableValue(forKey: currentWallpaperKey) else { return }
        currentWallpaper = migratedBundledVideoWallpaper(savedWallpaper)
    }

    func saveCurrentWallpaper() {
        // 当前壁纸只保存快照，不在这里额外改库内容。
        persistCurrentWallpaperSnapshot()
    }




    func loadPlaybackState() {
        // 播放状态只有在持久化键存在时才覆盖内存态，避免首次启动被默认 false 误伤。
        guard defaults.object(forKey: playbackStateKey) != nil else { return }
        isPlaying = defaults.bool(forKey: playbackStateKey)
    }

    func savePlaybackState() {
        // 播放状态只记录开关，不额外记录引擎内部细节。
        defaults.set(isPlaying, forKey: playbackStateKey)
    }

    func loadActiveWallpaperRuntime() {
        guard let savedRuntime: ActiveWallpaperRuntime = loadCodableValue(forKey: activeWallpaperRuntimeKey) else {
            return
        }
        activeWallpaperRuntime = savedRuntime
    }

    /// 与写侧的 JSON 编码对称：loadCodableValue 解码 String?（历史遗留
    /// 的 null data 也解码为 nil）。
    func loadLastWorkshopPlaybackRecordID() {
        lastWorkshopPlaybackRecordID = loadCodableValue(forKey: lastWorkshopPlaybackRecordIDKey)
    }

    func saveActiveWallpaperRuntime() {
        saveCodableValue(activeWallpaperRuntime, forKey: activeWallpaperRuntimeKey)
    }

    func flushPersistentState() {
        // Flush source index, runtime intent and preferences. Store flushes relationships/history separately.
        settingsAutoSaveWorkItem?.cancel()
        settingsAutoSaveWorkItem = nil
        saveSettings()
        flushWallpaperIndex()
        savePlaybackState()
        saveActiveWallpaperRuntime()
        persistCurrentWallpaperSnapshot()
    }

    func persistCurrentWallpaperSnapshot() {
        // 当前壁纸只写一份可恢复快照；没有当前项时移除键值，避免旧值残留。
        if let currentWallpaper {
            saveCodableValue(currentWallpaper, forKey: currentWallpaperKey)
            return
        }
        defaults.removeObject(forKey: currentWallpaperKey)
    }

    private func loadCodableValue<T: Decodable>(forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return decode(T.self, from: data)
    }

    func saveCodableValue<T: Encodable>(_ value: T, forKey key: String) {
        if preservesLegacyMigrationInputs,
           [wallpapersKey, initialIndexChangesKey].contains(key) { return }
        // 写盘前先做编码和去重，减少相同数据反复写入。
        guard let data = encode(value) else { return }
        if defaults.data(forKey: key) == data {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    func resetToFreshInstallState() {
        guard allowsLibraryMutation else { reportMigrationReadOnly(); return }
        // 这里的语义是“重新安装级重置”，所以必须清掉库、缓存、最近使用、标签和运行中状态。
        invalidateWallpaperIndexPersistence()
        settingsAutoSaveWorkItem?.cancel()
        settingsAutoSaveWorkItem = nil
        wallpapersAutoSaveWorkItem?.cancel()
        wallpapersAutoSaveWorkItem = nil
        pendingSystemWallpaperSyncWorkItem?.cancel()
        pendingSystemWallpaperSyncWorkItem = nil
        pendingManualNavigationWorkItem?.cancel()
        pendingManualNavigationWorkItem = nil
        missingIndexedAlertWorkItem?.cancel()
        missingIndexedAlertWorkItem = nil
        missingIndexedSourceScanWorkItem?.cancel()
        missingIndexedSourceScanWorkItem = nil

        currentIndex = 0
        isPlaying = true
        lastInteractiveWallpaperSetTime = 0
        lastManualNavigationAt = 0
        pendingManualNavigationDirection = nil
        // #7 Manager 侧去重变量已移除，Engine 侧统一去重。

        settings = defaultSettings
        previousAudibleVolume = defaultSettings.volume
        // 全新安装级重置也必须清除独立静音意图；默认音量恢复 50% 后不能继续静音。
        PlaybackMuteState.shared.setMuted(false)
        wallpapers.removeAll()
        currentWallpaper = nil
        lastWorkshopPlaybackRecordID = nil

        // 重置是"重新安装级"：停掉任何运行中的壁纸——web/scene 不能在
        // 重置后继续播放，runtime 标记也不能被 flush 再次持久化（否则
        // 下次启动落入 web/scene 空转分支）。停止会把 isPlaying 压成
        // false，但初次安装语义是自动播放：恢复播放态再进示例注入，
        // App 唯一恢复 owner 随后在新目录/关系投影就绪后接纳示例。
        if activeWallpaperRuntime == .scene {
            SceneDaemonClient.shared.stop(postsLaunchState: false)
        }
        stopCurrentPlayback()
        activeWallpaperRuntime = .video
        isPlaying = true

        // Scene 帧率档与库 UI 状态同样属于"设置"，与 SIL 侧重置对齐，
        // 兑现"恢复所有设置为初次安装状态"的弹窗承诺。
        PlaybackPerformanceProfile.save(.standard)
        PlaybackCommandMultiplexer.shared.dispatch(
            .setPerformanceProfile(maxFPS: PlaybackPerformanceProfile.standard.maxFPS)
        )
        // Retired preferences are removed only by explicit fresh-install reset.
        for key in ["WallpaperTags", "RecentWallpapers", "PerSelectionSortStates", "gridZoomOffset"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        clearPreviewCacheArtifacts()
        WallpaperIndexStore.shared.resetStore()

        // 同步重置图片库（图片库无缩略图缓存，只清库数据和 UserDefaults）
        let sil = SILService.shared
        sil.invalidatePendingMetadataLoad()
        sil.wallpapers.removeAll()
        UserDefaults.standard.removeObject(forKey: "SILTags")
        UserDefaults.standard.removeObject(forKey: "SILSortState")
        UserDefaults.standard.removeObject(forKey: "SILGridZoomOffset")
        try? FileManager.default.removeItem(at: sil.silPersistenceURL)

        loadSampleData()
        libraryPlaybackResetRequested?()
        applyEngineSettings(reloadWallpaper: false)
        updateLoginItemStatus()
        flushPersistentState()
        NotificationCenter.default.post(name: .wallpaperManagerDidResetToFreshInstallState, object: self)
    }

}

extension WallpaperManager {
    func clearPreviewCacheArtifacts() {
        // 预览缓存可重建；仅保留当前桌面或退出恢复基线仍引用的文件。
        bumpCacheGeneration()
        clearThumbnailMemoryCache()
        clearThumbnailInFlight()
        clearStaticFrameSchedule()

        try? FileManager.default.removeItem(at: thumbnailCacheDirectory)
        clearUnprotectedStaticFrameFiles()
        try? FileManager.default.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: staticFrameCacheDirectory, withIntermediateDirectories: true)
    }

}
