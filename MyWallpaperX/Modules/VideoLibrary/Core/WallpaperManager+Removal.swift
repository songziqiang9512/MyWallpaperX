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

    /// Only the explicit checked removal uses this file operation. Source rows
    /// remain facts; the relationship Store owns durable library exclusion.
    func deleteSourceFiles(_ targets: [VideoWallpaper], completion: @escaping (WallpaperSourceDeletionResult) -> Void) {
        let epoch = wallpaperIndexSaveEpoch
        var results: [WallpaperSourceDeletionResult.Item] = []
        var requests: [(WallpaperReference, WallpaperSourceFileDeletion.Prepared)] = []
        var seen = Set<WallpaperReference>()
        for target in targets {
            let reference = WallpaperReference(provider: .videoLibrary, sourceID: target.id)
            guard seen.insert(reference).inserted else { continue }
            let url = URL(fileURLWithPath: target.path).standardizedFileURL
            do {
                guard allowsLibraryMutation else { throw CocoaError(.fileWriteNoPermission) }
                guard wallpapers.contains(where: { $0.id.utf8.elementsEqual(target.id.utf8) && normalizedPath($0.path) == normalizedPath(url.path) }) else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "资料库条目已变化"])
                }
                guard !isLocalSourceFileInUse(normalizedPath(url.path)) else {
                    throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "源视频正在播放或准备，请先停止播放后重试"])
                }
                requests.append((reference, try WallpaperSourceFileDeletion.prepare(url)))
            } catch {
                results.append(.init(reference: reference, sourceURL: url, succeeded: false, sourceFileDeleted: false,
                    failureMessage: error.localizedDescription))
            }
        }
        guard !requests.isEmpty else { completion(.init(items: results)); return }
        enqueueDeletionTask { [weak self] in
            guard let self else { return }
            var results = results
            var outcomes: [Data: WallpaperSourceFileDeletion.Outcome] = [:]
            for (reference, request) in requests {
                let key = Data(request.url.path.utf8), prior = outcomes[key]
                let unlinked = DispatchQueue.main.sync {
                    guard self.wallpaperIndexSaveEpoch == epoch && self.allowsLibraryMutation
                        && self.wallpapers.contains(where: { $0.id.utf8.elementsEqual(reference.sourceID.utf8) && self.normalizedPath($0.path) == self.normalizedPath(request.url.path) })
                        && !self.isLocalSourceFileInUse(self.normalizedPath(request.url.path)) else {
                        return WallpaperSourceFileDeletion.Outcome(sourceFileDeleted: false,
                            failureMessage: "资料库或播放状态已变化，未删除源文件")
                    }
                    // The original playback admission is MainActor-isolated.
                    // Nothing can accept this source between this guard and unlink.
                    return prior ?? WallpaperSourceFileDeletion.unlinkPrepared(request)
                }
                let outcome = unlinked.succeeded && prior == nil
                    ? WallpaperSourceFileDeletion.synchronizeDirectory(after: request) : unlinked
                outcomes[key] = outcome
                results.append(.init(reference: reference, sourceURL: request.url, succeeded: outcome.succeeded,
                    sourceFileDeleted: outcome.sourceFileDeleted, failureMessage: outcome.failureMessage))
            }
            let report = WallpaperSourceDeletionResult(items: results)
            DispatchQueue.main.async { completion(report) }
        }
    }

    func isLocalSourceFileInUse(_ path: String) -> Bool {
        let path = normalizedPath(path)
        let tickets = [playbackSwitch.committed?.ticket, playbackSwitch.pending?.selection.ticket].compactMap { $0 }
            + playbackSwitch.cancellations.values.map(\.ticket) + playbackSwitch.retirements.values.map(\.ticket)
        return tickets.contains { ticket in
            switch switchSelections[ticket.id] {
            case .video(let wallpaper): return normalizedPath(wallpaper.path) == path
            case .systemStill(let url): return normalizedPath(url.path) == path
            default: return false
            }
        }
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
        guard !preservesLegacyMigrationInputs else { return }
        let uniqueWallpapers = wallpapersToPurge.reduce(into: [String: VideoWallpaper]()) { result, wallpaper in
            result[normalizedPath(wallpaper.path)] = wallpaper
        }
        let matchedWallpapers = uniqueWallpapers.values.filter { wallpaper in
            wallpapers.contains(where: { $0.id == wallpaper.id })
        }
        guard !matchedWallpapers.isEmpty else { return }

        let removedIDs = Set(matchedWallpapers.map { Data($0.id.utf8) })
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

    func applyLibraryRemoval(paths: Set<String>, removedIDs: Set<Data>) {
        // 主线程只做模型收口和当前播放切换，不在这里碰后台文件系统。
        guard !paths.isEmpty else { return }

        // A same-path replacement with a different source ID is a new row.
        // A late deletion can retire only the IDs accepted by this command.
        wallpapers.removeAll { paths.contains(normalizedPath($0.path)) && removedIDs.contains(Data($0.id.utf8)) }
        saveWallpapers()
    }

    func clearCurrentWallpaperReference() {
        // 当前壁纸引用只清快照，不立刻停引擎，停播由上层分支决定。
        currentWallpaper = nil
        // E2a-3: requested 层一并撤销（web/scene/systemStill 切换入口经
        // 此清引用，残留 pending 会让高亮谎报播放中）。
        pendingWallpaper = nil
        persistCurrentWallpaperSnapshot()
    }

    /// E2a-2: 用户请求的停止入口——选择权威回收真值（引用清空、
    /// 定时切换停止、播放态复位）后停播并推进产品意图纪元。命令通道
    /// 的 `.stop`（video handler）与 Scene 的 `.stopped` 事件都汇聚
    /// 到这里，保证 stopped 状态只有这一个归属。
    func stopCurrentPlayback() {
        pendingManualNavigationWorkItem?.cancel()
        pendingManualNavigationWorkItem = nil
        pendingManualNavigationDirection = nil
        let epoch = beginPlaybackIntent()
        guard playbackIntentEpoch == epoch else { return }
        // E2a-3: 停止同时撤销未提交的 requested 选择。
        pendingWallpaper = nil
        clearCurrentWallpaperReference()
        lastWorkshopPlaybackRecordID = nil
        stopAutoSwitchTimer()
        WallpaperEngine.shared.adoptIntentEpoch(epoch)
        WallpaperEngine.shared.stopPlayback()
        guard playbackIntentEpoch == epoch else { return }
        SceneDaemonClient.shared.stop()
        guard playbackIntentEpoch == epoch else { return }
        switchDeadline?.cancel()
        pendingSystemWallpaperSyncWorkItem?.cancel()
        isPlaying = false
        guard playbackIntentEpoch == epoch else { return }
        libraryPlaybackStopped?()
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

}
