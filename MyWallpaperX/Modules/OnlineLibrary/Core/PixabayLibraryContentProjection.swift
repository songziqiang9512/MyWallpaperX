import Foundation

/// The actual source-owned publication value; no parallel record or scan.
typealias PixabayPublishedDownload = OLDownloadedEntry

enum PixabayLibraryContentProjection {
    static func project(item: OnlineLibraryVideoItem? = nil, download: PixabayPublishedDownload? = nil,
                        sourceID explicitSourceID: Int? = nil, facts: WallpaperContentLocalFacts,
                        acquisition: WallpaperContentTransferState = .idle,
                        update: WallpaperContentTransferState = .idle,
                        backing: WallpaperContentBackingPublication? = nil) -> WallpaperContentItem? {
        guard let sourceID = download?.id ?? item?.id ?? explicitSourceID,
              explicitSourceID.map({ $0 == sourceID }) ?? true,
              item.map({ $0.id == sourceID }) ?? true else { return nil }
        let reference = WallpaperReference(provider: .pixabay, sourceID: String(sourceID))
        var capabilities = facts.capabilities
        // OnlineLibraryService can retry an initial download, but currently
        // owns neither a cancellable task handle nor a replacement-update API.
        // Keep those states visible without advertising unavailable commands.
        if !facts.isPublishedLocally && acquisition.phase == .failed { capabilities.insert(.retryDownload) }
        if !facts.isPublishedLocally && acquisition.phase == .idle { capabilities.insert(.download) }
        if item != nil { capabilities.insert(.openSource) }
        var metadata = WallpaperContentMetadata()
        metadata.author = item?.user
        metadata.sourceTags = item?.tags.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        metadata.durationSeconds = download?.duration.map(Double.init) ?? item.map { Double($0.duration) }
        let preferredFile = item.map { $0.videos.large ?? $0.videos.medium ?? $0.videos.small ?? $0.videos.tiny }
        metadata.fileSizeBytes = download.map { Int64($0.fileSize) } ?? preferredFile.flatMap { $0 }.map { Int64($0.size) }
        metadata.resolutionText = download?.resolutionString ?? item?.resolutionString
        metadata.createdAt = download?.creationDate
        metadata.modifiedAt = download?.modificationDate
        metadata.sourceURL = item.flatMap { URL(string: $0.pageURL) }
        metadata.previewURL = item?.previewThumbnailURL
        metadata.previewVideoURL = item?.videoPreviewURL
        metadata.resourceRevision = facts.resourceRevision ?? download?.thumbnailSourceKey
        let localTitle = facts.isPublishedLocally ? facts.localURL?.lastPathComponent : nil
        let title = download?.localURL.lastPathComponent ?? item?.displayTitle ?? localTitle ?? "Pixabay #\(sourceID)"
        let alias = facts.isPublishedLocally ? backing?.alias.flatMap { $0.canonical == reference ? $0 : nil } : nil
        return WallpaperContentItem(
            reference: reference, providerReference: reference,
            locator: WallpaperLocator(path: facts.localURL?.path ?? (facts.isPublishedLocally ? download?.localURL.path : nil),
                                      titleHint: title, mediaKind: .video, provenance: "pixabay-publication"),
            title: title, kind: .video, publishedAvailability: facts.availability,
            capabilities: capabilities, metadata: metadata, acquisition: acquisition, update: update,
            aliases: alias.map { [$0] } ?? [])
    }
}
