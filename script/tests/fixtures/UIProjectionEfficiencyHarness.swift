// Production bodies are inserted by test_ui_projection_efficiency.py. Services,
// grid rendering, and diffable application are recording boundaries; Combine,
// dispatch delivery, NSViewController replacement, snapshots, and filesystem
// admission use the platform implementations. No private user library is read.
import AppKit
import Combine
import Foundation

enum Category: Hashable { case myWallpapers, favorites, recentlyUsed, tags, settings }
enum WallpaperSortMode { case none, name, size, dateAdded }
struct SortState { var mode: WallpaperSortMode = .none; var ascending = true }
struct WallpaperSettings { var sortMode: WallpaperSortMode = .none; var sortAscending = true }
struct VideoWallpaper: Equatable {
    let id: String
    var title: String
    var tags: [String] = []
    var isFavorite = false
    var fileSize: Int64?
    var lastUsed = Date.distantPast
    var displayTitle: String { title }
}
enum SILSortMode: CaseIterable { case none, name, lastUsed, fileSize, addedAt }
struct SILSortState { var mode: SILSortMode = .none; var ascending = true }
struct SILWallpaper: Equatable {
    let id: String
    var title: String
    var tags: [String] = []
    var path: String { "/fixture/" + id }
    var fileSize: Int64?
    var lastUsed = Date.distantPast
    var addedAt = Date.distantPast
}
@MainActor final class WallpaperManager: ObservableObject {
    @Published var wallpapers: [VideoWallpaper] = []
    @Published var recentlyUsedWallpapers: [VideoWallpaper] = []
    @Published var searchQuery = ""
    @Published var perSelectionSortStates: [String: SortState] = [:]
    @Published var inspectedWallpaperID: String?
    var tags: [String] = []
    var settings = WallpaperSettings()
    var derivations = 0
    var favoriteWallpapers: [VideoWallpaper] { wallpapers.filter(\.isFavorite) }
    // VIDEO_PROJECTION_METHODS
}
@MainActor final class SILService: ObservableObject {
    static let shared = SILService()
    @Published var wallpapers: [SILWallpaper] = []
    @Published var selectedID: String?
    @Published var selectedIDs: Set<String> = []
    @Published var isMultiSelectMode = false
    @Published var gridZoomOffset = 0
    @Published var sortState = SILSortState()
    @Published var searchQuery = ""
    @Published var inspectedWallpaperID: String?
    var silTags: [String] = []
    var derivations = 0
    var comparisons = 0
    var currentContextTag: String?
    var visibleGridColumnCount = 4
    var inspectorSyncs = 0
    func syncSelectedWallpaperInspectorIfNeeded() { inspectorSyncs += 1 }
    // SIL_PROJECTION_METHODS
}
struct OnlineLibraryVideoItem: Equatable { let id: Int; var title: String = "fixture" }
@MainActor final class OnlineLibraryService: ObservableObject {
    static let shared = OnlineLibraryService()
    static var downloadDirectory = URL(fileURLWithPath: "/not-configured")
    @Published var items: [OnlineLibraryVideoItem] = []
    @Published var downloadingIDs: Set<Int> = []
    @Published var downloadedIDs: Set<Int> = []
    @Published var downloadProgressByID: [Int: Double] = [:]
    @Published var zoomOffset = 0
    @Published var inspectedDownloadedItemID: Int?
    var prioritizedWindows: [[Int]] = []
    func prioritizeVisibleItemIDs(_ ids: [Int], maxPixelSize: Int = 512) { prioritizedWindows.append(ids) }
    func thumbnailPrefetchNeedsRefresh() -> Bool { false }
    func cancelThumbnailPrefetch() {}
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var downloadsCount = 0
}
enum ModuleIdentifier: String { case onlineLibrary }
extension Notification.Name {
    static let inspectorHostDidPresent = Self("fixture.inspector.present")
    static let inspectorHostDidClose = Self("fixture.inspector.close")
    static let moduleDidBecomeActive = Self("fixture.module.active")
}
enum SelectedItem: Hashable {
    case category(Category), tag(String), silTag(String)
    case staticImageLibrary, onlineLibrary, onlineDownloads
    case steamWorkshop, steamSubscribed, steamDownloads
    @MainActor var selectionContext: WallpaperSelectionContext {
        switch self {
        case .category(let category): return .category(category)
        case .tag(let tag): return .tag(tag)
        default: return .category(.myWallpapers)
        }
    }
    var isInVideoLibraryContext: Bool {
        switch self { case .category, .tag: return true; default: return false }
    }
    var isInStaticImageLibraryContext: Bool {
        switch self { case .staticImageLibrary, .silTag: return true; default: return false }
    }
}
@MainActor enum WallpaperSelectionContext: Equatable {
    case category(Category), tag(String)
    var scrollPersistenceKey: String {
        switch self {
        case .category(let category): return "category.\(category)"
        case .tag(let tag): return "tag.\(tag)"
        }
    }
    // SELECTION_SOURCE
}
@MainActor final class AppKitLibraryGridContainerView: NSView {
    let wallpaperManager: WallpaperManager
    var outputs: [[VideoWallpaper]] = []
    init(wallpaperManager: WallpaperManager, animatesReorder: Bool, animatesInsertDelete: Bool) {
        self.wallpaperManager = wallpaperManager
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    func update(wallpapers: [VideoWallpaper]) {
        outputs.append(wallpaperManager.filterWallpapers(wallpapers,
            usingNormalizedQuery: wallpaperManager.normalizedSearchQuery))
    }
}
@MainActor final class SILGridContainerView: NSView {
    var currentSILTag: String?
    var outputs: [[SILWallpaper]] = []
    func update(wallpapers: [SILWallpaper]) { outputs.append(wallpapers) }
    func invalidateLayout() {}
    func scheduleSelectionVisualUpdate() {}
    func refreshVisibleItemsIfNeeded(isMultiSelectMode: Bool) {}
}
@MainActor final class StaticViewController: NSViewController {
    init(contentView: NSView) { super.init(nibName: nil, bundle: nil); view = contentView }
    required init?(coder: NSCoder) { nil }
}
typealias OnlineLibraryBrowserView = NSView
typealias AppKitOLDownloadsContainerView = NSView
typealias AppKitSteamWorkshopBrowserView = NSView
typealias AppKitSteamWorkshopDownloadsView = NSView

@MainActor final class ShellProbe: NSViewController {
    let wallpaperManager: WallpaperManager
    var hostedController: NSViewController?
    var currentSelectedItem: SelectedItem?
    var currentVideoGridView: AppKitLibraryGridContainerView?
    var currentSILGridView: SILGridContainerView?
    var currentSILTag: String?
    var cancellables = Set<AnyCancellable>()
    var pendingVideoGridUpdate = false
    var pendingSILGridUpdate = false
    init(_ manager: WallpaperManager) {
        wallpaperManager = manager
        super.init(nibName: nil, bundle: nil)
        observeVideoLibraryState()
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView() }
    func closeOnlineDownloadsInspectorIfNeeded(leavingFor: SelectedItem) {}
    func syncVideoInspectorIfNeeded() {}
    func syncSILInspectorIfNeeded() {}
    func syncOnlineDownloadsInspectorIfNeeded() {}
    func mountVideoInspectorContentIfNeeded(_ notification: Notification) {}
    func clearVideoInspectorIfNeeded(_ notification: Notification) {}
    func mountSILInspectorContentIfNeeded(_ notification: Notification) {}
    func clearSILInspectorIfNeeded(_ notification: Notification) {}
    func mountOnlineDownloadsInspectorContentIfNeeded(_ notification: Notification) {}
    func clearOnlineDownloadsInspectorIfNeeded(_ notification: Notification) {}
    // SHELL_METHODS
}
@MainActor final class SidebarProbe {
    let wallpaperManager: WallpaperManager
    var liveTagOrder: [String]?
    var rootNodes: [SidebarNode] = []
    init(_ manager: WallpaperManager) { wallpaperManager = manager }
    // SIDEBAR_METHODS
}

@MainActor final class AppKitOLBrowserItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("OnlineProbeCard")
    struct State: Equatable {
        let id: Int
        let title: String
        let downloading: Bool
        let downloaded: Bool
        let progress: Double?
    }
    var states: [State] = []
    var downloadAction: (() -> Void)?
    var wallpaperAction: (() -> Void)?
    func configure(item: OnlineLibraryVideoItem, isDownloading: Bool, isDownloaded: Bool,
                   downloadProgress: Double?, thumbnailDemandActive: Bool? = nil, onDownload: @escaping () -> Void,
                   onSetAsWallpaper: @escaping () -> Void) {
        states.append(State(id: item.id, title: item.title, downloading: isDownloading,
            downloaded: isDownloaded, progress: downloadProgress))
        downloadAction = onDownload
        wallpaperAction = onSetAsWallpaper
    }
}
@MainActor final class RecordingCollection {
    var visible: Set<IndexPath> = []
    var cells: [IndexPath: NSCollectionViewItem] = [:]
    func makeItem(withIdentifier: NSUserInterfaceItemIdentifier, for indexPath: IndexPath) -> NSCollectionViewItem { AppKitOLBrowserItem() }
    func indexPathsForVisibleItems() -> Set<IndexPath> { visible }
    func item(at indexPath: IndexPath) -> NSCollectionViewItem? { cells[indexPath] }
    func cell(_ index: Int) -> AppKitOLBrowserItem {
        cells[IndexPath(item: index, section: 0)] as! AppKitOLBrowserItem
    }
}
@MainActor final class RecordingDataSource<Section: Hashable, Item: Hashable> {
    let collectionView: RecordingCollection
    let provider: (RecordingCollection, IndexPath, Item) -> NSCollectionViewItem?
    var identifiers: [Item] = []
    init(collectionView: RecordingCollection,
         itemProvider: @escaping (RecordingCollection, IndexPath, Item) -> NSCollectionViewItem?) {
        self.collectionView = collectionView
        provider = itemProvider
    }
    func apply(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, animatingDifferences: Bool) {
        identifiers = snapshot.itemIdentifiers
        materializeVisible()
    }
    func materializeVisible() {
        for indexPath in collectionView.visible where indexPath.item < identifiers.count {
            collectionView.cells[indexPath] = provider(collectionView, indexPath, identifiers[indexPath.item])
        }
    }
}
@MainActor final class OnlineProbe {
    enum Section { case main }
    let service: OnlineLibraryService
    var onDownload: (OnlineLibraryVideoItem) -> Void = { _ in }
    var onSetAsWallpaper: (OnlineLibraryVideoItem) -> Void = { _ in }
    var cancellables = Set<AnyCancellable>()
    var orderedIDs: [Int] = []
    var itemsByID: [Int: OnlineLibraryVideoItem] = [:]
    var lastConsumedProgress: [Int: Double] = [:]
    var lastPrioritizedVisibleIDs: [Int]?
    var lastPrioritizedPixelLimit = 0
    var isThumbnailDemandUpdateScheduled = false
    var canLoadThumbnails = true
    let window: NSWindow? = nil
    let flowLayout = NSCollectionViewFlowLayout()
    var lastLoadedCount = 0
    let scrollView = NSScrollView()
    let collectionView = RecordingCollection()
    // ONLINE_PROVIDER
    init(_ service: OnlineLibraryService) { self.service = service }
    func bind() {
        // ONLINE_BINDINGS
    }
    func scheduleLayoutItemSizeUpdate() {}
    func checkLoadMore() {}
    func requestFocus() {}
    func pauseThumbnailDemand() { service.cancelThumbnailPrefetch() }
    // ONLINE_METHODS
}

enum GridThumbnailDecoder {
    static func pixelLimit(width: CGFloat, scale: CGFloat) -> Int { 512 }
}

@main struct UIProjectionEfficiencyHarness {
    @MainActor static func pump(_ duration: TimeInterval = 0.04) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let downloadRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
        OnlineLibraryService.downloadDirectory = downloadRoot
        var checks: [String: Bool] = [:]
        testShell(&checks)
        testSidebar(&checks)
        testSILTagProjection(&checks)
        try testOnline(&checks)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }

    @MainActor static func testShell(_ checks: inout [String: Bool]) {
        let manager = WallpaperManager()
        let sil = SILService.shared
        manager.wallpapers = [VideoWallpaper(id: "b", title: "Beta"), VideoWallpaper(id: "a", title: "Alpha")]
        let shell = ShellProbe(manager)
        shell.update(selectedItem: .category(.myWallpapers))
        let initial = shell.currentVideoGridView!
        checks["shellInitialConstructionIsSynchronous"] = initial.outputs.last?.map(\.id) == ["b", "a"]
        pump()
        manager.derivations = 0
        sil.derivations = 0
        let beforeInactiveSIL = initial.outputs.count
        for index in 1...20 {
            sil.wallpapers = [SILWallpaper(id: "inactive", title: "Still \(index)")]
            sil.searchQuery = "still \(index)"
            sil.sortState = SILSortState(mode: .name, ascending: index % 2 == 0)
        }
        pump()
        checks["shellInactiveSILBurstDoesNotDeriveActiveVideo"] = manager.derivations == 0
            && sil.derivations == 0 && initial.outputs.count == beforeInactiveSIL
        manager.derivations = 0
        let previousCount = initial.outputs.count
        for index in 1...50 {
            manager.wallpapers[0].fileSize = Int64(index)
            manager.wallpapers[0].title = "Beta \(index)"
            manager.recentlyUsedWallpapers = Array(manager.wallpapers.reversed())
        }
        manager.searchQuery = "beta"
        manager.perSelectionSortStates = ["category.myWallpapers": SortState(mode: .name, ascending: true)]
        // Exercise all seven production publisher bindings in the same turn.
        sil.wallpapers = [SILWallpaper(id: "s", title: "Still")]
        sil.searchQuery = "still"
        sil.sortState = SILSortState(mode: .name, ascending: true)
        checks["shellBurstDoesNotDeriveSynchronously"] = manager.derivations == 0
        pump()
        checks["shellBurstDerivesLatestVideoExactlyOnce"] = manager.derivations == 1
            && initial.outputs.count == previousCount + 1
            && initial.outputs.last == [manager.wallpapers[0]]
        manager.searchQuery = ""
        manager.wallpapers[0].tags = ["blue"]
        manager.wallpapers[1].tags = ["red"]
        shell.update(selectedItem: .tag("red"))
        let red = shell.currentVideoGridView!
        shell.update(selectedItem: .tag("blue"))
        let blue = shell.currentVideoGridView!
        let redCount = red.outputs.count
        let blueCount = blue.outputs.count
        pump()
        checks["shellQueuedRefreshUsesLatestVideoTagAndPreservesRetiredGrid"] = red.outputs.count == redCount
            && blue.outputs.count == blueCount + 1 && blue.outputs.last?.map(\.id) == ["b"]
        manager.wallpapers[0].title = "Latest"
        let videoCount = blue.outputs.count
        sil.searchQuery = ""
        sil.wallpapers = [SILWallpaper(id: "x", title: "X", tags: ["old"]),
            SILWallpaper(id: "y", title: "Y", tags: ["new"])]
        shell.update(selectedItem: .silTag("old"))
        let oldSIL = shell.currentSILGridView!
        shell.update(selectedItem: .silTag("new"))
        let newSIL = shell.currentSILGridView!
        let oldCount = oldSIL.outputs.count
        let newCount = newSIL.outputs.count
        sil.derivations = 0
        pump()
        checks["shellModuleAndSILTagSwitchCannotApplyStaleProjection"] = blue.outputs.count == videoCount
            && oldSIL.outputs.count == oldCount && newSIL.outputs.count == newCount + 1
            && newSIL.outputs.last?.map(\.id) == ["y"] && sil.derivations == 1
        manager.derivations = 0
        sil.derivations = 0
        let beforeInactiveVideo = newSIL.outputs.count
        for index in 1...20 {
            manager.wallpapers[0].fileSize = Int64(index)
            manager.recentlyUsedWallpapers = manager.wallpapers
            manager.searchQuery = "inactive \(index)"
            manager.perSelectionSortStates = [:]
        }
        pump()
        checks["shellInactiveVideoBurstDoesNotDeriveActiveSIL"] = manager.derivations == 0
            && sil.derivations == 0 && newSIL.outputs.count == beforeInactiveVideo
        manager.wallpapers[0].title = "Changed again"
        shell.update(selectedItem: .onlineLibrary)
        let retiredCount = newSIL.outputs.count
        manager.derivations = 0
        sil.derivations = 0
        pump()
        checks["shellNonLibraryModuleDoesNotDeriveQueuedLibraryState"] = manager.derivations == 0
            && sil.derivations == 0 && newSIL.outputs.count == retiredCount
        manager.searchQuery = ""
        sil.searchQuery = ""
        pump()
        shell.update(selectedItem: .category(.myWallpapers))
        let pendingVideo = shell.currentVideoGridView!
        let pendingVideoCount = pendingVideo.outputs.count
        // Drive this precise transition through the production scheduler so it
        // cannot depend on the run loop's interleaving of two receive(on:) sinks.
        // Queue the real SIL publication ahead of the dispatch; after switching,
        // its sink joins the already-pending source flags without adding a turn.
        sil.wallpapers[1].title = "Y final"
        shell.scheduleCurrentLibraryGridUpdate(forVideoLibrary: true)
        shell.update(selectedItem: .silTag("new"))
        let pendingSIL = shell.currentSILGridView!
        let pendingSILCount = pendingSIL.outputs.count
        shell.scheduleCurrentLibraryGridUpdate(forVideoLibrary: false)
        checks["shellPendingVideoToSILTransitionKeepsBothDirtySources"] = shell.pendingVideoGridUpdate
            && shell.pendingSILGridUpdate
        manager.derivations = 0
        sil.derivations = 0
        pump()
        checks["shellSharedPendingDispatchConsumesLatestSILWithoutLosingItsEvent"] = manager.derivations == 0
            && sil.derivations == 1 && pendingVideo.outputs.count == pendingVideoCount
            && pendingSIL.outputs.count == pendingSILCount + 1
            && pendingSIL.outputs.last?.map(\.title) == ["Y final"]
        var transient: ShellProbe? = ShellProbe(manager)
        transient?.update(selectedItem: .category(.myWallpapers))
        transient?.scheduleCurrentLibraryGridUpdate(forVideoLibrary: true)
        weak var weakShell = transient
        transient = nil
        checks["shellPendingDispatchAndCombineDoNotRetainController"] = weakShell == nil
        pump()
        checks["shellReleasedControllerRemainsReleasedAfterQueuedDelivery"] = weakShell == nil
    }

    @MainActor static func testSidebar(_ checks: inout [String: Bool]) {
        let manager = WallpaperManager()
        manager.tags = ["v", "empty"]
        manager.wallpapers = [VideoWallpaper(id: "v", title: "Video", tags: ["v"], isFavorite: true)]
        let sil = SILService.shared
        sil.silTags = ["blue", "", "empty", "blue"]
        sil.wallpapers = [SILWallpaper(id: "1", title: "One", tags: ["blue", "blue", "", "hidden"]),
            SILWallpaper(id: "2", title: "Two", tags: ["blue", "hidden"]),
            SILWallpaper(id: "3", title: "Three", tags: [])]
        OnlineLibraryService.shared.downloadedIDs = [1, 2]
        SteamWorkshopService.shared.downloadsCount = 3
        let sidebar = SidebarProbe(manager)
        let signature = sidebar.makeSidebarSnapshotSignature()
        var originalCounts: [String: Int] = [:]
        for tag in sil.silTags { originalCounts[tag] = sil.wallpapers.filter { $0.tags.contains(tag) }.count }
        checks["sidebarSinglePassMatchesFilterContainsIncludingDuplicateAndEmptyTags"] = signature.silTagCounts == originalCounts
            && signature.silTagCounts == ["blue": 2, "": 1, "empty": 0]
            && signature.silTagCounts["hidden"] == nil
        checks["sidebarVideoFavoriteAndTagCountsRemainEquivalent"] = signature.favoriteCount == 1
            && signature.tagCounts == ["v": 1] && signature.wallpaperCount == 1
        // A prepared snapshot must remain the sole count authority during rebuild.
        sil.wallpapers = []
        sil.silTags = ["new live tag"]
        OnlineLibraryService.shared.downloadedIDs = []
        SteamWorkshopService.shared.downloadsCount = 99
        sidebar.rebuildNodes(using: signature, tagOrder: manager.tags)
        let images = sidebar.rootNodes.first { if case .section(.images) = $0.kind { return true }; return false }!
        let online = sidebar.rootNodes.first { if case .section(.online) = $0.kind { return true }; return false }!
        let steam = sidebar.rootNodes.first { if case .section(.steam) = $0.kind { return true }; return false }!
        checks["sidebarRebuildConsumesSnapshotTagOrderAndCounts"] = images.children.map(\.title) == ["我的图片", "blue", "", "empty", "blue"]
            && images.children.map(\.count) == [3, 2, 1, 0, 2]
        checks["sidebarRebuildUsesSnapshotOnlineAndSteamCounts"] = online.children.last?.count == 2
            && steam.children.last?.count == 3
        let empty = sidebar.makeSidebarSnapshotSignature()
        checks["sidebarEmptyLibraryKeepsDeclaredZeroCountTags"] = empty.silTagCounts == ["new live tag": 0]
            && empty.silWallpapersCount == 0
    }

    /// Independent reference for the previous product order: search the whole
    /// library, sort it, then let the tag page filter that sorted result. Keep
    /// this oracle outside the production helper to catch changed tie ordering.
    @MainActor static func legacySortedAll(_ service: SILService) -> [SILWallpaper] {
        let query = service.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? service.wallpapers : service.wallpapers.filter {
            $0.title.lowercased().contains(query) || $0.path.lowercased().contains(query)
        }
        guard service.sortState.mode != .none else { return filtered }
        return filtered.sorted { a, b in
            let asc = service.sortState.ascending
            switch service.sortState.mode {
            case .none: return false
            case .name: return asc ? a.title < b.title : a.title > b.title
            case .lastUsed: return asc ? a.lastUsed < b.lastUsed : a.lastUsed > b.lastUsed
            case .fileSize:
                let left = a.fileSize ?? 0, right = b.fileSize ?? 0
                return asc ? left < right : left > right
            case .addedAt: return asc ? a.addedAt < b.addedAt : a.addedAt > b.addedAt
            }
        }
    }

    @MainActor static func testSILTagProjection(_ checks: inout [String: Bool]) {
        let sil = SILService.shared
        let rows: [(String, String, [String], Int64?, TimeInterval, TimeInterval)] = [
            ("path-hit-7", "同名", ["blue", "blue", ""], nil, 10, 20),
            ("path-hit-2", "Alpha", ["red"], 0, 10, 20),
            ("plain-9", "同名", ["blue"], 0, 10, 20),
            ("plain-3", "Beta", ["red", "blue"], 20, 30, 10),
            ("PATH-HIT-5", "alpha", [""], 20, 30, 10),
            ("plain-1", "同名", ["blue"], nil, 10, 20),
            ("plain-8", "Beta", [], 100, 30, 10),
            ("path-hit-4", "空白", ["blue"], 100, 5, 1),
        ]
        sil.wallpapers = rows.map { row in
            SILWallpaper(id: row.0, title: row.1, tags: row.2, fileSize: row.3,
                lastUsed: Date(timeIntervalSince1970: row.4), addedAt: Date(timeIntervalSince1970: row.5))
        }
        let queries = ["", "   ", "ALPHA", " path-HIT ", "同名", "no match", "\n"]
        let tags: [String?] = [nil, "", "blue", "red", "no-such-tag"]
        var allEquivalent = true
        var propertyEquivalent = true
        var exactTiesKeepOrder = true
        for mode in SILSortMode.allCases {
            for ascending in [false, true] {
                sil.sortState = SILSortState(mode: mode, ascending: ascending)
                for query in queries {
                    sil.searchQuery = query
                    let legacy = legacySortedAll(sil)
                    propertyEquivalent = propertyEquivalent && sil.sortedWallpapers.map(\.id) == legacy.map(\.id)
                    for tag in tags {
                        let expected = tag.map { tag in legacy.filter { $0.tags.contains(tag) } } ?? legacy
                        let actual = sil.sortedWallpapers(forSILTag: tag)
                        allEquivalent = allEquivalent && actual.map(\.id) == expected.map(\.id)
                    }
                }
                sil.searchQuery = "同名"
                // These three records compare equal for every comparator and
                // include nil/zero file sizes, which intentionally remain ties.
                exactTiesKeepOrder = exactTiesKeepOrder
                    && sil.sortedWallpapers(forSILTag: "blue").map(\.id) == ["path-hit-7", "plain-9", "plain-1"]
            }
        }
        checks["silTagProjectionMatchesLegacyWholeOutputForAllModesDirectionsQueriesAndTags"] = allEquivalent
        checks["silUntaggedPropertyPreservesItsExistingProjection"] = propertyEquivalent
        checks["silTagProjectionKeepsEqualValueInputOrderInBothDirections"] = exactTiesKeepOrder

        var navigationEquivalent = true
        for mode in SILSortMode.allCases {
            for ascending in [false, true] {
                sil.sortState = SILSortState(mode: mode, ascending: ascending)
                for query in queries {
                    sil.searchQuery = query
                    let legacy = legacySortedAll(sil)
                    for tag in tags {
                        sil.currentContextTag = tag
                        let visible = tag.map { tag in legacy.filter { $0.tags.contains(tag) } } ?? legacy
                        let selections: [String?] = [nil, "missing"] + visible.map { Optional($0.id) }
                        for current in selections {
                            for key in [UInt16(123), 124, 125, 126, 0] {
                                let expected: String?
                                if visible.isEmpty { expected = current }
                                else if let current, let index = visible.firstIndex(where: { $0.id == current }) {
                                    let offset: Int
                                    switch key {
                                    case 123: offset = -1
                                    case 124: offset = 1
                                    case 125: offset = sil.visibleGridColumnCount
                                    case 126: offset = -sil.visibleGridColumnCount
                                    default: offset = 0
                                    }
                                    expected = visible[min(max(0, index + offset), visible.count - 1)].id
                                } else { expected = visible.first?.id }
                                sil.selectedID = current
                                sil.moveSingleSelectionByArrowKey(key)
                                navigationEquivalent = navigationEquivalent && sil.selectedID == expected
                            }
                        }
                    }
                }
            }
        }
        checks["silArrowNavigationMatchesDisplayedLegacyOrderIncludingTiesAndBoundaries"] = navigationEquivalent
        sil.isMultiSelectMode = true
        sil.selectedID = "unchanged"
        let priorSyncs = sil.inspectorSyncs
        sil.moveSingleSelectionByArrowKey(124)
        checks["silMultiSelectionArrowDoesNotChangeSelectionOrInspector"] = sil.selectedID == "unchanged"
            && sil.inspectorSyncs == priorSyncs
        sil.isMultiSelectMode = false

        // A narrow page selects four scattered rows from a much larger input.
        // Count the actual production comparator, rather than timing a copy.
        sil.wallpapers = (0..<256).map { index in
            SILWallpaper(id: "large-\(index)", title: String(format: "%04d", 255 - index),
                tags: index % 64 == 0 ? ["narrow"] : [])
        }
        sil.searchQuery = ""
        sil.sortState = SILSortState(mode: .name, ascending: true)
        sil.comparisons = 0
        let whole = sil.sortedWallpapers
        let wholeComparisons = sil.comparisons
        sil.comparisons = 0
        sil.derivations = 0
        let narrow = sil.sortedWallpapers(forSILTag: "narrow")
        let narrowComparisons = sil.comparisons
        checks["silTagProjectionSortsOnlyTheSelectedSubset"] = narrow.count == 4 && sil.derivations == 1
            && narrow.map(\.id) == whole.filter { $0.tags.contains("narrow") }.map(\.id)
            && narrowComparisons > 0 && narrowComparisons < wholeComparisons / 8
        sil.comparisons = 0
        let missing = sil.sortedWallpapers(forSILTag: "absent")
        checks["silMissingTagPerformsNoSortComparisons"] = missing.isEmpty && sil.comparisons == 0
        sil.currentContextTag = "narrow"
        sil.selectedID = narrow.first?.id
        sil.comparisons = 0
        sil.derivations = 0
        sil.moveSingleSelectionByArrowKey(124)
        checks["silArrowNavigationSortsOnlyTheActiveTag"] = sil.selectedID == narrow.dropFirst().first?.id
            && sil.derivations == 1 && sil.comparisons == narrowComparisons
        sil.currentContextTag = nil
        sil.sortState = SILSortState(mode: .none, ascending: false)
        sil.comparisons = 0
        checks["silDefaultOrderFiltersWithoutSorting"] = sil.sortedWallpapers(forSILTag: "narrow").map(\.id)
            == sil.wallpapers.filter { $0.tags.contains("narrow") }.map(\.id) && sil.comparisons == 0
    }

    @MainActor static func testOnline(_ checks: inout [String: Bool]) throws {
        let service = OnlineLibraryService()
        let online = OnlineProbe(service)
        online.collectionView.visible = [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)]
        online.bind()
        service.items = [OnlineLibraryVideoItem(id: 1), OnlineLibraryVideoItem(id: 2), OnlineLibraryVideoItem(id: 3)]
        pump(0.25)
        let a = online.collectionView.cell(0)
        let b = online.collectionView.cell(1)
        let aInitial = a.states.count
        let bInitial = b.states.count
        service.downloadProgressByID = [1: 0.25]
        pump(0.25)
        checks["onlineProgressARefreshesAWithoutReconfiguringB"] = a.states.count == aInitial + 1
            && b.states.count == bInitial && a.states.last?.progress == 0.25
        let unchanged = a.states.count
        service.downloadProgressByID = [1: 0.25]
        pump(0.25)
        checks["onlineUnchangedProgressDoesNoCellWork"] = a.states.count == unchanged && b.states.count == bInitial
        service.downloadProgressByID = [:]
        pump(0.25)
        checks["onlineProgressRemovalClearsPreviousValue"] = a.states.count == unchanged + 1
            && a.states.last?.progress == nil && b.states.count == bInitial
        service.downloadProgressByID = [1: 0.4]
        service.downloadProgressByID = [1: 0.6]
        service.downloadProgressByID = [1: 0.9]
        pump(0.25)
        checks["onlineThrottledBurstDeliversLatestProgress"] = a.states.last?.progress == 0.9
        service.downloadingIDs = [1]
        pump()
        let beforeEnd = b.states.count
        service.downloadingIDs = []
        service.downloadedIDs = [1]
        service.downloadProgressByID = [:]
        pump(0.25)
        checks["onlineCompletionKeepsFullLowFrequencyStateRefresh"] = a.states.last?.downloaded == true
            && a.states.last?.downloading == false && a.states.last?.progress == nil && b.states.count > beforeEnd
        service.downloadProgressByID = [3: 0.7]
        pump(0.25)
        online.collectionView.visible = [IndexPath(item: 2, section: 0)]
        online.dataSource.materializeVisible()
        let c = online.collectionView.cell(2)
        checks["onlineNewlyVisibleCellUsesCurrentStateWithoutNewProgressEvent"] = c.states.last?.id == 3
            && c.states.last?.progress == 0.7
        online.collectionView.visible = [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)]
        let external = OnlineLibraryService.downloadDirectory.appendingPathComponent("online_2.mp4")
        try Data([0]).write(to: external)
        // A low-frequency collection-wide status publication still admits an
        // externally-created file for a card unrelated to the active task.
        service.downloadingIDs = [1]
        pump()
        checks["onlineLowFrequencyStatusRefreshDiscoversUnrelatedExternalDownload"] = service.downloadedIDs.contains(2)
            && b.states.last?.downloaded == true
        service.prioritizedWindows = []
        online.lastPrioritizedVisibleIDs = nil
        online.updateVisibleThumbnailPriorities()
        for _ in 0..<20 {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification,
                object: online.scrollView.contentView)
        }
        pump()
        checks["onlineRepeatedVisibleWindowSendsOneOrderedPriorityUpdate"] = service.prioritizedWindows == [[1, 2]]
        online.collectionView.visible = [IndexPath(item: 2, section: 0), IndexPath(item: 1, section: 0)]
        online.updateVisibleThumbnailPriorities()
        pump()
        checks["onlineChangedVisibleWindowUpdatesPriorityInIndexOrder"] = service.prioritizedWindows == [[1, 2], [2, 3]]
        service.items = [OnlineLibraryVideoItem(id: 1, title: "new 1"),
            OnlineLibraryVideoItem(id: 2, title: "new 2"), OnlineLibraryVideoItem(id: 3, title: "new 3")]
        pump()
        checks["onlineNewItemsGenerationInvalidatesSameVisibleIDPriorityWindow"] = service.prioritizedWindows == [[1, 2], [2, 3], [2, 3]]
            && online.collectionView.cell(2).states.last?.title == "new 3"
        let retired = online.collectionView.cell(2)
        let retiredCount = retired.states.count
        service.downloadProgressByID = [3: 0.8]
        service.items = [OnlineLibraryVideoItem(id: 1), OnlineLibraryVideoItem(id: 2),
            OnlineLibraryVideoItem(id: 4, title: "replacement")]
        pump(0.25)
        let replacement = online.collectionView.cell(2)
        checks["onlineQueuedOldIDProgressCannotReconfigureReplacementAtSameIndex"] = replacement.states.count == 1
            && replacement.states.last?.id == 4 && replacement.states.last?.progress == nil
            && retired.states.count == retiredCount
        service.downloadProgressByID = [:]
        pump(0.25)
        checks["onlineRemovedOldProgressKeyDoesNotTouchReplacementCell"] = replacement.states.count == 1
        var transient: OnlineProbe? = OnlineProbe(service)
        transient?.collectionView.visible = [IndexPath(item: 0, section: 0)]
        transient?.bind()
        pump(0.25)
        let retainedCell = transient!.collectionView.cell(0)
        weak var weakOnline = transient
        transient = nil
        checks["onlineCombineProviderAndCellActionsDoNotRetainContainer"] = weakOnline == nil
        retainedCell.downloadAction?()
        retainedCell.wallpaperAction?()
        service.downloadProgressByID = [1: 0.99]
        pump(0.25)
        checks["onlineReleasedContainerIsNotRevivedByQueuedProgress"] = weakOnline == nil
    }
}
