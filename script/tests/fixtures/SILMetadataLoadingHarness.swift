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
    var migrationRecoveryMessage: String?
    var allowsLibraryMutation: Bool { migrationRecoveryMessage == nil }
    static var defersMissingFileCleanupForPersonalSettingsRecovery = false
    var selectedIDs: Set<String> = []
    var selectedID: String?
    var inspectedWallpaperID: String?
    func scheduleInitialMissingFilesAlert(for removed: [SILWallpaper], attempt: Int) {}
    func reconcileForAudit() { reconcileMissingFilesOnLaunch() }
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

@MainActor enum SILCardObservation { static var configurations = 0 }
@MainActor final class CountingFlowLayout: NSCollectionViewFlowLayout {
    private(set) var invalidations = 0
    override func invalidateLayout() { invalidations += 1; super.invalidateLayout() }
}
@MainActor final class CountingLibraryCollectionView: WallpaperLibraryCollectionView {
    private(set) var reloads = 0
    private(set) var reloaded = Set<IndexPath>()
    override func reloadData() { reloads += 1; super.reloadData() }
    override func reloadItems(at paths: Set<IndexPath>) { reloaded.formUnion(paths); super.reloadItems(at: paths) }
}
@MainActor final class MetadataItems: NSObject, NSCollectionViewDataSource {
    var count = 2
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem { NSCollectionViewItem() }
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

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let images = SILService()
        let adapter = WallpaperLibraryCellAdapter(manager: WallpaperManager(), images: images,
            steam: SteamWorkshopService(), pixabay: PixabayService(),
            isPlaying: { _ in false }, makePrimaryAction: { _ in nil })
        let grid = WallpaperLibraryGridController { collection, index, content, state in
            adapter.makeCell(collection: collection, indexPath: index, content: content, state: state)
        }
        grid.updateCell = { adapter.updateCell($0, content: $1, state: $2) }
        grid.setCellVisible = { adapter.setVisible($0, $1) }
        grid.loadViewIfNeeded(); grid.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        grid.view.layoutSubtreeIfNeeded()
        func content(_ values: [SILWallpaper]) -> [WallpaperContentItem] {
            images.wallpapers = values
            return values.map { StaticImageLibraryContentProjection.project($0, facts: .init(
                isPublishedLocally: true, isAvailable: true, canPlay: true, canDelete: true,
                localURL: URL(fileURLWithPath: $0.path))) }
        }
        let first = content([a, b])
        grid.update(page: .images, items: first, selection: .init(), preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        grid.layout.prepare()
        let initialFrame = grid.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        // A native collection gives the real App adapter its original reuse
        // path. The explicit card stays offscreen; no thumbnail decoder runs.
        let cards = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600)), dataSource = MetadataItems()
        cards.dataSource = dataSource; cards.collectionViewLayout = NSCollectionViewFlowLayout(); cards.reloadData()
        let state = WallpaperLibraryGridController.CellState(isSelected: false, isSelecting: false, isFocused: false)
        let cell = adapter.makeCell(collection: cards, indexPath: IndexPath(item: 0, section: 0), content: first[0], state: state) as! SILGridItem
        cell.view.frame = NSRect(x: 0, y: 0, width: initialFrame.width, height: initialFrame.height)
        cell.viewDidLayout(); cell.applyHoverVisibility(true, animated: false)
        checks["initialMissingDimensionsKeepSquareAndEmptySizeText"] = !cell.currentMetadata.contains("×")
            && initialFrame.width == initialFrame.height
        let structuralReloads = grid.collection.reloads
        var portrait = a; portrait.pixelWidth = 8; portrait.pixelHeight = 12
        var offscreen = b; offscreen.pixelWidth = 12; offscreen.pixelHeight = 8
        let patched = content([portrait, offscreen])
        grid.update(page: .images, items: patched, selection: grid.selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        adapter.updateCell(cell, content: patched[0], state: state)
        let finalFrame = grid.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        let metadataDiagnostic: [String] = [
            "same-id-metadata initial=\(initialFrame) final=\(finalFrame) geometryEqual=\(finalFrame == initialFrame)",
            "sourceID=\(portrait.id) width=\(String(describing: portrait.pixelWidth)) height=\(String(describing: portrait.pixelHeight))",
            "projectedResolution=\(String(describing: patched[0].metadata.resolutionText)) cardMetadata=\(cell.currentMetadata)",
            "barExists=\(cell.controlBar != nil) barTip=\(String(describing: cell.controlBar?.toolTip)) titleHelp=\(String(describing: cell.controlBar?.titleView.accessibilityHelp()))",
            "cardFrame=\(cell.view.frame) coverBounds=\(cell.imageContainer.bounds) clip=\(grid.scrollView.contentView.bounds)",
            "configurations=\(SILCardObservation.configurations) reloads=\(grid.collection.reloads) itemReloads=\(grid.collection.reloaded)"
        ]
        FileHandle.standardError.write(Data((metadataDiagnostic.joined(separator: "\n") + "\n").utf8))
        checks["sameIDsRefreshMetadataWithoutChangingSquareGeometry"] = finalFrame == initialFrame
            && cell.currentMetadata.contains("8 × 12")
            && cell.controlBar?.titleView.accessibilityHelp() == cell.currentMetadata
            && cell.controlBar?.toolTip == nil && cell.controlBar?.titleView.toolTip == nil
        checks["metadataUpdatesReuseTheRealCardWithoutStructuralReload"] = grid.collection.reloads == structuralReloads
            && grid.collection.reloaded.isEmpty && grid.items == patched
        let invalidations = grid.layout.invalidations, configures = SILCardObservation.configurations
        grid.update(page: .images, items: patched, selection: grid.selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        adapter.updateCell(cell, content: patched[0], state: state)
        checks["identicalMetadataSkipsLayoutReloadAndSnapshot"] = grid.layout.invalidations == invalidations
            && grid.collection.reloads == structuralReloads && grid.collection.reloaded.isEmpty
            && SILCardObservation.configurations == configures && grid.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame == finalFrame
        // The replacement grid has synchronous native reloads, so there is no
        // retired diffable completion to hold. Rapid updates must retain the
        // latest topology and metadata without addressing old indices.
        let beforeTopology = grid.collection.reloads
        grid.update(page: .images, items: [first[0]], selection: grid.selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        grid.update(page: .images, items: [patched[1], patched[0]], selection: grid.selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        let afterTopology = grid.collection.reloads
        grid.update(page: .images, items: [patched[1], patched[0]], selection: grid.selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        checks["rapidTopologyChangesPublishTheLatestNativeOrderAndMetadata"] = grid.items == [patched[1], patched[0]]
            && afterTopology == beforeTopology + 2 && grid.collection.reloads == afterTopology
            && grid.items[1].metadata.resolutionText == "8×12" && grid.collection.reloaded.isEmpty
        let offline = record("offline-recovery", index.deletingLastPathComponent().appendingPathComponent("missing-image.png").path)
        try persist([offline], at: index)
        let preserved = try Data(contentsOf: index)
        let recovery = MetadataProbe(index), recoveryBatch = completedBatches
        recovery.migrationRecoveryMessage = "Migration needs recovery"
        recovery.load()
        wait("read-only metadata callback did not settle") { completedBatches > recoveryBatch }
        recovery.reconcileForAudit()
        recovery.save()
        checks["failedMigrationSILKeepsOfflineRecordAndOriginalBytes"] = try recovery.wallpapers == [offline]
            && Data(contentsOf: index) == preserved
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
