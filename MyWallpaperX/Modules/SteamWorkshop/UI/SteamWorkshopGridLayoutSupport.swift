//
//  SteamWorkshopGridLayoutSupport.swift
//  MyWallpaperX
//

import AppKit

enum SteamWorkshopGridLayoutSupport {
    static let sectionInset = NSEdgeInsets(top: WallpaperLibraryGridMetrics.topInset,
        left: WallpaperLibraryGridMetrics.edgeInset, bottom: WallpaperLibraryGridMetrics.bottomInset,
        right: WallpaperLibraryGridMetrics.edgeInset)

    static func shouldAnimateChange(from previous: [String], to next: [String],
                                    visibleCount: Int, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, !previous.isEmpty else { return false }
        let oldIDs = Set(previous), newIDs = Set(next)
        let changes = oldIDs.symmetricDifference(newIDs).count
        return changes > 0 && changes <= max(20, visibleCount + 20)
            && previous.filter(newIDs.contains) == next.filter(oldIDs.contains)
    }
}
