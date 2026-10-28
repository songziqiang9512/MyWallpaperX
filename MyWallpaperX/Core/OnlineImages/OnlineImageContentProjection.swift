import Foundation

nonisolated enum OnlineImageContentProjection {
    static func local(_ record: OnlineImageLocalRecord, url: URL, available: Bool) -> WallpaperContentItem {
        let facts = WallpaperContentLocalFacts(isPublishedLocally: true, isAvailable: available,
            canPlay: true, canDelete: true, canQuickLook: true, canExport: true, localURL: url,
            resourceRevision: record.revision.uuidString)
        var capabilities = facts.capabilities
        capabilities.insert(.openSource)
        if !available { capabilities.insert(.retryDownload) }
        return make(reference: record.assetID.reference, title: record.title,
            locator: .init(path: url.path, titleHint: record.title, mediaKind: .image, provenance: record.sourceURL.absoluteString),
            availability: facts.availability, capabilities: capabilities,
            metadata: .init(author: record.author, sourceTags: record.tags, contentRating: record.rating, fileSizeBytes: record.fileSizeBytes,
                resolutionText: "\(record.pixelWidth) × \(record.pixelHeight)", createdAt: record.firstDownloadedAt,
                sourceURL: record.sourceURL, thumbnailPath: url.path, resourceRevision: record.revision.uuidString))
    }

    static func remote(_ artwork: OnlineImageArtwork) -> WallpaperContentItem {
        var caps: WallpaperContentCapabilities = [.inspect, .openSource]
        if artwork.kind == .image, artwork.isMasked != true { caps.insert(.download) }
        if artwork.kind == .image, artwork.isMasked != true { caps.insert(.quickLook) }
        return make(reference: artwork.firstAssetID.reference, title: artwork.title,
            locator: .init(titleHint: artwork.title, mediaKind: artwork.kind == .image ? .image : .unknown,
                provenance: artwork.sourceURL.absoluteString), availability: .remote, capabilities: caps,
            metadata: .init(author: artwork.author, sourceTags: artwork.tags, contentRating: artwork.rating, fileSizeBytes: artwork.fileSizeBytes,
                resolutionText: resolution(artwork.width, artwork.height), createdAt: artwork.createdAt,
                sourceURL: artwork.sourceURL, previewURL: artwork.previewURL ?? artwork.thumbnailURL))
    }

    private static func resolution(_ width: Int?, _ height: Int?) -> String? {
        guard let width, let height else { return nil }
        return "\(width) × \(height)"
    }

    private static func make(reference: WallpaperReference, title: String, locator: WallpaperLocator,
        availability: WallpaperPublishedAvailability, capabilities: WallpaperContentCapabilities,
        metadata: WallpaperContentMetadata) -> WallpaperContentItem {
        .init(reference: reference, providerReference: reference, locator: locator, title: title,
            kind: locator.mediaKind, publishedAvailability: availability, capabilities: capabilities,
            metadata: metadata, acquisition: .idle, update: .idle, aliases: [])
    }
}
