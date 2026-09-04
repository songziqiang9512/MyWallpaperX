import Foundation

extension SteamWorkshopService {
    nonisolated static func fetchWorkshopItemByIDSearch(id: String) async throws -> SteamWorkshopBrowserItem? {
        let stub = SteamWorkshopBrowseStub(
            id: id,
            title: nil,
            author: nil,
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: nil,
            previewImageURL: nil
        )

        let detailsByID = try await fetchPublishedFileDetails(
            ids: [id],
            requestPriority: .userInitiated
        )
        guard let detail = detailsByID[id],
              let workshopAppID = Int(Constants.workshopAppID),
              detail.consumerAppID == workshopAppID else {
            return nil
        }

        let resolved = await item(from: detail, stub: stub)
        let enriched = try await maybeEnrichPreviewKind(for: resolved, requestPriority: .userInitiated)
        saveDetailCache(item: enriched)
        return enriched
    }

    nonisolated static func shouldEagerlyResolvePreviewKind(
        for requestPriority: SteamWorkshopDetailRequestPriority
    ) -> Bool {
        requestPriority == .userInitiated
    }

    nonisolated static func maybeEnrichPreviewKind(
        for item: SteamWorkshopBrowserItem,
        requestPriority: SteamWorkshopDetailRequestPriority
    ) async throws -> SteamWorkshopBrowserItem {
        guard shouldEagerlyResolvePreviewKind(for: requestPriority) else {
            return item
        }
        return try await enrichPreviewKind(for: item, requestPriority: requestPriority)
    }

    func mergeBrowserItem(_ item: SteamWorkshopBrowserItem) {
        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index] = item
        } else {
            browserItems.append(item)
        }
    }

    func mergeBrowserItems(_ items: [SteamWorkshopBrowserItem]) {
        guard !items.isEmpty else { return }
        var mergedItems = browserItems
        var indexByID = Dictionary(uniqueKeysWithValues: mergedItems.enumerated().map { ($0.element.id, $0.offset) })
        var didChange = false

        for item in items {
            if let index = indexByID[item.id] {
                guard mergedItems[index] != item else { continue }
                mergedItems[index] = item
                didChange = true
            } else {
                indexByID[item.id] = mergedItems.count
                mergedItems.append(item)
                didChange = true
            }
        }

        guard didChange else { return }
        browserItems = mergedItems
    }

    func detailHydrationDelayNanoseconds(remainingCount: Int) -> UInt64 {
        switch remainingCount {
        case 12...:
            return Constants.detailHydrationFastInterBatchDelayNanoseconds
        case 4...:
            return Constants.detailHydrationNormalInterBatchDelayNanoseconds
        default:
            return Constants.detailHydrationInterBatchDelayNanoseconds
        }
    }

    func detailHydrationBatchCount(queuedCount: Int) -> Int {
        switch queuedCount {
        case Constants.detailHydrationExpandedThreshold...:
            return Constants.detailHydrationExpandedBatchSize
        case Constants.detailHydrationNormalThreshold...:
            return Constants.detailHydrationBatchSize + 1
        default:
            return Constants.detailHydrationBatchSize
        }
    }

    func noteUserBrowsingActivity() {
        let candidate = Date().addingTimeInterval(Constants.browserInteractionDeferralInterval)
        if candidate > backgroundDetailDeferralUntil {
            backgroundDetailDeferralUntil = candidate
        }
    }

    func prioritizeUserRequestedDetail() {
        backgroundDetailDeferralUntil = Date().addingTimeInterval(Constants.detailRequestDeferralInterval)
    }

    func shouldDeferBackgroundDetailWork() -> Bool {
        Date() < backgroundDetailDeferralUntil
            || isRefreshingSelectedBrowserItem
            || isRefreshingSelectedDownloadDetailItem
    }

    func prefetchBrowserPreviewImages(aroundVisibleIDs ids: [String]) {
        guard !ids.isEmpty, !displayedBrowserItems.isEmpty else { return }
        let items = displayedBrowserItems
        let indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let visibleIndexes = ids.compactMap { indexByID[$0] }.sorted()
        guard let firstVisibleIndex = visibleIndexes.first,
              let lastVisibleIndex = visibleIndexes.last else { return }
        let startIndex = max(0, firstVisibleIndex - 12)
        let endIndex = min(items.count - 1, lastVisibleIndex + 12)
        guard startIndex <= endIndex else { return }
        prefetchBrowserPreviewImages(for: Array(items[startIndex...endIndex]), limit: 24)
    }

    func prefetchBrowserPreviewImages(for items: [SteamWorkshopBrowserItem], limit: Int) {
        guard !items.isEmpty, limit > 0 else { return }
        let candidates = items.compactMap { item -> (String, URL)? in
            guard let url = item.previewImageURL else { return nil }
            return (item.id, url)
        }
        let limitedCandidates = Array(candidates.prefix(limit))
        let nextIDSet = Set(limitedCandidates.map(\.0))
        let deltaCandidates = limitedCandidates.filter { id, url in
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            let hasCachedImage = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey) != nil
            return !lastPreviewPrefetchIDSet.contains(id) || !hasCachedImage
        }
        guard !deltaCandidates.isEmpty else { return }
        lastPreviewPrefetchIDSet = nextIDSet

        for (_, url) in deltaCandidates {
            let cacheKey = steamWorkshopPreviewCacheKey(for: url)
            SteamWorkshopPreviewImageCache.shared.prefetchRawDataAsync(forKey: cacheKey) {
                await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                    from: url,
                    priority: .prefetch
                )
            }
        }
    }

    func cancelBrowserDetailHydration() {
        browserDetailHydrationTask?.cancel()
        browserDetailHydrationTask = nil
        pendingBrowserDetailStubs.removeAll()
        pendingBrowserDetailStubIDs.removeAll()
        browserDetailRetryCounts.removeAll()
    }

    func enqueueBrowserDetailHydration(
        stubs: [SteamWorkshopBrowseStub],
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        navigationVersion: Int,
        resetQueue: Bool
    ) {
        if resetQueue {
            browserDetailHydrationTask?.cancel()
            browserDetailHydrationTask = nil
            pendingBrowserDetailStubs.removeAll()
            pendingBrowserDetailStubIDs.removeAll()
            browserDetailRetryCounts.removeAll()
        }

        for stub in stubs {
            guard Self.cachedItemNeedsHydration(for: stub) else { continue }
            guard pendingBrowserDetailStubIDs.insert(stub.id).inserted else { continue }
            pendingBrowserDetailStubs.append(stub)
        }

        guard browserDetailHydrationTask == nil else { return }
        browserDetailHydrationTask = Task(priority: .utility) { [weak self] in
            await self?.runBrowserDetailHydrationQueue(
                context: context,
                browserContentMode: browserContentMode,
                navigationVersion: navigationVersion
            )
        }
    }
}
