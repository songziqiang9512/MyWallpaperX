import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// PRODUCTION_MODEL
// PRODUCTION_RESULT
// PRODUCTION_IMAGE_LEAVES

@MainActor private final class VisibleItems {
    var visible = [10, 11, 12, 13, 14, 15]
    var displayedItems: [NSCollectionViewItem] = []
    func indexPathsForVisibleItems() -> Set<IndexPath> {
        Set(visible.map { IndexPath(item: $0, section: 0) })
    }
    func visibleItems() -> [NSCollectionViewItem] { displayedItems }
}

@MainActor private final class PrefetchGrid: NSView {
    struct Record { let path: String }
    let collectionView = VisibleItems()
    let thumbnailCache = ThumbnailCache(countLimit: 8, namespace: "sil-demand-fixture")
    var orderedIDs: [String] = []
    var lastAppliedIDs: [String] = []
    var wallpapersByID: [String: Record] = [:]
    var isScrollToTopAnimating = false
    var failedThumbnailSignatures = Set<String>()
    var missingPathWindowObservers = [NSObjectProtocol]()
    // PRODUCTION_GRID_STATE
    init(paths: [String]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        orderedIDs = paths.indices.map(String.init)
        lastAppliedIDs = orderedIDs
        wallpapersByID = Dictionary(uniqueKeysWithValues: zip(orderedIDs, paths).map { ($0, Record(path: $1)) })
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        missingPathWindowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    var tokens: [String: ThumbnailCacheRequestCancellation] { thumbnailPrefetchTokens.mapValues(\.token) }
    var pendingWork: DispatchWorkItem? { thumbnailPrefetchWork }
    func fire() { prefetchNearbyThumbnails() }
    func schedule() { scheduleThumbnailPrefetch() }
    func cancel() { cancelThumbnailPrefetch() }
    // Unrelated filesystem-probe/toplevel-scroll leaves; demand methods are unmodified.
    func updateMissingPathProbeTimer() {}
    func scheduleRestingScrollOriginCapture() {}
    // PRODUCTION_GRID_METHODS
}

@main private enum Checks {
    @MainActor static func pump(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
    @MainActor static func wait(_ reason: String, until predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() { precondition(Date() < deadline, reason); pump(0.003) }
    }
    static func writePNG(_ path: URL) throws {
        let color = CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)
        let context = CGContext(data: nil, width: 1000, height: 700, bitsPerComponent: 8,
            bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
        let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.png")
        try writePNG(original)
        let paths = try (0..<40).map { index -> String in
            let url = root.appendingPathComponent("\(index).png")
            try FileManager.default.copyItem(at: original, to: url)
            return url.path
        }
        var checks: [String: Bool] = [:]
        let grid = PrefetchGrid(paths: paths)
        let window = NSWindow(contentRect: grid.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: 14000, y: 14000))
        let host = NSView(frame: grid.frame)
        host.addSubview(grid)
        window.contentView = host
        window.orderFrontRegardless()
        defer { grid.cancel(); window.orderOut(nil); window.close() }
        grid.fire()
        let firstTokens = grid.tokens
        checks["nearbyDemandIsBounded"] = firstTokens.count == 6
        checks["forwardNearestIsIncluded"] = firstTokens["16"] != nil
        checks["backwardNearestIsIncluded"] = firstTokens["9"] != nil
        checks["visibleItemsDoNotStartPrefetch"] = (10...15).allSatisfy { firstTokens[String($0)] == nil }
        wait("nearby decoded images") {
            firstTokens.keys.allSatisfy { grid.thumbnailCache.cachedImage(forKey: paths[Int($0)!]) != nil }
        }
        pump(0.02)
        let ready = grid.thumbnailCache.cachedImage(forKey: paths[16])!
        // NSImage(cgImage:size:.zero) may expose a Retina bitmap rep; its
        // logical size retains the bounded ImageIO image dimensions.
        checks["nearbyImageIsDownsampled"] = ready.size.width == 512 && ready.size.height <= 512
        for _ in 0..<20 { grid.fire() }
        checks["unchangedViewportRetainsLeases"] = firstTokens.allSatisfy { grid.tokens[$0.key] === $0.value }
        var extraLoads = 0
        for index in 0..<12 {
            grid.thumbnailCache.load(forKey: "other-consumer-\(index)", loader: { ready }) { _ in extraLoads += 1 }
        }
        wait("other consumers finish") { extraLoads == 12 }
        checks["testActuallyEvictsNearbyImages"] = grid.thumbnailCache.cachedImage(forKey: paths[16]) == nil
        grid.fire()
        let handoffToken = grid.tokens["16"]
        wait("evicted near images reheat") { grid.thumbnailCache.cachedImage(forKey: paths[16]) != nil }
        checks["completedEvictedDemandCanReheat"] = handoffToken !== firstTokens["16"] && firstTokens["16"]?.cancelled == true
        grid.collectionView.visible = Array(16...21)
        grid.fire()
        checks["nearbyBecomingVisibleRetainsProducer"] = grid.tokens["16"] === handoffToken
            && handoffToken?.cancelled == false
        checks["farOldRequestsAreCancelled"] = firstTokens["7"]?.cancelled == true
        grid.collectionView.visible = Array(4...9)
        grid.fire()
        checks["reverseScrollPreparesBothNearestSides"] = grid.tokens["3"] != nil && grid.tokens["10"] != nil
        checks["boundedAfterReverse"] = grid.tokens.count <= 12
        let old = grid.tokens["3"]!
        grid.wallpapersByID["3"] = .init(path: original.path)
        grid.fire()
        checks["changedSourceRevokesOldLease"] = old.cancelled && grid.tokens["3"] !== old
        let beforeClear = grid.tokens
        grid.cancel()
        checks["cancelReleasesEveryLease"] = grid.tokens.isEmpty && beforeClear.values.allSatisfy(\.cancelled)
        grid.schedule()
        let scheduled = grid.pendingWork
        for _ in 0..<50 { grid.schedule() }
        checks["continuousInputDoesNotResetThrottle"] = grid.pendingWork === scheduled
        wait("coalesced demand fires") { !grid.tokens.isEmpty }
        checks["scheduledWorkCompletes"] = grid.pendingWork == nil
        let windowCard = SILGridItem()
        _ = windowCard.view
        grid.addSubview(windowCard.view)
        grid.collectionView.displayedItems = [windowCard]
        var windowCardToken: ThumbnailCacheRequestCancellation?
        windowCard.configure(wallpaper: SILWallpaper(path: paths[0]), isSelected: false,
            isMultiSelectMode: false, thumbnailVisible: true) { request, _ in windowCardToken = request }
        let orderedOutCardToken = windowCardToken
        let orderedOutTokens = grid.tokens
        window.orderOut(nil)
        wait("native orderOut retires demand") {
            grid.tokens.isEmpty && grid.pendingWork == nil && orderedOutCardToken?.cancelled == true
        }
        checks["hiddenWindowReleasesDemand"] = orderedOutTokens.values.allSatisfy(\.cancelled)
        checks["nativeOrderOutCancelsActualCard"] = orderedOutCardToken?.cancelled == true
        window.orderFrontRegardless()
        wait("native orderIn resumes demand") { !grid.tokens.isEmpty }
        checks["nativeOrderInRestartsNearbyDemand"] = !grid.tokens.isEmpty
        checks["nativeOrderInResumesActualCard"] = windowCardToken !== orderedOutCardToken && windowCardToken?.cancelled == false
        host.isHidden = true
        wait("native ancestor hide retires demand") { grid.tokens.isEmpty }
        checks["ancestorHiddenStopsDemand"] = grid.tokens.isEmpty && windowCardToken?.cancelled == true
        host.isHidden = false
        wait("native ancestor reveal resumes demand") { !grid.tokens.isEmpty }
        checks["ancestorRevealResumesDemand"] = !grid.tokens.isEmpty
        grid.lastAppliedIDs = []
        grid.fire()
        checks["pendingSnapshotDoesNotPrefetchWrongIDs"] = grid.tokens.isEmpty
        grid.lastAppliedIDs = grid.orderedIDs
        grid.collectionView.visible = []
        grid.fire()
        checks["emptyViewportDoesNotStartWork"] = grid.tokens.isEmpty

        let record = SILWallpaper(path: paths[0])
        let item = SILGridItem()
        _ = item.view
        item.view.frame = NSRect(x: 0, y: 0, width: 260, height: 180)
        var callback: ((SILThumbnailLoadResult) -> Void)?
        var token: ThumbnailCacheRequestCancellation?
        let loader: (ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void = {
            token = $0; callback = $1
        }
        item.configure(wallpaper: record, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true, thumbnailLoader: loader)
        checks["warmWaitStartsWithoutLoadingFlash"] = item.placeholderLabel.isHidden
        callback?(.image(ready))
        pump(0.13)
        checks["readyImageSuppressesDelayedPlaceholder"] = item.placeholderLabel.isHidden && item.thumbnailView.image === ready
        item.setThumbnailVisible(false)
        item.setThumbnailVisible(true)
        checks["readyImageSurvivesVisibilityWithoutReload"] = item.thumbnailView.image === ready && item.thumbnailRequestFinished
        item.configure(wallpaper: record, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true, thumbnailLoader: loader)
        pump(0.13)
        checks["realSlowLoadStillShowsLoading"] = !item.placeholderLabel.isHidden
        let hiddenToken = token, hiddenCallback = callback
        item.setThumbnailVisible(false)
        hiddenCallback?(.image(ready))
        checks["offscreenCancelsUnfinishedConsumer"] = hiddenToken?.cancelled == true && item.thumbnailView.image == nil
        item.setThumbnailVisible(true)
        checks["redisplayRestartsOnlyUnfinishedRequest"] = token !== hiddenToken && token?.cancelled == false
        let reusedToken = token, oldCallback = callback
        item.prepareForReuse()
        oldCallback?(.image(ready))
        pump(0.13)
        checks["reuseRevokesConsumer"] = reusedToken?.cancelled == true
        checks["reusedCardRejectsOldImageAndLoadingWork"] = item.thumbnailView.image == nil && item.placeholderLabel.isHidden
        item.configure(wallpaper: record, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true) { _, reply in reply(.missingFile) }
        checks["missingFileIsImmediateAndVisible"] = !item.placeholderLabel.isHidden && item.placeholderLabel.stringValue == "原文件不存在"
        item.configure(wallpaper: record, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true) { _, reply in reply(.unavailable) }
        checks["decodeFailureIsImmediateAndVisible"] = !item.placeholderLabel.isHidden && item.placeholderLabel.stringValue == "缩略图不可用"
        item.configure(wallpaper: record, isSelected: true, isMultiSelectMode: true, thumbnailVisible: true) { _, reply in reply(.image(ready)) }
        checks["selectionAndMultiselectStillApply"] = item.isSelectedState && item.isMultiSelect
        item.setThumbnailVisible(false)
        var hiddenLoadCount = 0
        item.configure(wallpaper: record, isSelected: false, isMultiSelectMode: false, thumbnailVisible: false) { request, reply in
            hiddenLoadCount += 1; token = request; callback = reply
        }
        var replacement = record
        replacement.id = "replacement"
        item.configure(wallpaper: replacement, isSelected: false, isMultiSelectMode: false, thumbnailVisible: false) { request, reply in
            hiddenLoadCount += 1; token = request; callback = reply
        }
        checks["hiddenReconfigureDoesNotStartVisibleWork"] = hiddenLoadCount == 0
        item.setThumbnailVisible(true)
        checks["showAfterHiddenReconfigureLoadsLatestOnly"] = hiddenLoadCount == 1 && item.wallpaperID == replacement.id
        callback?(.image(ready))
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
