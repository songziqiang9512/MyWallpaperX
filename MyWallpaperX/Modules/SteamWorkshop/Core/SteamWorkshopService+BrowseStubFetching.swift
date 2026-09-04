import Foundation

extension SteamWorkshopService {
    nonisolated static func fetchWorkshopStubPage(
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
    ) async throws -> SteamWorkshopBrowseStubPage {
        let url: URL
        switch context {
        case .discovery:
            url = makeBrowseURL(
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
        case .authorWorkshop(_, let workshopURL):
            url = makeAuthorWorkshopURL(baseURL: workshopURL, page: page)
        }
        let html = try await fetchHTMLForBrowseSource(url: url, context: context, source: source)
        let stubs = parseBrowsePage(html: html)
        for stub in stubs {
            await saveAuthorNameIfPossible(
                stub.author,
                creatorID: creatorID(from: stub.authorProfileURL) ?? creatorID(from: stub.authorWorkshopURL),
                authorProfileURL: stub.authorProfileURL,
                authorWorkshopURL: stub.authorWorkshopURL
            )
        }
        let pageSize = await context.isAuthorWorkshop
            ? Constants.authorWorkshopPageSize
            : (source.isPersonal ? Constants.personalWorkshopPageSize : Constants.browserPageSize)
        let hasNextPageLink = browsePageHasMore(html: html, currentPage: page)
        let hasMore = hasNextPageLink || stubs.count >= pageSize
        if !stubs.isEmpty {
            return SteamWorkshopBrowseStubPage(stubs: stubs, hasMore: hasMore)
        }

        let pattern = #"sharedfiles/filedetails/\?id=(\d+)"#
        let matches = firstCaptureMatches(pattern: pattern, in: html)
        var ordered: [SteamWorkshopBrowseStub] = []
        var seen = Set<String>()
        for id in matches where seen.insert(id).inserted {
            ordered.append(
                SteamWorkshopBrowseStub(
                    id: id,
                    title: nil,
                    author: nil,
                    authorProfileURL: nil,
                    authorWorkshopURL: nil,
                    hasAdultContent: false,
                    summary: nil,
                    previewImageURL: nil
                )
            )
        }
        let fallbackHasMore = hasNextPageLink || ordered.count >= pageSize
        return SteamWorkshopBrowseStubPage(stubs: ordered, hasMore: fallbackHasMore)
    }
}
