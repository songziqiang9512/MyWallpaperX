import Foundation

extension SteamWorkshopService {
    func enterBrowseSection(_ section: SteamWorkshopBrowseSection) {
        let current: SteamWorkshopBrowseSection = source.isPersonal ? .personal : .discovery
        guard current != section else { return }
        dismissItemDetail()
        if steamKitBrowseStore.currentKey != nil,
           !source.isPersonal || (steamAuth.isOnline && steamKitBrowseStore.currentKey?.accountSteamID == steamAuth.steamId) {
            retainedBrowseSections[current] = makeDiscoveryBrowseSnapshot()
        } else {
            retainedBrowseSections.removeValue(forKey: current)
        }
        browserFetchTask?.cancel()
        browserFetchTask = nil
        cancelSelectedItemDetailRefresh()
        selectedBrowserItem = nil
        navigationVersion += 1
        suppressAutomaticBrowseNavigation = true
        defer { suppressAutomaticBrowseNavigation = false }
        if let saved = retainedBrowseSections[section],
           section != .personal || (steamAuth.isOnline && saved.steamKitBrowseSnapshot.key?.accountSteamID == steamAuth.steamId) {
            source = saved.source
            browserContentMode = saved.browserContentMode
            facetFilters = saved.facetFilters
            personalSort = saved.personalSort
            trendingWindow = saved.trendingWindow
            restoreDiscoveryBrowseSnapshot(saved, restoredQuery: saved.browserQuery)
            return
        }
        source = section == .personal ? .mySubscriptions : .featured
        browserContentMode = .all
        facetFilters = .none
        setBrowserQuery("")
        steamKitBrowseStore.clear()
        browserItems = []
        browserState = .idle
        currentBrowserScrollOffsetY = 0
        pendingBrowserScrollRestoreOffset = 0
        navigateToBrowse()
    }

    func invalidatePersonalBrowseSnapshot(discard: Bool = false) {
        if discard {
            retainedBrowseSections.removeValue(forKey: .personal)
            if discoveryBrowseSnapshot?.source.isPersonal == true { discoveryBrowseSnapshot = nil }
            if steamKitBrowseStore.currentKey?.route == .personal { steamKitBrowseStore.clear() }
        } else {
            // Membership changes expire content, not the user's search and filters.
            retainedBrowseSections[.personal]?.steamKitBrowseSnapshot.refreshedAt = nil
            if discoveryBrowseSnapshot?.source.isPersonal == true {
                discoveryBrowseSnapshot?.steamKitBrowseSnapshot.refreshedAt = nil
            }
            if steamKitBrowseStore.currentKey?.route == .personal { steamKitBrowseStore.invalidateFreshness() }
        }
    }

    func showAuthorWorkshop(for item: SteamWorkshopBrowserItem) {
        guard let workshopURL = Self.resolvedAuthorWorkshopURL(for: item) else { return }
        dismissItemDetail()
        dismissDownloadInspector()
        if case let .authorWorkshop(_, currentURL) = browseContext,
           let creator = Self.creatorID(from: workshopURL),
           Self.creatorID(from: currentURL) == creator,
           browserState == .loaded || browserState == .loading {
            // Reopening the current author is navigation, not a refresh. Keep
            // loaded pages, search, continuation and scroll position intact.
            requestSteamWorkshopBrowserSelection()
            return
        }
        if !browseContext.isAuthorWorkshop {
            discoveryBrowseSnapshot = makeDiscoveryBrowseSnapshot()
        }
        savedDiscoveryQueryBeforeAuthorBrowse = browseContext.isAuthorWorkshop ? savedDiscoveryQueryBeforeAuthorBrowse : browserQuery
        // 阻止后续 filter 属性 didSet 触发 navigateToBrowse()，避免在作者工坊语境下误抓取
        suppressAutomaticBrowseNavigation = true
        browseContext = .authorWorkshop(
            authorName: item.author.isEmpty ? "未知作者" : item.author,
            workshopURL: workshopURL
        )
        setBrowserQuery("")
        navigationVersion += 1
        currentWorkshopItemID = nil
        currentPageTitle = browseContext.isAuthorWorkshop ? browseContext.title : source.pageTitle
        statusMessage = "正在加载作者工坊列表…"
        fetchBrowserItems()
        requestSteamWorkshopBrowserSelection()
    }

    func returnToDiscoveryBrowse() {
        guard browseContext.isAuthorWorkshop else { return }
        browserFetchTask?.cancel()
        browserFetchTask = nil
        dismissItemDetail()
        dismissDownloadInspector()
        navigationVersion += 1
        let restoredQuery = savedDiscoveryQueryBeforeAuthorBrowse ?? ""
        savedDiscoveryQueryBeforeAuthorBrowse = nil
        browseContext = .discovery
        if let snapshot = discoveryBrowseSnapshot {
            restoreDiscoveryBrowseSnapshot(snapshot, restoredQuery: restoredQuery)
        } else {
            setBrowserQuery(restoredQuery)
            navigateToBrowse()
        }
        discoveryBrowseSnapshot = nil
        suppressAutomaticBrowseNavigation = false
        prepareForBrowserEntry()
    }

    func handleBrowserQueryChanged() {
        if browseContext.isAuthorWorkshop {
            updateDisplayedBrowserItems()
        } else {
            navigateToBrowse()
        }
    }

    func setBrowserQuery(_ query: String) {
        isUpdatingBrowserQueryProgrammatically = true
        browserQuery = query
        isUpdatingBrowserQueryProgrammatically = false
        updateDisplayedBrowserItems()
    }

    func updateDisplayedBrowserItems() {
        guard browseContext.isAuthorWorkshop else {
            if source == .mySubscriptions {
                steamSubscriptions.synchronizeAccount()
                displayedBrowserItems = browserItems.filter { steamSubscriptions.states[$0.id] != .known(false) }
            } else {
                displayedBrowserItems = browserItems
            }
            return
        }

        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            displayedBrowserItems = browserItems
            return
        }

        let normalizedQuery = query.localizedLowercase
        let idQuery = Self.workshopItemIDSearchID(from: query)?.localizedLowercase ?? normalizedQuery
        displayedBrowserItems = browserItems.filter {
            $0.title.localizedLowercase.contains(normalizedQuery)
                || $0.author.localizedLowercase.contains(normalizedQuery)
                || $0.summary.localizedLowercase.contains(normalizedQuery)
                || $0.descriptionText.localizedLowercase.contains(normalizedQuery)
                || $0.tags.contains(where: { $0.localizedLowercase.contains(normalizedQuery) })
                || $0.id.localizedLowercase.contains(idQuery)
        }

        // Search is explicitly local to loaded author pages. A no-match query
        // must not silently drain the author's entire collection.
    }

    /// A confirmed removal changes one membership, not the user's loaded feed.
    /// Retire older pages and replay the overlapping remote page on continuation
    /// because offset pagination shifts when an earlier subscription is removed.
    func reconcileSubscriptionWrite(itemID: String, isSubscribed: Bool) {
        invalidatePersonalBrowseSnapshot()
        guard source == .mySubscriptions, shouldUseSteamKitPersonal else { return }
        if isSubscribed {
            if !browserItems.contains(where: { $0.id == itemID }) {
                fetchBrowserItems(forceRefresh: true)
            } else {
                updateDisplayedBrowserItems()
            }
            return
        }
        guard steamKitBrowseStore.removeSubscribedItem(itemID) else {
            updateDisplayedBrowserItems()
            return
        }
        browserFetchTask?.cancel()
        browserFetchTask = nil
        isLoadingMoreBrowserItems = false
        isRefreshingBrowserFeed = false
        browserLoadMoreFailureMessage = nil
        browserLoadMoreRetryAfter = .distantPast
        consecutiveEmptyLoadMorePages = 0
        browserItems.removeAll { $0.id == itemID }
        if browserState == .loading {
            fetchBrowserItems(forceRefresh: true)
            return
        }
        statusMessage = "已加载 \(browserItems.count) 项。排序和筛选仅作用于已加载项目。"
    }

    func makeDiscoveryBrowseSnapshot() -> SteamWorkshopDiscoveryBrowseSnapshot {
        SteamWorkshopDiscoveryBrowseSnapshot(
            browserContentMode: browserContentMode,
            browserItems: browserItems,
            browserState: browserState,
            hasMoreBrowserItems: hasMoreBrowserItems,
            browserLoadMoreFailureMessage: browserLoadMoreFailureMessage,
            statusMessage: isRefreshingBrowserFeed ? "已加载 \(browserItems.count) 项。" : statusMessage,
            currentPageTitle: currentPageTitle,
            browserQuery: browserQuery,
            currentWorkshopItemID: currentWorkshopItemID,
            selectedBrowserItem: selectedBrowserItem,
            scrollOffsetY: pendingBrowserScrollRestoreOffset ?? currentBrowserScrollOffsetY,
            steamKitBrowseSnapshot: steamKitBrowseStore.snapshot(),
            source: source,
            facetFilters: facetFilters,
            personalSort: personalSort,
            trendingWindow: trendingWindow,
            consecutiveEmptyLoadMorePages: consecutiveEmptyLoadMorePages,
            browserLoadMoreRetryAfter: browserLoadMoreRetryAfter
        )
    }

    func restoreDiscoveryBrowseSnapshot(
        _ snapshot: SteamWorkshopDiscoveryBrowseSnapshot,
        restoredQuery: String
    ) {
        let savedKey = snapshot.steamKitBrowseSnapshot.key
        let personalSnapshotIsCurrent = !source.isPersonal || (
            steamAuth.isOnline && savedKey == steamKitBrowseStore.makePersonalKey(
                source: source, accountSteamID: steamAuth.steamId, contentMode: browserContentMode,
                filters: facetFilters, search: restoredQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                window: trendingWindow, personalSort: personalSort))
        // A detail lookup has no personal key; reload it through the normal
        // route rather than restoring account-unscoped cached personal content.
        guard snapshot.browserContentMode == browserContentMode, personalSnapshotIsCurrent else {
            setBrowserQuery(restoredQuery)
            navigateToBrowse()
            return
        }
        guard snapshot.browserState == .loaded else {
            // The request captured before entering an author page was
            // invalidated. Restoring its spinner cannot resume that request.
            setBrowserQuery(restoredQuery)
            navigateToBrowse()
            return
        }
        setBrowserQuery(restoredQuery)
        selectedBrowserItemError = nil
        isRefreshingSelectedBrowserItem = false
        steamKitBrowseStore.restore(snapshot.steamKitBrowseSnapshot)
        steamSubscriptions.synchronizeAccount()
        let cachedIDs = snapshot.steamKitBrowseSnapshot.rawItems.map(\.publishedFileId)
            + snapshot.steamKitBrowseSnapshot.partialErrors.map(\.publishedFileId)
            + snapshot.browserItems.map(\.id)
        let removedIDs = Set(cachedIDs.filter {
            source == .mySubscriptions && steamSubscriptions.states[$0] == .known(false)
        })
        for id in removedIDs { steamKitBrowseStore.removeSubscribedItem(id) }
        browserItems = snapshot.browserItems.filter { !removedIDs.contains($0.id) }
        browserState = snapshot.browserState
        hasMoreBrowserItems = snapshot.hasMoreBrowserItems
        isLoadingMoreBrowserItems = false
        isRefreshingBrowserFeed = false
        browserLoadMoreFailureMessage = snapshot.browserLoadMoreFailureMessage
        browserLoadMoreRetryAfter = snapshot.browserLoadMoreRetryAfter
        consecutiveEmptyLoadMorePages = snapshot.consecutiveEmptyLoadMorePages
        statusMessage = snapshot.statusMessage
        currentPageTitle = snapshot.currentPageTitle
        currentWorkshopItemID = snapshot.currentWorkshopItemID
        if let selectedID = snapshot.selectedBrowserItem?.id {
            selectedBrowserItem = snapshot.browserItems.first(where: { $0.id == selectedID }) ?? snapshot.selectedBrowserItem
        } else {
            selectedBrowserItem = nil
        }
        pendingBrowserScrollRestoreOffset = snapshot.scrollOffsetY
    }

    func requestSteamWorkshopBrowserSelection() {
        NotificationCenter.default.post(
            name: .appKitSelectItemRequested,
            object: nil,
            userInfo: ["selectedItem": source.isPersonal ? "steamSubscribed" : "steamWorkshop",
                       "preserveSteamBrowseContext": true]
        )
    }
}
