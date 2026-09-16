import Foundation

final class QueryTransport: SteamServiceTransporting {
    var isRunning = false
    var onOutput: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?
    var respond: ([String: Any]) -> [String: Any] = { _ in [:] }
    func start() throws {
        isRunning = true
        emit(["v": 1, "type": "ready", "protocol": 1, "helperVersion": "0.1.0"])
    }
    func emit(_ value: [String: Any]) {
        var data = try! JSONSerialization.data(withJSONObject: value); data.append(10); onOutput?(data)
    }
    func send(_ data: Data) -> Bool {
        let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        var result: [String: Any] = ["v": 1, "type": "result", "requestId": request["requestId"]!,
                                    "ok": true, "data": respond(request)]
        if let epoch = request["accountEpoch"] { result["accountEpoch"] = epoch }
        emit(result)
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
        func item(_ id: String, _ size: Int) -> [String: Any] {
            ["publishedfileid": id, "creatorSteamId": "76561198000000000", "title": id,
             "description": "detail-\(id)", "consumerAppid": 431960, "fileSize": size,
             "visibility": 0, "banned": false, "subscriptions": 12, "favorited": 3,
             "lifetimeSubscriptions": 20, "lifetimeFavorited": 4, "views": 50,
             "dependencyIds": ["20", "21"],
             "tags": ["1", "2", "3", "4", "5", "6", "7", "8", "Video"]]
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
        wire.respond = { request in
            precondition(request["command"] as? String == "queryBrowse")
            let requestPayload = request["payload"] as! [String: Any]
            seenSort = requestPayload["sort"] as! String
            seenTags = requestPayload["tags"] as? [String] ?? []
            seenTagGroups = requestPayload["tagGroups"] as? [[String]] ?? []
            return payload
        }
        let facet = try await browse.fetch(page: 1, generation: browse.bumpGeneration())
        precondition(seenSort == "updated", "updated sort reaches helper")
        precondition(seenTags == ["Video"], "content mode stays AND tag")
        precondition(seenTagGroups.count == 3 && seenTagGroups[0] == ["Anime"]
            && seenTagGroups[1] == ["Everyone"] && seenTagGroups[2] == ["3840 x 2160"],
            "facet groups: in-facet OR, cross-facet AND")
        precondition(facet.items.count == 1)

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

        let authorKey = browse.makeAuthorKey(creatorSteamID: "76561198000000000", contentMode: .video,
            filters: .none)
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
        epoch = nil; subscriptions.refresh("1"); subscriptions.toggle("1")
        precondition(writes == 2 && subscriptions.state(for: "1") == .unknown)
        await client.stop(shutdownTimeout: 0)
        print("Strict queries, loaded-page projection, subscription timeout/account isolation PASS")
    }
}
