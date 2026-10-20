import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// PRODUCTION_MODEL

nonisolated final class HeaderProbe: @unchecked Sendable {
    static let shared = HeaderProbe()
    private let lock = NSLock()
    private var entered: DispatchSemaphore?
    private var release: DispatchSemaphore?
    private var readsOnMain: [Bool] = []
    func holdNextRead() -> (entered: DispatchSemaphore, release: DispatchSemaphore) {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        lock.lock(); self.entered = entered; self.release = release; lock.unlock()
        return (entered, release)
    }
    func beforeRead() {
        lock.lock()
        readsOnMain.append(Thread.isMainThread)
        let entered = self.entered, release = self.release
        self.entered = nil; self.release = nil
        lock.unlock()
        if let entered, let release {
            entered.signal()
            precondition(release.wait(timeout: .now() + 5) == .success)
        }
    }
    var allReadsOffMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return !readsOnMain.isEmpty && readsOnMain.allSatisfy { !$0 }
    }
}
nonisolated func ProbeImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
    HeaderProbe.shared.beforeRead()
    return CGImageSourceCreateWithURL(url, options)
}
@MainActor var completedBatches = 0
@MainActor final class MetadataProbe {
    var publications = 0
    var wallpapers: [SILWallpaper] = [] { didSet { publications += 1 } }
    var saves = 0
    var saveThreads: [Bool] = []
    let persistenceURL: URL
    init(_ url: URL) { persistenceURL = url }
    // PRODUCTION_STATE
    // PRODUCTION_METHODS
    // The full App reset has unrelated playback/settings effects. Its actual
    // source wiring is checked by Python; this composes the real SIL revoke.
    func resetForAudit() throws {
        invalidatePendingMetadataLoad()
        wallpapers = []
        try FileManager.default.removeItem(at: persistenceURL)
    }
}

@MainActor final class MetadataCell {
    var wallpaperID: String?
    let titleLabel = NSTextField(labelWithString: "")
    let metaLabel = NSTextField(labelWithString: "")
    func configure(wallpaper: SILWallpaper) {
        // PRODUCTION_CELL_METADATA
    }
}
@MainActor final class MetadataItems: NSObject, NSCollectionViewDataSource {
    var count = 0
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        NSCollectionViewItem()
    }
}
@MainActor final class MetadataLayout {
    let actual = SILWaterfallLayout()
    var invalidations = 0
    func invalidateLayout() { invalidations += 1; actual.invalidateLayout(); actual.prepare() }
}
@MainActor final class MetadataCollection {
    let native = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let items = MetadataItems()
    var visible: Set<IndexPath> = [IndexPath(item: 0, section: 0)]
    var reloaded = Set<IndexPath>()
    var configure: ((IndexPath) -> Void)?
    init() { native.dataSource = items }
    func indexPathsForVisibleItems() -> Set<IndexPath> { visible }
    func reloadItems(at paths: Set<IndexPath>) {
        reloaded.formUnion(paths)
        paths.forEach { configure?($0) }
    }
}
@MainActor final class MetadataDataSource {
    var applies = 0
    var holdCompletion = false
    var completions: [() -> Void] = []
    let applyItems: ([String]) -> Void
    init(_ applyItems: @escaping ([String]) -> Void) { self.applyItems = applyItems }
    func apply(_ snapshot: NSDiffableDataSourceSnapshot<MetadataGrid.Section, String>, animatingDifferences: Bool, completion: @escaping () -> Void) {
        applies += 1; applyItems(snapshot.itemIdentifiers)
        if holdCompletion { completions.append(completion) } else { completion() }
    }
    func releaseCompletion() {
        holdCompletion = false
        let pending = completions; completions = []
        pending.forEach { $0() }
    }
}
@MainActor final class MetadataGrid {
    enum Section: Hashable { case main }
    let collectionView = MetadataCollection()
    let waterfallLayout = MetadataLayout()
    let emptyLabel = NSTextField()
    var wallpapersByID: [String: SILWallpaper] = [:]
    var orderedIDs: [String] = []
    var orderedIndexByID: [String: Int] = [:]
    var pendingIDs: [String] = []
    var lastAppliedIDs: [String] = []
    var pendingDimensionReloadIDs = Set<String>()
    var isSnapshotScheduled = false
    var isApplyingSnapshot = false
    var cells: [String: MetadataCell] = [:]
    lazy var dataSource = MetadataDataSource { [weak self] ids in
        guard let self else { return }
        collectionView.items.count = ids.count
        collectionView.native.reloadData()
        for id in ids {
            let cell = cells[id] ?? MetadataCell()
            if let value = wallpapersByID[id] { cell.configure(wallpaper: value) }
            cells[id] = cell
        }
        waterfallLayout.actual.prepare()
    }
    init() {
        collectionView.native.collectionViewLayout = waterfallLayout.actual
        waterfallLayout.actual.aspectRatioProvider = { [weak self] path in
            guard let self, orderedIDs.indices.contains(path.item),
                  let value = wallpapersByID[orderedIDs[path.item]] else { return 16 / 9 }
            return value.aspectRatio
        }
        collectionView.configure = { [weak self] path in
            guard let self, orderedIDs.indices.contains(path.item),
                  let value = wallpapersByID[orderedIDs[path.item]] else { return }
            cells[value.id]?.configure(wallpaper: value)
        }
    }
    func scheduleSyncSelection() {}
    func scheduleVisibleRefresh() {}
    func scheduleRestingScrollOriginCapture() {}
    // PRODUCTION_GRID_METHODS
}

@main enum SILMetadataLoadingChecks {
    @MainActor static func wait(_ reason: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            precondition(Date() < deadline, reason)
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        }
    }
    static func png(_ url: URL, width: Int = 8, height: Int = 12) {
        let data = Data(repeating: 128, count: width * height * 4)
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    static func record(_ id: String, _ path: String, width: Int? = nil, height: Int? = nil) -> SILWallpaper {
        var value = SILWallpaper(path: path)
        value.id = id; value.pixelWidth = width; value.pixelHeight = height
        return value
    }
    static func persist(_ records: [SILWallpaper], at url: URL) throws {
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageA = root.appendingPathComponent("A.png"), imageB = root.appendingPathComponent("B.png")
        png(imageA); png(imageB, width: 11, height: 17)
        let a = record("A", imageA.path), b = record("B", imageB.path, width: 99)
        let index = root.appendingPathComponent("index.json")
        var checks: [String: Bool] = [:]

        try persist([a, b], at: index)
        let service = MetadataProbe(index), held = HeaderProbe.shared.holdNextRead()
        service.load()
        checks["jsonPublishesBeforeHeadersComplete"] = service.wallpapers == [a, b] && service.publications == 1
        precondition(held.entered.wait(timeout: .now() + 3) == .success)
        var mainRan = false
        DispatchQueue.main.async { mainRan = true }
        wait("header read blocked the main queue") { mainRan }
        checks["blockedHeaderDoesNotBlockMainQueue"] = mainRan && service.saves == 0
        service.wallpapers[0].title = "User title"
        service.wallpapers[0].tags = ["edited"]
        service.wallpapers[0].lastUsed = Date(timeIntervalSince1970: 123)
        service.wallpapers[0].pixelWidth = 321
        let beforePatch = service.publications, beforeBatch = completedBatches
        held.release.signal()
        wait("metadata patch did not finish") { completedBatches > beforeBatch }
        checks["onlyMissingFieldsArePatched"] = service.wallpapers[0].pixelWidth == 321
            && service.wallpapers[0].pixelHeight == 12 && service.wallpapers[1].pixelWidth == 99
            && service.wallpapers[1].pixelHeight == 17
        checks["currentUserMetadataSurvivesHeaderCompletion"] = service.wallpapers[0].title == "User title"
            && service.wallpapers[0].tags == ["edited"] && service.wallpapers[0].lastUsed == Date(timeIntervalSince1970: 123)
        checks["batchPublishesAndSavesExactlyOnceOnMain"] = service.publications == beforePatch + 1
            && service.saves == 1 && service.saveThreads == [true]
        checks["patchedMetadataUsesOriginalJSONPersistence"] = try JSONDecoder().decode([SILWallpaper].self,
            from: Data(contentsOf: index)) == service.wallpapers

        try persist([a, b], at: index)
        let stale = MetadataProbe(index), oldRead = HeaderProbe.shared.holdNextRead()
        stale.load()
        precondition(oldRead.entered.wait(timeout: .now() + 3) == .success)
        var replacement = a; replacement.path = imageB.path
        let imported = record("imported", imageA.path)
        stale.wallpapers = [replacement, imported] // B deleted; A changed path.
        let oldBatch = completedBatches
        oldRead.release.signal()
        wait("stale identities did not finish") { completedBatches > oldBatch }
        checks["changedPathDeletedIDAndNewImportRejectOldFields"] = stale.wallpapers == [replacement, imported] && stale.saves == 0

        try persist([a], at: index)
        let reset = MetadataProbe(index), resetRead = HeaderProbe.shared.holdNextRead()
        reset.load()
        precondition(resetRead.entered.wait(timeout: .now() + 3) == .success)
        try reset.resetForAudit()
        let resetBatch = completedBatches
        resetRead.release.signal()
        wait("reset callback did not finish") { completedBatches > resetBatch }
        checks["resetRevokesOldMetadataWithoutRecreatingIndex"] = reset.wallpapers.isEmpty && reset.saves == 0
            && !FileManager.default.fileExists(atPath: index.path)

        try persist([a], at: index)
        let reload = MetadataProbe(index), reloadRead = HeaderProbe.shared.holdNextRead()
        reload.load()
        precondition(reloadRead.entered.wait(timeout: .now() + 3) == .success)
        let newRecord = record("new", imageB.path)
        try persist([newRecord], at: index)
        reload.load()
        wait("replacement load did not complete") { reload.wallpapers.first?.pixelHeight == 17 }
        let newState = reload.wallpapers, reloadBatch = completedBatches
        reloadRead.release.signal()
        wait("retired load did not finish") { completedBatches > reloadBatch }
        checks["newLoadGenerationRejectsEarlierHeaderResults"] = reload.wallpapers == newState
            && newState.map(\.id) == ["new"] && reload.saves == 1

        try persist([a], at: index)
        let corrupt = MetadataProbe(index), corruptRead = HeaderProbe.shared.holdNextRead()
        corrupt.load()
        precondition(corruptRead.entered.wait(timeout: .now() + 3) == .success)
        try Data("bad json".utf8).write(to: index)
        corrupt.load()
        let corruptBatch = completedBatches
        corruptRead.release.signal()
        wait("corrupt reload did not revoke old metadata") { completedBatches > corruptBatch }
        checks["failedJSONReloadRevokesOldHeaderWrite"] = corrupt.wallpapers == [a] && corrupt.saves == 0
            && (try? Data(contentsOf: index)) == Data("bad json".utf8)

        let absent = record("missing", root.appendingPathComponent("missing.png").path)
        try persist([absent], at: index)
        let failure = MetadataProbe(index), failureBatch = completedBatches
        failure.load()
        wait("failed header did not finish") { completedBatches > failureBatch }
        checks["metadataReadFailureDoesNotDeleteOrWrite"] = failure.wallpapers == [absent] && failure.saves == 0
        checks["allLoadMetadataHeaderReadsUseUtilityThread"] = HeaderProbe.shared.allReadsOffMain

        let brokenFile = root.appendingPathComponent("bad-header.png")
        try Data("valid path, invalid image header".utf8).write(to: brokenFile)
        let broken = record("broken", brokenFile.path)
        try persist([broken], at: index)
        let badHeader = MetadataProbe(index), badHeaderBatch = completedBatches
        badHeader.load()
        wait("invalid image header did not finish") { completedBatches > badHeaderBatch }
        checks["existingFileWithBadHeaderDoesNotDeleteOrWrite"] = badHeader.wallpapers == [broken] && badHeader.saves == 0
        var duplicatePath = a; duplicatePath.id = "other-id"
        var duplicateID = b; duplicateID.id = a.id
        try persist([a, a, duplicatePath, duplicateID], at: index)
        let duplicates = MetadataProbe(index), duplicateBatch = completedBatches
        duplicates.load()
        wait("duplicate identities did not finish") { completedBatches > duplicateBatch }
        checks["duplicateIDsAndPathsKeepDistinctHeaderSourcesAndKnownFields"] = duplicates.wallpapers.count == 4
            && duplicates.wallpapers.prefix(3).allSatisfy { $0.pixelWidth == 8 && $0.pixelHeight == 12 }
            && duplicates.wallpapers[3].pixelWidth == 99 && duplicates.wallpapers[3].pixelHeight == 17
            && duplicates.saves == 1

        let complete = record("complete", imageA.path, width: 5, height: 6)
        try persist([complete], at: index)
        let ready = MetadataProbe(index), readyBatch = completedBatches
        ready.load()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        checks["completeMetadataRequiresNoBackgroundBatchOrSave"] = ready.wallpapers == [complete]
            && completedBatches == readyBatch && ready.saves == 0

        let grid = MetadataGrid()
        grid.update(wallpapers: [a, b])
        wait("initial grid snapshot did not settle") { grid.lastAppliedIDs == ["A", "B"] }
        let columns = grid.waterfallLayout.actual.columnCount
        let initialFrame = grid.waterfallLayout.actual.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        checks["initialMissingDimensionsUseFallbackAndEmptySizeText"] = grid.cells["A"]!.metaLabel.stringValue
            .contains("×") == false && abs(initialFrame.width / initialFrame.height - 16 / 9) < 0.001
        var portrait = a; portrait.pixelWidth = 8; portrait.pixelHeight = 12
        var offscreen = b; offscreen.pixelWidth = 12; offscreen.pixelHeight = 8
        grid.update(wallpapers: [portrait, offscreen])
        wait("same-ID grid metadata did not reload") { grid.cells["A"]!.metaLabel.stringValue.contains("8 × 12") }
        let finalFrame = grid.waterfallLayout.actual.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        checks["sameIDsAndColumnCountRefreshRealWaterfallGeometry"] = grid.waterfallLayout.actual.columnCount == columns
            && finalFrame.height > initialFrame.height && abs(finalFrame.width / finalFrame.height - 8.0 / 12.0) < 0.001
        checks["metadataReloadsOnlyChangedVisibleCellsWithoutStructuralSnapshot"] = grid.dataSource.applies == 1
            && grid.collectionView.reloaded == [IndexPath(item: 0, section: 0)]
        let invalidations = grid.waterfallLayout.invalidations
        grid.collectionView.reloaded.removeAll()
        grid.update(wallpapers: [portrait, offscreen])
        wait("identical grid input did not settle") { !grid.isSnapshotScheduled }
        checks["identicalMetadataSkipsLayoutReloadAndSnapshot"] = grid.waterfallLayout.invalidations == invalidations
            && grid.collectionView.reloaded.isEmpty && grid.dataSource.applies == 1

        let pendingGrid = MetadataGrid()
        pendingGrid.dataSource.holdCompletion = true
        pendingGrid.update(wallpapers: [a, b])
        wait("held snapshot did not start") { pendingGrid.isApplyingSnapshot }
        pendingGrid.update(wallpapers: [portrait, offscreen])
        wait("same-topology metadata update did not schedule") { !pendingGrid.isSnapshotScheduled }
        checks["metadataWaitsForPendingSnapshotBeforeReloadingCells"] = pendingGrid.collectionView.reloaded.isEmpty
            && pendingGrid.dataSource.applies == 1 && pendingGrid.lastAppliedIDs.isEmpty
        pendingGrid.dataSource.releaseCompletion()
        checks["snapshotCompletionFlushesLatestVisibleMetadataOnce"] = pendingGrid.lastAppliedIDs == ["A", "B"]
            && pendingGrid.dataSource.applies == 1 && pendingGrid.cells["A"]!.metaLabel.stringValue.contains("8 × 12")
            && pendingGrid.collectionView.reloaded == [IndexPath(item: 0, section: 0)]

        let topologyGrid = MetadataGrid()
        topologyGrid.dataSource.holdCompletion = true
        topologyGrid.update(wallpapers: [a])
        wait("old topology did not begin") { topologyGrid.isApplyingSnapshot }
        topologyGrid.update(wallpapers: [offscreen, portrait])
        wait("new topology did not pend") { !topologyGrid.isSnapshotScheduled }
        checks["metadataForNewTopologyCannotReloadOldIndices"] = topologyGrid.collectionView.reloaded.isEmpty
            && topologyGrid.dataSource.applies == 1
        topologyGrid.dataSource.releaseCompletion()
        wait("latest topology did not apply after old completion") { topologyGrid.lastAppliedIDs == ["B", "A"] }
        checks["latestTopologyRetainsSerialSnapshotAndCurrentMetadata"] = topologyGrid.dataSource.applies == 2
            && topologyGrid.cells["A"]!.metaLabel.stringValue.contains("8 × 12")
            && topologyGrid.collectionView.reloaded == Set([IndexPath(item: 1, section: 0)]).intersection(topologyGrid.collectionView.visible)
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
