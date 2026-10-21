import AppKit

/// Per-container interests only. Encoded/decoded data and producer lifetime stay
/// in OLDownloadedThumbnailStore's existing shared cache.
nonisolated struct OLDownloadedThumbnailDemandState: Sendable {
    struct Request: Sendable {
        let id: UUID
        let sourceHint: String
        var sourceKey: String?
        let cancellation: ThumbnailCacheRequestCancellation
        var completed = false
        var failed = false
    }
    var requests: [Int: Request] = [:]
    var previousVisibleStart: Int?
    var scheduled = false
}

extension AppKitOLDownloadsContainerView {
    var canLoadThumbnails: Bool {
        window?.isVisible == true && window?.isMiniaturized == false && !isHiddenOrHasHiddenAncestor
    }

    func observeThumbnailWindow() {
        thumbnailWindowObservation?.invalidate()
        thumbnailWindowObservation = nil
        thumbnailWindowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        thumbnailWindowObservers.removeAll()
        guard let window else { return }
        thumbnailWindowObservation = window.observe(\.isVisible, options: [.new]) { [weak self] observed, _ in
            MainActor.assumeIsolated {
                guard let self, self.window === observed else { return }
                self.updateThumbnailWindowVisibility()
            }
        }
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            thumbnailWindowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.window === (notification.object as? NSWindow) else { return }
                    self.updateThumbnailWindowVisibility()
                }
            })
        }
    }

    func updateThumbnailWindowVisibility() {
        if canLoadThumbnails { resumeThumbnailDemand() }
        else { pauseThumbnailDemand() }
    }

    func pauseThumbnailDemand() {
        thumbnailDemand.requests.values.forEach { $0.cancellation.cancel() }
        thumbnailDemand.requests.removeAll()
        thumbnailDemand.previousVisibleStart = nil
        collectionView.visibleItems().forEach { ($0 as? AppKitOLDownloadsItem)?.endDisplayingThumbnail() }
    }

    func resumeThumbnailDemand() {
        guard canLoadThumbnails else { return }
        collectionView.visibleItems().forEach { ($0 as? AppKitOLDownloadsItem)?.beginDisplayingThumbnail() }
        scheduleThumbnailDemand()
    }

    func scheduleThumbnailDemand() {
        guard !thumbnailDemand.scheduled else { return }
        thumbnailDemand.scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.thumbnailDemand.scheduled = false
            self.applyThumbnailDemand()
        }
    }

    private func applyThumbnailDemand() {
        guard canLoadThumbnails else { pauseThumbnailDemand(); return }
        let visible = collectionView.indexPathsForVisibleItems().map(\.item).sorted()
        let first = visible.first
        let direction = first.flatMap { first in
            thumbnailDemand.previousVisibleStart.map { first == $0 ? 0 : (first > $0 ? 1 : -1) }
        } ?? 0
        thumbnailDemand.previousVisibleStart = first
        let indices = GridThumbnailPrefetchDemand.indices(visibleIndices: visible, itemCount: orderedIDs.count,
            neighborLimit: min(12, max(1, lastComputedColumns * 2)), direction: direction)
        let visibleIDs = Set(visible.compactMap { orderedIDs.indices.contains($0) ? orderedIDs[$0] : nil })
        // Retain a near->visible request until it leaves both regions. Cancelling
        // it before the visible card joins would abort its shared producer.
        let desired = Set(indices.map { orderedIDs[$0] }).union(visibleIDs)
        for (id, request) in thumbnailDemand.requests where !desired.contains(id) {
            request.cancellation.cancel()
            thumbnailDemand.requests.removeValue(forKey: id)
        }
        for index in indices {
            let id = orderedIDs[index]
            guard let entry = entriesByID[id] else { continue }
            let sourceHint = entry.thumbnailSourceKey ?? entry.localURL.standardizedFileURL.path
            if let current = thumbnailDemand.requests[id], current.sourceHint == sourceHint, !current.cancellation.cancelled {
                if !current.completed || current.failed { continue }
                if let key = current.sourceKey, OLDownloadedThumbnailStore.sharedCache.cachedImage(forKey: key) != nil { continue }
            }
            thumbnailDemand.requests[id]?.cancellation.cancel()
            let requestID = UUID()
            let cancellation = ThumbnailCacheRequestCancellation()
            thumbnailDemand.requests[id] = .init(id: requestID, sourceHint: sourceHint, sourceKey: sourceHint, cancellation: cancellation)
            OLDownloadedThumbnailStore.prefetch(entry, cancellation: cancellation) { [weak self] actualKey, image in
                guard let self, self.thumbnailDemand.requests[id]?.id == requestID else { return }
                self.thumbnailDemand.requests[id]?.sourceKey = actualKey
                self.thumbnailDemand.requests[id]?.completed = true
                self.thumbnailDemand.requests[id]?.failed = image == nil
            }
        }
    }
}

extension AppKitOLDownloadsContainerView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath) {
        if canLoadThumbnails { (item as? AppKitOLDownloadsItem)?.beginDisplayingThumbnail() }
        else { (item as? AppKitOLDownloadsItem)?.endDisplayingThumbnail() }
        scheduleThumbnailDemand()
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath) {
        (item as? AppKitOLDownloadsItem)?.endDisplayingThumbnail()
        scheduleThumbnailDemand()
    }
}
