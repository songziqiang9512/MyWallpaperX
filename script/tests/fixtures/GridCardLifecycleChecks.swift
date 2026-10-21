import AppKit
import AVFoundation
import Foundation
import ObjectiveC
import QuartzCore

// Only data transport is controlled. The two complete production card files,
// their true Equatable models, AppKit hierarchy and completion bodies compile
// alongside this fixture. No loader below reads network or user media.
@MainActor final class CardThumbnailTransport {
    struct Pending {
        let key: String
        let completion: (NSImage?) -> Void
    }
    var cached: [String: NSImage] = [:]
    var pending: [Int: Pending] = [:]
    var history: [(Int, String)] = []
    private var nextID = 0

    init(label: String, countLimit: Int, totalCostLimit: Int,
         namespace: String, usesFailureCache: Bool) {}

    func cachedImage(forKey key: String) -> NSImage? { cached[key] }

    func load(forKey key: String, loader: @escaping () -> NSImage?,
              completion: @escaping (NSImage?) -> Void) {
        // Do not execute the AVAsset loader. Keep every callback, including
        // equal-key requests, so stale success/failure is deliverable.
        nextID += 1
        pending[nextID] = Pending(key: key, completion: completion)
        history.append((nextID, key))
    }

    func loadImageAsync(forKey key: String, priority: ThumbnailCacheRequestPriority,
        cancellation: ThumbnailCacheRequestCancellation?, loader: @escaping @Sendable () async -> NSImage?,
        completion: @escaping (NSImage?) -> Void) {
        nextID += 1
        pending[nextID] = Pending(key: key, completion: completion)
        history.append((nextID, key))
    }

    func deliver(_ ticket: Int, image: NSImage?) {
        precondition(Thread.isMainThread)
        guard let request = pending.removeValue(forKey: ticket) else {
            preconditionFailure("unknown Downloads transport ticket \(ticket)")
        }
        request.completion(image)
    }
}

nonisolated enum ThumbnailCacheRequestPriority { case visible, prefetch }
nonisolated final class ThumbnailCacheRequestCancellation: @unchecked Sendable { var cancelled: Bool { false }; func cancel() {} }

@MainActor final class OLThumbnailCache {
    static let shared = OLThumbnailCache()
    struct Pending {
        let url: URL
        let pixels: Int
        let continuation: CheckedContinuation<NSImage?, Never>
    }
    var pending: [Int: Pending] = [:]
    var history: [(Int, URL, Int)] = []
    var decoded: [Data: NSImage] = [:]
    private var nextID = 0

    var generation = 0
    func publicationGeneration() async -> Int { generation }

    func readyImage(for url: URL, maxPixelSize: Int) -> NSImage? { nil }

    func cachedImage(for url: URL, maxPixelSize: Int) async -> NSImage? {
        await withCheckedContinuation { continuation in
            nextID += 1
            pending[nextID] = Pending(url: url, pixels: maxPixelSize, continuation: continuation)
            history.append((nextID, url, maxPixelSize))
        }
    }

    func storeAndDecode(data: Data, for url: URL, maxPixelSize: Int, generation: Int) async -> NSImage? {
        decoded[data]
    }

    func image(for url: URL, maxPixelSize: Int, priority: OLThumbnailRequestPriority) async -> NSImage? {
        let generation = await publicationGeneration()
        if let image = await cachedImage(for: url, maxPixelSize: maxPixelSize) { return image }
        guard !Task.isCancelled,
              let data = await OLThumbnailRequestCoordinator.shared.loadData(from: url, priority: priority),
              !Task.isCancelled else { return nil }
        return await storeAndDecode(data: data, for: url, maxPixelSize: maxPixelSize, generation: generation)
    }

    func deliver(_ ticket: Int, image: NSImage?) {
        guard let request = pending.removeValue(forKey: ticket) else {
            preconditionFailure("unknown Browser cache ticket \(ticket)")
        }
        request.continuation.resume(returning: image)
    }
}

enum OLThumbnailRequestPriority { case visible }

@MainActor final class OLThumbnailRequestCoordinator {
    static let shared = OLThumbnailRequestCoordinator()
    struct Pending {
        let url: URL
        let continuation: CheckedContinuation<Data?, Never>
    }
    var pending: [Int: Pending] = [:]
    var history: [(Int, URL)] = []
    var returned: Set<Int> = []
    private var nextID = 0

    func loadData(from url: URL, priority: OLThumbnailRequestPriority) async -> Data? {
        var ticket = 0
        let result: Data? = await withCheckedContinuation { continuation in
            nextID += 1
            ticket = nextID
            pending[ticket] = Pending(url: url, continuation: continuation)
            history.append((ticket, url))
        }
        returned.insert(ticket)
        return result
    }

    func deliver(_ ticket: Int, data: Data?) {
        guard let request = pending.removeValue(forKey: ticket) else {
            preconditionFailure("unknown Browser network ticket \(ticket)")
        }
        // Ignore cancellation in this transport: the real card must reject
        // the late reply with its own Task/identity checks.
        request.continuation.resume(returning: data)
    }
}

// Browser failure's only mutation is spinner.stopAnimation. Observe the real
// NSProgressIndicator call, invoke its original implementation, then restore the
// method before this isolated process exits. No UI object is substituted.
@MainActor enum SpinnerObservation {
    static var stops: [ObjectIdentifier: Int] = [:]
    static func count(_ spinner: NSProgressIndicator) -> Int { stops[ObjectIdentifier(spinner), default: 0] }
    static func exchange() -> Bool {
        guard let original = class_getInstanceMethod(NSProgressIndicator.self,
                  #selector(NSProgressIndicator.stopAnimation(_:))),
              let observer = class_getInstanceMethod(NSProgressIndicator.self,
                  #selector(NSProgressIndicator.gridCardObservedStop(_:))) else { return false }
        method_exchangeImplementations(original, observer)
        return true
    }
}

extension NSProgressIndicator {
    @objc dynamic func gridCardObservedStop(_ sender: Any?) {
        SpinnerObservation.stops[ObjectIdentifier(self), default: 0] += 1
        gridCardObservedStop(sender)
    }
}

@MainActor final class Facts {
    var checks: [String: Bool] = [:]
    var details: [String: String] = [:]
    func expect(_ name: String, _ passed: Bool, _ detail: String = "") {
        checks[name] = (checks[name] ?? true) && passed
        if !passed { details[name] = detail }
    }
    func emit(_ name: String) {
        let object: [String: Any] = ["case": name, "checks": checks, "details": details]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}

@MainActor func pump(_ seconds: TimeInterval) {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    repeat {
        CATransaction.flush()
        _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
        for _ in 0..<100 {
            guard let event = NSApp.nextEvent(matching: .any, until: .distantPast,
                inMode: .default, dequeue: true) else { break }
            NSApp.sendEvent(event)
        }
    } while ProcessInfo.processInfo.systemUptime < end
}

@MainActor @discardableResult
func waitUntil(_ seconds: TimeInterval = 1, _ predicate: () -> Bool) -> Bool {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    while !predicate() && ProcessInfo.processInfo.systemUptime < end { pump(0.004) }
    return predicate()
}

@MainActor func layout(_ item: NSCollectionViewItem) {
    item.view.needsLayout = true
    item.view.layoutSubtreeIfNeeded()
    // Drive the complete controller callback, including its production key.
    item.viewDidLayout()
    CATransaction.flush()
}

func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 0.01 }
func samePoint(_ lhs: NSPoint, _ rhs: NSPoint) -> Bool { close(lhs.x, rhs.x) && close(lhs.y, rhs.y) }

@MainActor func browserModel(_ id: Int, tags: String = "forest", duration: Int = 11,
                             thumbnail: String? = "a", bytes: Int = 1_048_576,
                             width: Int = 1920) -> OnlineLibraryVideoItem {
    let file = OnlineLibraryVideoFile(url: "https://fixture.invalid/video/\(id)",
        width: width, height: 1080, size: bytes,
        thumbnail: thumbnail.map { "https://fixture.invalid/\($0).jpg" } ?? "")
    return OnlineLibraryVideoItem(id: id, pageURL: "https://fixture.invalid/page/\(id)/\(duration)",
        tags: tags, duration: duration, user: "fixture",
        videos: OnlineLibraryVideoFiles(large: nil, medium: file, small: nil, tiny: nil))
}

@MainActor func downloadModel(_ id: Int, name: String = "forest.mp4", bytes: Int = 1_048_576,
                              duration: Int? = 11, resolution: String? = "1920×1080") -> OLDownloadedEntry {
    OLDownloadedEntry(id: id, localURL: URL(fileURLWithPath: "/fixture/\(name)"),
                      fileSize: bytes, duration: duration, resolutionString: resolution)
}

@MainActor func configure(_ card: AppKitOLBrowserItem, _ item: OnlineLibraryVideoItem,
                          downloading: Bool = false, downloaded: Bool = false) {
    card.configure(item: item, isDownloading: downloading, isDownloaded: downloaded,
        downloadProgress: downloading ? 0.7 : nil, onDownload: {}, onSetAsWallpaper: {})
}

@MainActor func image(_ marker: Int) -> NSImage {
    NSImage(size: NSSize(width: CGFloat(31 + marker), height: CGFloat(19 + marker)))
}

// Controlled inputs on a real NSWindow. The scale override exercises delivery
// through the production backing-change callback without moving a real display.
@MainActor final class CardWindow: NSWindow {
    var testPointer = NSPoint(x: -10_000, y: -10_000)
    var testBackingScale: CGFloat = 1
    override var mouseLocationOutsideOfEventStream: NSPoint { testPointer }
    override var backingScaleFactor: CGFloat { testBackingScale }
}

@MainActor final class CardHost: NSObject, NSCollectionViewDataSource {
    enum Kind: Equatable { case browser, downloads }
    let kind: Kind
    let window: CardWindow
    let scroll = WallpaperGridScrollView()
    let collection = NSCollectionView()
    let flow = NSCollectionViewFlowLayout()
    var count: Int
    var made: [(ObjectIdentifier, Int, Bool)] = []
    var retained: [ObjectIdentifier: NSCollectionViewItem] = [:]

    init(_ kind: Kind, count: Int = 1) {
        self.kind = kind
        self.count = count
        window = CardWindow(contentRect: NSRect(x: 14_000, y: 14_000, width: 278, height: 210),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init()
        scroll.frame = NSRect(x: 0, y: 0, width: 278, height: 210)
        scroll.hasVerticalScroller = true
        flow.itemSize = NSSize(width: 240, height: 180)
        flow.minimumLineSpacing = 8
        flow.minimumInteritemSpacing = 8
        collection.collectionViewLayout = flow
        collection.isSelectable = true
        collection.frame = NSRect(x: 0, y: 0, width: 260, height: 210)
        collection.dataSource = self
        switch kind {
        case .browser:
            collection.register(AppKitOLBrowserItem.self,
                forItemWithIdentifier: AppKitOLBrowserItem.reuseIdentifier)
        case .downloads:
            collection.register(AppKitOLDownloadsItem.self,
                forItemWithIdentifier: AppKitOLDownloadsItem.reuseIdentifier)
        }
        scroll.documentView = collection
        window.contentView = scroll
        // Real NSAnimationContext completions require an ordered window. It is
        // far offscreen; the harness never reads or moves the real mouse.
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
        collection.reloadData()
        collection.layoutSubtreeIfNeeded()
        pump(0.04)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { count }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item: NSCollectionViewItem
        let wasPrepared: Bool
        switch kind {
        case .browser:
            let card = collectionView.makeItem(withIdentifier: AppKitOLBrowserItem.reuseIdentifier,
                for: indexPath) as! AppKitOLBrowserItem
            _ = card.view
            wasPrepared = card.currentItemID == -1 && card.presentedItem == nil && card.thumbnailView.image == nil
            configure(card, browserModel(10_000 + indexPath.item, thumbnail: nil))
            item = card
        case .downloads:
            let card = collectionView.makeItem(withIdentifier: AppKitOLDownloadsItem.reuseIdentifier,
                for: indexPath) as! AppKitOLDownloadsItem
            _ = card.view
            wasPrepared = card.currentEntryID == -1 && card.presentedEntry == nil && card.thumbnailView.image == nil
            card.configure(entry: downloadModel(10_000 + indexPath.item, name: "pool-\(indexPath.item).mp4"),
                isSelected: false, isMultiSelectMode: false, isPlaying: false)
            item = card
        }
        made.append((ObjectIdentifier(item), indexPath.item, wasPrepared))
        // Prevent a deallocated object's address from impersonating pool reuse.
        retained[ObjectIdentifier(item)] = item
        return item
    }

    func first() -> NSCollectionViewItem? {
        collection.item(at: IndexPath(item: 0, section: 0))
    }

    var visible: [NSCollectionViewItem] { collection.visibleItems() }

    func begin() {
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    }

    func end() {
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    }

    func scrollTo(_ index: Int) {
        collection.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .top)
        collection.layoutSubtreeIfNeeded()
        pump(0.035)
    }

    func finish() {
        collection.dataSource = nil
        window.orderOut(nil)
        window.close()
    }
}

@MainActor func isHovering(_ item: NSCollectionViewItem) -> Bool {
    if let card = item as? AppKitOLBrowserItem { return card.isHovering }
    if let card = item as? AppKitOLDownloadsItem { return card.isHovering }
    preconditionFailure("unexpected real card type")
}

@MainActor func idleHoverPresentation(_ item: NSCollectionViewItem) -> Bool {
    if let card = item as? AppKitOLBrowserItem {
        return !card.isHovering && !card.hoverVisible && close(card.titleLabel.alphaValue, 0)
            && close(card.metaLabel.alphaValue, 0) && card.gradientLayer.opacity == 0
            && close(card.currentCardScale, 1)
    }
    if let card = item as? AppKitOLDownloadsItem {
        return !card.isHovering && close(card.titleLabel.alphaValue, 0)
            && close(card.metaLabel.alphaValue, 0) && close(card.playActionButton.alphaValue, 0)
            && card.gradientLayer.opacity == 0 && close(card.currentCardScale, 1)
    }
    return false
}

@MainActor func imageRect(_ item: NSCollectionViewItem) -> NSRect {
    if let card = item as? AppKitOLBrowserItem { return card.imageContainer.frame }
    if let card = item as? AppKitOLDownloadsItem { return card.imageContainer.frame }
    preconditionFailure("unexpected real card type")
}

@MainActor func sendHoverEvents(_ item: NSCollectionViewItem, in host: CardHost,
                               point: NSPoint, facts: Facts, label: String) {
    let location = item.view.convert(point, to: nil)
    host.window.testPointer = location
    guard let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: location,
              modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
              windowNumber: host.window.windowNumber, context: nil, eventNumber: 1,
              trackingNumber: 0, userData: nil),
          let moved = NSEvent.mouseEvent(with: .mouseMoved, location: location,
              modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
              windowNumber: host.window.windowNumber, context: nil, eventNumber: 2,
              clickCount: 0, pressure: 0) else {
        facts.expect(label + ".native-hover-events-constructed", false); return
    }
    facts.expect(label + ".native-hover-events-constructed", true)
    item.mouseEntered(with: entered)
    item.mouseMoved(with: moved)
}

@MainActor func realCardScrollHover(_ facts: Facts) {
    for kind in [CardHost.Kind.browser, .downloads] {
        let label = kind == .browser ? "browser" : "downloads"
        let host = CardHost(kind, count: 30)
        defer { host.finish() }
        facts.expect(label + ".actual-active-visible-window", NSApp.isActive && host.window.isVisible)
        guard let existing = host.first() else { facts.expect(label + ".existing-card", false); continue }
        let hit = imageRect(existing).intersection(existing.view.visibleRect)
        guard !hit.isEmpty else { facts.expect(label + ".existing-visible-image", false); continue }
        let point = NSPoint(x: hit.midX, y: hit.midY)
        // Prime the real class's activation path: entered events would otherwise
        // be ignored even if the scrolling guard were absent.
        sendHoverEvents(existing, in: host, point: point, facts: facts, label: label + ".idle")
        facts.expect(label + ".idle-real-mouse-move-starts-hover", isHovering(existing))
        let representedBefore = Set(host.made.map { $0.1 })
        host.begin()
        facts.expect(label + ".begin-clears-existing-hover", !isHovering(existing)
            && existing.view.isGridHoverSuppressed)
        sendHoverEvents(existing, in: host, point: point, facts: facts, label: label + ".scroll-existing")
        layout(existing)
        pump(0.40)
        facts.expect(label + ".existing-card-events-and-layout-cannot-restore-hover", idleHoverPresentation(existing))
        host.scrollTo(18)
        let incoming = host.visible.filter {
            guard let index = host.collection.indexPath(for: $0) else { return false }
            return !representedBefore.contains(index.item)
        }
        facts.expect(label + ".native-scroll-reaches-newly-configured-real-cards", !incoming.isEmpty)
        var incomingEventCount = 0
        for (offset, card) in incoming.enumerated() {
            let rectangle = imageRect(card).intersection(card.view.visibleRect)
            guard !rectangle.isEmpty else { continue }
            facts.expect(label + ".incoming-\(offset)-reads-active-scroll", card.view.isGridHoverSuppressed)
            incomingEventCount += 1
            sendHoverEvents(card, in: host, point: NSPoint(x: rectangle.midX, y: rectangle.midY),
                facts: facts, label: label + ".scroll-new-\(offset)")
            layout(card)
        }
        facts.expect(label + ".incoming-real-card-receives-inside-image-events", incomingEventCount > 0)
        pump(0.40)
        facts.expect(label + ".new-card-events-and-layout-stay-non-hover", !incoming.isEmpty
            && incoming.allSatisfy { idleHoverPresentation($0) })
        // Move the native clip while the gate is active, then locate an actual
        // partly visible card rather than assuming a collection's flippedness.
        let origin = host.scroll.contentView.bounds.origin
        host.scroll.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + 45))
        host.scroll.reflectScrolledClipView(host.scroll.contentView)
        host.collection.layoutSubtreeIfNeeded()
        pump(0.03)
        guard let partial = host.visible.first(where: {
            let clipped = $0.view.bounds.intersection($0.view.visibleRect)
            return !clipped.isEmpty && clipped.height < $0.view.bounds.height - 2
        }) else { facts.expect(label + ".native-partial-card", false); continue }
        let bounds = partial.view.bounds, visible = bounds.intersection(partial.view.visibleRect)
        let candidates = [NSPoint(x: bounds.midX, y: bounds.minY + 1),
                          NSPoint(x: bounds.midX, y: bounds.maxY - 1)]
        guard let clipped = candidates.first(where: { bounds.contains($0) && !visible.contains($0) }) else {
            facts.expect(label + ".point-in-bounds-outside-clip", false); continue
        }
        host.window.testPointer = partial.view.convert(clipped, to: nil)
        host.end()
        pump(0.54) // Production quiet close followed by the normal hover exit.
        facts.expect(label + ".end-does-not-restore-clipped-away-pointer", !host.scroll.isGridScrolling
            && !isHovering(partial) && !partial.view.isGridPointerInside && idleHoverPresentation(partial),
            "bounds=\(bounds), clip=\(visible), pointer=\(clipped)")
        host.begin()
        host.window.testPointer = partial.view.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
        host.end()
        pump(0.54)
        facts.expect(label + ".end-restores-current-clipped-visible-pointer", !host.scroll.isGridScrolling
            && partial.view.isGridPointerInside && isHovering(partial),
            "active=\(NSApp.isActive) window=\(host.window.isVisible) scrolling=\(host.scroll.isGridScrolling) inside=\(partial.view.isGridPointerInside) hover=\(isHovering(partial)) frame=\(partial.view.frame) bounds=\(partial.view.bounds) clip=\(partial.view.visibleRect) pointer=\(partial.view.convert(host.window.testPointer, from: nil)) visibleItems=\(host.visible.contains(partial))")
    }
}

@MainActor func backingScaleRequests(_ facts: Facts) {
    let host = CardHost(.browser, count: 5)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLBrowserItem else { facts.expect("registered-browser", false); return }
    let cache = OLThumbnailCache.shared
    let model = browserModel(71, thumbnail: "backing-scale")
    let before = Set(cache.pending.keys)
    configure(card, model)
    layout(card)
    let firstReady = waitUntil { !Set(cache.pending.keys).subtracting(before).isEmpty }
    facts.expect("scale-one-request-reaches-production-card", firstReady)
    guard let first = Set(cache.pending.keys).subtracting(before).first, let firstRequest = cache.pending[first] else { return }
    let small = image(7)
    cache.deliver(first, image: small)
    facts.expect("scale-one-image-delivered", waitUntil { card.thumbnailView.image === small })
    host.collection.layoutSubtreeIfNeeded()
    card.view.layoutSubtreeIfNeeded()
    let size = card.view.bounds.size
    let visible = host.visible
    facts.expect("scale-test-card-is-native-visible-item", visible.contains { $0 === card })
    facts.expect("initial-layout-settled-before-backing-change", !card.view.needsLayout)
    let pendingBeforeChange = Set(cache.pending.keys)
    host.window.testBackingScale = 2
    host.scroll.viewDidChangeBackingProperties()
    facts.expect("production-backing-callback-dirties-real-visible-cards", !visible.isEmpty
        && visible.allSatisfy { $0.view.needsLayout })
    // Do not call layout(card) or viewDidLayout here. The production scroll
    // callback's needsLayout must reach the real controller through AppKit.
    host.scroll.layoutSubtreeIfNeeded()
    host.collection.layoutSubtreeIfNeeded()
    let upgraded = waitUntil { !Set(cache.pending.keys).subtracting(pendingBeforeChange).isEmpty }
    facts.expect("same-size-backing-change-reaches-thumbnail-request", upgraded,
        "old pixels=\(firstRequest.pixels), current pixels=\(card.requestedPixelLimit)")
    guard let second = Set(cache.pending.keys).subtracting(pendingBeforeChange).first,
          let secondRequest = cache.pending[second] else { return }
    facts.expect("request-tier-increases-with-same-card-size", card.view.bounds.size == size
        && firstRequest.url == secondRequest.url && secondRequest.pixels > firstRequest.pixels
        && card.requestedPixelLimit == secondRequest.pixels,
        "injected NSWindow scale 1→2, size=\(size), pixels=\(firstRequest.pixels)→\(secondRequest.pixels)")
    let large = image(8)
    cache.deliver(second, image: large)
    facts.expect("upgraded-cache-image-reaches-card", waitUntil { card.thumbnailView.image === large })
    let requestCount = cache.history.count
    host.scroll.viewDidChangeBackingProperties()
    host.scroll.layoutSubtreeIfNeeded()
    host.collection.layoutSubtreeIfNeeded()
    pump(0.06)
    facts.expect("same-backing-scale-does-not-repeat-thumbnail-request", cache.history.count == requestCount
        && card.view.bounds.size == size && card.thumbnailView.image === large)
}

@MainActor func browserNetworkTicket(_ card: AppKitOLBrowserItem, _ model: OnlineLibraryVideoItem,
                                    _ facts: Facts, _ name: String) -> Int? {
    let cache = OLThumbnailCache.shared
    let network = OLThumbnailRequestCoordinator.shared
    let previousCache = Set(cache.pending.keys)
    let previousNetwork = Set(network.pending.keys)
    configure(card, model)
    let cacheReady = waitUntil { !Set(cache.pending.keys).subtracting(previousCache).isEmpty }
    facts.expect(name + ".cache-request", cacheReady)
    guard let cacheTicket = Set(cache.pending.keys).subtracting(previousCache).first else { return nil }
    cache.deliver(cacheTicket, image: nil)
    let networkReady = waitUntil { !Set(network.pending.keys).subtracting(previousNetwork).isEmpty }
    facts.expect(name + ".network-request", networkReady)
    return Set(network.pending.keys).subtracting(previousNetwork).first
}

@MainActor func nativePool(_ facts: Facts) {
    for kind in [CardHost.Kind.browser, .downloads] {
        let label = kind == .browser ? "browser" : "downloads"
        let host = CardHost(kind, count: 48)
        defer { host.finish() }
        facts.expect(label + ".real-registered-class", kind == .browser
            ? host.first() is AppKitOLBrowserItem : host.first() is AppKitOLDownloadsItem)
        for index in stride(from: 0, through: 46, by: 2) {
            host.scrollTo(index)
        }
        var firstIndex: [ObjectIdentifier: Int] = [:]
        var reused = 0
        var prepared = true
        for (identity, index, wasPrepared) in host.made {
            if let oldIndex = firstIndex[identity], oldIndex != index {
                reused += 1
                prepared = prepared && wasPrepared
            }
            firstIndex[identity] = index
        }
        facts.expect(label + ".native-pool-returned-same-object-for-new-row", reused > 0,
            "makeItem calls=\(host.made.count), distinct objects=\(firstIndex.count)")
        facts.expect(label + ".native-reuse-cleared-old-model-before-configure", reused > 0 && prepared)
    }
}

@MainActor func browserReplies(_ facts: Facts) {
    let host = CardHost(.browser)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLBrowserItem else {
        facts.expect("registered-browser", false); return
    }
    let observed = SpinnerObservation.exchange()
    facts.expect("observe-real-spinner-original-method", observed)
    guard observed else { return }
    defer { _ = SpinnerObservation.exchange() }
    let oldImage = image(1), newImage = image(2)
    let oldData = Data([0xA1]), newData = Data([0xA2])
    OLThumbnailCache.shared.decoded[oldData] = oldImage
    OLThumbnailCache.shared.decoded[newData] = newImage
    for (reuseBetween, staleSucceeds) in [(false, false), (false, true), (true, false), (true, true)] {
        let label = (reuseBetween ? "reuse." : "reconfigure.") + (staleSucceeds ? "old-success" : "old-failure")
        card.prepareForReuse()
        guard let oldA = browserNetworkTicket(card, browserModel(1, thumbnail: "a"), facts, label + ".old-A") else { return }
        let firstGeneration = card.thumbnailRequestID
        if reuseBetween { card.prepareForReuse() }
        guard let oldB = browserNetworkTicket(card, browserModel(2, thumbnail: "b"), facts, label + ".B") else { return }
        if reuseBetween { card.prepareForReuse() }
        guard let newA = browserNetworkTicket(card, browserModel(1, thumbnail: "a"), facts, label + ".new-A") else { return }
        facts.expect(label + ".A-B-A-has-new-request", firstGeneration != card.thumbnailRequestID)
        facts.expect(label + ".long-loading-reveals-placeholder", waitUntil { !card.placeholderView.isHidden })
        let stopsBefore = SpinnerObservation.count(card.spinner)
        OLThumbnailRequestCoordinator.shared.deliver(oldA, data: staleSucceeds ? oldData : nil)
        facts.expect(label + ".old-A-delivered", waitUntil { OLThumbnailRequestCoordinator.shared.returned.contains(oldA) })
        pump(0.06)
        facts.expect(label + ".old-A-cannot-replace-new-A-image", card.thumbnailView.image == nil)
        facts.expect(label + ".old-A-cannot-hide-new-A-placeholder", !card.placeholderView.isHidden)
        facts.expect(label + ".old-A-cannot-stop-new-A-spinner", SpinnerObservation.count(card.spinner) == stopsBefore)
        OLThumbnailRequestCoordinator.shared.deliver(newA, data: newData)
        let delivered = waitUntil { card.thumbnailView.image === newImage }
        facts.expect(label + ".current-A-success-is-not-suppressed", delivered && card.placeholderView.isHidden)
        facts.expect(label + ".current-A-stops-own-spinner", SpinnerObservation.count(card.spinner) == stopsBefore + 1)
        let currentStops = SpinnerObservation.count(card.spinner)
        OLThumbnailRequestCoordinator.shared.deliver(oldB, data: staleSucceeds ? oldData : nil)
        facts.expect(label + ".old-B-delivered", waitUntil { OLThumbnailRequestCoordinator.shared.returned.contains(oldB) })
        pump(0.06)
        facts.expect(label + ".late-B-cannot-change-current-A", card.thumbnailView.image === newImage
            && card.placeholderView.isHidden && SpinnerObservation.count(card.spinner) == currentStops)
    }
}

@MainActor func downloadsReplies(_ facts: Facts) {
    let host = CardHost(.downloads)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLDownloadsItem else {
        facts.expect("registered-downloads", false); return
    }
    let transport = OLDownloadedThumbnailStore.sharedCache
    let oldImage = image(3), newImage = image(4)
    for (reuseBetween, staleSucceeds) in [(false, false), (false, true), (true, false), (true, true)] {
        for memoryHit in [false, true] {
            let label = (reuseBetween ? "reuse." : "reconfigure.") + (staleSucceeds ? "success" : "failure")
                + (memoryHit ? ".memory-hit" : ".pending")
            let a = downloadModel(1, name: "a.mp4"), b = downloadModel(2, name: "b.mp4")
            transport.cached.removeAll()
            card.prepareForReuse()
            card.configure(entry: a, isSelected: false, isMultiSelectMode: false, isPlaying: false)
            let oldA = transport.history.last!.0
            let generation = card.thumbnailRequestID
            if reuseBetween { card.prepareForReuse() }
            card.configure(entry: b, isSelected: false, isMultiSelectMode: false, isPlaying: false)
            let oldB = transport.history.last!.0
            if reuseBetween { card.prepareForReuse() }
            if memoryHit { transport.cached[OLDownloadedThumbnailStore.cacheKey(for: a.localURL)] = newImage }
            let countBefore = transport.history.count
            card.configure(entry: a, isSelected: true, isMultiSelectMode: true, isPlaying: true)
            let newA = memoryHit ? nil : transport.history.last?.0
            if !memoryHit { facts.expect(label + ".long-loading-reveals-placeholder", waitUntil { !card.placeholderLabel.isHidden }) }
            facts.expect(label + ".new-A-generation-even-on-cache-hit", card.thumbnailRequestID != generation)
            facts.expect(label + ".transport-entry", transport.history.count == countBefore + (memoryHit ? 0 : 1))
            transport.deliver(oldA, image: staleSucceeds ? oldImage : nil)
            facts.expect(label + ".old-A-cannot-change-image", memoryHit ? card.thumbnailView.image === newImage : card.thumbnailView.image == nil)
            facts.expect(label + ".old-A-cannot-change-placeholder", memoryHit ? card.placeholderLabel.isHidden
                : !card.placeholderLabel.isHidden && card.placeholderLabel.stringValue == "加载中...")
            if let newA { transport.deliver(newA, image: newImage) }
            transport.deliver(oldB, image: staleSucceeds ? oldImage : nil)
            facts.expect(label + ".current-A-presentation-survives-late-B", card.thumbnailView.image === newImage
                && card.placeholderLabel.isHidden && card.currentEntryID == 1)
            facts.expect(label + ".selection-playing-survive-late-replies", card.isSelectedState
                && card.isMultiSelectMode && card.isPlaying && card.playActionButton.isPlaying)
        }
    }
}

@MainActor func browserLayout(_ facts: Facts) {
    let host = CardHost(.browser)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLBrowserItem else { facts.expect("registered-browser", false); return }
    card.view.frame.size = NSSize(width: 230, height: 180)
    let original = browserModel(4, tags: String(repeating: "very long original title ", count: 8), thumbnail: "layout")
    let cacheBefore = Set(OLThumbnailCache.shared.pending.keys)
    configure(card, original, downloaded: true)
    layout(card)
    let ready = waitUntil { !Set(OLThumbnailCache.shared.pending.keys).subtracting(cacheBefore).isEmpty }
    facts.expect("cache-request-reaches-real-card", ready)
    guard let ticket = Set(OLThumbnailCache.shared.pending.keys).subtracting(cacheBefore).first else { return }
    let decoded = image(5)
    OLThumbnailCache.shared.deliver(ticket, image: decoded)
    facts.expect("cache-hit-published", waitUntil { card.thumbnailView.image === decoded })
    let mask = card.titleLabel.layer?.mask
    facts.expect("long-title-actually-has-mask", mask != nil)
    for _ in 0..<5 { card.viewDidLayout() }
    facts.expect("identical-layout-preserves-mask-object", mask != nil && card.titleLabel.layer?.mask === mask)
    let oldDurationWidth = card.durationBadgeView.frame.width
    let generation = card.thumbnailRequestID
    let requestCount = OLThumbnailCache.shared.history.count
    let changed = browserModel(4, tags: String(repeating: "replacement title ", count: 10), duration: 3661,
        thumbnail: "layout", bytes: 219_152_384, width: 3840)
    card.isSelected = true
    configure(card, changed, downloaded: true)
    layout(card)
    facts.expect("same-ID-title-updates", card.titleLabel.stringValue == changed.displayTitle)
    facts.expect("same-ID-metadata-updates", card.metaLabel.stringValue.contains("3840×1080")
        && card.metaLabel.stringValue.contains("61m1s") && card.currentPageURL == changed.pageURL)
    facts.expect("same-size-duration-reflows", card.durationBadgeView.frame.width > oldDurationWidth)
    facts.expect("metadata-change-keeps-image-request", card.thumbnailRequestID == generation
        && OLThumbnailCache.shared.history.count == requestCount && card.thumbnailView.image === decoded)
    facts.expect("content-change-preserves-selection-and-downloaded", card.isSelected && card.isDownloadedState
        && !card.downloadedBadge.isHidden)
    let changedMask = card.titleLabel.layer?.mask
    facts.expect("changed-text-keeps-valid-fade-mask", changedMask != nil
        && changedMask?.frame == card.titleLabel.bounds)
    card.viewDidLayout()
    facts.expect("changed-layout-is-cached", changedMask != nil && card.titleLabel.layer?.mask === changedMask)
    let oldPixels = card.requestedPixelLimit
    card.view.frame.size = NSSize(width: 420, height: 280)
    layout(card)
    facts.expect("resize-updates-real-16-by-9-container", close(card.imageContainer.frame.width, 420)
        && close(card.imageContainer.frame.height, 236) && close(card.imageContainer.frame.maxY, 280))
    facts.expect("larger-card-requests-larger-thumbnail", card.requestedPixelLimit > oldPixels)
    card.prepareForReuse()
    configure(card, browserModel(5, tags: "short", duration: 2, thumbnail: nil))
    layout(card)
    facts.expect("reuse-at-identical-size-rebuilds-content-layout", card.lastLayoutInputs?.size == card.view.bounds.size
        && card.titleLabel.stringValue == "short" && card.titleLabel.layer?.mask == nil
        && (card.durationBadgeTextLayer.string as? String) == "2s")
    facts.expect("reuse-placeholder-fills-resized-image", !card.placeholderView.isHidden
        && card.placeholderView.frame == card.imageContainer.bounds)
}

@MainActor func visibilityRequests(_ facts: Facts) {
    let host = CardHost(.browser)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLBrowserItem else { facts.expect("browser-mounted", false); return }
    let cache = OLThumbnailCache.shared
    card.prepareForReuse()
    var before = Set(cache.pending.keys)
    configure(card, browserModel(1201, thumbnail: "unfinished"), downloaded: false)
    facts.expect("first-visible-request", waitUntil { !Set(cache.pending.keys).subtracting(before).isEmpty })
    guard let old = Set(cache.pending.keys).subtracting(before).first else { return }
    card.endDisplayingThumbnail()
    before = Set(cache.pending.keys)
    card.beginDisplayingThumbnail()
    facts.expect("unfinished-restarts-on-display", waitUntil { !Set(cache.pending.keys).subtracting(before).isEmpty })
    guard let current = Set(cache.pending.keys).subtracting(before).first else { return }
    let ready = image(40)
    cache.deliver(old, image: image(41)); pump(0.03)
    facts.expect("ended-old-request-cannot-publish", card.thumbnailView.image == nil)
    cache.deliver(current, image: ready)
    facts.expect("resumed-visible-request-publishes", waitUntil { card.thumbnailView.image === ready })
    let requestCount = cache.history.count
    card.endDisplayingThumbnail(); card.beginDisplayingThumbnail(); pump(0.03)
    facts.expect("ready-image-survives-visibility-cycle", card.thumbnailView.image === ready && cache.history.count == requestCount)

    card.prepareForReuse()
    guard let networkTicket = browserNetworkTicket(card, browserModel(1202, thumbnail: "terminal-bad"), facts, "failed") else { return }
    OLThumbnailRequestCoordinator.shared.deliver(networkTicket, data: nil)
    facts.expect("terminal-failure-recorded", waitUntil { card.terminalThumbnailFailureGeneration != nil })
    let terminalCount = cache.history.count
    card.endDisplayingThumbnail(); card.beginDisplayingThumbnail(); pump(0.03)
    facts.expect("terminal-failure-not-retried-on-display", cache.history.count == terminalCount)
    cache.generation += 1
    card.endDisplayingThumbnail(); card.beginDisplayingThumbnail()
    facts.expect("clear-epoch-allows-new-visible-attempt", waitUntil { cache.history.count > terminalCount })

    card.endDisplayingThumbnail()
    let hiddenCount = cache.history.count
    configure(card, browserModel(1204, thumbnail: "hidden-old"), downloaded: false)
    configure(card, browserModel(1205, thumbnail: "hidden-current"), downloaded: false)
    pump(0.12)
    facts.expect("hidden-configure-two-identities-starts-no-work", cache.history.count == hiddenCount && card.thumbnailView.image == nil)
    card.beginDisplayingThumbnail()
    facts.expect("show-configured-hidden-starts-latest-only", waitUntil { cache.history.count == hiddenCount + 1 }
        && cache.history.last?.1 == card.currentThumbnailURL)

    let downloadHost = CardHost(.downloads)
    defer { downloadHost.finish() }
    guard let download = downloadHost.first() as? AppKitOLDownloadsItem else { facts.expect("downloads-mounted", false); return }
    let transport = OLDownloadedThumbnailStore.sharedCache
    download.prepareForReuse()
    download.configure(entry: downloadModel(1203, name: "unfinished.mp4"), isSelected: true, isMultiSelectMode: false, isPlaying: true)
    let oldDownload = transport.history.last!.0
    download.endDisplayingThumbnail(); download.beginDisplayingThumbnail()
    let newDownload = transport.history.last!.0
    facts.expect("download-unfinished-restarts", oldDownload != newDownload)
    transport.deliver(oldDownload, image: image(42))
    facts.expect("download-ended-request-cannot-publish", download.thumbnailView.image == nil)
    transport.deliver(newDownload, image: ready)
    let count = transport.history.count
    download.endDisplayingThumbnail(); download.beginDisplayingThumbnail()
    facts.expect("download-ready-survives-cycle", download.thumbnailView.image === ready && transport.history.count == count
        && download.isPlaying && download.isSelectedState)
    download.endDisplayingThumbnail()
    let hiddenDownloads = transport.history.count
    download.configure(entry: downloadModel(1206, name: "hidden-old.mp4"), isSelected: false, isMultiSelectMode: false, isPlaying: false)
    download.configure(entry: downloadModel(1207, name: "hidden-current.mp4"), isSelected: false, isMultiSelectMode: false, isPlaying: false)
    pump(0.12)
    facts.expect("hidden-download-configure-starts-no-work", transport.history.count == hiddenDownloads && download.thumbnailView.image == nil)
    download.beginDisplayingThumbnail()
    facts.expect("show-hidden-download-starts-latest-only", transport.history.count == hiddenDownloads + 1
        && transport.history.last?.1.contains("hidden-current.mp4") == true)

}

@MainActor func loadingDelay(_ facts: Facts) {
    let browserHost = CardHost(.browser)
    defer { browserHost.finish() }
    guard let browser = browserHost.first() as? AppKitOLBrowserItem else { facts.expect("browser-mounted", false); return }
    browser.prepareForReuse()
    let cache = OLThumbnailCache.shared
    let previous = Set(cache.pending.keys)
    configure(browser, browserModel(1001, thumbnail: "fast-disk"), downloaded: false)
    facts.expect("browser-warm-load-initially-quiet", browser.placeholderView.isHidden)
    guard waitUntil(1, { !Set(cache.pending.keys).subtracting(previous).isEmpty }),
          let ticket = Set(cache.pending.keys).subtracting(previous).first else {
        facts.expect("browser-cache-request", false); return
    }
    let ready = image(30)
    cache.deliver(ticket, image: ready)
    facts.expect("browser-ready-is-immediate", waitUntil { browser.thumbnailView.image === ready })
    pump(0.15)
    facts.expect("browser-delayed-spinner-cannot-cover-ready", browser.placeholderView.isHidden)
    browser.endDisplayingThumbnail()
    browser.prepareForReuse()
    configure(browser, browserModel(1002, thumbnail: "slow"), downloaded: false)
    facts.expect("browser-slow-load-still-reveals", waitUntil { !browser.placeholderView.isHidden })
    browser.prepareForReuse()
    pump(0.15)
    facts.expect("browser-old-delay-cannot-reveal-reused-card", browser.placeholderView.isHidden)

    let downloadHost = CardHost(.downloads)
    defer { downloadHost.finish() }
    guard let download = downloadHost.first() as? AppKitOLDownloadsItem else { facts.expect("download-mounted", false); return }
    let transport = OLDownloadedThumbnailStore.sharedCache
    download.prepareForReuse()
    download.configure(entry: downloadModel(1003, name: "warm.mp4"), isSelected: false, isMultiSelectMode: false, isPlaying: false)
    facts.expect("download-warm-load-initially-quiet", download.placeholderLabel.isHidden)
    transport.deliver(transport.history.last!.0, image: ready)
    pump(0.15)
    facts.expect("download-ready-has-no-delayed-label", download.thumbnailView.image === ready && download.placeholderLabel.isHidden)
    download.configure(entry: downloadModel(1004, name: "bad.mp4"), isSelected: false, isMultiSelectMode: false, isPlaying: false)
    transport.deliver(transport.history.last!.0, image: nil)
    facts.expect("download-failure-is-immediate", !download.placeholderLabel.isHidden && download.placeholderLabel.stringValue == "无法生成预览")
    pump(0.15)
    facts.expect("download-failure-is-not-replaced-by-loading", download.placeholderLabel.stringValue == "无法生成预览")
}

@MainActor func downloadsLayout(_ facts: Facts) {
    let host = CardHost(.downloads)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLDownloadsItem else { facts.expect("registered-downloads", false); return }
    let transport = OLDownloadedThumbnailStore.sharedCache
    card.prepareForReuse()
    card.view.frame.size = NSSize(width: 230, height: 180)
    let original = downloadModel(7, name: String(repeating: "long original title ", count: 6) + ".mp4")
    card.configure(entry: original, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    let first = transport.history.last!.0
    layout(card)
    let mask = card.titleLabel.layer?.mask
    facts.expect("long-title-actually-has-mask", mask != nil)
    for _ in 0..<5 { card.viewDidLayout() }
    facts.expect("identical-layout-preserves-mask-object", mask != nil && card.titleLabel.layer?.mask === mask)
    let decoded = image(6)
    transport.deliver(first, image: decoded)
    let generation = card.thumbnailRequestID, requests = transport.history.count
    let metadataOnly = downloadModel(7, name: original.localURL.lastPathComponent, duration: 3661, resolution: "3840×2160")
    card.configure(entry: metadataOnly, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    layout(card)
    facts.expect("same-ID-metadata-updates", card.metaLabel.stringValue.contains("61m1s") && card.metaLabel.stringValue.contains("3840×2160"))
    facts.expect("metadata-only-keeps-image-request", card.thumbnailRequestID == generation
        && transport.history.count == requests && card.thumbnailView.image === decoded)
    facts.expect("metadata-keeps-selection-playing-presentation", card.isSelectedState && card.isMultiSelectMode
        && card.isPlaying && card.playActionButton.isPlaying && !card.multiSelectBadge.isHidden
        && !card.multiSelectBadgeIcon.isHidden && close(card.imageContainer.layer?.borderWidth ?? 0, 2)
        && close(card.selectionTintView.alphaValue, 0.2))
    let unchangedMask = card.titleLabel.layer?.mask
    card.configure(entry: metadataOnly, isSelected: false, isMultiSelectMode: false, isPlaying: false)
    card.viewDidLayout()
    facts.expect("equal-content-still-applies-selection-playing", !card.isSelectedState && !card.isMultiSelectMode
        && !card.isPlaying && !card.playActionButton.isPlaying && card.multiSelectBadge.isHidden)
    facts.expect("equal-content-keeps-mask-object", unchangedMask != nil && card.titleLabel.layer?.mask === unchangedMask)
    let renamed = downloadModel(7, name: String(repeating: "replacement title ", count: 7) + ".mp4", duration: 3661)
    card.configure(entry: renamed, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    layout(card)
    facts.expect("same-ID-local-title-updates-at-same-size", card.titleLabel.stringValue == renamed.displayTitle
        && card.thumbnailRequestID != generation && transport.history.count == requests + 1)
    let beforeFailureFrame = card.placeholderLabel.frame
    let renameRequest = transport.history.last!.0
    transport.deliver(renameRequest, image: nil)
    layout(card)
    let failureFrame = card.placeholderLabel.frame
    facts.expect("same-size-failure-placeholder-reflows", card.placeholderLabel.stringValue == "无法生成预览"
        && !card.placeholderLabel.isHidden && failureFrame.width != beforeFailureFrame.width)
    facts.expect("failure-placeholder-is-centered", abs(failureFrame.midX - card.imageContainer.bounds.midX) <= 0.5
        && abs(failureFrame.midY - card.imageContainer.bounds.midY) <= 0.5)
    let failedGeneration = card.thumbnailRequestID
    let changedBytes = downloadModel(7, name: renamed.localURL.lastPathComponent, bytes: 2_097_152, duration: 3661)
    card.configure(entry: changedBytes, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    facts.expect("same-ID-file-size-change-invalidates-thumbnail", card.thumbnailRequestID != failedGeneration
        && card.placeholderLabel.stringValue == "加载中...")
    card.view.frame.size = NSSize(width: 360, height: 250)
    layout(card)
    facts.expect("resize-updates-real-16-by-9-container", close(card.imageContainer.frame.width, 360)
        && close(card.imageContainer.frame.height, 202) && close(card.imageContainer.frame.maxY, 250))
    card.prepareForReuse()
    facts.expect("prepare-clears-selection-playing", !card.isSelectedState && !card.isPlaying && !card.playActionButton.isPlaying)
    card.configure(entry: original, isSelected: true, isMultiSelectMode: true, isPlaying: true)
    layout(card)
    facts.expect("same-size-after-reuse-rebuilds-layout", card.lastLayoutInputs?.size == card.view.bounds.size
        && card.titleLabel.layer?.mask != nil && card.titleLabel.stringValue == original.displayTitle
        && card.placeholderLabel.stringValue == "加载中...")
    facts.expect("reused-selection-playing-applied", card.isSelectedState && card.isPlaying && card.playActionButton.isPlaying
        && !card.multiSelectBadge.isHidden && !card.multiSelectBadgeIcon.isHidden)
}

@MainActor func beginCompletion(_ card: AppKitOLBrowserItem, id: Int) {
    let item = browserModel(id, thumbnail: nil)
    configure(card, item, downloading: true)
    layout(card)
    configure(card, item, downloaded: true)
    layout(card)
}

@MainActor func animationCase(_ phase: String, _ facts: Facts) {
    let host = CardHost(.browser)
    defer { host.finish() }
    guard let card = host.first() as? AppKitOLBrowserItem else { facts.expect("registered-browser", false); return }
    beginCompletion(card, id: 1)
    let oldID = card.completionAnimationID
    let oldStart = ProcessInfo.processInfo.systemUptime
    let startOrigin = card.setWallpaperBtn.frame.origin
    facts.expect("native-animation-window-is-active-and-visible", NSApp.isActive && host.window.isVisible,
        "active=\(NSApp.isActive), visible=\(host.window.isVisible)")
    facts.expect("real-badge-started", !card.completionBadgeView.isHidden
        && close(card.completionBadgeView.alphaValue, 1) && card.isCompletionAnimating)
    switch phase {
    case "delayed":
        pump(0.18)
    case "move":
        let entered = waitUntil(0.58) {
            !samePoint(card.completionBadgeView.frame.origin, startOrigin)
                && close(card.completionBadgeView.alphaValue, 1) && !card.completionBadgeView.isHidden
        }
        facts.expect("native-old-move-stage-observed", entered,
            "elapsed=\(ProcessInfo.processInfo.systemUptime - oldStart), frame=\(card.completionBadgeView.frame)")
        guard entered else { return }
    case "fade":
        let entered = waitUntil(0.76) {
            card.completionBadgeView.alphaValue < 0.95 && !card.completionBadgeView.isHidden
        }
        facts.expect("native-old-fade-stage-observed", entered,
            "elapsed=\(ProcessInfo.processInfo.systemUptime - oldStart), alpha=\(card.completionBadgeView.alphaValue)")
        guard entered else { return }
    default:
        facts.expect("known-animation-phase", false); return
    }
    card.prepareForReuse()
    beginCompletion(card, id: 2)
    let newStart = ProcessInfo.processInfo.systemUptime
    facts.expect("reuse-started-distinct-B-animation", card.currentItemID == 2 && oldID != card.completionAnimationID
        && !card.completionBadgeView.isHidden && close(card.completionBadgeView.alphaValue, 1))
    if phase == "delayed" {
        pump(0.23) // Old A's .34 block is past; B's .34 block is still pending.
        facts.expect("old-delayed-move-cannot-move-B", samePoint(card.completionBadgeView.frame.origin, card.setWallpaperBtn.frame.origin)
            && close(card.completionBadgeView.alphaValue, 1) && !card.completionBadgeView.isHidden)
        pump(0.16) // A's .52 reveal is past; B's own reveal is still pending.
        facts.expect("old-reveal-cannot-reveal-B-early", card.isCompletionAnimating && card.downloadedBadge.isHidden)
        let toOldHide = oldStart + 0.81 - ProcessInfo.processInfo.systemUptime
        if toOldHide > 0 { pump(toOldHide) }
        facts.expect("old-hide-cannot-hide-B-during-own-completion", !card.completionBadgeView.isHidden,
            "B age=\(ProcessInfo.processInfo.systemUptime - newStart)")
    } else if phase == "move" {
        pump(0.29) // A's move completion is past; B is still in its .34 bounce.
        facts.expect("old-move-completion-cannot-fade-B", close(card.completionBadgeView.alphaValue, 1)
            && !card.completionBadgeView.isHidden && card.isCompletionAnimating,
            "B age=\(ProcessInfo.processInfo.systemUptime - newStart), alpha=\(card.completionBadgeView.alphaValue)")
    } else {
        pump(0.20) // A's .14 fade completion/hide are past; B's bounce is pending.
        facts.expect("old-nested-fade-completion-cannot-hide-B", !card.completionBadgeView.isHidden
            && close(card.completionBadgeView.alphaValue, 1) && card.isCompletionAnimating,
            "B age=\(ProcessInfo.processInfo.systemUptime - newStart)")
    }
    let finished = waitUntil(1.1) { card.completionBadgeView.isHidden && !card.isCompletionAnimating }
    facts.expect("B-own-animation-still-finishes", finished && !card.downloadedBadge.isHidden
        && !card.setWallpaperBtn.isHidden && card.currentItemID == 2)
}

@main struct GridCardLifecycleChecks {
    @MainActor static func main() {
        if let pidPath = ProcessInfo.processInfo.environment["MWX_GRID_NATIVE_PID_PATH"] {
            try! String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidPath, atomically: true, encoding: .utf8)
        }
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let name = CommandLine.arguments.dropFirst().first ?? ""
        let facts = Facts()
        switch name {
        case "native-pool": nativePool(facts)
        case "browser-replies": browserReplies(facts)
        case "downloads-replies": downloadsReplies(facts)
        case "browser-layout": browserLayout(facts)
        case "downloads-layout": downloadsLayout(facts)
        case "loading-delay": loadingDelay(facts)
        case "visibility-requests": visibilityRequests(facts)
        case "real-card-scroll": realCardScrollHover(facts)
        case "backing-scale": backingScaleRequests(facts)
        case "animation-delayed": animationCase("delayed", facts)
        case "animation-move": animationCase("move", facts)
        case "animation-fade": animationCase("fade", facts)
        default: facts.expect("known-case", false)
        }
        facts.emit(name)
    }
}
