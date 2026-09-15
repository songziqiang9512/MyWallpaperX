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
        prioritizeUserRequestedDetail()
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
        let uniqueIDs = Array(Set(itemIDs))
        guard !uniqueIDs.isEmpty else { return }
        var deletedTitles: [String] = []
        for itemID in uniqueIDs {
            let title = latestDownloadRecord(for: itemID)?.title
            if deleteDownloadIfPossible(itemID: itemID), let title {
                deletedTitles.append(title)
            }
        }
        reloadInstalledItems()
        if uniqueIDs.count == 1, let title = deletedTitles.first {
            statusMessage = "已移除 \(title)"
        } else if !deletedTitles.isEmpty {
            statusMessage = "已移除 \(deletedTitles.count) 个下载项"
        }
    }

    @discardableResult
    private func deleteDownloadIfPossible(itemID: String) -> Bool {
        guard let record = latestDownloadRecord(for: itemID) else { return false }
        switch record.status {
        case .queued, .downloading:
            NSSound.beep()
            return false
        case .ready, .failed:
            break
        }

        let fileManager = FileManager.default
        if record.contentType == .video {
            if let videoURL = record.exportedVideoURL ?? record.sourceVideoURL,
               fileManager.fileExists(atPath: videoURL.path) {
                try? fileManager.removeItem(at: videoURL)
            }
        } else if fileManager.fileExists(atPath: record.folderURL.path),
                  record.folderURL.lastPathComponent == itemID,
                  (record.folderURL.deletingLastPathComponent() == webLibraryRootURL
                   || record.folderURL.deletingLastPathComponent() == sceneLibraryRootURL) {
            try? fileManager.removeItem(at: record.folderURL)
        }
        try? fileManager.removeItem(at: downloadMetadataFileURL(for: record))

        downloads.removeAll { $0.id == itemID }
        // SK4.1：删除本地项时取消其排队任务（JobStore 真值）。
        if let job = downloadJobStore.activeJob(forWorkshopItemId: itemID) {
            downloadJobStore.cancel(id: job.id)
        }
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
}
