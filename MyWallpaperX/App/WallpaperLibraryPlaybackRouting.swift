import Foundation

/// Translates the captured canonical selection to the existing source owner.
/// The App owns no cursor, history, ticket, renderer or resource index.
@MainActor
enum WallpaperLibraryPlaybackRouting {
    static func dispatch(_ pending: WallpaperPlaybackSequence.Pending, content: WallpaperContentItem,
                         manager: WallpaperManager, workshop: SteamWorkshopService,
                         pixabay: PixabayService, images: SILService,
                         relationships: UserCollectionsSnapshot? = nil) -> Bool {
        guard manager.acceptsLibraryPlayback(pending), content.publishedAvailability.isAvailable,
              content.capabilities.contains(.play) else { return false }
        let requested = pending.proposal.entry.reference
        if requested != content.reference {
            guard let relationships,
                  let canonical = try? WallpaperLibraryQuery.canonicalReferences([requested], relationships: relationships),
                  canonical[requested] == content.reference else { return false }
        }
        let owner = content.providerReference
        switch owner.provider {
        case .videoLibrary:
            guard content.kind == .video, pending.ticket.runtime == .video,
                  let value = manager.wallpapers.first(where: { $0.id.utf8.elementsEqual(owner.sourceID.utf8) }) else { return false }
            manager.setAsWallpaper(value, libraryPending: pending)
            return true
        case .staticImageLibrary:
            guard content.kind == .image, pending.ticket.runtime == .systemStill,
                  let value = images.wallpapers.first(where: { $0.id.utf8.elementsEqual(owner.sourceID.utf8) }) else { return false }
            manager.setStaticWallpaper(URL(fileURLWithPath: value.path), libraryPending: pending)
            return true
        case .steamWorkshop:
            guard let value = workshop.latestDownloadRecord(for: owner.sourceID),
                  value.id.utf8.elementsEqual(owner.sourceID.utf8) else { return false }
            switch (content.kind, value.contentType, pending.ticket.runtime) {
            case (.video, .video, .video), (.web, .web, .web), (.scene, .scene, .scene):
                return workshop.setAsWallpaper(value, libraryPending: pending)
            default: return false
            }
        case .pixabay:
            guard content.kind == .video, pending.ticket.runtime == .video,
                  let id = Int(owner.sourceID), String(id).utf8.elementsEqual(owner.sourceID.utf8) else { return false }
            return pixabay.setLocalFileAsWallpaper(id: id, libraryPending: pending)
        case .wallhaven, .pixiv:
            let library = OnlineImageLibrary.shared
            guard content.kind == .image, pending.ticket.runtime == .systemStill,
                  let record = library.record(for: owner), record.revision.uuidString == content.metadata.resourceRevision,
                  let url = library.localURL(for: record) else { return false }
            manager.setStaticWallpaper(url, libraryPending: pending)
            return true
        }
    }
}

#if DEBUG
extension WallpaperLibraryPlaybackRouting {
    struct DiagnosticWebPreparation {
        let pending: WallpaperPlaybackSequence.Pending
        let requestID: UUID
        let cancel: () -> Void
        let isCurrent: () -> Bool
        let intentEpoch: UInt64
    }

    static func prepareDiagnosticWebProcess() -> DiagnosticWebPreparation? {
        let manager = WallpaperManager.shared
        var result: DiagnosticWebPreparation?
        manager.requestDiagnosticPlayback(reference: .init(provider: .steamWorkshop, sourceID: "debug-web-preparation"),
                                          runtime: .web) { pending in
            guard let process = SteamWorkshopService.shared.prepareWebPlaybackProcess?(pending) else { return false }
            result = DiagnosticWebPreparation(pending: pending, requestID: process.requestID,
                cancel: process.cancel, isCurrent: process.isCurrent, intentEpoch: process.intentEpoch)
            return true
        }
        return result
    }

    static func postDiagnosticWeb(entryURL: URL, rootURL: URL, recordID: String, requestID: UUID = UUID(),
                                  preparation: DiagnosticWebPreparation? = nil) {
        let manager = WallpaperManager.shared
        let post: (WallpaperPlaybackSequence.Pending) -> Bool = { pending in
            NotificationCenter.default.post(name: .steamWorkshopWebWallpaperReadyToPlay, object: nil,
                userInfo: ["requestID": requestID, "entryURL": entryURL, "rootURL": rootURL,
                    "recordID": recordID, "propertiesJSON": "{}", "language": "en-us",
                    "runtimeProfile": WallpaperEngine.WebRuntimeProfile.diagnostic,
                    "intentEpoch": pending.ticket.epoch, "libraryPending": pending])
            return true
        }
        if let preparation {
            guard preparation.requestID == requestID, manager.acceptsLibraryPlayback(preparation.pending) else { return }
            _ = post(preparation.pending)
        } else {
            manager.requestDiagnosticPlayback(reference: .init(provider: .steamWorkshop, sourceID: recordID),
                                              runtime: .web, prepare: post)
        }
    }
}
#endif
