import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum SteamWorkshopWebDependencyStatus: Equatable { case none, available(itemID: String), missing(itemID: String) }

/// Only the service's unrelated catalog owner is substituted. Hydration, image
/// transport, cache IO, source decisions and presentation state are production.
@MainActor final class SteamWorkshopService {
    var browserItems: [SteamWorkshopBrowserItem] = []
    var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    var downloads: [SteamWorkshopDownloadRecord] = []
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { downloads.first { $0.id == id } }
}

nonisolated final class ReuseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func increment(_ key: String) { lock.lock(); counts[key, default: 0] += 1; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[key, default: 0] }
}

// This wrapper is used only by the temporary production prefetch copy.
nonisolated func checkedPrefetchKey(for url: URL, maxPixelSize: Int) -> String {
    precondition(!Thread.isMainThread, "prefetch must never fingerprint on the UI thread")
    return steamWorkshopPreviewStillKey(for: url, maxPixelSize: maxPixelSize)
}

@main struct ThumbnailReturnReuseChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        func pump(_ test: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(8)
            while !test(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            return test()
        }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["REUSE_FIXTURE_ROOT"]!)
        let remote = URL(string: ProcessInfo.processInfo.environment["REUSE_FIXTURE_REMOTE"]!)!
        let local = root.appendingPathComponent("preview.gif")
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 3, nil)!
        for color in [NSColor.black, .red, .blue] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 640,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            color.setFill(); NSRect(x: 0, y: 0, width: 640, height: 640).fill()
            NSGraphicsContext.restoreGraphicsState()
            CGImageDestinationAddImage(destination, bitmap.cgImage!,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        let original = data as Data
        try original.write(to: local)
        try original.write(to: root.appendingPathComponent("remote.gif"))
        let red = steamWorkshopPreviewImage(from: original)!
        let blue = NSImage(size: NSSize(width: 20, height: 20))
        let memory = DecodedThumbnailMemoryCache(countLimit: 3, totalCostLimit: 300)
        for key in ["a", "b", "c"] { memory.setObject(red, forKey: key as NSString, cost: 100) }
        _ = memory.object(forKey: "a")
        memory.setObject(blue, forKey: "d", cost: 100)
        checks["accessPromotesRecentCardInsteadOfInsertionOrder"] = memory.object(forKey: "b") == nil
            && memory.object(forKey: "a") === red && memory.object(forKey: "d") === blue
        memory.setObject(red, forKey: "oversize", cost: 301)
        checks["oversizeDoesNotDiscardWorkingSet"] = memory.object(forKey: "oversize") == nil && memory.object(forKey: "a") === red
        memory.setObject(blue, forKey: "a", cost: 220)
        checks["replacementUsesNewCostAndEvictsOlderEntries"] = memory.object(forKey: "a") === blue
            && memory.object(forKey: "c") == nil && memory.object(forKey: "d") == nil
        DispatchQueue.concurrentPerform(iterations: 300) { i in
            memory.setObject(red, forKey: "thread-\(i % 5)" as NSString, cost: 100)
            _ = memory.object(forKey: "thread-\((i + 1) % 5)" as NSString)
        }
        memory.removeAllObjects()
        checks["pressureAndExplicitReleaseEmptyMemoryTier"] = (0..<5).allSatisfy { memory.object(forKey: "thread-\($0)" as NSString) == nil }

        func stillBytes(width: Int, height: Int, orientation: Int = 1) -> Data {
            let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            cg.setFillColor(NSColor.red.cgColor); cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, cg.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            precondition(CGImageDestinationFinalize(destination)); return data as Data
        }
        for (name, width, height, orientation) in [("portrait", 800, 1200, 1), ("panorama", 1600, 800, 1), ("rotated", 1200, 800, 6)] {
            let bytes = stillBytes(width: width, height: height, orientation: orientation)
            for (scale, tier) in [(1, 256), (2, 512)] {
                let image = steamWorkshopPreviewImage(from: bytes, maxPixelSize: tier)!
                let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                let requiredShortSide = name == "panorama" && scale == 2 ? 400 : 256 * scale
                checks["\(name)-\(scale)x-both-axes-within-old-cap"] = min(cg.width, cg.height) >= requiredShortSide
                    && max(cg.width, cg.height) <= 800
            }
        }
        let fallbackStore = ThumbnailCache(namespace: "generated-local-" + UUID().uuidString)
        let generationCounter = ReuseCounter()
        for _ in 0..<8 {
            var image: NSImage?
            fallbackStore.load(forKey: "existing-thumbnail") {
                generationCounter.increment("extract"); return red
            } completion: { image = $0 }
            _ = pump { image != nil }; fallbackStore.imageCache.removeAllObjects()
        }
        checks["sharedLocalDiskCacheAvoidsRepeatedSourceExtraction"] = generationCounter.count("extract") == 1

        var pixabayChecksFinished = false
        Task { @MainActor in
            let pixabayCache = OnlineImageThumbnailCache.shared
            await pixabayCache.clearAll()
            let epoch = await pixabayCache.publicationGeneration()
            let first = await pixabayCache.storeAndDecode(data: original, for: remote, maxPixelSize: 512, generation: epoch)
            checks["onlineReadyPixelsAvailableSynchronously"] = first != nil && pixabayCache.readyImage(for: remote, maxPixelSize: 512) === first
            await pixabayCache.clearAll()
            // A delayed HTTP/prefetch response still carries its pre-clear epoch.
            let late = await pixabayCache.storeAndDecode(data: original, for: remote, maxPixelSize: 512, generation: epoch)
            await pixabayCache.store(data: original, for: remote, generation: epoch)
            let raw = await pixabayCache.cachedData(for: remote)
            checks["onlineClearRejectsOldVisibleAndPrefetchPublication"] = late == nil && raw == nil
                && pixabayCache.readyImage(for: remote, maxPixelSize: 512) == nil
            let next = await pixabayCache.publicationGeneration()
            let fresh = await pixabayCache.storeAndDecode(data: original, for: remote, maxPixelSize: 512, generation: next)
            checks["onlineNewGenerationStillPublishesNormally"] = fresh != nil
            await pixabayCache.clearAll()
            pixabayChecksFinished = true
        }
        checks["onlineActorChecksCompleted"] = pump { pixabayChecksFinished }

        let counter = ReuseCounter()
        let cache = ThumbnailCache(namespace: "return-reuse-" + UUID().uuidString)
        func load() -> NSImage? {
            var result: NSImage?
            cache.loadImageDataAsync(forKey: "still-512", sourceDataKey: "original", loader: {
                counter.increment("network"); return original
            }, decoder: { bytes in
                let source = CGImageSourceCreateWithData(bytes as CFData, nil)!
                counter.increment(CGImageSourceGetCount(source) > 1 ? "original-decode" : "still-decode")
                return steamWorkshopPreviewImage(from: bytes, maxPixelSize: 512)
            }) {
                counter.increment("image-callback")
                if !Thread.isMainThread { counter.increment("off-main-callback") }
                result = $0
            }
            _ = pump { result != nil }; return result
        }
        let first = load()!
        checks["coldSourceCreatesStillAndRetainsOriginal"] = counter.count("network") == 1 && counter.count("original-decode") == 1
        var synchronous = false
        var loadReturned = false
        cache.loadImageDataAsync(forKey: "still-512", sourceDataKey: "original", loader: { nil }) {
            synchronous = $0 === first && !loadReturned && Thread.isMainThread
        }
        loadReturned = true
        checks["warmMemoryReturnsSynchronously"] = synchronous
        for _ in 0..<12 { cache.imageCache.removeAllObjects(); _ = load() }
        checks["twelveDiskReturnsNeverRefetchOrRescanGIF"] = counter.count("network") == 1
            && counter.count("original-decode") == 1 && counter.count("still-decode") == 12
        checks["coldAndDiskImageCallbacksStayOnMainAndCompleteOnce"] = counter.count("image-callback") == 13
            && counter.count("off-main-callback") == 0
        var raw: Data?
        cache.loadRawDataAsync(forKey: "original", loader: { nil }) {
            counter.increment("raw-callback")
            if !Thread.isMainThread { counter.increment("off-main-callback") }
            raw = $0
        }
        checks["hoverStillReceivesAllOriginalFrames"] = pump { raw != nil } && raw == original
            && steamWorkshopAnimatedPreviewImage(from: raw!) != nil
        checks["rawCallbackStaysOnMainAndCompletesOnce"] = counter.count("raw-callback") == 1
            && counter.count("off-main-callback") == 0
        cache.remove(forKey: "still-512")
        _ = load()
        checks["missingDerivedStillRebuildsFromRawWithoutNetwork"] = counter.count("network") == 1 && counter.count("original-decode") == 2

        func item(_ id: String, _ preview: URL) -> SteamWorkshopBrowserItem {
            SteamWorkshopBrowserItem(id: id, title: "Cache fixture", author: "Author", authorProfileURL: nil,
                authorWorkshopURL: nil, hasAdultContent: false, summary: "", descriptionText: "", tags: [],
                workshopTypeText: nil, ageRatingText: nil, genreText: nil, categoryText: nil, dependencyIDs: [],
                previewImageURL: preview, previewVideoURL: nil, previewAssetKind: .animatedImage, fileSizeText: nil,
                resolutionText: nil, postedText: nil, updatedText: nil, favoritesText: nil, subscriptionsText: nil,
                scoreText: nil, lifetimeFavoritesText: nil, lifetimeSubscriptionsText: nil, visibilityText: nil,
                moderationText: nil, detailFields: [], detailURL: remote)
        }
        func record(_ item: SteamWorkshopBrowserItem, preview: URL, status: SteamWorkshopDownloadRecord.Status = .ready) -> SteamWorkshopDownloadRecord {
            SteamWorkshopDownloadRecord(id: item.id, title: item.title, description: "", tags: [], folderURL: root,
                projectFileURL: nil, ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
                entryHTMLURL: nil, resolvedWebRootURL: nil, previewURL: preview, sourceVideoURL: nil,
                exportedVideoURL: nil, updatedAt: Date(), sizeText: "", status: status, browserItem: item,
                contentType: .video, dependencyItemID: nil, dependencyStatus: .none)
        }
        let forward = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(40...51), itemCount: 100, neighborLimit: 12, direction: 1)
        let backward = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(40...51), itemCount: 100, neighborLimit: 12, direction: -1)
        checks["nearestDemandIncludesForwardInsteadOfPrefixTruncation"] = forward == [52,39,53,38,54,37,55,36,56,35,57,34]
        checks["reverseChangesPriorityWithoutChangingBoundedNeighborhood"] = backward == [39,52,38,53,37,54,36,55,35,56,34,57]
        checks["nearestDemandClampsEdgesAndSkipsVisibleGaps"] = GridThumbnailPrefetchDemand.indices(visibleIndices: [-1,0,2,100], itemCount: 5, neighborLimit: 24, direction: -1) == [3,4]
        checks["emptyViewportNeverWarmsCatalog"] = GridThumbnailPrefetchDemand.indices(visibleIndices: [], itemCount: 10_000, neighborLimit: 24, direction: 1).isEmpty

        let online = item("local-ready", remote.appendingPathComponent("local-ready.gif"))
        let installed = record(online, preview: local)
        var requests: [(URL, Int, SteamWorkshopPreviewLoadCancellation, (NSImage?) -> Void)] = []
        var observedPrefetch: SteamWorkshopPreviewPrefetchController? = SteamWorkshopPreviewPrefetchController(load: {
            requests.append(($0, $1, $2, $3))
        })
        func settle(_ controller: SteamWorkshopPreviewPrefetchController) {
            precondition(pump { !controller.preparationIsRunning && controller.pendingSources == nil }, "source preparation timed out")
        }
        let nearby = SteamWorkshopPreviewPrefetchController.Candidate(id: online.id, item: online, record: installed)
        observedPrefetch!.replace(with: [nearby], maxPixelSize: 256)
        observedPrefetch!.replace(with: [nearby], maxPixelSize: 256)
        settle(observedPrefetch!)
        checks["prefetchSameIdentityOnlyStartsOnce"] = requests.count == 1 && requests[0].0 == local
        var becameVisible = nearby; becameVisible.startsIfMissing = false
        observedPrefetch!.replace(with: [becameVisible], maxPixelSize: 256)
        settle(observedPrefetch!)
        checks["prefetchLeaseSurvivesDelayedVisibleSourceValidation"] = requests.count == 1 && !requests[0].2.cancelled
        observedPrefetch!.replace(with: [becameVisible], maxPixelSize: 512)
        checks["pixelChangeCancelsObsoleteLeaseWithoutStartingVisibleDuplicate"] = requests[0].2.cancelled && requests.count == 1
        observedPrefetch!.replace(with: [nearby], maxPixelSize: 512)
        settle(observedPrefetch!)
        checks["newPixelDemandStartsRequestedTier"] = requests.count == 2 && requests[1].1 == 512
        requests[1].3(nil)
        checks["failedInstalledPrefetchUsesRemoteFallbackWithSameLease"] = requests.count == 3
            && requests[2].0 == online.previewImageURL && requests[1].2 === requests[2].2
        observedPrefetch!.replace(with: [], maxPixelSize: 512)
        checks["leavingViewportCancelsOnlyGridConsumer"] = requests[2].2.cancelled
        observedPrefetch!.replace(with: [nearby], maxPixelSize: 256)
        settle(observedPrefetch!)
        observedPrefetch!.cancelAll()
        checks["hideOrClearCancelsAllPrefetch"] = requests.last!.2.cancelled
        observedPrefetch!.replace(with: [nearby], maxPixelSize: 256)
        settle(observedPrefetch!)
        let surviving = requests.last!.2
        observedPrefetch = nil
        checks["deinitRetiresGridPrefetchConsumers"] = surviving.cancelled
        let pressurePrefetch = SteamWorkshopPreviewPrefetchController(load: { requests.append(($0, $1, $2, $3)) })
        pressurePrefetch.replace(with: [nearby], maxPixelSize: 800)
        settle(pressurePrefetch)
        let beforeRelease = requests.count
        requests.last!.3(red)
        // No corresponding ready pixels remain, as after an LRU pressure release.
        pressurePrefetch.replace(with: [nearby], maxPixelSize: 800)
        settle(pressurePrefetch)
        checks["completedPrefetchRewarmsAfterDecodedPixelsAreEvicted"] = requests.count == beforeRelease + 1
        pressurePrefetch.cancelAll()
        let blocked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        SteamWorkshopPreviewPrefetchController.preparationQueue.async {
            blocked.signal(); release.wait()
        }
        precondition(blocked.wait(timeout: .now() + 2) == .success)
        let countBeforeBlocked = requests.count
        let coalesced = SteamWorkshopPreviewPrefetchController(load: { requests.append(($0, $1, $2, $3)) })
        coalesced.replace(with: [nearby], maxPixelSize: 256)
        coalesced.replace(with: [nearby], maxPixelSize: 800)
        coalesced.cancelAll()
        coalesced.replace(with: [nearby], maxPixelSize: 512)
        checks["blockedFileChecksLeaveMainThreadResponsive"] = requests.count == countBeforeBlocked
        release.signal()
        settle(coalesced)
        checks["latestViewportSurvivesHideAndLateSourcePreparation"] = requests.count == countBeforeBlocked + 1
            && requests.last!.1 == 512
        coalesced.cancelAll()

        let selected = steamWorkshopPreviewSources(item: online, record: installed)
        checks["onlineAndSubscriptionPickInstalledPreviewBeforeRemote"] = selected.primary == local && selected.fallback == online.previewImageURL
        checks["incompleteDownloadKeepsRemotePreview"] = steamWorkshopPreviewSources(item: online,
            record: record(online, preview: local, status: .downloading)).primary == online.previewImageURL
        let state = SteamWorkshopPreviewState()
        var observedLoading = false
        state.onChange = { if state.placeholder == .loading { observedLoading = true } }
        state.configure(previewURL: selected.primary, fallbackImageURL: selected.fallback, fallbackVideoURL: nil, maxPixelSize: 512)
        checks["liveLocalSourceLoadsWithoutRemote"] = pump { state.image != nil }
        state.reset(); observedLoading = false
        state.configure(previewURL: selected.primary, fallbackImageURL: selected.fallback, fallbackVideoURL: nil, maxPixelSize: 512)
        checks["readyReuseDoesNotEmitIntermediateLoading"] = state.image != nil && !observedLoading
        let service = SteamWorkshopService()
        service.displayedBrowserItems = [online]; service.downloads = [installed]
        let prefetch = SteamWorkshopPreviewPrefetchController()
        prefetch.replace(with: [.init(id: online.id, item: online, record: installed)], maxPixelSize: 256)
        checks["prefetchSharesInstalledSourceAndRequestedPixelTier"] = pump { steamWorkshopCachedPreviewImage(for: local, maxPixelSize: 256) != nil }
        let oldKey = steamWorkshopPreviewStillKey(for: local, maxPixelSize: 512)
        try Data([0, 1, 2, 3]).write(to: local)
        checks["localReplacementChangesCacheIdentity"] = oldKey != steamWorkshopPreviewStillKey(for: local, maxPixelSize: 512)
        let corruptRemote = remote.appendingPathComponent("corrupt-fallback.gif")
        state.configure(previewURL: local, fallbackImageURL: corruptRemote, fallbackVideoURL: nil, maxPixelSize: 512)
        checks["corruptLocalFallsBackToRealHTTP"] = pump { state.image != nil && state.placeholder == .hidden }
        try FileManager.default.removeItem(at: local)
        state.configure(previewURL: local, fallbackImageURL: remote.appendingPathComponent("missing-fallback.gif"), fallbackVideoURL: nil)
        checks["deletedLocalDoesNotReviveOldStaticCache"] = pump { state.image != nil && state.placeholder == .hidden }
        cache.clearAll()
        _ = load()
        checks["explicitClearRequiresFreshSource"] = counter.count("network") == 2
        state.reset()
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks, "counts": [
            "network": counter.count("network"), "originalDecodes": counter.count("original-decode"),
            "stillDecodes": counter.count("still-decode")]], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
