import Foundation

extension SteamWorkshopService {
    func mergeBrowserItem(_ item: SteamWorkshopBrowserItem) {
        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index] = item
        }
    }

    func prioritizeVisibleBrowserItemIDs(_ ids: [String]) {
        let normalized = Array(NSOrderedSet(array: ids.filter { !$0.isEmpty })) as? [String] ?? []
        guard !normalized.isEmpty, !displayedBrowserItems.isEmpty else { return }
        let items = displayedBrowserItems
        let indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let visibleIndexes = normalized.compactMap { indexByID[$0] }.sorted()
        guard let firstVisibleIndex = visibleIndexes.first,
              let lastVisibleIndex = visibleIndexes.last else { return }
        let startIndex = max(0, firstVisibleIndex - 12)
        let endIndex = min(items.count - 1, lastVisibleIndex + 12)
        guard startIndex <= endIndex else { return }
        prefetchBrowserPreviewImages(for: Array(items[startIndex...endIndex]), limit: 24)
    }

    private func prefetchBrowserPreviewImages(
        for items: [SteamWorkshopBrowserItem],
        limit: Int
    ) {
        let candidates = items.prefix(limit).compactMap { item -> (String, URL)? in
            guard let url = item.previewImageURL else { return nil }
            return (item.id, url)
        }
        let nextIDSet = Set(candidates.map(\.0))
        let delta = candidates.filter { id, url in
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            return !lastPreviewPrefetchIDSet.contains(id)
                || SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey) == nil
        }
        guard !delta.isEmpty else { return }
        lastPreviewPrefetchIDSet = nextIDSet
        for (_, url) in delta {
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            SteamWorkshopPreviewImageCache.shared.prefetchRawDataAsync(forKey: cacheKey) {
                await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                    from: url,
                    priority: .prefetch
                )
            }
        }
    }
}
