import Combine

@MainActor enum VideoReadyDeliveryTrace {
    static var events: [[String: Any]] = []
    static var cardFinals: [String: [Bool]] = [:]
    static func note(_ event: String, _ fields: [String: Any] = [:]) {
        events.append(fields.merging(["event": event, "hostSeconds": ProcessInfo.processInfo.systemUptime]) { _, new in new })
    }
    static func cardFinal(_ name: String, image: Bool) {
        cardFinals[name, default: []].append(image)
        note("card-final", ["name": name, "hasImage": image])
    }
}

nonisolated final class VideoProviderDeliveryObservation: @unchecked Sendable {
    static let shared = VideoProviderDeliveryObservation()
    private let lock = NSLock()
    private var activeCallbacks = Set<String>()
    private var memoryThreads: [String: [Bool]] = [:]
    private var finishes: [String: Int] = [:]
    func enterMainCallback(_ key: String) {
        lock.lock(); activeCallbacks.insert(key); lock.unlock()
    }
    func leaveMainCallback(_ key: String) {
        lock.lock(); activeCallbacks.remove(key); lock.unlock()
    }
    func memoryHit(_ key: String) {
        lock.lock(); memoryThreads[key, default: []].append(Thread.isMainThread); lock.unlock()
    }
    func recordFinish(_ key: String) {
        lock.lock(); finishes[key, default: 0] += 1; lock.unlock()
    }
    func snapshot(_ key: String) -> (insideMainCallback: Bool, memoryThreads: [Bool], finishes: Int) {
        lock.lock(); defer { lock.unlock() }
        return (activeCallbacks.contains(key), memoryThreads[key] ?? [], finishes[key, default: 0])
    }
}

@MainActor final class StatusCoverSink: NSImageView {
    func setImage(_ image: NSImage?) { self.image = image }
}

@MainActor final class StatusVideoCoverProbe {
    enum CoverSource { case video(VideoWallpaper) }
    struct Panel { let cover = StatusCoverSink(frame: .zero) }
    struct ResetLeaf { func reset() {} }
    let panel = Panel()
    let workshopPreview = ResetLeaf()
    let videoPreview: AppKitThumbnailProvider
    let previewQueue = DispatchQueue(label: "mwx.status-cover.preparation", qos: .utility)
    var videoCancellation: ThumbnailCacheRequestCancellation?
    var localImageCancellation: ThumbnailCacheRequestCancellation?
    var displayedCoverSource: CoverSource?
    var refreshToken: Int?
    var imageGeneration: UInt64 = 0
    var finals: [Bool] = []
    var loadStarts = 0, matchingReadyCount = 0
    var readyOverflow = false
    init(manager: WallpaperManager) { videoPreview = AppKitThumbnailProvider(wallpaperManager: manager) }
    // ACTUAL_STATUS_METHODS
}

@MainActor final class StatusReadySubscription {
    let wallpaperManager: WallpaperManager
    let panelController: StatusVideoCoverProbe
    var observing = true
    var cancellables = Set<AnyCancellable>()
    init(manager: WallpaperManager, panel: StatusVideoCoverProbe) {
        wallpaperManager = manager; panelController = panel
        // ACTUAL_STATUS_SUBSCRIPTION
    }
}

@main enum VideoGeneratedThumbnailDeliveryChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        if CommandLine.arguments.contains("--status-cover") { try statusChecks(root: root); return }
        let aURL = root.appendingPathComponent("A.mov"), bURL = root.appendingPathComponent("B.mov")
        let manager = try WallpaperManager(root: root.appendingPathComponent("cache"))
        let a = VideoWallpaper(id: "a", title: "A", path: aURL.path)
        let b = VideoWallpaper(id: "b", title: "B", path: bURL.path)
        manager.wallpapers = [a, b]
        let originalRows = manager.wallpapers
        let aJPEG = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(a.path)))
        let bJPEG = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(b.path)))
        let observed = VideoThumbnailObservations.shared
        let aHold = observed.holdNext(aURL), bHold = observed.holdNext(bURL)
        var releasedA = false, releasedB = false
        defer {
            if !releasedA { aHold.release.signal() }
            if !releasedB { bHold.release.signal() }
        }
        var readyPaths: [String] = []
        let readySubscription = manager.thumbnailReadyPublisher.sink { path in
            readyPaths.append(path)
            VideoReadyDeliveryTrace.note("thumbnail-ready", ["path": path])
        }
        func pump(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(4)
            while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
            return predicate()
        }
        func jpegFacts(_ url: URL) -> [String: Any] {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return ["decoded": false] }
            return ["decoded": true, "width": image.width, "height": image.height,
                "sha256": (try? Data(contentsOf: url)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""]
        }
        func pixel(_ image: NSImage?) -> [Int] {
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
            var rgba = [UInt8](repeating: 0, count: 4)
            rgba.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return rgba.map(Int.init)
        }
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        let card = VideoCardProbe(); card.observationName = "waiting-A"
        func configure(_ value: VideoCardProbe) {
            value.configure(wallpaper: a, isSelected: false, isPlaying: false, multiSelectMode: false,
                wallpaperManager: manager, thumbnailProvider: provider)
        }
        func drainProvider() -> Bool {
            let receipt = DecodeHold()
            provider.decodeQueue.async { DispatchQueue.main.async { receipt.arrive() } }
            return pump { receipt.didEnter }
        }
        func snapshot(_ label: String) -> [String: Any] {
            let facts: [String: Any] = ["label": label, "hostSeconds": ProcessInfo.processInfo.systemUptime,
                "aCardHasImage": card.thumbnailImageView.image != nil, "aCardPixelRGBA": pixel(card.thumbnailImageView.image),
                "aCardRequestPending": card.thumbnailRequestIsPending, "aCardFinals": VideoReadyDeliveryTrace.cardFinals["waiting-A", default: []],
                "aReadyCount": readyPaths.filter { $0 == a.path }.count, "aJPEG": jpegFacts(aJPEG),
                "bHoldEntered": bHold.didEnter, "bReleased": releasedB, "bInFlight": manager.isThumbnailGenerationInFlight(for: b.path),
                "controlledStaticAndModelCalls": manager.importStages.recordedCounts,
                "sourceRowsUnchanged": manager.wallpapers == originalRows]
            VideoReadyDeliveryTrace.note("snapshot", ["label": label])
            return facts
        }
        var controls: [String: Bool] = [:]
        controls["startsWithoutDerivedJPEGs"] = !manager.pathExists(aJPEG.path) && !manager.pathExists(bJPEG.path)
        VideoReadyDeliveryTrace.note("actual-import-batch-start")
        manager.scheduleImportedAssetsProcessing([aURL, bURL])
        let batchDrained = DecodeHold()
        manager.importAssetPipelineQueue.async { batchDrained.arrive() }
        controls["aRealAVEntryIsHeld"] = pump { aHold.didEnter }
        controls["aGenerationIsInFlightBeforeCardRequest"] = manager.isThumbnailGenerationInFlight(for: a.path)
        VideoReadyDeliveryTrace.note("card-configure")
        configure(card)
        controls["originalProviderProcessedInitialRequest"] = drainProvider()
        let beforeReady = snapshot("before-A-ready")
        releasedA = true; aHold.release.signal()
        VideoReadyDeliveryTrace.note("release-A-AV-gate")
        controls["aReadyArrivesWhileBRealAVIsHeld"] = pump { readyPaths.contains(a.path) && bHold.didEnter }
            && !releasedB && manager.isThumbnailGenerationInFlight(for: b.path)
        controls["aJPEGDecodesWithImageIOBeforeBCompletes"] = jpegFacts(aJPEG)["decoded"] as? Bool == true
        let afterReady = snapshot("A-ready-B-held")
        let directDelivery = pump { card.thumbnailImageView.image != nil }
        provider.updateVisiblePreviewDemand(with: [a])
        controls["originalVisibleDemandCheckDrained"] = drainProvider()
        provider.repairVisiblePreviews()
        controls["originalCadenceRepairCheckDrained"] = drainProvider()
        let afterRepair = snapshot("after-original-repair-B-held")
        let controlCard = VideoCardProbe(); controlCard.observationName = "already-ready-A"
        configure(controlCard)
        controls["freshCardReadsTheSameRealAWhileBIsHeld"] = pump { controlCard.thumbnailImageView.image != nil }
        let controlPixel = pixel(controlCard.thumbnailImageView.image)
        controls["freshCardPixelsAreAred"] = controlPixel.count == 4 && controlPixel[0] > 180 && controlPixel[2] < 60
        controls["sourceRowsRemainNilPathAndUnchanged"] = manager.wallpapers == originalRows
            && manager.wallpapers.allSatisfy { $0.thumbnailPath == nil }
        let afterControl = snapshot("after-fresh-A-control-B-held")
        let beforeReleaseCalls = manager.importStages.recordedCounts
        controls["actualBatchHasNotEnteredStaticStageBeforeBRelease"] = !batchDrained.didEnter
            && beforeReleaseCalls["static-" + a.path, default: 0] == 0
            && beforeReleaseCalls["static-" + b.path, default: 0] == 0
        releasedB = true; bHold.release.signal()
        VideoReadyDeliveryTrace.note("release-B-AV-gate")
        controls["actualBatchFinishesAfterBRelease"] = pump { batchDrained.didEnter && readyPaths.contains(b.path) }
        controls["bJPEGDecodesAfterRelease"] = jpegFacts(bJPEG)["decoded"] as? Bool == true
        controls["oneRealThumbnailDecodePerVideo"] = observed.count(aURL) == 1 && observed.count(bURL) == 1
        controls["realDecodeRemainsBoundedOffMain"] = observed.boundedOffMain
        var checks: [String: Bool] = [
            "generatedAReachesOriginalCardWhileBHeld": directDelivery,
            "generatedARequestHasOneSuccessfulFinal": VideoReadyDeliveryTrace.cardFinals["waiting-A"] == [true]
        ]
        let warmScheduleCalls = manager.importStages.count("schedule-static-" + a.path)
        let warmAVCalls = observed.count(aURL)
        var warmAsset: VideoThumbnailAsset?
        manager.ensurePreviewAssetsForWallpaper(a) { warmAsset = $0 }
        checks["warmUIPreparationReturnsReadyThumbnailWithoutSchedulingStaticFrame"] = warmAsset?.path == aJPEG.path
            && manager.importStages.count("schedule-static-" + a.path) == warmScheduleCalls
            && observed.count(aURL) == warmAVCalls
        var recoveryFacts: [String: Any] = [:]
        let cache = VideoLibraryThumbnailStore.sharedCache
        let fm = FileManager.default
        let deliveryPath = root.appendingPathComponent("provider-delivery.jpg")
        try fm.copyItem(at: aJPEG, to: deliveryPath)
        let deliveryRow = VideoWallpaper(id: "provider-delivery", title: "delivery", path: a.path,
            thumbnailPath: deliveryPath.path)
        let deliveryObservation = VideoProviderDeliveryObservation.shared
        var coldDelivery: NSImage?, warmDelivery: NSImage?
        var coldOnMain = false, coldInsideCacheCallback = false, warmOnMain = false
        controls["delivery-cold-has-no-ready-memory"] = cache.cachedImage(forKey: deliveryPath.path) == nil
        let coldLease = provider.loadThumbnail(for: deliveryRow) {
            coldDelivery = $0; coldOnMain = Thread.isMainThread
            coldInsideCacheCallback = deliveryObservation.snapshot(deliveryPath.path).insideMainCallback
        }
        controls["delivery-cold-real-cache-result-arrives"] = pump { coldDelivery != nil }
        checks["cache-main-completion-delivers-before-returning-to-cache"] = coldOnMain && coldInsideCacheCallback
        let beforeWarm = deliveryObservation.snapshot(deliveryPath.path).memoryThreads.count
        let warmLease = provider.loadThumbnail(for: deliveryRow) {
            warmDelivery = $0; warmOnMain = Thread.isMainThread
        }
        controls["delivery-warm-result-arrives"] = pump { warmDelivery != nil }
        let warmThreads = deliveryObservation.snapshot(deliveryPath.path).memoryThreads
        checks["background-memory-hit-still-delivers-on-main"] = warmThreads.count == beforeWarm + 1
            && warmThreads.last == false && warmOnMain && warmDelivery === coldDelivery
        let beforeCancelledWarm = warmThreads.count
        var cancelledWarmCallbacks = 0
        let cancelledWarmLease = provider.loadThumbnail(for: deliveryRow) { _ in cancelledWarmCallbacks += 1 }
        let providerReturned = DispatchSemaphore(value: 0)
        provider.decodeQueue.async { providerReturned.signal() }
        controls["warm-worker-returned-before-main-can-consume-queued-result"] =
            providerReturned.wait(timeout: .now() + 2) == .success
        let cancelledWarmThreads = deliveryObservation.snapshot(deliveryPath.path).memoryThreads
        controls["cancelled-warm-result-used-the-real-background-memory-hit"] =
            cancelledWarmThreads.count == beforeCancelledWarm + 1 && cancelledWarmThreads.last == false
        cancelledWarmLease.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        checks["cancel-after-warm-worker-return-suppresses-queued-main-delivery"] = cancelledWarmCallbacks == 0
        recoveryFacts["provider-delivery"] = ["coldOnMain": coldOnMain, "coldInsideCacheCallback": coldInsideCacheCallback,
            "warmOnMain": warmOnMain, "memoryHitThreads": cancelledWarmThreads,
            "cancelledWarmCallbacks": cancelledWarmCallbacks]
        withExtendedLifetime((coldLease, warmLease, cancelledWarmLease)) {}
        func ownedSource(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name + ".mov")
            try fm.copyItem(at: aURL, to: url)
            return url
        }
        func drained(_ provider: AppKitThumbnailProvider) -> Bool {
            let receipt = DecodeHold()
            provider.decodeQueue.async { DispatchQueue.main.async { receipt.arrive() } }
            return pump { receipt.didEnter }
        }
        for diskOnly in [false, true] {
            let name = diskOnly ? "stale-disk" : "stale-memory"
            let source = try ownedSource(name)
            let owner = try WallpaperManager(root: root.appendingPathComponent(name + "-cache"))
            let row = VideoWallpaper(id: name, title: name, path: source.path)
            owner.wallpapers = [row]
            let currentProvider = AppKitThumbnailProvider(wallpaperManager: owner)
            var generated: String?
            owner.generateThumbnail(for: source) { generated = $0?.path }
            controls[name + "-initial-real-generation"] = pump { generated != nil }
            let outputPath = owner.thumbnailOutputURL(forKey: owner.cacheKey(forNormalizedPath: owner.normalizedPath(source.path)))
            var oldImage: NSImage?
            let oldFinishes = deliveryObservation.snapshot(outputPath.path).finishes
            let oldLease = currentProvider.loadThumbnail(for: row) { oldImage = $0 }
            controls[name + "-old-real-red-pixels-warmed"] = pump {
                oldImage != nil && deliveryObservation.snapshot(outputPath.path).finishes > oldFinishes
            }
                && pixel(oldImage).first.map { $0 > 180 } == true
            let diskURL = cache.diskCacheURL(for: outputPath.path)
            checks[name + "-prepared-JPEG-does-not-create-cache-copy"] = !fm.fileExists(atPath: diskURL.path)
            // Seed a real R112-style derived copy; current prepared-file delivery must not create one.
            cache.remove(forKey: outputPath.path)
            let legacyImage = oldImage!
            var legacySeeded = false
            let finishesBeforeSeed = deliveryObservation.snapshot(outputPath.path).finishes
            cache.load(forKey: outputPath.path, input: .image(legacyImage, nativeSize: nil)) { _ in legacySeeded = true }
            controls[name + "-legacy-cache-seed-completes"] = pump {
                legacySeeded && deliveryObservation.snapshot(outputPath.path).finishes > finishesBeforeSeed
            }
            let diskExisted = fm.fileExists(atPath: diskURL.path)
            controls[name + "-legacy-real-cache-disk-copy-exists"] = diskExisted
            if diskOnly { cache.imageCache.removeAllObjects() }
            controls[name + "-selected-cache-layer-is-controlled"] = (cache.cachedImage(forKey: outputPath.path) == nil) == diskOnly
            try fm.removeItem(at: outputPath)
            try fm.removeItem(at: source); try fm.copyItem(at: bURL, to: source)
            generated = nil
            let hold = observed.holdNext(source)
            owner.generateThumbnail(for: source) { generated = $0?.path }
            controls[name + "-replacement-real-AV-held"] = pump { hold.didEnter }
            var firstDone = false, firstImage: NSImage?
            let replacementLease = currentProvider.loadThumbnail(for: row) { firstImage = $0; firstDone = true }
            controls[name + "-missing-request-processed"] = drained(currentProvider)
            hold.release.signal()
            controls[name + "-replacement-JPEG-created-and-request-final"] = pump { generated != nil && firstDone }
                && jpegFacts(outputPath)["decoded"] as? Bool == true
            let firstPixel = pixel(firstImage)
            var secondDone = false, secondImage: NSImage?
            let secondLease = currentProvider.loadThumbnail(for: row) { secondImage = $0; secondDone = true }
            controls[name + "-post-generation-request-completes"] = pump { secondDone }
            let secondPixel = pixel(secondImage)
            checks[name + "-handoff-uses-new-blue-not-old-cache"] = firstPixel.count == 4 && firstPixel[2] > 180 && firstPixel[0] < 60
            checks[name + "-following-cache-hit-is-new-blue"] = secondPixel.count == 4 && secondPixel[2] > 180 && secondPixel[0] < 60
            checks[name + "-prepared-replacement-does-not-recreate-legacy-copy"] = !fm.fileExists(atPath: diskURL.path)
            controls[name + "-one-replacement-decode-and-no-model-write"] = observed.count(source) == 2 && owner.wallpapers == [row]
            recoveryFacts[name] = ["firstRGBA": firstPixel, "nextRGBA": secondPixel,
                "realAVCalls": observed.count(source), "legacyCacheSeeded": legacySeeded, "cacheDiskBeforeReplacement": diskExisted,
                "staticAndModelLeaves": owner.importStages.recordedCounts]
            withExtendedLifetime((oldLease, replacementLease, secondLease, oldImage)) {}
        }
        do {
            let source = try ownedSource("upgrade-preserves-small")
            let owner = try WallpaperManager(root: root.appendingPathComponent("upgrade-preserves-small-cache"))
            let row = VideoWallpaper(id: "upgrade-preserves-small", title: "upgrade", path: source.path)
            let currentProvider = AppKitThumbnailProvider(wallpaperManager: owner)
            var initial: VideoThumbnailAsset?
            owner.generateThumbnail(for: source) { initial = $0 }
            controls["upgrade-original-master-is-ready"] = pump { initial != nil }
            let smallRequest = ThumbnailRequest(width: 64, height: 64, mode: .fill)
            var smallImage: NSImage?
            let smallLease = currentProvider.loadThumbnail(for: row, request: smallRequest) { smallImage = $0 }
            controls["upgrade-small-real-provider-result-is-warm"] = pump { smallImage != nil }
            let previousBytes = initial.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0.path)) }
            let hold = observed.holdNext(source)
            var largeImage: NSImage?
            let largeLease = currentProvider.loadThumbnail(for: row, request: ThumbnailRequest(width: 256, height: 256, mode: .fill)) { largeImage = $0 }
            controls["upgrade-large-real-AV-is-held"] = pump { hold.didEnter }
            checks["upgrade-keeps-compatible-small-ready-pixels"] = smallImage != nil
                && currentProvider.cachedThumbnail(for: row, request: smallRequest) === smallImage
                && initial.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0.path)) } == previousBytes
            var duringImage: NSImage?
            let duringLease = currentProvider.loadThumbnail(for: row, request: smallRequest) { duringImage = $0 }
            checks["small-consumer-completes-while-larger-upgrade-is-held"] = pump { duringImage != nil }
                && duringImage === smallImage && largeImage == nil
            hold.release.signal()
            checks["upgrade-larger-final-is-correct-and-only-one-extra-AV"] = pump { largeImage != nil }
                && pixel(largeImage).first.map { $0 > 180 } == true && observed.count(source) == 2
            recoveryFacts["upgrade-preserves-small"] = ["AVCalls": observed.count(source),
                "smallStillReady": duringImage != nil, "largeFinal": largeImage != nil]
            withExtendedLifetime((smallLease, largeLease, duringLease)) {}
        }
        let missingWithFallback = root.appendingPathComponent("not-created-with-static-frame.mov")
        let fallbackRow = VideoWallpaper(id: "static-fallback", title: "fallback", path: missingWithFallback.path)
        var staticFallback: NSImage?
        let fallbackLease = provider.loadThumbnail(for: fallbackRow, request: ThumbnailRequest(width: 128, height: 96, mode: .fit),
            fallbackImagePath: aJPEG.path) { staticFallback = $0 }
        checks["existingStaticFallbackIsDeliveredWithoutVideoGeneration"] = pump { staticFallback != nil }
            && pixel(staticFallback).first.map { $0 > 180 } == true && observed.count(missingWithFallback) == 0
            && manager.importStages.count("ensure-" + missingWithFallback.path) == 0
        var preferredThumbnail: NSImage?
        let preferredLease = provider.loadThumbnail(for: a, fallbackImagePath: bJPEG.path) { preferredThumbnail = $0 }
        checks["resolvedThumbnailRemainsPreferredOverStaticFallback"] = pump { preferredThumbnail != nil }
            && pixel(preferredThumbnail).first.map { $0 > 180 } == true && observed.count(aURL) == 1
        withExtendedLifetime((fallbackLease, preferredLease)) {}
        for name in ["prefetch", "cooldown", "missing"] {
            let source: URL
            if name == "missing" { source = root.appendingPathComponent("not-created.mov") }
            else { source = try ownedSource(name) }
            let owner = try WallpaperManager(root: root.appendingPathComponent(name + "-cache"))
            let row = VideoWallpaper(id: name, title: name, path: source.path)
            owner.wallpapers = [row]
            if name == "cooldown" { owner.markThumbnailGenerationFailure(for: owner.normalizedPath(source.path)) }
            let currentProvider = AppKitThumbnailProvider(wallpaperManager: owner)
            var finals: [Bool] = []
            let lease = currentProvider.loadThumbnail(for: row, priority: name == "prefetch" ? .prefetch : .visible) { finals.append($0 != nil) }
            controls[name + "-request-finishes-with-nil"] = pump { !finals.isEmpty } && finals == [false]
            checks[name + "-does-not-start-real-AV"] = observed.count(source) == 0
            if name == "prefetch" || name == "missing" {
                checks[name + "-does-not-enter-ensure-or-report-missing"] = owner.importStages.count("ensure-" + row.path) == 0
                    && owner.importStages.count("missing-" + row.path) == 0
            }
            recoveryFacts[name] = ["finals": finals, "realAVCalls": observed.count(source), "leaves": owner.importStages.recordedCounts]
            withExtendedLifetime(lease) {}
        }
        for name in ["cancel", "clear"] {
            let source = try ownedSource(name)
            let owner = try WallpaperManager(root: root.appendingPathComponent(name + "-cache"))
            let row = VideoWallpaper(id: name, title: name, path: source.path)
            owner.wallpapers = [row]
            let currentProvider = AppKitThumbnailProvider(wallpaperManager: owner)
            let hold = observed.holdNext(source)
            var producerDone = false
            owner.generateThumbnail(for: source) { _ in producerDone = true }
            controls[name + "-real-generation-held"] = pump { hold.didEnter }
            var callbackCount = 0
            let waitingCard = VideoCardProbe(); waitingCard.observationName = name
            var lease: ThumbnailCacheRequestCancellation?
            if name == "clear" {
                waitingCard.configure(wallpaper: row, isSelected: false, isPlaying: false, multiSelectMode: false,
                    wallpaperManager: owner, thumbnailProvider: currentProvider)
            } else {
                lease = currentProvider.loadThumbnail(for: row) { _ in callbackCount += 1 }
            }
            controls[name + "-request-processed-while-producer-held"] = drained(currentProvider)
            let callbacksBeforeCancel = callbackCount
            if name == "cancel" { lease?.cancel() }
            else {
                owner.clearPreviewCacheArtifacts()
                controls["clear-releases-waiting-card-once"] = pump { VideoReadyDeliveryTrace.cardFinals[name]?.count == 1 }
                    && VideoReadyDeliveryTrace.cardFinals[name] == [false]
                checks["clear-nil-final-does-not-start-another-generation"] = !owner.isThumbnailGenerationInFlight(for: source.path)
            }
            hold.release.signal()
            let settled = DecodeHold()
            owner.thumbnailQueue.async(flags: .barrier) { settled.arrive() }
            controls[name + "-old-producer-drained"] = pump { producerDone && settled.didEnter }
            checks[name + "-still-one-real-generation"] = observed.count(source) == 1
            if name == "cancel" { checks["cancel-has-no-late-callback"] = callbackCount == callbacksBeforeCancel }
            else {
                checks["clear-keeps-final-nil-and-no-late-image"] = VideoReadyDeliveryTrace.cardFinals[name] == [false]
                    && waitingCard.thumbnailImageView.image == nil
                    && owner.existingThumbnailPath(for: source) == nil
            }
            recoveryFacts[name] = ["callbacks": callbackCount, "callbacksBeforeCancel": callbacksBeforeCancel,
                "cardFinals": VideoReadyDeliveryTrace.cardFinals[name, default: []], "realAVCalls": observed.count(source),
                "leaves": owner.importStages.recordedCounts]
            withExtendedLifetime((lease, waitingCard)) {}
        }
        let output: [String: Any] = ["controls": controls, "checks": checks, "recovery": recoveryFacts,
            "observations": ["beforeReady": beforeReady, "afterReady": afterReady, "afterRepair": afterRepair,
                "afterFreshControl": afterControl, "freshControlPixelRGBA": controlPixel,
                "allCardFinals": VideoReadyDeliveryTrace.cardFinals, "readyPaths": readyPaths,
                "afterBatchStaticAndModelCalls": manager.importStages.recordedCounts, "events": VideoReadyDeliveryTrace.events],
            "scope": "Actual generator/import batch/provider/cache/card methods; static scheduling, model publication and missing-file presentation are recording leaves. No Catalog/DB/window or automatic 2s cadence execution."]
        withExtendedLifetime((provider, card, controlCard, readySubscription)) {
            print(String(decoding: try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
        }
    }

    @MainActor static func statusChecks(root: URL) throws {
        let manager = try WallpaperManager(root: root.appendingPathComponent("status-cache"))
        WallpaperManager.shared = manager
        let observed = VideoThumbnailObservations.shared
        var controls: [String: Bool] = [:], checks: [String: Bool] = [:], facts: [String: Any] = [:]
        func pump(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(7)
            while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
            return predicate()
        }
        func source(_ name: String, blue: Bool = false) throws -> (URL, VideoWallpaper) {
            let url = root.appendingPathComponent("status-" + name + ".mov")
            try FileManager.default.copyItem(at: root.appendingPathComponent(blue ? "B.mov" : "A.mov"), to: url)
            return (url, VideoWallpaper(id: name, title: name, path: url.path))
        }
        func open(_ row: VideoWallpaper) -> (StatusVideoCoverProbe, StatusReadySubscription) {
            let panel = StatusVideoCoverProbe(manager: manager)
            let subscription = StatusReadySubscription(manager: manager, panel: panel)
            panel.displayedCoverSource = .video(row); panel.imageGeneration = 1
            panel.loadVideoCover(row, generation: panel.imageGeneration)
            return (panel, subscription)
        }
        func drained(_ panel: StatusVideoCoverProbe) -> Bool {
            let done = DecodeHold()
            let decodeQueue = panel.videoPreview.decodeQueue
            panel.previewQueue.async {
                decodeQueue.async { DispatchQueue.main.async { done.arrive() } }
            }
            return pump { done.didEnter }
        }
        func red(_ image: NSImage?) -> Bool {
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            var rgba = [UInt8](repeating: 0, count: 4)
            rgba.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return rgba[0] > 180 && rgba[2] < 60
        }
        func receipt(_ panel: StatusVideoCoverProbe, _ url: URL) -> [String: Any] {
            ["finals": panel.finals, "loadStarts": panel.loadStarts, "matchingReady": panel.matchingReadyCount,
             "readyOverflow": panel.readyOverflow, "hasImage": panel.panel.cover.image != nil,
             "realAVCalls": observed.count(url), "generateCalls": manager.importStages.count("requested-" + url.path),
             "ensureCalls": manager.importStages.count("ensure-" + url.path)]
        }
        let (coldURL, coldRow) = try source("cold")
        let coldHold = observed.holdNext(coldURL)
        let (cold, coldSubscription) = open(coldRow)
        controls["cold-enters-real-held-AV"] = pump { coldHold.didEnter }
        controls["cold-has-no-early-final"] = cold.finals.isEmpty && cold.panel.cover.image == nil
        coldHold.release.signal()
        controls["cold-final-arrives"] = pump { !cold.finals.isEmpty || cold.readyOverflow }
        checks["normal-cold-provider-final-is-red"] = cold.finals == [true] && red(cold.panel.cover.image)
            && observed.count(coldURL) == 1 && !cold.readyOverflow
        facts["cold"] = receipt(cold, coldURL)
        cold.releasePreview()
        let (warm, warmSubscription) = open(coldRow)
        controls["warm-final-arrives"] = pump { !warm.finals.isEmpty || warm.readyOverflow }
        checks["warm-shares-real-cache-without-AV"] = warm.finals == [true] && red(warm.panel.cover.image)
            && observed.count(coldURL) == 1
        let warmStarts = warm.loadStarts
        manager.notifyThumbnailReady(forPath: coldRow.path)
        controls["external-ready-is-delivered"] = pump { warm.finals.count >= 2 || warm.readyOverflow }
        checks["external-ready-still-reloads-same-source"] = warm.loadStarts == warmStarts + 1
            && warm.finals == [true, true] && red(warm.panel.cover.image)
        facts["warmAndExternalReady"] = receipt(warm, coldURL)
        warm.releasePreview()

        let (clearURL, clearRow) = try source("clear")
        let clearHold = observed.holdNext(clearURL)
        let (cleared, clearSubscription) = open(clearRow)
        controls["clear-enters-real-held-AV"] = pump { clearHold.didEnter }
        manager.clearPreviewCacheArtifacts()
        controls["clear-settles-or-exposes-restart"] = pump {
            !cleared.finals.isEmpty || cleared.loadStarts > 1 || cleared.readyOverflow
        }
        clearHold.release.signal()
        controls["clear-producers-drain"] = pump {
            !manager.isThumbnailGenerationInFlight(for: clearURL.path) && observed.boundedOffMain
                && (!cleared.finals.isEmpty || cleared.readyOverflow)
        } && drained(cleared)
        checks["clear-nil-does-not-regenerate-or-reload"] = cleared.finals == [false]
            && cleared.loadStarts == 1 && observed.count(clearURL) == 1 && cleared.panel.cover.image == nil
        facts["clear"] = receipt(cleared, clearURL)
        cleared.releasePreview()

        let (switchURL, switchRow) = try source("switch", blue: true)
        let switchHold = observed.holdNext(switchURL)
        let (switched, switchSubscription) = open(switchRow)
        controls["switch-enters-real-held-AV"] = pump { switchHold.didEnter }
        switched.videoCancellation?.cancel()
        switched.imageGeneration &+= 1; switched.displayedCoverSource = .video(coldRow)
        switched.loadVideoCover(coldRow, generation: switched.imageGeneration)
        controls["switch-current-red-final-arrives"] = pump { red(switched.panel.cover.image) }
        let currentReadyCount = switched.matchingReadyCount
        switchHold.release.signal()
        controls["switch-old-producer-drains"] = pump {
            !manager.isThumbnailGenerationInFlight(for: switchURL.path) && observed.boundedOffMain
        } && drained(switched)
        checks["old-ready-and-late-callback-cannot-replace-new-source"] = red(switched.panel.cover.image)
            && switched.finals == [true] && switched.matchingReadyCount == currentReadyCount
        facts["switch"] = receipt(switched, switchURL)
        switched.releasePreview()

        let (closeURL, closeRow) = try source("close", blue: true)
        let closeHold = observed.holdNext(closeURL)
        let (closed, closeSubscription) = open(closeRow)
        controls["close-enters-real-held-AV"] = pump { closeHold.didEnter }
        closed.releasePreview()
        let startsAtClose = closed.loadStarts
        closeHold.release.signal()
        controls["close-old-producer-drains"] = pump {
            !manager.isThumbnailGenerationInFlight(for: closeURL.path) && observed.boundedOffMain
        } && drained(closed)
        checks["release-cancels-and-cannot-reopen-on-ready"] = closed.finals.isEmpty
            && closed.loadStarts == startsAtClose && closed.panel.cover.image == nil && closed.matchingReadyCount == 0
        facts["close"] = receipt(closed, closeURL)

        let missingURL = root.appendingPathComponent("status-not-created.mov")
        let missingRow = VideoWallpaper(id: "missing", title: "missing", path: missingURL.path)
        let (missing, missingSubscription) = open(missingRow)
        controls["missing-source-provider-final-arrives"] = pump { !missing.finals.isEmpty || missing.readyOverflow }
        controls["missing-source-is-quiescent"] = pump {
            !manager.isThumbnailGenerationInFlight(for: missingURL.path) && observed.boundedOffMain
        } && drained(missing)
        checks["missing-source-final-is-nil"] = missing.finals == [false] && missing.panel.cover.image == nil
        checks["missing-source-does-not-enter-ensure-or-generation"] = observed.count(missingURL) == 0
            && manager.importStages.count("ensure-" + missingURL.path) == 0
            && manager.importStages.count("requested-" + missingURL.path) == 0
        facts["missing"] = receipt(missing, missingURL)
        missing.releasePreview()

        let invalidURL = root.appendingPathComponent("status-invalid.mov")
        try Data("not a video".utf8).write(to: invalidURL)
        let invalidRow = VideoWallpaper(id: "invalid", title: "invalid", path: invalidURL.path)
        let (failed, failureSubscription) = open(invalidRow)
        controls["failure-final-or-bounded-ready-overflow-arrives"] = pump { !failed.finals.isEmpty || failed.readyOverflow }
        controls["failure-real-AV-is-quiescent"] = pump { observed.boundedOffMain } && drained(failed)
        checks["failure-cooldown-does-not-feedback-ready"] = failed.finals == [false]
            && !failed.readyOverflow && failed.loadStarts == 1 && failed.panel.cover.image == nil
        facts["failure"] = receipt(failed, invalidURL)
        failed.releasePreview()
        var weakProbe: StatusVideoCoverProbe? = StatusVideoCoverProbe(manager: manager)
        weak var releasedProbe = weakProbe
        weakProbe?.displayedCoverSource = .video(coldRow)
        weakProbe?.imageGeneration = 1
        weakProbe?.loadVideoCover(coldRow, generation: 1)
        weakProbe = nil
        checks["queued-cover-work-does-not-retain-released-consumer"] = pump { releasedProbe == nil }
        withExtendedLifetime((coldSubscription, warmSubscription, clearSubscription, switchSubscription,
                              closeSubscription, missingSubscription, failureSubscription)) {
            let output: [String: Any] = ["controls": controls, "checks": checks, "status": facts,
                "events": VideoReadyDeliveryTrace.events,
                "scope": "Actual Status four methods and original ready receive/sink/store chain, Provider, Core, cache and owned AV. NSImageView sink and field-only carriers; static/model leaves. Eight matching ready events release the actual consumer as a bounded failure observation. No full Status window, controller lifecycle, Catalog, DB or visible rendering proof."]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
        }
    }
}
