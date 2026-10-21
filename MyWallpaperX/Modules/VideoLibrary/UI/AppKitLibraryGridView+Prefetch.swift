import AppKit

extension AppKitLibraryGridContainerView {
    var thumbnailDemandIsVisible: Bool {
        window?.isVisible == true && window?.isMiniaturized == false && !isHiddenOrHasHiddenAncestor
    }

    func scheduleViewportPrefetch() {
        guard thumbnailDemandIsVisible else { cancelViewportPrefetch(); return }
        // Leading coalescing: subsequent bounds events update the viewport but
        // never postpone this work indefinitely during a continuous gesture.
        for case let card as AppKitWallpaperItem in collectionView.visibleItems() { card.setThumbnailVisible(true) }
        guard viewportPrefetchWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewportPrefetchWorkItem = nil
            self.prefetchCurrentViewport()
        }
        viewportPrefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    func cancelViewportPrefetch() {
        viewportPrefetchWorkItem?.cancel()
        viewportPrefetchWorkItem = nil
        lastPrefetchOffsetY = nil
        thumbnailProvider.cancelAllPrefetch()
        for case let card as AppKitWallpaperItem in collectionView.visibleItems() { card.setThumbnailVisible(false) }
    }

    private func prefetchCurrentViewport() {
        guard thumbnailDemandIsVisible else {
            cancelViewportPrefetch(); return
        }
        let offset = collectionView.visibleRect.minY
        let direction = lastPrefetchOffsetY.map { offset == $0 ? 0 : (offset > $0 ? 1 : -1) } ?? 0
        lastPrefetchOffsetY = offset
        let visible = collectionView.indexPathsForVisibleItems().map(\.item)
        // One nearby row on each side, with the next travel direction first.
        let columns = max(1, wallpaperManager.visibleGridColumnCount)
        let indices = GridThumbnailPrefetchDemand.indices(visibleIndices: visible, itemCount: orderedIDs.count,
                                                         neighborLimit: min(24, columns * 2), direction: direction)
        thumbnailProvider.replacePrefetch(with: indices.compactMap { wallpapersByID[orderedIDs[$0]] },
            retainingVisible: visible.compactMap { index in
                guard index >= 0, index < orderedIDs.count else { return nil }
                return wallpapersByID[orderedIDs[index]]
            })
    }
}
