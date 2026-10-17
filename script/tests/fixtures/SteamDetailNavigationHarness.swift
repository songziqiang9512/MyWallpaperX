import AppKit
import Foundation

// Only external leaves (disk publication, Shell and preview networking) are
// inert. Tests compile the production query, conversion, refresh and routing.
@MainActor final class SteamWorkshopService {
    let steamWorkshopQueryClient: SteamWorkshopQueryClient
    let steamKitBrowseStore: SteamKitBrowseStore
    var browserItems: [SteamWorkshopBrowserItem] = [] { didSet { updateDisplayedBrowserItems() } }
    var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    var browserContentMode = SteamWorkshopBrowserContentMode.video
    var facetFilters = SteamWorkshopBrowseFacetFilters.none
    var source = SteamWorkshopSource.featured
    var trendingWindow = SteamWorkshopTrendingWindow.week
    var personalSort = SteamWorkshopPersonalSort.subscriptionDate
    var browserState = SteamWorkshopBrowserLoadState.loaded
    var browseContext = SteamWorkshopBrowseContext.discovery
    var browserQuery = "", currentPageTitle = "", statusMessage = ""
    var currentWorkshopItemID: String?
    var selectedBrowserItem: SteamWorkshopBrowserItem?
    var selectedDownloadInspectorItem: SteamWorkshopBrowserItem?
    var selectedDownloadDetailItem: SteamWorkshopBrowserItem?
    var selectedBrowserItemError: String?, selectedDownloadDetailError: String?
    var isRefreshingSelectedBrowserItem = false, isRefreshingSelectedDownloadDetailItem = false
    var selectedItemDetailTask: Task<Void, Never>?, browserFetchTask: Task<Void, Never>?
    var inFlightDetailItemID: String?
    var navigationVersion = 0
    var discoveryBrowseSnapshot: SteamWorkshopDiscoveryBrowseSnapshot?
    var savedDiscoveryQueryBeforeAuthorBrowse: String?
    var suppressAutomaticBrowseNavigation = false
    var currentBrowserScrollOffsetY: CGFloat = 0
    var pendingBrowserScrollRestoreOffset: CGFloat?
    var hasMoreBrowserItems = false, isLoadingMoreBrowserItems = false, isRefreshingBrowserFeed = false
    var browserLoadMoreFailureMessage: String?
    var browserLoadMoreRetryAfter = Date.distantPast
    var consecutiveEmptyLoadMorePages = 0
    var fetches = 0, focusRequests = 0, publications = 0, continuationRequests = 0
    var savedItem: Data?
    struct Auth { var isOnline = true; var steamId: String? = "account" }
    var steamAuth = Auth()
    lazy var steamSubscriptions = SteamWorkshopSubscriptionStore(
        identity: { 1 }, read: { _ in false }, write: { _, _ in })
    enum Status { case ready }
    struct Record { let status = Status.ready; let folderURL = URL(fileURLWithPath: "/isolated") }
    var records: [String: Record] = [:]
    init(_ query: SteamWorkshopQueryClient) {
        steamWorkshopQueryClient = query
        steamKitBrowseStore = SteamKitBrowseStore(queryClient: query)
    }
    func latestDownloadRecord(for id: String) -> Record? { records[id] }
    func persistDownloadMetadata(item: SteamWorkshopBrowserItem, id: String, targetURL: URL) {
        publications += 1
        savedItem = try! JSONEncoder().encode(item)
    }
    func reloadInstalledItems() {}
    struct Snapshot { let fetchedAt = Date() }
    func managedDownloadSnapshots(matchingItemID: String) -> [String: Snapshot] { [matchingItemID: Snapshot()] }
    func setBrowserQuery(_ value: String) { browserQuery = value; updateDisplayedBrowserItems() }
    func fetchBrowserItems(forceRefresh: Bool = false) {
        fetches += 1
        browserState = .loading
        if case let .authorWorkshop(_, url) = browseContext {
            steamKitBrowseStore.resetFor(key: steamKitBrowseStore.makeAuthorKey(creatorSteamID: Self.creatorID(from: url)!))
            browserItems = []
        }
    }
    func requestSteamWorkshopBrowserSelection() { focusRequests += 1 }
    func loadMoreBrowserItemsIfNeeded() { continuationRequests += 1 }
    nonisolated static func workshopItemIDSearchID(from query: String) -> String? { nil }
    nonisolated static func resolvedAuthorWorkshopURL(for item: SteamWorkshopBrowserItem) -> URL? { item.authorWorkshopURL }
    nonisolated static func saveDetailCache(item: SteamWorkshopBrowserItem) {}
    enum Priority { case userInitiated }
    nonisolated static func maybeEnrichPreviewKind(for item: SteamWorkshopBrowserItem,
                                                 requestPriority: Priority) async throws -> SteamWorkshopBrowserItem { item }
}

@MainActor final class GridProbe {
    let service: SteamWorkshopService
    var orderedIDs = ["matching-card"]
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    init(_ service: SteamWorkshopService) {
        self.service = service
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 120))
    }
}

@main struct SteamDetailNavigationHarness {
    @MainActor static func main() async throws {
        let wire = QueryTransport()
        let client = SteamServiceClient(executablePath: "/offline-helper", transportFactory: { _ in wire })
        let query = SteamWorkshopQueryClient(client: client)
        let service = SteamWorkshopService(query)
        func value(_ id: String, kind: String = "Scene") -> [String: Any] {
            ["publishedfileid": id, "creatorSteamId": "76561198389424716", "creatorName": "Author",
             "title": "Work \(id)", "description": "Official description", "consumerAppid": 431960,
             "visibility": 0, "banned": false, "dependencyIds": [], "tags": [kind]]
        }
        func page(_ number: Int, _ items: [[String: Any]], more: Bool = false) -> [String: Any] {
            ["page": number, "total": 9, "hasMore": more, "wrongAppDropped": 0, "items": items]
        }
        var reply = page(0, [value("3221354414")])
        wire.respond = { _ in reply }
        let typed = try await query.details(ids: ["3221354414"]).items[0]
        let brief = SteamWorkshopBrowserItem.make(from: typed)
        precondition(brief.author == "Author" && brief.authorWorkshopURL != nil && brief.detailFields.isEmpty)
        precondition(SteamWorkshopDetailRefreshSupport.needsRefresh(brief),
            "a downloaded list snapshot still needs details when its author is present")
        service.records[brief.id] = .init()
        service.selectedDownloadInspectorItem = brief
        service.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: false)
        await service.selectedItemDetailTask?.value
        let detailed = service.selectedDownloadDetailItem!
        precondition(service.selectedDownloadDetailError == nil && detailed.workshopTypeText == "Scene")
        precondition(detailed.descriptionText == "Official description" && service.publications == 1)
        precondition(detailed.resolutionText == nil && detailed.fileSizeText == nil && detailed.previewImageURL == nil)
        precondition(!SteamWorkshopDetailRefreshSupport.needsRefresh(detailed), "optional missing fields are final values")
        precondition(service.browserItems.isEmpty, "download detail refresh cannot add cards to another feed")
        let persisted = try JSONDecoder().decode(SteamWorkshopBrowserItem.self, from: service.savedItem!)
        service.selectedDownloadInspectorItem = persisted
        let sends = wire.sends
        service.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: false)
        precondition(wire.sends == sends && service.publications == 1, "reopening repaired metadata performs no query")

        let failed = SteamWorkshopService(query)
        failed.records[brief.id] = .init()
        failed.selectedDownloadInspectorItem = brief
        reply = page(0, [])
        failed.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: false)
        await failed.selectedItemDetailTask?.value
        precondition(failed.selectedDownloadDetailError != nil && failed.publications == 0,
            "a failed lookup cannot publish the incomplete local snapshot as success")
        reply = page(0, [value(brief.id)])
        failed.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: true)
        await failed.selectedItemDetailTask?.value
        precondition(failed.selectedDownloadDetailError == nil && failed.publications == 1
            && failed.selectedDownloadDetailItem?.workshopTypeText == "Scene", "a previous failure remains retryable")

        // A strict-ID search can expose Web/Scene while discovery remains Video.
        reply = page(0, [value("100002", kind: "Web")])
        var webBrief = brief
        let webTyped = try await query.details(ids: ["100002"]).items[0]
        webBrief = SteamWorkshopBrowserItem.make(from: webTyped)
        service.browserItems = [webBrief]
        let beforeRapidOpen = wire.sends
        service.presentItemDetail(webBrief)
        service.selectedItemDetailTask?.cancel()
        service.presentItemDetail(webBrief)
        service.presentItemDetail(webBrief)
        await service.selectedItemDetailTask?.value
        precondition(service.browserContentMode == .video && service.selectedBrowserItem?.workshopTypeText == "Web")
        precondition(service.selectedBrowserItemError == nil && wire.sends == beforeRapidOpen + 1,
            "the same automatic detail request is shared, not canceled and reissued")

        // Keep A genuinely pending in the real query client, then select a full
        // cached B. Both inspector consumers must retire A and its spinner.
        let cachedWeb = service.selectedBrowserItem!
        let switching = SteamWorkshopService(query)
        switching.browserItems = [brief, cachedWeb]
        wire.holdsResponses = true
        reply = page(0, [value(brief.id)])
        switching.presentItemDetail(brief)
        while wire.deferredResponses.isEmpty { await Task.yield() }
        let obsoleteOnlineTask = switching.selectedItemDetailTask!
        switching.presentItemDetail(cachedWeb)
        precondition(!switching.isRefreshingSelectedBrowserItem && switching.selectedItemDetailTask == nil)
        wire.flushResponses()
        await obsoleteOnlineTask.value
        precondition(switching.selectedBrowserItem?.id == cachedWeb.id && switching.selectedBrowserItemError == nil)
        switching.openDownload(brief)
        while wire.deferredResponses.isEmpty { await Task.yield() }
        let obsoleteDownloadTask = switching.selectedItemDetailTask!
        switching.openDownload(cachedWeb)
        precondition(!switching.isRefreshingSelectedDownloadDetailItem && switching.selectedItemDetailTask == nil)
        wire.flushResponses()
        await obsoleteDownloadTask.value
        precondition(switching.selectedDownloadDetailItem == cachedWeb && switching.selectedDownloadDetailError == nil)
        // Same item, different consumers must transfer ownership, not dedupe
        // against a task that can only publish to the previous consumer.
        switching.openDownload(brief)
        while wire.deferredResponses.isEmpty { await Task.yield() }
        let priorConsumerTask = switching.selectedItemDetailTask!
        switching.presentItemDetail(brief)
        precondition(priorConsumerTask.isCancelled && switching.selectedDownloadInspectorItem == nil
            && switching.isRefreshingSelectedBrowserItem && !switching.isRefreshingSelectedDownloadDetailItem)
        while wire.deferredResponses.count < 2 { await Task.yield() }
        wire.flushResponses()
        await switching.selectedItemDetailTask?.value
        precondition(!switching.isRefreshingSelectedBrowserItem && switching.selectedBrowserItem?.detailFields.isEmpty == false)
        switching.presentItemDetail(brief)
        // The previous success enriched its browser list, so use a fresh lean A.
        switching.browserItems = [brief]
        switching.presentItemDetail(brief)
        while wire.deferredResponses.isEmpty { await Task.yield() }
        let navigationTask = switching.selectedItemDetailTask!
        switching.navigateToBrowse()
        precondition(navigationTask.isCancelled && switching.selectedItemDetailTask == nil
            && switching.inFlightDetailItemID == nil && !switching.isRefreshingSelectedBrowserItem)
        wire.flushResponses()
        await navigationTask.value
        wire.holdsResponses = false

        // Preserve discovery filters and loaded page identity across author navigation.
        let discoveryKey = service.steamKitBrowseStore.makeKey(source: .featured, contentMode: .video,
            filters: .none, search: "", window: .week)
        service.steamKitBrowseStore.resetFor(key: discoveryKey)
        reply = page(1, [value("100002", kind: "Video")], more: true)
        _ = try await service.steamKitBrowseStore.fetch(page: 1, generation: service.steamKitBrowseStore.bumpGeneration())
        service.browserState = .loaded
        service.facetFilters = .init(themes: [.anime], ageRating: .everyone, resolutions: [.uhd4k])
        let filters = service.facetFilters
        service.showAuthorWorkshop(for: detailed)
        precondition(service.fetches == 1 && service.browserContentMode == .video && service.facetFilters == filters)
        let authorKey = service.steamKitBrowseStore.currentKey!
        precondition(authorKey.contentTypeTags.isEmpty && authorKey.filters.isEmpty)
        reply = page(1, [value("3221354414"), value("100002", kind: "Web"), value("100003", kind: "Video")], more: true)
        let author = try await service.steamKitBrowseStore.fetch(page: 1, generation: service.steamKitBrowseStore.bumpGeneration())
        service.browserItems = author.items.map(SteamWorkshopBrowserItem.make(from:))
        service.browserState = .loaded; service.hasMoreBrowserItems = true
        service.setBrowserQuery("no-match")
        let grid = GridProbe(service)
        grid.orderedIDs = []
        grid.check()
        precondition(service.continuationRequests == 0, "local search must not silently fetch all pages")
        service.setBrowserQuery("3221354414")
        grid.orderedIDs = service.displayedBrowserItems.map(\.id)
        precondition(grid.orderedIDs.count == 1)
        grid.check()
        precondition(service.continuationRequests == 0, "a single local match cannot trigger grid preloading")
        service.retryLoadingMoreBrowserItems()
        precondition(service.continuationRequests == 1, "search still allows explicit footer continuation")
        service.setBrowserQuery("  ")
        grid.check()
        precondition(service.continuationRequests == 2, "clearing author search restores grid preloading")
        service.setBrowserQuery("no-match")
        service.currentBrowserScrollOffsetY = 420
        service.showAuthorWorkshop(for: service.browserItems[0])
        precondition(service.fetches == 1 && service.steamKitBrowseStore.nextPage == 2
            && service.browserQuery == "no-match" && service.currentBrowserScrollOffsetY == 420,
            "the same author is idempotent and keeps pages, search and scroll")
        service.browserLoadMoreRetryAfter = Date().addingTimeInterval(30)
        service.consecutiveEmptyLoadMorePages = 3
        service.returnToDiscoveryBrowse()
        precondition(service.browserContentMode == .video && service.facetFilters == filters
            && service.browserItems.map(\.id) == [webBrief.id] && service.steamKitBrowseStore.currentKey == discoveryKey)
        precondition(service.browserLoadMoreRetryAfter == .distantPast && service.consecutiveEmptyLoadMorePages == 0,
            "author page continuation failures cannot pause discovery continuation")
        // A snapshot whose first request was interrupted cannot restore a permanent spinner.
        service.browserState = .loading
        service.showAuthorWorkshop(for: detailed)
        service.returnToDiscoveryBrowse()
        precondition(service.fetches == 3, "an interrupted discovery load is restarted on return")
        service.browserState = .loaded
        service.browserItems = []
        service.prepareForBrowserEntry()
        precondition(service.fetches == 3, "a valid empty result must not reload whenever its view reattaches")
        print("detail/navigation PASS: full metadata repair, optional fields, sharing, filter isolation, idempotency and restoration")
        await client.stop(shutdownTimeout: 0.1)
    }
}
