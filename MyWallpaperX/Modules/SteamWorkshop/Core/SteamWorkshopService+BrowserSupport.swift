//
//  SteamWorkshopService+BrowserSupport.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    nonisolated static func workshopItemIDSearchID(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count >= 6,
           trimmed.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
            return trimmed
        }
        return firstCapture(pattern: #"(?:^|[?&\s])id=(\d{6,})\b"#, in: trimmed)
    }
}
