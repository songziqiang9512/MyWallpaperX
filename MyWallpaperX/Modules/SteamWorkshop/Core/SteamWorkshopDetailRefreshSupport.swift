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
        needsListRefresh(item)
    }

    static func needsDownloadedMetadataRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        !hasAuthorName(item)
            || (item.authorProfileURL == nil && item.authorWorkshopURL == nil)
    }

    static func needsListRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        item.detailFields.isEmpty
            || item.fileSizeText == nil
            || item.resolutionText == nil
            || item.workshopTypeText == nil
            || item.previewImageURL == nil
            || !hasAuthorName(item)
            || (item.authorProfileURL == nil && item.authorWorkshopURL == nil)
    }

}
