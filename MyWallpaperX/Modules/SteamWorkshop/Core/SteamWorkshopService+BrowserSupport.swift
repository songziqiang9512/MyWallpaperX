//
//  SteamWorkshopService+BrowserSupport.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    nonisolated static func workshopItemIDSearchID(from query: String) -> String? {
        WallpaperProvider.workshopItemIDSearchID(from: query)
    }
}
