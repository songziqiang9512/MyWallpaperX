//
//  SteamWorkshopService+BrowserSupport.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    nonisolated static func workshopItemIDSearchID(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count >= 6,
           trimmed.unicodeScalars.allSatisfy({ scalar in
               scalar.value >= 48 && scalar.value <= 57
           }) {
            return trimmed
        }
        return firstCapture(pattern: #"(?:^|[?&\s])id=(\d{6,})\b"#, in: trimmed)
    }

    func logBrowserDebug(_ message: String) {
        guard defaults.bool(forKey: Constants.browserDebugLoggingEnabledKey) else { return }
        NSLog("[SteamWorkshopBrowser] %@", message)
    }

    func loadingStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            if source.isPersonal { return "正在加载\(source.pageTitle)列表…" }
            return "正在抓取 Wallpaper Engine 创意工坊\(browserContentMode.shortDisplayName)列表…"
        case .authorWorkshop(let authorName, _):
            return "正在抓取 \(authorName) 的创意工坊作品…"
        }
    }

    func cachedStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            if source.isPersonal { return "已载入缓存的\(source.pageTitle)列表" }
            return "已载入缓存的创意工坊列表"
        case .authorWorkshop(let authorName, _):
            return "已载入 \(authorName) 的工坊缓存列表"
        }
    }

    func emptyResultsStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            if source.isPersonal {
                let action = source == .myFavorites ? "收藏" : "订阅"
                return "当前账号还没有\(action) Wallpaper Engine \(browserContentMode.displayName)。"
            }
            return "没有抓取到符合条件的\(browserContentMode.displayName)项目。"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 当前没有抓取到可展示的\(browserContentMode.displayName)项目。"
        }
    }

    func baseCardsStatusMessage(for context: SteamWorkshopBrowseContext, count: Int) -> String {
        switch context {
        case .discovery:
            if source.isPersonal { return "已载入 \(count) 个\(source.pageTitle)项目，正在补全详情…" }
            return "已载入 \(count) 张基础卡片，正在补全详情…"
        case .authorWorkshop(let authorName, _):
            return "已载入 \(authorName) 的 \(count) 张基础卡片，正在补全详情…"
        }
    }

    func completedStatusMessage(
        for context: SteamWorkshopBrowseContext,
        totalCount: Int,
        hasMore: Bool
    ) -> String {
        switch context {
        case .discovery:
            if source.isPersonal { return hasMore ? "已加载 \(totalCount) 个\(source.pageTitle)项目" : "已加载全部 \(totalCount) 个\(source.pageTitle)项目" }
            return hasMore ? "已加载 \(totalCount) 个创意工坊\(browserContentMode.displayName)项目" : "已加载全部 \(totalCount) 个已抓取项目"
        case .authorWorkshop(let authorName, _):
            return hasMore ? "已加载 \(authorName) 的 \(totalCount) 个创意工坊项目" : "已加载 \(authorName) 的全部 \(totalCount) 个已抓取项目"
        }
    }

    func failureStatusMessage(for context: SteamWorkshopBrowseContext) -> String {
        switch context {
        case .discovery:
            if source.isPersonal { return "\(source.pageTitle)列表加载失败" }
            return "创意工坊列表抓取失败"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 的工坊列表抓取失败"
        }
    }

    func prefetchStatusMessage(for context: SteamWorkshopBrowseContext, page: Int) -> String {
        switch context {
        case .discovery:
            if source.isPersonal { return "已预加载\(source.pageTitle)第 \(page) 页，正在补全详细信息…" }
            return "已预加载第 \(page) 页基础卡片，正在补全详细信息…"
        case .authorWorkshop(let authorName, _):
            return "已预加载 \(authorName) 的第 \(page) 页基础卡片，正在补全详细信息…"
        }
    }

    func browsePageSize(for context: SteamWorkshopBrowseContext, source: SteamWorkshopSource) -> Int {
        switch context {
        case .discovery:
            return source.isPersonal ? Constants.personalWorkshopPageSize : Constants.browserPageSize
        case .authorWorkshop:
            return Constants.authorWorkshopPageSize
        }
    }

    func loadBrowserCache(
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        personalSort: SteamWorkshopPersonalSort = .subscriptionDate
    ) -> SteamWorkshopBrowserCacheSnapshot? {
        let url = cacheFileURL(
            context: context,
            browserContentMode: browserContentMode,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            personalSort: personalSort
        )
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SteamWorkshopBrowserCacheSnapshot.self, from: data)
    }

    func saveBrowserCache(
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        items: [SteamWorkshopBrowserItem],
        personalSort: SteamWorkshopPersonalSort = .subscriptionDate
    ) {
        let snapshot = SteamWorkshopBrowserCacheSnapshot(fetchedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try? data.write(
            to: cacheFileURL(
                context: context,
                browserContentMode: browserContentMode,
                source: source,
                query: query,
                trendingWindow: trendingWindow,
                themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            personalSort: personalSort
            ),
            options: [.atomic]
        )
    }

    func outputIndicatesAuthenticationFailure(_ output: String) -> Bool {
        let lowered = output.localizedLowercase
        return lowered.contains("invalid password")
            || lowered.contains("login failure")
            || lowered.contains("failed to log in")
            || lowered.contains("account logon denied")
            || lowered.contains("incorrect login")
            || lowered.contains("too many login failures")
            || lowered.contains("not logged on")
            || lowered.contains("logged in elsewhere")
            || lowered.contains("please use force_install_dir before logon")
            || lowered.contains("steam guard")
            || lowered.contains("please enter your password")
    }

    func outputIndicatesBenignSteamBootstrap(_ output: String) -> Bool {
        let lowered = output.localizedLowercase
        guard lowered.contains("loading steam api") || lowered.contains("iopollinghelpers_osx.cpp") else {
            return false
        }
        guard lowered.contains("ok") else {
            return false
        }
        return !outputIndicatesAuthenticationFailure(output)
            && !outputIndicatesAccessRestriction(output)
    }

    func outputIndicatesAccessRestriction(_ output: String) -> Bool {
        let lowered = output.localizedLowercase
        return lowered.contains("access denied")
            || lowered.contains("private")
            || lowered.contains("friends only")
            || lowered.contains("permission")
            || lowered.contains("not available")
            || lowered.contains("failed to download item")
    }

    private func cacheFileURL(
        context: SteamWorkshopBrowseContext,
        browserContentMode: SteamWorkshopBrowserContentMode,
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        personalSort: SteamWorkshopPersonalSort
    ) -> URL {
        switch context {
        case .discovery:
            if source.isPersonal {
                let account = safeCacheComponent(for: communityAccountID ?? "pending", fallback: "unknown")
                let search = safeCacheComponent(for: query, fallback: "all")
                return cacheDirectoryURL.appendingPathComponent("personal-\(account)-\(source.rawValue)-\(personalSort.rawValue)-\(browserContentMode.rawValue)-\(themeFilter.rawValue)-\(ageRatingFilter.rawValue)-\(resolutionFilter.rawValue)-\(categoryFilter.rawValue)-\(search).json")
            }
        case .authorWorkshop:
            return cacheDirectoryURL.appendingPathComponent("\(context.cacheKeyComponent).json")
        }
        let normalized = safeCacheComponent(for: query, fallback: "all")
        let theme = themeFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let age = String(ageRatingFilter.rawValue)
        let resolution = resolutionFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let category = categoryFilter.rawValue.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let period = source.supportsTimeRange ? trendingWindow.rawValue : "na"
        return cacheDirectoryURL.appendingPathComponent("\(browserContentMode.rawValue)-\(source.rawValue)-\(period)-\(theme)-\(age)-\(resolution)-\(category)-\(normalized).json")
    }

    func clearPersonalSubscriptionCaches() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("personal-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func safeCacheComponent(for value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let ascii = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .map { scalar -> Character in
                let scalarString = String(scalar).lowercased()
                return scalarString.range(of: #"^[a-z0-9]$"#, options: .regularExpression) != nil
                    ? (scalarString.first ?? "-")
                    : "-"
            }
        let slug = String(ascii)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let digest = Self.stableCacheDigest(for: trimmed)
        if slug.isEmpty {
            return "\(fallback)-\(digest)"
        }
        return "\(String(slug.prefix(48)))-\(digest)"
    }

    private static func stableCacheDigest(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
