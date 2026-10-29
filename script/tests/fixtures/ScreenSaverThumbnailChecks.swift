import AppKit

@MainActor enum WallpaperLibraryArtworkProvider {
    // ACTUAL_ARTWORK_IDENTITY
}

@MainActor final class ScreenSaverIntegration {
    var configuration: ScreenSaverConfiguration?
}

@MainActor final class ScreenSaverCoordinator {
    static let shared = ScreenSaverCoordinator()
    var posterURL: URL?
    func publishedPosterURL() -> URL? { posterURL }
}

enum SILThumbnailLoadResult { case image(NSImage), unavailable }
@MainActor final class SILThumbnailProvider {
    struct Request {
        let cancellation: ThumbnailCacheRequestCancellation
        let complete: (SILThumbnailLoadResult) -> Void
    }
    var requests: [Request] = []
    func load(path: String, cancellation: ThumbnailCacheRequestCancellation,
              completion: @escaping (SILThumbnailLoadResult) -> Void) {
        requests.append(.init(cancellation: cancellation, complete: completion))
    }
}

@MainActor final class ThumbnailOwner {
    let integration = ScreenSaverIntegration()
    let selectedPreview = NSImageView()
    let posterLoader = SILThumbnailProvider()
    var draft = ScreenSaverPreferences()
    var selectedArtworkIdentity: WallpaperLibraryArtworkProvider.Identity?
    var selectedArtworkCancellation: (() -> Void)?
    var savedPosterURL: URL?
    var savedImage: NSImage?
    var savedArtworkCancellation: ThumbnailCacheRequestCancellation?
    var selectedRequests: [(content: WallpaperContentItem, complete: (NSImage?) -> Void)] = []
    var selectedCancellations = 0
    lazy var artworkLoader: (WallpaperContentItem, @escaping (NSImage?) -> Void) -> (() -> Void) = { [unowned self] content, complete in
        selectedRequests.append((content, complete))
        return { [weak self] in self?.selectedCancellations += 1 }
    }

    // ACTUAL_REFRESH_ARTWORK
    // ACTUAL_STOP_ARTWORK
}

@main enum ScreenSaverThumbnailChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let owner = ThumbnailOwner()
        let a = WallpaperReference(provider: .videoLibrary, sourceID: "A")
        let b = WallpaperReference(provider: .videoLibrary, sourceID: "B")
        func content(_ reference: WallpaperReference, available: Bool = true,
                     revision: String = "1", kind: WallpaperMediaKind = .video) -> WallpaperContentItem {
            .init(reference: reference, providerReference: reference,
                locator: .init(path: "/fixture/\(reference.sourceID).mp4", titleHint: reference.sourceID, mediaKind: kind),
                title: reference.sourceID, kind: kind, publishedAvailability: available ? .available : .unavailable,
                capabilities: [.play, .organize], metadata: .init(resourceRevision: revision),
                acquisition: .idle, update: .idle, aliases: [])
        }
        func publish(_ reference: WallpaperReference) {
            owner.integration.configuration = .init(content: .init(kind: .video,
                mediaGeneration: UUID().uuidString, title: reference.sourceID, sourceIdentity: reference.storageKey,
                entryRelativePath: "video.mp4", posterRelativePath: "poster.jpg"))
            ScreenSaverCoordinator.shared.posterURL = URL(fileURLWithPath: "/fixture/\(reference.sourceID)/poster.jpg")
        }
        let imageA = NSImage(size: NSSize(width: 80, height: 50))
        let imageB = NSImage(size: NSSize(width: 80, height: 50))
        var checks: [String: Bool] = [:]

        publish(a); owner.draft.reference = a
        owner.refreshArtwork(content: content(a))
        let aSelected = owner.selectedRequests[0].complete
        aSelected(imageA)
        owner.refreshArtwork(content: content(a))
        checks["unchanged-source-reuses-one-request-without-reading-published-poster"] = owner.selectedRequests.count == 1
            && owner.posterLoader.requests.isEmpty && owner.selectedPreview.image === imageA

        owner.draft.reference = b
        owner.refreshArtwork(content: content(b))
        aSelected(imageA)
        checks["late-selected-image-cannot-fill-a-new-selection"] = owner.selectedPreview.image !== imageA
            && owner.selectedCancellations == 1
        owner.selectedRequests[1].complete(imageB)
        checks["unsaved-selection-displays-its-own-thumbnail"] = owner.selectedPreview.image === imageB
            && owner.posterLoader.requests.isEmpty

        owner.refreshArtwork(content: content(b, available: false))
        checks["unrelated-published-copy-cannot-fill-a-missing-source"] = owner.selectedPreview.image !== imageA
            && owner.selectedPreview.image !== imageB && owner.posterLoader.requests.isEmpty
        publish(b)
        owner.refreshArtwork(content: content(b, available: false))
        let bPoster = owner.posterLoader.requests[0]
        checks["missing-source-requests-only-its-matching-published-copy"] = owner.savedImage == nil
            && owner.posterLoader.requests.count == 1
        bPoster.complete(.image(imageB))
        owner.refreshArtwork(content: content(b, available: false))
        checks["matching-copy-covers-removed-source-and-reuses-request"] = owner.selectedPreview.image === imageB
            && owner.posterLoader.requests.count == 1

        publish(a)
        owner.refreshArtwork(content: content(b, available: false))
        bPoster.complete(.image(imageB))
        checks["new-publication-revokes-the-old-fallback"] = owner.selectedPreview.image !== imageB
            && owner.savedImage == nil && bPoster.cancellation.cancelled
        owner.draft.reference = a
        owner.refreshArtwork(content: content(a, available: false))
        owner.posterLoader.requests[1].complete(.unavailable)
        checks["failed-poster-never-borrows-previous-content"] = owner.selectedPreview.image !== imageB
            && owner.savedImage == nil

        publish(b); owner.draft.reference = b
        owner.refreshArtwork(content: content(b, available: false))
        let pendingPoster = owner.posterLoader.requests[2]
        owner.refreshArtwork(content: content(b, revision: "2"))
        pendingPoster.complete(.image(imageA))
        let secondB = owner.selectedRequests.last!.complete
        let count = owner.selectedRequests.count
        owner.refreshArtwork(content: content(b, revision: "2"))
        checks["available-source-cancels-fallback-and-requests-once"] = owner.selectedRequests.count == count
            && count == 3 && pendingPoster.cancellation.cancelled && owner.selectedPreview.image !== imageA
        secondB(imageB)
        owner.stopArtwork()
        secondB(imageA); pendingPoster.complete(.image(imageA))
        checks["close-revokes-both-delivery-paths"] = owner.selectedPreview.image !== imageA && owner.savedImage == nil
        owner.draft.reference = a
        owner.refreshArtwork(content: content(a, kind: .scene))
        checks["non-video-drafts-do-not-load-source-artwork"] = owner.selectedRequests.count == count
        owner.stopArtwork()
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
