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

@main enum VideoGeneratedThumbnailDeliveryChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
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
        var recoveryFacts: [String: Any] = [:]
        let cache = VideoLibraryThumbnailStore.sharedCache
        let fm = FileManager.default
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
            owner.generateThumbnail(for: source) { generated = $0 }
            controls[name + "-initial-real-generation"] = pump { generated != nil }
            let outputPath = owner.thumbnailOutputURL(forKey: owner.cacheKey(forNormalizedPath: owner.normalizedPath(source.path)))
            var oldImage: NSImage?
            let oldLease = currentProvider.loadThumbnail(for: row) { oldImage = $0 }
            controls[name + "-old-real-red-pixels-warmed"] = pump { oldImage != nil }
                && pixel(oldImage).first.map { $0 > 180 } == true
            let diskURL = cache.diskCacheURL(for: outputPath.path)
            let diskExisted = fm.fileExists(atPath: diskURL.path)
            controls[name + "-real-cache-disk-copy-exists"] = diskExisted
            if diskOnly { cache.imageCache.removeAllObjects() }
            controls[name + "-selected-cache-layer-is-controlled"] = (cache.cachedImage(forKey: outputPath.path) == nil) == diskOnly
            try fm.removeItem(at: outputPath)
            try fm.removeItem(at: source); try fm.copyItem(at: bURL, to: source)
            generated = nil
            let hold = observed.holdNext(source)
            owner.generateThumbnail(for: source) { generated = $0 }
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
            controls[name + "-one-replacement-decode-and-no-model-write"] = observed.count(source) == 2 && owner.wallpapers == [row]
            recoveryFacts[name] = ["firstRGBA": firstPixel, "nextRGBA": secondPixel,
                "realAVCalls": observed.count(source), "cacheDiskBeforeReplacement": diskExisted,
                "staticAndModelLeaves": owner.importStages.recordedCounts]
            withExtendedLifetime((oldLease, replacementLease, secondLease, oldImage)) {}
        }
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
}
