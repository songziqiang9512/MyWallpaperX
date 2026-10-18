import Foundation

final class QueryTransport: SteamServiceTransporting {
    var isRunning = false
    var onOutput: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?
    var respond: ([String: Any]) -> [String: Any] = { _ in [:] }
    var advertisedCapabilities = [SteamServiceProtocol.trendDaysCapability]
    var sends = 0
    var requests: [[String: Any]] = []
    var holdsResponses = false
    var deferredResponses: [[String: Any]] = []
    func flushResponses() {
        let responses = deferredResponses
        deferredResponses = []
        responses.forEach(emit)
    }
    func start() throws {
        isRunning = true
        emit(["v": 1, "type": "ready", "protocol": 1, "helperVersion": "0.1.0",
              "capabilities": advertisedCapabilities])
    }
    func emit(_ value: [String: Any]) {
        var data = try! JSONSerialization.data(withJSONObject: value); data.append(10); onOutput?(data)
    }
    func send(_ data: Data) -> Bool {
        let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        sends += 1
        requests.append(request)
        var result: [String: Any] = ["v": 1, "type": "result", "requestId": request["requestId"]!,
                                    "ok": true, "data": respond(request)]
        if let epoch = request["accountEpoch"] { result["accountEpoch"] = epoch }
        if holdsResponses { deferredResponses.append(result) } else { emit(result) }
        return true
    }
    func closeInput() {}
    func terminate() { isRunning = false }
    func scheduleForcedTermination(after delay: TimeInterval) {}
}

@main struct SteamQueryHarness {
    @MainActor static func main() async throws {
        let wire = QueryTransport()
        let client = SteamServiceClient(executablePath: "/fake", transportFactory: { _ in wire })
        let query = SteamWorkshopQueryClient(client: client)
        func item(_ id: String, _ size: Int, created: Int? = nil) -> [String: Any] {
            var value: [String: Any] = ["publishedfileid": id, "creatorSteamId": "76561198000000000", "title": id,
             "description": "detail-\(id)", "consumerAppid": 431960, "fileSize": size,
             "visibility": 0, "banned": false, "subscriptions": 12, "favorited": 3,
             "lifetimeSubscriptions": 20, "lifetimeFavorited": 4, "views": 50,
             "dependencyIds": ["20", "21"],
             "tags": ["1", "2", "3", "4", "5", "6", "7", "8", "Video"]]
            if let created { value["timeCreated"] = created }
            return value
        }
        func page(_ number: Int, _ items: [[String: Any]]) -> [String: Any] {
            ["page": number, "items": items, "total": 3, "hasMore": number < 3, "wrongAppDropped": 0]
        }
        var payload = page(1, [item("1", 10)])
        wire.respond = { _ in payload }
        let first = try await query.browse(sort: .newest, page: 1)
        precondition(first.items[0].tags.count == 9)
        precondition(first.items[0].creatorSteamId == "76561198000000000")
        precondition(first.items[0].description == "detail-1")
        precondition(first.items[0].subscriptions == 12 && first.items[0].views == 50)
        precondition(first.items[0].dependencyIds == ["20", "21"])
        for key in ["items", "page", "total", "hasMore", "wrongAppDropped"] {
            payload = page(1, [item("1", 10)]); payload.removeValue(forKey: key)
            do { _ = try await query.browse(sort: .newest, page: 1); fatalError("missing field accepted: \(key)") }
            catch SteamServiceClient.RequestError.helperError(let code, _) { precondition(code == "protocolMismatch") }
        }
        for bad in [["publishedfileid": "1"], item("", 1), item("abc", 1), item("18446744073709551616", 1)] {
            payload = page(1, [bad])
            do { _ = try await query.browse(sort: .newest, page: 1); fatalError("bad item accepted") } catch { }
        }
        var named = item("1", 1); named["creatorName"] = "海岸作者"
        payload = page(1, [named])
        let namedPage = try await query.browse(sort: .newest, page: 1)
        precondition(namedPage.items.first?.creatorName == "海岸作者")
        named["creatorName"] = 123
        payload = page(1, [named])
        do { _ = try await query.browse(sort: .newest, page: 1); fatalError("bad creator name accepted") } catch { }
        var badCreator = item("1", 1); badCreator["creatorSteamId"] = "vanity-name"
        payload = page(1, [badCreator])
        do { _ = try await query.browse(sort: .newest, page: 1); fatalError("bad creator accepted") } catch { }
        var badBanned = item("1", 1); badBanned["banned"] = "false"
        payload = page(1, [badBanned])
        do { _ = try await query.browse(sort: .newest, page: 1); fatalError("bad moderation accepted") } catch { }
        var badDependency = item("1", 1); badDependency["dependencyIds"] = ["not-an-id"]
        payload = page(1, [badDependency])
        do { _ = try await query.browse(sort: .newest, page: 1); fatalError("bad dependency accepted") } catch { }
        payload = ["states": ["1": "false"]]
        do { _ = try await query.subscriptionStates(ids: ["1"]); fatalError("invalid bool accepted") } catch { }
        payload = ["states": [:]]
        do { _ = try await query.subscriptionStates(ids: ["1"]); fatalError("missing state treated false") } catch { }
        payload = ["ids": ["1", 2], "page": 1, "total": 2, "hasMore": false]
        do { _ = try await query.favoriteIds(page: 1); fatalError("invalid ID dropped") } catch { }
        payload = page(0, []); payload["partial"] = [["publishedfileid": "7", "code": "unsupportedContent"]]
        let partial = try await query.details(ids: ["7"])
        precondition(partial.partialErrors.first?.publishedFileId == "7")

        let browse = SteamKitBrowseStore(queryClient: query)
        let key = browse.makePersonalKey(source: .mySubscriptions, accountSteamID: "a", contentMode: .all,
            filters: .none, search: "", window: .allTime, personalSort: .fileSize)
        browse.resetFor(key: key)
        payload = page(1, [item("1", 10)])
        _ = try await browse.fetchPersonal(page: 1, generation: browse.bumpGeneration())
        payload = page(2, [item("2", 100), item("1", 20)])
        let loaded = try await browse.fetchPersonal(page: 2, generation: browse.bumpGeneration())
        precondition(loaded.items.count == 2 && browse.rawItems.count == 2)
        precondition(Projection(browse).steamKitPersonalPostProcess(loaded.items).map(\.publishedFileId) == ["2", "1"], "sort whole loaded set, not page append")
        payload = [:]
        do { _ = try await browse.fetchPersonal(page: 3, generation: browse.bumpGeneration()); fatalError("bad page accepted") } catch { }
        precondition(browse.nextPage == 3 && browse.rawItems.count == 2, "failure preserves raw pages and next page")
        payload = page(3, [item("3", 30)])
        _ = try await browse.fetchPersonal(page: 3, generation: browse.generation - 1)
        precondition(browse.nextPage == 3 && browse.rawItems.count == 2, "stale page cannot commit")
        precondition(SteamKitBrowseStore.sort(for: .updated) == .updated)
        let discoverySnapshot = browse.snapshot()

        // 分面筛选：discovery 键把面选择编译为服务端 taggroups（面内 OR、
        // 跨面 AND），content mode 仍是 AND requiredtag；updated 排序放行。
        let facetKey = browse.makeKey(source: .updated, contentMode: .video,
            filters: SteamWorkshopBrowseFacetFilters(themes: [.anime], ageRating: .everyone,
                resolutions: [.uhd4k]),
            search: "", window: .allTime)
        browse.resetFor(key: facetKey)
        payload = page(1, [item("21", 10)])
        var seenTagGroups: [[String]] = []
        var seenTags: [String] = []
        var seenSort = ""
        var seenTrendDays: Int?
        wire.respond = { request in
            precondition(request["command"] as? String == "queryBrowse")
            let requestPayload = request["payload"] as! [String: Any]
            seenSort = requestPayload["sort"] as! String
            seenTags = requestPayload["tags"] as? [String] ?? []
            seenTagGroups = requestPayload["tagGroups"] as? [[String]] ?? []
            seenTrendDays = requestPayload["days"] as? Int
            return payload
        }
        let facet = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        precondition(seenSort == "updated", "updated sort reaches helper")
        precondition(seenTags == ["Video"], "content mode stays AND tag")
        precondition(seenTagGroups.count == 3 && seenTagGroups[0] == ["Anime"]
            && seenTagGroups[1] == ["Everyone"] && seenTagGroups[2] == ["3840 x 2160"],
            "facet groups: in-facet OR, cross-facet AND")
        precondition(facet.items.count == 1)
        precondition(SteamWorkshopTrendingWindow.today.rankingDays == 1
            && SteamWorkshopTrendingWindow.week.rankingDays == 7
            && SteamWorkshopTrendingWindow.month.rankingDays == 30
            && SteamWorkshopTrendingWindow.quarter.rankingDays == 90
            && SteamWorkshopTrendingWindow.halfYear.rankingDays == 180
            && SteamWorkshopTrendingWindow.year.rankingDays == 365
            && SteamWorkshopTrendingWindow.allTime.rankingDays == nil,
            "trend windows must map to the supported remote ranking interval")

        // A trend window defines the remote ranking interval. It is not a
        // publication-date filter: an older item returned by Steam must keep
        // its server order and remain visible.
        let trendKey = browse.makeKey(source: .featured, contentMode: .video,
            filters: .none, search: "", window: .week)
        browse.resetFor(key: trendKey)
        payload = page(1, [item("22", 10, created: 1)])
        let trend = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        let trendProjection = Projection(browse)
        trendProjection.source = .featured
        trendProjection.trendingWindow = .week
        precondition(trendProjection.steamKitStructuredPostProcess(trend.items)
            .map(\.publishedFileId) == ["22"],
            "trend days rank the remote result and cannot delete older publications")
        precondition(seenTrendDays == 7 && trendKey.trendDays == 7,
            "the frozen query key must carry the week ranking interval to the helper")

        // Freeze capability negotiation at the actual browse business entry.
        // An old helper may still serve all-time trend results, but a week
        // window must fail before any request reaches its wire.
        let oldWire = QueryTransport()
        oldWire.advertisedCapabilities = []
        oldWire.respond = { _ in page(1, [item("77", 10, created: 1)]) }
        let oldClient = SteamServiceClient(executablePath: "/old-helper", transportFactory: { _ in oldWire })
        let oldQuery = SteamWorkshopQueryClient(client: oldClient)
        let oldBrowse = SteamKitBrowseStore(queryClient: oldQuery)
        let allTimeKey = oldBrowse.makeKey(source: .featured, contentMode: .video,
            filters: .none, search: "", window: .allTime)
        oldBrowse.resetFor(key: allTimeKey)
        let oldAllTime = try await oldBrowse.fetch(page: 1, generation: oldBrowse.bumpGeneration())
        precondition(oldAllTime.items.map(\.publishedFileId) == ["77"] && oldWire.sends == 1,
            "an old helper must remain compatible with an all-time trend query")
        let allTimePayload = oldWire.requests.last?["payload"] as? [String: Any]
        precondition(allTimePayload?["days"] == nil, "all-time must not send trend days")
        let oldWeekKey = oldBrowse.makeKey(source: .featured, contentMode: .video,
            filters: .none, search: "", window: .week)
        oldBrowse.resetFor(key: oldWeekKey)
        do {
            _ = try await oldBrowse.fetch(page: 1, generation: oldBrowse.bumpGeneration())
            fatalError("old helper accepted a windowed trend query")
        } catch SteamServiceClient.RequestError.incompatibleProtocol {
            precondition(oldWire.sends == 1,
                "a missing trend capability must reject before the windowed wire send")
        }

        let multi = SteamWorkshopBrowseFacetFilters(themes: [.anime, .nature],
            ageRating: .everyone, resolutions: [.uhd4k, .fhd])
        precondition(multi.tagGroups == [["Anime", "Nature"], ["Everyone"], ["3840 x 2160", "1920 x 1080"]])
        precondition(multi.allows(tags: ["Nature", "Everyone", "1920 x 1080"]))
        precondition(multi.allows(tags: ["anime", "Everyone", "3840 x 2160"]))
        precondition(!multi.allows(tags: ["City", "Everyone", "1920 x 1080"]))
        precondition(!multi.allows(tags: ["Anime", "Everyone", "2560 x 1440"]))
        precondition(!multi.allows(tags: ["Anime", "Mature", "3840 x 2160"]))

        var categories: SteamWorkshopBrowserContentMode = .all
        categories.toggle(.video)
        categories.toggle(.scene)
        precondition(categories == [.video, .scene])
        precondition(categories.queryTags == ["Video", "Scene"])
        precondition(categories.allows(tags: ["Scene"]) && categories.allows(tags: ["video"]))
        precondition(!categories.allows(tags: ["Web"]))
        let combinedKey = browse.makeKey(source: .updated, contentMode: categories,
            filters: multi, search: "", window: .allTime)
        precondition(combinedKey != facetKey, "category combinations must invalidate the query")
        precondition(combinedKey == browse.makeKey(source: .updated, contentMode: [.scene, .video],
            filters: multi, search: "", window: .allTime), "click order must not change key")
        browse.resetFor(key: combinedKey)
        _ = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        precondition(seenTags.isEmpty, "multiple categories cannot be AND required tags")
        precondition(seenTagGroups == [["Video", "Scene"]] + multi.tagGroups)
        var videoItem = item("31", 30)
        videoItem["tags"] = ["Video", "Anime", "Everyone", "3840 x 2160"]
        var sceneItem = item("32", 20)
        sceneItem["tags"] = ["Scene", "Nature", "Everyone", "1920 x 1080"]
        var webItem = item("33", 10)
        webItem["tags"] = ["Web", "Anime", "Everyone", "3840 x 2160"]
        payload = page(1, [videoItem, sceneItem, webItem])
        let mixed = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        let visibleIDs = Set(Projection(browse).steamKitPersonalPostProcess(mixed.items).map(\.publishedFileId))
        precondition(visibleIDs == ["31", "32"], "grid projection must keep Video/Scene and reject Web")
        categories.toggle(.scene)
        precondition(categories == .video)
        categories.toggle(.video)
        precondition(categories == .all && categories.queryTags.isEmpty)

        let authorKey = browse.makeAuthorKey(creatorSteamID: "76561198000000000")
        browse.resetFor(key: authorKey)
        payload = page(1, [item("10", 10)])
        wire.respond = { request in
            precondition(request["command"] as? String == "queryAuthor")
            let requestPayload = request["payload"] as! [String: Any]
            precondition(requestPayload["creatorSteamId"] as? String == "76561198000000000")
            return payload
        }
        let author = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        precondition(author.items.map(\.publishedFileId) == ["10"])
        precondition(authorKey.contentTypeTags.isEmpty && authorKey.filters.isEmpty,
            "author requests cannot inherit hidden discovery filters")
        let authorProjection = Projection(browse)
        authorProjection.browserContentMode = .video
        authorProjection.facetFilters = multi
        precondition(authorProjection.steamKitStructuredPostProcess(mixed.items).map(\.publishedFileId)
            == ["31", "32", "33"], "all author content types survive discovery filters")

        let detailsKey = browse.makeDetailsKey(itemID: "11")
        browse.resetFor(key: detailsKey)
        payload = page(0, [item("11", 11)])
        wire.respond = { request in
            if request["command"] as? String != "queryDetails" { return [:] }
            return payload
        }
        let details = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        precondition(details.items.map(\.publishedFileId) == ["11"] && !details.hasMore)
        let detailGeneration = browse.generation
        browse.restore(discoverySnapshot)
        precondition(browse.generation == detailGeneration + 1)
        precondition(browse.currentKey == key && browse.nextPage == 3 && browse.hasMore)
        precondition(browse.rawItems.map(\.publishedFileId) == ["1", "2"])

        // A removal edits the loaded feed in place. Offset pages overlap on the
        // next continuation; even replaying page one must keep later survivors.
        let membership = SteamKitBrowseStore(queryClient: query)
        membership.resetFor(key: key)
        wire.respond = { _ in payload }
        payload = page(1, [item("101", 10), item("102", 10)])
        _ = try await membership.fetchPersonal(page: 1, generation: membership.bumpGeneration(), replacingLoadedItems: true)
        payload = page(2, [item("103", 10), item("104", 10)])
        _ = try await membership.fetchPersonal(page: 2, generation: membership.bumpGeneration())
        let membershipProjection = Projection(membership)
        membershipProjection.browserItems = membership.rawItems.map { .init(id: $0.publishedFileId) }
        let beforeRemoval = membership.generation
        membershipProjection.reconcileSubscriptionWrite(itemID: "102", isSubscribed: false)
        precondition(membershipProjection.browserItems.map(\.id) == ["101", "103", "104"])
        precondition(membership.rawItems.map(\.publishedFileId) == ["101", "103", "104"])
        precondition(membershipProjection.refreshes == 0 && membership.nextPage == 2)
        payload = page(3, [item("102", 10), item("999", 10)])
        _ = try await membership.fetchPersonal(page: 3, generation: beforeRemoval)
        precondition(membership.rawItems.map(\.publishedFileId) == ["101", "103", "104"], "old page cannot resurrect removed membership")
        payload = page(2, [item("104", 10), item("105", 10)])
        _ = try await membership.fetchPersonal(page: membership.nextPage, generation: membership.bumpGeneration())
        precondition(membership.rawItems.map(\.publishedFileId) == ["101", "103", "104", "105"], "overlap includes the remote page boundary item")
        membershipProjection.reconcileSubscriptionWrite(itemID: "101", isSubscribed: false)
        precondition(membership.nextPage == 2)
        membershipProjection.reconcileSubscriptionWrite(itemID: "103", isSubscribed: false)
        precondition(membership.nextPage == 1)
        payload = page(1, [item("104", 10), item("106", 10)])
        _ = try await membership.fetchPersonal(page: 1, generation: membership.bumpGeneration())
        precondition(membership.rawItems.map(\.publishedFileId) == ["104", "105", "106"], "page-one continuation preserves later loaded survivors")
        let oldPageObservation = membershipProjection.steamSubscriptions.beginMembershipObservation()
        membershipProjection.steamSubscriptions.refresh("104")
        for _ in 0..<1000 {
            if membershipProjection.steamSubscriptions.state(for: "104") == .known(false) { break }
            await Task.yield()
        }
        precondition(membershipProjection.steamKitPersonalPostProcess(membership.rawItems).map(\.publishedFileId) == ["105", "106"], "confirmed negatives stay out of future and restored personal projections")
        membershipProjection.browserItems = membership.rawItems.map { .init(id: $0.publishedFileId) }
        precondition(membershipProjection.displayedBrowserItems.map(\.id) == ["105", "106"], "restored browser snapshots honor current membership")
        membershipProjection.browseContext.isAuthorWorkshop = true
        membershipProjection.updateDisplayedBrowserItems()
        precondition(membershipProjection.displayedBrowserItems.map(\.id) == ["104", "105", "106"], "an author's page is independent of subscription membership")
        membershipProjection.browseContext.isAuthorWorkshop = false
        membershipProjection.steamSubscriptions.observeSubscribedIDs(["104"], observation: oldPageObservation)
        precondition(membershipProjection.steamSubscriptions.state(for: "104") == .known(false), "a page started before readback cannot resurrect a removed subscription")
        let newPageObservation = membershipProjection.steamSubscriptions.beginMembershipObservation()
        membershipProjection.steamSubscriptions.observeSubscribedIDs(["104"], observation: newPageObservation)
        precondition(membershipProjection.steamSubscriptions.state(for: "104") == .known(true), "a fresh page can discover a subscription restored externally")
        membershipProjection.reconcileSubscriptionWrite(itemID: "104", isSubscribed: true)
        precondition(membershipProjection.refreshes == 0, "a rejected unsubscribe leaves existing membership alone")
        membershipProjection.source = .myFavorites
        membershipProjection.updateDisplayedBrowserItems()
        precondition(membershipProjection.displayedBrowserItems.map(\.id) == ["104", "105", "106"], "favorite membership is independent of subscription membership")
        membershipProjection.reconcileSubscriptionWrite(itemID: "104", isSubscribed: false)
        precondition(membership.rawItems.map(\.publishedFileId) == ["104", "105", "106"], "subscription actions cannot remove favorite cards")
        membershipProjection.source = .mySubscriptions
        membershipProjection.shouldUseSteamKitPersonal = false
        membershipProjection.reconcileSubscriptionWrite(itemID: "104", isSubscribed: false)
        precondition(membership.rawItems.count == 3, "an author view keeps the author's work")

        // The actual write/readback hook must re-project a details-route card
        // whose cached content survived an unsubscribe.
        let detailStore = SteamKitBrowseStore(queryClient: query)
        detailStore.resetFor(key: detailStore.makeDetailsKey(itemID: "401"))
        let detailProjection = Projection(detailStore)
        detailProjection.browserItems = [.init(id: "401")]
        detailProjection.steamSubscriptions.refresh("401")
        for _ in 0..<1000 {
            if detailProjection.steamSubscriptions.state(for: "401") == .known(false) { break }
            await Task.yield()
        }
        detailProjection.reconcileSubscriptionWrite(itemID: "401", isSubscribed: false)
        precondition(detailProjection.displayedBrowserItems.isEmpty)
        detailProjection.steamSubscriptions.toggle("401")
        for _ in 0..<1000 {
            if detailProjection.steamSubscriptions.state(for: "401") == .known(true) { break }
            await Task.yield()
        }
        precondition(detailProjection.displayedBrowserItems.map(\.id) == ["401"], "subscribe hook restores the hidden cached card")

        let restoredStore = SteamKitBrowseStore(queryClient: query)
        restoredStore.resetFor(key: key)
        payload = page(1, [item("501", 10), item("502", 10)])
        _ = try await restoredStore.fetchPersonal(page: 1, generation: restoredStore.bumpGeneration(), replacingLoadedItems: true)
        let restored = Projection(restoredStore)
        restored.browserItems = restoredStore.rawItems.map { .init(id: $0.publishedFileId) }
        let saved = restored.makeDiscoveryBrowseSnapshot()
        restoredStore.resetFor(key: authorKey)
        restored.browseContext.isAuthorWorkshop = true
        restored.shouldUseSteamKitPersonal = false
        restored.steamSubscriptions.observeSubscribedIDs(["501"])
        restored.steamSubscriptions.toggle("501")
        for _ in 0..<1000 {
            if restored.steamSubscriptions.state(for: "501") == .known(false) { break }
            await Task.yield()
        }
        restored.browseContext.isAuthorWorkshop = false
        restored.shouldUseSteamKitPersonal = true
        restored.restoreDiscoveryBrowseSnapshot(saved, restoredQuery: "")
        precondition(restored.navigations == 0 && restoredStore.nextPage == 1,
            "author-page unsubscribe rewinds the saved personal page boundary")
        precondition(restored.browserItems.map(\.id) == ["502"])
        let observation = restored.steamSubscriptions.beginMembershipObservation()
        payload = page(1, [item("502", 10), item("503", 10)])
        let replay = try await restoredStore.fetchPersonal(page: restoredStore.nextPage, generation: restoredStore.bumpGeneration())
        restored.steamSubscriptions.observeSubscribedIDs(replay.observedSubscribedIDs, observation: observation)
        precondition(restored.steamKitPersonalPostProcess(replay.items).map(\.publishedFileId) == ["502", "503"],
            "overlap fills the boundary without resurrecting the canceled card")
        // An old cached ID is not new evidence even when it survived in raw.
        restoredStore.restore(saved.steamKitBrowseSnapshot)
        payload = page(2, [item("504", 10)])
        let freshObservation = restored.steamSubscriptions.beginMembershipObservation()
        let merged = try await restoredStore.fetchPersonal(page: 2, generation: restoredStore.bumpGeneration())
        restored.steamSubscriptions.observeSubscribedIDs(merged.observedSubscribedIDs, observation: freshObservation)
        precondition(merged.items.contains { $0.publishedFileId == "501" }
            && restored.steamSubscriptions.state(for: "501") == .known(false),
            "merged cache cannot supply fresh positive membership evidence")
        restored.steamAuth.steamId = "b"
        restored.restoreDiscoveryBrowseSnapshot(saved, restoredQuery: "")
        precondition(restored.navigations == 1, "account B cannot restore account A's personal feed")
        restored.steamAuth.steamId = "a"; restored.steamAuth.isOnline = false
        restored.restoreDiscoveryBrowseSnapshot(saved, restoredQuery: "")
        precondition(restored.navigations == 2, "logged-out personal restoration navigates to login guidance")

        // The detail inspector can remove membership while a new initial page
        // is in flight, even though that key has no raw items yet.
        let emptyStore = SteamKitBrowseStore(queryClient: query)
        emptyStore.resetFor(key: key)
        let initialGeneration = emptyStore.bumpGeneration()
        let loading = Projection(emptyStore)
        loading.browserState = .loading
        loading.reconcileSubscriptionWrite(itemID: "601", isSubscribed: false)
        precondition(loading.refreshes == 1 && emptyStore.generation > initialGeneration,
            "remove miss retires and restarts an initial personal page")
        payload = page(1, [item("601", 10), item("602", 10)])
        _ = try await emptyStore.fetchPersonal(page: 1, generation: initialGeneration)
        precondition(emptyStore.nextPage == 1 && emptyStore.rawItems.isEmpty,
            "stale initial page cannot advance the cursor after remove miss")

        // Real section navigation, success TTL and loaded-tail preservation.
        var clock: TimeInterval = 1000
        let cache = SteamKitBrowseStore(queryClient: query, now: { clock })
        cache.resetFor(key: key)
        payload = page(1, [item("701", 10), item("702", 10)])
        _ = try await cache.fetchPersonal(page: 1, generation: cache.bumpGeneration(), replacingLoadedItems: true)
        clock += 30
        payload = page(2, [item("703", 10)])
        _ = try await cache.fetchPersonal(page: 2, generation: cache.bumpGeneration())
        let tabs = Projection(cache)
        tabs.browserItems = cache.rawItems.map { .init(id: $0.publishedFileId) }
        tabs.currentBrowserScrollOffsetY = 550
        tabs.consecutiveEmptyLoadMorePages = 3
        tabs.browserLoadMoreRetryAfter = Date().addingTimeInterval(30)
        let retryAfter = tabs.browserLoadMoreRetryAfter
        tabs.enterBrowseSection(.discovery)
        precondition(tabs.navigations == 1 && tabs.source == .featured)
        let publicKey = cache.makeKey(source: .featured, contentMode: .all,
            filters: .none, search: "", window: .allTime)
        cache.resetFor(key: publicKey)
        payload = page(1, [item("801", 10), item("802", 10)])
        _ = try await cache.fetch(page: 1, generation: cache.bumpGeneration())
        tabs.browserItems = cache.rawItems.map { .init(id: $0.publishedFileId) }
        tabs.browserState = .loaded
        tabs.currentBrowserScrollOffsetY = 120
        tabs.pendingBrowserScrollRestoreOffset = nil
        tabs.enterBrowseSection(.personal)
        precondition(tabs.browserItems.map(\.id) == ["701", "702", "703"] && cache.nextPage == 3)
        precondition(tabs.pendingBrowserScrollRestoreOffset == 550 && tabs.personalSort == .fileSize)
        precondition(tabs.consecutiveEmptyLoadMorePages == 3 && tabs.browserLoadMoreRetryAfter == retryAfter,
            "tab return preserves sparse-page pause and automatic retry cooldown")
        tabs.prepareForBrowserEntry()
        tabs.enterBrowseSection(.personal)
        precondition(tabs.refreshes == 0 && tabs.navigations == 1, "fresh tab return does not request or reorder")
        clock = 1119.9
        tabs.prepareForBrowserEntry()
        precondition(tabs.refreshes == 0, "pagination must not extend first-page TTL")
        clock = 1120
        tabs.prepareForBrowserEntry()
        precondition(tabs.refreshes == 1, "personal TTL expires at 120 seconds")
        tabs.isLoadingMoreBrowserItems = true
        tabs.prepareForBrowserEntry()
        precondition(tabs.refreshes == 1, "entry cannot duplicate continuation")
        tabs.isLoadingMoreBrowserItems = false
        let holding = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        tabs.browserFetchTask = holding
        tabs.prepareForBrowserEntry()
        precondition(tabs.refreshes == 1, "entry cannot duplicate in-flight first page")
        holding.cancel(); tabs.browserFetchTask = nil
        payload = page(1, [item("701", 20), item("702", 10)])
        let sameHead = try await cache.fetchPersonal(page: 1, generation: cache.bumpGeneration(), replacingLoadedItems: true)
        precondition(sameHead.items.map(\.publishedFileId) == ["701", "702", "703"] && cache.nextPage == 3)
        precondition(sameHead.observedSubscribedIDs == ["701", "702"], "cached tail is not new membership evidence")
        precondition(cache.isFresh(maxAge: 120))
        payload = [:]
        clock = 1300
        do { _ = try await cache.fetchPersonal(page: 1, generation: cache.bumpGeneration(), replacingLoadedItems: true); fatalError("bad refresh accepted") } catch {}
        precondition(!cache.isFresh(maxAge: 120) && cache.rawItems.count == 3, "failure preserves content without extending TTL")
        payload = page(1, [item("709", 10)])
        _ = try await cache.fetchPersonal(page: 1, generation: cache.bumpGeneration(), replacingLoadedItems: true)
        precondition(cache.rawItems.map(\.publishedFileId) == ["709"] && cache.nextPage == 2, "changed head retires tail")
        clock = 1299
        precondition(!cache.isFresh(maxAge: 120), "a future stamp cannot be fresh")
        clock = 1300
        tabs.enterBrowseSection(.discovery)
        tabs.shouldUseSteamKitPersonal = false; tabs.shouldUseSteamKitStructuredBrowse = true
        tabs.prepareForBrowserEntry()
        precondition(tabs.refreshes == 1, "public feed has its own 300-second TTL")
        clock = 1330
        tabs.prepareForBrowserEntry()
        precondition(tabs.refreshes == 2)

        // Failed/loading new criteria replace any older successful tab snapshot.
        tabs.browserQuery = "new search"
        tabs.browserContentMode = .scene
        tabs.browserState = .failed("offline")
        cache.resetFor(key: cache.makeKey(source: .featured, contentMode: .scene,
            filters: .none, search: "new search", window: .allTime))
        tabs.enterBrowseSection(.personal)
        tabs.enterBrowseSection(.discovery)
        precondition(tabs.browserQuery == "new search" && tabs.browserContentMode == .scene,
            "return after a failed new query preserves current controls")
        precondition(tabs.navigations == 2, "failed snapshot restarts its own query")

        // Subscription writes preserve inactive personal criteria; account events discard private data.
        tabs.enterBrowseSection(.personal)
        tabs.shouldUseSteamKitPersonal = true; tabs.shouldUseSteamKitStructuredBrowse = false
        tabs.browserContentMode = .scene; tabs.browserQuery = "my scene"
        tabs.personalSort = .name; tabs.browserState = .loaded
        cache.resetFor(key: cache.makePersonalKey(source: .mySubscriptions, accountSteamID: "a",
            contentMode: .scene, filters: .none, search: "my scene", window: .allTime, personalSort: .name))
        payload = page(1, [item("711", 10)])
        _ = try await cache.fetchPersonal(page: 1, generation: cache.bumpGeneration(), replacingLoadedItems: true)
        tabs.browserItems = [.init(id: "711")]
        tabs.enterBrowseSection(.discovery)
        tabs.reconcileSubscriptionWrite(itemID: "711", isSubscribed: false)
        tabs.enterBrowseSection(.personal)
        precondition(tabs.browserQuery == "my scene" && tabs.browserContentMode == .scene && tabs.personalSort == .name)
        precondition(!cache.isFresh(maxAge: 120), "inactive subscription write expires personal data")
        let beforeAuthorReturn = tabs.refreshes
        tabs.discoveryBrowseSnapshot = tabs.makeDiscoveryBrowseSnapshot()
        tabs.savedDiscoveryQueryBeforeAuthorBrowse = tabs.browserQuery
        tabs.browseContext.isAuthorWorkshop = true
        tabs.shouldUseSteamKitPersonal = false; tabs.shouldUseSteamKitStructuredBrowse = true
        cache.resetFor(key: authorKey)
        tabs.reconcileSubscriptionWrite(itemID: "712", isSubscribed: true)
        // Actual computed routing changes synchronously with browseContext in the App.
        tabs.shouldUseSteamKitPersonal = true; tabs.shouldUseSteamKitStructuredBrowse = false
        tabs.returnToDiscoveryBrowse()
        precondition(tabs.refreshes == beforeAuthorReturn + 1 && tabs.browserQuery == "my scene",
            "author return refreshes expired personal content without losing controls")
        tabs.refresh()
        precondition(tabs.refreshes == beforeAuthorReturn + 2, "manual refresh bypasses TTL")
        tabs.invalidatePersonalBrowseSnapshot(discard: true)
        precondition(tabs.retainedBrowseSections[.personal] == nil && cache.currentKey == nil && cache.rawItems.isEmpty,
            "account event clears current private tail even when the SteamID will be unchanged")
        payload = page(1, [item("711", 10)])
        cache.resetFor(key: key)
        _ = try await cache.fetchPersonal(page: 1, generation: cache.bumpGeneration(), replacingLoadedItems: true)
        precondition(cache.nextPage == 2 && cache.rawItems.count == 1, "same-account relogin starts without old tail")
        print("Section cache, TTL, failed criteria, membership invalidation and account boundaries PASS")

        var epoch: Int? = 1
        var writes = 0
        var reads = 0
        var remote = false
        var failRead = false
        var held: CheckedContinuation<Bool, Error>?
        var holdRead = false
        let subscriptions = SteamWorkshopSubscriptionStore(identity: { epoch }, read: { _ in
            reads += 1
            if holdRead { return try await withCheckedThrowingContinuation { held = $0 } }
            if failRead { throw URLError(.timedOut) }
            return remote
        }, write: { _, desired in
            writes += 1; remote = desired
            throw URLError(.timedOut) // server applied, response lost
        })
        func waitIdle(_ id: String) async {
            for _ in 0..<1000 {
                switch subscriptions.state(for: id) {
                case .loading, .writing, .reconciling: await Task.yield()
                default: return
                }
            }
            fatalError("store did not settle")
        }
        let firstAccountObservation = subscriptions.beginMembershipObservation()
        subscriptions.observeSubscribedIDs(["2"])
        precondition(subscriptions.state(for: "2") == .known(true), "current subscription page seeds membership")
        subscriptions.toggle("1")
        precondition(writes == 0 && reads == 0, "unknown cannot write")
        subscriptions.refresh("1"); await waitIdle("1")
        precondition(subscriptions.state(for: "1") == .known(false))
        subscriptions.toggle("1"); subscriptions.toggle("1"); await waitIdle("1")
        precondition(writes == 1 && reads == 2 && subscriptions.state(for: "1") == .known(true), "timeout readback, no duplicate write")
        failRead = true
        subscriptions.toggle("1"); await waitIdle("1")
        precondition(writes == 2)
        if case .unconfirmed = subscriptions.state(for: "1") {} else { fatalError("ambiguous result assumed known") }
        subscriptions.toggle("1"); precondition(writes == 2, "unconfirmed cannot repeat write")
        failRead = false; holdRead = true
        subscriptions.refresh("1")
        while held == nil { await Task.yield() }
        epoch = 2; subscriptions.synchronizeAccount()
        held?.resume(returning: true); held = nil
        for _ in 0..<20 { await Task.yield() }
        precondition(subscriptions.state(for: "1") == .unknown, "old account read cannot publish")
        precondition(subscriptions.state(for: "2") == .unknown, "page membership cannot cross accounts")
        subscriptions.observeSubscribedIDs(["2"], observation: firstAccountObservation)
        precondition(subscriptions.state(for: "2") == .unknown, "a prior account page cannot reseed membership")
        epoch = nil; subscriptions.refresh("1"); subscriptions.toggle("1")
        precondition(writes == 2 && subscriptions.state(for: "1") == .unknown)
        await client.stop(shutdownTimeout: 0)
        print("Strict queries, loaded-page projection, subscription timeout/account isolation PASS")
    }
}
