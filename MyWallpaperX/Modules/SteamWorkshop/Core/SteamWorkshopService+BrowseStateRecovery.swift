import Foundation

extension SteamWorkshopService {
    func updateBrowserScrollMetrics(
        offsetY: CGFloat,
        contentHeight _: CGFloat,
        viewportHeight _: CGFloat
    ) {
        currentBrowserScrollOffsetY = offsetY
    }

    func consumePendingBrowserScrollRestoreOffset() {
        pendingBrowserScrollRestoreOffset = nil
    }

    func clearAllCachedState() {
        browserFetchTask?.cancel()
        browserFetchTask = nil
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        // 只清浏览态与派生缓存。账号会话（signOut 会删 Keychain 持久
        // 凭据）与进行中的下载不属于"清除缓存"，不得在此隐藏执行；
        // 确认弹窗的清理清单与实际行为保持一致。
        steamAuth.cancelPendingAuthentication()

        clearSteamWorkshopCacheDirectory(cacheDirectoryURL)
        clearSteamWorkshopCacheDirectory(Self.detailCacheDirectoryURL())
        SteamWorkshopPreviewImageCache.shared.removeAll()
        ThumbnailCache.clearDiskCache()

        steamKitBrowseStore.clear()
        browserItems = []
        displayedBrowserItems = []
        pendingBrowserScrollRestoreOffset = nil
        browserState = .idle
        isRefreshingBrowserFeed = false
        previewReloadToken += 1
        isLoadingMoreBrowserItems = false
        hasMoreBrowserItems = true
        browserLoadMoreFailureMessage = nil
        browserLoadMoreRetryAfter = .distantPast
        lastPreviewPrefetchIDSet.removeAll()
        selectedBrowserItem = nil
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        currentWorkshopItemID = nil
        currentPageTitle = "Steam 创意工坊"
        activeDownloadItemIDs.removeAll()
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
        // 在途/排队下载同样不属于"清除缓存"：cancelAll 会把任务持久化
        // 置 cancelled 并销毁排队意图；派生进度态清空即可，任务自身由
        // 下载管线收尾。
        downloadProgressStore.removeAll()
        zoomOffset = 0

        browseContext = .discovery
        discoveryBrowseSnapshot = nil
        savedDiscoveryQueryBeforeAuthorBrowse = nil
        isUpdatingBrowserQueryProgrammatically = true
        browserQuery = ""
        isUpdatingBrowserQueryProgrammatically = false
        suppressAutomaticBrowseNavigation = true
        browserContentMode = .video
        source = .featured
        personalSort = .subscriptionDate
        trendingWindow = .week
        facetFilters = .none
        suppressAutomaticBrowseNavigation = false

        navigationVersion += 1
        currentPageTitle = browseContext.title
        statusMessage = "Steam 创意工坊已恢复到初始状态。下次进入时会重新加载。"
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
        guard let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path else {
            return false
        }
        return path.hasPrefix(cacheRoot + "/")
    }
}
