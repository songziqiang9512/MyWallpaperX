import Combine
import Foundation

/// Responses deliberately ignore task cancellation. The real Session must
/// reject an obsolete response even when a transport completes after cancel.
@MainActor final class ControlledBrowseClient {
    private(set) var authorInvalidations = 0
    func invalidateAuthorSnapshot() async { authorInvalidations += 1 }
    struct Request {
        let query: OnlineImageBrowserSession.Query
        let page: OnlineImagePageRequest
        let scope: String
    }
    var scope = "pixiv-anonymous"
    private(set) var requests: [Request] = []
    private(set) var completed = Set<Int>()
    private var pending: [Int: CheckedContinuation<OnlineImagePage, Error>] = [:]

    func page(query: WallhavenQuery, request: OnlineImagePageRequest) async throws -> OnlineImagePage {
        try await fetch(.wallhaven(query), page: request)
    }
    func page(query: PixivQuery, request: OnlineImagePageRequest) async throws -> OnlineImagePage {
        try await fetch(.pixiv(query), page: request)
    }
    private func fetch(_ query: OnlineImageBrowserSession.Query, page: OnlineImagePageRequest) async throws -> OnlineImagePage {
        let index = requests.count
        requests.append(.init(query: query, page: page, scope: scope))
        defer { completed.insert(index) }
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func respond(_ index: Int, _ result: Result<OnlineImagePage, Error>) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("Response must target one outstanding request")
        }
        continuation.resume(with: result)
    }
}

/// Only the Session's acquisition leaf is replaced; there is no second cache,
/// query owner, cancellation policy or local library projection in this stub.
@MainActor final class OnlineImageLibrary {
    let client = ControlledBrowseClient()
    var pixivScope = "pixiv-anonymous"
    var wallhavenScope = "wallhaven-key-0"
    var pixivScopeAfterPreparation: String?
    var wallhavenScopeAfterPreparation: String?
    func requestScope(_ source: OnlineImageSource) -> String { source == .pixiv ? pixivScope : wallhavenScope }
    func prepareWallhaven() async -> ControlledBrowseClient {
        if let wallhavenScopeAfterPreparation {
            wallhavenScope = wallhavenScopeAfterPreparation; self.wallhavenScopeAfterPreparation = nil
        }
        client.scope = wallhavenScope
        return client
    }
    func preparePixiv() async -> ControlledBrowseClient {
        if let pixivScopeAfterPreparation {
            pixivScope = pixivScopeAfterPreparation; self.pixivScopeAfterPreparation = nil
        }
        client.scope = pixivScope
        return client
    }
}

private struct BrowseFixtureFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw BrowseFixtureFailure(message: "Timed out: " + message)
}

@MainActor private func request(_ library: OnlineImageLibrary, count: Int) async throws -> Int {
    try await waitFor("request \(count)") { library.client.requests.count >= count }
    return count - 1
}

@MainActor private func respond(_ library: OnlineImageLibrary, index: Int,
                               result: Result<OnlineImagePage, Error>) async throws {
    library.client.respond(index, result)
    try await waitFor("delivery \(index)") { library.client.completed.contains(index) }
    // The controlled leaf has returned; let the real Session consume its value.
    await Task.yield()
}

@MainActor private func artwork(_ source: OnlineImageSource, _ id: String, _ title: String? = nil) -> OnlineImageArtwork {
    .init(source: source, artworkID: id, title: title ?? id,
          sourceURL: URL(string: "https://example.invalid/artwork/" + id)!, kind: .image)
}

@MainActor private func cacheAndPagination(_ checks: inout [String: Bool], source: OnlineImageSource) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: source, library: library)
    let prefix = source.rawValue + ":"
    let second = OnlineImagePageRequest(page: 2, seed: "fixed-seed", date: "20261025", offset: 24)
    let third = OnlineImagePageRequest(page: 3, seed: "fixed-seed", date: "20261025", offset: 48)
    session.enter()
    let initial = try await request(library, count: 1)
    session.enter(); session.enter(); await Task.yield()
    checks[prefix + "repeated-entry-coalesces-the-inflight-initial-page"] = library.client.requests.count == 1
    let first = [artwork(source, "11", "first"), artwork(source, "11", "duplicate"), artwork(source, "12")]
    try await respond(library, index: initial, result: .success(.init(items: first, next: second, total: 72)))
    try await waitFor("initial page") { !session.state.isLoading }
    checks[prefix + "initial-page-deduplicates-in-first-occurrence-order"] = session.state.items.map(\.artworkID) == ["11", "12"]
        && session.state.items.first?.title == "first"
    session.leave(); session.enter(); session.enter(); session.setQuery(session.state.query)
    await Task.yield()
    checks[prefix + "same-query-reentry-within-five-minutes-does-not-request"] = library.client.requests.count == 1
        && session.state.items.map(\.artworkID) == ["11", "12"] && !session.state.isLoading
    session.loadMore()
    let continuation = try await request(library, count: 2)
    checks[prefix + "pagination-preserves-source-continuation-facts"] = library.client.requests[continuation].page == second
    try await respond(library, index: continuation, result: .success(.init(items: [
        artwork(source, "12", "updated-12"), artwork(source, "13", "old-13"),
        artwork(source, "13", "updated-13"), artwork(source, "11", "updated-11"), artwork(source, "14")
    ], next: third, total: 72)))
    try await waitFor("second page") { !session.state.isLoading }
    checks[prefix + "append-deduplicates-updates-existing-values-and-keeps-first-position"] = session.state.items.map(\.artworkID) == ["11", "12", "13", "14"]
        && session.state.items.map(\.title) == ["updated-11", "updated-12", "updated-13", "14"]

    session.fixtureExpireCache(); session.enter()
    let background = try await request(library, count: 3)
    checks[prefix + "stale-reentry-keeps-all-cached-pages-visible-before-response"] = session.state.items.map(\.artworkID) == ["11", "12", "13", "14"]
        && session.state.next == third && library.client.requests[background].page == .init()
    let sameIDs = [artwork(source, "11", "fresh-11"), artwork(source, "11", "fresh-duplicate"), artwork(source, "12", "fresh-12")]
    try await respond(library, index: background, result: .success(.init(items: sameIDs, next: second, total: 72)))
    try await waitFor("unchanged background page") { !session.state.isLoading }
    checks[prefix + "background-home-refresh-keeps-multipage-order-and-continuation"] = session.state.items.map(\.artworkID) == ["11", "12", "13", "14"]
        && session.state.next == third && session.state.items[1].title == "fresh-12"
    checks[prefix + "same-home-identities-do-not-create-new-content-notice"] = session.state.notice == nil
    session.fixtureExpireCache(); session.enter()
    let changed = try await request(library, count: 4)
    try await respond(library, index: changed, result: .success(.init(items: [
        artwork(source, "15"), artwork(source, "11", "changed-11"), artwork(source, "12")
    ], next: second, total: 73)))
    try await waitFor("changed background page") { !session.state.isLoading }
    checks[prefix + "changed-home-creates-notice-without-inserting-or-reordering-cached-rows"] = session.state.notice != nil
        && session.state.items.map(\.artworkID) == ["11", "12", "13", "14"] && session.state.next == third
    session.leave()
}

@MainActor private func queryAndCancellation(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: .wallhaven, library: library)
    session.setSearch("old query")
    let old = try await request(library, count: 1)
    session.setSearch("  new query  ")
    let current = try await request(library, count: 2)
    checks["query-change-resets-items-and-trims-search-before-new-request"] = session.state.query.search == "new query"
        && library.client.requests[current].query.search == "new query" && session.state.items.isEmpty
    try await respond(library, index: old, result: .success(.init(items: [artwork(.wallhaven, "21")], next: nil)))
    checks["late-old-query-cannot-publish-or-clear-current-loading"] = session.state.items.isEmpty
        && session.state.query.search == "new query" && session.state.isLoading && session.state.error == nil
    let continuation = OnlineImagePageRequest(page: 2, seed: "query-seed")
    try await respond(library, index: current, result: .success(.init(items: [artwork(.wallhaven, "22")], next: continuation)))
    try await waitFor("new query") { !session.state.isLoading }
    session.loadMore()
    let oldMore = try await request(library, count: 3)
    session.setSearch("third query")
    let third = try await request(library, count: 4)
    try await respond(library, index: oldMore, result: .failure(CancellationError()))
    checks["cancelled-old-page-cannot-clear-new-page-loading-or-publish-an-error"] = session.state.query.search == "third query"
        && session.state.isLoading && session.state.error == nil && session.state.items.isEmpty
    try await respond(library, index: third, result: .success(.init(items: [artwork(.wallhaven, "23")], next: nil)))
    try await waitFor("third query") { !session.state.isLoading }
    checks["only-current-query-result-is-published"] = session.state.items.map(\.artworkID) == ["23"]
    session.leave()
}

@MainActor private func refreshFailure(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: .wallhaven, library: library)
    let next = OnlineImagePageRequest(page: 2, seed: "refresh-seed")
    session.enter()
    let first = try await request(library, count: 1)
    try await respond(library, index: first, result: .success(.init(items: [artwork(.wallhaven, "31")], next: next)))
    try await waitFor("refresh initial") { !session.state.isLoading }
    session.loadMore()
    let more = try await request(library, count: 2)
    let third = OnlineImagePageRequest(page: 3, seed: "refresh-seed")
    try await respond(library, index: more, result: .success(.init(items: [artwork(.wallhaven, "32")], next: third)))
    try await waitFor("refresh second page") { !session.state.isLoading }
    let old = session.state
    session.refresh()
    let failed = try await request(library, count: 3)
    checks["explicit-refresh-displays-old-pages-until-success"] = session.state.items == old.items
        && session.state.next == old.next && session.state.isLoading && session.state.refreshToken != old.refreshToken
    try await respond(library, index: failed, result: .failure(OnlineImageError.message("controlled refresh failure")))
    try await waitFor("refresh failure") { !session.state.isLoading }
    checks["failed-explicit-refresh-retains-old-pages-and-continuation"] = session.state.items == old.items
        && session.state.next == old.next && session.state.hasLoaded && session.state.error == "controlled refresh failure"
    session.refresh()
    let retry = try await request(library, count: 4)
    checks["failed-explicit-refresh-can-be-retried-at-home-page"] = library.client.requests[retry].page == .init()
        && session.state.error == nil && session.state.items == old.items
    try await respond(library, index: retry, result: .success(.init(items: [artwork(.wallhaven, "33")], next: next)))
    try await waitFor("refresh retry") { !session.state.isLoading }
    checks["successful-explicit-refresh-replaces-old-pages-once"] = session.state.items.map(\.artworkID) == ["33"]
        && session.state.next == next && session.state.error == nil
    session.leave()
}

@MainActor private func emptyFilteredPages(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: .pixiv, library: library)
    let query = PixivQuery(search: "filtered", ranking: .weekly, workType: .manga)
    session.setQuery(.pixiv(query))
    let first = try await request(library, count: 1)
    let next = OnlineImagePageRequest(page: 2, date: "20261025", offset: 12)
    try await respond(library, index: first, result: .success(.init(items: [], next: next, total: 25)))
    try await waitFor("empty filtered home") { !session.state.isLoading }
    checks["filtered-empty-home-keeps-server-continuation"] = session.state.hasLoaded && session.state.items.isEmpty && session.state.next == next
    session.loadMore()
    let second = try await request(library, count: 2)
    let third = OnlineImagePageRequest(page: 3, date: "20261025", offset: 24)
    try await respond(library, index: second, result: .success(.init(items: [], next: third, total: 25)))
    try await waitFor("second empty filtered page") { !session.state.isLoading }
    session.loadMore()
    let last = try await request(library, count: 3)
    checks["consecutive-filtered-empty-pages-can-continue-with-exact-query-and-offset"] = library.client.requests[second].page == next
        && library.client.requests[last].page == third && library.client.requests[last].query == .pixiv(query)
    try await respond(library, index: last, result: .success(.init(items: [artwork(.pixiv, "41")], next: nil, total: 25)))
    try await waitFor("filtered final page") { !session.state.isLoading }
    checks["filtered-empty-pages-do-not-hide-later-visible-work"] = session.state.items.map(\.artworkID) == ["41"] && session.state.next == nil
    session.leave()
}

@MainActor private func authorReturn(_ checks: inout [String: Bool], source: OnlineImageSource) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: source, library: library)
    let prefix = source.rawValue + ":"
    var captures = 0, restores = 0
    session.onCaptureReturnScroll = { captures += 1 }
    session.onRestoreReturnScroll = { restores += 1 }
    let query: OnlineImageBrowserSession.Query = source == .pixiv
        ? .pixiv(PixivQuery(search: "origin search", ranking: .monthly, workType: .illustrations))
        : .wallhaven(WallhavenQuery(search: "origin search", sorting: .favorites, purity: "110", ratios: ["16x9"]))
    let second = OnlineImagePageRequest(page: 2, date: "20261024", offset: 24)
    session.setQuery(query)
    let first = try await request(library, count: 1)
    try await respond(library, index: first, result: .success(.init(items: [artwork(source, "51")], next: second, total: 100)))
    try await waitFor("origin first page") { !session.state.isLoading }
    session.loadMore()
    let more = try await request(library, count: 2)
    let third = OnlineImagePageRequest(page: 3, date: "20261024", offset: 48)
    try await respond(library, index: more, result: .success(.init(items: [artwork(source, "52")], next: third, total: 100)))
    try await waitFor("origin second page") { !session.state.isLoading }
    let origin = session.state
    session.openAuthor(.init(source: source == .pixiv ? .wallhaven : .pixiv, id: "77", name: "Wrong source"))
    checks[prefix + "author-from-another-source-cannot-change-the-query"] = session.state.query == origin.query && !session.hasReturnContext
    let authorIdentity = OnlineImageAuthor(source: source, id: "77", name: "作者名字")
    session.openAuthor(authorIdentity)
    let author = try await request(library, count: 3)
    let authorQuery: OnlineImageBrowserSession.Query
    switch query {
    case .pixiv(var value): value.search = ""; value.authorID = "77"; authorQuery = .pixiv(value)
    case .wallhaven(var value): value.search = ""; value.authorUsername = "77"; authorQuery = .wallhaven(value)
    }
    checks[prefix + "author-entry-captures-one-origin-and-clears-only-source-search"] = captures == 1 && session.hasReturnContext
        && library.client.requests[author].query == authorQuery && library.client.authorInvalidations == 0
        && session.state.author == authorIdentity && session.state.query.authorIdentifier == authorIdentity.id
    try await respond(library, index: author, result: .success(.init(items: [artwork(source, "53")], next: .init(page: 2))))
    try await waitFor("author page") { !session.state.isLoading }
    let filteredQuery: OnlineImageBrowserSession.Query
    switch authorQuery {
    case .pixiv(var value): value.workType = .manga; value.ai = .hide; filteredQuery = .pixiv(value)
    case .wallhaven(var value): value.categories = "010"; value.order = .asc; filteredQuery = .wallhaven(value)
    }
    session.setQuery(filteredQuery)
    let filtered = try await request(library, count: 4)
    checks[prefix + "author-filter-preserves-label-snapshot-and-original-return-context"] = session.hasReturnContext && captures == 1
        && library.client.requests[filtered].query == filteredQuery && library.client.authorInvalidations == 0
        && session.state.author == authorIdentity
    try await respond(library, index: filtered, result: .success(.init(items: [artwork(source, "54")], next: nil)))
    try await waitFor("author filtered page") { !session.state.isLoading }
    session.openAuthor(.init(source: source, id: "77"))
    await Task.yield()
    checks[prefix + "same-author-entry-reuses-the-current-context-and-known-name"] = library.client.requests.count == 4
        && session.state.author == authorIdentity && session.state.query == filteredQuery && captures == 1
    session.openAuthor(.init(source: source, id: "88", name: "另一位作者"))
    let laterAuthor = try await request(library, count: 5)
    session.goBack()
    checks[prefix + "author-back-restores-original-query-pages-and-continuation"] = session.state.query == origin.query
        && session.state.items == origin.items && session.state.next == origin.next && session.state.firstPageIDs == origin.firstPageIDs
        && session.state.total == origin.total && session.state.checkedAt == origin.checkedAt && session.state.refreshToken == origin.refreshToken
        && !session.hasReturnContext && captures == 1 && restores == 1 && !session.state.isLoading && session.state.author == nil
    try await respond(library, index: laterAuthor, result: .success(.init(items: [artwork(source, "55")], next: nil)))
    checks[prefix + "author-response-after-back-cannot-overwrite-restored-origin"] = session.state.query == origin.query
        && session.state.items == origin.items && session.state.next == origin.next && session.state.error == nil
    session.enter(); await Task.yield()
    checks[prefix + "fresh-restored-origin-reentry-does-not-refetch"] = library.client.requests.count == 5
    session.openAuthor(authorIdentity)
    let revisit = try await request(library, count: 6)
    try await respond(library, index: revisit, result: .success(.init(items: [artwork(source, "56")], next: nil)))
    try await waitFor("author revisited") { !session.state.isLoading }
    session.setSearch(" new search ")
    let search = try await request(library, count: 7)
    checks[prefix + "editing-search-exits-author-mode-and-clears-its-return-context"] = session.state.query.authorIdentifier == nil
        && session.state.query.search == "new search" && session.state.author == nil && !session.hasReturnContext
        && library.client.requests[search].query == session.state.query
    try await respond(library, index: search, result: .success(.init(items: [], next: nil)))
    try await waitFor("new search") { !session.state.isLoading }
    session.leave()
}

@MainActor private func authorReturnToUnloadedOrigin(_ checks: inout [String: Bool], source: OnlineImageSource) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: source, library: library)
    session.setSearch("origin still loading")
    let origin = try await request(library, count: 1)
    let query = session.state.query
    session.openAuthor(.init(source: source, id: "77", name: "作者"))
    let author = try await request(library, count: 2)
    session.goBack()
    let restored = try await request(library, count: 3)
    checks[source.rawValue + ":author-back-restarts-an-unloaded-origin"] = session.state.query == query
        && library.client.requests[restored].query == query && session.state.isLoading && !session.state.hasLoaded
        && !session.hasReturnContext && session.state.author == nil
    try await respond(library, index: origin, result: .success(.init(items: [artwork(source, "old-origin")], next: nil)))
    try await respond(library, index: author, result: .success(.init(items: [artwork(source, "old-author")], next: nil)))
    checks[source.rawValue + ":late-origin-and-author-do-not-overwrite-restarted-origin"] = session.state.items.isEmpty && session.state.isLoading
    try await respond(library, index: restored, result: .success(.init(items: [artwork(source, "current-origin")], next: nil)))
    try await waitFor("restored unloaded origin") { !session.state.isLoading }
    checks[source.rawValue + ":unloaded-origin-eventually-publishes-current-request"] = session.state.hasLoaded
        && session.state.items.map(\.artworkID) == ["current-origin"]
    session.leave()
}

@MainActor private func scopeChanges(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary()
    library.pixivScope = "account-a"
    let session = OnlineImageBrowserSession(source: .pixiv, library: library)
    session.enter()
    let old = try await request(library, count: 1)
    library.pixivScope = "account-b"; session.enter()
    let current = try await request(library, count: 2)
    checks["scope-change-on-enter-invalidates-old-cache-and-starts-current-scope"] = library.client.requests[old].scope == "account-a"
        && library.client.requests[current].scope == "account-b" && session.state.items.isEmpty && !session.state.hasLoaded
    try await respond(library, index: old, result: .success(.init(items: [artwork(.pixiv, "61")], next: nil)))
    checks["old-scope-late-response-cannot-publish-or-clear-current-loading"] = session.state.items.isEmpty && session.state.isLoading
    try await respond(library, index: current, result: .success(.init(items: [artwork(.pixiv, "62")], next: nil)))
    try await waitFor("current scope") { !session.state.isLoading }
    session.openAuthor(.init(source: .pixiv, id: "77", name: "作者"))
    let author = try await request(library, count: 3)
    library.pixivScope = "account-c"; session.resetScope()
    checks["explicit-scope-reset-clears-author-origin-and-visible-account-state"] = !session.hasReturnContext
        && session.state.items.isEmpty && session.state.next == nil && !session.state.hasLoaded && !session.state.isLoading
    checks["scope-reset-preserves-only-the-explicit-author-query-label"] = session.state.author == .init(source: .pixiv, id: "77", name: "作者")
        && session.state.query.authorIdentifier == "77"
    session.enter()
    let latest = try await request(library, count: 4)
    try await respond(library, index: author, result: .failure(OnlineImageError.message("obsolete account failure")))
    checks["old-scope-error-cannot-clear-new-scope-loading"] = session.state.isLoading && session.state.error == nil
    try await respond(library, index: latest, result: .success(.init(items: [artwork(.pixiv, "63")], next: nil)))
    try await waitFor("latest scope") { !session.state.isLoading }
    checks["only-current-scope-work-remains-visible"] = session.state.items.map(\.artworkID) == ["63"]
    session.leave()
}

@MainActor private func preparedCookieScope(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: .pixiv, library: library)
    library.pixivScopeAfterPreparation = "restored-cookie-scope"
    session.enter()
    let first = try await request(library, count: 1)
    session.enter(); await Task.yield()
    checks["prepared-cookie-scope-does-not-cancel-an-already-current-held-home-page"] = library.client.requests.count == 1
        && session.state.isLoading
    let next = OnlineImagePageRequest(page: 2, date: "20261025", offset: 24)
    try await respond(library, index: first, result: .success(.init(items: [artwork(.pixiv, "81")], next: next)))
    try await waitFor("prepared cookie home") { !session.state.isLoading }
    session.loadMore()
    let second = try await request(library, count: 2)
    let third = OnlineImagePageRequest(page: 3, date: "20261025", offset: 48)
    try await respond(library, index: second, result: .success(.init(items: [artwork(.pixiv, "82")], next: third)))
    try await waitFor("prepared cookie continuation") { !session.state.isLoading }
    checks["first-cookie-preparation-binds-the-actual-restored-scope"] = library.client.requests[first].scope == "restored-cookie-scope"
        && library.client.requests[second].page == next && session.state.items.map(\.artworkID) == ["81", "82"]
    session.leave(); session.enter(); await Task.yield()
    checks["first-cookie-restoration-keeps-five-minute-multipage-cache-without-refetch"] = library.client.requests.count == 2
        && session.state.items.map(\.artworkID) == ["81", "82"] && session.state.next == third && !session.state.isLoading
    session.leave()
}

@MainActor private func sourceScopeConsumption(_ checks: inout [String: Bool], source: OnlineImageSource) async throws {
    let library = OnlineImageLibrary()
    func changeScope(_ value: String) {
        if source == .pixiv { library.pixivScope = value } else { library.wallhavenScope = value }
    }
    func changeScopeDuringPreparation(_ value: String) {
        if source == .pixiv { library.pixivScopeAfterPreparation = value } else { library.wallhavenScopeAfterPreparation = value }
    }
    let prefix = source.rawValue + ":"
    changeScope("scope-a")
    let session = OnlineImageBrowserSession(source: source, library: library)
    session.enter()
    let first = try await request(library, count: 1)
    let oldNext = OnlineImagePageRequest(page: 2, seed: "old-scope-seed", date: "20261024", offset: 24)
    try await respond(library, index: first, result: .success(.init(items: [artwork(source, "91")], next: oldNext)))
    try await waitFor("scope a home") { !session.state.isLoading }
    session.loadMore()
    let staleSuccess = try await request(library, count: 2)
    changeScope("scope-b") // No App callback, enter, or explicit reset accompanies this change.
    try await respond(library, index: staleSuccess, result: .success(.init(items: [artwork(source, "92")], next: .init(page: 3))))
    checks[prefix + "late-old-scope-success-revokes-cache-and-finishes-loading-without-ui-reset"] = !session.state.isLoading
        && !session.state.hasLoaded && session.state.items.isEmpty && session.state.next == nil && session.state.error == nil
        && library.client.requests.count == 2
    session.enter()
    let current = try await request(library, count: 3)
    let nextB = OnlineImagePageRequest(page: 2, seed: "scope-b-seed", offset: 24)
    checks[prefix + "scope-revocation-can-restart-at-home-without-hidden-network-loop"] = library.client.requests[current].page == .init()
        && library.client.requests[current].scope == "scope-b"
    try await respond(library, index: current, result: .success(.init(items: [artwork(source, "93")], next: nextB)))
    try await waitFor("scope b home") { !session.state.isLoading }
    session.loadMore()
    let staleFailure = try await request(library, count: 4)
    changeScope("scope-c")
    try await respond(library, index: staleFailure, result: .failure(OnlineImageError.message("old scope failure")))
    checks[prefix + "late-old-scope-failure-does-not-leave-loading-or-account-error"] = !session.state.isLoading
        && session.state.items.isEmpty && session.state.error == nil && !session.state.hasLoaded && library.client.requests.count == 4
    session.enter()
    let nextHome = try await request(library, count: 5)
    let nextC = OnlineImagePageRequest(page: 2, seed: "scope-c-seed", offset: 24)
    try await respond(library, index: nextHome, result: .success(.init(items: [artwork(source, "94")], next: nextC)))
    try await waitFor("scope c home") { !session.state.isLoading }
    changeScopeDuringPreparation("scope-d")
    session.loadMore()
    let rebuilt = try await request(library, count: 6)
    checks[prefix + "scope-change-during-load-more-preparation-replaces-old-continuation-with-home"] = library.client.requests[rebuilt].page == .init()
        && library.client.requests[rebuilt].scope == "scope-d" && session.state.isLoading && session.state.items.isEmpty && session.state.next == nil
    let nextD = OnlineImagePageRequest(page: 2, seed: "scope-d-seed", offset: 24)
    try await respond(library, index: rebuilt, result: .success(.init(items: [artwork(source, "95")], next: nextD)))
    try await waitFor("scope d rebuilt home") { !session.state.isLoading }
    session.leave(); session.enter(); await Task.yield()
    checks[prefix + "rebuilt-scope-home-publishes-alone-and-retains-fresh-cache"] = session.state.items.map(\.artworkID) == ["95"]
        && session.state.next == nextD && library.client.requests.count == 6 && !session.state.isLoading
    session.openAuthor(.init(source: source, id: "77", name: "作者"))
    let author = try await request(library, count: 7)
    try await respond(library, index: author, result: .success(.init(items: [artwork(source, "96")], next: nil)))
    try await waitFor("scope d author") { !session.state.isLoading }
    changeScope("scope-e"); session.goBack()
    checks[prefix + "author-back-cannot-restore-previous-account-cache-without-ui-reset"] = !session.hasReturnContext
        && session.state.items.isEmpty && !session.state.isLoading && library.client.requests.count == 7
    session.leave()
}

@MainActor private func authorBackgroundContinuation(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: .pixiv, library: library)
    session.openAuthor(.init(source: .pixiv, id: "77", name: "作者"))
    let first = try await request(library, count: 1)
    let next = OnlineImagePageRequest(page: 2, offset: 24)
    try await respond(library, index: first, result: .success(.init(items: [artwork(.pixiv, "101")], next: next)))
    try await waitFor("author initial snapshot") { !session.state.isLoading }
    session.fixtureExpireCache(); session.enter()
    let background = try await request(library, count: 2)
    checks["author-background-check-does-not-replace-id-snapshot-under-saved-offset"] = library.client.authorInvalidations == 0
    try await respond(library, index: background, result: .success(.init(items: [artwork(.pixiv, "101")], next: next)))
    try await waitFor("author background snapshot") { !session.state.isLoading }
    session.loadMore()
    let more = try await request(library, count: 3)
    checks["author-background-check-keeps-exact-continuation-and-snapshot"] = library.client.requests[more].page == next
        && library.client.authorInvalidations == 0
    try await respond(library, index: more, result: .success(.init(items: [artwork(.pixiv, "102")], next: nil)))
    try await waitFor("author continuation") { !session.state.isLoading }
    session.refresh()
    let refresh = try await request(library, count: 4)
    checks["author-explicit-refresh-starts-new-id-snapshot-at-first-page"] = library.client.authorInvalidations == 1
        && library.client.requests[refresh].page == .init()
    try await respond(library, index: refresh, result: .success(.init(items: [artwork(.pixiv, "103")], next: nil)))
    try await waitFor("author explicit refresh") { !session.state.isLoading }
    session.leave()
}

@MainActor private func authorEmptyContinuation(_ checks: inout [String: Bool], source: OnlineImageSource) async throws {
    let library = OnlineImageLibrary(), session = OnlineImageBrowserSession(source: source, library: library)
    session.openAuthor(.init(source: source, id: "77", name: "作者"))
    let initial = try await request(library, count: 1)
    let second = OnlineImagePageRequest(page: 2), third = OnlineImagePageRequest(page: 3)
    try await respond(library, index: initial, result: .success(.init(items: [artwork(source, "103")], next: second)))
    try await waitFor("author initial") { !session.state.isLoading }
    session.loadMore(); let empty = try await request(library, count: 2)
    try await respond(library, index: empty, result: .success(.init(items: [], next: third)))
    try await waitFor("author empty continuation") { !session.state.isLoading }
    checks[source.rawValue + "-author-empty-page-reports-status-without-dropping-items-or-next"] =
        session.state.notice == "暂未获取到更多内容" && session.state.next == third
        && session.state.items.map(\.artworkID) == ["103"]
    session.loadMore(); let continued = try await request(library, count: 3)
    try await respond(library, index: continued, result: .success(.init(items: [artwork(source, "104")], next: nil)))
    try await waitFor("author resumes after empty page") { !session.state.isLoading }
    checks[source.rawValue + "-author-later-page-clears-empty-notice-and-retains-order"] =
        session.state.notice == nil && session.state.next == nil && session.state.items.map(\.artworkID) == ["103", "104"]
    session.leave()
}

@main private struct OnlineImageBrowseHarness {
    @MainActor static func main() async throws {
        var checks: [String: Bool] = [:]
        try await cacheAndPagination(&checks, source: .wallhaven)
        try await cacheAndPagination(&checks, source: .pixiv)
        try await queryAndCancellation(&checks)
        try await refreshFailure(&checks)
        try await emptyFilteredPages(&checks)
        try await authorReturn(&checks, source: .wallhaven)
        try await authorReturn(&checks, source: .pixiv)
        try await authorReturnToUnloadedOrigin(&checks, source: .wallhaven)
        try await authorReturnToUnloadedOrigin(&checks, source: .pixiv)
        try await authorBackgroundContinuation(&checks)
        try await authorEmptyContinuation(&checks, source: .wallhaven)
        try await authorEmptyContinuation(&checks, source: .pixiv)
        try await scopeChanges(&checks)
        try await preparedCookieScope(&checks)
        try await sourceScopeConsumption(&checks, source: .wallhaven)
        try await sourceScopeConsumption(&checks, source: .pixiv)
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
