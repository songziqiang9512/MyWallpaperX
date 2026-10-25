// Production bodies are inserted by test_ui_projection_efficiency.py. Services,
// grid rendering, and diffable application are recording boundaries; Combine,
// dispatch delivery, NSViewController replacement and snapshots use platform
// implementations. The separate downloaded-source gate covers filesystem facts.
import AppKit
import Combine
import Foundation

struct OnlineLibraryVideoItem: Equatable {
    let id: Int; var title: String = "fixture"
    var previewThumbnailURL: URL? { URL(string: "https://fixture.invalid/\(id).jpg")! }
}
@MainActor final class OnlineLibraryService: ObservableObject {
    static let shared = OnlineLibraryService()
    static var downloadDirectory = URL(fileURLWithPath: "/not-configured")
    @Published var items: [OnlineLibraryVideoItem] = []
    @Published var downloadingIDs: Set<Int> = []
    @Published var downloadedIDs: Set<Int> = []
    @Published var downloadProgressByID: [Int: Double] = [:]
    @Published var inspectedDownloadedItemID: Int?
    var prioritizedWindows: [[Int]] = []
    func prioritizeVisibleItemIDs(_ ids: [Int], maxPixelSize: Int = 512) { prioritizedWindows.append(ids) }
    func thumbnailPrefetchNeedsRefresh() -> Bool { false }
    func cancelThumbnailPrefetch() {}
}
enum ModuleIdentifier: String { case onlineLibrary }
extension Notification.Name {
    static let inspectorHostDidPresent = Self("fixture.inspector.present")
    static let inspectorHostDidClose = Self("fixture.inspector.close")
    static let moduleDidBecomeActive = Self("fixture.module.active")
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
    var configuredOrganization: WallpaperInspectorActions?
    var organizationUpdates: [(id: Int, state: WallpaperInspectorActions.State?)] = []
    var downloadAction: (() -> Void)?
    var wallpaperAction: (() -> Void)?
    func configure(item: OnlineLibraryVideoItem, isDownloading: Bool, isDownloaded: Bool,
                   downloadProgress: Double?, thumbnailDemandActive: Bool? = nil,
                   organization: WallpaperInspectorActions? = nil, onDownload: @escaping () -> Void,
                   onSetAsWallpaper: @escaping () -> Void) {
        states.append(State(id: item.id, title: item.title, downloading: isDownloading,
            downloaded: isDownloaded, progress: downloadProgress))
        configuredOrganization = organization
        downloadAction = onDownload
        wallpaperAction = onSetAsWallpaper
    }
    func updateOrganization(_ actions: WallpaperInspectorActions?, for itemID: Int) {
        // A recording boundary only: the complete real card gate proves its
        // wrong-ID guard. Do not reproduce that guard as this gate's oracle.
        organizationUpdates.append((itemID, actions?.state))
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
    var defersApplications = false
    var pendingIdentifiers: [Item]?
    var pendingCompletions: [() -> Void] = []
    init(collectionView: RecordingCollection,
         itemProvider: @escaping (RecordingCollection, IndexPath, Item) -> NSCollectionViewItem?) {
        self.collectionView = collectionView
        provider = itemProvider
    }
    func apply(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, animatingDifferences: Bool,
               completion: (() -> Void)? = nil) {
        if defersApplications {
            pendingIdentifiers = snapshot.itemIdentifiers
            if let completion { pendingCompletions.append(completion) }
            return
        }
        identifiers = snapshot.itemIdentifiers
        materializeVisible()
        completion?()
    }
    func finishPendingApplication() {
        guard let pendingIdentifiers else { return }
        self.pendingIdentifiers = nil
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        identifiers = pendingIdentifiers
        materializeVisible()
        completions.forEach { $0() }
    }
    func itemIdentifier(for indexPath: IndexPath) -> Item? {
        guard indexPath.section == 0, identifiers.indices.contains(indexPath.item) else { return nil }
        return identifiers[indexPath.item]
    }
    func materializeVisible() {
        for indexPath in collectionView.visible where indexPath.item < identifiers.count {
            collectionView.cells[indexPath] = provider(collectionView, indexPath, identifiers[indexPath.item])
        }
    }
}
@MainActor final class OnlineProbe {
    let listThumbnailTintSource = ListThumbnailTintSource()
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
    // ONLINE_ORGANIZATION_FACTORY
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
        try testOnline(&checks)
        testOrganization(&checks)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
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
        // Rendering and status ticks no longer inspect the directory. The
        // source's published result updates the unrelated card instead.
        service.downloadingIDs = [1]
        pump()
        checks["onlineLowFrequencyStatusDoesNotGuessExternalFileAvailability"] = !service.downloadedIDs.contains(2)
            && b.states.last?.downloaded == false
        service.downloadedIDs = [1, 2]
        pump()
        checks["onlineSourcePublicationRefreshesUnrelatedExternalDownload"] = service.downloadedIDs.contains(2)
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

    @MainActor static func testOrganization(_ checks: inout [String: Bool]) {
        let service = OnlineLibraryService(), online = OnlineProbe(service)
        online.collectionView.visible = [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)]
        var eligible: Set<Int> = [11], favorites = Set<Int>(), factoryCalls: [Int] = []
        let factory: (OnlineLibraryVideoItem) -> WallpaperInspectorActions? = { item in
            factoryCalls.append(item.id)
            guard eligible.contains(item.id) else { return nil }
            return .init(state: .init(isPlaying: false, isFavorite: favorites.contains(item.id),
                canPerformPrimary: false, canFavorite: true, canOrganize: true, playlistNames: []),
                onPrimary: {}, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        }
        online.makeOrganization = factory
        online.bind()
        service.items = [OnlineLibraryVideoItem(id: 11), OnlineLibraryVideoItem(id: 12), OnlineLibraryVideoItem(id: 13)]
        pump(0.25)
        let a = online.collectionView.cell(0), b = online.collectionView.cell(1)
        checks["onlineOrganizationFactorySuppliesOnlyEligibleVisibleCards"] = a.configuredOrganization?.state.isFavorite == false
            && b.configuredOrganization == nil && !factoryCalls.contains(13)
        service.downloadedIDs = [11, 12]
        pump()
        checks["onlineDownloadedIDsAloneCannotCreateOrganization"] = a.states.last?.downloaded == true
            && b.states.last?.downloaded == true && a.configuredOrganization != nil && b.configuredOrganization == nil

        let aConfigurations = a.states.count, bConfigurations = b.states.count
        eligible = [11, 12]; favorites = [11]; factoryCalls = []
        online.refreshOrganization()
        checks["onlineRelationshipEchoUsesVisibleIDsWithoutReconfiguration"] = factoryCalls.sorted() == [11, 12]
            && a.states.count == aConfigurations && b.states.count == bConfigurations
            && a.organizationUpdates.last?.id == 11 && a.organizationUpdates.last?.state?.isFavorite == true
            && b.organizationUpdates.last?.id == 12 && b.organizationUpdates.last?.state?.isFavorite == false
        let aUpdates = a.organizationUpdates.count, bUpdates = b.organizationUpdates.count
        online.makeOrganization = nil
        checks["onlineOrganizationFactoryWithdrawalRevokesWithoutReconfiguration"] = a.states.count == aConfigurations
            && b.states.count == bConfigurations && a.organizationUpdates.count == aUpdates + 1
            && b.organizationUpdates.count == bUpdates + 1 && a.organizationUpdates.last?.id == 11
            && b.organizationUpdates.last?.id == 12 && a.organizationUpdates.last?.state == nil
            && b.organizationUpdates.last?.state == nil

        eligible = [21]; favorites = [21]
        online.makeOrganization = factory
        online.dataSource.defersApplications = true
        service.items = [OnlineLibraryVideoItem(id: 21), OnlineLibraryVideoItem(id: 22)]
        pump()
        online.refreshOrganization()
        checks["onlineOrganizationEchoCarriesNewIDAcrossDeferredSnapshot"] = online.orderedIDs == [21, 22]
            && online.dataSource.identifiers == [11, 12, 13] && a.states.last?.id == 11
            && b.states.last?.id == 12 && a.states.count == aConfigurations && b.states.count == bConfigurations
            && a.organizationUpdates.last?.id == 21 && a.organizationUpdates.last?.state?.isFavorite == true
            && b.organizationUpdates.last?.id == 22 && b.organizationUpdates.last?.state == nil
        online.dataSource.finishPendingApplication()
        let newA = online.collectionView.cell(0), newB = online.collectionView.cell(1)
        checks["onlineDeferredProviderUsesCurrentOrganizationWhenNewCellArrives"] = newA !== a && newB !== b
            && newA.states.last?.id == 21 && newA.configuredOrganization?.state.isFavorite == true
            && newB.states.last?.id == 22 && newB.configuredOrganization == nil
    }
}
