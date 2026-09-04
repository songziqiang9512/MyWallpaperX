//
//  SteamWorkshopService+DownloadAccessors.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    func canLaunchDownloadRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        guard record.status == .ready else { return false }
        if record.contentType == .web {
            guard record.isPlayableOrLaunchable else { return false }
            if let report = webValidationReport(for: record),
               report.fatalIssue != nil {
                return false
            }
            return true
        }
        return record.isPlayableOrLaunchable
    }

    func cachedCanLaunchDownloadRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        guard record.status == .ready else { return false }
        if record.contentType == .web {
            guard record.isPlayableOrLaunchable else { return false }
            let signature = webValidationSignature(for: record)
            if let cached = webValidationReportCache[record.id],
               cached.signature == signature {
                return cached.report.fatalIssue == nil
            }
            return true
        }
        return record.isPlayableOrLaunchable
    }

    var filteredDownloads: [SteamWorkshopDownloadRecord] {
        displayedDownloads
    }

    var visibleVideoDownloadsCount: Int {
        downloads.filter { $0.contentType == .video }.count
    }

    var visibleWebDownloadsCount: Int {
        downloads.filter { $0.contentType == .web }.count
    }

    var visibleSceneDownloadsCount: Int {
        downloads.filter { $0.contentType == .scene }.count
    }

    var visibleMissingDependencyDownloadsCount: Int {
        downloads.filter {
            if case .missing = $0.dependencyStatus {
                return true
            }
            return false
        }.count
    }

    func firstDisplayedDownloadID(in ids: Set<String>) -> String? {
        displayedDownloads.first { ids.contains($0.id) }?.id
    }

    var downloadsCount: Int { downloads.count }

    var activeFilterDisplayParts: [String] {
        var parts: [String] = []
        if themeFilter != .all { parts.append(themeFilter.displayName) }
        if let ageRating = ageRatingFilter.activeDisplayName { parts.append(ageRating) }
        if resolutionFilter != .all { parts.append(resolutionFilter.displayName) }
        if categoryFilter != .all { parts.append(categoryFilter.displayName) }
        return parts
    }

    var activeFilterSummary: String {
        let parts = activeFilterDisplayParts
        return parts.isEmpty ? "未筛选" : parts.joined(separator: " · ")
    }

    var activeBrowserContextSummary: String? {
        guard let activeAuthorWorkshopName else { return nil }
        return "当前正在浏览 \(activeAuthorWorkshopName) 的创意工坊作品"
    }

    var hasVisibleBrowserItems: Bool {
        !displayedBrowserItems.isEmpty
    }

    func isDownloading(itemID: String) -> Bool {
        latestDownloadRecord(for: itemID)?.status == .downloading
    }

    func isQueuedForDownload(itemID: String) -> Bool {
        latestDownloadRecord(for: itemID)?.status == .queued
    }

    func latestDownloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        downloads.first(where: { $0.id == itemID })
    }

    var selectedDownloadRecord: SteamWorkshopDownloadRecord? {
        guard let selectedDownloadID else { return nil }
        return latestDownloadRecord(for: selectedDownloadID)
    }

    var effectiveSelectedDownloadIDs: Set<String> {
        if isDownloadsMultiSelectMode {
            return selectedDownloadIDs
        }
        if let selectedDownloadID {
            return [selectedDownloadID]
        }
        return []
    }

    var canDeleteSelectedDownload: Bool {
        let selectedIDs = effectiveSelectedDownloadIDs
        guard !selectedIDs.isEmpty else { return false }
        return selectedIDs.allSatisfy { id in
            guard let record = latestDownloadRecord(for: id) else { return false }
            switch record.status {
            case .ready, .failed:
                return true
            case .queued, .downloading:
                return false
            }
        }
    }

    var canShowSelectedDownloadInfo: Bool {
        !isDownloadsMultiSelectMode && selectedDownloadRecord != nil
    }

    var canRevealSelectedDownload: Bool {
        !isDownloadsMultiSelectMode && selectedDownloadRecord != nil
    }

    var canSelectAllDownloads: Bool {
        isDownloadsMultiSelectMode && !displayedDownloads.isEmpty
    }

    func downloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        guard let record = latestDownloadRecord(for: itemID),
              record.status == .ready else {
            return nil
        }
        return record
    }

    func playableDownloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        guard let record = latestDownloadRecord(for: itemID),
              canLaunchDownloadRecord(record) else {
            return nil
        }
        return record
    }

    func isDownloaded(itemID: String) -> Bool {
        downloadRecord(for: itemID) != nil
    }

    func latestDownloadFailure(for itemID: String) -> String? {
        latestDownloadRecord(for: itemID)?.failureMessage
    }
}
