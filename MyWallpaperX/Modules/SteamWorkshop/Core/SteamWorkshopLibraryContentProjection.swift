import Foundation

nonisolated enum SteamWorkshopLibraryContentProjection {
    static func project(record: SteamWorkshopDownloadRecord? = nil, browserItem: SteamWorkshopBrowserItem? = nil,
                        facts: WallpaperContentLocalFacts,
                        progress: SteamWorkshopDownloadProgressSnapshot? = nil,
                        acquisition: WallpaperContentTransferState? = nil,
                        update: WallpaperContentTransferState? = nil,
                        backing: WallpaperContentBackingPublication? = nil) -> WallpaperContentItem? {
        let browser = browserItem ?? record?.browserItem
        guard let sourceID = record?.id ?? browser?.id, !sourceID.isEmpty,
              browser.map({ $0.id.utf8.elementsEqual(sourceID.utf8) }) ?? true else { return nil }
        let reference = WallpaperReference(provider: .steamWorkshop, sourceID: sourceID)
        let kind = mediaKind(record?.contentType, text: browser?.workshopTypeText)
        let matchingProgress = progress.flatMap { $0.itemID.utf8.elementsEqual(sourceID.utf8) ? $0 : nil }
        let derived = transfer(record?.status, progress: matchingProgress)
        let initial = acquisition ?? (facts.isPublishedLocally ? .idle : derived)
        let replacement = update ?? (facts.isPublishedLocally ? derived : .idle)
        var capabilities = facts.capabilities
        // A failed initial intent has no published media, but the existing
        // Steam owner can still discard that local task/history entry.
        if let record, case .failed = record.status, facts.canDelete { capabilities.insert(.delete) }
        if initial.canCancel || replacement.canCancel { capabilities.insert(.cancelDownload) }
        if initial.phase == .failed { capabilities.insert(.retryDownload) }
        if replacement.phase == .failed { capabilities.insert(.retryUpdate) }
        if !facts.isPublishedLocally && initial.phase == .idle { capabilities.insert(.download) }
        // Numeric validation belongs only to the Steam remote API action. It
        // never excludes a local opaque ID such as video:<stem> from the grid.
        if UInt64(sourceID) != nil { capabilities.insert(.subscribe) }
        if browser != nil { capabilities.insert(.openSource) }
        var metadata = WallpaperContentMetadata()
        metadata.author = browser?.author
        metadata.summary = browser?.summary ?? record?.description
        metadata.descriptionText = record?.description ?? browser?.descriptionText
        metadata.sourceTags = browser?.tags ?? []
        for tag in record?.tags ?? [] where !metadata.sourceTags.contains(tag) { metadata.sourceTags.append(tag) }
        metadata.fileSizeBytes = record?.sizeBytes
        metadata.resolutionText = browser?.resolutionText
        metadata.createdAt = record?.createdAt
        metadata.modifiedAt = record?.updatedAt
        metadata.sourceURL = browser?.detailURL
        metadata.previewURL = record?.previewURL ?? browser?.previewImageURL
        metadata.previewVideoURL = browser?.previewVideoURL
        metadata.resourceRevision = facts.resourceRevision
        metadata.detailFields = browser?.detailFields.map { .init(label: $0.label, value: $0.value) } ?? []
        let title = browser?.title ?? record?.title ?? sourceID
        let alias = facts.isPublishedLocally ? backing?.alias.flatMap { $0.canonical == reference ? $0 : nil } : nil
        return WallpaperContentItem(
            reference: reference, providerReference: reference,
            locator: WallpaperLocator(path: facts.localURL?.path ?? (facts.isPublishedLocally ? record?.folderURL.path : nil),
                                      titleHint: title, mediaKind: kind, provenance: "steam-workshop-publication"),
            title: title, kind: kind, publishedAvailability: facts.availability,
            capabilities: capabilities, metadata: metadata, acquisition: initial, update: replacement,
            aliases: alias.map { [$0] } ?? [])
    }

    private static func mediaKind(_ contentType: SteamWorkshopDownloadContentType?, text: String?) -> WallpaperMediaKind {
        switch contentType {
        case .video: return .video
        case .web: return .web
        case .scene: return .scene
        case .unknown, nil:
            switch text?.lowercased() {
            case "video", "视频", "视频壁纸": return .video
            case "web", "web壁纸": return .web
            case "scene", "场景", "场景壁纸": return .scene
            default: return .unknown
            }
        }
    }

    static func transfer(_ status: SteamWorkshopDownloadRecord.Status?,
                                 progress: SteamWorkshopDownloadProgressSnapshot?) -> WallpaperContentTransferState {
        if let progress {
            let phase: WallpaperContentTransferState.Phase
            switch progress.phase {
            case .connecting: phase = .connecting
            case .preparing: phase = .preparing
            case .transferring: phase = .transferring
            case .validating: phase = .validating
            case .saving: phase = .publishing
            case .waiting: phase = .waiting
            case .failed: phase = .failed
            }
            return WallpaperContentTransferState(phase: phase, totalBytes: progress.totalBytes,
                                                 completedBytes: progress.verifiedBytes,
                                                 failureMessage: progress.failureMessage,
                                                 jobKey: progress.jobKey,
                                                 attempt: progress.attempt, sequence: progress.sequence)
        }
        switch status {
        case .queued: return .init(phase: .queued)
        case .downloading: return .init(phase: .transferring)
        case .failed(let message): return .init(phase: .failed, failureMessage: message)
        case .ready, nil: return .idle
        }
    }
}
