import AppKit
import Combine
import Foundation

// ACTUAL_FAVORITE_STATE
// ACTUAL_CARD_STATE
// ACTUAL_RENDER_SIGNATURE

// Controlled page and renderer leaves; actual Sequence/Transaction identities
// make the fixed native action independent of a later request or UI selection.
@MainActor private final class WallpaperManager {
    var playbackSwitch=PlaybackSwitchTransaction()
    var libraryPlaybackSequence=WallpaperPlaybackSequence()
    var stops=0
    var randomRequests = 0
    func setRandomPlaybackEnabled(_ value: Bool) { if value { randomRequests += 1 } }
    @discardableResult func select(_ reference:WallpaperReference,source:WallpaperPlaybackSequence.Snapshot)->PlaybackSwitchTicket {
        let proposal=libraryPlaybackSequence.proposeSelection(reference,from:source)!
        let (ticket,initial)=playbackSwitch.begin(proposal.entry.runtime!)
        _ = libraryPlaybackSequence.stage(proposal,ticket:ticket)
        run(initial)
        run(playbackSwitch.prepared(ticket,executionID:UUID()))
        return ticket
    }
    private func run(_ initial:[PlaybackSwitchTransaction.Effect]) {
        var effects=initial
        while !effects.isEmpty {
            switch effects.removeFirst() {
            case .output(let op):effects += playbackSwitch.activityCompleted(op,succeeded:true)
            case .activate(let selection):effects += playbackSwitch.visible(selection.ticket,executionID:selection.executionID!)
            case .commit(let selection,let recovery):_ = libraryPlaybackSequence.commit(selection.ticket,recovery:recovery)
            case .cancel(let barrier,_):effects += playbackSwitch.cancelled(barrier)
            case .retire(let barrier,_),.handoff(let barrier,_,_):effects += playbackSwitch.retired(barrier)
            default:break
            }
        }
    }
    func stopCurrentPlayback(){stops += 1;libraryPlaybackSequence.stop();run(playbackSwitch.stop())}
}
@MainActor private final class CommandWorkspace {
    let manager:WallpaperManager
    var displayed:WallpaperPlaybackSequence.Snapshot
    var plays:[(WallpaperReference,WallpaperPlaybackSequence.Snapshot?)]=[]
    var playingQueries = 0
    var relationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
        playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
    let presentation = RemotePresentation()
    init(_ manager:WallpaperManager,_ source:WallpaperPlaybackSequence.Snapshot){self.manager=manager;displayed=source}
    func isPlaying(_ ref:WallpaperReference)->Bool {
        playingQueries += 1
        return manager.libraryPlaybackSequence.committed?.reference == ref
            && manager.libraryPlaybackSequence.committed?.ticket == manager.playbackSwitch.committed?.ticket
    }
    func capturePlaybackSnapshot(for ref:WallpaperReference)throws->WallpaperPlaybackSequence.Snapshot{displayed}
    func play(_ ref:WallpaperReference,from source:WallpaperPlaybackSequence.Snapshot? = nil){
        plays.append((ref,source));_ = manager.select(ref,source:source ?? displayed)
    }
}
// This gate covers fixed primary actions, recovery delegation and local drop
// admission. Local/remote recovery execute in their dedicated real-owner gates.
@MainActor private final class WallpaperLibraryImportCoordinator {
    static func canRelocate(_ content: WallpaperContentItem, relationships: UserCollectionsSnapshot) -> Bool { false }
    func chooseReplacement(for reference: WallpaperReference) { preconditionFailure("Recovery is not an available-content action") }
}
@MainActor private final class CommandSteam {}
@MainActor private final class CommandPixabay {}
@MainActor private final class PlaylistRecordingLeaf {
    let record: ([WallpaperReference]) -> Void
    init(_ record: @escaping ([WallpaperReference]) -> Void) { self.record = record }
    func add(_ items: [WallpaperOrganizationItem], to id: UUID, completion: (() -> Void)? = nil) { record(items.map(\.reference)); completion?() }
    func create(members: [WallpaperOrganizationItem], completion: (() -> Void)? = nil) { record(members.map(\.reference)); completion?() }
}
@MainActor private enum WallpaperLibraryDownloadRecovery {
    static func makePrimaryAction(for item: WallpaperContentItem, workspace: CommandWorkspace,
        steam: CommandSteam, pixabay: CommandPixabay) -> (() -> Void)? { OnlineImageCommandRecoveryProbe.action(for: item) }
}
@MainActor private final class WallpaperLibraryCommands {
    let manager:WallpaperManager
    let workspace:CommandWorkspace
    var canOrganize = true
    var favoriteActions: [[WallpaperReference]] = []
    var playlistActions: [[WallpaperReference]] = []
    let imports = WallpaperLibraryImportCoordinator()
    let steam = CommandSteam(), pixabay = CommandPixabay()
    private lazy var playlists: PlaylistRecordingLeaf? = .init { [weak self] in self?.playlistActions.append($0) }
    init(_ manager:WallpaperManager,_ workspace:CommandWorkspace){self.manager=manager;self.workspace=workspace}
    func toggleFavorite(_ refs: [WallpaperReference], expectingRemoval: Bool? = nil) { guard canOrganize else { return }; favoriteActions.append(refs) }
    func choosePlaylist(_ refs: [WallpaperReference], anchor: NSView? = nil) { guard canOrganize else { return }; playlistActions.append(refs) }
    private func resolveSelection(_ refs: [WallpaperReference]?) -> [WallpaperContentItem]? {
        (refs ?? []).map { .init(reference: $0, providerReference: $0, locator: .init(), title: $0.sourceID,
            kind: .video, publishedAvailability: .available, capabilities: [.organize], metadata: .init(), acquisition: .idle, update: .idle, aliases: []) }
    }
    func makeRestoreLibraryAction(for content: WallpaperContentItem) -> (() -> Void)? { nil }
    // ACTUAL_PLAYLIST_MENU
    // ACTUAL_PRIMARY_FACTORY
}

private struct SteamWorkshopBrowserItem { let id: String }
private struct PixabayVideoItem { let id: Int }
@MainActor private final class RemotePixabaySelection { var selectedItem: PixabayVideoItem? }
private enum AppKitSteamWorkshopBrowserItem {
    // ACTUAL_STEAM_ORGANIZATION
}
@MainActor private final class RemoteSteam { var selectedBrowserItem: SteamWorkshopBrowserItem?; @Published var navigationVersion = 0 }
@MainActor private struct RemoteOnlineImages {
    var selectedContent: WallpaperContentItem?
    func selectedOrganizationActions() -> WallpaperInspectorActions? { nil }
}
@MainActor private final class RemotePresentation {
    struct Query { var items: [WallpaperContentItem] = [] }
    var queryResult = Query()
    var page = WallpaperLibraryPage.workshop
    var selectionState = WallpaperLibrarySelectionState()
    func beginOrganizationOperation(_ references: Set<WallpaperReference>) -> WallpaperLibrarySelectionReceipt? { nil }
    func completeOrganizationOperation(_ receipt: WallpaperLibrarySelectionReceipt?, succeeded: Bool) {}
}
@MainActor private final class RemoteWorkspace {
    let presentation = RemotePresentation()
    var relationships: UserCollectionsSnapshot
    var requests: [WallpaperReference] = []
    init(_ relationships: UserCollectionsSnapshot) { self.relationships = relationships }
    func requestSingle(_ ref: WallpaperReference) { requests.append(ref) }
}
@MainActor private final class RemoteComposition {
    let onlineImages = RemoteOnlineImages()
    let workspace: RemoteWorkspace
    // Modal admission is a controlled leaf here; native sheets have their own gate.
    var permitsInput = true, isVisible = true
    let steam = RemoteSteam()
    private var subscriptions = Set<AnyCancellable>()
    let steamBrowserContent = RemoteNavigationRefreshLeaf()
    let pixabayBrowserContent = RemotePixabaySelection()
    let commands: WallpaperLibraryCommands
    var downloadedContent: [WallpaperReference: WallpaperContentItem] = [:]
    var cardState: WallpaperLibraryCardStateProjection?
    var playlistNames: [WallpaperReference: [String]] = [:]
    init(_ workspace: RemoteWorkspace, _ commands: WallpaperLibraryCommands) {
        self.workspace = workspace; self.commands = commands
        // ACTUAL_STEAM_NAVIGATION_BINDING
    }
    func organization(_ item: SteamWorkshopBrowserItem) -> AppKitSteamWorkshopBrowserItem.OrganizationPresentation? { remoteOrganization(for: item) }
    func inspector(_ item: SteamWorkshopBrowserItem) -> WallpaperInspectorActions? { remoteInspectorActions(for: item) }
    func menu(_ item: SteamWorkshopBrowserItem) -> NSMenu? { remoteOrganizationMenu(for: item) }
    func pixabay(_ id: Int) -> WallpaperInspectorActions? { pixabayOrganization(for: .init(id: id)) }
    func favorite(_ content: WallpaperContentItem) -> (() -> Void)? { makeCardFavoriteAction(content) }
    // ACTUAL_REMOTE_ACTIONS
}

// Actual Composition admission and native collection drop callbacks; only the
// importer leaf is controlled. No window is shown and no media is imported.
// ACTUAL_DRAG_INFO_LEAF
@MainActor private final class FileDropGrid {
    let collection = NSCollectionView()
    var onImportFiles: (([URL]) -> Bool)?
    // ACTUAL_FILE_DROP_RECEIPT
    func validate(_ info: NSDraggingInfo) -> NSDragOperation {
        var proposed = NSIndexPath(forItem: 0, inSection: 0)
        var operation = NSCollectionView.DropOperation.on
        return withUnsafeMutablePointer(to: &proposed) { pointer in
            collectionView(collection, validateDrop: info, proposedIndexPath: AutoreleasingUnsafeMutablePointer(pointer), dropOperation: &operation)
        }
    }
    func accept(_ info: NSDraggingInfo) -> Bool {
        collectionView(collection, acceptDrop: info, indexPath: .init(item: 0, section: 0), dropOperation: .on)
    }
}
@MainActor private final class FileDropCommands {
    var canOrganize = true
    var allowsImport = true
    var canImport: Bool { canOrganize && allowsImport }
    var imports: [[URL]] = []
    func importFiles(_ urls: [URL]) { imports.append(urls) }
}
@MainActor private final class FileDropComposition {
    let workspace: RemoteWorkspace
    var permitsInput = true
    let commands = FileDropCommands()
    let grid = FileDropGrid()
    init(_ workspace: RemoteWorkspace) { self.workspace = workspace }
    func configure(_ page: WallpaperLibraryPage) {
        workspace.presentation.page = page
        configureFileDrop(for: page)
    }
    // ACTUAL_FILE_DROP_BINDING
}

private enum RecentAlertStyle { case warning }
@MainActor private final class RecentAlert {
    let title: String; let message: String; let buttons: [String]
    var showsSuppressionButton = false
    let suppressionButton: NSButton? = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    init(title: String, message: String, buttons: [String]) { self.title = title; self.message = message; self.buttons = buttons }
}
@MainActor private enum RecentAlertProbe {
    static var alert: RecentAlert?
    static var completion: ((NSApplication.ModalResponse) -> Void)?
    static func finish(_ response: NSApplication.ModalResponse) { let action = completion; completion = nil; action?(response) }
}
@MainActor private func makeAppAlert(title: String, message: String, style: RecentAlertStyle = .warning, buttons: [String] = ["确定"]) -> RecentAlert {
    .init(title: title, message: message, buttons: buttons)
}
@MainActor private func presentAppAlert(_ alert: RecentAlert, in window: NSWindow?,
    completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
    RecentAlertProbe.alert = alert; RecentAlertProbe.completion = completion
}
@MainActor private final class RecentPresentation {
    var page = WallpaperLibraryPage.recent
    var selectionState = WallpaperLibrarySelectionState()
    var errors = 0
    func report(_ error: Error) { errors += 1 }
    func beginOrganizationOperation(_ references: Set<WallpaperReference>) -> WallpaperLibrarySelectionReceipt? { nil }
    func completeOrganizationOperation(_ receipt: WallpaperLibrarySelectionReceipt?, succeeded: Bool) {}
}
@MainActor private final class RecentWorkspace {
    let collections: UserCollectionsController?
    let presentation = RecentPresentation()
    var relationships: UserCollectionsSnapshot { collections!.snapshot }
    var edited: [WallpaperLibraryPage] = []
    init(_ collections: UserCollectionsController) { self.collections = collections }
    func didEditMembers(of page: WallpaperLibraryPage) { edited.append(page) }
}
@MainActor private final class RecentCommands {
    let workspace: RecentWorkspace
    var canOrganize = true
    let hostWindow: () -> NSWindow? = { nil }
    init(_ workspace: RecentWorkspace) { self.workspace = workspace }
    // ACTUAL_RECENT_MENU
}

// These leaves provide exact per-source completion facts and real isolated
// file deletion. Navigation/receipt/query and relationship writes are product
// implementations; no collection view or diffable selection oracle is copied.
private struct RemovalRecord { let id: String; var path: String = "" }
private struct RemovalFileResult {
    let localURL: URL
    let failureMessage: String?
    var sourceFileDeleted: Bool = false
    var succeeded: Bool { failureMessage == nil }
}
@MainActor private final class RemovalManager {
    var wallpapers: [RemovalRecord] = []
    var completion: ((WallpaperSourceDeletionResult) -> Void)?
    var requested: [String] = []
    func deleteSourceFiles(_ items: [RemovalRecord], completion: @escaping (WallpaperSourceDeletionResult) -> Void) {
        requested = items.map(\.id); self.completion = completion
    }
    func isLocalSourceFileInUse(_ path: String) -> Bool { false }
    func finish(_ successfulIDs: Set<String>) {
        let results = requested.map { id -> WallpaperSourceDeletionResult.Item in
            let row = wallpapers.first { $0.id == id }!
            return .init(reference: .init(provider: .videoLibrary, sourceID: id), sourceURL: URL(fileURLWithPath: row.path),
                succeeded: successfulIDs.contains(id), sourceFileDeleted: successfulIDs.contains(id),
                failureMessage: successfulIDs.contains(id) ? nil : "controlled source failure")
        }
        let action = completion; completion = nil; action?(.init(items: results))
    }
}
@MainActor private final class RemovalImages {
    var wallpapers: [RemovalRecord] = [], requested: [String] = []
    var failedIDs: Set<String> = []
    func deleteSourceFiles(ids: [String], isInUse: @escaping (URL) -> Bool, completion: @escaping (WallpaperSourceDeletionResult) -> Void) {
        requested = ids
        completion(.init(items: wallpapers.filter { ids.contains($0.id) }.map {
            let url = URL(fileURLWithPath: $0.path), success = !failedIDs.contains($0.id) && !isInUse(URL(fileURLWithPath: $0.path))
            return .init(reference: .init(provider: .staticImageLibrary, sourceID: $0.id), sourceURL: url,
                succeeded: success, sourceFileDeleted: success, failureMessage: success ? nil : "controlled source failure")
        }))
    }
}
@MainActor private final class RemovalSteam {
    let steamDownloadLibraryRootURL = URL(fileURLWithPath: "/controlled/steam")
    var requested: [String] = []
    var completion: ((WallpaperSourceDeletionResult) -> Void)?
    func deleteSourceFiles(itemIDs: [String], completion: @escaping (WallpaperSourceDeletionResult) -> Void) {
        requested = itemIDs; self.completion = completion
    }
    func finish(_ result: [String: Bool]) {
        let action = completion; completion = nil
        action?(.init(items: requested.map {
            .init(reference: .init(provider: .steamWorkshop, sourceID: $0), sourceURL: URL(fileURLWithPath: "/controlled/" + $0),
                succeeded: result[$0] == true, sourceFileDeleted: result[$0] == true, failureMessage: result[$0] == true ? nil : "controlled failure")
        }))
    }
}
@MainActor private final class RemovalPixabay {
    static let downloadDirectory = URL(fileURLWithPath: "/controlled/online")
    static var downloadRoots: [URL] { [downloadDirectory] }
    var failingNames: Set<String> = []
    var requested: [URL] = []
    func deleteLocalFiles(at urls: [URL], isInUse: ((URL) -> Bool)? = nil) -> [RemovalFileResult] {
        requested = urls
        return urls.map { url in
            do {
                if failingNames.contains(url.lastPathComponent) || isInUse?(url) == true { throw CocoaError(.fileWriteNoPermission) }
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return RemovalFileResult(localURL: url, failureMessage: nil, sourceFileDeleted: true)
            } catch { return RemovalFileResult(localURL: url, failureMessage: url.lastPathComponent + ": " + error.localizedDescription) }
        }
    }
}
@MainActor private final class RemovalCatalog {
    var catalog: WallpaperLibraryCatalog
    var refreshes = 0
    init(_ catalog: WallpaperLibraryCatalog) { self.catalog = catalog }
    func refreshAvailability() { refreshes += 1 }
}
@MainActor private final class RemovalWorkspace {
    let collections: UserCollectionsController?
    let presentation: WallpaperLibraryPresentation
    let catalog: RemovalCatalog
    var relationships: UserCollectionsSnapshot { collections!.snapshot }
    var edited: [WallpaperLibraryPage] = []
    init(_ collections: UserCollectionsController, _ catalog: WallpaperLibraryCatalog, defaults: UserDefaults) {
        self.collections = collections; self.catalog = RemovalCatalog(catalog)
        presentation = WallpaperLibraryPresentation(collections: collections, defaults: defaults)
        presentation.update(catalog: catalog, relationships: collections.snapshot)
    }
    func publish(_ next: WallpaperLibraryCatalog) {
        catalog.catalog = next
        presentation.update(catalog: next, relationships: relationships)
    }
    func didEditMembers(of page: WallpaperLibraryPage) {
        edited.append(page)
        presentation.update(catalog: catalog.catalog, relationships: relationships)
    }
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        try WallpaperLibraryQuery.resolve([reference], catalog: catalog.catalog, relationships: relationships)[0]
    }
}
@MainActor private final class RemovalCommands {
    let workspace: RemovalWorkspace
    let manager = RemovalManager()
    let images = RemovalImages()
    let steam = RemovalSteam()
    let pixabay = RemovalPixabay()
    let hostWindow: () -> NSWindow? = { nil }
    var canOrganize = true
    var admittedWrites = 0
    private var playlists: PlaylistOrganizationActions?
    var selection: [WallpaperContentItem] {
        workspace.presentation.queryResult.items.filter { workspace.presentation.selectionState.references.contains($0.reference) }
    }
    init(_ workspace: RemovalWorkspace) {
        self.workspace = workspace
        let actions = PlaylistOrganizationActions(collections: workspace.collections!, hostWindow: { nil })
        actions.onDidEdit = { [weak workspace] id, _ in workspace?.didEditMembers(of: .playlist(id)) }
        actions.permitsEditing = { [weak self] in self?.canOrganize == true }
        playlists = actions
    }
    // ACTUAL_REMOVAL_COMMANDS
    // ACTUAL_RESTORATION_COMMANDS
    // ACTUAL_PLAYLIST_MENU
    // ACTUAL_FAVORITE_COMMANDS
    // ACTUAL_RECENT_ACTIONS
}

@main private enum WallpaperLibraryCommandTransactionsChecks {
    @MainActor static func main() async throws {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        var checks:[String:Bool]=[:]
        let a=WallpaperReference(provider:.videoLibrary,sourceID:"A"),b=WallpaperReference(provider:.videoLibrary,sourceID:"B")
        let firstSource=try WallpaperPlaybackSequence.Snapshot(source:.page(.videos),revision:1,
            entries:[a,b].map{.init(reference:$0,runtime:.video,isPlayable:true)},sourceQuery:.init())
        let otherSource=try WallpaperPlaybackSequence.Snapshot(source:.page(.favorites),revision:2,
            entries:[a,b].map{.init(reference:$0,runtime:.video,isPlayable:true)},sourceQuery:.init())
        func content(_ ref:WallpaperReference, kind: WallpaperMediaKind = .video)->WallpaperContentItem {
            .init(reference:ref,providerReference:ref,locator:.init(mediaKind:kind),title:ref.sourceID,kind:kind,
                  publishedAvailability:.available,capabilities:[.play,.organize],metadata:.init(),acquisition:.idle,update:.idle,aliases:[])
        }
        do {
            let c = WallpaperReference(provider: .videoLibrary, sourceID: "C")
            let source = try WallpaperPlaybackSequence.Snapshot(source: .page(.playlist(UUID())), revision: 4,
                entries: [a, b, c].map { .init(reference: $0, runtime: .video, isPlayable: true) })
            let manager = WallpaperManager(), view = CommandWorkspace(manager, source)
            let commands = WallpaperLibraryCommands(manager, view)
            view.presentation.queryResult.items = [content(b), content(c), content(a)]
            view.presentation.selectionState = .init(references: [a], focusedReference: a)
            commands.playDisplayed()
            checks["playlist-play-starts-at-visible-first-despite-another-selection"] = view.plays.last?.0 == b
                && manager.libraryPlaybackSequence.committed?.snapshot == source && manager.randomRequests == 0
            var distinct = true
            for _ in 0..<30 {
                let before = manager.libraryPlaybackSequence.committed?.reference
                commands.playDisplayed(random: true)
                distinct = distinct && view.plays.last?.0 != before && [a, b, c].contains(view.plays.last!.0)
            }
            checks["playlist-random-never-replays-current-and-retains-one-mode-owner"] = distinct && manager.randomRequests == 30
            _ = manager.select(a, source: source)
            view.relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil, playlists: [], members: [], favorites: [], recent: [], aliases: [.init(alias: a, canonical: b, proof: .publishedDownload)], locators: [])
            view.presentation.queryResult.items = [content(b), content(c)]
            commands.playDisplayed(random: true)
            checks["playlist-random-excludes-current-canonical-backing-after-alias-publication"] = view.plays.last?.0 == c
            view.presentation.queryResult.items = [content(c)]
            commands.playDisplayed(random: true)
            checks["playlist-random-singleton-remains-playable"] = view.plays.last?.0 == c
        }
        try runCompositionProjectionChecks(&checks)
        func send(_ action:@escaping ()->Void)->Bool {
            let item=ActionMenuItem(title:"captured command",symbol:"play",handler:action)
            let menu=NSMenu();menu.addItem(item)
            return app.sendAction(item.action!,to:item.target,from:item)
        }
        do {
            let manager=WallpaperManager()
            let view=CommandWorkspace(manager,firstSource),commands=WallpaperLibraryCommands(manager,view)
            _ = manager.select(a,source:firstSource)
            let stop=commands.makePrimaryAction(for:content(a))!
            let newer=manager.select(a,source:otherSource)
            checks["native-old-stop-does-not-stop-new-ticket-for-same-ref"] = send(stop) && manager.stops == 0
                && manager.playbackSwitch.committed?.ticket == newer && view.plays.isEmpty
            let stopAgain=commands.makePrimaryAction(for:content(a))!
            let bTicket=manager.select(b,source:otherSource)
            checks["native-old-stop-cannot-turn-into-play-after-other-wallpaper"] = send(stopAgain) && manager.stops == 0
                && manager.playbackSwitch.committed?.ticket == bTicket && view.plays.isEmpty
            let valid=commands.makePrimaryAction(for:content(b))!
            checks["native-current-stop-settles-exact-owner"] = send(valid) && manager.stops == 1 && manager.playbackSwitch.committed == nil
        }
        do {
            let manager=WallpaperManager()
            let workspace=CommandWorkspace(manager,firstSource),commands=WallpaperLibraryCommands(manager,workspace)
            let play=commands.makePrimaryAction(for:content(a))!
            workspace.displayed=otherSource
            _ = manager.select(a,source:otherSource)
            checks["native-captured-play-remains-play-with-original-source"] = send(play) && manager.stops == 0
                && workspace.plays.count == 1 && workspace.plays[0].1 == firstSource
                && manager.libraryPlaybackSequence.committed?.snapshot.source == firstSource.source
        }
        do {
            let manager = WallpaperManager()
            let workspace = CommandWorkspace(manager, firstSource)
            let commands = WallpaperLibraryCommands(manager, workspace)
            let old = manager.select(a, source: firstSource)
            let calls = workspace.playingQueries
            let renderedStop = commands.makePrimaryAction(for: content(a), from: firstSource,
                renderedPlaying: true, renderedTicket: old)!
            checks["rendered-primary-factory-does-not-requery-catalog-state"] = workspace.playingQueries == calls
            _ = manager.select(b, source: otherSource)
            checks["rendered-old-stop-still-revalidates-current-transaction"] = send(renderedStop) && manager.stops == 0
        }
        do {
            let raw = WallpaperReference(provider: .videoLibrary, sourceID: "backing")
            let target = WallpaperReference(provider: .steamWorkshop, sourceID: "backing")
            let nfc = WallpaperReference(provider: .videoLibrary, sourceID: "\u{e9}")
            let nfd = WallpaperReference(provider: .videoLibrary, sourceID: "e\u{301}")
            let items = (0..<300).map { content(.init(provider: .videoLibrary, sourceID: "row-\($0)")) }
                + [content(raw), content(target), content(nfc), content(nfd)]
            let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [.init(reference: raw, favoritedAt: nil), .init(reference: nfc, favoritedAt: nil)],
                recent: [], aliases: [.init(alias: raw, canonical: target, proof: .publishedDownload)], locators: [])
            let ticket = PlaybackSwitchTicket(epoch: 42, id: UUID(), runtime: .video)
            let before = WallpaperLibraryQuery.resolverInitializationCount
            let state = try WallpaperLibraryCardStateProjection(items: items, relationships: relationships,
                committedReference: raw, sequenceTicket: ticket, runtimeTicket: ticket)
            let after = WallpaperLibraryQuery.resolverInitializationCount
            var lookups = 0
            for _ in 0..<20 { for item in items {
                if state.isFavorite(item.reference) { lookups += 1 }
                _ = state.isPlaying(item.reference)
                _ = state.canonical(item.reference)
            } }
            checks["card-state-normalizes-once-for-whole-batch"] = after == before + 1
            checks["visible-card-state-lookups-never-rebuild-full-resolver"] = WallpaperLibraryQuery.resolverInitializationCount == after && lookups == 60
            checks["card-state-alias-favorite-and-playing-use-canonical-identity"] = state.isFavorite(raw) && state.isFavorite(target)
                && state.isPlaying(raw) && state.isPlaying(target) && state.committedTicket == ticket
            checks["card-state-preserves-opaque-unicode-and-provider-separation"] = state.isFavorite(nfc) && !state.isFavorite(nfd)
                && !state.isPlaying(nfc) && !state.isPlaying(.init(provider: .pixabay, sourceID: target.sourceID))
            let mismatch = try WallpaperLibraryCardStateProjection(items: items, relationships: relationships,
                committedReference: raw, sequenceTicket: ticket,
                runtimeTicket: .init(epoch: ticket.epoch + 1, id: UUID(), runtime: .video))
            checks["card-state-never-publishes-playing-for-uncommitted-sequence"] = !mismatch.isPlaying(raw) && mismatch.committedTicket == nil
        }
        do {
            let remote = WallpaperReference(provider: .steamWorkshop, sourceID: "ready-download")
            let item = SteamWorkshopBrowserItem(id: remote.sourceID)
            let relationships = UserCollectionsSnapshot(revision: 7, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [.init(reference: remote, favoritedAt: nil)], recent: [], aliases: [], locators: [])
            let source = try WallpaperPlaybackSequence.Snapshot(source: .single(remote), revision: 1,
                entries: [.init(reference: remote, runtime: .video, isPlayable: true)])
            let manager = WallpaperManager(), remoteWorkspace = RemoteWorkspace(relationships)
            let commandWorkspace = CommandWorkspace(manager, source), commands = WallpaperLibraryCommands(manager, commandWorkspace)
            let composition = RemoteComposition(remoteWorkspace, commands)
            let committed = manager.select(remote, source: source)
            composition.downloadedContent[remote] = content(remote)
            composition.cardState = try WallpaperLibraryCardStateProjection(items: [content(remote)], relationships: relationships,
                committedReference: remote, sequenceTicket: committed, runtimeTicket: committed)
            composition.steam.selectedBrowserItem = item
            composition.playlistNames[remote] = ["Mixed"]
            let before = WallpaperLibraryQuery.resolverInitializationCount
            let organization = composition.organization(item)!, inspector = composition.inspector(item)!
            for _ in 0..<100 { _ = composition.organization(item); _ = composition.inspector(item) }
            checks["remote-card-and-inspector-factories-only-use-render-batch-lookups"] = WallpaperLibraryQuery.resolverInitializationCount == before
                && organization.isFavorite && organization.isPlaying && inspector.state.isPlaying
                && inspector.state.playlistNames == ["Mixed"]
            composition.permitsInput = false
            organization.onFavorite?(); inspector.onPrimary(); inspector.onChoosePlaylist(nil)
            checks["held-remote-actions-refuse-new-input-from-a-covered-main-window"] = commands.favoriteActions.isEmpty
                && commands.playlistActions.isEmpty && remoteWorkspace.requests.isEmpty && manager.stops == 0
            composition.permitsInput = true
            organization.onFavorite?(); inspector.onChoosePlaylist(nil)
            checks["remote-downloaded-heart-and-playlist-target-fixed-local-ref"] = commands.favoriteActions == [[remote]]
                && commands.playlistActions == [[remote]]
            composition.steam.selectedBrowserItem = SteamWorkshopBrowserItem(id: "another-selected-detail")
            inspector.onToggleFavorite(); inspector.onChoosePlaylist(nil)
            checks["remote-inspector-actions-revoke-when-source-selection-changes"] = commands.favoriteActions.count == 1 && commands.playlistActions.count == 1
            _ = manager.select(b, source: firstSource)
            organization.onPrimary?()
            checks["remote-old-stop-never-stops-a-new-transaction"] = manager.stops == 0 && remoteWorkspace.requests.isEmpty
            let newest = manager.libraryPlaybackSequence.committed!
            composition.cardState = try WallpaperLibraryCardStateProjection(items: [content(remote)], relationships: relationships,
                committedReference: newest.reference, sequenceTicket: newest.ticket, runtimeTicket: newest.ticket)
            let play = composition.organization(item)!
            play.onPrimary?()
            checks["remote-play-requests-single-fixed-ref-without-borrowing-view-source"] = remoteWorkspace.requests == [remote]
            remoteWorkspace.presentation.selectionState.sessionID = UUID()
            play.onFavorite?(); play.onPrimary?()
            checks["remote-navigation-session-revokes-old-render-callbacks"] = commands.favoriteActions.count == 1 && remoteWorkspace.requests == [remote]
            let beforeReset = composition.organization(item)!
            remoteWorkspace.relationships = UserCollectionsSnapshot(revision: relationships.revision, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            beforeReset.onFavorite?(); beforeReset.onPrimary?()
            checks["remote-reset-epoch-revokes-old-render-callbacks"] = commands.favoriteActions.count == 1 && remoteWorkspace.requests == [remote]
            composition.downloadedContent[remote] = WallpaperContentItem(reference: remote, providerReference: remote, locator: .init(),
                title: "Not published", kind: .video, publishedAvailability: .remote, capabilities: [.inspect, .download],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            checks["remote-first-download-failure-or-task-does-not-invent-local-organization"] = composition.organization(item) == nil && composition.inspector(item) == nil
            composition.downloadedContent = [.init(provider: .steamWorkshop, sourceID: "\u{e9}"): content(remote)]
            checks["remote-provider-lookup-keeps-opaque-unicode-byte-identity"] = composition.organization(.init(id: "e\u{301}")) == nil
        }
        do {
            let ref = WallpaperReference(provider: .steamWorkshop, sourceID: "menu-download")
            let other = WallpaperReference(provider: .steamWorkshop, sourceID: "other-detail")
            let item = SteamWorkshopBrowserItem(id: ref.sourceID)
            let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            let source = try WallpaperPlaybackSequence.Snapshot(source: .single(ref), revision: 1,
                entries: [.init(reference: ref, runtime: .video, isPlayable: true)])
            let manager = WallpaperManager(), workspace = RemoteWorkspace(relationships)
            let commands = WallpaperLibraryCommands(manager, CommandWorkspace(manager, source))
            let composition = RemoteComposition(workspace, commands)
            composition.downloadedContent[ref] = content(ref)
            composition.cardState = try WallpaperLibraryCardStateProjection(items: [content(ref)], relationships: relationships,
                committedReference: nil, sequenceTicket: nil, runtimeTicket: nil)
            func invoke(_ menu: NSMenu, _ index: Int) {
                let entry = menu.items[index].submenu?.items.first ?? menu.items[index]
                _ = app.sendAction(entry.action!, to: entry.target, from: entry)
            }
            let menu = composition.menu(item)!
            composition.steam.selectedBrowserItem = .init(id: other.sourceID)
            invoke(menu, 0); invoke(menu, 1)
            checks["browser-context-organization-targets-clicked-download-without-opening-or-borrowing-detail"] =
                menu.items.map(\.title) == ["特别喜爱", "添加到列表"] && menu.items[1].submenu != nil
                && commands.favoriteActions == [[ref]] && commands.playlistActions == [[ref]]
                && composition.steam.selectedBrowserItem?.id == other.sourceID
            workspace.presentation.page = .videos
            invoke(menu, 0); invoke(menu, 1)
            checks["browser-context-held-menu-rejects-page-change"] = commands.favoriteActions.count == 1 && commands.playlistActions.count == 1
            workspace.presentation.page = .workshop
            let sessionMenu = composition.menu(item)!
            workspace.presentation.selectionState.sessionID = UUID()
            invoke(sessionMenu, 0); invoke(sessionMenu, 1)
            checks["browser-context-held-menu-rejects-new-page-session"] = commands.favoriteActions.count == 1 && commands.playlistActions.count == 1
            composition.steamBrowserContent.selectedItem = item
            let selected = composition.selectedBrowserOrganizationActions()!
            selected.onToggleFavorite(); selected.onChoosePlaylist(nil)
            checks["browser-main-menu-actions-project-grid-selection-without-borrowing-inspector"] = commands.favoriteActions == [[ref], [ref]]
                && commands.playlistActions == [[ref], [ref]] && composition.steam.selectedBrowserItem?.id == other.sourceID
            composition.steamBrowserContent.selectedItem = .init(id: other.sourceID)
            selected.onToggleFavorite(); selected.onChoosePlaylist(nil)
            checks["browser-main-menu-held-actions-cannot-retarget-later-source-selection"] = commands.favoriteActions.count == 2 && commands.playlistActions.count == 2
            commands.canOrganize = false
            let readOnly = composition.menu(item)!
            checks["browser-organization-menu-retains-disabled-items-during-read-only-recovery"] = readOnly.items.allSatisfy { !$0.isEnabled }
            commands.canOrganize = true
            composition.downloadedContent[ref] = WallpaperContentItem(reference: ref, providerReference: ref, locator: .init(),
                title: "Remote", kind: .video, publishedAvailability: .remote, capabilities: [.inspect, .download],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            composition.steamBrowserContent.selectedItem = item
            checks["browser-unpublished-selection-has-no-context-or-main-menu-organization"] = composition.menu(item) == nil && composition.selectedBrowserOrganizationActions() == nil
            composition.downloadedContent = [.init(provider: .steamWorkshop, sourceID: "\u{e9}"): content(ref)]
            checks["browser-menu-provider-identity-never-folds-opaque-unicode-ids"] = composition.menu(.init(id: "e\u{301}")) == nil
        }
        do {
            let ref = WallpaperReference(provider: .pixabay, sourceID: "7")
            let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [.init(reference: ref, favoritedAt: nil)], recent: [], aliases: [], locators: [])
            let source = try WallpaperPlaybackSequence.Snapshot(source: .single(ref), revision: 1,
                entries: [.init(reference: ref, runtime: .video, isPlayable: true)])
            let manager = WallpaperManager(), workspace = RemoteWorkspace(relationships)
            workspace.presentation.page = .pixabay
            let commands = WallpaperLibraryCommands(manager, CommandWorkspace(manager, source))
            let composition = RemoteComposition(workspace, commands)
            checks["pixabay-browser-id-alone-does-not-invent-local-organization"] = composition.pixabay(7) == nil
            composition.downloadedContent[ref] = content(ref)
            composition.cardState = try WallpaperLibraryCardStateProjection(items: [content(ref)], relationships: relationships,
                committedReference: nil, sequenceTicket: nil, runtimeTicket: nil)
            let actions = composition.pixabay(7)!
            actions.onToggleFavorite(); actions.onChoosePlaylist(nil); actions.onPrimary()
            checks["pixabay-local-organization-needs-no-steam-selection-or-account"] = actions.state.canFavorite
                && actions.state.canOrganize && commands.favoriteActions == [[ref]] && commands.playlistActions == [[ref]]
                && workspace.requests == [ref] && composition.steam.selectedBrowserItem == nil
            checks.merge(pixabayNativeMenuChecks(composition, commands: commands)) { _, new in new }
            let before = WallpaperLibraryQuery.resolverInitializationCount
            for _ in 0..<100 { _ = composition.pixabay(7) }
            checks["pixabay-organization-reuses-one-canonical-card-projection"] = WallpaperLibraryQuery.resolverInitializationCount == before
            composition.downloadedContent[ref] = .init(reference: ref, providerReference: ref, locator: .init(mediaKind: .video),
                title: "Offline", kind: .video, publishedAvailability: .unavailable, capabilities: [.inspect],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            let offline = composition.pixabay(7)!
            checks["pixabay-offline-favorite-removal-does-not-enable-add-to-playlist"] = offline.state.canFavorite
                && !offline.state.canOrganize && !offline.state.canPerformPrimary
            commands.canOrganize = false
            offline.onToggleFavorite()
            let busy = composition.pixabay(7)!
            checks["pixabay-current-readonly-revokes-even-held-favorite-action"] = !busy.state.canFavorite
                && !busy.state.canOrganize && commands.favoriteActions.count == 2
            commands.canOrganize = true
            workspace.presentation.page = .workshop
            actions.onToggleFavorite(); actions.onChoosePlaylist(nil); actions.onPrimary()
            checks["pixabay-held-browser-actions-do-not-run-after-page-change"] = commands.favoriteActions.count == 2
                && commands.playlistActions.count == 2 && workspace.requests == [ref]
        }
        do {
            let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            let workspace = RemoteWorkspace(relationships), composition = FileDropComposition(workspace)
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let file = URL(fileURLWithPath: "/fixture/external-import.mp4")
            board.writeObjects([file as NSURL])
            let drag = GridDropInfo(source: nil, board: board)
            for page in [WallpaperLibraryPage.videos, .images, .playlist(UUID())] {
                composition.configure(page)
                let before = composition.commands.imports.count
                checks["external-file-drop-accepts-only-bound-local-page-\(page.persistenceKey)"] = composition.grid.validate(drag) == .copy
                    && composition.grid.accept(drag) && composition.commands.imports.count == before + 1
                    && composition.commands.imports.last == [file]
            }
            let modalImportCount = composition.commands.imports.count
            composition.permitsInput = false
            checks["held-file-drop-refuses-new-input-from-a-covered-main-window"] = !composition.grid.accept(drag)
                && composition.commands.imports.count == modalImportCount
            composition.permitsInput = true
            for page in [WallpaperLibraryPage.downloads, .recent, .favorites, .playlists, .workshop, .pixabay] {
                composition.configure(page)
                let before = composition.commands.imports.count
                checks["external-file-drop-never-advertises-or-accepts-disallowed-page-\(page.persistenceKey)"] = composition.grid.validate(drag).isEmpty
                    && !composition.grid.accept(drag) && composition.commands.imports.count == before
            }
            composition.commands.canOrganize = false
            composition.configure(.videos)
            let before = composition.commands.imports.count
            checks["recovery-readonly-local-page-has-no-file-drop-binding"] = composition.grid.validate(drag).isEmpty
                && !composition.grid.accept(drag) && composition.commands.imports.count == before
            composition.commands.canOrganize = true
            composition.configure(.images)
            workspace.presentation.page = .playlist(UUID())
            checks["late-file-drop-cannot-redirect-to-a-new-import-capable-page"] = !composition.grid.accept(drag)
                && composition.commands.imports.count == before
            composition.configure(.videos)
            workspace.relationships = UserCollectionsSnapshot(revision: 2, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            checks["late-file-drop-cannot-use-a-new-reset-epoch"] = !composition.grid.accept(drag)
                && composition.commands.imports.count == before
            composition.configure(.videos)
            composition.commands.canOrganize = false
            checks["file-drop-native-acceptance-propagates-new-readonly-rejection"] = !composition.grid.accept(drag)
                && composition.commands.imports.count == before
            composition.commands.canOrganize = true
            composition.configure(.videos)
            let remoteBoard = NSPasteboard.withUniqueName()
            defer { remoteBoard.releaseGlobally() }
            remoteBoard.writeObjects([URL(string: "https://example.invalid/wallpaper.mp4")! as NSURL])
            let remote = GridDropInfo(source: nil, board: remoteBoard)
            checks["external-web-url-never-becomes-an-implicit-download"] = composition.grid.validate(remote).isEmpty
                && !composition.grid.accept(remote) && composition.commands.imports.count == before
        }
        func wait(_ condition:()->Bool) async ->Bool {
            let deadline=Date().addingTimeInterval(3)
            while !condition(),Date()<deadline {try? await Task.sleep(for:.milliseconds(2))}
            return condition()
        }
        func closeGroup(_ manager:UndoManager){while manager.groupingLevel > 0{manager.endUndoGrouping()}}
        // A07_BUSY_EVENTS_BEGIN
        do {
            let store=UserCollectionsStore(url:root.appendingPathComponent("undo.sqlite3"))
            let controller=UserCollectionsController(store:store,snapshot:try await store.snapshot())
            var errors=0,restores=0
            let undo=WallpaperLibraryRelationshipUndo(collections:controller,report:{_ in errors += 1},didRestore:{restores += 1})
            var busyStates: [Bool] = []
            let busySubscription = undo.undoManager.applyingChanges.sink { [weak manager = undo.undoManager] in
                guard let manager else { return }
                busyStates.append(manager.isApplyingTransaction)
            }
            undo.undoManager.isApplyingTransaction = false
            checks["unchanged-undo-busy-state-does-not-publish-invalidation"] = busyStates.isEmpty
            let id=try await controller.createPlaylist(name:"Original");closeGroup(undo.undoManager)
            checks["real-sqlite-ui-edit-registers-native-undo"] = undo.undoManager.canUndo && controller.snapshot.playlists.count == 1
            undo.undoManager.undo()
            checks["native-undo-cannot-be-reentered-while-transaction-pending"] = undo.undoManager.isApplyingTransaction && !undo.undoManager.canUndo && !undo.undoManager.canRedo
            checks["real-undo-publishes-busy-synchronously-before-await"] = busyStates == [true]
            _ = await wait{!undo.undoManager.isApplyingTransaction}
            checks["native-undo-applies-real-organization-transaction"] = controller.snapshot.playlists.isEmpty && restores == 1 && errors == 0 && undo.undoManager.canRedo
            checks["successful-undo-publishes-available-after-transaction"] = busyStates == [true, false]
            undo.undoManager.redo()
            checks["real-redo-publishes-busy-before-its-transaction"] = busyStates == [true, false, true]
            _ = await wait{!undo.undoManager.isApplyingTransaction}
            checks["native-redo-restores-exact-playlist-uuid"] = controller.snapshot.playlists.map(\.id) == [id] && restores == 2 && errors == 0
            checks["successful-redo-publishes-available-once"] = busyStates == [true, false, true, false]
            closeGroup(undo.undoManager)
            undo.undoManager.undo()
            try await controller.reset()
            _ = await wait{!undo.undoManager.isApplyingTransaction}
            let afterReset=restores
            _ = try await controller.createPlaylist(name:"After reset");closeGroup(undo.undoManager)
            checks["stale-undo-after-reset-is-silent-and-preserves-new-history"] = errors == 0 && restores == afterReset && undo.undoManager.canUndo
                && controller.snapshot.playlists.map(\.name) == ["After reset"]
            checks["reset-revoked-undo-still-publishes-available-on-exit"] = busyStates == [true, false, true, false, true, false]
                && !undo.undoManager.isApplyingTransaction
            busySubscription.cancel()
        }
        do {
            let store=UserCollectionsStore(url:root.appendingPathComponent("alias-conflict.sqlite3"))
            let controller=UserCollectionsController(store:store,snapshot:try await store.snapshot())
            var errors=0
            let undo=WallpaperLibraryRelationshipUndo(collections:controller,report:{_ in errors += 1},didRestore:{})
            var busyStates: [Bool] = []
            let busySubscription = undo.undoManager.applyingChanges.sink { [weak manager = undo.undoManager] in
                guard let manager else { return }
                busyStates.append(manager.isApplyingTransaction)
            }
            _ = try await controller.createPlaylist(name:"Do not overwrite");closeGroup(undo.undoManager)
            let alias=WallpaperReferenceAlias(alias:a,canonical:.init(provider:.steamWorkshop,sourceID:"canonical"),proof:.publishedDownload)
            _ = try await controller.perform(.linkAlias(alias,Date()))
            undo.undoManager.undo()
            checks["failing-undo-publishes-busy-synchronously"] = busyStates == [true]
            _ = await wait{!undo.undoManager.isApplyingTransaction}
            checks["undo-rejects-new-alias-proof-without-overwriting-real-state"] = errors == 1 && controller.snapshot.playlists.map(\.name) == ["Do not overwrite"]
                && controller.snapshot.aliases == [alias] && !undo.undoManager.canRedo && !undo.undoManager.canUndo
            checks["failed-undo-publishes-available-without-another-edit"] = busyStates == [true, false]
                && !undo.undoManager.isApplyingTransaction
            busySubscription.cancel()
        }
        // A07_BUSY_EVENTS_END
        do {
            let store = UserCollectionsStore(url: root.appendingPathComponent("favorite-policy.sqlite3"))
            let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
            let suite = "mwx.favorite.policy." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let view = RemovalWorkspace(controller, .init(videos: [content(a), content(b)], revision: 1), defaults: defaults)
            let commands = RemovalCommands(view)
            view.presentation.setSelection([a], focused: a)
            commands.toggleFavorite(expectingRemoval: false)
            checks["favorite-command-inserts-through-real-sqlite-and-presentation"] = await wait { controller.snapshot.favorites.map(\.reference) == [a] }
                && commands.admittedWrites == 1
            let missing = WallpaperContentItem(reference: a, providerReference: a, locator: .init(mediaKind: .video),
                title: "A", kind: .video, publishedAvailability: .unavailable, capabilities: [.inspect],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            view.publish(.init(videos: [missing, content(b)], revision: 2))
            view.presentation.setSelection([a, b], focused: a, isSelecting: true)
            let revision = controller.snapshot.revision
            let admitted = commands.admittedWrites
            commands.toggleFavorite()
            checks["mixed-offline-favorite-and-unfavorited-online-row-do-not-advertise-noop"] = !commands.canFavorite
                && !commands.favoriteActionState.canExecute && controller.snapshot.revision == revision && commands.admittedWrites == admitted
            view.presentation.setSelection([a], focused: a)
            checks["all-favorite-selection-can-remove-while-offline"] = commands.canFavorite
                && commands.favoriteActionState.isRemoving && commands.favoriteActionState.title == "取消特别喜爱"
            commands.toggleFavorite(expectingRemoval: false)
            checks["held-add-intent-does-not-turn-into-removal"] = controller.snapshot.revision == revision && commands.admittedWrites == admitted
            commands.toggleFavorite(expectingRemoval: true)
            checks["offline-favorite-removal-persists-through-real-store"] = await wait { controller.snapshot.favorites.isEmpty }
            view.presentation.setSelection([b], focused: b)
            commands.canOrganize = false
            let beforeReadOnly = commands.admittedWrites
            commands.toggleFavorite()
            checks["read-only-favorite-never-enqueues-a-write"] = !commands.canFavorite && controller.snapshot.favorites.isEmpty
                && commands.admittedWrites == beforeReadOnly
            commands.canOrganize = true
            commands.toggleFavorite(expectingRemoval: false)
            _ = await wait { controller.snapshot.favorites.map(\.reference) == [b] }
            let joined = controller.snapshot.revision
            let afterJoin = commands.admittedWrites
            commands.toggleFavorite(expectingRemoval: false)
            checks["rendered-add-does-not-toggle-newly-favorited-row-back-off"] = controller.snapshot.revision == joined
                && controller.snapshot.favorites.map(\.reference) == [b] && commands.admittedWrites == afterJoin
            let heldSelection = commands.makeFavoriteAction()!
            view.presentation.setSelection([a], focused: a)
            heldSelection()
            checks["actual-favorite-factory-rejects-later-selection-session"] = controller.snapshot.revision == joined
                && commands.admittedWrites == afterJoin
            view.presentation.setSelection([b], focused: b)
            let heldPage = commands.makeFavoriteAction()!
            view.presentation.switchPage(.favorites)
            heldPage()
            checks["actual-favorite-factory-rejects-later-page"] = controller.snapshot.revision == joined && commands.admittedWrites == afterJoin
            view.presentation.switchPage(.videos)
            view.presentation.setSelection([b], focused: b)
            let heldRemoval = commands.makeFavoriteAction()!
            try await controller.perform(.setFavorite(content(b).organizationItem, false, Date()))
            view.didEditMembers(of: .favorites)
            let removedRevision = controller.snapshot.revision
            heldRemoval()
            checks["actual-favorite-factory-never-inverts-its-rendered-intent"] = controller.snapshot.revision == removedRevision
                && controller.snapshot.favorites.isEmpty && commands.admittedWrites == afterJoin

        }
        do {
            let store = UserCollectionsStore(url: root.appendingPathComponent("recent-menu.sqlite3"))
            let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
            _ = try await controller.createPlaylist(name: "Preserve organization")
            controller.recordSuccessfulUse(a, locator: nil, sequence: 1)
            _ = await wait { !controller.snapshot.recent.isEmpty }
            let workspace = RecentWorkspace(controller), commands = RecentCommands(workspace)
            let organization = controller.snapshot.organizationState
            let menu = commands.makeRecentMenu()!, item = menu.items[0]
            _ = app.sendAction(item.action!, to: item.target, from: item)
            checks["recent-menu-opens-real-confirmation-before-clearing"] = RecentAlertProbe.alert?.buttons == ["清空最近使用", "取消"]
                && controller.snapshot.recent.map(\.reference) == [a]
            RecentAlertProbe.finish(.alertSecondButtonReturn)
            checks["recent-menu-cancel-preserves-current-records"] = controller.snapshot.recent.map(\.reference) == [a]
            _ = app.sendAction(item.action!, to: item.target, from: item)
            commands.canOrganize = false
            RecentAlertProbe.finish(.alertFirstButtonReturn)
            checks["recent-menu-rechecks-editing-admission-after-sheet"] = controller.snapshot.recent.map(\.reference) == [a] && workspace.edited.isEmpty
            commands.canOrganize = true
            _ = app.sendAction(item.action!, to: item.target, from: item)
            RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { controller.snapshot.recent.isEmpty }
            checks["recent-menu-clears-only-history-through-real-sqlite"] = controller.snapshot.recent.isEmpty
                && controller.snapshot.organizationState == organization && workspace.presentation.errors == 0
            checks["recent-menu-remains-present-but-disabled-for-empty-history"] = commands.makeRecentMenu()?.items[0].isEnabled == false
            controller.recordSuccessfulUse(b, locator: nil, sequence: 2)
            _ = await wait { controller.snapshot.recent.map(\.reference) == [b] }
            checks["recent-menu-clear-does-not-block-later-successful-play"] = controller.snapshot.recent.map(\.reference) == [b]
            let oldMenu = commands.makeRecentMenu()!, oldItem = oldMenu.items[0]
            try await controller.reset()
            controller.recordSuccessfulUse(a, locator: nil, sequence: 1)
            _ = await wait { controller.snapshot.recent.map(\.reference) == [a] }
            RecentAlertProbe.alert = nil
            _ = app.sendAction(oldItem.action!, to: oldItem.target, from: oldItem)
            checks["old-recent-menu-cannot-borrow-new-reset-epoch"] = RecentAlertProbe.alert == nil && controller.snapshot.recent.map(\.reference) == [a]
            workspace.presentation.page = .videos
            checks["recent-menu-is-not-created-for-unrelated-page"] = commands.makeRecentMenu() == nil
        }
        do {
            let store = UserCollectionsStore(url: root.appendingPathComponent("removal.sqlite3"))
            let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
            let suite = "mwx.command.removal." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let steam = WallpaperReference(provider: .steamWorkshop, sourceID: "one")
            let pixabay = WallpaperReference(provider: .pixabay, sourceID: "two")
            let last = WallpaperReference(provider: .pixabay, sourceID: "three")
            let steamURL = root.appendingPathComponent("steam_one.mp4")
            let firstURL = root.appendingPathComponent("online_two.mp4"), lastURL = root.appendingPathComponent("online_three.mp4")
            try Data([1]).write(to: steamURL); try Data([2]).write(to: firstURL); try Data([3]).write(to: lastURL)
            func row(_ ref: WallpaperReference, _ title: String, _ url: URL? = nil) -> WallpaperContentItem {
                .init(reference: ref, providerReference: ref, locator: .init(path: url?.path, mediaKind: .video),
                    title: title, kind: .video, publishedAvailability: .available, capabilities: [.play, .organize],
                    metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            }
            let rows = [row(steam, "A", steamURL), row(pixabay, "B", firstURL), row(last, "C", lastURL)]
            func workspace(_ catalog: WallpaperLibraryCatalog, page: WallpaperLibraryPage) -> RemovalWorkspace {
                defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
                let view = RemovalWorkspace(controller, catalog, defaults: defaults)
                view.presentation.switchPage(page)
                view.presentation.setQueryState(.init(sort: .name))
                return view
            }
            let old = WallpaperLibraryCatalog(downloads: rows, revision: 100)
            let view = workspace(old, page: .downloads), commands = RemovalCommands(view)
            view.presentation.setSelection([steam, pixabay], focused: steam, isSelecting: true)
            commands.pixabay.failingNames = [firstURL.lastPathComponent]
            commands.remove()
            let sourceOption = RecentAlertProbe.alert?.suppressionButton
            checks["compact-removal-keeps-scope-count-short-actions-and-natural-checkbox-width"] = RecentAlertProbe.alert?.buttons == ["移除", "取消"]
                && RecentAlertProbe.alert?.title == "从我的下载移除 2 项？"
                && RecentAlertProbe.alert?.message == "移除下载项目及最近使用记录，源文件和其他列表保留。勾选会删除源文件，无法撤销。"
                && sourceOption?.alignment == .left && sourceOption?.state == .off
                && (sourceOption?.frame.width ?? 0) > 0 && (sourceOption?.frame.width ?? 320) < 320
            checks["delete-confirmation-defers-source-writes-and-preserves-fixed-targets"] = commands.steam.requested.isEmpty
                && commands.pixabay.requested.isEmpty && FileManager.default.fileExists(atPath: firstURL.path)
                && (RecentAlertProbe.alert?.suppressionButton)?.state == .off
            (RecentAlertProbe.alert?.suppressionButton)?.state = .on
            RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { commands.steam.requested == [steam.sourceID] }
            view.publish(.init(downloads: Array(rows.dropFirst()), revision: 101))
            commands.steam.finish([steam.sourceID: true])
            _ = await wait { view.presentation.selectionState.references == [pixabay] && view.catalog.refreshes == 1 && !view.edited.isEmpty }
            checks["mixed-delete-dispatches-to-original-source-owners"] = commands.steam.requested == [steam.sourceID]
                && commands.pixabay.requested == [firstURL] && FileManager.default.fileExists(atPath: firstURL.path)
            checks["actual-mixed-delete-receipt-retains-failure-selection-mode-and-file"] = view.presentation.selectionState.references == [pixabay]
                && view.presentation.selectionState.focusedReference == pixabay && view.presentation.selectionState.isSelecting
                && FileManager.default.fileExists(atPath: firstURL.path)
                && RecentAlertProbe.alert?.message.contains(firstURL.lastPathComponent) == true && view.catalog.refreshes == 1
            let stable = view.presentation.selectionState
            view.presentation.update(catalog: old, relationships: controller.snapshot)
            checks["old-projection-after-mixed-delete-cannot-revive-success-or-clear-failure"] = view.presentation.queryResult.items.map(\.reference) == [pixabay, last]
                && view.presentation.selectionState == stable
            let priorEdits = view.edited.count
            commands.remove(); (RecentAlertProbe.alert?.suppressionButton)?.state = .on
            RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { view.edited.count > priorEdits }
            checks["all-source-delete-failures-leave-current-selection-and-bytes-unchanged"] = view.presentation.selectionState == stable
                && FileManager.default.fileExists(atPath: firstURL.path)
            commands.pixabay.failingNames = []
            view.presentation.setSelection([pixabay], focused: pixabay)
            commands.remove(); (RecentAlertProbe.alert?.suppressionButton)?.state = .on
            RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { view.presentation.selectionState.references == [last] }
            checks["successful-source-delete-uses-real-store-exclusion-projection"] = !FileManager.default.fileExists(atPath: firstURL.path)
                && controller.snapshot.excludedLibraryReferences.contains { $0.reference == pixabay }
            view.publish(.init(downloads: [rows[2]], revision: 102))
            checks["successful-single-delete-restores-adjacent-card-through-real-commands"] = view.presentation.queryResult.items.map(\.reference) == [last]
                && view.presentation.selectionState.references == [last] && view.presentation.selectionState.focusedReference == last
                && !view.presentation.selectionState.isSelecting && FileManager.default.fileExists(atPath: lastURL.path)
            commands.remove(); RecentAlertProbe.finish(.alertSecondButtonReturn)
            checks["cancelled-delete-keeps-source-and-current-adjacent-selection"] = FileManager.default.fileExists(atPath: lastURL.path)
                && view.presentation.selectionState.references == [last]
                && (RecentAlertProbe.alert?.suppressionButton)?.state == .off
            let priorSteam = commands.steam.requested, priorPixabay = commands.pixabay.requested
            commands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { view.presentation.queryResult.items.isEmpty }
            let keptDownloadBytes = try Data(contentsOf: lastURL)
            checks["default-off-download-removal-persists-without-source-delete"] = controller.snapshot.excludedLibraryReferences.contains { $0.reference == last }
                && keptDownloadBytes == Data([3]) && commands.steam.requested == priorSteam && commands.pixabay.requested == priorPixabay

            let va = WallpaperReference(provider: .videoLibrary, sourceID: "video-A")
            let vb = WallpaperReference(provider: .videoLibrary, sourceID: "video-B")
            let videoAURL = root.appendingPathComponent("video_a.mp4"), videoBURL = root.appendingPathComponent("video_b.mp4")
            try Data([4]).write(to: videoAURL); try Data([5]).write(to: videoBURL)
            let videos = [row(va, "A", videoAURL), row(vb, "B", videoBURL)]
            let videoView = workspace(.init(videos: videos, revision: 200), page: .videos)
            let videoCommands = RemovalCommands(videoView)
            videoCommands.manager.wallpapers = [.init(id: va.sourceID, path: videoAURL.path), .init(id: vb.sourceID, path: videoBURL.path)]
            videoView.presentation.setSelection([va], focused: va)
            videoCommands.remove(); (RecentAlertProbe.alert?.suppressionButton)?.state = .on
            RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { videoCommands.manager.requested == [va.sourceID] }
            videoView.publish(.init(videos: [videos[1]], revision: 201))
            videoCommands.manager.finish([va.sourceID])
            _ = await wait { videoView.presentation.selectionState.references == [vb] }
            checks["video-source-completion-uses-same-post-pruning-receipt"] = videoCommands.manager.requested == [va.sourceID]
                && videoView.presentation.selectionState.references == [vb]
            let ia = WallpaperReference(provider: .staticImageLibrary, sourceID: "image-A")
            let ib = WallpaperReference(provider: .staticImageLibrary, sourceID: "image-B")
            let imageAURL = root.appendingPathComponent("image_a.png"), imageBURL = root.appendingPathComponent("image_b.png")
            try Data([6]).write(to: imageAURL); try Data([7]).write(to: imageBURL)
            let imageRows = [row(ia, "A", imageAURL), row(ib, "B", imageBURL)]
            let imageView = workspace(.init(images: imageRows, revision: 300), page: .images)
            let imageCommands = RemovalCommands(imageView)
            imageCommands.images.wallpapers = [.init(id: ia.sourceID, path: imageAURL.path), .init(id: ib.sourceID, path: imageBURL.path)]
            imageView.presentation.setSelection([ia], focused: ia)
            imageCommands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { imageView.presentation.selectionState.references == [ib] }
            imageView.publish(.init(images: imageRows, revision: 301))
            let keptImageBytes = try Data(contentsOf: imageAURL)
            checks["image-library-exclusion-uses-same-success-receipt"] = imageView.presentation.selectionState.references == [ib]
                && keptImageBytes == Data([6]) && imageCommands.images.wallpapers.count == 2

            let id = try await controller.createPlaylist(name: "Deletion transaction")
            try await controller.perform(.addMembers(id, videos.map(\.organizationItem), Date()))
            let listView = workspace(.init(videos: videos, revision: 400), page: .playlist(id))
            let listCommands = RemovalCommands(listView)
            listView.presentation.setSelection([va], focused: va)
            listCommands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { controller.snapshot.members.filter { $0.playlistID == id }.map(\.reference) == [vb] && !listView.edited.isEmpty }
            checks["playlist-store-transaction-uses-same-fixed-order-removal-receipt"] = listView.presentation.selectionState.references == [vb]
                && listView.edited == [.playlist(id)] && listCommands.manager.requested.isEmpty
            _ = try await controller.perform([.setFavorite(videos[0].organizationItem, true, Date()), .setFavorite(videos[1].organizationItem, true, Date())])
            let favoritesView = workspace(.init(videos: videos, revision: 500), page: .favorites)
            let favoritesCommands = RemovalCommands(favoritesView)
            favoritesView.presentation.setSelection([va], focused: va)
            favoritesCommands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { controller.snapshot.favorites.map(\.reference) == [vb] && !favoritesView.edited.isEmpty }
            checks["favorite-store-removal-uses-same-receipt-without-source-deletion"] = favoritesView.presentation.selectionState.references == [vb]
                && favoritesCommands.manager.requested.isEmpty && favoritesCommands.pixabay.requested.isEmpty
            controller.recordSuccessfulUse(vb, locator: nil, sequence: 1)
            controller.recordSuccessfulUse(va, locator: nil, sequence: 2)
            _ = await wait { controller.snapshot.recent.map(\.reference) == [va, vb] }
            let recentView = workspace(.init(videos: videos, revision: 600), page: .recent)
            let recentCommands = RemovalCommands(recentView)
            recentView.presentation.setSelection([va], focused: va)
            recentCommands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
            _ = await wait { controller.snapshot.recent.map(\.reference) == [vb] && !recentView.edited.isEmpty }
            checks["recent-store-removal-uses-same-receipt-and-preserves-other-relations"] = recentView.presentation.selectionState.references == [vb]
                && controller.snapshot.members.filter { $0.playlistID == id }.map(\.reference) == [vb]
                && controller.snapshot.favorites.map(\.reference) == [vb]
            checks.merge(try await runOnlineImageRemovalChecks(root: root, controller: controller,
                workspace: { workspace($0, page: $1) }), uniquingKeysWith: { _, newer in newer })
        }
        checks.merge(try await runLibraryRestorationChecks(root: root), uniquingKeysWith: { _, newer in newer })
        checks.merge(try await runOrganizationCompletionChecks(root: root), uniquingKeysWith: { _, newer in newer })
        checks.merge(try await runRecentSidebarCommandChecks(root: root), uniquingKeysWith: { _, newer in newer })
        checks.merge(try await steamNavigationActionChecks(app: app)) { _, new in new }
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
