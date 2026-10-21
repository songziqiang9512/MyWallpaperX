import Foundation

extension SteamWorkshopService {
    func mergeBrowserItem(_ item: SteamWorkshopBrowserItem) {
        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index] = item
        }
    }

    func prioritizeVisibleBrowserItemIDs(_ ids: [String], maxPixelSize: Int = 800) {
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
        prefetchBrowserPreviewImages(for: Array(items[startIndex...endIndex]), limit: 24, maxPixelSize: maxPixelSize)
    }

    private func prefetchBrowserPreviewImages(
        for items: [SteamWorkshopBrowserItem],
        limit: Int, maxPixelSize: Int
    ) {
        let candidates = items.prefix(limit).compactMap { item -> (String, URL, URL?)? in
            let sources = steamWorkshopPreviewSources(item: item, record: latestDownloadRecord(for: item.id))
            guard let url = sources.primary else { return nil }
            return (item.id, url, sources.fallback)
        }
        let nextIDSet = Set(candidates.map(\.0))
        let delta = candidates.filter { id, url, _ in
            !lastPreviewPrefetchIDSet.contains(id) || steamWorkshopCachedPreviewImage(for: url, maxPixelSize: maxPixelSize) == nil
        }
        guard !delta.isEmpty else { return }
        lastPreviewPrefetchIDSet = nextIDSet
        for (_, url, fallback) in delta {
            steamWorkshopLoadPreviewImage(from: url, maxPixelSize: maxPixelSize, priority: .prefetch) { image in
                if image == nil, let fallback, fallback != url {
                    steamWorkshopLoadPreviewImage(from: fallback, maxPixelSize: maxPixelSize, priority: .prefetch) { _ in }
                }
            }
        }
    }
}
