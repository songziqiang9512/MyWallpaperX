import Foundation

extension SteamWorkshopService {
    func runBrowserDetailHydrationQueue(
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        navigationVersion: Int
    ) async {
        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.navigationVersion == navigationVersion,
                   self.browseContext == context,
                   self.browserContentMode == browserContentMode {
                    self.statusMessage = self.completedStatusMessage(
                        for: context,
                        totalCount: self.browserItems.count,
                        hasMore: self.hasMoreBrowserItems
                    )
                    self.saveBrowserCache(
                        context: context,
                        browserContentMode: browserContentMode,
                        source: self.source,
                        query: self.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                        trendingWindow: self.trendingWindow,
                        themeFilter: self.themeFilter,
                        ageRatingFilter: self.ageRatingFilter,
                        resolutionFilter: self.resolutionFilter,
                        categoryFilter: self.categoryFilter,
                        items: self.browserItems,
                        personalSort: self.personalSort
                    )
                }
                self.browserDetailHydrationTask = nil
            }
        }

        while !Task.isCancelled {
            let shouldDefer = await MainActor.run { self.shouldDeferBackgroundDetailWork() }
            if shouldDefer {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }

            let stubs: [SteamWorkshopBrowseStub] = await MainActor.run {
                guard self.navigationVersion == navigationVersion,
                      self.browseContext == context,
                      self.browserContentMode == browserContentMode else {
                    self.pendingBrowserDetailStubs.removeAll()
                    self.pendingBrowserDetailStubIDs.removeAll()
                    self.browserDetailRetryCounts.removeAll()
                    return []
                }
                guard !self.pendingBrowserDetailStubs.isEmpty else { return [] }
                let batchCount = min(
                    self.detailHydrationBatchCount(queuedCount: self.pendingBrowserDetailStubs.count),
                    self.pendingBrowserDetailStubs.count
                )
                let nextBatch = Array(self.pendingBrowserDetailStubs.prefix(batchCount))
                self.pendingBrowserDetailStubs.removeFirst(batchCount)
                nextBatch.forEach { self.pendingBrowserDetailStubIDs.remove($0.id) }
                return nextBatch
            }

            guard !stubs.isEmpty else { break }

            do {
                let items = try await Self.fetchWorkshopItems(
                    stubs: stubs,
                    browserContentMode: browserContentMode,
                    requestPriority: .background
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == navigationVersion,
                          self.browseContext == context,
                          self.browserContentMode == browserContentMode else { return }
                    let visibleItems = self.visibleItemsAfterApplyingAgeRating(items)
                    self.removeAgeFilteredStubs(stubs, keeping: visibleItems)
                    for item in visibleItems {
                        self.browserDetailRetryCounts[item.id] = nil
                    }
                    self.mergeBrowserItems(visibleItems)
                    if let selectedID = self.selectedBrowserItem?.id,
                       let refreshedSelected = visibleItems.first(where: { $0.id == selectedID }) {
                        self.selectedBrowserItem = refreshedSelected
                        self.selectedBrowserItemError = nil
                    }
                    self.logBrowserDebug(
                        "detail hydration success batchCount=\(items.count) remainingQueue=\(self.pendingBrowserDetailStubs.count)"
                    )
                }
                let remainingCount = await MainActor.run { self.pendingBrowserDetailStubs.count }
                try? await Task.sleep(nanoseconds: detailHydrationDelayNanoseconds(remainingCount: remainingCount))
            } catch {
                guard !Task.isCancelled else { return }
                let nsError = error as NSError
                let isRateLimited = nsError.domain == NSURLErrorDomain && nsError.code == 429
                let isTransientNetworkFailure = nsError.domain == NSURLErrorDomain
                let attempt = await MainActor.run { () -> Int in
                    var highestAttempt = 0
                    for stub in stubs {
                        let next = (self.browserDetailRetryCounts[stub.id] ?? 0) + 1
                        self.browserDetailRetryCounts[stub.id] = next
                        highestAttempt = max(highestAttempt, next)
                    }
                    return highestAttempt
                }

                if isRateLimited, attempt <= 4 {
                    await MainActor.run {
                        for stub in stubs.reversed() {
                            if self.pendingBrowserDetailStubIDs.insert(stub.id).inserted {
                                self.pendingBrowserDetailStubs.insert(stub, at: 0)
                            }
                        }
                        self.logBrowserDebug(
                            "detail hydration rate-limited batchCount=\(stubs.count) attempt=\(attempt) queueCount=\(self.pendingBrowserDetailStubs.count)"
                        )
                    }
                    let backoffSeconds = UInt64(min(20, attempt * 4))
                    try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                    continue
                }

                if isTransientNetworkFailure, attempt <= 2 {
                    await MainActor.run {
                        for stub in stubs {
                            if self.pendingBrowserDetailStubIDs.insert(stub.id).inserted {
                                self.pendingBrowserDetailStubs.append(stub)
                            }
                        }
                        self.logBrowserDebug(
                            "detail hydration transient retry batchCount=\(stubs.count) attempt=\(attempt) queueCount=\(self.pendingBrowserDetailStubs.count) code=\(nsError.code)"
                        )
                    }
                    let backoffSeconds = UInt64(min(8, attempt * 2))
                    try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                    continue
                }

                await MainActor.run {
                    self.logBrowserDebug(
                        "detail hydration failed batchCount=\(stubs.count) code=\(nsError.code) domain=\(nsError.domain) error=\(nsError.localizedDescription)"
                    )
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func prefetchUpcomingBrowserPageIfNeeded(
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int,
        personalSort: SteamWorkshopPersonalSort = .subscriptionDate,
        lookaheadDepth: Int = 0
    ) {
        // 个人库使用单一的、带登录态的 WebView。预取会与用户主动翻页争用该 WebView，
        // 导致 WebKit 取消前一个导航并返回 NSURLErrorCancelled (-999)。
        guard !source.isPersonal, page > 1 else { return }
        let key = browserPagePrefetchKey(
            context: context,
            browserContentMode: browserContentMode,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: page,
            personalSort: personalSort
        )
        guard prefetchedBrowserPageKeys.insert(key).inserted else { return }
        let expectedNavigationVersion = navigationVersion

        Task(priority: .utility) {
            guard let pageResult = try? await Self.fetchWorkshopStubPage(
                context: context,
                browserContentMode: browserContentMode,
                source: source,
                query: query,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter,
                page: page,
                personalSort: personalSort
            ), !pageResult.stubs.isEmpty else {
                return
            }
            await MainActor.run {
                guard self.navigationVersion == expectedNavigationVersion,
                      self.browseContext == context,
                      self.browserContentMode == browserContentMode,
                      self.source == source,
                      self.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                      self.trendingWindow == trendingWindow,
                      self.themeFilter == themeFilter,
                      self.ageRatingFilter == ageRatingFilter,
                      self.resolutionFilter == resolutionFilter,
                      self.categoryFilter == categoryFilter,
                      self.personalSort == personalSort else {
                    return
                }
                self.prefetchedBrowserPages[key] = pageResult
            }
            guard lookaheadDepth > 0, pageResult.hasMore else { return }
            await MainActor.run {
                guard self.navigationVersion == expectedNavigationVersion else { return }
                self.prefetchUpcomingBrowserPageIfNeeded(
                    context: context,
                    browserContentMode: browserContentMode,
                    source: source,
                    query: query,
                    trendingWindow: trendingWindow,
                    themeFilter: themeFilter,
                    ageRatingFilter: ageRatingFilter,
                    resolutionFilter: resolutionFilter,
                    categoryFilter: categoryFilter,
                    page: page + 1,
                    personalSort: personalSort,
                    lookaheadDepth: lookaheadDepth - 1
                )
            }
        }
    }

    func browserPagePrefetchKey(
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int,
        personalSort: SteamWorkshopPersonalSort = .subscriptionDate
    ) -> String {
        "\(context.cacheKeyComponent)|\(browserContentMode.rawValue)|\(source.rawValue)|\(personalSort.rawValue)|\(trendingWindow.rawValue)|\(themeFilter.rawValue)|\(ageRatingFilter.rawValue)|\(resolutionFilter.rawValue)|\(categoryFilter.rawValue)|\(query)|\(page)"
    }
}
