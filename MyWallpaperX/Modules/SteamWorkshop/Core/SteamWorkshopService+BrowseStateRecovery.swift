import Foundation

extension SteamWorkshopService {
    /// Uncovered document viewport coordinates: zero is the real top even
    /// when AppKit places the native clip origin below an overlapping toolbar.
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

    func clearAllCachedState(completion: (@Sendable () -> Void)? = nil) {
        browserFetchTask?.cancel()
        browserFetchTask = nil
        cancelSelectedItemDetailRefresh()
        // 只清浏览态与派生缓存。账号会话（signOut 会删 Keychain 持久
        // 凭据）与进行中的下载不属于"清除缓存"，不得在此隐藏执行；
        // 确认弹窗的清理清单与实际行为保持一致。
        steamAuth.cancelPendingAuthentication()

        SteamWorkshopDownloadThumbnailPipeline.shared.invalidateCachedResults()
        // ItemDetails is already inside this owned cache root. Detach it once;
        // utility deletion must never revisit the path used by new requests.
        let directory = cacheDirectoryURL
        let retired = directory.appendingPathExtension("clear-" + UUID().uuidString)
        let detached: Bool
        do { try FileManager.default.moveItem(at: directory, to: retired); detached = true }
        catch { detached = false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SteamWorkshopPreviewImageCache.shared.clearAll {
            DispatchQueue.global(qos: .utility).async {
                if detached { try? FileManager.default.removeItem(at: retired) }
                if let completion { DispatchQueue.main.async(execute: completion) }
            }
        }

        steamKitBrowseStore.clear()
        retainedBrowseSections.removeAll()
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
        selectedBrowserItem = nil
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        currentWorkshopItemID = nil
        currentPageTitle = "Steam 创意工坊"
        activeDownloadItemIDs.removeAll()
        downloads = []
        selectedDownloadInspectorItem = nil
        selectedDownloadDetailItem = nil
        selectedDownloadDetailError = nil
        isRefreshingSelectedDownloadDetailItem = false
        downloadError = nil
        // 在途/排队下载同样不属于"清除缓存"：cancelAll 会把任务持久化
        // 置 cancelled 并销毁排队意图；派生进度态清空即可，任务自身由
        // 下载管线收尾。
        downloadProgressStore.removeAll()

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
        statusMessage = "Steam 创意工坊已恢复到初始状态。"
        // The unified grid no longer owns a didMoveToWindow reload. Cache
        // clearing is the explicit refresh intent; use the original single-flight
        // source scan once, independently of later queries or page changes.
        reloadInstalledItems()
    }

}
