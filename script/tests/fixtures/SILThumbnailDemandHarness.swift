import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated final class SILSignatureReads: @unchecked Sendable {
    static let shared = SILSignatureReads()
    private let lock = NSLock()
    private var reads = 0
    private var decodes = 0
    func record() { lock.lock(); reads += 1; lock.unlock() }
    func recordDecode() { lock.lock(); decodes += 1; lock.unlock() }
    func reset() { lock.lock(); reads = 0; decodes = 0; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var decodeCount: Int { lock.lock(); defer { lock.unlock() }; return decodes }
}

// Only a scheduling boundary is held. The original ImageIO decode and source
// signature have already failed before the production cache publishes nil.
nonisolated final class SILFailureDeliveryProbe: @unchecked Sendable {
    static let shared = SILFailureDeliveryProbe()
    private let lock = NSLock()
    private var held: [String: DispatchSemaphore] = [:]
    private var started: Set<String> = []
    func hold(_ path: String) { lock.lock(); held[path] = DispatchSemaphore(value: 0); lock.unlock() }
    func waitIfHeld(_ path: String) {
        lock.lock()
        let gate = held[path]
        if gate != nil { started.insert(path) }
        lock.unlock()
        if let gate { precondition(gate.wait(timeout: .now() + 8) == .success, "held SIL failure was not released") }
    }
    func waiting(_ path: String) -> Bool { lock.lock(); defer { lock.unlock() }; return started.contains(path) }
    func release(_ path: String) {
        lock.lock(); let gate = held.removeValue(forKey: path); started.remove(path); lock.unlock()
        gate?.signal()
    }
}

nonisolated final class SILCacheAdmissions: @unchecked Sendable {
    static let shared = SILCacheAdmissions()
    private let lock = NSLock()
    private var policies: [String: [Bool]] = [:]
    func registered(_ key: String, cachesFailure: Bool) {
        lock.lock(); policies[key, default: []].append(cachesFailure); lock.unlock()
    }
    func values(_ key: String) -> [Bool] { lock.lock(); defer { lock.unlock() }; return policies[key] ?? [] }
}

@MainActor final class SILInspectorPreviewProbe: NSView {
    final class Surface: NSView {
        var image: NSImage?
        var updates = 0
        func updateImage(_ value: NSImage?) { image = value; updates += 1 }
    }
    var wallpaper: SILWallpaper
    var previewPath: String?
    var previewRequest: ThumbnailRequest?
    var previewCancellation: ThumbnailCacheRequestCancellation?
    let previewSurface = Surface(frame: NSRect(x: 0, y: 0, width: 256, height: 156))
    init(path: String) { wallpaper = SILWallpaper(path: path); super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func attach() -> NSWindow {
        let owner = NSWindow(contentRect: previewSurface.frame, styleMask: [.titled], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false; owner.contentView = self
        return owner
    }
    func load() { loadPreviewImage() }
    // ACTUAL_INSPECTOR_PREVIEW_LOAD
    // ACTUAL_INSPECTOR_MOUNT
}

@MainActor enum SILLoadObservation {
    static let cache = ThumbnailCache(countLimit: 96, namespace: "sil-demand-fixture", usesFailureCache: true)
    static var requests: [String: ThumbnailCacheRequestCancellation] = [:]
    static var prefetchRequests: [String: ThumbnailCacheRequestCancellation] = [:]
    static var completed = Set<ObjectIdentifier>()
    static func finished(_ cancellation: ThumbnailCacheRequestCancellation) { completed.insert(ObjectIdentifier(cancellation)) }
    static func started(_ path: String, _ cancellation: ThumbnailCacheRequestCancellation,
                        priority: ThumbnailCacheRequestPriority) {
        requests[path] = cancellation
        if priority == .prefetch { prefetchRequests[path] = cancellation }
    }
}
@MainActor private final class PrefetchGrid: NSView {
    let images = SILService()
    let adapter: WallpaperLibraryCellAdapter
    let controller: WallpaperLibraryGridController
    var orderedIDs: [String] { images.wallpapers.map(\.id) }
    var items: [WallpaperContentItem] = []
    var visible: [WallpaperContentItem] = [], nearby: [WallpaperContentItem] = []
    var thumbnailCache: ThumbnailCache { adapter.imageThumbnails.cache }
    var tokens: [String: ThumbnailCacheRequestCancellation] {
        Dictionary(uniqueKeysWithValues: adapter.prefetches.keys.compactMap { reference in
            guard let record = images.wallpapers.first(where: { reference.sourceID == $0.id }),
                  let token = SILLoadObservation.prefetchRequests[record.path] else { return nil }
            return (reference.sourceID, token)
        })
    }
    var pendingWork: DispatchWorkItem? { controller.viewportWork }
    init(paths: [String]) {
        adapter = WallpaperLibraryCellAdapter(manager: WallpaperManager(), images: images,
            steam: SteamWorkshopService(), pixabay: PixabayService(),
            isPlaying: { _ in false }, makePrimaryAction: { _ in nil })
        let adapter = self.adapter
        controller = WallpaperLibraryGridController { adapter.makeCell(collection: $0, indexPath: $1, content: $2, state: $3) }
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        controller.updateCell = { adapter.updateCell($0, content: $1, state: $2) }
        controller.setCellVisible = { adapter.setVisible($0, $1) }
        controller.onViewport = { [weak self] visible, nearby, request in
            self?.visible = visible; self?.nearby = nearby
            adapter.updateViewport(visible: visible, prefetch: nearby, request: request)
        }
        controller.loadViewIfNeeded(); controller.view.frame = bounds
        addSubview(controller.view)
        images.wallpapers = paths.enumerated().map { index, path in var value = SILWallpaper(path: path); value.id = String(index); return value }
        update()
    }
    required init?(coder: NSCoder) { nil }
    func update() {
        items = images.wallpapers.map { StaticImageLibraryContentProjection.project($0, facts: .init(
            isPublishedLocally: true, isAvailable: true, canPlay: true, canDelete: true, localURL: URL(fileURLWithPath: $0.path))) }
        controller.update(page: .images, items: items, selection: controller.selection,
            preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        controller.view.layoutSubtreeIfNeeded(); controller.layout.prepare()
    }
    func scroll(to index: Int) {
        let frame = controller.layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: frame.minY))
        controller.scrollView.reflectScrolledClipView(controller.scrollView.contentView)
        fire()
    }
    func fire() { controller.publishViewport() }
    func schedule() { controller.scheduleViewport() }
    func cancel() { controller.cancelViewport() }
}

@MainActor enum SILFullLayoutObservation {
    static var bodies: [ObjectIdentifier: Int] = [:]
}

@main private enum Checks {
    static func imagesIndex(_ records: [SILWallpaper], id: String) -> Int { records.firstIndex { $0.id == id }! }
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
    @MainActor static func failureCacheChecks(root: URL, original: URL) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let fm = FileManager.default, probe = SILSignatureReads.shared
        let visible = root.appendingPathComponent("visible-miss.png")
        let repaired = root.appendingPathComponent("replaced-failure.png")
        let prefetch = root.appendingPathComponent("prefetch-failure.png")
        let bytes = try Data(contentsOf: original)
        try bytes.write(to: visible)
        try Data(repeating: 0x7f, count: bytes.count).write(to: repaired)
        let before = Date(timeIntervalSince1970: 1_700_000_000.125)
        let after = Date(timeIntervalSince1970: 1_700_000_000.875)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: repaired.path)
        let provider = SILThumbnailProvider(cache: ThumbnailCache(countLimit: 8, namespace: "sil-failure-demand", usesFailureCache: true))
        func load(_ path: String, priority: ThumbnailCacheRequestPriority = .visible) -> SILThumbnailLoadResult {
            var result: SILThumbnailLoadResult?
            provider.load(path: path, priority: priority, cancellation: .init()) { result = $0 }
            wait("real SIL provider completes") { result != nil }
            return result!
        }
        probe.reset()
        if case .image = load(visible.path) {
            checks["emptyFailureSetVisibleDoesNotReadSignature"] = probe.count == 0
        }
        probe.reset()
        if case .missingFile = load(root.appendingPathComponent("missing.png").path) {
            checks["visibleMissingFileKeepsFeedbackWithoutSignature"] = probe.count == 0
        }
        probe.reset()
        if case .unavailable = load(repaired.path) {
            checks["decodeFailureRecordsCurrentSignature"] = probe.count == 1 && provider.recordedFailureSignatures.count == 1
        }
        let failedSignature = silGridThumbnailFailureSignature(atPath: repaired.path)!
        probe.reset()
        if case .unavailable = load(repaired.path) {
            checks["unchangedFailureSkipsDecode"] = probe.count == 1 && probe.decodeCount == 0
                && provider.cache.hasCachedFailure(forKey: repaired.path)
                && provider.recordedFailureSignatures.contains(failedSignature)
        }
        let unrelated = root.appendingPathComponent("unrelated-cold.png")
        try bytes.write(to: unrelated)
        probe.reset()
        if case .image = load(unrelated.path) {
            checks["oneFailedPathDoesNotMakeOtherColdPathsReadSignatures"] = probe.count == 0 && probe.decodeCount == 1
        }
        probe.reset()
        var warmResult: SILThumbnailLoadResult?
        provider.load(path: unrelated.path, cancellation: .init()) { warmResult = $0 }
        if case .image? = warmResult {
            checks["warmProviderRemainsSynchronousWithoutSignatureOrDecode"] = probe.count == 0 && probe.decodeCount == 0
        }
        try bytes.write(to: repaired)
        try fm.setAttributes([.modificationDate: after], ofItemAtPath: repaired.path)
        let nextSignature = silGridThumbnailFailureSignature(atPath: repaired.path)!
        probe.reset()
        if case .image = load(repaired.path) {
            checks["sameSecondSameSizeReplacementInvalidatesFailure"] = failedSignature != nextSignature
                && Int64(before.timeIntervalSince1970) == Int64(after.timeIntervalSince1970) && probe.count == 1
        }
        // Create the prefetch negative entry through a real decode failure.
        // Repairing bytes while preserving path/size/mtime must still suppress
        // work; changing only subsecond mtime then restores decode eligibility.
        try Data(repeating: 0x7f, count: bytes.count).write(to: prefetch)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: prefetch.path)
        guard case .unavailable = load(prefetch.path) else { preconditionFailure("prefetch failure seed must really fail ImageIO") }
        let prefetchSignature = silGridThumbnailFailureSignature(atPath: prefetch.path)!
        precondition(provider.recordedFailureSignatures.contains(prefetchSignature))
        try bytes.write(to: prefetch)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: prefetch.path)
        probe.reset()
        if case .unavailable = load(prefetch.path, priority: .prefetch) {
            checks["prefetchFailureSkipsDecode"] = provider.cache.cachedImage(forKey: prefetch.path) == nil
                && probe.count == 1 && probe.decodeCount == 0 && provider.recordedFailureSignatures.contains(prefetchSignature)
        }
        try fm.setAttributes([.modificationDate: after], ofItemAtPath: prefetch.path)
        let replacementSignature = silGridThumbnailFailureSignature(atPath: prefetch.path)!
        probe.reset()
        if case .image = load(prefetch.path, priority: .prefetch) {
            checks["prefetchReplacementUsesPreciseSignature"] = probe.count == 1
                && provider.cache.cachedImage(forKey: prefetch.path) != nil && prefetchSignature != replacementSignature
                && Int64(before.timeIntervalSince1970) == Int64(after.timeIntervalSince1970)
        }

        for clearAll in [true, false] {
            let unchanged = root.appendingPathComponent(clearAll ? "clear-all-same-source.png" : "remove-same-source.png")
            try Data(repeating: 0x7f, count: bytes.count).write(to: unchanged)
            try fm.setAttributes([.modificationDate: before], ofItemAtPath: unchanged.path)
            guard case .unavailable = load(unchanged.path) else { preconditionFailure("same-source repair must start with a real decode failure") }
            let identity = silGridThumbnailFailureSignature(atPath: unchanged.path)!
            try bytes.write(to: unchanged)
            try fm.setAttributes([.modificationDate: before], ofItemAtPath: unchanged.path)
            precondition(silGridThumbnailFailureSignature(atPath: unchanged.path) == identity)
            precondition(provider.cache.hasCachedFailure(forKey: unchanged.path))
            if clearAll { provider.cache.clearAll() } else { provider.cache.remove(forKey: unchanged.path) }
            probe.reset()
            guard case .image = load(unchanged.path) else { preconditionFailure("explicit cache invalidation did not restore the same provider") }
            checks[clearAll ? "clearAllMakesSameSizeMtimeRepairRetryableInOriginalProvider" : "singleKeyMakesSameSizeMtimeRepairRetryableInOriginalProvider"] =
                probe.decodeCount == 1 && !provider.cache.hasCachedFailure(forKey: unchanged.path)
                && !provider.recordedFailureSignatures.contains(identity)
        }

        let held = root.appendingPathComponent("held-old-failure.png"), heldProbe = SILFailureDeliveryProbe.shared
        try Data(repeating: 0x7f, count: bytes.count).write(to: held)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: held.path)
        heldProbe.hold(held.path)
        var oldFailureCompletions = 0
        provider.load(path: held.path, cancellation: .init()) { result in
            guard case .unavailable = result else { preconditionFailure("held real ImageIO failure changed result") }
            oldFailureCompletions += 1
        }
        wait("real decode failed before its source-signature delivery") { heldProbe.waiting(held.path) }
        provider.cache.clearAll()
        try bytes.write(to: held)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: held.path)
        heldProbe.release(held.path)
        wait("old failed consumer still finishes once after clear") { oldFailureCompletions == 1 }
        checks["oldInFlightNilAfterClearCannotRestoreFailureAuthority"] = !provider.cache.hasCachedFailure(forKey: held.path)
            && !provider.recordedFailureSignatures.contains(silGridThumbnailFailureSignature(atPath: held.path)!)
        guard case .image = load(held.path) else { preconditionFailure("old nil memo blocked a repaired same-source demand") }
        checks["sameProviderRecoversAfterClearingHeldOldFailure"] = oldFailureCompletions == 1
            && provider.cache.cachedImage(forKey: held.path) != nil

        let unknown = root.appendingPathComponent("other-provider-failure.png")
        try Data(repeating: 0x7f, count: bytes.count).write(to: unknown)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: unknown.path)
        let joinedProvider = SILThumbnailProvider(cache: provider.cache)
        heldProbe.hold(unknown.path)
        var ownerNil = 0, joinedNil = 0
        provider.load(path: unknown.path, cancellation: .init()) { result in
            guard case .unavailable = result else { preconditionFailure("failure owner must receive nil") }
            ownerNil += 1
        }
        wait("first provider owns the real failure producer") { heldProbe.waiting(unknown.path) }
        joinedProvider.load(path: unknown.path, cancellation: .init()) { result in
            guard case .unavailable = result else { preconditionFailure("joined provider must receive the same nil") }
            joinedNil += 1
        }
        wait("second actual provider joined the same cache request") { SILCacheAdmissions.shared.values(unknown.path).count == 2 }
        heldProbe.release(unknown.path)
        wait("both providers finish the shared failure exactly once") { ownerNil == 1 && joinedNil == 1 }
        let unknownIdentity = silGridThumbnailFailureSignature(atPath: unknown.path)!
        checks["joinedProviderDoesNotGuessAnotherProducersFailureIdentity"] =
            provider.cache.hasCachedFailure(forKey: unknown.path) && !joinedProvider.recordedFailureSignatures.contains(unknownIdentity)
        try bytes.write(to: unknown)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: unknown.path)
        probe.reset()
        var joinedRecovery: SILThumbnailLoadResult?
        joinedProvider.load(path: unknown.path, cancellation: .init()) { joinedRecovery = $0 }
        wait("unknown failure identity allows one real demand retry") { joinedRecovery != nil }
        guard case .image? = joinedRecovery else { preconditionFailure("unknown producer permanently blocked the repaired same-key source") }
        checks["unknownProducerIdentityRetriesActualImageIOInsteadOfReusingNegative"] = probe.count == 1 && probe.decodeCount == 1
            && !provider.cache.hasCachedFailure(forKey: unknown.path) && ownerNil == 1 && joinedNil == 1

        for firstCachesFailure in [true, false] {
            let mixed = root.appendingPathComponent(firstCachesFailure ? "mixed-true-first.png" : "mixed-false-first.png")
            try Data(repeating: 0x7f, count: bytes.count).write(to: mixed)
            let mixedCache = ThumbnailCache(namespace: "mixed-policy-" + UUID().uuidString, usesFailureCache: true)
            let gateKey = mixed.path + "-producer"
            heldProbe.hold(gateKey)
            var firstCompletions = 0, secondCompletions = 0
            mixedCache.load(forKey: mixed.path, cachesFailure: firstCachesFailure,
                input: .sourceFile(URL(filePath: mixed.path, directoryHint: .notDirectory),
                    onFailure: { heldProbe.waitIfHeld(gateKey) })) { value in precondition(value == nil); firstCompletions += 1 }
            wait("first mixed-policy producer is held") { heldProbe.waiting(gateKey) }
            mixedCache.load(forKey: mixed.path, cachesFailure: !firstCachesFailure,
                input: .sourceFile(URL(filePath: mixed.path, directoryHint: .notDirectory),
                    onFailure: { preconditionFailure("mixed policy must not decode another same-key producer") })) { value in
                precondition(value == nil); secondCompletions += 1
            }
            heldProbe.release(gateKey)
            wait("both mixed-policy consumers finish once") { firstCompletions == 1 && secondCompletions == 1 }
            checks[firstCachesFailure ? "trueThenFalseConsumersShareOneProducerAndBothFinish" : "falseThenTrueConsumersShareOneProducerAndBothFinish"] =
                mixedCache.hasCachedFailure(forKey: mixed.path) == firstCachesFailure
            try bytes.write(to: mixed)
            var independent: NSImage?
            mixedCache.load(forKey: mixed.path, cachesFailure: false, input: .sourceFile(URL(filePath: mixed.path, directoryHint: .notDirectory))) { independent = $0 }
            wait("later independent false demand bypasses the original negative conclusion") { independent != nil }
            checks[firstCachesFailure ? "independentFalseBypassesEarlierTrueFailure" : "independentFalseDoesNotManufactureNegativeCache"] =
                !mixedCache.hasCachedFailure(forKey: mixed.path) && firstCompletions == 1 && secondCompletions == 1
            mixedCache.clearAll()
        }

        let inspectorPath = root.appendingPathComponent("inspector-negative-bypass.png")
        try Data(repeating: 0x7f, count: bytes.count).write(to: inspectorPath)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: inspectorPath.path)
        let inspectorProvider = SILThumbnailProvider()
        var inspectorSeed: SILThumbnailLoadResult?
        inspectorProvider.load(path: inspectorPath.path, cancellation: .init()) { inspectorSeed = $0 }
        wait("actual SIL store has a real provider failure") { inspectorSeed != nil }
        precondition(SILThumbnailStore.sharedCache.hasCachedFailure(forKey: inspectorPath.path))
        let inspector = SILInspectorPreviewProbe(path: inspectorPath.path)
        let inspectorWindow = inspector.attach(); defer { inspectorWindow.close() }
        wait("actual Inspector false policy still completes its invalid source") { inspector.previewSurface.updates == 1 }
        checks["inspectorFalsePolicyKeepsItsOwnFailedDemandRetryable"] = inspector.previewSurface.image == nil
            && SILCacheAdmissions.shared.values(inspectorPath.path) == [true, false]
        try bytes.write(to: inspectorPath)
        try fm.setAttributes([.modificationDate: before], ofItemAtPath: inspectorPath.path)
        inspectorWindow.contentView = nil
        inspectorWindow.contentView = inspector
        wait("actual Inspector preview remount retries the repaired unchanged source") { inspector.previewSurface.image != nil }
        let inspectorPixels = inspector.previewSurface.image!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        checks["inspectorOriginalPreviewMethodBypassesNegativeCacheAndCoversItsBackingBounds"] =
            inspectorPixels.width >= Int(ceil(256 * inspectorWindow.backingScaleFactor))
            && inspectorPixels.height >= Int(ceil(156 * inspectorWindow.backingScaleFactor))
            && SILCacheAdmissions.shared.values(inspectorPath.path) == [true, false, false]
            && !SILThumbnailStore.sharedCache.hasCachedFailure(forKey: inspectorPath.path)
        SILThumbnailStore.sharedCache.imageCache.removeAllObjects()
        var recoveredDiskImage: NSImage?
        let decodesBeforeDiskReturn = probe.decodeCount
        SILThumbnailStore.sharedCache.load(forKey: inspectorPath.path,
            input: .sourceFile(URL(filePath: inspectorPath.path, directoryHint: .notDirectory))) { recoveredDiskImage = $0 }
        wait("ordinary true demand reads the successful Inspector disk result") { recoveredDiskImage != nil }
        checks["successfulFalseDemandRetiresOldFailureAcrossMemoryEviction"] =
            !SILThumbnailStore.sharedCache.hasCachedFailure(forKey: inspectorPath.path)
            && inspector.previewSurface.updates == 2 && probe.decodeCount == decodesBeforeDiskReturn
        var cancelledCompleted = false
        let token = ThumbnailCacheRequestCancellation(); token.cancel()
        probe.reset()
        provider.load(path: root.appendingPathComponent("cancelled.png").path, cancellation: token) { _ in cancelledCompleted = true }
        pump(0.03)
        checks["cancelledVisibleMissDoesNotCompleteOrReadSignature"] = !cancelledCompleted && probe.count == 0
        return checks
    }
    @MainActor static func warmLayoutChecks() throws -> [String: Bool] {
        func pixels(_ width: Int, _ height: Int) -> NSImage {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.systemGreen.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
        }
        let cache = ThumbnailCache(countLimit: 4, totalCostLimit: 4 * 1024 * 1024,
            namespace: "sil-full-layout-" + UUID().uuidString)
        let provider = SILThumbnailProvider(cache: cache)
        var model = SILWallpaper(path: "/fixture/full-layout.png"); model.id = "layout"
        let landscape = pixels(400, 200), portrait = pixels(200, 400)
        var seeded: NSImage?
        cache.load(forKey: model.path, input: .image(landscape)) { seeded = $0 }
        wait("real cache prepares the known landscape") { seeded != nil }
        let ready = seeded!
        let card = SILGridItem(); _ = card.view
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 240))
        window.contentView = host; host.addSubview(card.view); window.orderFrontRegardless()
        defer { card.prepareForReuse(); window.orderOut(nil); window.close() }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: 0, section: 0))
        attributes.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
        card.apply(attributes)
        func count() -> Int { SILFullLayoutObservation.bodies[ObjectIdentifier(card), default: 0] }
        func borderIsSelected(_ selected: Bool) -> Bool {
            var color: CGColor?
            card.imageContainer.effectiveAppearance.performAsCurrentDrawingAppearance {
                color = (selected ? WallpaperLibraryControlStyle.cardOutlineColor(selected: true,
                    in: card.imageContainer.effectiveAppearance) : NSColor.separatorColor).cgColor
            }
            return card.imageContainer.layer?.borderWidth == (selected ? WallpaperLibraryControlStyle.cardSelectionBorderWidth : 1)
                && card.imageContainer.layer?.borderColor == color
        }
        var checks: [String: Bool] = [:], work: [String: Int] = [:]
        var loads = 0, insideGrant = false, synchronous = false
        card.configure(wallpaper: model, isSelected: false, isMultiSelectMode: false,
            thumbnailVisible: false, cachedThumbnail: cache.cachedImage(forKey: model.path)) { token, reply in
                loads += 1
                provider.load(path: model.path, cancellation: token) { result in synchronous = insideGrant; reply(result) }
            }
        card.apply(attributes)
        let signatures = SILSignatureReads.shared.count, decodes = SILSignatureReads.shared.decodeCount
        var before = count()
        insideGrant = true; card.setThumbnailVisible(true); insideGrant = false
        work["warmProviderFinal"] = count() - before
        checks["warm-layout-real-provider-remains-synchronous-and-source-free"] = synchronous && loads == 1
            && SILSignatureReads.shared.count == signatures && SILSignatureReads.shared.decodeCount == decodes
        checks["warm-layout-final-keeps-identity-crop-and-hidden-placeholder"] = card.wallpaperID == model.id
            && card.thumbnailView.image === ready && card.thumbnailView.frame == NSRect(x: -120, y: 0, width: 480, height: 240)
            && card.thumbnailRequestFinished && card.thumbnailCancellation == nil && card.loadingPlaceholderWork == nil && card.placeholderLabel.isHidden
        var reply: ((SILThumbnailLoadResult) -> Void)?, token: ThumbnailCacheRequestCancellation?
        checks["warm-layout-laid-out-unselected-border-is-current"] = borderIsSelected(false)
        before = count()
        card.configure(wallpaper: model, isSelected: true, isMultiSelectMode: false, thumbnailVisible: true) { token = $0; reply = $1 }
        checks["warm-layout-selection-feedback-is-synchronous-before-any-final-or-pump"] = borderIsSelected(true)
            && card.thumbnailView.image === ready && !card.thumbnailRequestFinished && count() == before
        provider.load(path: model.path, cancellation: token!) { reply?($0) }
        work["selectedWarmFinal"] = count() - before
        checks["warm-layout-selected-warm-final-keeps-border-and-current-pixels"] = borderIsSelected(true)
            && card.thumbnailView.image === ready && card.thumbnailRequestFinished
        card.configure(wallpaper: model, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true) { token = $0; reply = $1 }
        checks["warm-layout-unselection-feedback-is-synchronous-while-image-is-held"] = borderIsSelected(false)
        checks["warm-layout-same-resource-retains-pixels-while-new-result-is-held"] = card.thumbnailView.image === ready && !card.thumbnailRequestFinished
        before = count(); reply?(.image(portrait)); work["changedAspectFinal"] = count() - before
        checks["warm-layout-same-size-new-aspect-updates-only-the-image-frame"] = card.thumbnailView.image === portrait
            && card.thumbnailView.frame == NSRect(x: 0, y: -120, width: 240, height: 480) && card.placeholderLabel.isHidden && borderIsSelected(false)
        before = count(); attributes.frame.size = NSSize(width: 320, height: 320); card.apply(attributes)
        work["changedSize"] = count() - before
        checks["warm-layout-size-change-still-lays-out-the-entire-card"] = card.imageContainer.bounds.size == NSSize(width: 320, height: 320)
            && card.thumbnailView.frame == NSRect(x: 0, y: -160, width: 320, height: 640)
        card.configure(wallpaper: model, isSelected: true, isMultiSelectMode: false, thumbnailVisible: true) { token = $0; reply = $1 }
        checks["warm-layout-selection-before-failure-is-immediate"] = borderIsSelected(true)
        reply?(.unavailable)
        checks["warm-layout-failure-keeps-the-current-selection-border"] = borderIsSelected(true)
        let unavailableFrame = card.placeholderLabel.frame
        before = count()
        card.configure(wallpaper: model, isSelected: false, isMultiSelectMode: false,
            thumbnailVisible: true, cachedThumbnail: ready) { _, finish in finish(.unavailable) }
        work["repeatUnavailable"] = count() - before
        checks["warm-layout-repeated-failure-clears-refilled-pixels-and-restores-image-bounds"] = card.thumbnailView.image == nil
            && card.thumbnailView.frame == card.imageContainer.bounds && !card.placeholderLabel.isHidden
            && card.placeholderLabel.stringValue == "缩略图不可用" && card.placeholderLabel.frame == unavailableFrame && borderIsSelected(false)
        card.configure(wallpaper: model, isSelected: false, isMultiSelectMode: false,
            thumbnailVisible: true, cachedThumbnail: ready) { _, finish in finish(.missingFile) }
        checks["warm-layout-missing-file-keeps-its-own-label-and-nil-image-frame"] = card.thumbnailView.image == nil
            && card.thumbnailView.frame == card.imageContainer.bounds && !card.placeholderLabel.isHidden
            && card.placeholderLabel.stringValue == "原文件不存在" && abs(card.placeholderLabel.frame.midX - 160) < 0.5
        card.configure(wallpaper: model, isSelected: true, isMultiSelectMode: false, thumbnailVisible: true) { token = $0; reply = $1 }
        checks["warm-layout-selection-before-cancellation-is-immediate"] = borderIsSelected(true)
        pump(0.13)
        checks["warm-layout-slow-request-still-shows-the-original-delayed-loading"] = !card.placeholderLabel.isHidden
            && card.placeholderLabel.stringValue == "加载中..." && !card.thumbnailRequestFinished
        let cancelledToken = token, stale = reply
        card.setThumbnailVisible(false); stale?(.image(portrait))
        checks["warm-layout-hidden-consumer-rejects-its-late-image"] = cancelledToken?.cancelled == true
            && card.thumbnailView.image == nil && borderIsSelected(true)
        card.prepareForReuse(); var replacement = model; replacement.id = "replacement"; replacement.path += ".new"
        card.configure(wallpaper: replacement, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true) { token = $0; reply = $1 }
        card.apply(attributes)
        before = count(); stale?(.image(portrait)); work["staleAfterReuse"] = count() - before
        checks["warm-layout-reuse-rejects-old-identity-and-preserves-loading"] = card.wallpaperID == replacement.id
            && card.thumbnailView.image == nil && !card.thumbnailRequestFinished
        before = count(); reply?(.image(ready)); work["reusedFinal"] = count() - before
        pump(0.13)
        checks["warm-layout-reused-final-keeps-current-source-and-cancels-delayed-placeholder"] = card.wallpaperID == replacement.id
            && card.thumbnailView.image === ready && card.thumbnailView.frame == NSRect(x: -160, y: 0, width: 640, height: 320)
            && card.thumbnailRequestFinished && card.thumbnailCancellation == nil && card.loadingPlaceholderWork == nil && card.placeholderLabel.isHidden
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: work, options: [.sortedKeys]), as: UTF8.self)
        FileHandle.standardError.write(Data("SIL full layout work: \(raw)\n".utf8))
        return checks
    }

    @MainActor static func main() throws {
        if CommandLine.arguments.dropFirst().first == "--warm-layout" {
            initializeNativeAppHarness()
            print(String(decoding: try JSONSerialization.data(withJSONObject: warmLayoutChecks(), options: [.sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.dropFirst().first == "--card-reflow" {
            initializeNativeAppHarness()
            let checks = wallpaperGridCardReflowChecks(label: "static-image", provider: .staticImageLibrary,
                itemClass: SILGridItem.self, reuseIdentifier: SILGridItem.reuseID,
                resetColdTracking: SILGridItem.resetHoverTracking,
                makeCard: { collection, path, state, playing in
                    let card = collection.makeItem(withIdentifier: SILGridItem.reuseID, for: path) as! SILGridItem
                    let model = try! JSONDecoder().decode(SILWallpaper.self, from: Data("""
                        {"id":"reflow-\(path.item)","path":"fixture-reflow-\(path.item).png","title":"reflow","tags":[],"lastUsed":0,"addedAt":0}
                        """.utf8))
                    card.configure(wallpaper: model, isSelected: state.isSelected, isMultiSelectMode: state.isSelecting,
                        thumbnailVisible: false, isPlaying: playing) { _, _ in
                            preconditionFailure("hidden reflow fixture must not load thumbnails")
                        }
                    return card
                }, updateState: { cell, state, playing in
                    let card = cell as! SILGridItem
                    card.applySelectionState(isSelected: state.isSelected, multiSelectMode: state.isSelecting)
                    card.applyPlayingState(isPlaying: playing)
                }, isHovering: { ($0 as! SILGridItem).isHovering },
                bar: { ($0 as! SILGridItem).controlBar })
            print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
            return
        }
        if CommandLine.arguments.dropFirst().first == "--card-interactions" {
            initializeNativeAppHarness()
            let item = SILGridItem(); _ = item.view
            // Decode the real Codable model from fixture data: no media is read.
            let model = try JSONDecoder().decode(SILWallpaper.self, from: Data("""
                {"id":"interaction","path":"fixture-only.png","title":"interaction","tags":[],"lastUsed":0,"addedAt":0}
                """.utf8))
            item.configure(wallpaper: model, isSelected: false, isMultiSelectMode: false, thumbnailVisible: false) { _, _ in
                preconditionFailure("hidden interaction fixture must not load thumbnails")
            }
            let checks = gridCardInteractionChecks(item: item, cardRoot: item.imageContainer,
                outline: item.hoverOutline, isHovering: { item.isHovering }, label: "static-image",
                dragImageView: item.thumbnailView, layoutDragImage: { item.updateThumbnailFrame() })
            print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
            return
        }
        if CommandLine.arguments.dropFirst().first == "--adaptive-return" {
            initializeNativeAppHarness()
            let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var checks: [String: Bool] = [:]
            let master = root.appendingPathComponent("master.png")
            try writePNG(master)
            let provider = SILThumbnailProvider()
            var seed: SILThumbnailLoadResult?
            provider.load(path: master.path, request: .init(width: 128, height: 128, mode: .fill), cancellation: .init()) { seed = $0 }
            wait("small grid source publishes its final square") { seed != nil }
            if case let .image(image)? = seed {
                checks["small-grid-final-is-one-128-square"] = image.size == NSSize(width: 128, height: 128)
            } else { checks["small-grid-final-is-one-128-square"] = false }
            var stored: CGImageSource?
            wait("unique seed commits its decodable uncropped master before disk-return checks") {
                guard let source = CGImageSourceCreateWithURL(provider.cache.diskCacheURL(for: master.path) as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      image.width >= 512, image.width > image.height else { return false }
                stored = source
                return true
            }
            let storedProperties = CGImageSourceCopyPropertiesAtIndex(stored!, 0, nil)! as NSDictionary
            let storedWidth = (storedProperties[kCGImagePropertyPixelWidth] as! NSNumber).intValue
            let storedHeight = (storedProperties[kCGImagePropertyPixelHeight] as! NSNumber).intValue
            let sourceDecodes = SILSignatureReads.shared.decodeCount
            provider.cache.imageCache.removeAllObjects()
            let parked = root.appendingPathComponent("master-parked.png")
            try FileManager.default.moveItem(at: master, to: parked)
            let inspector = SILInspectorPreviewProbe(path: master.path)
            let inspectorWindow = inspector.attach(); defer { inspectorWindow.close() }
            inspector.load()
            wait("actual rectangular Inspector consumer completes its disk return") { inspector.previewSurface.updates == 1 }
            checks["small-grid-keeps-uncropped-512-master-for-rectangular-inspector"] = inspector.previewSurface.image.map {
                storedWidth >= 512 && storedWidth > storedHeight
                    && $0.size.width >= ceil(256 * inspectorWindow.backingScaleFactor)
                    && $0.size.height >= ceil(156 * inspectorWindow.backingScaleFactor)
            } == true
            checks["rectangular-inspector-return-needs-no-source-reextract"] = SILSignatureReads.shared.decodeCount == sourceDecodes
                && !FileManager.default.fileExists(atPath: master.path) && inspector.previewSurface.image != nil
            let tiny = root.appendingPathComponent("tiny.png")
            let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
            let destination = CGImageDestinationCreateWithURL(tiny as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(destination))
            var tinyResult: SILThumbnailLoadResult?
            provider.load(path: tiny.path, request: .init(width: 128, height: 128, mode: .fill), cancellation: .init()) { tinyResult = $0 }
            wait("native small source completes") { tinyResult != nil }
            if case let .image(image)? = tinyResult {
                checks["master-floor-does-not-upscale-a-native-small-source"] = image.size == NSSize(width: 24, height: 24)
            } else { checks["master-floor-does-not-upscale-a-native-small-source"] = false }
            let paths = try (0..<160).map { index -> String in
                let path = root.appendingPathComponent("card-\(index).png")
                try FileManager.default.copyItem(at: parked, to: path); return path.path
            }
            let grid = PrefetchGrid(paths: paths)
            grid.autoresizingMask = [.width, .height]
            grid.controller.view.autoresizingMask = [.width, .height]
            let window = NSWindow(contentRect: grid.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = grid; window.center(); window.orderFrontRegardless()
            defer { grid.cancel(); window.orderOut(nil); window.close() }
            window.contentView?.layoutSubtreeIfNeeded()
            let oldRequest = grid.controller.thumbnailRequest
            let oldSide = oldRequest.width
            let path = IndexPath(item: 120, section: 0)
            var oldResult: SILThumbnailLoadResult?
            grid.adapter.imageThumbnails.load(path: paths[120], request: oldRequest, cancellation: .init()) { oldResult = $0 }
            wait("held offscreen source is ready") { oldResult != nil }
            // This idle factory isolates the prepared card from the live grid's reuse.
            let factory = NSCollectionView()
            factory.dataSource = grid.controller
            factory.collectionViewLayout = NSCollectionViewFlowLayout()
            defer { withExtendedLifetime(factory) {} }
            let held = grid.controller.collectionView(factory, itemForRepresentedObjectAt: path) as! SILGridItem
            let oldPixels = held.thumbnailView.image
            checks["held-offscreen-card-starts-with-old-target-pixels"] = !held.isThumbnailVisible
                && held.thumbnailView.image?.size == NSSize(width: oldSide, height: oldSide)
            window.setContentSize(NSSize(width: 1200, height: 500))
            window.contentView?.layoutSubtreeIfNeeded()
            let currentRequest = grid.controller.thumbnailRequest
            let currentSide = currentRequest.width
            checks["native-resize-increases-the-required-target"] = currentSide > oldSide
            let attributes = grid.controller.layout.layoutAttributesForItem(at: path)!
            grid.controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: attributes.frame.minY))
            grid.controller.scrollView.reflectScrolledClipView(grid.controller.scrollView.contentView)
            window.contentView?.layoutSubtreeIfNeeded()
            // An actual invalidation prevents a newer warmed image masking the old captured loader.
            grid.thumbnailCache.remove(forKey: paths[120])
            held.apply(attributes)
            checks["before-grant-held-card-still-has-source-120-and-its-old-pixels"] =
                held.wallpaperID == "120" && held.wallpaperPath == paths[120] && !held.isThumbnailVisible
                    && oldPixels != nil && held.thumbnailView.image === oldPixels
            let readsBeforeGrant = grid.images.sourceReads
            grid.controller.collectionView(grid.controller.collection, willDisplay: held, forRepresentedObjectAt: path)
            checks["regrant-reuses-bound-source-without-another-library-search"] = grid.images.sourceReads == readsBeforeGrant
            checks["regrant-does-not-clear-the-current-correct-resource"] = held.thumbnailView.image != nil
            wait("retained card finishes its original display request") { held.thumbnailRequestFinished }
            checks["retained-offscreen-card-receives-the-current-final-target"] = held.thumbnailView.image?.size
                == NSSize(width: min(currentSide, 700), height: min(currentSide, 700))
            grid.controller.collectionView(grid.controller.collection, didEndDisplaying: held, forRepresentedObjectAt: path)
            checks["nil-revocation-releases-the-held-card-demand"] = !held.isThumbnailVisible && held.thumbnailCancellation == nil
            print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
            return
        }
        let residentReturn = CommandLine.arguments.dropFirst().first == "--resident-return"
        if residentReturn { initializeNativeAppHarness() }
        else { _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory) }
        let root = URL(fileURLWithPath: CommandLine.arguments[residentReturn ? 2 : 1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.png")
        try writePNG(original)
        let paths = try (0..<160).map { index -> String in
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
        if residentReturn { window.center() }
        window.orderFrontRegardless()
        defer { grid.cancel(); window.orderOut(nil); window.close() }
        if residentReturn {
            var expected: [String: NSImage] = [:]
            let initialCells = NSHashTable<SILGridItem>.weakObjects()
            var rebound = Set<ObjectIdentifier>()
            let settled = {
                grid.pendingWork == nil && !grid.visible.isEmpty
                    && SILLoadObservation.requests.values.allSatisfy { $0.cancelled || SILLoadObservation.completed.contains(ObjectIdentifier($0)) }
                    && grid.nearby.allSatisfy { value in grid.thumbnailCache.cachedImage(forKey: paths[Int(value.reference.sourceID)!], request: grid.controller.thumbnailRequest) != nil }
                    && grid.visible.allSatisfy { value in
                        guard let card = grid.controller.collection.item(at: IndexPath(item: Int(value.reference.sourceID)!, section: 0)) as? SILGridItem else { return false }
                        return card.wallpaperID == value.reference.sourceID && card.thumbnailRequestFinished && card.thumbnailView.image != nil
                    }
            }
            for index in [0, 40, 80, 120] {
                let frame = grid.controller.layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
                grid.controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: frame.minY))
                grid.controller.scrollView.reflectScrolledClipView(grid.controller.scrollView.contentView)
                grid.controller.view.layoutSubtreeIfNeeded()
                wait("production viewport and nearby pixels settle", until: settled)
                if index == 0 {
                    for content in grid.visible.prefix(20) {
                        let card = grid.controller.collection.item(at: IndexPath(item: Int(content.reference.sourceID)!, section: 0)) as! SILGridItem
                        expected[content.reference.sourceID] = card.thumbnailView.image!
                        initialCells.add(card)
                    }
                } else {
                    for card in initialCells.allObjects where card.wallpaperID.map({ expected[$0] == nil }) == true {
                        rebound.insert(ObjectIdentifier(card))
                    }
                }
            }
            checks["productionResidentReturnSeedsTwentyNativeImages"] = expected.count == 20
            checks["productionResidentReturnKeepsTwentyImagesInOriginalCache"] = expected.allSatisfy { entry in
                grid.thumbnailCache.cachedImage(forKey: paths[Int(entry.key)!], request: grid.controller.thumbnailRequest) === entry.value
            }
            FileHandle.standardError.write(Data("SIL RESIDENT POOL reused=\(rebound.count) expected=\(expected.count)\n".utf8))
            let sourceDecodes = SILSignatureReads.shared.decodeCount
            let firstFrame = grid.controller.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
            grid.controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: firstFrame.minY))
            grid.controller.scrollView.reflectScrolledClipView(grid.controller.scrollView.contentView)
            grid.controller.view.layoutSubtreeIfNeeded()
            checks["productionResidentReturnHasOriginalPixelsInSameTurn"] = expected.allSatisfy { entry in
                guard let card = grid.controller.collection.item(at: IndexPath(item: Int(entry.key)!, section: 0)) as? SILGridItem else { return false }
                return card.wallpaperID == entry.key && card.thumbnailView.image === entry.value && card.placeholderLabel.isHidden
            }
            wait("production return settles without source extraction", until: settled)
            checks["productionResidentReturnDoesNotDecodeOriginalSourcesAgain"] = SILSignatureReads.shared.decodeCount == sourceDecodes
            checks["productionResidentReturnCaseCompleted"] = true
            print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
            return
        }
        grid.scroll(to: 9)
        wait("native initial viewport settles") { grid.pendingWork == nil && !grid.visible.isEmpty }
        wait("initial visible consumers finish") {
            SILLoadObservation.requests.values.allSatisfy { $0.cancelled || SILLoadObservation.completed.contains(ObjectIdentifier($0)) }
        }
        // Isolate one settled viewport, rather than retaining near leases from
        // AppKit's initial layout at the top before the requested scroll.
        grid.cancel(); grid.fire()
        var firstTokens = grid.tokens
        let visibleIDs = grid.visible.compactMap { Int($0.reference.sourceID) }.sorted()
        precondition(!visibleIDs.isEmpty)
        let forward = visibleIDs.last! + 1, backward = visibleIDs.first! - 1
        checks["nearbyDemandIsBounded"] = firstTokens.count <= 96 && firstTokens.count == grid.nearby.count
        checks["nearbyCoversExistingVisibleWindowBeforeAndAfter"] =
            (max(0, visibleIDs.first! - visibleIDs.count)..<visibleIDs.first!).allSatisfy { firstTokens[String($0)] != nil }
            && (visibleIDs.last! + 1...visibleIDs.last! + visibleIDs.count).allSatisfy { firstTokens[String($0)] != nil }
        checks["forwardNearestIsIncluded"] = firstTokens[String(forward)] != nil
        checks["backwardNearestIsIncluded"] = firstTokens[String(backward)] != nil
        checks["visibleItemsDoNotStartPrefetch"] = visibleIDs.allSatisfy { firstTokens[String($0)] == nil }
        wait("nearby decoded images") {
            firstTokens.keys.allSatisfy { grid.thumbnailCache.cachedImage(forKey: paths[Int($0)!], request: grid.controller.thumbnailRequest) != nil }
        }
        checks["emptyFailureSetPrefetchDoesNotReadSignature"] = SILSignatureReads.shared.count == 0
        // The real unified grid also decodes visible cards. Let that initial
        // batch settle, then warm the current nearby window before asserting a
        // stable viewport keeps leases. Capacity eviction is tested explicitly
        // below with a separate consumer, rather than confused with this setup.
        wait("initial visible and nearby consumers finish") {
            SILLoadObservation.requests.values.allSatisfy { $0.cancelled || SILLoadObservation.completed.contains(ObjectIdentifier($0)) }
        }
        grid.fire(); firstTokens = grid.tokens
        wait("settled nearby images remain warm") {
            firstTokens.keys.allSatisfy { grid.thumbnailCache.cachedImage(forKey: paths[Int($0)!], request: grid.controller.thumbnailRequest) != nil }
        }
        let ready = grid.thumbnailCache.cachedImage(forKey: paths[forward], request: grid.controller.thumbnailRequest)!
        checks["nearbyImageIsDownsampled"] = ready.size.width == CGFloat(grid.controller.thumbnailRequest.width) && ready.size.height == ready.size.width
        for _ in 0..<20 { grid.fire() }
        checks["unchangedViewportRetainsLeases"] = firstTokens.allSatisfy { grid.tokens[$0.key] === $0.value }
        var extraLoads = 0
        for index in 0..<144 {
            grid.thumbnailCache.load(forKey: "other-consumer-\(index)", input: .image(ready)) { _ in extraLoads += 1 }
        }
        wait("other consumers finish") { extraLoads == 144 }
        checks["testActuallyEvictsNearbyImages"] = grid.thumbnailCache.cachedImage(forKey: paths[forward], request: grid.controller.thumbnailRequest) == nil
        grid.fire()
        let handoffToken = grid.tokens[String(forward)]
        wait("evicted near images reheat") { grid.thumbnailCache.cachedImage(forKey: paths[forward], request: grid.controller.thumbnailRequest) != nil }
        checks["completedEvictedDemandCanReheat"] = handoffToken !== firstTokens[String(forward)] && firstTokens[String(forward)]?.cancelled == true
        let beforeForwardScroll = grid.tokens
        grid.scroll(to: forward)
        checks["nearbyBecomingVisibleRetainsProducer"] = grid.visible.contains { $0.reference.sourceID == String(forward) }
            && grid.tokens[String(forward)] === handoffToken && handoffToken?.cancelled == false
        let nextDemand = Set((grid.visible + grid.nearby).map { $0.providerReference.sourceID })
        let departed = Set(beforeForwardScroll.keys).subtracting(nextDemand)
        precondition(!departed.isEmpty, "scroll must move at least one current nearby lease out of demand")
        checks["farOldRequestsAreCancelled"] = departed.allSatisfy { beforeForwardScroll[$0]?.cancelled == true }
        let beforeReverseTokens = grid.tokens
        let reverseColumns = WallpaperLibraryGridMetrics(
            clipWidth: grid.controller.scrollView.contentView.bounds.width, preferredColumns: 5).columns
        let reverseIndex = reverseColumns * 2
        precondition(reverseIndex < forward, "fixture must actually reverse from the forward viewport")
        grid.scroll(to: reverseIndex)
        let reverseIDs = grid.visible.compactMap { Int($0.reference.sourceID) }.sorted()
        precondition(reverseIDs.first! > 0 && reverseIDs.last! + 1 < paths.count,
            "nearest-side checks require an actual offscreen item on both sides")
        checks["reverseScrollPreparesBothNearestSides"] = grid.tokens[String(reverseIDs.first! - 1)] != nil
            && grid.tokens[String(reverseIDs.last! + 1)] != nil
            && grid.nearby.first?.reference.sourceID == String(reverseIDs.first! - 1)
        let reverseVisible = Set(grid.visible.map { $0.providerReference.sourceID })
        let reverseNearby = Set(grid.nearby.map { $0.providerReference.sourceID })
        let reverseDemand = Set((grid.visible + grid.nearby).map { $0.providerReference.sourceID })
        let reverseLeases = Set(grid.tokens.keys)
        checks["boundedAfterReverse"] = reverseNearby.count <= 96
            && (max(0, reverseIDs.first! - reverseIDs.count)..<reverseIDs.first!).allSatisfy { reverseNearby.contains(String($0)) }
            && (reverseIDs.last! + 1...reverseIDs.last! + reverseIDs.count).allSatisfy { reverseNearby.contains(String($0)) }
            && reverseLeases.isSubset(of: reverseDemand)
            && reverseLeases.subtracting(reverseVisible).count <= 96
            && reverseLeases.subtracting(reverseNearby).allSatisfy { id in
                reverseVisible.contains(id) && beforeReverseTokens[id] === grid.tokens[id]
                    && grid.tokens[id]?.cancelled == false
            }
        let changed = grid.nearby.first!.reference.sourceID
        let old = grid.tokens[changed]!
        let changedIndex = imagesIndex(grid.images.wallpapers, id: changed)
        grid.images.wallpapers[changedIndex].path = original.path
        grid.update(); grid.fire()
        checks["changedSourceRevokesOldLease"] = old.cancelled && grid.tokens[changed] !== old
        let beforeClear = grid.tokens
        grid.cancel()
        checks["cancelReleasesEveryLease"] = grid.tokens.isEmpty && beforeClear.values.allSatisfy(\.cancelled)
        grid.schedule()
        let scheduled = grid.pendingWork
        for _ in 0..<50 { grid.schedule() }
        checks["continuousInputDoesNotResetThrottle"] = scheduled != nil && grid.pendingWork === scheduled
        wait("coalesced demand fires") { !grid.tokens.isEmpty }
        checks["scheduledWorkCompletes"] = grid.pendingWork == nil
        let firstVisible = grid.visible.first!.reference
        let firstIndex = grid.items.firstIndex { $0.reference == firstVisible }!
        let windowCard = grid.controller.collection.item(at: IndexPath(item: firstIndex, section: 0)) as! SILGridItem
        var windowCardToken: ThumbnailCacheRequestCancellation?
        windowCard.setThumbnailVisible(false)
        windowCard.configure(wallpaper: grid.images.wallpapers[firstIndex], isSelected: false,
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
        grid.controller.update(page: .images, items: [], selection: .init(), preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        grid.fire()
        checks["synchronousEmptyTopologyRevokesAllOldIDRequests"] = grid.tokens.isEmpty && grid.visible.isEmpty && grid.nearby.isEmpty
        checks["emptyViewportDoesNotStartWork"] = grid.pendingWork == nil || grid.tokens.isEmpty

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
        item.prepareForReuse()
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
        checks.merge(try failureCacheChecks(root: root, original: original)) { _, new in new }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
