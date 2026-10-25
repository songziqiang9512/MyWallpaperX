extension Notification.Name { static let appKitSelectItemRequested = Notification.Name("select") }
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
    var shouldUseSteamKitPersonal: Bool { source.isPersonal && !browseContext.isAuthorWorkshop }
    var shouldUseSteamKitStructuredBrowse: Bool { !shouldUseSteamKitPersonal }
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
    var authorWorkshopReturnDestination: SteamWorkshopAuthorReturnDestination?
    var currentDownloadsScrollOffsetY: CGFloat = 0
    var pendingDownloadsScrollRestoreOffsetY: CGFloat?
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
    struct Record {
        var id = "3221354414"
        let status = Status.ready
        let folderURL = URL(fileURLWithPath: "/isolated")
        var browserItem: SteamWorkshopBrowserItem?
    }
    var downloads: [Record] = []
    var records: [String: Record] = [:] { didSet { downloads = Array(records.values) } }
    init(_ query: SteamWorkshopQueryClient) {
        steamWorkshopQueryClient = query
        steamKitBrowseStore = SteamKitBrowseStore(queryClient: query)
    }
    func latestDownloadRecord(for id: String) -> Record? { downloads.first { $0.id == id } }
    func persistDownloadMetadata(item: SteamWorkshopBrowserItem, id: String, targetURL: URL, fetchedAt: Date = Date()) {
        metadata[id] = Snapshot(fetchedAt: fetchedAt, item: item)
        publications += 1
        savedItem = try! JSONEncoder().encode(item)
    }
    func reloadInstalledItems() {}
    struct Snapshot { let fetchedAt: Date; let item: SteamWorkshopBrowserItem }
    var metadata: [String: Snapshot] = [:]
    func managedDownloadSnapshots(matchingItemID: String) -> [String: Snapshot] { metadata }
    func setBrowserQuery(_ value: String) { browserQuery = value; updateDisplayedBrowserItems() }
    func fetchBrowserItems(forceRefresh: Bool = false) {
        fetches += 1
        browserState = .loading
        if case let .authorWorkshop(_, url) = browseContext {
            steamKitBrowseStore.resetFor(key: steamKitBrowseStore.makeAuthorKey(creatorSteamID: Self.creatorID(from: url)!))
            browserItems = []
        }
    }
    func loadMoreBrowserItemsIfNeeded() { continuationRequests += 1 }
    nonisolated static func workshopItemIDSearchID(from query: String) -> String? { nil }
    nonisolated static func resolvedAuthorWorkshopURL(for item: SteamWorkshopBrowserItem) -> URL? { item.authorWorkshopURL }
    nonisolated static func saveDetailCache(item: SteamWorkshopBrowserItem) {}
    nonisolated(unsafe) static var detailCaches: [String: SteamWorkshopDetailCacheSnapshot] = [:]
    nonisolated static func loadDetailCache(id: String) -> SteamWorkshopBrowserItem? { loadDetailCacheSnapshot(id: id)?.item }
    nonisolated static func loadDetailCacheSnapshot(id: String) -> SteamWorkshopDetailCacheSnapshot? { detailCaches[id] }

}

@MainActor final class GridProbe {
    let service: SteamWorkshopService
    var window: NSWindow? = NSWindow()
    var isApplyingSnapshot = false, isItemsApplyScheduled = false
    var pendingItems: [SteamWorkshopBrowserItem]?
    var orderedIDs = ["matching-card"]
    let scrollView = WallpaperGridScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
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
        precondition(service.latestDownloadRecord(for: brief.id)?.browserItem == persisted,
            "accepted details are immediately reusable before any library scan")
        service.dismissDownloadInspector()
        service.openDownload(service.latestDownloadRecord(for: brief.id)!.browserItem!)
        let sends = wire.sends
        service.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: false)
        precondition(wire.sends == sends && service.publications == 1, "reopening repaired metadata performs no query")

        // Execute the actual disk-cache reader, including identity and age checks.
        let cacheURL = DiskCacheProbe.detailCacheFileURL(id: brief.id)
        try JSONEncoder().encode(SteamWorkshopDetailCacheSnapshot(fetchedAt: Date(), item: detailed)).write(to: cacheURL)
        precondition(DiskCacheProbe.loadDetailCache(id: brief.id) == detailed)
        try JSONEncoder().encode(SteamWorkshopDetailCacheSnapshot(fetchedAt: Date().addingTimeInterval(-86401), item: detailed)).write(to: cacheURL)
        precondition(DiskCacheProbe.loadDetailCache(id: brief.id) == nil, "expired shared cache is not adopted as fresh")
        try JSONEncoder().encode(SteamWorkshopDetailCacheSnapshot(fetchedAt: Date(), item: detailed))
            .write(to: DiskCacheProbe.detailCacheFileURL(id: "different"))
        precondition(DiskCacheProbe.loadDetailCache(id: "different") == nil, "cache identity must match its requested ID")
        try Data("invalid".utf8).write(to: cacheURL)
        precondition(DiskCacheProbe.loadDetailCache(id: brief.id) == nil)

        // Expiration is a quiet refresh, not an explicit user retry.
        let quiet = SteamWorkshopService(query)
        quiet.records[brief.id] = .init(browserItem: detailed)
        quiet.metadata[brief.id] = .init(fetchedAt: Date().addingTimeInterval(-73 * 3600), item: detailed)
        wire.holdsResponses = true
        quiet.openDownload(detailed)
        precondition(quiet.selectedDownloadDetailItem == detailed && !quiet.isRefreshingSelectedDownloadDetailItem)
        let quietTask = quiet.selectedItemDetailTask!
        quiet.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: false, metadataIsStale: true)
        precondition(quiet.selectedItemDetailTask != nil && !quietTask.isCancelled, "quiet refresh deduplicates")
        while wire.deferredResponses.isEmpty { await Task.yield() }
        wire.flushResponses()
        await quietTask.value
        precondition(quiet.selectedDownloadDetailError == nil && quiet.publications == 1)
        wire.holdsResponses = false
        reply = page(0, [])
        quiet.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: false, metadataIsStale: true)
        await quiet.selectedItemDetailTask?.value
        precondition(quiet.selectedDownloadDetailError == nil && quiet.selectedDownloadDetailItem != nil,
            "quiet network failure keeps visible cached data without an error notice")
        quiet.refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: true)
        precondition(quiet.isRefreshingSelectedDownloadDetailItem, "manual retry remains visible")
        await quiet.selectedItemDetailTask?.value
        precondition(quiet.selectedDownloadDetailError != nil, "manual retry still reports a real failure")
        reply = page(0, [value(brief.id)])
        // A fresh shared detail cache repairs older local metadata without another query.
        let cached = SteamWorkshopService(query)
        cached.records[brief.id] = .init(browserItem: brief)
        cached.metadata[brief.id] = .init(fetchedAt: Date(), item: brief)
        let cacheDate = Date().addingTimeInterval(-3600)
        SteamWorkshopService.detailCaches[brief.id] = .init(fetchedAt: cacheDate, item: detailed)
        let beforeCache = wire.sends
        cached.openDownload(brief)
        precondition(cached.selectedDownloadDetailItem == detailed && cached.selectedItemDetailTask == nil)
        precondition(cached.metadata[brief.id]?.fetchedAt == cacheDate && cached.publications == 1,
            "cache adoption preserves original age rather than extending it")
        precondition(wire.sends == beforeCache, "cache reuse performs no helper or preview request")
        cached.dismissDownloadInspector()
        cached.openDownload(detailed)
        precondition(cached.publications == 1, "equal cache timestamp does not republish")
        SteamWorkshopService.detailCaches = [:]

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
        service.steamKitBrowseStore.resetFor(key: discoveryKey)
        reply = page(1, [])
        _ = try await service.steamKitBrowseStore.fetch(page: 1, generation: service.steamKitBrowseStore.bumpGeneration())
        service.browserState = .loaded
        service.browserItems = []
        service.prepareForBrowserEntry()
        precondition(service.fetches == 3, "a valid empty result must not reload whenever its view reattaches")
        // Downloads is the first origin even when a personal browser feed is retained.
        let downloadOrigin = SteamWorkshopService(query)
        downloadOrigin.source = .mySubscriptions
        downloadOrigin.selectedDownloadInspectorItem = detailed
        downloadOrigin.currentDownloadsScrollOffsetY = 780
        downloadOrigin.browserState = .loading
        var selectedRoute: String?
        let observer = NotificationCenter.default.addObserver(forName: .appKitSelectItemRequested,
            object: nil, queue: nil) { note in
                MainActor.assumeIsolated { selectedRoute = note.userInfo?["selectedItem"] as? String }
            }
        downloadOrigin.showAuthorWorkshop(for: detailed)
        precondition(downloadOrigin.authorWorkshopReturnDestination == .downloads && selectedRoute == "steamWorkshop",
            "Downloads entered after Subscriptions still hosts author pages in Workshop")
        downloadOrigin.browserState = .loaded
        downloadOrigin.showAuthorWorkshop(for: detailed)
        precondition(downloadOrigin.authorWorkshopReturnDestination == .downloads,
            "same-author reentry must preserve initial Downloads origin")
        let authorFetches = downloadOrigin.fetches
        downloadOrigin.isLoadingMoreBrowserItems = true
        downloadOrigin.isRefreshingBrowserFeed = true
        downloadOrigin.returnToDiscoveryBrowse()
        precondition(!downloadOrigin.isLoadingMoreBrowserItems && !downloadOrigin.isRefreshingBrowserFeed)
        precondition(selectedRoute == "steamDownloads" && downloadOrigin.pendingDownloadsScrollRestoreOffsetY == 780)
        precondition(downloadOrigin.fetches == authorFetches && downloadOrigin.browserState == .idle,
            "returning to Downloads does not load an interrupted invisible browser page")
        downloadOrigin.selectedDownloadInspectorItem = detailed
        downloadOrigin.showAuthorWorkshop(for: detailed)
        selectedRoute = nil
        downloadOrigin.returnToDiscoveryBrowse(selectOrigin: false)
        precondition(selectedRoute == nil && downloadOrigin.authorWorkshopReturnDestination == nil,
            "explicit sidebar navigation must not bounce to an old origin")
        downloadOrigin.source = .mySubscriptions
        downloadOrigin.showAuthorWorkshop(for: detailed)
        precondition(selectedRoute == "steamWorkshop" && downloadOrigin.authorWorkshopReturnDestination == .personal,
            "a direct subscription author entry uses Workshop but remembers subscription origin")
        downloadOrigin.returnToDiscoveryBrowse()
        precondition(selectedRoute == "steamSubscribed", "Back returns to Subscriptions independently of the author host")
        NotificationCenter.default.removeObserver(observer)
        print("detail/navigation PASS: full metadata repair, optional fields, sharing, filter isolation, idempotency and restoration")
        await client.stop(shutdownTimeout: 0.1)
    }
}
