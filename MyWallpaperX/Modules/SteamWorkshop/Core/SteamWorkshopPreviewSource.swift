import AppKit

/// Browse, subscriptions and downloads use the same installed preview decision.
/// No directory scan: a failed/missing local preview falls through in PreviewState.
func steamWorkshopPreviewSources(item: SteamWorkshopBrowserItem, record: SteamWorkshopDownloadRecord?) -> (primary: URL?, fallback: URL?) {
    let remote = [item.previewImageURL, record?.browserItem?.previewImageURL]
        .compactMap { $0 }.first { !$0.isFileURL }
    if record?.status == .ready, let local = record?.previewURL, local.isFileURL {
        return (local, remote)
    }
    return (item.previewImageURL ?? remote, remote)
}

func steamWorkshopPreviewStillKey(for url: URL, maxPixelSize: Int = 800) -> String {
    let source = url.isFileURL ? steamWorkshopLocalPreviewCacheKey(for: url) : steamWorkshopPreviewCacheKey(for: url)
    return "steam-still-v1:\(maxPixelSize):\(source)"
}

func steamWorkshopCachedPreviewImage(for url: URL, maxPixelSize: Int = 800) -> NSImage? {
    SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: steamWorkshopPreviewStillKey(for: url, maxPixelSize: maxPixelSize))
}

func steamWorkshopLoadPreviewImage(
    from url: URL,
    maxPixelSize: Int = 800,
    priority: SteamWorkshopPreviewRequestPriority = .visible,
    cancellation: SteamWorkshopPreviewLoadCancellation? = nil,
    completion: @escaping (NSImage?) -> Void
) {
    let rawKey = url.isFileURL ? steamWorkshopLocalPreviewCacheKey(for: url) : steamWorkshopPreviewCacheKey(for: url)
    let stillKey = "steam-still-v1:\(maxPixelSize):\(rawKey)"
    SteamWorkshopPreviewImageCache.shared.loadImageDataAsync(
        forKey: stillKey, sourceDataKey: rawKey,
        priority: priority == .prefetch ? .prefetch : .visible,
        onPriorityPromotion: { Task { await SteamWorkshopPreviewRequestCoordinator.shared.promoteVisibleRequest(for: url) } },
        loader: { priorityProvider in
            if url.isFileURL { return try? Data(contentsOf: url) }
            return await SteamWorkshopPreviewRequestCoordinator.shared.loadData(from: url, priority: priority,
                priorityProvider: { priority == .userInitiated ? .userInitiated : (priorityProvider() == .prefetch ? .prefetch : .visible) })
        }, decoder: { steamWorkshopPreviewImage(from: $0, maxPixelSize: maxPixelSize) },
        cancellation: cancellation, completion: completion)
}

func steamWorkshopInvalidatePreview(_ url: URL) {
    let rawKey = url.isFileURL ? steamWorkshopLocalPreviewCacheKey(for: url) : steamWorkshopPreviewCacheKey(for: url)
    // Only these three pixel tiers are produced by grid/detail consumers.
    for tier in [256, 512, 800] {
        SteamWorkshopPreviewImageCache.shared.remove(forKey: "steam-still-v1:\(tier):\(rawKey)")
    }
    SteamWorkshopPreviewImageCache.shared.remove(forKey: rawKey)
}
