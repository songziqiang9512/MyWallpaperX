import Foundation
import AppKit

extension SteamWorkshopService {
    func selectDownload(itemID: String?) {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let resolvedItemID = itemID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let nextSelectedIDs = !isDownloadsMultiSelectMode
            ? (resolvedItemID.map { [$0] } ?? [])
            : selectedDownloadIDs
        applyDownloadSelectionState(
            primaryID: resolvedItemID,
            selectedIDs: nextSelectedIDs,
            forceSingleSelection: !isDownloadsMultiSelectMode
        )
    }

    func replaceSelectedDownloads(with ids: Set<String>, primaryID: String? = nil) {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let sanitized = ids.intersection(visibleIDs)
        let resolvedPrimaryID: String?
        if isDownloadsMultiSelectMode {
            if let primaryID, sanitized.contains(primaryID) {
                resolvedPrimaryID = primaryID
            } else {
                resolvedPrimaryID = firstDisplayedDownloadID(in: sanitized)
            }
        } else {
            resolvedPrimaryID = primaryID ?? firstDisplayedDownloadID(in: sanitized)
        }
        let resolvedSelectedIDs = isDownloadsMultiSelectMode
            ? sanitized
            : (resolvedPrimaryID.map { [$0] } ?? [])
        applyDownloadSelectionState(
            primaryID: resolvedPrimaryID,
            selectedIDs: resolvedSelectedIDs,
            forceSingleSelection: !isDownloadsMultiSelectMode
        )
    }

    func toggleDownloadsMultiSelectMode() {
        if isDownloadsMultiSelectMode {
            exitDownloadsMultiSelectMode()
        } else {
            enterDownloadsMultiSelectMode()
        }
    }

    func enterDownloadsMultiSelectMode() {
        isDownloadsMultiSelectMode = true
        selectedDownloadID = nil
        selectedDownloadIDs.removeAll()
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func exitDownloadsMultiSelectMode() {
        isDownloadsMultiSelectMode = false
        selectedDownloadID = nil
        selectedDownloadIDs.removeAll()
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func deleteSelectedDownload() {
        let targetIDs = Array(effectiveSelectedDownloadIDs)
        guard !targetIDs.isEmpty else { return }
        deleteDownloads(itemIDs: targetIDs)
    }

    func selectAllDownloads() {
        guard canSelectAllDownloads else { return }
        let ids = Set(displayedDownloads.map(\.id))
        replaceSelectedDownloads(with: ids, primaryID: selectedDownloadID ?? displayedDownloads.first?.id)
    }

    func revealSelectedDownload() {
        guard let record = selectedDownloadRecord else { return }
        revealItem(record)
    }

    func presentSelectedDownloadInfo() {
        guard let record = selectedDownloadRecord else { return }
        let item = record.displayItemForToolbar
        if selectedDownloadInspectorItem?.id == item.id {
            dismissDownloadInspector()
        } else {
            presentDownloadInspector(item)
        }
    }

    func presentDownloadInfo(for itemID: String) {
        guard let record = latestDownloadRecord(for: itemID) else { return }
        let item = resolvedDownloadInspectorItem(for: record)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.selectedDownloadInspectorItem?.id == item.id {
                self.dismissDownloadInspector()
            } else {
                self.presentDownloadInspector(item)
            }
        }
    }

    func dismissDownloadInspector() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        selectedDownloadInspectorItem = nil
        selectedDownloadDetailItem = nil
        selectedDownloadDetailError = nil
        isRefreshingSelectedDownloadDetailItem = false
    }

    func clearDownloadSelectionAndInspector() {
        selectedDownloadID = nil
        selectedDownloadIDs.removeAll()
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func syncDownloadsInspectorSelectionIfNeeded() {
        guard !isDownloadsMultiSelectMode,
              let record = selectedDownloadRecord else {
            dismissDownloadInspector()
            return
        }

        guard selectedDownloadInspectorItem != nil else {
            return
        }

        let item = resolvedDownloadInspectorItem(for: record)
        if selectedDownloadInspectorItem?.id == item.id {
            selectedDownloadInspectorItem = item
            selectedDownloadDetailItem = item
            return
        }
        presentDownloadInspector(item)
    }

    func publishDownloadSelectionState(
        primaryID: String?,
        selectedIDs: Set<String>,
        deferPublishing: Bool
    ) {
        if deferPublishing {
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.selectedDownloadID != primaryID || self.selectedDownloadIDs != selectedIDs else {
                    return
                }
                self.selectedDownloadID = primaryID
                self.selectedDownloadIDs = selectedIDs
                self.syncDownloadsInspectorSelectionIfNeeded()
            }
        } else {
            guard selectedDownloadID != primaryID || selectedDownloadIDs != selectedIDs else {
                return
            }
            selectedDownloadID = primaryID
            selectedDownloadIDs = selectedIDs
            syncDownloadsInspectorSelectionIfNeeded()
        }
    }

    func deleteDownload(itemID: String) {
        deleteDownloads(itemIDs: [itemID])
    }

    private func presentDownloadInspector(_ item: SteamWorkshopBrowserItem) {
        selectedDownloadInspectorItem = item
        selectedDownloadDetailItem = item
        selectedDownloadDetailError = nil
        currentWorkshopItemID = item.id
        currentPageTitle = item.title
        statusMessage = "已加载 \(item.title)"
        refreshSelectedDownloadInspectorDetailIfNeeded(
            forceRefresh: SteamWorkshopDetailRefreshSupport.needsDownloadedMetadataRefresh(item)
        )
    }

    private func resolvedDownloadInspectorItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        if let detailItem = selectedDownloadDetailItem,
           detailItem.id == record.id {
            return detailItem
        }
        return record.displayItemForToolbar
    }

    private func applyDownloadSelectionState(
        primaryID: String?,
        selectedIDs: Set<String>,
        forceSingleSelection: Bool
    ) {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let sanitizedPrimaryID = primaryID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let normalizedSelectedIDs = forceSingleSelection
            ? (sanitizedPrimaryID.map { [$0] } ?? [])
            : selectedIDs.intersection(visibleIDs)
        let resolvedPrimaryID: String?
        if let sanitizedPrimaryID {
            resolvedPrimaryID = sanitizedPrimaryID
        } else if forceSingleSelection {
            resolvedPrimaryID = nil
        } else {
            resolvedPrimaryID = firstDisplayedDownloadID(in: normalizedSelectedIDs)
        }
        guard selectedDownloadID != resolvedPrimaryID || selectedDownloadIDs != normalizedSelectedIDs else {
            return
        }
        publishDownloadSelectionState(
            primaryID: resolvedPrimaryID,
            selectedIDs: normalizedSelectedIDs,
            deferPublishing: true
        )
    }

    private func deleteDownloads(itemIDs: [String]) {
        let ids = Set(itemIDs).subtracting(removingDownloadIDs)
        guard !ids.isEmpty else { return }
        removingDownloadIDs.formUnion(ids)
        Task { [weak self] in
            guard let self else { return }
            defer { self.removingDownloadIDs.subtract(ids) }
            var removed = 0
            for id in ids {
                if await self.deleteDownloadIfPossible(itemID: id) { removed += 1 }
            }
            self.reloadInstalledItems()
            if removed == ids.count { self.statusMessage = "已删除 \(removed) 个壁纸及本地文件" }
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
        if isRecordCurrentlyPlaying(record) { WallpaperManager.shared.stopCurrentPlayback() }
        let library = steamDownloadLibraryRootURL
        let target = record.contentType == .video && readySnapshot?.commit == nil
            ? (record.exportedVideoURL ?? record.sourceVideoURL ?? record.folderURL) : record.folderURL
        let identity = readySnapshot?.commit.flatMap(SteamWorkshopLibraryTransaction.storageIdentity(for:))
        if let identity {
            var admitted = false
            for _ in 0..<100 {
                if steamLibraryVersionLeaseRegistry.beginReclamation(identity) { admitted = true; break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard admitted else {
                statusMessage = "删除失败：壁纸资源尚未释放，请停止播放后重试。"
                return false
            }
        }
        var tombstonePublished = false
        do {
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

        downloads.removeAll { $0.id == itemID }
        if selectedDownloadID == itemID {
            selectedDownloadID = nil
        }
        selectedDownloadIDs.remove(itemID)
        if !isDownloadsMultiSelectMode {
            selectedDownloadIDs = selectedDownloadID.map { [$0] } ?? []
        }
        syncDownloadsInspectorSelectionIfNeeded()
        return true
    }

    private func legacyDownloadSnapshot(
        _ snapshot: SteamWorkshopDownloadMetadataSnapshot,
        matches record: SteamWorkshopDownloadRecord
    ) -> Bool {
        guard snapshot.commit == nil, snapshot.item.id == record.id else { return false }
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
