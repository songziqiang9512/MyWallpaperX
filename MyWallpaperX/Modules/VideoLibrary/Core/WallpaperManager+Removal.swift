//
//  WallpaperManager+Removal.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperManager {
    struct RemovalRecord {
        let id: String
        let title: String
        let path: String
        let thumbnailPath: String?
        let staticFramePath: String?
    }

    func enqueueDeletionTask(_ task: @escaping () -> Void) {
        // 删除任务统一走后台队列，避免大批量移除时阻塞前台交互。
        deletionQueue.async(execute: task)
    }

    func removeWallpapers(
        _ wallpapersToRemove: [VideoWallpaper],
        in scope: WallpaperRemovalScope,
        completion: ((WallpaperDeletionSummary) -> Void)? = nil
    ) {
        // 删除按 scope 分流：库删除走异步派生资源清理，其他列表只移引用，不碰源文件。
        let uniqueWallpapers = deduplicatedWallpapers(wallpapersToRemove)
        guard !uniqueWallpapers.isEmpty else {
            completion?(WallpaperDeletionSummary(requestedCount: 0, removedCount: 0, failures: []))
            return
        }

        switch scope {
        case .library:
            removeLibraryWallpapers(uniqueWallpapers, completion: completion)
        case .recentlyUsed:
            removeRecentlyUsedWallpapers(uniqueWallpapers)
            completion?(WallpaperDeletionSummary(requestedCount: uniqueWallpapers.count, removedCount: uniqueWallpapers.count, failures: []))
        case .favorites:
            removeFavoriteReferences(uniqueWallpapers)
            completion?(WallpaperDeletionSummary(requestedCount: uniqueWallpapers.count, removedCount: uniqueWallpapers.count, failures: []))
        case .tag(let tag):
            removeTagReferences(uniqueWallpapers, tag: tag)
            completion?(WallpaperDeletionSummary(requestedCount: uniqueWallpapers.count, removedCount: uniqueWallpapers.count, failures: []))
        }
    }

    func removeRecentlyUsedWallpapers(_ wallpapersToRemove: [VideoWallpaper]) {
        // 最近使用只移除引用，不碰磁盘源文件。
        let removalPaths = normalizedPaths(for: wallpapersToRemove)
        guard !removalPaths.isEmpty else { return }

        recentlyUsedWallpapers.removeAll { removalPaths.contains(normalizedPath($0.path)) }
        saveRecentWallpapers()
        clearSelectionState()
    }

    func removeFavoriteReferences(_ wallpapersToRemove: [VideoWallpaper]) {
        // 收藏取消是主库属性回写，因此要走同一份引用移除逻辑。
        applyReferenceRemoval(for: wallpapersToRemove) { wallpaper in
            wallpaper.isFavorite = false
        }
    }

    func removeTagReferences(_ wallpapersToRemove: [VideoWallpaper], tag: String) {
        // 标签移除同样只改主库快照，不删源文件。
        applyReferenceRemoval(for: wallpapersToRemove) { wallpaper in
            wallpaper.tags.removeAll { $0 == tag }
        }
    }

    private func applyReferenceRemoval(
        for wallpapersToRemove: [VideoWallpaper],
        update: (inout VideoWallpaper) -> Void
    ) {
        // 这里是收藏 / 标签这类“引用型删除”的唯一写回点。
        let removalPaths = normalizedPaths(for: wallpapersToRemove)
        guard !removalPaths.isEmpty else { return }

        for index in wallpapers.indices where removalPaths.contains(normalizedPath(wallpapers[index].path)) {
            update(&wallpapers[index])
        }
        saveWallpapers()
        clearSelectionState()
    }

    private func removeLibraryWallpapers(
        _ wallpapersToRemove: [VideoWallpaper],
        completion: ((WallpaperDeletionSummary) -> Void)?
    ) {
        // 库删除分两段：后台清派生资源，主线程删索引和刷新 UI。
        let removalRecords = wallpapersToRemove.map(removalRecord(for:))

        enqueueDeletionTask { [weak self] in
            guard let self else { return }
            var successfulPaths = Set<String>()
            var successfulIDs = Set<String>()
            var failures: [WallpaperDeletionFailure] = []

            for record in removalRecords {
                failures.append(contentsOf: self.removeDerivedAssets(for: record))
                successfulPaths.insert(record.path)
                successfulIDs.insert(record.id)
            }

            DispatchQueue.main.async {
                self.applyLibraryRemoval(paths: successfulPaths, removedIDs: successfulIDs)
                let summary = WallpaperDeletionSummary(
                    requestedCount: removalRecords.count,
                    removedCount: successfulPaths.count,
                    failures: failures
                )
                completion?(summary)
            }
        }
    }

    private func deduplicatedWallpapers(_ wallpapers: [VideoWallpaper]) -> [VideoWallpaper] {
        // 删除前先按标准化路径去重，避免一个文件被重复删除两次。
        var seenPaths = Set<String>()
        var unique: [VideoWallpaper] = []

        for wallpaper in wallpapers {
            let normalized = normalizedPath(wallpaper.path)
            if seenPaths.insert(normalized).inserted {
                unique.append(wallpaper)
            }
        }

        return unique
    }

    @discardableResult
    func removeDerivedAssets(for record: RemovalRecord) -> [WallpaperDeletionFailure] {
        // 这里只清理缩略图/静帧等派生资源，绝不删除 record.path 对应的源视频文件。
        var failures: [WallpaperDeletionFailure] = []
        removeFileIfExists(atPath: record.thumbnailPath, title: record.title, failures: &failures)
        removeFileIfExists(atPath: record.staticFramePath, title: record.title, failures: &failures)

        let fileURL = URL(fileURLWithPath: record.path)
        removeFileIfExists(atPath: thumbnailOutputURL(for: fileURL).path, title: record.title, failures: &failures)
        removeFileIfExists(atPath: staticFrameOutputURL(for: fileURL).path, title: record.title, failures: &failures)

        setCachedThumbnailPath(nil, for: cacheKey(for: fileURL))
        let normalized = normalizedPath(record.path)
        clearThumbnailGenerationFailure(for: normalized)
        removeThumbnailInFlight(for: normalized)
        finishStaticFrameSchedule(for: normalized)
        return failures
    }

    func purgeMissingIndexedWallpapersFromLibrary(
        _ wallpapersToPurge: [VideoWallpaper],
        notifyUser: Bool
    ) {
        let uniqueWallpapers = wallpapersToPurge.reduce(into: [String: VideoWallpaper]()) { result, wallpaper in
            result[normalizedPath(wallpaper.path)] = wallpaper
        }
        let matchedWallpapers = uniqueWallpapers.values.filter { wallpaper in
            wallpapers.contains(where: { $0.id == wallpaper.id })
        }
        guard !matchedWallpapers.isEmpty else { return }

        let removedIDs = Set(matchedWallpapers.map(\.id))
        let removalPaths = Set(matchedWallpapers.map { normalizedPath($0.path) })
        let titles = matchedWallpapers.map(\.displayTitle).sorted()

        for wallpaper in matchedWallpapers {
            removeDerivedAssets(for: removalRecord(for: wallpaper))
        }

        applyLibraryRemoval(paths: removalPaths, removedIDs: removedIDs)

        if notifyUser {
            presentAutoRemovedMissingIndexedFilesAlert(titles: titles)
        }
    }

    func applyLibraryRemoval(paths: Set<String>, removedIDs: Set<String>) {
        // 主线程只做模型收口和当前播放切换，不在这里碰后台文件系统。
        guard !paths.isEmpty else { return }

        let currentWallpaperID = currentWallpaper?.id
        let normalizedCurrentPath = currentWallpaper.map { normalizedPath($0.path) }
        let wasCurrentRemoved = normalizedCurrentPath.map { paths.contains($0) } ?? false

        // 删除前先在当前排序列表中找到临近的跳转目标，删除后列表里就找不到了。
        let nextSelectionID = resolveNextSelectionID(removedIDs: removedIDs)
        let nextPlaybackWallpaperID = resolveNextPlaybackWallpaperID(
            removedIDs: removedIDs,
            currentWallpaperID: currentWallpaperID
        )

        removeWallpapersFromCollections(paths)

        if wasCurrentRemoved {
            clearCurrentWallpaperReference()
        }

        clearSelectionAndPendingState(removedIDs, nextSelectionID: nextSelectionID)
        saveWallpapers()

        if wasCurrentRemoved {
            if let nextWallpaper = nextPlaybackWallpaperID.flatMap({ nextWallpaperAfterRemoval(withID: $0) }) {
                setAsWallpaper(nextWallpaper)
            } else {
                WallpaperEngine.shared.stopPlayback()
            }
        }
    }

    private func resolveNextSelectionID(removedIDs: Set<String>) -> String? {
        // 在删除发生前的已排序列表中，找到当前选中项，取其后继（优先）或前驱作为跳转目标。
        guard let selectedID = selectedWallpaperId, removedIDs.contains(selectedID) else { return nil }
        return resolveAdjacentWallpaperID(
            anchoredAt: selectedID,
            removedIDs: removedIDs,
            preferredContext: currentSelectionContext
        )
    }

    private func resolveNextPlaybackWallpaperID(
        removedIDs: Set<String>,
        currentWallpaperID: String?
    ) -> String? {
        guard let currentWallpaperID, removedIDs.contains(currentWallpaperID) else { return nil }
        return resolveAdjacentWallpaperID(
            anchoredAt: currentWallpaperID,
            removedIDs: removedIDs,
            preferredContext: currentSelectionContext,
            fallbackContext: playbackSourceContext
        )
    }

    private func resolveAdjacentWallpaperID(
        anchoredAt wallpaperID: String,
        removedIDs: Set<String>,
        preferredContext: WallpaperSelectionContext,
        fallbackContext: WallpaperSelectionContext? = nil
    ) -> String? {
        if let resolved = resolveAdjacentWallpaperID(
            anchoredAt: wallpaperID,
            removedIDs: removedIDs,
            within: preferredContext
        ) {
            return resolved
        }

        if let fallbackContext,
           fallbackContext != preferredContext,
           let resolved = resolveAdjacentWallpaperID(
                anchoredAt: wallpaperID,
                removedIDs: removedIDs,
                within: fallbackContext
           ) {
            return resolved
        }

        let next = wallpapers.first { $0.id != wallpaperID && !removedIDs.contains($0.id) }
        return next?.id
    }

    private func resolveAdjacentWallpaperID(
        anchoredAt wallpaperID: String,
        removedIDs: Set<String>,
        within context: WallpaperSelectionContext
    ) -> String? {
        let source = context.sourceWallpapers(from: self)
        let selectionKey = context.scrollPersistenceKey
        let sorted = sortedWallpapers(source.isEmpty ? wallpapers : source, selectionKey: selectionKey)
        guard let currentIndex = sorted.firstIndex(where: { $0.id == wallpaperID }) else { return nil }
        let next = sorted[(currentIndex + 1)...].first(where: { !removedIDs.contains($0.id) })
        let prev = sorted[..<currentIndex].last(where: { !removedIDs.contains($0.id) })
        return (next ?? prev)?.id
    }

    private func nextWallpaperAfterRemoval(withID wallpaperID: String) -> VideoWallpaper? {
        wallpapers.first { $0.id == wallpaperID }
    }

    func removeWallpapersFromCollections(_ paths: Set<String>) {
        // 所有集合清理都先按标准化路径匹配，保证“我的壁纸 / 最近使用 / 收藏 / 标签”一致。
        wallpapers.removeAll { paths.contains(normalizedPath($0.path)) }
        recentlyUsedWallpapers.removeAll { paths.contains(normalizedPath($0.path)) }
        constrainRecentWallpapersToLibrary()
        saveRecentWallpapers()
    }

    func clearSelectionAndPendingState(_ removedIDs: Set<String>, nextSelectionID: String? = nil) {
        // 删除后把单选态跳到预先计算好的临近项（在删除前已确定）。
        if let selectedWallpaperId, removedIDs.contains(selectedWallpaperId) {
            self.selectedWallpaperId = nextSelectionID
        }

        selectedWallpaperIds.subtract(removedIDs)

        if isMultiSelectMode {
            clearSelectionState()
        }
    }

    func clearCurrentWallpaperReference() {
        // 当前壁纸引用只清快照，不立刻停引擎，停播由上层分支决定。
        currentWallpaper = nil
        // E2a-3: requested 层一并撤销（web/scene/systemStill 切换入口经
        // 此清引用，残留 pending 会让高亮谎报播放中）。
        pendingWallpaper = nil
        persistCurrentWallpaperSnapshot()
    }

    func clearCurrentWallpaperAndStopPlayback() {
        stopCurrentPlayback()
    }

    /// E2a-2: 用户请求的停止入口——选择权威回收真值（引用清空、
    /// 定时切换停止、播放态复位）后停播并推进产品意图纪元。命令通道
    /// 的 `.stop`（video handler）与 Scene 的 `.stopped` 事件都汇聚
    /// 到这里，保证 stopped 状态只有这一个归属。
    func stopCurrentPlayback() {
        // E2a-3: 停止同时撤销未提交的 requested 选择。
        pendingWallpaper = nil
        clearCurrentWallpaperReference()
        stopAutoSwitchTimer()
        WallpaperEngine.shared.adoptIntentEpoch(beginPlaybackIntent())
        WallpaperEngine.shared.stopPlayback()
        isPlaying = false
    }

    func removalRecord(for wallpaper: VideoWallpaper) -> RemovalRecord {
        // RemovalRecord 只承载删除时需要的派生资源信息，不包含任何 UI 状态。
        RemovalRecord(
            id: wallpaper.id,
            title: wallpaper.displayTitle,
            path: normalizedPath(wallpaper.path),
            thumbnailPath: wallpaper.thumbnailPath,
            staticFramePath: wallpaper.staticFramePath
        )
    }

    private func removeFileIfExists(
        atPath path: String?,
        title: String,
        failures: inout [WallpaperDeletionFailure]
    ) {
        // 这里只尝试删除缓存文件；源视频路径不应该走到这里。
        guard let path, pathExists(path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            failures.append(
                WallpaperDeletionFailure(
                    title: title,
                    path: path,
                    reason: "缓存清理失败"
                )
            )
        }
    }

    private func normalizedPaths(for wallpapers: [VideoWallpaper]) -> Set<String> {
        Set(wallpapers.map { normalizedPath($0.path) })
    }
}
