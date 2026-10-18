import AppKit
import Combine

struct GridEntry: Equatable { let id: String; var title: String = "Wallpaper" }
typealias SteamWorkshopBrowserItem = GridEntry
typealias SteamWorkshopDownloadRecord = GridEntry

@MainActor final class GridService {
    @Published var displayedBrowserItems: [GridEntry] = []
    var browserLoadMoreFailureMessage: String?
    var isLoadingMoreBrowserItems = false
    var hasMoreBrowserItems = false
    @Published var pendingBrowserScrollRestoreOffset: CGFloat?
    var displayedDownloads: [GridEntry] = []
    var selectedDownloadID: String?
    var selectedDownloadIDs: Set<String> = []
    var isDownloadsMultiSelectMode = false
    var downloadSelectionPublicationVersion = 0
    func syncDownloadsInspectorSelectionIfNeeded() {}
    func consumePendingBrowserScrollRestoreOffset() { pendingBrowserScrollRestoreOffset = nil }
    // SELECTION_METHODS
}

enum GridSection { case main, status }
@MainActor final class ProbeDataSource {
    let source: NSCollectionViewDiffableDataSource<GridSection, String>
    var holdCompletions = false
    var heldCompletions: [() -> Void] = []
    init(_ source: NSCollectionViewDiffableDataSource<GridSection, String>) { self.source = source }
    func snapshot() -> NSDiffableDataSourceSnapshot<GridSection, String> { source.snapshot() }
    func apply(_ snapshot: NSDiffableDataSourceSnapshot<GridSection, String>, animatingDifferences: Bool,
               completion: @escaping () -> Void) {
        source.apply(snapshot, animatingDifferences: animatingDifferences) { [weak self] in
            if let self, self.holdCompletions { self.heldCompletions.append(completion) }
            else { completion() }
        }
    }
    func release() {
        holdCompletions = false
        let callbacks = heldCompletions
        heldCompletions.removeAll()
        callbacks.forEach { $0() }
    }
}
final class GridCell: NSCollectionViewItem {
    override func loadView() {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        view = label
    }
}

@MainActor class GridProbe: NSView {
    typealias Section = GridSection
    let service = GridService()
    let scrollView = NSScrollView()
    let collectionView = NSCollectionView()
    let flowLayout = SteamWorkshopGridLayoutSupport.makeFlowLayout()
    var orderedIDs: [String] = []
    var keyboardFocusedID: String?
    var focusScrolls = 0
    var metadataRefreshes = 0
    lazy var dataSource = ProbeDataSource(NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { _, _, id in
        let cell = GridCell()
        (cell.view as? NSTextField)?.stringValue = id
        return cell
    })
    override init(frame: NSRect) {
        super.init(frame: frame)
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource.source
        flowLayout.itemSize = NSSize(width: 100, height: 100)
        scrollView.frame = bounds
        scrollView.hasVerticalScroller = false
        scrollView.documentView = collectionView
        addSubview(scrollView)
    }
    required init?(coder: NSCoder) { nil }
    func updateKeyboardFocusItem(withID id: String?, focused: Bool) {}
    func reloadKeyboardFocus(previous: String?, next: String?) {}
    func focusItem(at index: Int) { keyboardFocusedID = orderedIDs[index]; focusScrolls += 1 }
    func actualIDs() -> [String] { dataSource.snapshot().itemIdentifiers.filter { $0 != SteamWorkshopBrowserFooterSupport.itemID } }
    func reflowIsInOrder() -> Bool {
        let frames = actualIDs().enumerated().compactMap { index, _ in
            flowLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame
        }
        return frames.count == actualIDs().count && zip(frames, frames.dropFirst()).allSatisfy { a, b in
            b.minY > a.minY || (b.minY == a.minY && b.minX > a.minX)
        }
    }
}

@MainActor final class BrowserProbe: GridProbe {
    var itemsByID: [String: GridEntry] = [:]
    var footerState = SteamWorkshopBrowserFooterSupport.State.hidden
    var pendingItems: [GridEntry]?
    var isItemsApplyScheduled = false
    var isApplyingSnapshot = false
    var hasResolvedInitialItemSize = true
    var cancellables = Set<AnyCancellable>()
    func bind() {
        // BROWSER_BINDINGS
    }
    func updateLayoutItemSize() -> Bool { hasResolvedInitialItemSize }
    func scheduleLayoutItemSizeUpdate() {}
    func updateBrowserScrollMetrics() {}
    func prioritizeVisibleItemsForHydration() {}
    func checkLoadMore() {}
    func reloadVisibleMetadata(for ids: Set<String>) { metadataRefreshes += 1 }
    func reloadVisibleItems() { metadataRefreshes += 1 }
    func configureVisibleFooterIfNeeded() {}
    // BROWSER_METHODS
}

@MainActor final class DownloadsProbe: GridProbe {
    var recordsByID: [String: GridEntry] = [:]
    var previousOrderedIDs: [String] = []
    var pendingRecords: [GridEntry]?
    var isRecordsApplyScheduled = false
    var isApplyingRecords = false
    let emptyLabel = NSTextField(labelWithString: "")
    func currentEmptyStateText() -> String { "Empty" }
    func refreshVisibleDownloadItems(for ids: Set<String>) { metadataRefreshes += 1 }
    // DOWNLOAD_METHODS
}

@main struct SteamGridUpdateHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 700, height: 340),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 340))
        window.contentView = root
        window.orderFrontRegardless()
        let browser = BrowserProbe(frame: NSRect(x: 0, y: 0, width: 340, height: 320))
        let downloads = DownloadsProbe(frame: NSRect(x: 350, y: 0, width: 340, height: 320))
        root.addSubview(browser); root.addSubview(downloads)
        browser.bind()
        let all = (1...36).map { GridEntry(id: String(format: "%02d", $0)) }
        var checks: [String: Bool] = [:]
        func pump(_ condition: () -> Bool) -> Bool {
            let until = Date().addingTimeInterval(4)
            while !condition(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            root.layoutSubtreeIfNeeded()
            return condition()
        }
        func idle() -> Bool {
            !browser.isApplyingSnapshot && !browser.isItemsApplyScheduled && browser.pendingItems == nil
                && !downloads.isApplyingRecords && !downloads.isRecordsApplyScheduled && downloads.pendingRecords == nil
        }
        func update(_ entries: [GridEntry]) {
            browser.service.displayedBrowserItems = entries
            downloads.service.displayedDownloads = entries
            downloads.service.sanitizeDownloadSelectionAgainstDisplayedDownloads()
            downloads.applyRecords(entries)
        }
        func capture(_ name: String) throws {
            guard let path = ProcessInfo.processInfo.environment["MWX_STEAM_GRID_PROOF_DIR"] else { return }
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            root.layoutSubtreeIfNeeded()
            if let image = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: image)
                try image.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            }
        }
        update(Array(all.prefix(3)))
        update(all)
        checks["sameTurnUpdatesCoalesceToLatest"] = browser.actualIDs().isEmpty && downloads.actualIDs().isEmpty
            && pump { idle() && browser.actualIDs() == all.map(\.id) && downloads.actualIDs() == all.map(\.id) }
        browser.keyboardFocusedID = "16"; downloads.keyboardFocusedID = "16"
        downloads.service.selectDownload(itemID: "16")
        checks["realSingleSelectionEstablished"] = pump { downloads.service.selectedDownloadID == "16" && downloads.service.selectedDownloadIDs == ["16"] }
        browser.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: 330))
        downloads.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: 330))
        try capture("before-removal")
        let browserScrolls = browser.focusScrolls, downloadScrolls = downloads.focusScrolls
        let removed = all.filter { $0.id != "16" }
        update(removed)
        checks["singleRemovalCompletes"] = pump { idle() && browser.actualIDs() == removed.map(\.id) && downloads.actualIDs() == removed.map(\.id) }
        checks["removedSingleSelectionMovesWithFocus"] = pump { downloads.service.selectedDownloadID == "17" && downloads.service.selectedDownloadIDs == ["17"] }
        checks["removedFocusMovesToAdjacentSurvivor"] = browser.keyboardFocusedID == "17" && downloads.keyboardFocusedID == "17"
        checks["removalNeverScrollsFocusToFirstCard"] = browser.focusScrolls == browserScrolls && downloads.focusScrolls == downloadScrolls
        checks["bothNativeGridsReflowInOriginalOrder"] = browser.reflowIsInOrder() && downloads.reflowIsInOrder()
        try capture("after-removal")
        // Delay the production completion after native completion to exercise
        // latest-pending serialization without substituting the native apply.
        let first = removed.filter { $0.id != "20" }
        browser.dataSource.holdCompletions = true; downloads.dataSource.holdCompletions = true
        update(first)
        checks["nativeApplyCompletionCanArriveLate"] = pump {
            !browser.dataSource.heldCompletions.isEmpty && !downloads.dataSource.heldCompletions.isEmpty
        }
        let activeBrowserIDs = browser.orderedIDs, activeDownloadIDs = downloads.orderedIDs
        let second = first.filter { $0.id != "21" }
        var latest = second.filter { $0.id != "22" }
        latest[0].title = "Latest metadata"
        update(second); update(latest)
        checks["pendingEventsDoNotMutateActiveSnapshotModel"] = browser.orderedIDs == activeBrowserIDs && downloads.orderedIDs == activeDownloadIDs
        _ = pump { !browser.isItemsApplyScheduled && !downloads.isRecordsApplyScheduled }
        checks["inFlightApplyRetainsLatestPendingUpdate"] = browser.pendingItems == latest && downloads.pendingRecords == latest
            && browser.orderedIDs == first.map(\.id) && downloads.orderedIDs == first.map(\.id)
        browser.dataSource.release(); downloads.dataSource.release()
        checks["queuedRemovalUsesLatestSnapshotAndMetadata"] = pump { idle() && browser.actualIDs() == latest.map(\.id) && downloads.actualIDs() == latest.map(\.id) }
            && browser.itemsByID["01"]?.title == "Latest metadata" && downloads.recordsByID["01"]?.title == "Latest metadata"
        // The old short author document cannot clamp/consume a saved offset
        // before the restored long discovery snapshot has laid out.
        update(Array(all.prefix(2)))
        _ = pump { idle() && browser.actualIDs().count == 2 }
        browser.service.displayedBrowserItems = all
        browser.service.pendingBrowserScrollRestoreOffset = 700
        checks["restoredOffsetWaitsForLongFeedLayout"] = pump {
            idle() && browser.actualIDs().count == all.count && browser.service.pendingBrowserScrollRestoreOffset == nil
                && abs(browser.scrollView.contentView.bounds.origin.y - 700) < 1
        }
        update(all)
        _ = pump { idle() && downloads.actualIDs().count == all.count }
        downloads.service.isDownloadsMultiSelectMode = true
        downloads.service.selectedDownloadID = "17"
        downloads.service.selectedDownloadIDs = ["17", "18"]
        downloads.keyboardFocusedID = "17"
        update(all.filter { $0.id != "17" })
        checks["multiSelectionOnlyKeepsSurvivors"] = pump {
            idle() && downloads.keyboardFocusedID == "18" && downloads.service.selectedDownloadID == "18"
                && downloads.service.selectedDownloadIDs == ["18"]
        }
        // Explicit selections are visible to later sanitization immediately;
        // stale deferred library cleanup cannot overwrite a newer command.
        downloads.service.isDownloadsMultiSelectMode = false
        downloads.service.selectDownload(itemID: "19")
        downloads.service.selectDownload(itemID: "20")
        checks["latestSelectionWins"] = downloads.service.selectedDownloadID == "20"
        downloads.service.selectDownload(itemID: "21")
        downloads.service.selectDownload(itemID: "20")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["selectingCurrentItemKeepsLatestIntent"] = downloads.service.selectedDownloadID == "20"
        downloads.service.selectedDownloadID = "missing"
        downloads.service.selectedDownloadIDs = ["missing"]
        downloads.service.sanitizeDownloadSelectionAgainstDisplayedDownloads()
        downloads.service.selectDownload(itemID: "21")
        downloads.service.sanitizeDownloadSelectionAgainstDisplayedDownloads()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["sanitizationUsesLatestSelectionIntent"] = downloads.service.selectedDownloadID == "21" && downloads.service.selectedDownloadIDs == ["21"]
        downloads.service.publishDownloadSelectionState(primaryID: "22", selectedIDs: ["22"], deferPublishing: true)
        downloads.service.selectedDownloadID = nil; downloads.service.selectedDownloadIDs = []
        _ = pump { idle() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["directClearRetiresDeferredSelection"] = downloads.service.selectedDownloadID == nil && downloads.service.selectedDownloadIDs.isEmpty
        browser.service.hasMoreBrowserItems = true
        update([])
        checks["emptyFeedCanShowContinuationFooter"] = pump { idle() && browser.dataSource.snapshot().itemIdentifiers == [SteamWorkshopBrowserFooterSupport.itemID] }
        browser.service.hasMoreBrowserItems = false
        browser.refreshFooterState()
        checks["footerRemovalPublishesEvenAfterStateChanged"] = pump { idle() && browser.dataSource.snapshot().itemIdentifiers.isEmpty }
        let policy = SteamWorkshopGridLayoutSupport.shouldAnimateChange
        checks["smallDeletionUsesNaturalAnimation"] = policy(all.map(\.id), removed.map(\.id), 9, false)
        checks["reducedMotionDisablesMovement"] = !policy(all.map(\.id), removed.map(\.id), 9, true)
        checks["largeRemovalAvoidsAnimationStorm"] = !policy(all.map(\.id), ["36"], 3, false)
        checks["explicitReorderDoesNotUseRemovalAnimation"] = !policy(["1", "2", "3"], ["3", "1", "2"], 3, false)
        checks["noChangeDoesNotAnimate"] = !policy(["1"], ["1"], 3, false)
        checks["initialLoadDoesNotAnimate"] = !policy([], ["1"], 3, false)
        window.close()
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
