//
//  WallpaperManager+Persistence.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperManager {
    private var defaults: UserDefaults { .standard }
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
        // 壁纸索引更新要比设置更谨慎：后台写盘 + 最近使用收口一起做。
        wallpapersAutoSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWallpapers()
            self.constrainRecentWallpapersToLibrary()
            self.saveRecentWallpapers()
        }
        wallpapersAutoSaveWorkItem = workItem
        // 合并短时间内大量 wallpaper 变更（尤其是缩略图补齐），减少重复全量写入。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func scheduleRecentWallpapersAutoPersist() {
        // 最近使用是高频写入数据，单独短延迟合并，避免每次切换都落盘。
        recentWallpapersAutoSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveRecentWallpapers()
        }
        recentWallpapersAutoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func loadSavedState() {
        // 启动恢复顺序固定：先最近使用，再当前壁纸，再播放状态，确保兜底链路可用。
        // 加载最近播放列表
        loadRecentWallpapers()

        // 加载当前壁纸（依赖最近播放列表作为兜底来源）
        loadCurrentWallpaper()

        // 加载播放状态
        loadPlaybackState()
        loadActiveWallpaperRuntime()
    }

    func loadTags() {
        // 标签列表先读持久化值；没有的话再用默认标签种子补齐。
        let storedTags: [String]? = loadCodableValue(forKey: tagsKey)
        let wallpaperTags = wallpapers.flatMap(\.tags)

        if let storedTags {
            // 已持久化的 tags 保留用户排序；默认标签只在首次安装或缺失时作为种子。
            tags = normalizedTagList(storedTags + wallpaperTags)
            return
        }

        tags = normalizedTagList(WallpaperManager.defaultTags + wallpaperTags)
    }

    func loadWallpapers() {
        // #11 修复：SQLite 加载改为异步，不阻塞主线程。
        // 启动时先用 UserDefaults 旧数据（毫秒级）让后续 init() 链路立即可用。
        // 没有旧数据时 wallpapers 保持空数组，loadSampleData 会注入内置示例。
        if let legacyWallpapers: [VideoWallpaper] = loadCodableValue(forKey: wallpapersKey) {
            wallpapers = deduplicatedWallpapersByPath(legacyWallpapers.map(migratedBundledVideoWallpaper))
            scheduleMissingIndexedSourceFilesScan()
        }

        // 后台异步加载 SQLite 索引，完成后回主线程替换。
        // init() 剩余链路（loadSampleData/loadTags/restorePlaybackState）基于同步阶段数据执行，
        // SQLite 回填后只替换 wallpapers 数组，不重新走整个启动链路。
        WallpaperIndexStore.shared.loadWallpapersAsync { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let sqliteWallpapers) where !sqliteWallpapers.isEmpty:
                let deduped = self.deduplicatedWallpapersByPath(self.migratedBundledVideoIndex(sqliteWallpapers))
                self.wallpapers = deduped
                self.scanForMissingMetadata()
                self.scheduleMissingIndexedSourceFilesScan()
                // SQLite 加载成功后清理旧 UserDefaults 冗余数据。
                UserDefaults.standard.removeObject(forKey: self.wallpapersKey)
                // 后台补填 fileSize（供「按大小排序」使用），避免主线程磁盘 I/O。
                let pathsNeedingSize = deduped.filter { $0.fileSize == nil }.map { $0.path }
                if !pathsNeedingSize.isEmpty {
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        var updates: [(path: String, size: Int64)] = []
                        for path in pathsNeedingSize {
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                               let size = attrs[.size] as? Int64 {
                                updates.append((path, size))
                            }
                        }
                        guard !updates.isEmpty else { return }
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            for update in updates {
                                let normalized = self.normalizedPath(update.path)
                                if let index = self.wallpapers.firstIndex(where: { self.normalizedPath($0.path) == normalized }) {
                                    self.wallpapers[index].fileSize = update.size
                                }
                            }
                        }
                    }
                }
            case .failure:
                // SQLite 不可用时继续用已加载的 UserDefaults 数据，并触发迁移。
                if !self.wallpapers.isEmpty {
                    self.migrateLegacyWallpaperIndexToSQLite(self.wallpapers)
                }
            default:
                break
            }
        }
    }

    func scheduleMissingIndexedSourceFilesScan() {
        missingIndexedSourceScanWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.wallpapers
            guard !snapshot.isEmpty else { return }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let missingWallpapers = snapshot.filter { !self.normalizedSourcePathExists($0.path) }
                guard !missingWallpapers.isEmpty else { return }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
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

    func loadWallpapersFromSQLiteIfAvailable() -> [VideoWallpaper]? {
        // SQLite 已经是主索引后端时，直接从它读，不再同时读旧 UserDefaults。
        guard let hasIndex = try? WallpaperIndexStore.shared.hasPersistedIndex(), hasIndex else {
            return nil
        }
        return try? WallpaperIndexStore.shared.loadWallpapers()
    }

    func migrateLegacyWallpaperIndexToSQLite(_ legacyWallpapers: [VideoWallpaper]) {
        // 迁移失败时保留旧路径，避免把用户库写成空。
        do {
            try WallpaperIndexStore.shared.saveWallpapers(legacyWallpapers)
            UserDefaults.standard.removeObject(forKey: wallpapersKey)
        } catch {
            // 迁移失败时保留旧索引，避免影响现有数据可用性。
        }
    }

    func hasPersistedWallpaperIndex() -> Bool {
        // 启动时判断是否已有壁纸索引，决定要不要注入内置示例。
        // #11 修复：不再在主线程同步查询 SQLite（queue.sync 会阻塞）。
        // 用两个轻量判断替代：内存中已有壁纸 OR UserDefaults 旧 key 存在。
        // SQLite 异步回填后 wallpapers 会被替换，loadSampleData 的去重逻辑保证不重复注入。
        if !wallpapers.isEmpty { return true }
        return defaults.object(forKey: wallpapersKey) != nil
    }

    func saveWallpapers() {
        // 壁纸索引先写 SQLite，失败再回退到旧存储，保证不会因为后端异常丢库。
        do {
            try wallpaperIndexStore.saveWallpapers(wallpapers)
            defaults.removeObject(forKey: wallpapersKey)
        } catch {
            // SQLite 不可用时兜底到旧存储路径，保证不丢数据。
            saveCodableValue(wallpapers, forKey: wallpapersKey)
        }
    }

    func saveTags() {
        // 标签单独持久化，避免和壁纸索引绑成一坨。
        saveCodableValue(tags, forKey: tagsKey)
    }

    func restorePlaybackState() {
        guard activeWallpaperRuntime == .video else { return }
        // 恢复播放状态只负责恢复当前播放项，不重新编排最近使用或标签状态。
        if let currentWallpaper = currentWallpaper {
            // 启动恢复只恢复播放，不重排最近使用列表，避免额外写盘和列表抖动。
            setAsWallpaper(
                currentWallpaper,
                userInitiated: false,
                recordHistory: false,
                updateRecentList: false
            )
        } else if !wallpapers.isEmpty {
            // 兜底：如果没有保存的当前壁纸，使用第一个壁纸
            let firstWallpaper = wallpapers[0]
            currentWallpaper = firstWallpaper
            // 启动恢复只恢复播放，不重排最近使用列表，避免额外写盘和列表抖动。
            setAsWallpaper(
                firstWallpaper,
                userInitiated: false,
                recordHistory: false,
                updateRecentList: false
            )
        }
    }

    func loadSettings() {
        // 设置是轻量配置，优先从 UserDefaults 读取；没有就使用默认值。
        if let loadedSettings: WallpaperSettings = loadCodableValue(forKey: settingsKey) {
            settings = loadedSettings
            if loadedSettings.volume > 0 {
                previousAudibleVolume = loadedSettings.volume
            }
        }
    }

    func saveSettings() {
        // 设置保存后只在暂停策略变化时推动引擎重新评估，避免无关字段连锁重建。
        saveCodableValue(settings, forKey: settingsKey)

        // 仅在暂停策略相关配置变化时同步到引擎，避免无关设置触发重复状态评估。
        let currentSnapshot = EnginePauseSettingsSnapshot(settings: settings)
        guard lastAppliedEnginePauseSettings != currentSnapshot else { return }
        lastAppliedEnginePauseSettings = currentSnapshot

        if !wallpapers.isEmpty {
            WallpaperEngine.shared.updateSettings(
                pauseWhenOtherAppFocused: currentSnapshot.pauseWhenOtherAppFocused,
                pauseWhenOtherAppFullscreen: currentSnapshot.pauseWhenOtherAppFullscreen,
                pauseWhenUnplugged: currentSnapshot.pauseWhenUnplugged,
                pauseWhenIdle: currentSnapshot.pauseWhenIdle,
                idleTimeoutMinutes: currentSnapshot.idleTimeoutMinutes
            )
        }
    }

    func loadCurrentWallpaper() {
        // 当前壁纸是快照引用：先尝试恢复原项，失败再从最近使用列表兜底。
        guard let savedWallpaper: VideoWallpaper = loadCodableValue(forKey: currentWallpaperKey) else {
            return
        }

        if let resolved = resolveExistingWallpaperFromSnapshot(savedWallpaper) {
            currentWallpaper = resolved
            if resolved.path != savedWallpaper.path { saveCurrentWallpaper() }
        } else {
            // 壁纸文件不存在，尝试从最近播放列表中找
            loadFromRecentWallpapers()
        }
    }

    func saveCurrentWallpaper() {
        // 当前壁纸只保存快照，不在这里额外改库内容。
        persistCurrentWallpaperSnapshot()
    }

    func loadRecentWallpapers() {
        guard let data = defaults.data(forKey: recentWallpapersKey),
              let savedWallpapers = decode([VideoWallpaper].self, from: data) else {
            return
        }

        // 最近使用是快照数据，启动时必须先做存在性清洗，再决定是否回写。
        recentlyUsedWallpapers = savedWallpapers.map(migratedBundledVideoWallpaper)
        normalizeRecentWallpapers(limit: WallpaperManager.recentWallpapersLimit, requireExistingFiles: true)

        // 仅在清洗后的结果与原持久化内容不一致时才回写，减少冷启动无意义写盘。
        if let normalizedData = encode(recentlyUsedWallpapers),
           normalizedData != data {
            defaults.set(normalizedData, forKey: recentWallpapersKey)
        }
    }

    func saveRecentWallpapers() {
        // 最近使用整体写回快照，供冷启动恢复和列表回填使用。
        saveCodableValue(recentlyUsedWallpapers, forKey: recentWallpapersKey)
    }

    func updateRecentWallpapers(_ wallpaper: VideoWallpaper) {
        // 最近使用只在“确实属于当前库”时更新，防止历史快照混入外部路径。
        if !(wallpapers.indices.contains(currentIndex) && wallpapers[currentIndex].id == wallpaper.id),
           !wallpapers.contains(where: { $0.id == wallpaper.id }) {
            return
        }
        let normalized = normalizedPath(wallpaper.path)
        if let first = recentlyUsedWallpapers.first,
           normalizedPath(first.path) == normalized {
            if first != wallpaper {
                recentlyUsedWallpapers[0] = wallpaper
                scheduleRecentWallpapersAutoPersist()
            }
            return
        }
        // 移除已存在的相同壁纸
        recentlyUsedWallpapers.removeAll { normalizedPath($0.path) == normalized }
        // 添加到列表开头
        recentlyUsedWallpapers.insert(wallpaper, at: 0)
        normalizeRecentWallpapers(limit: WallpaperManager.recentWallpapersLimit, requireExistingFiles: false)
        // 高频切换时合并写盘，避免每次切换都触发持久化。
        scheduleRecentWallpapersAutoPersist()
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

    func saveActiveWallpaperRuntime() {
        saveCodableValue(activeWallpaperRuntime, forKey: activeWallpaperRuntimeKey)
    }

    func loadFromRecentWallpapers() {
        // 当前壁纸丢失时，从最近使用里按可恢复快照兜底。
        // 从最近播放列表中找第一个可用的壁纸
        for wallpaper in recentlyUsedWallpapers {
            if let resolved = resolveExistingWallpaperFromSnapshot(wallpaper) {
                currentWallpaper = resolved
                return
            }
        }
        // 如果最近播放列表也没有可用的，使用兜底逻辑
        if !wallpapers.isEmpty {
            currentWallpaper = wallpapers[0]
        }
    }

    func flushPersistentState() {
        // 退出前统一刷盘，保证 settings / tags / walls / recent / playback 都同步落地。
        settingsAutoSaveWorkItem?.cancel()
        settingsAutoSaveWorkItem = nil
        wallpapersAutoSaveWorkItem?.cancel()
        wallpapersAutoSaveWorkItem = nil
        recentWallpapersAutoSaveWorkItem?.cancel()
        recentWallpapersAutoSaveWorkItem = nil
        saveSettings()
        saveTags()
        saveWallpapers()
        saveRecentWallpapers()
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

    private func saveCodableValue<T: Encodable>(_ value: T, forKey key: String) {
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
        // 这里的语义是“重新安装级重置”，所以必须清掉库、缓存、最近使用、标签和运行中状态。
        settingsAutoSaveWorkItem?.cancel()
        settingsAutoSaveWorkItem = nil
        wallpapersAutoSaveWorkItem?.cancel()
        wallpapersAutoSaveWorkItem = nil
        recentWallpapersAutoSaveWorkItem?.cancel()
        recentWallpapersAutoSaveWorkItem = nil
        pendingSystemWallpaperSyncWorkItem?.cancel()
        pendingSystemWallpaperSyncWorkItem = nil
        pendingManualNavigationWorkItem?.cancel()
        pendingManualNavigationWorkItem = nil
        missingIndexedAlertWorkItem?.cancel()
        missingIndexedAlertWorkItem = nil
        missingIndexedSourceScanWorkItem?.cancel()
        missingIndexedSourceScanWorkItem = nil

        clearSelectionState()
        selectedCategory = .myWallpapers
        selectedTag = nil
        searchQuery = ""
        isSearchFieldActive = false
        isDragSelecting = false
        currentIndex = 0
        isPlaying = true
        lastInteractiveWallpaperSetTime = 0
        lastManualNavigationAt = 0
        pendingManualNavigationDirection = nil
        pendingManualNavigationUserInitiated = false
        // #7 Manager 侧去重变量已移除，Engine 侧统一去重。
        playbackHistoryPaths.removeAll()

        settings = defaultSettings
        previousAudibleVolume = defaultSettings.volume
        tags = WallpaperManager.defaultTags
        wallpapers.removeAll()
        recentlyUsedWallpapers.removeAll()
        currentWallpaper = nil

        clearPreviewCacheArtifacts()
        WallpaperIndexStore.shared.resetStore()

        // 同步重置图片库（图片库无缩略图缓存，只清库数据和 UserDefaults）
        let sil = SILService.shared
        sil.wallpapers.removeAll()
        sil.silTags.removeAll()
        sil.sortState = SILSortState()
        sil.gridZoomOffset = 0
        sil.clearSelectionState()
        UserDefaults.standard.removeObject(forKey: "SILTags")
        UserDefaults.standard.removeObject(forKey: "SILSortState")
        UserDefaults.standard.removeObject(forKey: "SILGridZoomOffset")
        try? FileManager.default.removeItem(at: sil.silPersistenceURL)

        loadSampleData()
        restorePlaybackState()
        applyEngineSettings(reloadWallpaper: false)
        updateLoginItemStatus()
        flushPersistentState()
        NotificationCenter.default.post(name: .wallpaperManagerDidResetToFreshInstallState, object: self)
    }

}

extension WallpaperManager {
    func clearPreviewCacheArtifacts() {
        // 预览缓存是纯派生数据，重置时直接删目录并重建，避免旧缓存残留误命中。
        bumpCacheGeneration()
        clearThumbnailMemoryCache()
        clearThumbnailInFlight()
        clearStaticFrameSchedule()

        try? FileManager.default.removeItem(at: thumbnailCacheDirectory)
        try? FileManager.default.removeItem(at: staticFrameCacheDirectory)
        try? FileManager.default.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: staticFrameCacheDirectory, withIntermediateDirectories: true)
    }

    func normalizedTagList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        output.reserveCapacity(values.count)
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
        }
        return output
    }
}
