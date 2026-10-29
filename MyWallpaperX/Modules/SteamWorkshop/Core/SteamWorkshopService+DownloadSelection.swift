import Foundation
import AppKit

extension SteamWorkshopService {

    func dismissDownloadInspector() {
        if selectedDownloadInspectorItem != nil { cancelSelectedItemDetailRefresh() }
        selectedDownloadInspectorItem = nil
        selectedDownloadDetailItem = nil
        selectedDownloadDetailError = nil
        isRefreshingSelectedDownloadDetailItem = false
    }

    func deleteDownload(itemID: String) {
        deleteDownloads(itemIDs: [itemID])
    }

    func presentDownloadInspector(_ item: SteamWorkshopBrowserItem) {
        if selectedDownloadInspectorItem?.id != item.id || selectedBrowserItem != nil {
            cancelSelectedItemDetailRefresh()
            selectedBrowserItem = nil
        }
        let metadataSnapshot = managedDownloadSnapshots(matchingItemID: item.id)[item.id]
        var resolvedItem = metadataSnapshot?.item ?? item
        var fetchedAt = metadataSnapshot?.fetchedAt
        if let cached = Self.loadDetailCacheSnapshot(id: item.id),
           !SteamWorkshopDetailRefreshSupport.needsRefresh(cached.item),
           SteamWorkshopDetailRefreshSupport.needsRefresh(resolvedItem)
            || cached.fetchedAt > (fetchedAt ?? .distantPast) {
            resolvedItem = cached.item
            fetchedAt = cached.fetchedAt
            persistRefreshedDownloadMetadata(resolvedItem, fetchedAt: cached.fetchedAt)
        }
        selectedDownloadInspectorItem = resolvedItem
        selectedDownloadDetailItem = resolvedItem
        selectedDownloadDetailError = nil
        currentWorkshopItemID = resolvedItem.id
        currentPageTitle = resolvedItem.title
        statusMessage = "已加载 \(resolvedItem.title)"
        refreshSelectedDownloadInspectorDetailIfNeeded(
            forceRefresh: false,
            metadataIsStale: SteamWorkshopDetailRefreshSupport.isDownloadedMetadataStale(fetchedAt: fetchedAt)
        )
    }

    func deleteDownloads(itemIDs: [String], completion: (([String: Bool]) -> Void)? = nil) {
        guard Set(itemIDs.map { WallpaperReference(provider: .steamWorkshop, sourceID: $0) }).count == Set(itemIDs).count else {
            statusMessage = "删除未开始：旧回执接口不能区分这些文件身份。"
            completion?([:])
            return
        }
        deleteSourceFiles(itemIDs: itemIDs) { result in
            var legacy: [String: Bool] = [:]
            // Compatibility for original callers. Typed product consumers keep
            // exact provider/UTF8 identity and never use this lossy String map.
            for item in result.items { legacy[item.reference.sourceID] = item.succeeded }
            completion?(legacy)
        }
    }

    func deleteSourceFiles(itemIDs: [String], completion: @escaping (WallpaperSourceDeletionResult) -> Void) {
        var seen = Set<WallpaperReference>()
        let ids = itemIDs.filter { seen.insert(.init(provider: .steamWorkshop, sourceID: $0)).inserted && !removingDownloadIDs.contains($0) }
        guard !ids.isEmpty else { completion(.init(items: [])); return }
        removingDownloadIDs.formUnion(ids)
        Task { [weak self] in
            guard let self else { return }
            defer { self.removingDownloadIDs.subtract(ids) }
            var results: [WallpaperSourceDeletionResult.Item] = []
            for id in ids {
                let record = self.latestDownloadRecord(for: id)
                let url = record?.exportedVideoURL ?? record?.sourceVideoURL ?? record?.folderURL ?? self.steamDownloadLibraryRootURL
                let succeeded = await self.deleteDownloadIfPossible(itemID: id)
                results.append(.init(reference: .init(provider: .steamWorkshop, sourceID: id), sourceURL: url,
                    succeeded: succeeded, sourceFileDeleted: succeeded && record?.status == .ready,
                    failureMessage: succeeded ? nil : "Steam 源文件删除未完成；资源可能仍在使用或版本已变化"))
            }
            self.reloadInstalledItems()
            let removed = results.filter(\.succeeded).count
            if removed == ids.count { self.statusMessage = "已删除 \(removed) 个壁纸及本地文件" }
            completion(.init(items: results))
        }
    }

    @discardableResult
    private func deleteDownloadIfPossible(itemID: String) async -> Bool {
        guard let record = latestDownloadRecord(for: itemID) else { return false }
        var readySnapshot: SteamWorkshopDownloadMetadataSnapshot?
        switch record.status {
        case .queued, .downloading:
            NSSound.beep()
            return false
        case .ready:
            do {
                readySnapshot = try loadManagedDownloadSnapshots(
                    requireComplete: true,
                    matchingItemID: itemID,
                    includeLegacy: true
                )[itemID]
                if readySnapshot == nil {
                    readySnapshot = try loadLegacyVideoDownloadSnapshot(matching: record)
                }
            } catch {
                statusMessage = "移除失败：下载记录无法安全读取；内容保持不变。"
                return false
            }
            if let snapshot = readySnapshot, snapshot.commit == nil, !legacyDownloadSnapshot(snapshot, matches: record) {
                statusMessage = "移除失败：旧版下载身份不一致；内容保持不变。"
                return false
            }
        case .failed:
            if let account = steamAuth.steamId,
               let job = downloadJobStore.failedJob(forWorkshopItemId: itemID, accountSteamId: account) {
                discardFailedDownload(jobID: job.id)
                guard downloadJobStore.job(id: job.id)?.state == .cancelled else { return false }
            }
        }

        // Fence new downloads before stopping consumers or touching disk.
        if let activeJob = downloadJobStore.activeJob(forWorkshopItemId: itemID) {
            guard downloadJobStore.cancel(id: activeJob.id) != nil else {
                statusMessage = "删除失败：下载取消状态无法保存。"
                return false
            }
            steamJobItemPayloads.removeValue(forKey: itemID)
            cancelDownloadImmediately(itemID: itemID, showFeedback: false)
        }
        if record.contentType == .scene, SceneDaemonClient.shared.hasIntent(for: record.id) {
            guard let prepareSceneDownloadRemoval else {
                statusMessage = "删除失败：Scene 播放控制尚未就绪，请稍后重试。"
                return false
            }
            let released = await withCheckedContinuation { continuation in
                prepareSceneDownloadRemoval(record.id) { continuation.resume(returning: $0) }
            }
            guard released else {
                statusMessage = "删除失败：壁纸资源仍在切换，请完成切换后重试。"
                return false
            }
        } else if isRecordCurrentlyPlaying(record) {
            WallpaperManager.shared.stopCurrentPlayback()
        }
        let library = steamDownloadLibraryRootURL
        let target = record.contentType == .video && readySnapshot?.commit == nil
            ? (record.exportedVideoURL ?? record.sourceVideoURL ?? record.folderURL) : record.folderURL
        let identity = readySnapshot?.commit.flatMap(SteamWorkshopLibraryTransaction.storageIdentity(for:))
        if let identity {
            guard steamLibraryVersionLeaseRegistry.beginReclamation(identity) else {
                statusMessage = "删除失败：壁纸资源尚未释放，请停止播放后重试。"
                return false
            }
        }
        var tombstonePublished = false
        do {
            // Consumers have stopped and admission is fenced. Settle any old
            // publication before writing the deletion pointer; cleanup stays in GC.
            try SteamWorkshopLibraryTransaction.recoverPublications(
                libraryRoot: library, matchingItemID: itemID)
            guard try loadManagedDownloadSnapshots(requireComplete: true, matchingItemID: itemID,
                includeLegacy: true)[itemID]?.commit == readySnapshot?.commit else {
                throw SteamWorkshopLibraryTransaction.Failure(message: "下载版本已变化，请刷新后重试删除。")
            }
            if var snapshot = readySnapshot {
                if var commit = snapshot.commit {
                    commit.removed = true
                    snapshot.commit = commit
                } else { snapshot.legacyRemoved = true }
                try SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(snapshot),
                    itemID: itemID, libraryRoot: library)
                tombstonePublished = true
            }
            if record.status == .ready {
                let expected = readySnapshot?.commit
                try await Task.detached(priority: .utility) {
                    try SteamWorkshopLibraryTransaction.removeContent(at: target, itemID: itemID,
                        libraryRoot: library, expectedCommit: expected)
                }.value
            }
        } catch {
            if tombstonePublished, let original = readySnapshot {
                try? SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(original),
                    itemID: itemID, libraryRoot: library)
            }
            if let identity { steamLibraryVersionLeaseRegistry.reclamationFailed(identity) }
            statusMessage = "删除失败：\(error.localizedDescription)"
            return false
        }

        if selectedDownloadInspectorItem?.id.utf8.elementsEqual(itemID.utf8) == true {
            dismissDownloadInspector()
        } else if selectedBrowserItem?.id.utf8.elementsEqual(itemID.utf8) == true {
            cancelSelectedItemDetailRefresh()
        }
        if isValidWorkshopItemID(itemID) {
            try? FileManager.default.removeItem(at: Self.detailCacheFileURL(id: itemID))
        }
        removeWebRuntimeCaches(for: itemID)
        downloads.removeAll { $0.id.utf8.elementsEqual(itemID.utf8) }
        return true
    }

    private func legacyDownloadSnapshot(
        _ snapshot: SteamWorkshopDownloadMetadataSnapshot,
        matches record: SteamWorkshopDownloadRecord
    ) -> Bool {
        guard snapshot.commit == nil, snapshot.item.id.utf8.elementsEqual(record.id.utf8) else { return false }
        switch record.contentType {
        case .video:
            guard let snapshotURL = snapshot.exportedVideoURL,
                  let recordURL = record.exportedVideoURL ?? record.sourceVideoURL else { return false }
            return snapshotURL.standardizedFileURL == recordURL.standardizedFileURL
        case .web, .scene:
            return snapshot.legacyFolderURL?.standardizedFileURL == record.folderURL.standardizedFileURL
        case .unknown:
            return false
        }
    }
}
