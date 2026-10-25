import Foundation

enum StaticImageLibraryContentProjection {
    static func project(_ wallpaper: SILWallpaper, facts: WallpaperContentLocalFacts) -> WallpaperContentItem {
        let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: wallpaper.id)
        var metadata = WallpaperContentMetadata()
        metadata.fileSizeBytes = wallpaper.fileSize
        if let width = wallpaper.pixelWidth, let height = wallpaper.pixelHeight {
            metadata.resolutionText = "\(width)×\(height)"
        }
        metadata.createdAt = wallpaper.addedAt
        metadata.lastUsedAt = wallpaper.lastUsed
        metadata.resourceRevision = facts.resourceRevision
        let title = wallpaper.title.isEmpty ? URL(fileURLWithPath: wallpaper.path).lastPathComponent : wallpaper.title
        return WallpaperContentItem(
            reference: reference, providerReference: reference,
            locator: WallpaperLocator(path: facts.localURL?.path ?? wallpaper.path, titleHint: title,
                                      mediaKind: .image, provenance: "static-image-library"),
            title: title, kind: .image, publishedAvailability: facts.availability,
            capabilities: facts.capabilities, metadata: metadata, acquisition: .idle, update: .idle, aliases: [])
    }
}
