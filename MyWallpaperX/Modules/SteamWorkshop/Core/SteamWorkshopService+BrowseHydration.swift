import Foundation

extension SteamWorkshopService {
    nonisolated static func maybeEnrichPreviewKind(
        for item: SteamWorkshopBrowserItem,
        requestPriority: SteamWorkshopDetailRequestPriority
    ) async throws -> SteamWorkshopBrowserItem {
        guard requestPriority == .userInitiated,
              item.previewAssetKind == .unknown,
              let previewImageURL = item.previewImageURL else {
            return item
        }

        var request = URLRequest(url: previewImageURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        let frozenRequest = request
        let mimeType = try? await SteamWorkshopDetailRequestScheduler.shared.run(
            priority: requestPriority
        ) {
            let (_, response) = try await URLSession.shared.data(for: frozenRequest)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return http.value(forHTTPHeaderField: "Content-Type")
        }
        let kind: SteamWorkshopPreviewAssetKind
        switch mimeType?.lowercased() {
        case let value? where value.contains("gif"): kind = .animatedImage
        case let value? where value.contains("image/"): kind = .stillImage
        default: kind = .unknown
        }
        return withPreviewKind(kind, item: item)
    }

    nonisolated static func withPreviewKind(
        _ previewKind: SteamWorkshopPreviewAssetKind,
        item: SteamWorkshopBrowserItem
    ) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: item.id,
            title: item.title,
            author: item.author,
            authorProfileURL: item.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL,
            hasAdultContent: item.hasAdultContent,
            summary: item.summary,
            descriptionText: item.descriptionText,
            tags: item.tags,
            workshopTypeText: item.workshopTypeText,
            ageRatingText: item.ageRatingText,
            genreText: item.genreText,
            categoryText: item.categoryText,
            dependencyIDs: item.dependencyIDs,
            previewImageURL: item.previewImageURL,
            previewVideoURL: item.previewVideoURL,
            previewAssetKind: previewKind,
            fileSizeText: item.fileSizeText,
            resolutionText: item.resolutionText,
            postedText: item.postedText,
            updatedText: item.updatedText,
            favoritesText: item.favoritesText,
            subscriptionsText: item.subscriptionsText,
            scoreText: item.scoreText,
            lifetimeFavoritesText: item.lifetimeFavoritesText,
            lifetimeSubscriptionsText: item.lifetimeSubscriptionsText,
            visibilityText: item.visibilityText,
            moderationText: item.moderationText,
            detailFields: item.detailFields,
            detailURL: item.detailURL
        )
    }

    func mergeBrowserItem(_ item: SteamWorkshopBrowserItem) {
        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index] = item
        } else {
            browserItems.append(item)
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
