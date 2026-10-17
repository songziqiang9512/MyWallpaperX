//
//  SteamWorkshopDetailRefreshSupport.swift
//  MyWallpaperX
//

import Foundation

nonisolated enum SteamWorkshopDetailRefreshSupport {
    static func hasAuthorName(_ item: SteamWorkshopBrowserItem) -> Bool {
        let name = item.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未知作者" else { return false }
        let creator = SteamWorkshopService.creatorID(from: item.authorProfileURL)
            ?? SteamWorkshopService.creatorID(from: item.authorWorkshopURL)
        return creator.map { name != "Steam \($0)" } ?? true
    }

    static func needsRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        // List snapshots intentionally have no official detail fields. A
        // successful detail response remains valid when optional metadata
        // (resolution, preview or a public creator name) is unavailable.
        item.detailFields.isEmpty
    }

    /// Downloaded-item metadata otherwise lives forever in the persisted
    /// snapshot, so a panel open re-pulls it once per TTL. Unknown age (a
    /// legacy install without a managed snapshot) stays on the completeness
    /// check: no surprise network work. Only managed snapshots carry the
    /// timestamp back after a refresh, so legacy installs never enter TTL
    /// tracking. Browser-side metadata needs no TTL — list queries are
    /// per-session and the detail disk cache already expires at
    /// `Constants.detailCacheTTL`.
    nonisolated static let downloadedMetadataRefreshTTL: TimeInterval = 72 * 60 * 60

    static func isDownloadedMetadataStale(fetchedAt: Date?, now: Date = Date()) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) >= downloadedMetadataRefreshTTL
    }

}
