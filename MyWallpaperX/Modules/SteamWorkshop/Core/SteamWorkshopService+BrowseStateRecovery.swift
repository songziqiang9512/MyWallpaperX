import Foundation

extension SteamWorkshopService {
    func updateBrowserScrollMetrics(
        offsetY: CGFloat,
        contentHeight _: CGFloat,
        viewportHeight _: CGFloat
    ) {
        currentBrowserScrollOffsetY = offsetY
    }

    func prioritizeVisibleBrowserItemIDs(_ ids: [String]) {
        let normalized = Array(NSOrderedSet(array: ids.filter { !$0.isEmpty })) as? [String] ?? []
        guard normalized != prioritizedVisibleBrowserItemIDs else { return }
        prioritizedVisibleBrowserItemIDs = normalized
        noteUserBrowsingActivity()
        prefetchBrowserPreviewImages(aroundVisibleIDs: normalized)
        guard !normalized.isEmpty, pendingBrowserDetailStubs.count > 1 else { return }

        let prioritizedSet = Set(normalized)
        let front = pendingBrowserDetailStubs.filter { prioritizedSet.contains($0.id) }
        guard !front.isEmpty else { return }
        let back = pendingBrowserDetailStubs.filter { !prioritizedSet.contains($0.id) }
        pendingBrowserDetailStubs = front.sorted { lhs, rhs in
            (normalized.firstIndex(of: lhs.id) ?? .max) < (normalized.firstIndex(of: rhs.id) ?? .max)
        } + back
    }

    func consumePendingBrowserScrollRestoreOffset() {
        pendingBrowserScrollRestoreOffset = nil
    }

    func loadCachedBrowserItemsIfPossible() {
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = loadBrowserCache(
            context: browseContext,
            browserContentMode: browserContentMode,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            personalSort: personalSort
        ) {
            browserItems = cached.items
            browserState = .loaded
            repairVisibleBrowserItemsIfNeeded()
        }
    }

    func repairVisibleBrowserItemsIfNeeded() {
        guard !browserItems.isEmpty else { return }
        let stubsNeedingHydration = browserItems
            .filter { SteamWorkshopDetailRefreshSupport.needsRefresh($0) }
            .map(SteamWorkshopDetailRefreshSupport.makeStub)
        guard !stubsNeedingHydration.isEmpty else { return }

        logBrowserDebug(
            "repairVisibleBrowserItemsIfNeeded context=\(browseContext.title) count=\(stubsNeedingHydration.count)"
        )
        enqueueBrowserDetailHydration(
            stubs: stubsNeedingHydration,
            context: browseContext,
            browserContentMode: browserContentMode,
            navigationVersion: navigationVersion,
            resetQueue: false
        )
    }

    func clearAllCachedState() {
        browserFetchTask?.cancel()
        browserFetchTask = nil
        cancelBrowserDetailHydration()
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        cancelActiveLoginSession()
        cancelDownloadImmediately(showFeedback: false)
        logoutImmediately()

        clearSteamWorkshopCacheDirectory(cacheDirectoryURL)
        clearSteamWorkshopCacheDirectory(Self.detailCacheDirectoryURL())
        clearSteamWorkshopCacheDirectory(runtimeInstallRootURL)
        SteamWorkshopPreviewImageCache.shared.removeAll()
        ThumbnailCache.clearDiskCache()
        Task {
            await Self.authorNameStore.clear()
        }

        browserItems = []
        displayedBrowserItems = []
        pendingBrowserScrollRestoreOffset = nil
        browserState = .idle
        isRefreshingBrowserFeed = false
        previewReloadToken += 1
        isLoadingMoreBrowserItems = false
        hasMoreBrowserItems = true
        browserNextPage = 1
        browserLoadMoreRetryAfter = .distantPast
        prefetchedBrowserPageKeys.removeAll()
        prefetchedBrowserPages.removeAll()
        pendingBrowserDetailStubs = []
        pendingBrowserDetailStubIDs.removeAll()
        browserDetailRetryCounts.removeAll()
        lastPreviewPrefetchIDSet.removeAll()
        prioritizedVisibleBrowserItemIDs = []
        selectedBrowserItem = nil
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        currentWorkshopItemID = nil
        currentPageTitle = "Steam 创意工坊"
        activeDownloadItemID = nil
        downloads = []
        downloadsQuery = ""
        downloadsSortMode = .updatedAt
        downloadsSortAscending = false
        isDownloadsMultiSelectMode = false
        selectedDownloadID = nil
        selectedDownloadIDs = []
        selectedDownloadInspectorItem = nil
        selectedDownloadDetailItem = nil
        selectedDownloadDetailError = nil
        isRefreshingSelectedDownloadDetailItem = false
        downloadError = nil
        pendingDownloadRequest = nil
        queuedDownloadRequests = []
        activeDownloadWasCancelled = false
        zoomOffset = 0

        browseContext = .discovery
        savedDiscoveryQueryBeforeAuthorBrowse = nil
        isUpdatingBrowserQueryProgrammatically = true
        browserQuery = ""
        isUpdatingBrowserQueryProgrammatically = false
        suppressAutomaticBrowseNavigation = true
        browserContentMode = .video
        source = .featured
        personalSort = .subscriptionDate
        trendingWindow = .week
        themeFilter = .all
        ageRatingFilter = .all
        resolutionFilter = .all
        categoryFilter = .all
        suppressAutomaticBrowseNavigation = false

        requestedURL = Self.makeBrowseURL(
            browserContentMode: browserContentMode,
            source: source,
            query: "",
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: 1,
            personalSort: personalSort
        )
        navigationVersion += 1
        currentPageTitle = browseContext.title
        statusMessage = "Steam 创意工坊已恢复到初始状态。下次进入时会像首次使用一样重新加载。"
    }

    private func clearSteamWorkshopCacheDirectory(_ url: URL) {
        let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard isAllowedSteamWorkshopCacheDeletionTarget(standardizedURL) else {
            assertionFailure("Refusing to clear non-cache Steam Workshop path: \(standardizedURL.path)")
            return
        }
        try? FileManager.default.removeItem(at: standardizedURL)
    }

    private func isAllowedSteamWorkshopCacheDeletionTarget(_ url: URL) -> Bool {
        let path = url.path
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        if let cacheRoot, path == cacheRoot || path.hasPrefix(cacheRoot + "/") {
            return true
        }
        if let appSupportRoot, path == appSupportRoot || path.hasPrefix(appSupportRoot + "/") {
            return true
        }
        return false
    }
}
