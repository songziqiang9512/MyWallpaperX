import Combine
import Foundation

/// Query, continuation and one author return context. Geometry/selection stay with the Shell grid.
@MainActor final class OnlineImageBrowserSession: ObservableObject {
    enum Query: Hashable {
        case wallhaven(WallhavenQuery), pixiv(PixivQuery)
        var search: String {
            switch self { case .wallhaven(let q): q.search; case .pixiv(let q): q.search }
        }
    }
    struct State {
        var query: Query
        var items: [OnlineImageArtwork] = []
        var firstPageIDs: [String] = []
        var next: OnlineImagePageRequest?
        var total: Int?
        var notice: String?
        var error: String?
        var isLoading = false
        var hasLoaded = false
        var checkedAt: Date?
        var refreshToken = UUID()
    }
    let source: OnlineImageSource
    @Published private(set) var state: State
    @Published private(set) var hasReturnContext = false
    private let library: OnlineImageLibrary
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var returnContext: State?
    private var scope: String
    var onResetScroll: (() -> Void)?
    var onCaptureReturnScroll: (() -> Void)?
    var onRestoreReturnScroll: (() -> Void)?

    init(source: OnlineImageSource, library: OnlineImageLibrary) {
        self.source = source; self.library = library; scope = library.requestScope(source)
        state = .init(query: source == .wallhaven ? .wallhaven(.init()) : .pixiv(.init()))
    }

    func enter() {
        if scope != library.requestScope(source) { resetScope() }
        if !state.hasLoaded { refresh() }
        else if let checked = state.checkedAt, Date().timeIntervalSince(checked) >= 300 { fetch(request: .init(), background: true) }
    }

    func leave() { task?.cancel(); task = nil; generation = UUID(); state.isLoading = false }

    func resetScope() {
        leave(); scope = library.requestScope(source)
        returnContext = nil; hasReturnContext = false
        state = .init(query: state.query)
        onResetScroll?()
    }

    func setQuery(_ query: Query) {
        guard query != state.query else { return }
        let keepsAuthorOrigin: Bool
        if case .pixiv(let previous) = state.query, case .pixiv(let next) = query {
            keepsAuthorOrigin = previous.authorID != nil && previous.authorID == next.authorID
        } else { keepsAuthorOrigin = false }
        leave()
        if !keepsAuthorOrigin { returnContext = nil; hasReturnContext = false }
        state = .init(query: query)
        onResetScroll?(); refresh()
    }

    func setSearch(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.query {
        case .wallhaven(var q): q.search = text; setQuery(.wallhaven(q))
        case .pixiv(var q): q.search = text; q.authorID = nil; setQuery(.pixiv(q))
        }
    }

    func openAuthor(_ id: String) {
        guard source == .pixiv, case .pixiv(var query) = state.query, query.authorID != id else { return }
        leave()
        if returnContext == nil { onCaptureReturnScroll?(); returnContext = state }
        query.authorID = id; query.search = ""
        state = .init(query: .pixiv(query)); hasReturnContext = true
        onResetScroll?(); refresh()
    }

    func goBack() {
        guard scope == library.requestScope(source) else { resetScope(); return }
        guard let previous = returnContext else { return }
        leave(); returnContext = nil; state = previous; hasReturnContext = false
        onRestoreReturnScroll?()
    }

    func refresh() { state.refreshToken = UUID(); fetch(request: .init(), background: false, reset: true) }
    func loadMore() { if let next = state.next { fetch(request: next, background: false) } }

    private func fetch(request: OnlineImagePageRequest, background: Bool, reset: Bool = false) {
        guard !state.isLoading || reset else { return }
        if reset { leave() }
        let id = UUID(); generation = id
        let query = state.query, source = self.source
        state.isLoading = true; state.error = nil
        task = Task { [weak self, library] in
            var preparedScope: String?
            do {
                let fetchPage: (OnlineImagePageRequest, Bool) async throws -> OnlineImagePage
                switch query {
                case .wallhaven(let value):
                    let client = await library.prepareWallhaven()
                    fetchPage = { request, _ in try await client.page(query: value, request: request) }
                case .pixiv(let value):
                    let client = await library.preparePixiv()
                    fetchPage = { request, resetsList in
                        if resetsList, request.page == 1, value.authorID != nil { await client.invalidateAuthorSnapshot() }
                        return try await client.page(query: value, request: request)
                    }
                }
                guard let self, !Task.isCancelled, generation == id, state.query == query else { return }
                let currentScope = library.requestScope(source)
                preparedScope = currentScope
                let replacesScope = scope != currentScope
                if replacesScope {
                    returnContext = nil; hasReturnContext = false
                    state = .init(query: query); state.isLoading = true
                    onResetScroll?()
                }
                let page = try await fetchPage(replacesScope ? .init() : request, reset || replacesScope)
                guard !Task.isCancelled, generation == id, state.query == query else { return }
                guard library.requestScope(source) == currentScope else { resetScope(); return }
                if background && !replacesScope {
                    let byID = Dictionary(page.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                    state.items = state.items.map { byID[$0.id] ?? $0 }
                    if state.firstPageIDs != page.items.map(\.id) { state.notice = "有新内容可刷新" }
                } else if reset || replacesScope {
                    state.items = Self.unique(page.items)
                    state.firstPageIDs = page.items.map(\.id)
                    state.next = page.next; state.notice = page.notice
                    onResetScroll?()
                } else {
                    var indices = Dictionary(state.items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
                    for value in page.items {
                        if let index = indices[value.id] { state.items[index] = value }
                        else { indices[value.id] = state.items.count; state.items.append(value) }
                    }
                    state.next = page.next; state.notice = page.notice
                }
                scope = currentScope
                state.total = page.total; state.checkedAt = Date(); state.hasLoaded = true
                state.isLoading = false; task = nil
            } catch {
                guard let self, !Task.isCancelled, generation == id else { return }
                if let preparedScope, preparedScope != library.requestScope(source) { resetScope(); return }
                state.error = error.localizedDescription; state.isLoading = false; task = nil
            }
        }
    }

    private static func unique(_ items: [OnlineImageArtwork]) -> [OnlineImageArtwork] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
