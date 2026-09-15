//
//  SteamWorkshopDetailRefreshSupport.swift
//  MyWallpaperX
//

import Foundation

nonisolated enum SteamWorkshopDetailRefreshSupport {
    static func needsRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        needsListRefresh(item)
    }

    static func needsDownloadedMetadataRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        item.author == "未知作者"
            || (item.authorProfileURL == nil && item.authorWorkshopURL == nil)
    }

    static func needsListRefresh(_ item: SteamWorkshopBrowserItem) -> Bool {
        item.detailFields.isEmpty
            || item.fileSizeText == nil
            || item.resolutionText == nil
            || item.workshopTypeText == nil
            || item.previewImageURL == nil
            || item.author == "未知作者"
            || (item.authorProfileURL == nil && item.authorWorkshopURL == nil)
    }

}
