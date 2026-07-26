//
//  WallpaperManager+BundledVideos.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperManager {
    func migratedBundledVideoIndex(_ source: [VideoWallpaper]) -> [VideoWallpaper] {
        let migrated = source.map(migratedBundledVideoWallpaper)
        if migrated != source {
            scheduleWallpapersAutoPersist()
        }
        return migrated
    }

    func migratedBundledVideoWallpaper(_ wallpaper: VideoWallpaper) -> VideoWallpaper {
        guard !normalizedSourcePathExists(wallpaper.path),
              let migratedURL = BundledVideoLibrary.migratedURL(forPersistedPath: wallpaper.path) else {
            return wallpaper
        }
        return VideoWallpaper(
            id: wallpaper.id,
            title: wallpaper.title,
            path: migratedURL.path,
            thumbnailPath: wallpaper.thumbnailPath,
            staticFramePath: wallpaper.staticFramePath,
            isFavorite: wallpaper.isFavorite,
            lastUsed: wallpaper.lastUsed,
            tags: wallpaper.tags,
            fileSize: wallpaper.fileSize,
            duration: wallpaper.duration,
            resolution: wallpaper.resolution
        )
    }

    func resolveExistingWallpaperFromSnapshot(_ persistedWallpaper: VideoWallpaper) -> VideoWallpaper? {
        let wallpaper = migratedBundledVideoWallpaper(persistedWallpaper)
        guard normalizedSourcePathExists(wallpaper.path) else { return nil }
        let storedID = upsertWallpaper(wallpaper)
        return wallpapers.first(where: { $0.id == storedID }) ?? wallpaper
    }
}
