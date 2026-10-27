import AppKit

// The production library context menu and favorite-action factory run beside
// the real source menu. Controlled business leaves record the chosen targets;
// invoking the shared reveal never opens Finder or touches user media.
private enum WallpaperProvider: Hashable { case steamWorkshop, videoLibrary }
private struct WallpaperReference: Hashable { let provider: WallpaperProvider; let sourceID: String }
private enum WallpaperMediaKind { case image, video, web, scene }
private struct MenuCapabilities: OptionSet {
    let rawValue: Int
    static let play = Self(rawValue: 1 << 0), organize = Self(rawValue: 1 << 1), reveal = Self(rawValue: 1 << 2)
    static let quickLook = Self(rawValue: 1 << 3), retryDownload = Self(rawValue: 1 << 4), retryUpdate = Self(rawValue: 1 << 5)
}
private struct WallpaperContentItem {
    let reference: WallpaperReference
    var providerReference: WallpaperReference { reference }
    let title: String
    let kind: WallpaperMediaKind
    let capabilities: MenuCapabilities
    let locator: URL?
}

// ACTUAL_LIBRARY_FAVORITE_STATE

@MainActor private final class LibraryMenuWorkspace {
    enum Page { case downloads, favorites; var isRemoteBrowse: Bool { false } }
    struct Relationships { var resetEpoch = UUID() }
    struct Presentation {
        struct Selection { var sessionID = UUID() }
        var page = Page.downloads
        var selectionState = Selection()
    }
    var relationships = Relationships()
    var presentation = Presentation()
    func isPlaying(_ reference: WallpaperReference) -> Bool { false }
    func capturePlaybackSnapshot(for reference: WallpaperReference) throws -> UUID { UUID() }
    func play(_ reference: WallpaperReference, from source: UUID?) {}
}
@MainActor private final class LibraryMenuManager {
    struct Commit { let ticket: UUID }
    struct PlaybackSwitch { var committed: Commit? }
    var playbackSwitch = PlaybackSwitch()
}
@MainActor private final class LibraryMenuImports { func chooseReplacement(for reference: WallpaperReference) {} }
private enum WallpaperLibraryImportCoordinator {
    static func canRelocate(_ item: WallpaperContentItem, relationships: LibraryMenuWorkspace.Relationships) -> Bool { false }
}
private enum WallpaperLibraryDownloadRecovery {
    static func makeMenu(for item: WallpaperContentItem, workspace: LibraryMenuWorkspace,
                         steam: SteamWorkshopService, online: Int, includeSourcePage: Bool = true) -> NSMenu? { nil }
}
private struct OnlineImageAssetID: Hashable { init?(reference: WallpaperReference) { return nil } }
@MainActor private final class OnlineImageLibrary {
    static let shared = OnlineImageLibrary()
    var progress: [OnlineImageAssetID: Int] = [:]
    func cancel(_ id: OnlineImageAssetID) {}
}
private enum SteamWorkshopDownloadGridSupport {
    static func isRetryEligible(_ record: Record) -> Bool { record.status == .failed }
}
typealias SteamWorkshopDownloadRecord = Record
private extension Record {
    var title: String { id }
    var displayItemForToolbar: SteamWorkshopBrowserItem {
        .init(id: id, title: id, detailURL: URL(string: "https://example.invalid/" + id)!)
    }
}
private extension SteamWorkshopService {
    func downloadWorkshopItem(id: String, pageTitle: String) { commands.append("download:" + id) }
}

@MainActor private final class LibraryMenuCommands {
    let workspace = LibraryMenuWorkspace()
    let manager = LibraryMenuManager()
    let imports = LibraryMenuImports()
    let steam = SteamWorkshopService()
    let online = 0
    var canOrganize = true
    var onInspect: ((WallpaperContentItem) -> Void)?
    var onPreview: ((WallpaperContentItem) -> Void)?
    var sourceItems: [WallpaperReference: WallpaperContentItem] = [:]
    var favoriteProjectionCalls = 0, resolveCalls = 0
    var favoriteRequests: [([WallpaperReference], Bool?)] = []
    var revealed: [[URL]] = []
    func favoriteActionState(for items: [WallpaperContentItem]) -> WallpaperLibraryFavoriteActionState {
        favoriteProjectionCalls += 1
        return .init(canEdit: canOrganize, hasItems: !items.isEmpty, allFavorite: false,
                     allOrganizable: items.allSatisfy { $0.capabilities.contains(.organize) })
    }
    private func resolveSelection(_ references: [WallpaperReference]?) -> [WallpaperContentItem]? {
        resolveCalls += 1
        return references.map { $0.compactMap { sourceItems[$0] } }
    }
    func toggleFavorite(_ references: [WallpaperReference], expectingRemoval: Bool?) {
        favoriteRequests.append((references, expectingRemoval))
    }
    func stop(_ reference: WallpaperReference, expectedTicket: UUID) {}
    func makePlaylistMenu(_ references: [WallpaperReference]) -> NSMenu? { NSMenu() }
    func reveal(_ items: [WallpaperContentItem]) { revealed.append(items.compactMap(\.locator)) }
    func removalTitle(for page: LibraryMenuWorkspace.Page) -> String { "移除" }
    func remove(_ items: [WallpaperContentItem], from page: LibraryMenuWorkspace.Page) {}
    // ACTUAL_LIBRARY_FAVORITE_FACTORY
    // ACTUAL_LIBRARY_CONTEXT_MENU
}

@MainActor private func runLibraryMenuCompositionChecks() {
    let commands = LibraryMenuCommands()
    let remote = WallpaperReference(provider: .steamWorkshop, sourceID: "1234567890")
    let local = WallpaperReference(provider: .videoLibrary, sourceID: "local")
    let downloaded = WallpaperContentItem(reference: remote, title: "Downloaded", kind: .video,
        capabilities: [.play, .organize, .reveal], locator: URL(fileURLWithPath: "/owned/library/downloaded.mp4"))
    let video = WallpaperContentItem(reference: local, title: "Local", kind: .video,
        capabilities: [.play, .organize, .reveal], locator: URL(fileURLWithPath: "/owned/library/local.mp4"))
    commands.sourceItems = [remote: downloaded, local: video]
    commands.steam.record = Record(id: remote.sourceID, status: .ready)
    func revealItems(_ menu: NSMenu) -> [NSMenuItem] { menu.items.filter { $0.title == "在 Finder 中显示" } }
    func invoke(_ item: NSMenuItem) {
        precondition(item.isEnabled)
        precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
    }

    let ready = commands.contextMenu(for: [downloaded])!
    precondition(revealItems(ready).count == 1 && revealItems(ready)[0].isEnabled,
        "a ready Steam library context menu has exactly one shared reveal")
    precondition(ready.items.contains { $0.title == "查看作者工坊" }
        && ready.items.contains { $0.title == "加入订阅" }, "source author and subscription commands remain")
    precondition(commands.favoriteProjectionCalls == 1 && commands.resolveCalls == 0,
        "one context-menu assembly shares its current favorite projection without resolving again")
    commands.steam.record = Record(id: "another", status: .ready)
    invoke(revealItems(ready)[0])
    precondition(commands.revealed == [[downloaded.locator!]], "shared reveal keeps the clicked content path")
    invoke(ready.items.first { $0.title == "特别喜爱" }!)
    precondition(commands.favoriteRequests.count == 1 && commands.favoriteRequests[0].0 == [remote]
        && commands.favoriteRequests[0].1 == false, "the pre-resolved favorite action retains its rendered add intent")
    commands.workspace.presentation.page = .favorites
    invoke(revealItems(ready)[0])
    precondition(commands.revealed.count == 1, "a held composite menu cannot act on a later page")
    commands.workspace.presentation.page = .downloads
    let beforeReset = commands.contextMenu(for: [downloaded])!
    commands.workspace.relationships.resetEpoch = UUID()
    invoke(revealItems(beforeReset)[0])
    precondition(commands.revealed.count == 1, "a held composite menu cannot survive reset")
    let beforeSelection = commands.contextMenu(for: [downloaded])!
    commands.workspace.presentation.selectionState.sessionID = UUID()
    invoke(beforeSelection.items.first { $0.title == "特别喜爱" }!)
    precondition(commands.favoriteRequests.count == 1, "the pre-resolved favorite factory keeps selection-session revocation")

    commands.steam.record = Record(id: remote.sourceID, status: .failed, failureMessage: "failed")
    let failed = WallpaperContentItem(reference: remote, title: "Failed", kind: .video,
        capabilities: [.retryDownload], locator: nil)
    let failedMenu = commands.contextMenu(for: [failed])!
    precondition(revealItems(failedMenu).count == 1 && !revealItems(failedMenu)[0].isEnabled,
        "unpublished failed content has one disabled reveal and no source duplicate")
    precondition(failedMenu.items.contains { $0.title == "重试下载" && $0.isEnabled }, "download recovery remains available")
    let localMenu = commands.contextMenu(for: [video])!
    precondition(revealItems(localMenu).count == 1 && revealItems(localMenu)[0].isEnabled
        && !localMenu.items.contains { $0.title == "查看作者工坊" }, "local video keeps the same single shared reveal")
    let mixed = commands.contextMenu(for: [downloaded, video])!
    precondition(revealItems(mixed).count == 1, "multi-provider selection exposes one shared reveal")
    invoke(revealItems(mixed)[0])
    precondition(commands.revealed.last == [downloaded.locator!, video.locator!], "multi-selection reveal retains both fixed targets")
    precondition(commands.contextMenu(for: []) == nil, "empty selection never produces a context menu")

    commands.canOrganize = false
    let readOnly = commands.contextMenu(for: [downloaded])!
    precondition(readOnly.items.first { $0.title == "特别喜爱" }?.isEnabled == false,
        "reusing the current projection never enables read-only organization")
    commands.canOrganize = true
    commands.favoriteProjectionCalls = 0; commands.resolveCalls = 0
    let ordinaryFavorite = commands.makeFavoriteAction([local])!
    precondition(commands.resolveCalls == 1 && commands.favoriteProjectionCalls == 1,
        "ordinary callers still resolve and project through the original action factory")
    commands.workspace.relationships.resetEpoch = UUID()
    ordinaryFavorite()
    precondition(commands.favoriteRequests.count == 1, "ordinary favorite actions retain reset revocation")
}
