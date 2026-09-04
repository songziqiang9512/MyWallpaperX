import Foundation

extension SteamWorkshopService {
    func navigateToBrowse() {
        cancelBrowserDetailHydration()
        requestedURL = requestedURLForCurrentContext(page: 1)
        navigationVersion += 1
        currentWorkshopItemID = nil
        currentPageTitle = browseContext.isAuthorWorkshop ? browseContext.title : source.pageTitle
        fetchBrowserItems()
    }

    func refresh() {
        cancelBrowserDetailHydration()
        navigationVersion += 1
        reloadInstalledItems()
        SteamWorkshopPreviewRequestCoordinator.shared.resetAllFailureStates()
        isRefreshingBrowserFeed = true
        statusMessage = browseContext.isAuthorWorkshop
            ? "正在刷新作者工坊列表…"
            : "正在刷新 Steam 创意工坊列表…"
        fetchBrowserItems(forceRefresh: true)
    }

    func prepareForBrowserEntry() {
        startupTask?.cancel()
        startupTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.prepareRuntimeIfNeeded()
            await MainActor.run {
                guard !self.isLoadingMoreBrowserItems else { return }
                guard self.browserFetchTask == nil else { return }
                if self.browserItems.isEmpty || self.browserState == .idle {
                    self.logBrowserDebug(
                        "prepareForBrowserEntry trigger initial fetch context=\(self.browseContext.title) state=\(self.browserState)"
                    )
                    self.fetchBrowserItems(forceRefresh: true)
                } else {
                    self.repairVisibleBrowserItemsIfNeeded()
                }
            }
        }
    }

    func fetchBrowserItems(forceRefresh: Bool = false) {
        browserFetchTask?.cancel()
        cancelBrowserDetailHydration()
        browserNextPage = 2
        hasMoreBrowserItems = true
        isLoadingMoreBrowserItems = false
        browserLoadMoreRetryAfter = .distantPast
        isRefreshingBrowserFeed = forceRefresh
        prefetchedBrowserPageKeys.removeAll()
        prefetchedBrowserPages.removeAll()
        let browseContext = self.browseContext
        let source = self.source
        let personalSort = self.personalSort
        let browserContentMode = self.browserContentMode
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trendingWindow = self.trendingWindow
        let themeFilter = self.themeFilter
        let ageRatingFilter = self.ageRatingFilter
        let resolutionFilter = self.resolutionFilter
        let categoryFilter = self.categoryFilter
        let expectedNavigationVersion = navigationVersion
        let pageSize = browsePageSize(for: browseContext, source: source)
        logBrowserDebug(
            "fetchBrowserItems start context=\(browseContext.title) forceRefresh=\(forceRefresh) query=\(query) pageSize=\(pageSize)"
        )
        if preparePersonalWorkshopFetchIfNeeded(source: source, forceRefresh: forceRefresh, navigationVersion: expectedNavigationVersion) { return }

        if browseContext == .discovery,
           let itemID = Self.workshopItemIDSearchID(from: query) {
            browserState = .loading
            browserItems = []
            hasMoreBrowserItems = false
            currentWorkshopItemID = itemID
            statusMessage = "正在按 ID 加载创意工坊项目 \(itemID)…"
            browserFetchTask = Task(priority: .userInitiated) { [weak self] in
                do {
                    let item = try await Self.fetchWorkshopItemByIDSearch(id: itemID)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self else { return }
                        guard self.navigationVersion == expectedNavigationVersion,
                              self.browseContext == browseContext,
                              self.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                        self.isRefreshingBrowserFeed = false
                        self.browserItems = item.map { [$0] } ?? []
                        self.browserState = .loaded
                        self.hasMoreBrowserItems = false
                        self.browserNextPage = 2
                        self.isLoadingMoreBrowserItems = false
                        self.statusMessage = item == nil
                            ? "没有找到 ID 为 \(itemID) 的 Wallpaper Engine 创意工坊项目。"
                            : "已按 ID 加载创意工坊项目 \(itemID)"
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self else { return }
                        guard self.navigationVersion == expectedNavigationVersion,
                              self.browseContext == browseContext,
                              self.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                        self.isRefreshingBrowserFeed = false
                        self.browserState = .failed(error.localizedDescription)
                        self.hasMoreBrowserItems = false
                        self.isLoadingMoreBrowserItems = false
                        self.statusMessage = "按 ID 加载创意工坊项目失败"
                    }
                }
            }
            return
        }

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
            hasMoreBrowserItems = ageRatingFilter != .all || cached.items.count >= pageSize
            browserNextPage = max(2, (cached.items.count / pageSize) + 1)
            statusMessage = cachedStatusMessage(for: browseContext)
            logBrowserDebug(
                "fetchBrowserItems cacheHit context=\(browseContext.title) cachedCount=\(cached.items.count) nextPage=\(browserNextPage) hasMore=\(hasMoreBrowserItems)"
            )
            if !forceRefresh,
               ageRatingFilter == .all,
               Date().timeIntervalSince(cached.fetchedAt) < Constants.cacheTTL {
                isRefreshingBrowserFeed = false
                logBrowserDebug("fetchBrowserItems skipRemote context=\(browseContext.title) reason=freshCache")
                return
            }
            if forceRefresh {
                statusMessage = browseContext.isAuthorWorkshop
                    ? "正在刷新作者工坊列表…"
                    : "正在刷新 Steam 创意工坊\(browserContentMode.displayName)列表…"
            }
        } else {
            browserState = .loading
            browserItems = []
            statusMessage = loadingStatusMessage(for: browseContext)
        }
        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let pageResult = try await Self.fetchWorkshopStubPage(
                    context: browseContext,
                    browserContentMode: browserContentMode,
                    source: source,
                    query: query,
                    trendingWindow: trendingWindow,
                    themeFilter: themeFilter,
                    ageRatingFilter: ageRatingFilter,
                    resolutionFilter: resolutionFilter,
                    categoryFilter: categoryFilter,
                    page: 1,
                    personalSort: personalSort
                )
                let stubs = pageResult.stubs
                let seededItems = stubs.map(Self.seededBrowserItem)
                guard let self else { return }
                let ageFilteredItems = try await self.fetchAgeFilteredBrowserItemsIfNeeded(
                    stubs: stubs,
                    browserContentMode: browserContentMode
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          self.browseContext == browseContext,
                          self.source == source,
                          self.personalSort == personalSort,
                          self.browserContentMode == browserContentMode else { return }
                    self.isRefreshingBrowserFeed = false
                    self.browserItems = ageFilteredItems ?? seededItems
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = pageResult.hasMore
                    self.browserNextPage = 2
                    if ageFilteredItems == nil {
                        self.enqueueBrowserDetailHydration(
                            stubs: stubs,
                            context: browseContext,
                            browserContentMode: browserContentMode,
                            navigationVersion: expectedNavigationVersion,
                            resetQueue: true
                        )
                        self.statusMessage = self.browserItems.isEmpty
                            ? self.emptyResultsStatusMessage(for: browseContext)
                            : self.baseCardsStatusMessage(for: browseContext, count: self.browserItems.count)
                    } else {
                        self.statusMessage = self.browserItems.isEmpty && !pageResult.hasMore
                            ? self.emptyResultsStatusMessage(for: browseContext)
                            : self.completedStatusMessage(
                                for: browseContext,
                                totalCount: self.browserItems.count,
                                hasMore: pageResult.hasMore
                            )
                        self.saveBrowserCache(
                            context: browseContext,
                            browserContentMode: browserContentMode,
                            source: source,
                            query: query,
                            trendingWindow: trendingWindow,
                            themeFilter: themeFilter,
                            ageRatingFilter: ageRatingFilter,
                            resolutionFilter: resolutionFilter,
                            categoryFilter: categoryFilter,
                            items: self.browserItems,
                            personalSort: personalSort
                        )
                        self.continueAgeFilteredPaginationIfNeeded(
                            loadedVisibleItemCount: self.browserItems.count
                        )
                    }
                    self.logBrowserDebug(
                        "fetchBrowserItems page1Fallback context=\(browseContext.title) stubCount=\(stubs.count) hasMore=\(pageResult.hasMore)"
                    )
                }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          self.browseContext == browseContext,
                          self.source == source,
                          self.personalSort == personalSort,
                          self.browserContentMode == browserContentMode else { return }
                    self.isRefreshingBrowserFeed = false
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = pageResult.hasMore
                    self.browserNextPage = 2
                    self.isLoadingMoreBrowserItems = false
                    self.prefetchUpcomingBrowserPageIfNeeded(
                        context: browseContext,
                        browserContentMode: browserContentMode,
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: self.browserNextPage,
                        personalSort: personalSort,
                        lookaheadDepth: 1
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.navigationVersion == expectedNavigationVersion,
                          self.browseContext == browseContext,
                          self.source == source,
                          self.personalSort == personalSort,
                          self.browserContentMode == browserContentMode else { return }
                    self.isRefreshingBrowserFeed = false
                    if self.browserItems.isEmpty {
                        self.browserState = .failed(error.localizedDescription)
                    }
                    self.logBrowserDebug(
                        "fetchBrowserItems failed context=\(browseContext.title) currentCount=\(self.browserItems.count) error=\(error.localizedDescription)"
                    )
                    self.statusMessage = self.failureStatusMessage(for: browseContext)
                }
            }
        }
    }

    nonisolated static func fetchWorkshopItems(
        stubs: [SteamWorkshopBrowseStub],
        browserContentMode: SteamWorkshopBrowserContentMode,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> [SteamWorkshopBrowserItem] {
        guard !stubs.isEmpty else { return [] }
        var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
        var unresolvedStubs: [SteamWorkshopBrowseStub] = []
        itemsByID.reserveCapacity(stubs.count)
        unresolvedStubs.reserveCapacity(stubs.count)

        for stub in stubs {
            if let cached = loadDetailCache(id: stub.id),
               browserItemMatchesContentMode(cached, browserContentMode: browserContentMode) {
                let merged = mergeStub(stub, into: cached)
                let needsHTMLSupplement = shouldSupplementWithHTML(item: merged)
                if !needsHTMLSupplement {
                    let enriched = try await maybeEnrichPreviewKind(for: merged, requestPriority: requestPriority)
                    if enriched != cached {
                        saveDetailCache(item: enriched)
                    }
                    itemsByID[stub.id] = enriched
                    continue
                }
            }
            unresolvedStubs.append(stub)
        }

        let detailsByID = try await fetchPublishedFileDetails(
            ids: unresolvedStubs.map(\.id),
            requestPriority: requestPriority
        )
        let missingIDs = unresolvedStubs.map(\.id).filter { detailsByID[$0] == nil }
        if !missingIDs.isEmpty {
            NSLog(
                "[SteamWorkshopService] official details missing requested=%ld returned=%ld missing=%@",
                unresolvedStubs.count,
                detailsByID.count,
                missingIDs.joined(separator: ",")
            )
        }
        for stub in unresolvedStubs {
            if let detail = detailsByID[stub.id] {
                let item = try await fetchWorkshopItem(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    officialDetail: detail,
                    allowHTMLFallback: false,
                    requestPriority: requestPriority
                )
                itemsByID[stub.id] = item
                continue
            }

            do {
                let item = try await fetchWorkshopItem(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    officialDetail: nil,
                    allowHTMLFallback: true,
                    requestPriority: requestPriority
                )
                itemsByID[stub.id] = item
            } catch {
                let fallback = fallbackBrowserItem(from: stub)
                let enrichedFallback = try await maybeEnrichPreviewKind(for: fallback, requestPriority: requestPriority)
                itemsByID[stub.id] = enrichedFallback
            }
        }

        return stubs.compactMap { itemsByID[$0.id] }
    }

    nonisolated static func prewarmDetailCache(
        for stubs: [SteamWorkshopBrowseStub],
        browserContentMode: SteamWorkshopBrowserContentMode
    ) async throws {
        let uncachedStubs = stubs.filter { loadDetailCache(id: $0.id) == nil }
        guard !uncachedStubs.isEmpty else { return }

        var startIndex = 0
        while startIndex < uncachedStubs.count {
            let endIndex = min(startIndex + Constants.detailPrefetchBatchSize, uncachedStubs.count)
            let batch = Array(uncachedStubs[startIndex..<endIndex])
            let detailsByID = try await fetchPublishedFileDetails(
                ids: batch.map(\.id),
                requestPriority: .background
            )
            for stub in batch {
                guard let detail = detailsByID[stub.id],
                      detailRepresentsContent(detail, browserContentMode: browserContentMode) else { continue }
                let item = await item(from: detail, stub: stub)
                saveDetailCache(item: item)
            }
            startIndex = endIndex
            if startIndex < uncachedStubs.count {
                try? await Task.sleep(nanoseconds: Constants.detailPrefetchInterBatchDelayNanoseconds)
            }
        }
    }

    nonisolated static func fetchWorkshopItem(
        stub: SteamWorkshopBrowseStub,
        browserContentMode: SteamWorkshopBrowserContentMode,
        officialDetail: SteamWorkshopPublishedFileDetail? = nil,
        allowHTMLFallback: Bool = true,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> SteamWorkshopBrowserItem {
        if let cached = loadDetailCache(id: stub.id),
           browserItemMatchesContentMode(cached, browserContentMode: browserContentMode) {
            let merged = await applyingCachedAuthorNameIfPossible(to: mergeStub(stub, into: cached))
            let needsHTMLSupplement = allowHTMLFallback && shouldSupplementWithHTML(item: merged)
            if !needsHTMLSupplement {
                let enriched = try await maybeEnrichPreviewKind(for: merged, requestPriority: requestPriority)
                if enriched != cached {
                    saveDetailCache(item: enriched)
                }
                return enriched
            }
        }

        let detail = if let officialDetail {
            officialDetail
        } else {
            try await fetchPublishedFileDetails(
                ids: [stub.id],
                requestPriority: requestPriority
            )[stub.id]
        }

        var resolvedItem: SteamWorkshopBrowserItem
        if let detail {
            if !detailRepresentsContent(detail, browserContentMode: browserContentMode) {
                throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: "当前条目不是\(browserContentMode.displayName)。"
                ])
            }
            resolvedItem = await item(from: detail, stub: stub)
        } else {
            resolvedItem = fallbackBrowserItem(from: stub)
        }

        if allowHTMLFallback, shouldSupplementWithHTML(item: resolvedItem) {
            do {
                let htmlItem = try await fetchWorkshopItemFromHTML(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    requestPriority: requestPriority
                )
                await saveAuthorNameIfPossible(
                    htmlItem.author,
                    creatorID: detail?.creator,
                    authorProfileURL: htmlItem.authorProfileURL ?? stub.authorProfileURL,
                    authorWorkshopURL: htmlItem.authorWorkshopURL ?? stub.authorWorkshopURL
                )
                resolvedItem = mergeDetailedItem(preferred: htmlItem, fallback: resolvedItem)
            } catch {
                // 官方接口成功时，不因为 HTML 兜底失败而让详情整体失败。
            }
        }

        let merged = mergeStub(stub, into: resolvedItem)
        let enriched = try await maybeEnrichPreviewKind(for: merged, requestPriority: requestPriority)
        saveDetailCache(item: enriched)
        return enriched
    }

    nonisolated static func fetchWorkshopItemFromHTML(
        stub: SteamWorkshopBrowseStub,
        browserContentMode: SteamWorkshopBrowserContentMode,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> SteamWorkshopBrowserItem {
        let detailURL = makeDetailURL(id: stub.id)
        let html = try await fetchHTML(url: detailURL, requestPriority: requestPriority)
        let parsed = parseDetailPage(html: html, fallbackID: stub.id)
        if let workshopTypeText = parsed.workshopTypeText,
           !workshopTypeMatches(browserContentMode: browserContentMode, workshopTypeText: workshopTypeText) {
            throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                NSLocalizedDescriptionKey: "当前条目详情页标记类型为 \(workshopTypeText)，不是\(browserContentMode.displayName)。"
            ])
        }
        return SteamWorkshopBrowserItem(
            id: stub.id,
            title: parsed.title,
            author: parsed.author,
            authorProfileURL: parsed.authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: parsed.authorWorkshopURL ?? stub.authorWorkshopURL,
            hasAdultContent: stub.hasAdultContent,
            summary: parsed.summary,
            descriptionText: parsed.descriptionText,
            tags: parsed.tags,
            workshopTypeText: parsed.workshopTypeText,
            ageRatingText: parsed.ageRatingText,
            genreText: parsed.genreText,
            categoryText: parsed.categoryText,
            dependencyIDs: parsed.dependencyIDs,
            previewImageURL: parsed.previewImageURL,
            previewVideoURL: parsed.previewVideoURL,
            previewAssetKind: parsed.previewVideoURL == nil ? .unknown : .video,
            fileSizeText: parsed.fileSizeText,
            resolutionText: parsed.resolutionText,
            postedText: parsed.postedText,
            updatedText: parsed.updatedText,
            favoritesText: parsed.favoritesText,
            subscriptionsText: parsed.subscriptionsText,
            scoreText: parsed.scoreText,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: parsed.detailFields,
            detailURL: detailURL
        )
    }

    nonisolated static func fetchPublishedFileDetails(
        ids: [String],
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> [String: SteamWorkshopPublishedFileDetail] {
        let normalizedIDs = Array(NSOrderedSet(array: ids.filter { !$0.isEmpty })) as? [String] ?? []
        guard !normalizedIDs.isEmpty else { return [:] }

        var request = URLRequest(url: URL(string: Constants.publishedFileDetailsAPI)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")

        var formItems = ["itemcount=\(normalizedIDs.count)"]
        formItems.append(contentsOf: normalizedIDs.enumerated().map { index, id in
            "publishedfileids[\(index)]=\(id)"
        })
        request.httpBody = formItems.joined(separator: "&").data(using: .utf8)
        let frozenRequest = request

        let (data, response) = try await SteamWorkshopDetailRequestScheduler.shared.run(priority: requestPriority) {
            try await URLSession.shared.data(for: frozenRequest)
        }
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Steam 官方详情接口请求失败，HTTP \(http.statusCode)"
                ]
            )
        }

        let decoded = try JSONDecoder().decode(SteamWorkshopPublishedFileResponseEnvelope.self, from: data)
        var result: [String: SteamWorkshopPublishedFileDetail] = [:]
        for detail in decoded.response.publishedfiledetails where detail.result == 1 {
            result[detail.publishedfileid] = detail
        }
        return result
    }

    nonisolated static func item(from detail: SteamWorkshopPublishedFileDetail, stub: SteamWorkshopBrowseStub) async -> SteamWorkshopBrowserItem {
        let tags = detail.tags.map(\.tag).map(normalizeText).filter { !$0.isEmpty }
        let authorProfileURL = detail.creator.flatMap { creator in
            URL(string: "https://steamcommunity.com/profiles/\(creator)/")
        }
        let authorWorkshopURL = detail.creator.flatMap { creator in
            URL(string: "https://steamcommunity.com/profiles/\(creator)/myworkshopfiles/?appid=\(Constants.workshopAppID)")
        }
        let resolvedAuthor = await resolvedAuthorName(
            creatorID: detail.creator,
            stub: stub,
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL
        )
        let descriptionText = normalizeText(detail.description ?? "")
        let summaryText = stub.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summaryText?.isEmpty == false ? summaryText! : descriptionText
        let workshopType = preferredTag(in: tags, matching: SteamWorkshopBrowserContentMode.allCases.map(\.requiredTagValue))
        let ageRating = preferredTag(in: tags, matching: SteamWorkshopAgeRatingFilter.ratingTagValues)
        let category = preferredTag(in: tags, matching: SteamWorkshopCategoryFilter.allCases.dropFirst().map(\.rawValue))
        let resolution = tags.first(where: isResolutionTag)
        let genre = tags.first(where: { tag in
            !isSystemWorkshopTag(tag)
        })
        let subscriptions = detail.subscriptions
        let favorites = detail.favorited
        let lifetimeSubscriptions = detail.lifetimeSubscriptions
        let lifetimeFavorites = detail.lifetimeFavorited
        let scoreText = detail.views.map { "浏览 \($0)" }
        let visibilityText = visibilityText(for: detail.visibility)
        let moderationText = moderationText(banned: detail.banned, banReason: detail.banReason)

        return SteamWorkshopBrowserItem(
            id: detail.publishedfileid,
            title: normalizeText(detail.title ?? normalizedStubTitle(stub)),
            author: resolvedAuthor,
            authorProfileURL: authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: authorWorkshopURL ?? stub.authorWorkshopURL,
            hasAdultContent: stub.hasAdultContent,
            summary: summary,
            descriptionText: descriptionText.isEmpty ? summary : descriptionText,
            tags: tags,
            workshopTypeText: workshopType,
            ageRatingText: ageRating,
            genreText: genre,
            categoryText: category,
            dependencyIDs: [],
            previewImageURL: detail.previewURL ?? stub.previewImageURL,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: detail.fileSize.map(fileSizeText(forBytes:)),
            resolutionText: resolution,
            postedText: formatSteamTimestamp(detail.timeCreated),
            updatedText: formatSteamTimestamp(detail.timeUpdated),
            favoritesText: favorites.map(formatCount),
            subscriptionsText: subscriptions.map(formatCount),
            scoreText: scoreText,
            lifetimeFavoritesText: lifetimeFavorites.map(formatCount),
            lifetimeSubscriptionsText: lifetimeSubscriptions.map(formatCount),
            visibilityText: visibilityText,
            moderationText: moderationText,
            detailFields: buildOfficialDetailFields(
                fileSizeText: detail.fileSize.map(fileSizeText(forBytes:)),
                resolutionText: resolution,
                postedText: formatSteamTimestamp(detail.timeCreated),
                updatedText: formatSteamTimestamp(detail.timeUpdated),
                subscriptionsText: subscriptions.map(formatCount),
                favoritesText: favorites.map(formatCount),
                lifetimeSubscriptionsText: lifetimeSubscriptions.map(formatCount),
                lifetimeFavoritesText: lifetimeFavorites.map(formatCount),
                visibilityText: visibilityText,
                moderationText: moderationText,
                tags: tags
            ),
            detailURL: makeDetailURL(id: detail.publishedfileid)
        )
    }

    nonisolated static func detailRepresentsContent(
        _ detail: SteamWorkshopPublishedFileDetail,
        browserContentMode: SteamWorkshopBrowserContentMode
    ) -> Bool {
        browserContentMode.isAll || detail.tags.contains { tag in
            tag.tag.compare(browserContentMode.requiredTagValue, options: .caseInsensitive) == .orderedSame
        }
    }

    nonisolated static func workshopTypeMatches(
        browserContentMode: SteamWorkshopBrowserContentMode,
        workshopTypeText: String
    ) -> Bool {
        browserContentMode.isAll || workshopTypeText.compare(browserContentMode.requiredTagValue, options: .caseInsensitive) == .orderedSame
    }

    nonisolated static func browserItemMatchesContentMode(
        _ item: SteamWorkshopBrowserItem,
        browserContentMode: SteamWorkshopBrowserContentMode
    ) -> Bool {
        if !browserContentMode.isAll, let workshopTypeText = item.workshopTypeText,
           workshopTypeMatches(browserContentMode: browserContentMode, workshopTypeText: workshopTypeText) {
            return true
        }
        return browserContentMode.isAll || item.tags.contains {
            $0.compare(browserContentMode.requiredTagValue, options: .caseInsensitive) == .orderedSame
        }
    }

    nonisolated static func shouldSupplementWithHTML(item: SteamWorkshopBrowserItem) -> Bool {
        item.author == "未知作者"
            || item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || item.previewImageURL == nil
            || item.authorWorkshopURL == nil
            || item.dependencyIDs.isEmpty
    }

    nonisolated static func mergeDetailedItem(
        preferred: SteamWorkshopBrowserItem,
        fallback: SteamWorkshopBrowserItem
    ) -> SteamWorkshopBrowserItem {
        let resolvedDependencyIDs = preferred.dependencyIDs.isEmpty ? fallback.dependencyIDs : preferred.dependencyIDs
        return SteamWorkshopBrowserItem(
            id: preferred.id,
            title: preferred.title.isEmpty ? fallback.title : preferred.title,
            author: preferred.author == "未知作者" ? fallback.author : preferred.author,
            authorProfileURL: preferred.authorProfileURL ?? fallback.authorProfileURL,
            authorWorkshopURL: preferred.authorWorkshopURL ?? fallback.authorWorkshopURL,
            hasAdultContent: preferred.hasAdultContent || fallback.hasAdultContent,
            summary: preferred.summary.isEmpty ? fallback.summary : preferred.summary,
            descriptionText: preferred.descriptionText.isEmpty ? fallback.descriptionText : preferred.descriptionText,
            tags: preferred.tags.isEmpty ? fallback.tags : preferred.tags,
            workshopTypeText: preferred.workshopTypeText ?? fallback.workshopTypeText,
            ageRatingText: preferred.ageRatingText ?? fallback.ageRatingText,
            genreText: preferred.genreText ?? fallback.genreText,
            categoryText: preferred.categoryText ?? fallback.categoryText,
            dependencyIDs: resolvedDependencyIDs,
            previewImageURL: preferred.previewImageURL ?? fallback.previewImageURL,
            previewVideoURL: preferred.previewVideoURL ?? fallback.previewVideoURL,
            previewAssetKind: preferred.previewAssetKind == .unknown ? fallback.previewAssetKind : preferred.previewAssetKind,
            fileSizeText: preferred.fileSizeText ?? fallback.fileSizeText,
            resolutionText: preferred.resolutionText ?? fallback.resolutionText,
            postedText: preferred.postedText ?? fallback.postedText,
            updatedText: preferred.updatedText ?? fallback.updatedText,
            favoritesText: preferred.favoritesText ?? fallback.favoritesText,
            subscriptionsText: preferred.subscriptionsText ?? fallback.subscriptionsText,
            scoreText: preferred.scoreText ?? fallback.scoreText,
            lifetimeFavoritesText: preferred.lifetimeFavoritesText ?? fallback.lifetimeFavoritesText,
            lifetimeSubscriptionsText: preferred.lifetimeSubscriptionsText ?? fallback.lifetimeSubscriptionsText,
            visibilityText: preferred.visibilityText ?? fallback.visibilityText,
            moderationText: preferred.moderationText ?? fallback.moderationText,
            detailFields: preferred.detailFields.isEmpty ? fallback.detailFields : preferred.detailFields,
            detailURL: preferred.detailURL
        )
    }

    nonisolated static func fetchHTML(
        url: URL,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let frozenRequest = request
        let (data, response) = try await SteamWorkshopDetailRequestScheduler.shared.run(priority: requestPriority) {
            try await URLSession.shared.data(for: frozenRequest)
        }
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Steam 页面请求失败，HTTP \(http.statusCode)：\(url.absoluteString)"
                ]
            )
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw URLError(.cannotDecodeRawData)
        }
        return html
    }

    nonisolated static func enrichPreviewKind(
        for item: SteamWorkshopBrowserItem,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> SteamWorkshopBrowserItem {
        if item.previewAssetKind != .unknown {
            return item
        }
        guard let previewImageURL = item.previewImageURL else {
            return item
        }

        let mimeType = try? await fetchPreviewMimeType(url: previewImageURL, requestPriority: requestPriority)
        let previewKind: SteamWorkshopPreviewAssetKind
        switch mimeType?.lowercased() {
        case let value? where value.contains("gif"):
            previewKind = .animatedImage
        case let value? where value.contains("image/"):
            previewKind = .stillImage
        default:
            previewKind = .unknown
        }
        return withPreviewKind(previewKind, item: item)
    }

    nonisolated static func fetchPreviewMimeType(
        url: URL,
        requestPriority: SteamWorkshopDetailRequestPriority = .background
    ) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0", forHTTPHeaderField: "User-Agent")
        let frozenRequest = request
        let (_, response) = try await SteamWorkshopDetailRequestScheduler.shared.run(priority: requestPriority) {
            try await URLSession.shared.data(for: frozenRequest)
        }
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return http.value(forHTTPHeaderField: "Content-Type")
    }

    nonisolated static func withPreviewKind(_ previewKind: SteamWorkshopPreviewAssetKind, item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
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

    nonisolated static func fallbackBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: stub.id,
            title: normalizedStubTitle(stub),
            author: normalizedStubAuthor(stub),
            authorProfileURL: stub.authorProfileURL,
            authorWorkshopURL: stub.authorWorkshopURL,
            hasAdultContent: stub.hasAdultContent,
            summary: stub.summary ?? "",
            descriptionText: stub.summary ?? "",
            tags: [],
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: nil,
            dependencyIDs: [],
            previewImageURL: stub.previewImageURL,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: nil,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: makeDetailURL(id: stub.id)
        )
    }

    nonisolated static func seededBrowserItem(from stub: SteamWorkshopBrowseStub) -> SteamWorkshopBrowserItem {
        guard let cached = loadDetailCache(id: stub.id) else {
            return fallbackBrowserItem(from: stub)
        }
        return mergeStub(stub, into: cached)
    }

    nonisolated static func mergeStub(_ stub: SteamWorkshopBrowseStub, into item: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: item.id,
            title: item.title.isEmpty ? normalizedStubTitle(stub) : item.title,
            author: item.author.isEmpty ? normalizedStubAuthor(stub) : item.author,
            authorProfileURL: item.authorProfileURL ?? stub.authorProfileURL,
            authorWorkshopURL: item.authorWorkshopURL ?? stub.authorWorkshopURL,
            hasAdultContent: item.hasAdultContent || stub.hasAdultContent,
            summary: item.summary,
            descriptionText: item.descriptionText,
            tags: item.tags,
            workshopTypeText: item.workshopTypeText,
            ageRatingText: item.ageRatingText,
            genreText: item.genreText,
            categoryText: item.categoryText,
            dependencyIDs: item.dependencyIDs,
            previewImageURL: item.previewImageURL ?? stub.previewImageURL,
            previewVideoURL: item.previewVideoURL,
            previewAssetKind: item.previewAssetKind,
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
}
