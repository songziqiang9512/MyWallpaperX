//
//  SteamWorkshopService+SteamKitBrowse.swift
//  MyWallpaperX
//

import Foundation

// SK6.2：SteamKit 统一查询是唯一浏览执行权，没有双后端设置或同请求
// fallback。
// 合同（§4.1）：
// - QueryKey（排序/标签/搜索/时间窗）+ generation：条件变化重置分页；
//   逆序/迟到响应按 generation 丢弃，已有页不清空。
// - 同 key 刷新不闪回空白（保留旧页，轻量刷新状态）。
// - 追加页失败保留已有页、冷却后滑动重试；三页以上按 ID 去重。
// - `days` 是 trend 排序的远端排名区间，不是发布时间过滤；由 QueryKey
//   贯穿 Swift IPC 到 helper，不得按 timeCreated 删除已返回作品。分面筛选
//   （类型/分级/分辨率/分类）已于 2026-09-16 经 `taggroups` 实测开放：discovery 服务端执行（面内 OR、
//   跨面 AND），author/personal 由 steamKitApplyKeyTagFilters 客户端后筛。
// - 详情批条目自带网格所需字段（标题/预览/标签/大小/更新时间），
//   打开详情面板仍走既有按 ID 补全路径。
extension SteamWorkshopService {
    /// 公开 discovery route。作者页与严格 ID 分别走同一个 store 的
    /// `.author`/`.details` 查询，绝不掉回 HTML。
    var shouldUseSteamKitBrowse: Bool {
        !source.isPersonal
            && !browseContext.isAuthorWorkshop
            && Self.workshopItemIDSearchID(from: browserQuery) == nil
    }

    var shouldUseSteamKitAuthor: Bool {
        browseContext.isAuthorWorkshop
    }

    var shouldUseSteamKitItemLookup: Bool {
        !browseContext.isAuthorWorkshop
            && Self.workshopItemIDSearchID(from: browserQuery) != nil
    }

    var shouldUseSteamKitStructuredBrowse: Bool {
        shouldUseSteamKitBrowse || shouldUseSteamKitAuthor || shouldUseSteamKitItemLookup
    }

    func fetchDiscoveryViaSteamKit(forceRefresh: Bool) {
        if case .authorWorkshop(_, let workshopURL) = browseContext,
           Self.creatorID(from: workshopURL) == nil {
            browserFetchTask?.cancel()
            browserFetchTask = nil
            browserItems = []
            browserState = .failed("作者标识不可用")
            hasMoreBrowserItems = false
            isLoadingMoreBrowserItems = false
            browserLoadMoreFailureMessage = nil
            isRefreshingBrowserFeed = false
            statusMessage = "无法解析该作者的 SteamID，请从作品详情重新进入作者工坊。"
            return
        }
        let key: SteamKitBrowseStore.Key
        if case .authorWorkshop(_, let workshopURL) = browseContext,
           let creatorSteamID = Self.creatorID(from: workshopURL) {
            key = steamKitBrowseStore.makeAuthorKey(
                creatorSteamID: creatorSteamID,
                contentMode: browserContentMode,
                filters: facetFilters
            )
        } else if let itemID = Self.workshopItemIDSearchID(from: browserQuery),
                  shouldUseSteamKitItemLookup {
            key = steamKitBrowseStore.makeDetailsKey(itemID: itemID)
            currentWorkshopItemID = itemID
        } else {
            key = steamKitBrowseStore.makeKey(
                source: source,
                contentMode: browserContentMode,
                filters: facetFilters,
                search: browserQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                window: trendingWindow
            )
        }
        let keyChanged = steamKitBrowseStore.currentKey != key
        if keyChanged {
            steamKitBrowseStore.resetFor(key: key)
        }
        let generation = steamKitBrowseStore.bumpGeneration()
        let expectedNavigationVersion = navigationVersion

        browserFetchTask?.cancel()
        isLoadingMoreBrowserItems = false
        browserLoadMoreFailureMessage = nil
        isRefreshingBrowserFeed = forceRefresh
        browserLoadMoreRetryAfter = .distantPast
        consecutiveEmptyLoadMorePages = 0
        if keyChanged || browserItems.isEmpty {
            browserState = .loading
            browserItems = []
            hasMoreBrowserItems = true
            switch key.route {
            case .author: statusMessage = "正在加载作者工坊列表…"
            case .details(let itemID): statusMessage = "正在按 ID 加载创意工坊项目 \(itemID)…"
            case .discovery, .personal: statusMessage = "正在加载 Steam 创意工坊…"
            }
        } else {
            // §4.1：同 key 刷新不闪回空白，旧页上方轻量状态。保留既有
            // hasMore，避免已到底的 feed 在刷新期间再次触发 loadMore。
            statusMessage = "正在刷新…"
        }

        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.steamKitBrowseStore.fetch(page: 1, generation: generation)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation,
                          self.shouldUseSteamKitStructuredBrowse else { return }
                    self.browserFetchTask = nil
                    let filtered = self.steamKitStructuredPostProcess(result.items)
                        .map(SteamWorkshopBrowserItem.make(from:))
                    self.browserItems = filtered
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = result.hasMore
                    self.isRefreshingBrowserFeed = false
                    if result.total > 0 {
                        self.statusMessage = "已加载 \(filtered.count) 项 / 共 \(result.total) 项。"
                    } else {
                        self.statusMessage = "已加载 \(filtered.count) 项。"
                    }
                    self.appendSteamKitPartialNotice()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation else { return }
                    self.browserFetchTask = nil
                    if self.browserItems.isEmpty {
                        self.browserState = .failed("加载失败：\(error.localizedDescription)")
                    }
                    self.statusMessage = "加载失败，请稍后重试。"
                    self.isRefreshingBrowserFeed = false
                }
            }
        }
    }

    /// 稀疏交叉筛选下自动续载的上限：连续多页无新增可见项即停止自动
    /// 加载，保留远端 hasMore 与手动继续入口；刷新/改键时归零。
    static let maxConsecutiveEmptyLoadMorePages = 3

    func loadMoreDiscoveryViaSteamKitIfNeeded() {
        guard !isLoadingMoreBrowserItems,
              // 刷新在途时抑制 loadMore：loadMore 的 bumpGeneration 会让
              // 在途刷新回包按代际判废，并泄漏 isRefreshingBrowserFeed。
              !isRefreshingBrowserFeed,
              hasMoreBrowserItems,
              browserState == .loaded,
              consecutiveEmptyLoadMorePages < Self.maxConsecutiveEmptyLoadMorePages,
              Date() >= browserLoadMoreRetryAfter else {
            return
        }
        let page = steamKitBrowseStore.nextPage
        let generation = steamKitBrowseStore.bumpGeneration()
        let expectedNavigationVersion = navigationVersion
        let previousVisibleCount = browserItems.count
        browserLoadMoreFailureMessage = nil
        isLoadingMoreBrowserItems = true
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.steamKitBrowseStore.fetch(page: page, generation: generation)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation,
                          self.shouldUseSteamKitStructuredBrowse else { return }
                    let filtered = self.steamKitStructuredPostProcess(result.items)
                        .map(SteamWorkshopBrowserItem.make(from:))
                    self.browserItems = filtered
                    self.hasMoreBrowserItems = result.hasMore
                    if filtered.count <= previousVisibleCount {
                        self.consecutiveEmptyLoadMorePages += 1
                        if self.consecutiveEmptyLoadMorePages >= Self.maxConsecutiveEmptyLoadMorePages {
                            self.statusMessage = "已暂停自动加载，可继续加载或调整筛选。"
                        }
                    } else {
                        self.consecutiveEmptyLoadMorePages = 0
                    }
                    self.isLoadingMoreBrowserItems = false
                    self.browserLoadMoreFailureMessage = self.hasMoreBrowserItems
                        && self.consecutiveEmptyLoadMorePages >= Self.maxConsecutiveEmptyLoadMorePages
                        ? "已加载页暂无新增匹配项目 · 点击继续加载" : nil
                    self.browserLoadMoreRetryAfter = .distantPast
                    if self.hasMoreBrowserItems {
                        self.statusMessage = result.total > 0
                            ? "已加载 \(self.browserItems.count) 项 / 共 \(result.total) 项。"
                            : "已加载 \(self.browserItems.count) 项。"
                        self.appendSteamKitPartialNotice()
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation else { return }
                    self.isLoadingMoreBrowserItems = false
                    self.hasMoreBrowserItems = true
                    self.browserLoadMoreFailureMessage = "加载失败 · 重试"
                    self.browserLoadMoreRetryAfter = Date().addingTimeInterval(
                        Constants.loadMoreRetryCooldown
                    )
                    self.statusMessage = "加载下一页失败，稍后继续下滑会重试。"
                }
            }
        }
    }

    /// 个人来源始终由新 route 接管。离线时在原区域显示登录指引，不创建
    /// helper 请求，也不回落到 Cookie/HTML。
    var shouldUseSteamKitPersonal: Bool {
        source.isPersonal
            && !browseContext.isAuthorWorkshop
    }

    func fetchPersonalViaSteamKit(forceRefresh: Bool) {
        guard steamAuth.isOnline else {
            browserFetchTask?.cancel()
            browserFetchTask = nil
            browserItems = []
            browserState = .loaded
            hasMoreBrowserItems = false
            isLoadingMoreBrowserItems = false
            browserLoadMoreFailureMessage = nil
            isRefreshingBrowserFeed = false
            statusMessage = "需要登录，请使用工具栏的「登录 Steam」。"
            return
        }
        let key = steamKitBrowseStore.makePersonalKey(
            source: source,
            accountSteamID: steamAuth.steamId,
            contentMode: browserContentMode,
            filters: facetFilters,
            search: browserQuery.trimmingCharacters(in: .whitespacesAndNewlines),
            window: trendingWindow,
            personalSort: personalSort
        )
        let keyChanged = steamKitBrowseStore.currentKey != key
        if keyChanged {
            steamKitBrowseStore.resetFor(key: key)
        }
        let generation = steamKitBrowseStore.bumpGeneration()
        let expectedNavigationVersion = navigationVersion

        browserFetchTask?.cancel()
        isLoadingMoreBrowserItems = false
        browserLoadMoreFailureMessage = nil
        isRefreshingBrowserFeed = forceRefresh
        browserLoadMoreRetryAfter = .distantPast
        consecutiveEmptyLoadMorePages = 0
        if keyChanged || browserItems.isEmpty {
            browserState = .loading
            browserItems = []
            hasMoreBrowserItems = true
            statusMessage = source == .mySubscriptions
                ? "正在加载「我的订阅」…"
                : "正在加载「我的收藏」…"
        } else {
            // §4.1：同 key 刷新不闪回空白，旧页上方轻量状态。保留既有
            // hasMore，避免已到底的 feed 在刷新期间再次触发 loadMore
            // （与 discovery route 的 SK3.2 修复对齐）。
            statusMessage = "正在刷新…"
        }

        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.steamKitBrowseStore.fetchPersonal(page: 1, generation: generation)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation,
                          self.shouldUseSteamKitPersonal else { return }
                    self.browserFetchTask = nil
                    if self.source == .mySubscriptions {
                        self.steamSubscriptions.observeSubscribedIDs(result.items.map(\.publishedFileId))
                    }
                    let processed = self.steamKitPersonalPostProcess(result.items)
                        .map(SteamWorkshopBrowserItem.make(from:))
                    self.browserItems = processed
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = result.hasMore
                    self.isRefreshingBrowserFeed = false
                    self.statusMessage = result.total > 0
                        ? "已加载 \(processed.count) 项 / 共 \(result.total) 项。"
                        : "已加载 \(processed.count) 项。"
                    self.appendSteamKitPartialNotice()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation else { return }
                    self.browserFetchTask = nil
                    if self.browserItems.isEmpty {
                        self.browserState = .failed("加载失败：\(error.localizedDescription)")
                    }
                    self.statusMessage = "加载失败，请稍后重试。"
                    self.isRefreshingBrowserFeed = false
                }
            }
        }
    }

    func loadMorePersonalViaSteamKitIfNeeded() {
        guard !isLoadingMoreBrowserItems,
              // 刷新在途时抑制 loadMore：与 discovery route 的 SK3.2 修复对齐，
              // 否则 loadMore 的 bumpGeneration 会判废在途刷新并泄漏
              // isRefreshingBrowserFeed。
              !isRefreshingBrowserFeed,
              hasMoreBrowserItems,
              browserState == .loaded,
              consecutiveEmptyLoadMorePages < Self.maxConsecutiveEmptyLoadMorePages,
              Date() >= browserLoadMoreRetryAfter else {
            return
        }
        let page = steamKitBrowseStore.nextPage
        let generation = steamKitBrowseStore.bumpGeneration()
        let expectedNavigationVersion = navigationVersion
        let previousVisibleCount = browserItems.count
        browserLoadMoreFailureMessage = nil
        isLoadingMoreBrowserItems = true
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.steamKitBrowseStore.fetchPersonal(page: page, generation: generation)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation,
                          self.shouldUseSteamKitPersonal else { return }
                    if self.source == .mySubscriptions {
                        self.steamSubscriptions.observeSubscribedIDs(result.items.map(\.publishedFileId))
                    }
                    let processed = self.steamKitPersonalPostProcess(result.items)
                        .map(SteamWorkshopBrowserItem.make(from:))
                    self.browserItems = processed
                    self.hasMoreBrowserItems = result.hasMore
                    if processed.count <= previousVisibleCount {
                        self.consecutiveEmptyLoadMorePages += 1
                        if self.consecutiveEmptyLoadMorePages >= Self.maxConsecutiveEmptyLoadMorePages {
                            self.statusMessage = "已暂停自动加载，可继续加载或调整筛选。"
                        }
                    } else {
                        self.consecutiveEmptyLoadMorePages = 0
                    }
                    self.isLoadingMoreBrowserItems = false
                    self.browserLoadMoreFailureMessage = self.hasMoreBrowserItems
                        && self.consecutiveEmptyLoadMorePages >= Self.maxConsecutiveEmptyLoadMorePages
                        ? "已加载页暂无新增匹配项目 · 点击继续加载" : nil
                    self.browserLoadMoreRetryAfter = .distantPast
                    if self.hasMoreBrowserItems {
                        self.statusMessage = result.total > 0
                            ? "已加载 \(self.browserItems.count) 项 / 共 \(result.total) 项。"
                            : "已加载 \(self.browserItems.count) 项。"
                        self.appendSteamKitPartialNotice()
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation else { return }
                    self.isLoadingMoreBrowserItems = false
                    self.hasMoreBrowserItems = true
                    self.browserLoadMoreFailureMessage = "加载失败 · 重试"
                    self.browserLoadMoreRetryAfter = Date().addingTimeInterval(
                        Constants.loadMoreRetryCooldown
                    )
                    self.statusMessage = "加载下一页失败，稍后继续下滑会重试。"
                }
            }
        }
    }

    /// Product detail owner after SK6.1. The helper is the only semantic data
    /// source; preview MIME probing remains a bounded media request and cannot
    /// change item identity, author, tags or subscription metadata.
    func fetchWorkshopItemViaSteamKit(
        fallback: SteamWorkshopBrowserItem,
        browserContentMode: SteamWorkshopBrowserContentMode
    ) async throws -> SteamWorkshopBrowserItem {
        let page = try await steamWorkshopQueryClient.details(ids: [fallback.id])
        guard let item = page.items.first(where: { $0.publishedFileId == fallback.id }) else {
            throw SteamServiceClient.RequestError.helperError(
                code: "unsupportedContent", message: "作品不存在或当前账号无权访问。")
        }
        guard browserContentMode.allows(tags: item.tags) else {
            throw SteamServiceClient.RequestError.helperError(
                code: "unsupportedContent", message: "当前条目不是\(browserContentMode.displayName)。")
        }
        let detailed = SteamWorkshopBrowserItem.makeDetailed(from: item, fallback: fallback)
        let enriched = try await Self.maybeEnrichPreviewKind(
            for: detailed,
            requestPriority: .userInitiated
        )
        Self.saveDetailCache(item: enriched)
        return enriched
    }

    private func appendSteamKitPartialNotice() {
        if steamKitBrowseStore.currentKey?.route == .personal {
            statusMessage += " 排序和筛选仅作用于已加载项目。"
        }
        let errors = steamKitBrowseStore.partialErrors
        guard !errors.isEmpty else { return }
        let ids = errors.prefix(5).map(\.publishedFileId).joined(separator: "、")
        statusMessage += " 另有 \(errors.count) 项暂不可用（\(ids)），可刷新重试。"
    }

    private func steamKitStructuredPostProcess(
        _ items: [SteamWorkshopQueryItem]
    ) -> [SteamWorkshopQueryItem] {
        guard let key = steamKitBrowseStore.currentKey else { return items }
        switch key.route {
        case .details:
            return items
        case .author:
            return steamKitApplyKeyTagFilters(items, key: key)
        case .discovery:
            return steamKitApplyKeyTagFilters(items, key: key)
        case .personal:
            return steamKitPersonalPostProcess(items)
        }
    }

    /// 内容分类组内 OR，与其他分面 AND；所有 route 共享最终过滤。
    /// 分面筛选（面内 OR、跨面 AND）统一在此执行。
    private func steamKitApplyKeyTagFilters(
        _ items: [SteamWorkshopQueryItem],
        key: SteamKitBrowseStore.Key
    ) -> [SteamWorkshopQueryItem] {
        var result = items
        if !key.contentTypeTags.isEmpty {
            result = result.filter { item in
                key.contentTypeTags.contains { modeTag in
                    item.tags.contains { $0.caseInsensitiveCompare(modeTag) == .orderedSame }
                }
            }
        }
        guard !key.filters.isEmpty else { return result }
        return result.filter { key.filters.allows(tags: $0.tags) }
    }

    /// 个人来源后处理：内容模式/分面过滤 + 标题搜索 +
    /// 个人排序（rating/favorites 无返回字段，已从菜单移除）。
    private func steamKitPersonalPostProcess(
        _ items: [SteamWorkshopQueryItem]
    ) -> [SteamWorkshopQueryItem] {
        var result = items
        let key = steamKitBrowseStore.currentKey
        if let key {
            result = steamKitApplyKeyTagFilters(result, key: key)
        }
        if let key, !key.search.isEmpty {
            let search = key.search
            result = result.filter { $0.title.localizedStandardContains(search) }
        }
        switch personalSort {
        case .subscriptionDate:
            result.sort { ($0.timeSubscribed ?? 0) > ($1.timeSubscribed ?? 0) }
        case .lastUpdated:
            result.sort { ($0.timeUpdated ?? 0) > ($1.timeUpdated ?? 0) }
        case .fileSize:
            result.sort { ($0.fileSize ?? 0) > ($1.fileSize ?? 0) }
        case .name:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return result
    }

}

/// 查询条目 → 网格模型：新 route 条目自带网格所需字段；缺失的详情
/// 字段（作者/描述等）在打开详情面板时由既有按 ID 补全路径填充。
extension SteamWorkshopBrowserItem {
    static func make(from item: SteamWorkshopQueryItem) -> SteamWorkshopBrowserItem {
        let updatedDate = item.timeUpdated.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        // 复用产品唯一的大小文本（parseByteCount 可回解、不随本机 locale
        // 变化），不用 ByteCountFormatter 的本地化输出。
        let sizeText = item.fileSize.map {
            SteamWorkshopService.fileSizeText(forBytes: Int64($0))
        }
        let updatedText = updatedDate.map {
            Self.relativeFormatter.localizedString(for: $0, relativeTo: Date())
        }
        let detailURL = URL(string:
            "https://steamcommunity.com/sharedfiles/filedetails/?id=\(item.publishedFileId)&appid=431960"
        ) ?? URL(string: "https://steamcommunity.com/")!
        let authorProfileURL = item.creatorSteamId.flatMap {
            URL(string: "https://steamcommunity.com/profiles/\($0)/")
        }
        let authorWorkshopURL = item.creatorSteamId.flatMap {
            URL(string: "https://steamcommunity.com/profiles/\($0)/myworkshopfiles/?appid=431960")
        }
        return SteamWorkshopBrowserItem(
            id: item.publishedFileId,
            title: item.title,
            author: item.creatorName ?? "",
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL,
            hasAdultContent: item.tags.contains(where: { $0.caseInsensitiveCompare("Mature") == .orderedSame }),
            summary: "",
            descriptionText: "",
            tags: item.tags,
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: nil,
            dependencyIDs: item.dependencyIds,
            previewImageURL: item.previewUrl.flatMap(URL.init(string:)),
            previewVideoURL: nil,
            previewAssetKind: .stillImage,
            fileSizeText: sizeText,
            // 复用唯一分辨率 tag 判定（含无空格/× 变体），不新增第二套 matcher。
            resolutionText: item.tags.first(where: { SteamWorkshopService.isResolutionTag($0) }),
            postedText: nil,
            updatedText: updatedText,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: detailURL
        )
    }

    static func makeDetailed(
        from item: SteamWorkshopQueryItem,
        fallback: SteamWorkshopBrowserItem
    ) -> SteamWorkshopBrowserItem {
        let tags = item.tags
        let description = item.description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = description.isEmpty ? fallback.summary : description
        let creator = item.creatorSteamId
        let authorProfileURL = creator.flatMap {
            URL(string: "https://steamcommunity.com/profiles/\($0)/")
        } ?? fallback.authorProfileURL
        let authorWorkshopURL = creator.flatMap {
            URL(string: "https://steamcommunity.com/profiles/\($0)/myworkshopfiles/?appid=431960")
        } ?? fallback.authorWorkshopURL
        let sameCreator = creator == nil || SteamWorkshopService.creatorID(from: fallback.authorProfileURL) == creator
        let author = item.creatorName ?? (sameCreator ? fallback.author : "")
        let workshopType = SteamWorkshopService.preferredTag(
            in: tags,
            matching: SteamWorkshopBrowserContentMode.allCases.map(\.requiredTagValue)
        )
        let ageRating = SteamWorkshopService.preferredTag(
            in: tags,
            matching: SteamWorkshopAgeRatingFilter.ratingTagValues
        )
        let category = SteamWorkshopService.preferredTag(
            in: tags,
            matching: SteamWorkshopCategoryFilter.allCases.dropFirst().map(\.rawValue)
        )
        let resolution = tags.first(where: SteamWorkshopService.isResolutionTag)
        let genre = tags.first(where: { !SteamWorkshopService.isSystemWorkshopTag($0) })
        let fileSizeText = item.fileSize.map { SteamWorkshopService.fileSizeText(forBytes: Int64($0)) }
        let postedText = SteamWorkshopService.formatSteamTimestamp(item.timeCreated.map(Int64.init))
        let updatedText = SteamWorkshopService.formatSteamTimestamp(item.timeUpdated.map(Int64.init))
        let favoritesText = item.favorited.map(SteamWorkshopService.formatCount)
        let subscriptionsText = item.subscriptions.map(SteamWorkshopService.formatCount)
        let lifetimeFavoritesText = item.lifetimeFavorited.map(SteamWorkshopService.formatCount)
        let lifetimeSubscriptionsText = item.lifetimeSubscriptions.map(SteamWorkshopService.formatCount)
        let visibilityText = SteamWorkshopService.visibilityText(for: item.visibility)
        let moderationText = SteamWorkshopService.moderationText(
            banned: item.banned.map { $0 ? 1 : 0 },
            banReason: item.banReason
        )
        return SteamWorkshopBrowserItem(
            id: item.publishedFileId,
            title: item.title,
            author: author,
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL,
            hasAdultContent: fallback.hasAdultContent || tags.contains(where: {
                $0.caseInsensitiveCompare("Mature") == .orderedSame
            }),
            summary: summary,
            descriptionText: description.isEmpty ? summary : description,
            tags: tags,
            workshopTypeText: workshopType,
            ageRatingText: ageRating,
            genreText: genre,
            categoryText: category,
            dependencyIDs: item.dependencyIds,
            previewImageURL: item.previewUrl.flatMap(URL.init(string:)) ?? fallback.previewImageURL,
            previewVideoURL: fallback.previewVideoURL,
            previewAssetKind: fallback.previewAssetKind,
            fileSizeText: fileSizeText,
            resolutionText: resolution,
            postedText: postedText,
            updatedText: updatedText,
            favoritesText: favoritesText,
            subscriptionsText: subscriptionsText,
            scoreText: item.views.map { "浏览 \($0)" },
            lifetimeFavoritesText: lifetimeFavoritesText,
            lifetimeSubscriptionsText: lifetimeSubscriptionsText,
            visibilityText: visibilityText,
            moderationText: moderationText,
            detailFields: SteamWorkshopService.buildOfficialDetailFields(
                fileSizeText: fileSizeText,
                resolutionText: resolution,
                postedText: postedText,
                updatedText: updatedText,
                subscriptionsText: subscriptionsText,
                favoritesText: favoritesText,
                lifetimeSubscriptionsText: lifetimeSubscriptionsText,
                lifetimeFavoritesText: lifetimeFavoritesText,
                visibilityText: visibilityText,
                moderationText: moderationText,
                tags: tags
            ),
            detailURL: fallback.detailURL
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// 分页与代际状态（SK3.2 QueryKey/generation）。UI 缓存仍以服务侧
/// browserItems 为 UI 投影；本类保留同键原始已加载集合，后置过滤与排序只对整集合执行。
@MainActor
final class SteamKitBrowseStore {
    enum Route: Equatable {
        case discovery
        case personal
        case author(creatorSteamID: String)
        case details(itemID: String)
    }

    struct Key: Equatable {
        let route: Route
        let sort: SteamWorkshopQuerySort
        /// 服务端 AND requiredtag（内容模式）。面内多选分面在 `filters`。
        let contentTypeTags: [String]
        /// 分面筛选组合参与键：任一面变化必然换键重置分页。
        let filters: SteamWorkshopBrowseFacetFilters
        let search: String
        /// RankedByTrend interval. This changes remote ordering only and must
        /// never be interpreted as a local publication-date cutoff.
        let trendDays: Int?
        /// SK3.3 个人来源：来源与个人排序参与键；discovery 键两者为 nil。
        let source: SteamWorkshopSource?
        let personalSortRaw: String?
        /// §4.1/§3.3：账号身份参与个人来源键；discovery 键为 nil。
        let accountSteamID: String?
    }

    struct Snapshot {
        let key: Key?
        let nextPage: Int
        let hasMore: Bool
        let rawItems: [SteamWorkshopQueryItem]
        let partialErrors: [SteamWorkshopQueryPage.SteamWorkshopPartialError]
    }

    private(set) var generation = 0
    private(set) var currentKey: Key?
    private(set) var nextPage = 1
    private(set) var hasMore = false
    private(set) var rawItems: [SteamWorkshopQueryItem] = []
    private(set) var partialErrors: [SteamWorkshopQueryPage.SteamWorkshopPartialError] = []

    private let queryClient: SteamWorkshopQueryClient

    init(queryClient: SteamWorkshopQueryClient) {
        self.queryClient = queryClient
    }

    func makeKey(
        source: SteamWorkshopSource,
        contentMode: SteamWorkshopBrowserContentMode,
        filters: SteamWorkshopBrowseFacetFilters,
        search: String,
        window: SteamWorkshopTrendingWindow
    ) -> Key {
        Key(
            route: .discovery,
            sort: Self.sort(for: source),
            contentTypeTags: contentMode.queryTags,
            filters: filters,
            search: search,
            trendDays: source.supportsTimeRange ? window.rankingDays : nil,
            source: nil,
            personalSortRaw: nil,
            accountSteamID: nil
        )
    }

    /// SK3.3 个人来源键（已订阅/收藏）。accountSteamID 参与键：换号后键必然
    /// 变化（§4.1 QueryKey 含账号；§3.3 旧账号私有数据不展示给新账号）。
    /// 服务端无 tag 筛选能力，contentTypeTags/filters 仅由客户端后置执行。
    func makePersonalKey(
        source: SteamWorkshopSource,
        accountSteamID: String?,
        contentMode: SteamWorkshopBrowserContentMode,
        filters: SteamWorkshopBrowseFacetFilters,
        search: String,
        window: SteamWorkshopTrendingWindow,
        personalSort: SteamWorkshopPersonalSort
    ) -> Key {
        Key(
            route: .personal,
            sort: .subscriptions,
            contentTypeTags: contentMode.queryTags,
            filters: filters,
            search: search,
            trendDays: source.supportsTimeRange ? window.rankingDays : nil,
            source: source,
            personalSortRaw: personalSort.rawValue,
            accountSteamID: accountSteamID
        )
    }

    func makeAuthorKey(
        creatorSteamID: String,
        contentMode: SteamWorkshopBrowserContentMode,
        filters: SteamWorkshopBrowseFacetFilters
    ) -> Key {
        Key(
            route: .author(creatorSteamID: creatorSteamID),
            sort: .newest,
            contentTypeTags: contentMode.queryTags,
            filters: filters,
            search: "",
            trendDays: nil,
            source: nil,
            personalSortRaw: nil,
            accountSteamID: nil
        )
    }

    func makeDetailsKey(itemID: String) -> Key {
        Key(
            route: .details(itemID: itemID),
            sort: .newest,
            contentTypeTags: [],
            filters: .none,
            search: "",
            trendDays: nil,
            source: nil,
            personalSortRaw: nil,
            accountSteamID: nil
        )
    }

    func resetFor(key: Key) {
        currentKey = key
        rawItems = []
        partialErrors = []
        nextPage = 1
        hasMore = true
    }

    func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    func snapshot() -> Snapshot {
        Snapshot(
            key: currentKey,
            nextPage: nextPage,
            hasMore: hasMore,
            rawItems: rawItems,
            partialErrors: partialErrors
        )
    }

    func restore(_ snapshot: Snapshot) {
        generation += 1
        currentKey = snapshot.key
        nextPage = snapshot.nextPage
        hasMore = snapshot.hasMore
        rawItems = snapshot.rawItems
        partialErrors = snapshot.partialErrors
    }

    func clear() {
        generation += 1
        currentKey = nil
        nextPage = 1
        hasMore = false
        rawItems = []
        partialErrors = []
    }

    private func merge(_ items: [SteamWorkshopQueryItem], page: Int,
                       errors: [SteamWorkshopQueryPage.SteamWorkshopPartialError] = []) -> [SteamWorkshopQueryItem] {
        if page == 1 { rawItems = []; partialErrors = [] }
        var index = Dictionary(uniqueKeysWithValues: rawItems.enumerated().map { ($0.element.publishedFileId, $0.offset) })
        for item in items {
            if let offset = index[item.publishedFileId] { rawItems[offset] = item }
            else { index[item.publishedFileId] = rawItems.count; rawItems.append(item) }
        }
        partialErrors.append(contentsOf: errors)
        return rawItems
    }

    func fetch(
        page: Int,
        generation: Int
    ) async throws -> (items: [SteamWorkshopQueryItem], total: Int, hasMore: Bool) {
        guard let key = currentKey else {
            throw SteamServiceClient.RequestError.notReady
        }
        let result: SteamWorkshopQueryPage
        switch key.route {
        case .discovery:
            result = try await queryClient.browse(
                sort: key.sort,
                page: page,
                tags: key.contentTypeTags.count == 1 ? key.contentTypeTags : [],
                tagGroups: (key.contentTypeTags.count > 1 ? [key.contentTypeTags] : []) + key.filters.tagGroups,
                search: key.search,
                trendDays: key.trendDays
            )
        case .author(let creatorSteamID):
            result = try await queryClient.author(creatorSteamId: creatorSteamID, page: page)
        case .details(let itemID):
            guard page == 1 else {
                throw SteamServiceClient.RequestError.helperError(
                    code: "unsupportedQuery", message: "detail lookup has one page")
            }
            let details = try await queryClient.details(ids: [itemID])
            result = SteamWorkshopQueryPage(
                page: page,
                total: details.total,
                hasMore: false,
                items: details.items,
                wrongAppDropped: details.wrongAppDropped,
                partialErrors: details.partialErrors
            )
        case .personal:
            throw SteamServiceClient.RequestError.notReady
        }
        // 迟到/被取代的响应不得提交分页状态：否则旧页回包会把 nextPage
        // 推过头造成跳页缺数据。上层按代际丢弃合并，这里对齐提交语义。
        guard generation == self.generation, key == currentKey else {
            return (result.items, result.total, result.hasMore)
        }
        nextPage = page + 1
        hasMore = result.hasMore
        return (merge(result.items, page: page, errors: result.partialErrors), result.total, result.hasMore)
    }

    /// SK3.3：个人来源取页。已订阅直接结构化分页；收藏为 ID 分页 +
    /// 详情批补全（30 个/批，符合 helper queryDetails 上限）。
    /// 与 fetch 相同：非当前代际的迟到回包不提交分页状态。
    func fetchPersonal(
        page: Int,
        generation: Int
    ) async throws -> (items: [SteamWorkshopQueryItem], total: Int, hasMore: Bool) {
        guard let key = currentKey, key.route == .personal, let source = key.source else {
            throw SteamServiceClient.RequestError.notReady
        }
        func commit(hasMore: Bool) {
            nextPage = page + 1
            self.hasMore = hasMore
        }
        switch source {
        case .mySubscriptions:
            let result = try await queryClient.subscriptions(page: page)
            guard generation == self.generation, key == currentKey else {
                return (result.items, result.total, result.hasMore)
            }
            commit(hasMore: result.hasMore)
            return (merge(result.items, page: page, errors: result.partialErrors), result.total, result.hasMore)
        case .myFavorites:
            let (ids, total, hasMore) = try await queryClient.favoriteIds(page: page)
            var items: [SteamWorkshopQueryItem] = []
            var errors: [SteamWorkshopQueryPage.SteamWorkshopPartialError] = []
            for chunkStart in stride(from: 0, to: ids.count, by: 30) {
                let chunk = Array(ids[chunkStart..<min(chunkStart + 30, ids.count)])
                if chunk.isEmpty { continue }
                let details = try await queryClient.details(ids: chunk)
                items.append(contentsOf: details.items)
                errors.append(contentsOf: details.partialErrors)
            }
            guard generation == self.generation, key == currentKey else {
                return (items, total, hasMore)
            }
            commit(hasMore: hasMore)
            return (merge(items, page: page, errors: errors), total, hasMore)
        default:
            throw SteamServiceClient.RequestError.helperError(
                code: "unsupportedQuery", message: "unsupported personal source")
        }
    }

    /// 来源 → 统一排序键（SK0.1 实测可用的四个排序）。
    static func sort(for source: SteamWorkshopSource) -> SteamWorkshopQuerySort {
        switch source {
        case .featured: return .trend
        case .recent: return .newest
        case .mostSubscribed: return .subscriptions
        case .updated: return .updated
        case .mySubscriptions, .myFavorites: return .subscriptions
        }
    }
}
