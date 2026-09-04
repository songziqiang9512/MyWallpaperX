import Foundation

extension SteamWorkshopService {
    nonisolated static func makeBrowseURL(
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
    ) -> URL {
        if source.isPersonal {
            return makePersonalWorkshopURL(
                browserContentMode: browserContentMode,
                source: source,
                query: query,
                themeFilter: themeFilter,
                ageRatingFilter: ageRatingFilter,
                resolutionFilter: resolutionFilter,
                categoryFilter: categoryFilter,
                page: page,
                personalSort: personalSort
            )
        }
        var components = URLComponents(string: Constants.steamCommunityBase)!
        var queryItems = [
            URLQueryItem(name: "appid", value: Constants.workshopAppID),
            URLQueryItem(name: "searchtext", value: query),
            URLQueryItem(name: "browsesort", value: source.browseFilter),
            URLQueryItem(name: "actualsort", value: source.browseFilter),
            URLQueryItem(name: "section", value: "readytouseitems"),
            URLQueryItem(name: "numperpage", value: "\(Constants.browserPageSize)"),
            URLQueryItem(name: "p", value: "\(max(1, page))")
        ]
        if !browserContentMode.isAll {
            queryItems.append(URLQueryItem(name: "requiredtags[0]", value: browserContentMode.requiredTagValue))
        }
        if let themeTag = themeFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: themeTag))
        }
        if let resolutionTag = resolutionFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: resolutionTag))
        }
        if let categoryTag = categoryFilter.tagValue,
           categoryTag.caseInsensitiveCompare(browserContentMode.requiredTagValue) != .orderedSame {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: categoryTag))
        }
        if source.supportsTimeRange {
            queryItems.append(URLQueryItem(name: "days", value: trendingWindow.daysValue))
        }
        components.queryItems = queryItems
        return components.url!
    }

    nonisolated static func makePersonalWorkshopURL(
        browserContentMode: SteamWorkshopBrowserContentMode,
        source: SteamWorkshopSource,
        query: String,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int,
        personalSort: SteamWorkshopPersonalSort = .subscriptionDate
    ) -> URL {
        var components = URLComponents(string: "https://steamcommunity.com/my/myworkshopfiles/")!
        var queryItems = [
            URLQueryItem(name: "appid", value: Constants.workshopAppID),
            URLQueryItem(name: "searchtext", value: query),
            URLQueryItem(name: "browsesort", value: source.browseFilter),
            URLQueryItem(name: "browsefilter", value: source.browseFilter),
            URLQueryItem(name: "sortmethod", value: personalSort.rawValue),
            URLQueryItem(name: "numperpage", value: "\(Constants.personalWorkshopPageSize)"),
            URLQueryItem(name: "p", value: "\(max(1, page))")
        ]
        if !browserContentMode.isAll {
            queryItems.append(URLQueryItem(name: "requiredtags[0]", value: browserContentMode.requiredTagValue))
        }
        [themeFilter.tagValue, resolutionFilter.tagValue, categoryFilter.tagValue]
            .compactMap { $0 }
            .filter { $0.caseInsensitiveCompare(browserContentMode.requiredTagValue) != .orderedSame }
            .forEach { queryItems.append(URLQueryItem(name: "requiredtags[]", value: $0)) }
        components.queryItems = queryItems
        return components.url!
    }

    nonisolated static func makeDetailURL(id: String) -> URL {
        var components = URLComponents(string: Constants.detailBase)!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "searchtext", value: "")
        ]
        return components.url!
    }

    nonisolated static func makeAuthorWorkshopURL(baseURL: URL, page: Int) -> URL {
        let normalizedURL = normalizedAuthorWorkshopURL(baseURL) ?? baseURL
        guard var components = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false) else {
            return normalizedURL
        }
        let existingQueryItems = components.queryItems ?? []
        var queryItems = existingQueryItems.filter {
            let key = $0.name
            return key != "p" && key != "appid" && key != "numperpage"
        }
        queryItems.insert(URLQueryItem(name: "appid", value: Constants.workshopAppID), at: 0)
        queryItems.append(URLQueryItem(name: "p", value: "\(max(1, page))"))
        queryItems.append(URLQueryItem(name: "numperpage", value: "\(Constants.authorWorkshopPageSize)"))
        components.queryItems = queryItems
        return components.url ?? normalizedURL
    }
}
