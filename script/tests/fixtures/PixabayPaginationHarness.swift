import AppKit
import Combine
import Foundation

// PRODUCTION_DECODER

@MainActor private final class PagingService: ObservableObject {
    // PRODUCTION_FIELDS
    let session: URLSession
    var apiKey = "fixture-key"
    var hasValidAPIKey: Bool { !apiKey.isEmpty }
    var thumbnailCancellations = 0
    var mergeVisits = 0
    init(session: URLSession) { self.session = session }
    func cancelThumbnailPrefetch() { thumbnailCancellations += 1 }
    // PRODUCTION_OWNER
    func auditIndex() -> Bool {
        itemIndexByID.count == items.count && items.enumerated().allSatisfy { itemIndexByID[$0.element.id] == $0.offset }
    }
    func task() -> Task<Void, Never>? { searchTask }
    func page() -> Int { currentPage }
}

nonisolated private final class PageProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: ControlledPageProtocol] = [:]
    private var counts: [String: Int] = [:]
    private var stoppedKeys = Set<String>()
    static func key(_ request: URLRequest) -> String {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        return (query.first { $0.name == "q" }?.value ?? "") + ":" + (query.first { $0.name == "page" }?.value ?? "")
    }
    func start(_ value: ControlledPageProtocol) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(value.request)
        pending[key] = value; counts[key, default: 0] += 1
    }
    func stop(_ value: ControlledPageProtocol) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(value.request)
        if pending[key] === value { pending.removeValue(forKey: key) }
        stoppedKeys.insert(key)
    }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[key, default: 0] }
    func parameters(_ key: String) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: URLComponents(url: pending[key]!.request.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
    }
    func stopped(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return stoppedKeys.contains(key) }
    func take(_ key: String) -> ControlledPageProtocol {
        lock.lock(); defer { lock.unlock() }
        guard let value = pending.removeValue(forKey: key) else { preconditionFailure("no live real HTTP request: " + key) }
        return value
    }
    func reply(_ key: String, data: Data, status: Int = 200) {
        let value = take(key)
        value.client?.urlProtocol(value, didReceive: HTTPURLResponse(url: value.request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        value.client?.urlProtocol(value, didLoad: data)
        value.client?.urlProtocolDidFinishLoading(value)
    }
    func fail(_ key: String) {
        let value = take(key)
        value.client?.urlProtocol(value, didFailWithError: URLError(.notConnectedToInternet))
    }
}

nonisolated private final class ControlledPageProtocol: URLProtocol, @unchecked Sendable {
    static let state = PageProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "pixabay.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state.start(self) }
    override func stopLoading() { Self.state.stop(self) }
}

@main private struct PixabayPaginationHarness {
    @MainActor static func wait(_ label: String, until condition: () -> Bool) async {
        for _ in 0..<3000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("timed out: " + label)
    }
    static func response(_ hits: [(Int, String)], total: Int) -> Data {
        let values: [[String: Any]] = hits.map { id, title in
            ["id": id, "pageURL": "https://pixabay.com/videos/\(id)/", "tags": title,
             "duration": 9, "user": "author", "videos": ["small": ["url": "https://media.test/\(id).mp4",
              "width": 640, "height": 360, "size": 123, "thumbnail": "https://media.test/\(id).jpg"]]]
        }
        return try! JSONSerialization.data(withJSONObject: ["totalHits": total, "hits": values])
    }
    @MainActor static func service() -> PagingService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledPageProtocol.self]
        return PagingService(session: URLSession(configuration: configuration))
    }
    @MainActor static func pages() async -> [String: Bool] {
        let owner = service(), transport = ControlledPageProtocol.state
        defer { owner.session.invalidateAndCancel() }
        var storedPairsValid = true, publishedUnique = true, deferredPairsValid = true
        var deliveredArrays: [[Int]] = [], snapshots: [[Int]] = []
        let immediate = owner.$items.sink { next in
            // Combine emits before the array setter. The index must describe
            // that still-stored array, not the about-to-be-published array.
            MainActor.assumeIsolated {
                storedPairsValid = storedPairsValid && owner.auditIndex()
                publishedUnique = publishedUnique && Set(next.map(\.id)).count == next.count
                deliveredArrays.append(next.map(\.id))
            }
        }
        let delayed = owner.$items.receive(on: DispatchQueue.main).sink { next in
            MainActor.assumeIsolated {
                deferredPairsValid = deferredPairsValid && owner.auditIndex()
                var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
                snapshot.appendSections([0]); snapshot.appendItems(next.map(\.id), toSection: 0)
                snapshots.append(snapshot.itemIdentifiers)
            }
        }
        defer { immediate.cancel(); delayed.cancel() }
        owner.search(params: .init(query: "stable", perPage: 3))
        await wait("first real HTTP") { transport.count("stable:1") == 1 }
        transport.reply("stable:1", data: response([(1, "old"), (1, "latest"), (2, "two")], total: 12))
        await owner.task()?.value
        var checks = ["single-page-duplicates-preserve-first-position-and-latest-metadata": owner.items.map(\.id) == [1, 2]
            && owner.items.first?.tags == "latest" && owner.auditIndex() && owner.hasMore && owner.totalHits == 12]
        owner.loadNextPage()
        await wait("second page") { transport.count("stable:2") == 1 }
        transport.reply("stable:2", data: response([(2, "two-new"), (1, "one-new"), (2, "two-latest")], total: 12))
        await owner.task()?.value
        checks["all-duplicate-page-updates-metadata-without-premature-end-or-reordering"] = owner.items.map(\.id) == [1, 2]
            && owner.items.map(\.tags) == ["one-new", "two-latest"] && owner.page() == 2 && owner.hasMore && owner.auditIndex()
        owner.loadNextPage()
        await wait("third page") { transport.count("stable:3") == 1 }
        transport.reply("stable:3", data: response([(3, "three"), (4, "four"), (3, "three-new")], total: 12))
        await owner.task()?.value
        checks["cross-page-overlap-keeps-stable-rows-and-appends-new-identities"] = owner.items.map(\.id) == [1, 2, 3, 4]
            && owner.items[2].tags == "three-new" && owner.hasMore && owner.auditIndex()
        owner.loadNextPage()
        await wait("fourth page") { transport.count("stable:4") == 1 }
        transport.reply("stable:4", data: response([(4, "four-new"), (5, "five"), (6, "six")], total: 12))
        await owner.task()?.value
        await wait("deferred subscriber") { snapshots.last == [1, 2, 3, 4, 5, 6] }
        checks["server-page-size-not-unique-row-count-determines-the-final-page"] = owner.page() == 4 && !owner.hasMore
            && owner.totalHits == 12 && owner.items.map(\.id) == [1, 2, 3, 4, 5, 6] && owner.items[3].tags == "four-new"
        checks["published-arrays-and-native-diffable-snapshots-never-contain-duplicate-ids"] = publishedUnique
            && deliveredArrays.contains([1, 2]) && snapshots.contains([1, 2, 3, 4]) && snapshots.last == owner.items.map(\.id)
        checks["synchronous-willset-and-deferred-subscribers-see-valid-stored-array-index-pairs"] = storedPairsValid && deferredPairsValid && owner.auditIndex()
        let final = owner.items
        owner.loadNextPage()
        checks["no-request-after-the-server-terminal-page-and-no-extra-source-reset"] = owner.items == final
            && transport.count("stable:5") == 0 && owner.thumbnailCancellations == 1
        var filtered = PixabaySearchParams(query: "filtered", category: .backgrounds, perPage: 2, order: .latest)
        filtered.videoType = .animation; filtered.minWidth = 3840; filtered.minHeight = 2160
        filtered.editorsChoice = true; filtered.safeSearch = false
        owner.search(params: filtered)
        await wait("real filter request") { transport.count("filtered:1") == 1 }
        let parameters = transport.parameters("filtered:1")
        checks["official-video-filter-fields-reach-the-real-http-request-without-image-only-parameters"] = parameters["category"] == "backgrounds"
            && parameters["video_type"] == "animation" && parameters["min_width"] == "3840" && parameters["min_height"] == "2160"
            && parameters["editors_choice"] == "true" && parameters["safesearch"] == "false" && parameters["order"] == "latest"
            && parameters["colors"] == nil && parameters["orientation"] == nil
        transport.reply("filtered:1", data: response([(20, "filtered")], total: 1)); await owner.task()?.value
        owner.toolbarCategory = .backgrounds; owner.toolbarQuery = "kept filters"
        owner.searchWithCurrentContext(order: .popular)
        await wait("search keeps filters") { transport.count("kept filters:1") == 1 }
        let preserved = transport.parameters("kept filters:1")
        checks["search-and-sort-preserve-the-current-real-source-filter-fields"] = preserved["category"] == "backgrounds"
            && preserved["video_type"] == "animation" && preserved["min_width"] == "3840" && preserved["min_height"] == "2160"
            && preserved["editors_choice"] == "true" && preserved["safesearch"] == "false" && preserved["order"] == "popular"
        transport.reply("kept filters:1", data: response([(21, "preserved")], total: 1)); await owner.task()?.value
        var cleared = owner.currentParams; cleared.clearFilters(); owner.search(params: cleared)
        await wait("clear filters request") { transport.count("kept filters:1") == 2 }
        let defaultParameters = transport.parameters("kept filters:1")
        checks["clear-filters-preserves-search-order-and-restores-safe-defaults"] = defaultParameters["q"] == "kept filters"
            && defaultParameters["order"] == "popular" && defaultParameters["safesearch"] == "true"
            && ["category", "video_type", "min_width", "min_height", "editors_choice"].allSatisfy { defaultParameters[$0] == nil }
        transport.reply("kept filters:1", data: response([(22, "cleared")], total: 1)); await owner.task()?.value
        var mergeWork: [String: Int] = [:]
        owner.search(params: .init(query: "long-prefix", perPage: 128))
        await wait("long first page") { transport.count("long-prefix:1") == 1 }
        var beforeMerge = owner.mergeVisits
        transport.reply("long-prefix:1", data: response((0..<128).map { ($0, "prefix-\($0)") }, total: 512))
        await owner.task()?.value
        mergeWork["longFirst"] = owner.mergeVisits - beforeMerge
        checks["long-first-page-replaces-the-previous-search-and-builds-a-complete-index"] = owner.items.map(\.id) == Array(0..<128)
            && owner.items[127].tags == "prefix-127" && owner.auditIndex() && owner.page() == 1 && owner.hasMore
        owner.loadNextPage()
        await wait("long mixed continuation") { transport.count("long-prefix:2") == 1 }
        beforeMerge = owner.mergeVisits
        transport.reply("long-prefix:2", data: response([(127, "tail-first"), (126, "tail-reverse"), (127, "tail-latest"),
            (128, "new-first"), (129, "new-neighbor"), (128, "new-latest"), (0, "head-latest")], total: 512))
        await owner.task()?.value
        mergeWork["mixedContinuation"] = owner.mergeVisits - beforeMerge
        await wait("long mixed native snapshot") { snapshots.last == Array(0..<130) }
        checks["long-prefix-reverse-overlap-and-new-duplicates-preserve-first-position-and-last-metadata"] = owner.items.map(\.id) == Array(0..<130)
            && owner.items[0].tags == "head-latest" && owner.items[125].tags == "prefix-125"
            && owner.items[126].tags == "tail-reverse" && owner.items[127].tags == "tail-latest"
            && owner.items[128].tags == "new-latest" && owner.items[129].tags == "new-neighbor" && owner.auditIndex()
        let beforeEmpty = owner.items, publicationsBeforeEmpty = deliveredArrays.count, snapshotsBeforeEmpty = snapshots.count
        owner.loadNextPage()
        await wait("empty long continuation") { transport.count("long-prefix:3") == 1 }
        beforeMerge = owner.mergeVisits
        transport.reply("long-prefix:3", data: response([], total: 512)); await owner.task()?.value
        mergeWork["emptyContinuation"] = owner.mergeVisits - beforeMerge
        await wait("empty-page native snapshot") { snapshots.count == snapshotsBeforeEmpty + 1 }
        checks["empty-continuation-still-publishes-and-advances-the-server-page-without-losing-the-index"] = owner.items == beforeEmpty
            && deliveredArrays.count == publicationsBeforeEmpty + 1 && snapshots.last == Array(0..<130)
            && owner.page() == 3 && owner.hasMore && owner.totalHits == 512 && owner.auditIndex()
        owner.loadNextPage()
        await wait("page after empty continuation") { transport.count("long-prefix:4") == 1 }
        beforeMerge = owner.mergeVisits
        transport.reply("long-prefix:4", data: response([(129, "after-empty-update"), (130, "after-empty-new")], total: 512))
        await owner.task()?.value
        mergeWork["afterEmpty"] = owner.mergeVisits - beforeMerge
        checks["page-after-empty-reuses-current-rows-and-reaches-the-server-terminal-page"] = owner.items.map(\.id) == Array(0..<131)
            && owner.items[129].tags == "after-empty-update" && owner.items[130].tags == "after-empty-new"
            && owner.page() == 4 && !owner.hasMore && owner.auditIndex()
        owner.search(params: .init(query: "replacement", perPage: 2))
        checks["search-clears-the-long-array-and-index-before-admitting-its-new-response"] = owner.items.isEmpty && owner.auditIndex()
        await wait("replacement search") { transport.count("replacement:1") == 1 }
        beforeMerge = owner.mergeVisits
        transport.reply("replacement:1", data: response([(800, "replacement-first"), (800, "replacement-latest")], total: 2))
        await owner.task()?.value
        mergeWork["afterSearch"] = owner.mergeVisits - beforeMerge
        checks["replacement-search-keeps-only-its-own-unique-latest-row"] = owner.items.map(\.id) == [800]
            && owner.items[0].tags == "replacement-latest" && owner.auditIndex() && !owner.hasMore
        owner.clearAPIKeyAndReset()
        checks["key-reset-clears-the-array-and-index-after-long-pagination"] = owner.items.isEmpty && owner.auditIndex() && !owner.hasLoadedOnce
        owner.setAPIKeyAndSearch("fresh-key")
        await wait("new-key replacement search") { transport.count("replacement:1") == 2 }
        beforeMerge = owner.mergeVisits
        transport.reply("replacement:1", data: response([(900, "reset-first"), (901, "reset-neighbor"), (900, "reset-latest")], total: 3))
        await owner.task()?.value
        mergeWork["afterReset"] = owner.mergeVisits - beforeMerge
        await wait("post-reset native snapshot") { snapshots.last == [900, 901] }
        checks["key-reset-rebuilds-first-position-last-metadata-and-real-publisher-pairs"] = owner.items.map(\.id) == [900, 901]
            && owner.items.map(\.tags) == ["reset-latest", "reset-neighbor"] && owner.auditIndex()
            && storedPairsValid && deferredPairsValid && publishedUnique
        let workJSON = String(decoding: try! JSONSerialization.data(withJSONObject: mergeWork, options: [.sortedKeys]), as: UTF8.self)
        FileHandle.standardError.write(Data("Pagination merge work: \(workJSON)\n".utf8))
        let typedJSON = #"""
        {"totalHits":3,"futureResponse":true,"hits":[
          {"id":701,"pageURL":"https://pixabay.com/videos/701/","tags":"雪, night","duration":65,"user":"作者","futureItem":true,
           "videos":{"large":{"url":"https://media.test/large.mp4","width":3840,"height":2160,"size":4096,"thumbnail":"https://media.test/large.jpg","futureFile":true},
                     "medium":{"url":"https://media.test/medium.mp4","width":1280,"height":720,"size":2048,"thumbnail":"https://media.test/medium.jpg"},
                     "small":{"url":"https://media.test/small.mp4","width":640,"height":360,"size":1024,"thumbnail":"https://media.test/small.jpg"},
                     "tiny":{"url":"https://media.test/tiny.mp4","width":320,"height":180,"size":512,"thumbnail":"https://media.test/tiny.jpg"},"futureVariant":false}},
          {"id":702,"pageURL":"","tags":"missing","duration":0,"user":"","videos":{}},
          {"id":703,"pageURL":"","tags":"null","duration":0,"user":"","videos":{"large":null,"medium":null,"small":null,"tiny":null}}
        ]}
        """#
        owner.search(params: .init(query: "typed-models", perPage: 3))
        await wait("typed model HTTP") { transport.count("typed-models:1") == 1 }
        transport.reply("typed-models:1", data: Data(typedJSON.utf8))
        await owner.task()?.value
        let expected = PixabayVideoItem(id: 701, pageURL: "https://pixabay.com/videos/701/", tags: "雪, night", duration: 65, user: "作者",
            videos: .init(
                large: .init(url: "https://media.test/large.mp4", width: 3840, height: 2160, size: 4096, thumbnail: "https://media.test/large.jpg"),
                medium: .init(url: "https://media.test/medium.mp4", width: 1280, height: 720, size: 2048, thumbnail: "https://media.test/medium.jpg"),
                small: .init(url: "https://media.test/small.mp4", width: 640, height: 360, size: 1024, thumbnail: "https://media.test/small.jpg"),
                tiny: .init(url: "https://media.test/tiny.mp4", width: 320, height: 180, size: 512, thumbnail: "https://media.test/tiny.jpg")))
        checks["http-model-fields-and-all-four-variants-survive-with-unknown-keys-ignored"] = owner.items.first == expected
            && owner.items.map(\.id) == [701, 702, 703] && owner.totalHits == 3 && !owner.hasMore
            && !owner.isLoading && owner.errorMessage == nil && owner.auditIndex()
        let emptyVideos = PixabayVideoFiles(large: nil, medium: nil, small: nil, tiny: nil)
        checks["http-missing-and-null-optional-variants-both-remain-nil"] = owner.items.dropFirst().map(\.videos) == [emptyVideos, emptyVideos]
        let invalidResponses = [
            ("missing-item-field", typedJSON.replacingOccurrences(of: #""user":"作者","#, with: "")),
            ("wrong-item-type", typedJSON.replacingOccurrences(of: #""duration":65"#, with: #""duration":"65""#)),
            ("missing-file-field", typedJSON.replacingOccurrences(of: #""thumbnail":"https://media.test/large.jpg","#, with: "")),
            ("wrong-file-type", typedJSON.replacingOccurrences(of: #""width":3840"#, with: #""width":"3840""#))
        ]
        var schemaErrors: [String: String] = [:]
        for (label, body) in invalidResponses {
            owner.search(params: .init(query: label, perPage: 3))
            await wait(label + " HTTP") { transport.count(label + ":1") == 1 }
            transport.reply(label + ":1", data: Data(body.utf8))
            await owner.task()?.value
            schemaErrors[label] = owner.errorMessage
            checks["http-required-field-rejection-" + label] = owner.items.isEmpty && owner.auditIndex()
                && !owner.isLoading && !owner.hasMore && owner.errorMessage?.hasPrefix("网络错误：") == true
        }
        let errorsJSON = String(decoding: try! JSONSerialization.data(withJSONObject: schemaErrors, options: [.sortedKeys]), as: UTF8.self)
        FileHandle.standardError.write(Data("Pixabay schema errors: \(errorsJSON)\n".utf8))
        return checks
    }
    @MainActor static func cancellation() async -> [String: Bool] {
        let owner = service(), transport = ControlledPageProtocol.state
        defer { owner.session.invalidateAndCancel() }
        var checks: [String: Bool] = [:]
        for kind in ["success", "http-failure", "transport-failure", "cancellation"] {
            let old = "old-" + kind, new = "new-" + kind
            owner.search(params: .init(query: old, perPage: 2))
            await wait("old started " + kind) { transport.count(old + ":1") == 1 }
            let oldTask = owner.task()
            // Queue the real URLSession outcome while still on MainActor, then
            // synchronously admit a new search before that task can resume.
            if kind == "success" { transport.reply(old + ":1", data: response([(90, "stale")], total: 1)) }
            if kind == "http-failure" { transport.reply(old + ":1", data: Data(), status: 429) }
            if kind == "transport-failure" { transport.fail(old + ":1") }
            owner.search(params: .init(query: new, perPage: 2))
            await wait("new started " + kind) { transport.count(new + ":1") == 1 }
            await oldTask?.value
            checks["old-" + kind + "-cannot-clear-new-loading-or-publish-old-results-errors"] = owner.isLoading
                && owner.items.isEmpty && owner.errorMessage == nil && owner.currentParams.query == new && owner.auditIndex()
            if kind == "cancellation" {
                await wait("URLSession stopLoading") { transport.stopped(old + ":1") }
                checks["cancelled-http-request-reaches-the-real-urlprotocol-stop-boundary"] = transport.stopped(old + ":1")
            }
            transport.reply(new + ":1", data: response([(7, "current-" + kind)], total: 1))
            await owner.task()?.value
            checks["new-" + kind + "-settles-own-loading-and-unique-index"] = !owner.isLoading
                && owner.items.map(\.id) == [7] && owner.items.first?.tags == "current-" + kind && owner.auditIndex()
        }
        owner.search(params: .init(query: "before-empty-key", perPage: 2))
        await wait("old request before empty-key rejection") { transport.count("before-empty-key:1") == 1 }
        let rejectedTask = owner.task()
        owner.apiKey = ""
        owner.search(params: .init(query: "empty-key", perPage: 2))
        let rejectedSettledSynchronously = !owner.isLoading && owner.errorMessage == "请先填写 Pixabay API Key"
        await rejectedTask?.value
        checks["empty-key-admission-settles-loading-without-waiting-for-the-old-cancelled-request"] = rejectedSettledSynchronously
            && !owner.isLoading && owner.items.isEmpty && owner.auditIndex() && owner.currentParams.query == "empty-key"
            && owner.errorMessage == "请先填写 Pixabay API Key" && transport.count("empty-key:1") == 0
        owner.apiKey = "fixture-key"
        owner.search(params: .init(query: "reset", perPage: 2))
        await wait("reset started") { transport.count("reset:1") == 1 }
        let resetTask = owner.task()
        owner.clearAPIKeyAndReset()
        await resetTask?.value
        checks["clear-api-reset-keeps-empty-publication-and-cancelled-task-does-not-revive-loading"] = owner.items.isEmpty
            && owner.auditIndex() && !owner.isLoading && owner.errorMessage == nil && !owner.hasLoadedOnce && owner.apiKey.isEmpty
        owner.apiKey = "fixture-key"
        var kept = PixabaySearchParams(query: "key-replacement", category: .nature, perPage: 2, order: .latest)
        kept.minWidth = 1920; kept.editorsChoice = true
        // The real filter apply stores this toolbar category before search;
        // a later order action consumes it through searchWithCurrentContext.
        owner.toolbarCategory = kept.category
        owner.search(params: kept)
        await wait("old key request") { transport.count("key-replacement:1") == 1 }
        let oldKeyTask = owner.task()
        owner.toolbarQuery = "unsubmitted old-key draft"
        transport.reply("key-replacement:1", data: Data(), status: 403)
        owner.setAPIKeyAndSearch(" replacement-key ")
        await wait("replacement key request") { transport.count("key-replacement:1") == 2 }
        await oldKeyTask?.value
        let replacement = transport.parameters("key-replacement:1")
        checks["replacing-key-cancels-old-outcome-and-preserves-the-current-query"] = owner.isLoading
            && owner.errorMessage == nil && owner.items.isEmpty && owner.currentParams == kept && owner.toolbarQuery == kept.query
            && replacement["key"] == "replacement-key" && replacement["q"] == "key-replacement"
            && replacement["order"] == "latest" && replacement["category"] == "nature"
            && replacement["min_width"] == "1920" && replacement["editors_choice"] == "true"
        owner.searchWithCurrentContext(order: .popular)
        await wait("new-key filter request") { transport.count("key-replacement:1") == 3 }
        var filtered = kept; filtered.order = .popular
        let filterParameters = transport.parameters("key-replacement:1")
        checks["filter-after-key-replacement-cannot-submit-an-old-key-toolbar-draft"] = owner.currentParams == filtered
            && filterParameters["q"] == kept.query && owner.toolbarQuery == kept.query
            && filterParameters["category"] == "nature" && filterParameters["order"] == "popular"
            && filterParameters["min_width"] == "1920" && filterParameters["editors_choice"] == "true"
        owner.toolbarQuery = "new-key draft remains editable"
        owner.setAPIKeyAndSearch("replacement-key")
        await Task.yield()
        checks["saving-the-same-key-does-not-replace-the-active-request"] = transport.count("key-replacement:1") == 3
            && owner.task()?.isCancelled == false && owner.isLoading && owner.currentParams == filtered
            && owner.toolbarQuery == "new-key draft remains editable"
        transport.reply("key-replacement:1", data: response([(8, "new key result")], total: 1))
        await owner.task()?.value
        checks["replacement-key-publishes-only-its-own-result"] = owner.items.map(\.id) == [8]
            && owner.errorMessage == nil && !owner.isLoading && owner.auditIndex()
        return checks
    }
    @MainActor static func main() async {
        let checks = CommandLine.arguments.last == "cancellation" ? await cancellation() : await pages()
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
