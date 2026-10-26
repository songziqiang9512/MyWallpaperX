import Combine
import Foundation

// Deferred App candidate. Combine with the Core harness helpers and inject
// the real App methods at ACTUAL_AUTHOR_BRIDGE when that integration resumes.
// The Core browse gate neither reads nor compiles this file.
// Only the App bridge's page/reset inputs, inspector close and Shell navigation
// are controlled. The real Session and App methods run below. Shell's existing
// per-page query/selection persistence and native toolbar layout are separate gates.
@MainActor private final class AuthorBridgeWorkspace {
    struct Presentation { var page = WallpaperLibraryPage.downloads }
    struct Relationships { var resetEpoch = UUID() }
    var presentation = Presentation()
    var relationships = Relationships()
}
@MainActor private final class AuthorBridgeInspector {
    var closes = 0
    func closeInspector() { closes += 1 }
    func closePreview() { closes += 1 }
}
@MainActor private final class AuthorBridgeProbe {
    let workspace = AuthorBridgeWorkspace()
    let inspector = AuthorBridgeInspector()
    let pixiv: OnlineImageBrowserSession
    let wallhaven: OnlineImageBrowserSession
    private var authorOrigin: (page: WallpaperLibraryPage, resetEpoch: UUID)?
    var onNavigate: ((WallpaperLibraryPage) -> Void)?
    var onChange: (() -> Void)?
    var navigations: [WallpaperLibraryPage] = []
    var scrollCaptures: [WallpaperLibraryPage] = []
    init(_ library: OnlineImageLibrary) {
        pixiv = .init(source: .pixiv, library: library)
        wallhaven = .init(source: .wallhaven, library: library)
        onNavigate = { [weak self] page in
            self?.navigations.append(page); self?.workspace.presentation.page = page
        }
    }
    func browser(for page: WallpaperLibraryPage) -> Bool { scrollCaptures.append(page); return true }
    // ACTUAL_AUTHOR_BRIDGE
}

@MainActor private func externalAuthorReturn(_ checks: inout [String: Bool]) async throws {
    let library = OnlineImageLibrary(), bridge = AuthorBridgeProbe(library)
    bridge.pixiv.enter()
    let initial = try await request(library, count: 1)
    let next = OnlineImagePageRequest(page: 2, date: "20261024", offset: 24)
    try await respond(library, index: initial, result: .success(.init(items: [artwork(.pixiv, "71")], next: next)))
    try await waitFor("external author origin") { !bridge.pixiv.state.isLoading }
    let browseOrigin = bridge.pixiv.state
    bridge.openAuthor("77", from: .downloads)
    let author = try await request(library, count: 2)
    try await respond(library, index: author, result: .success(.init(items: [artwork(.pixiv, "72")], next: nil)))
    try await waitFor("external author") { !bridge.pixiv.state.isLoading }
    checks["local-author-entry-routes-through-existing-pixiv-page-with-one-return-context"] = bridge.navigations == [.pixiv]
        && bridge.hasReturnContext(for: .pixiv) && bridge.inspector.closes == 2 && bridge.scrollCaptures == [.pixiv]
    bridge.openAuthor("88", from: .pixiv)
    let nested = try await request(library, count: 3)
    try await respond(library, index: nested, result: .success(.init(items: [artwork(.pixiv, "73")], next: nil)))
    try await waitFor("author within author") { !bridge.pixiv.state.isLoading }
    bridge.goBack()
    checks["author-within-author-preserves-external-local-origin-without-navigation-stack"] = bridge.navigations == [.pixiv, .downloads]
        && bridge.workspace.presentation.page == .downloads && bridge.pixiv.state.query == browseOrigin.query
        && bridge.pixiv.state.items == browseOrigin.items && bridge.pixiv.state.next == browseOrigin.next

    bridge.pixiv.setQuery(.pixiv(.init(authorID: "77")))
    let direct = try await request(library, count: 4)
    try await respond(library, index: direct, result: .success(.init(items: [artwork(.pixiv, "74")], next: nil)))
    try await waitFor("direct author query") { !bridge.pixiv.state.isLoading }
    bridge.pixiv.resetScope() // Retains author query while discarding Session return state.
    bridge.workspace.presentation.page = .favorites
    bridge.openAuthor("77", from: .favorites)
    checks["same-author-external-origin-supplies-return-even-without-session-return-state"] = !bridge.pixiv.hasReturnContext
        && bridge.hasReturnContext(for: .pixiv) && library.client.requests.count == 4
    bridge.goBack()
    checks["same-author-early-return-does-not-swallow-local-page-return"] = bridge.workspace.presentation.page == .favorites
        && Array(bridge.navigations.suffix(2)) == [.pixiv, .favorites] && !bridge.hasReturnContext(for: .pixiv)

    bridge.workspace.presentation.page = .downloads
    bridge.openAuthor("77", from: .downloads)
    let playlist = WallpaperLibraryPage.playlist(UUID())
    bridge.workspace.presentation.page = playlist
    bridge.openAuthor("77", from: playlist)
    bridge.goBack()
    checks["new-local-author-entry-replaces-external-origin-rather-than-returning-to-old-local-page"] = bridge.workspace.presentation.page == playlist
        && bridge.navigations.last == playlist && library.client.requests.count == 4

    bridge.workspace.presentation.page = .downloads
    bridge.openAuthor("77", from: .downloads)
    bridge.workspace.relationships.resetEpoch = UUID()
    let navigationCount = bridge.navigations.count
    checks["reset-revokes-external-author-return-admission"] = !bridge.hasReturnContext(for: .pixiv)
    bridge.goBack()
    checks["reset-author-back-cannot-navigate-to-old-local-target"] = bridge.workspace.presentation.page == .pixiv
        && bridge.navigations.count == navigationCount && !bridge.hasReturnContext(for: .pixiv)
    bridge.pixiv.leave(); bridge.wallhaven.leave()
}
