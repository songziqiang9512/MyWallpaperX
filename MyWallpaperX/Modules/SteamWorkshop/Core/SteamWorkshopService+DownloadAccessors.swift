//
//  SteamWorkshopService+DownloadAccessors.swift
//  MyWallpaperX
//

import AppKit
import Foundation

extension SteamWorkshopService {
    func canLaunchDownloadRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        guard record.status == .ready else { return false }
        if record.contentType == .web {
            guard record.isPlayableOrLaunchable else { return false }
            return webLaunchEntryIsValid(for: record)
        }
        return record.isPlayableOrLaunchable
    }

    func cachedCanLaunchDownloadRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        guard record.status == .ready else { return false }
        // Cards project the published record. The selected target's current
        // files are checked by canLaunchDownloadRecord and runtime preparation.
        let hasVideo = record.exportedVideoURL != nil || record.sourceVideoURL != nil
        if record.contentType == .web {
            guard record.entryHTMLURL != nil else { return false }
            if hasVideo || record.dependencyItemID == nil { return true }
            if case .available = record.dependencyStatus { return true }
            return false
        }
        return hasVideo || record.contentType == .scene
    }

    var activeFilterDisplayParts: [String] {
        var parts: [String] = []
        parts.append(
            contentsOf: SteamWorkshopThemeFilter.allCases
                .filter { facetFilters.themes.contains($0) }
                .map(\.displayName)
        )
        if let ageRating = facetFilters.ageRating.activeDisplayName { parts.append(ageRating) }
        parts.append(
            contentsOf: SteamWorkshopResolutionFilter.allCases
                .filter { facetFilters.resolutions.contains($0) }
                .map(\.displayName)
        )
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
        downloadJobStore.activeJob(forWorkshopItemId: itemID)?.state == .running
    }

    func isQueuedForDownload(itemID: String) -> Bool {
        downloadJobStore.activeJob(forWorkshopItemId: itemID)?.state == .queued
    }

    func latestDownloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        downloads.first(where: { $0.id.utf8.elementsEqual(itemID.utf8) })
    }

    func downloadRecord(for itemID: String) -> SteamWorkshopDownloadRecord? {
        guard let record = latestDownloadRecord(for: itemID),
              record.status == .ready else {
            return nil
        }
        return record
    }

    /// 该下载记录是否正在作为当前壁纸播放（下载页卡片播放态的判定源）。
    func isRecordCurrentlyPlaying(_ record: SteamWorkshopDownloadRecord) -> Bool {
        switch record.contentType {
        case .unknown:
            return false
        case .scene:
            return SceneDaemonClient.shared.activeRecordID == record.id
        case .web:
            return isActiveWebRecord(record)
        case .video:
            guard WallpaperEngine.shared.currentPlaybackContentKind == .video,
                  let path = WallpaperEngine.shared.currentContentPath else { return false }
            return [record.exportedVideoURL, record.sourceVideoURL].compactMap { $0 }
                .contains { $0.resolvingSymlinksInPath().standardizedFileURL.path == path }
        }
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
