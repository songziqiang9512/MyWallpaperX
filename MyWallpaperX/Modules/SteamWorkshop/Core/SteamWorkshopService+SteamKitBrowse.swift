//
//  SteamWorkshopService+SteamKitBrowse.swift
//  MyWallpaperX
//

import Foundation

// SK3.2：新浏览 route（SteamKit 统一查询消费）。
//
// 注入：开发期以 `--mwx-steam-kit-browse` 启动参数或 defaults 键
// `SteamWorkshop.useSteamKitBrowse` 开启；SK6.1 前不接管发行默认，
// 不提供用户可长期选择双后端的设置。
// 合同（§4.1）：
// - QueryKey（排序/标签/搜索/时间窗）+ generation：条件变化重置分页；
//   逆序/迟到响应按 generation 丢弃，已有页不清空。
// - 同 key 刷新不闪回空白（保留旧页，轻量刷新状态）。
// - 追加页失败保留已有页、冷却后滑动重试；三页以上按 ID 去重。
// - 已知边界：`days` 时间窗与年龄分级服务端不支持（SK0.1 缺口）——
//   时间窗在已加载项上按 timeCreated 后置过滤；分级过滤本 route 未开放。
// - 详情批条目自带网格所需字段（标题/预览/标签/大小/更新时间），
//   打开详情面板仍走既有按 ID 补全路径。
extension SteamWorkshopService {
    var isSteamKitBrowseEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("--mwx-steam-kit-browse") { return true }
        return UserDefaults.standard.bool(forKey: "SteamWorkshop.useSteamKitBrowse")
    }

    /// 新 route 是否适用于当前浏览上下文（公开 discovery 来源；作者/个人
    /// 来源分别待 SK3.3 及后续卡接入，期间走既有 route）。
    var shouldUseSteamKitBrowse: Bool {
        isSteamKitBrowseEnabled && !source.isPersonal && !browseContext.isAuthorWorkshop
    }

    func fetchDiscoveryViaSteamKit(forceRefresh: Bool) {
        let key = steamKitBrowseStore.makeKey(
            source: source,
            contentMode: browserContentMode,
            theme: themeFilter,
            resolution: resolutionFilter,
            category: categoryFilter,
            search: browserQuery.trimmingCharacters(in: .whitespacesAndNewlines),
            window: trendingWindow
        )
        let keyChanged = steamKitBrowseStore.currentKey != key
        if keyChanged {
            steamKitBrowseStore.resetFor(key: key)
        }
        let generation = steamKitBrowseStore.bumpGeneration()
        let expectedNavigationVersion = navigationVersion

        browserFetchTask?.cancel()
        cancelBrowserDetailHydration()
        isLoadingMoreBrowserItems = false
        isRefreshingBrowserFeed = forceRefresh
        hasMoreBrowserItems = true
        browserNextPage = 2
        if keyChanged || browserItems.isEmpty {
            browserState = .loading
            browserItems = []
            statusMessage = "正在加载 Steam 创意工坊…"
        } else {
            // §4.1：同 key 刷新不闪回空白，旧页上方轻量状态。
            statusMessage = "正在刷新…"
        }

        browserFetchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.steamKitBrowseStore.fetch(page: 1)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation,
                          self.shouldUseSteamKitBrowse else { return }
                    let filtered = self.steamKitPostFilter(result.items)
                        .map(SteamWorkshopBrowserItem.make(from:))
                    self.browserItems = filtered
                    self.browserState = .loaded
                    self.hasMoreBrowserItems = result.hasMore
                    self.browserNextPage = 2
                    self.isRefreshingBrowserFeed = false
                    if result.total > 0 {
                        self.statusMessage = "已加载 \(filtered.count) 项 / 共 \(result.total) 项。"
                    } else {
                        self.statusMessage = "已加载 \(filtered.count) 项。"
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation else { return }
                    if self.browserItems.isEmpty {
                        self.browserState = .failed("加载失败：\(error.localizedDescription)")
                    }
                    self.statusMessage = "加载失败，请稍后重试。"
                    self.isRefreshingBrowserFeed = false
                }
            }
        }
    }

    func loadMoreDiscoveryViaSteamKitIfNeeded() {
        guard !isLoadingMoreBrowserItems,
              hasMoreBrowserItems,
              browserState == .loaded,
              Date() >= browserLoadMoreRetryAfter else {
            return
        }
        let page = steamKitBrowseStore.nextPage
        let generation = steamKitBrowseStore.bumpGeneration()
        let expectedNavigationVersion = navigationVersion
        isLoadingMoreBrowserItems = true
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.steamKitBrowseStore.fetch(page: page)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation,
                          self.shouldUseSteamKitBrowse else { return }
                    let filtered = self.steamKitPostFilter(result.items)
                        .map(SteamWorkshopBrowserItem.make(from:))
                    let existingIDs = Set(self.browserItems.map(\.id))
                    let newItems = filtered.filter { !existingIDs.contains($0.id) }
                    self.browserItems.append(contentsOf: newItems)
                    self.browserNextPage = page + 1
                    self.hasMoreBrowserItems = result.hasMore
                    self.isLoadingMoreBrowserItems = false
                    self.browserLoadMoreRetryAfter = .distantPast
                    self.statusMessage = result.total > 0
                        ? "已加载 \(self.browserItems.count) 项 / 共 \(result.total) 项。"
                        : "已加载 \(self.browserItems.count) 项。"
                }
            } catch {
                await MainActor.run {
                    guard self.navigationVersion == expectedNavigationVersion,
                          generation == self.steamKitBrowseStore.generation else { return }
                    self.isLoadingMoreBrowserItems = false
                    self.hasMoreBrowserItems = true
                    self.browserLoadMoreRetryAfter = Date().addingTimeInterval(
                        Constants.loadMoreRetryCooldown
                    )
                    self.statusMessage = "加载下一页失败，稍后继续下滑会重试。"
                }
            }
        }
    }

    /// 客户端后置过滤：趋势时间窗按 timeCreated（服务端 days 字段不可用）。
    private func steamKitPostFilter(
        _ items: [SteamWorkshopQueryItem]
    ) -> [SteamWorkshopQueryItem] {
        guard let cutoffInterval = steamKitWindowCutoffInterval else { return items }
        return items.filter { ($0.timeCreated ?? 0) >= cutoffInterval }
    }

    private var steamKitWindowCutoffInterval: Int? {
        let day = 86_400.0
        let now = Date().timeIntervalSince1970
        switch trendingWindow {
        case .today: return Int(now - day)
        case .week: return Int(now - 7 * day)
        case .month: return Int(now - 30 * day)
        case .quarter: return Int(now - 91 * day)
        case .halfYear: return Int(now - 182 * day)
        case .year: return Int(now - 365 * day)
        case .allTime: return nil
        }
    }
}

/// 查询条目 → 网格模型：新 route 条目自带网格所需字段；缺失的详情
/// 字段（作者/描述等）在打开详情面板时由既有按 ID 补全路径填充。
extension SteamWorkshopBrowserItem {
    static func make(from item: SteamWorkshopQueryItem) -> SteamWorkshopBrowserItem {
        let updatedDate = item.timeUpdated.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sizeText = item.fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        }
        let updatedText = updatedDate.map {
            Self.relativeFormatter.localizedString(for: $0, relativeTo: Date())
        }
        let detailURL = URL(string:
            "https://steamcommunity.com/sharedfiles/filedetails/?id=\(item.publishedFileId)&appid=431960"
        ) ?? URL(string: "https://steamcommunity.com/")!
        return SteamWorkshopBrowserItem(
            id: item.publishedFileId,
            title: item.title,
            author: "",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: item.tags.contains(where: { $0.caseInsensitiveCompare("Mature") == .orderedSame }),
            summary: "",
            descriptionText: "",
            tags: item.tags,
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: nil,
            dependencyIDs: [],
            previewImageURL: item.previewUrl.flatMap(URL.init(string:)),
            previewVideoURL: nil,
            previewAssetKind: .stillImage,
            fileSizeText: sizeText,
            resolutionText: item.tags.first {
                $0.contains(" x ") || $0.contains("resolution") || $0.caseInsensitiveCompare("Dynamic resolution") == .orderedSame
            },
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// 分页与代际状态（SK3.2 QueryKey/generation）。UI 缓存仍以服务侧
/// browserItems 为唯一权威，本类只负责键控取页。
@MainActor
final class SteamKitBrowseStore {
    struct Key: Equatable {
        let sort: SteamWorkshopQuerySort
        let tags: [String]
        let search: String
        let trendingWindowRaw: String
    }

    private(set) var generation = 0
    private(set) var currentKey: Key?
    private(set) var nextPage = 1
    private(set) var hasMore = false

    private let queryClient: SteamWorkshopQueryClient

    init(queryClient: SteamWorkshopQueryClient) {
        self.queryClient = queryClient
    }

    func makeKey(
        source: SteamWorkshopSource,
        contentMode: SteamWorkshopBrowserContentMode,
        theme: SteamWorkshopThemeFilter,
        resolution: SteamWorkshopResolutionFilter,
        category: SteamWorkshopCategoryFilter,
        search: String,
        window: SteamWorkshopTrendingWindow
    ) -> Key {
        var tags: [String] = []
        if !contentMode.isAll {
            tags.append(contentMode.requiredTagValue)
        }
        if let themeTag = theme.tagValue {
            tags.append(themeTag)
        }
        if let resolutionTag = resolution.tagValue {
            tags.append(resolutionTag)
        }
        if let categoryTag = category.tagValue,
           !tags.contains(where: { $0.caseInsensitiveCompare(categoryTag) == .orderedSame }) {
            tags.append(categoryTag)
        }
        return Key(
            sort: Self.sort(for: source),
            tags: tags,
            search: search,
            trendingWindowRaw: window.rawValue
        )
    }

    func resetFor(key: Key) {
        currentKey = key
        nextPage = 1
        hasMore = true
    }

    func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    func fetch(page: Int) async throws -> (items: [SteamWorkshopQueryItem], total: Int, hasMore: Bool) {
        guard let key = currentKey else {
            throw SteamServiceClient.RequestError.notReady
        }
        let result = try await queryClient.browse(
            sort: key.sort,
            page: page,
            tags: key.tags,
            search: key.search
        )
        nextPage = page + 1
        hasMore = result.hasMore
        return (result.items, result.total, result.hasMore)
    }

    /// 来源 → 统一排序键（SK0.1 实测可用的四个排序）。
    static func sort(for source: SteamWorkshopSource) -> SteamWorkshopQuerySort {
        switch source {
        case .featured: return .trend
        case .recent: return .newest
        case .mostSubscribed: return .subscriptions
        case .updated: return .newest
        case .mySubscriptions, .myFavorites: return .subscriptions
        }
    }
}
