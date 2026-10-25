import Foundation

nonisolated enum VideoLibraryContentProjection {
    static func project(_ wallpaper: VideoWallpaper, facts: WallpaperContentLocalFacts,
                        backing: WallpaperContentBackingPublication? = nil) -> WallpaperContentItem {
        let original = WallpaperReference(provider: .videoLibrary, sourceID: wallpaper.id)
        let alias = backing?.alias.flatMap { $0.alias == original ? $0 : nil }
        let reference = alias?.canonical ?? original
        var metadata = WallpaperContentMetadata()
        metadata.fileSizeBytes = wallpaper.fileSize
        metadata.durationSeconds = wallpaper.duration.map(Double.init)
        metadata.resolutionText = wallpaper.resolution
        metadata.lastUsedAt = wallpaper.lastUsed
        metadata.createdAt = wallpaper.firstIndexedAt
        metadata.thumbnailPath = wallpaper.thumbnailPath
        metadata.resourceRevision = facts.resourceRevision
        return WallpaperContentItem(
            reference: reference, providerReference: original,
            locator: WallpaperLocator(path: facts.localURL?.path ?? wallpaper.path,
                                      titleHint: wallpaper.displayTitle, mediaKind: .video,
                                      provenance: alias == nil ? "video-library" : "published-download-backing"),
            title: wallpaper.displayTitle, kind: .video, publishedAvailability: facts.availability,
            capabilities: facts.capabilities, metadata: metadata, acquisition: .idle, update: .idle,
            aliases: alias.map { [$0] } ?? [])
    }
}
