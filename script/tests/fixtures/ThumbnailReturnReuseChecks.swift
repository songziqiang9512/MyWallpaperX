import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum SteamWorkshopWebDependencyStatus: Equatable, Codable { case none, available(itemID: String), missing(itemID: String) }

/// Only the service's unrelated catalog owner is substituted. Hydration, image
/// transport, cache IO, source decisions and presentation state are production.
@MainActor final class SteamWorkshopService {
    var browserItems: [SteamWorkshopBrowserItem] = []
    var displayedBrowserItems: [SteamWorkshopBrowserItem] = []
    var downloads: [SteamWorkshopDownloadRecord] = []
    var previewReloadToken = 0
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { downloads.first { $0.id == id } }
}

nonisolated final class ReuseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func increment(_ key: String) { lock.lock(); counts[key, default: 0] += 1; lock.unlock() }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[key, default: 0] }
}

nonisolated enum ReuseInputObservation {
    static let counter = ReuseCounter()
}

@MainActor enum AdapterPrefetchRetentionProbe {
    final class Entry {
        weak var image: NSImage?
        let bytes: Int
        init(_ image: NSImage) {
            self.image = image
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            bytes = cg.bytesPerRow * cg.height
        }
    }
    static var entries: [String: Entry] = [:]
    static func record(_ image: NSImage, source: URL) {
        guard source.lastPathComponent.hasPrefix("prefetch-retention-") else { return }
        entries[source.lastPathComponent] = Entry(image)
    }
    static var live: [String: Int] {
        let held = entries.values.filter { $0.image != nil }
        return ["images": held.count, "bytes": held.reduce(0) { $0 + $1.bytes }]
    }
}

// This wrapper is used only by the temporary production prefetch copy.
nonisolated func checkedPrefetchKey(for url: URL, maxPixelSize: Int) -> String {
    precondition(!Thread.isMainThread, "prefetch must never fingerprint on the UI thread")
    return steamWorkshopPreviewStillKey(for: url, maxPixelSize: maxPixelSize)
}

@main struct ThumbnailReturnReuseChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        var taskRowPixels: [String: [String: Int]] = [:]
        func pump(_ seconds: TimeInterval = 8, _ test: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
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

        func stillBytes(width: Int, height: Int, orientation: Int = 1, color: NSColor = .red) -> Data {
            let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            cg.setFillColor(color.cgColor); cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
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
        for tier in [256, 512, 800] {
            let previewURL = root.appendingPathComponent("steam-target-\(tier).jpg")
            try stillBytes(width: 1200, height: 1200).write(to: previewURL)
            let shared = SteamWorkshopPreviewImageCache.shared
            shared.clearAll()
            let decodeKey = "steam-decode-\(tier)", before = ReuseInputObservation.counter.count("steam-decode-\(tier)")
            let preheated = SteamWorkshopPreviewState(loaders: .live(priority: .prefetch))
            preheated.configure(previewURL: previewURL, fallbackVideoURL: nil, maxPixelSize: tier)
            let prepared = pump { preheated.image != nil }
            let first = preheated.image
            let pixels = first?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            if let pixels {
                taskRowPixels["steam-\(tier)"] = ["width": pixels.width, "height": pixels.height,
                    "bytes": pixels.bytesPerRow * pixels.height]
            }
            let visible = SteamWorkshopPreviewState()
            visible.configure(previewURL: previewURL, fallbackVideoURL: nil, maxPixelSize: tier)
            checks["steam-\(tier)-visible-reuses-prefetched-pixels-without-decoding"] = prepared && first != nil
                && pixels?.width == tier && pixels?.height == tier && visible.image === first
                && ReuseInputObservation.counter.count(decodeKey) == before + 1
            if tier > 256 {
                checks["steam-\(tier)-preparation-does-not-create-unused-256-variant"] =
                    shared.cachedImage(forKey: steamWorkshopPreviewStillKey(for: previewURL, maxPixelSize: 256)) == nil
            }
            try stillBytes(width: 1200, height: 1200, color: .blue).write(to: previewURL, options: .atomic)
            visible.configure(previewURL: previewURL, fallbackVideoURL: nil, maxPixelSize: tier)
            let replaced = pump { visible.image != nil && visible.image !== first }
            let replacement = visible.image
            let color = replacement?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                .flatMap { NSBitmapImageRep(cgImage: $0).colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB) }
            checks["steam-\(tier)-source-replacement-does-not-borrow-old-ready-pixels"] = replaced
                && (color?.blueComponent ?? 0) > 0.9 && (color?.redComponent ?? 1) < 0.1
                && ReuseInputObservation.counter.count(decodeKey) == before + 2
            shared.clearAll()
            let readyAfterClear = steamWorkshopCachedPreviewImage(for: previewURL, maxPixelSize: tier)
            let afterClear = SteamWorkshopPreviewState()
            afterClear.configure(previewURL: previewURL, fallbackVideoURL: nil, maxPixelSize: tier)
            checks["steam-\(tier)-clear-requires-fresh-pixels-but-keeps-live-view"] = readyAfterClear == nil
                && visible.image === replacement && pump { afterClear.image != nil }
                && afterClear.image !== replacement && ReuseInputObservation.counter.count(decodeKey) == before + 3
            preheated.reset(); visible.reset(); afterClear.reset()
        }
        let fallbackStore = ThumbnailCache(namespace: "generated-local-" + UUID().uuidString)
        let generationCounter = ReuseInputObservation.counter
        let inputsBeforeReturns = generationCounter.count("input")
        for _ in 0..<8 {
            var image: NSImage?
            let finishesBeforeReturn = generationCounter.count("finish:existing-thumbnail")
            fallbackStore.load(forKey: "existing-thumbnail", input: .image(red)) { image = $0 }
            precondition(pump { image != nil && generationCounter.count("finish:existing-thumbnail") > finishesBeforeReturn })
            fallbackStore.imageCache.removeAllObjects()
        }
        checks["sharedLocalDiskCacheAvoidsRepeatedSourceExtraction"] = generationCounter.count("input") == inputsBeforeReturns + 1

        var pixabayChecksFinished = false
        Task { @MainActor in
            let pixabayCache = OnlineImageThumbnailCache.shared
            await pixabayCache.clearAll()
            let epoch = await pixabayCache.publicationGeneration()
            let target = ThumbnailRequest(width: 512, height: 288, mode: .fit)
            await pixabayCache.store(data: original, for: remote, generation: epoch)
            let first = await pixabayCache.image(for: remote, request: target, priority: .visible)
            checks["onlineReadyPixelsAvailableSynchronously"] = first != nil && pixabayCache.readyImage(for: remote, request: target) === first
            let explicitURL = remote.appendingPathComponent("same-generation-new-data")
            let inputs = ThumbnailCache(namespace: "known-online-input-" + UUID().uuidString)
            func prepare(_ bytes: Data) async -> NSImage? {
                for await image in inputs.prepare(bytes, forKey: explicitURL.absoluteString, request: target) { return image }
                return nil
            }
            let explicitRed = await prepare(stillBytes(width: 160, height: 160))
            let blueBytes = stillBytes(width: 160, height: 160, color: .blue)
            let explicitBlue = await prepare(blueBytes)
            let readyBlue = inputs.cachedImage(forKey: explicitURL.absoluteString, request: target)
            func color(_ image: NSImage?) -> NSColor? {
                image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    .map { NSBitmapImageRep(cgImage: $0) }?.colorAt(x: 40, y: 40)?.usingColorSpace(.deviceRGB)
            }
            checks["onlineExplicitNewDataAtomicallyReplacesSameURLReadyPixels"] = explicitRed != nil && explicitBlue != nil
                && readyBlue === explicitBlue && (color(explicitRed)?.redComponent ?? 0) > 0.9
                && (color(readyBlue)?.blueComponent ?? 0) > 0.9 && (color(readyBlue)?.redComponent ?? 1) < 0.1
            let warmHook = ReuseCounter()
            var deniedWarm: NSImage?
            for await image in inputs.prepare(blueBytes,
                forKey: explicitURL.absoluteString, request: target, beforePublication: {
                    warmHook.increment("calls"); return false
                }) { deniedWarm = image }
            checks["knownInputWarmHitStillRunsSuccessfulSourceHookOnce"] = deniedWarm == nil && warmHook.count("calls") == 1
                && inputs.cachedImage(forKey: explicitURL.absoluteString, request: target) === readyBlue
            let stale = Task { await pixabayCache.image(for: remote.appendingPathComponent("late-online.gif"), request: target, priority: .visible) }
            let pending = root.appendingPathComponent("online-http-held")
            for _ in 0..<3000 {
                if FileManager.default.fileExists(atPath: pending.path) { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            checks["onlineClearHeldActualHTTPBeforeReply"] = FileManager.default.fileExists(atPath: pending.path)
            await pixabayCache.clearAll()
            try? Data().write(to: root.appendingPathComponent("online-http-release"))
            let late = await stale.value
            await pixabayCache.store(data: original, for: remote, generation: epoch)
            let raw = await pixabayCache.cachedData(for: remote)
            checks["onlineClearRejectsOldVisibleAndPrefetchPublication"] = late == nil && raw == nil
                && pixabayCache.readyImage(for: remote, request: target) == nil
            let next = await pixabayCache.publicationGeneration()
            await pixabayCache.store(data: original, for: remote, generation: next)
            let fresh = await pixabayCache.image(for: remote, request: target, priority: .visible)
            checks["onlineNewGenerationStillPublishesNormally"] = fresh != nil
            await pixabayCache.clearAll()
            pixabayChecksFinished = true
        }
        checks["onlineActorChecksCompleted"] = pump { pixabayChecksFinished }

        let counter = ReuseCounter()
        let cache = ThumbnailCache(namespace: "return-reuse-" + UUID().uuidString)
        func load() -> NSImage? {
            var result: NSImage?
            let finishesBeforeReturn = ReuseInputObservation.counter.count("finish:still-512")
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
            precondition(pump { result != nil && ReuseInputObservation.counter.count("finish:still-512") > finishesBeforeReturn })
            return result
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

        let biasedForward = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(40...51), itemCount: 100,
            neighborLimit: 12, direction: 1, forwardBias: 2)
        let biasedBackward = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(40...51), itemCount: 100,
            neighborLimit: 12, direction: -1, forwardBias: 2)
        checks["forwardBiasTwoPreparesEightLeadingAndFourTrailingItems"] = biasedForward == [52,53,39,54,55,38,56,57,37,58,59,36]
        checks["forwardBiasTwoReversesLeadingSideAndPriority"] = biasedBackward == [39,38,52,37,36,53,35,34,54,33,32,55]
        checks["forwardBiasTwoKeepsUnknownDirectionSymmetric"] = GridThumbnailPrefetchDemand.indices(
            visibleIndices: Array(40...51), itemCount: 100, neighborLimit: 12, direction: 0, forwardBias: 2)
            == [52,39,53,38,54,37,55,36,56,35,57,34]
        checks["forwardBiasTwoFillsLowerEdgeFromRemainingSide"] = GridThumbnailPrefetchDemand.indices(
            visibleIndices: [1,2], itemCount: 12, neighborLimit: 6, direction: -1, forwardBias: 2) == [0,3,4,5,6,7]
        checks["forwardBiasTwoFillsUpperEdgeFromRemainingSide"] = GridThumbnailPrefetchDemand.indices(
            visibleIndices: [9,10], itemCount: 12, neighborLimit: 6, direction: 1, forwardBias: 2) == [11,8,7,6,5,4]
        let biasedBounded = GridThumbnailPrefetchDemand.indices(visibleIndices: [3,4], itemCount: 8,
            neighborLimit: 96, direction: 1, forwardBias: 2)
        checks["forwardBiasTwoRemainsBoundedUniqueAndOutsideVisibleSpan"] = biasedBounded == [5,6,2,7,1,0]
            && Set(biasedBounded) == [0,1,2,5,6,7] && biasedBounded.count == 6

        let rapidForward = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(100...119), predictedIndices: Array(203...222),
            itemCount: 1_000, neighborLimit: 96, direction: 1, forwardBias: 2)
        checks["nativeForwardLandingFitsTheOriginalBudget"] = Set(203...222).isSubset(of: Set(rapidForward))
            && rapidForward.count == 96 && Set(rapidForward).count == 96 && Set(100...119).isDisjoint(with: rapidForward)
            && rapidForward.first == 120 && rapidForward.contains(99)
        let rapidReverse = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(400...419), predictedIndices: Array(297...316),
            itemCount: 1_000, neighborLimit: 96, direction: -1, forwardBias: 2)
        checks["nativeReverseLandingKeepsImmediateNeighbors"] = Set(297...316).isSubset(of: Set(rapidReverse))
            && rapidReverse.count == 96 && Set(rapidReverse).count == 96 && Set(400...419).isDisjoint(with: rapidReverse)
            && rapidReverse.first == 399 && rapidReverse.contains(420)
        let covered = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(40...51), predictedIndices: Array(45...58),
            itemCount: 100, neighborLimit: 12, direction: 1, forwardBias: 2)
        checks["alreadyCoveredNativePredictionKeepsTheOriginalOrder"] = covered == biasedForward
        let remoteLanding = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(100...119), predictedIndices: Array(203...222),
            itemCount: 1_000, neighborLimit: 18, direction: 1)
        checks["unfundedNativePredictionKeepsEveryOriginalNeighbor"] = remoteLanding == GridThumbnailPrefetchDemand.indices(
            visibleIndices: Array(100...119), itemCount: 1_000, neighborLimit: 18, direction: 1)
        let largeViewport = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(100...159), predictedIndices: Array(400...459),
            itemCount: 1_000, neighborLimit: 96, direction: 1, forwardBias: 2)
        checks["localFullViewportPairExceedingBudgetKeepsOriginalNeighbors"] = largeViewport == GridThumbnailPrefetchDemand.indices(
            visibleIndices: Array(100...159), itemCount: 1_000, neighborLimit: 96, direction: 1, forwardBias: 2)
        let edge = GridThumbnailPrefetchDemand.indices(visibleIndices: Array(950...969), predictedIndices: [-1] + Array(980...999) + [1_000],
            itemCount: 1_000, neighborLimit: 96, direction: 1, forwardBias: 2)
        checks["nativePredictionEntryClampsInvalidIndicesAndKeepsTheLastItems"] = Set(980...999).isSubset(of: Set(edge))
            && edge.allSatisfy { (0..<1_000).contains($0) } && Set(edge).count == edge.count

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

        do {
            let source = root.appendingPathComponent("steam-warm-task-row.jpg")
            try stillBytes(width: 1200, height: 1200).write(to: source)
            let shared = SteamWorkshopPreviewImageCache.shared
            var large: NSImage?
            steamWorkshopLoadPreviewImage(from: source, maxPixelSize: 800) { large = $0 }
            precondition(pump { large != nil })
            let beforeDecode = ReuseInputObservation.counter.count("steam-decode-256")
            var returned = false, synchronous = false, small: NSImage?
            steamWorkshopLoadPreviewImage(from: source, maxPixelSize: 256) { small = $0; synchronous = !returned }
            returned = true
            precondition(pump { small != nil })
            checks["steam-small-task-row-borrows-larger-ready-image-synchronously"] = synchronous && small === large
                && steamWorkshopCachedPreviewImage(for: source, maxPixelSize: 256) === large
                && ReuseInputObservation.counter.count("steam-decode-256") == beforeDecode
            let exact = steamWorkshopPreviewStillKey(for: source, maxPixelSize: 256)
            checks["steam-warm-borrow-does-not-add-a-smaller-physical-variant"] = shared.cachedImage(forKey: exact) == nil
            shared.remove(forKey: exact)
            let candidate = SteamWorkshopPreviewPrefetchController.Candidate(id: "warm-row", item: item("warm-row", source), record: nil)
            var loads = 0
            let prefetch = SteamWorkshopPreviewPrefetchController(load: { url, pixels, cancellation, completion in
                loads += 1
                steamWorkshopLoadPreviewImage(from: url, maxPixelSize: pixels, cancellation: cancellation, completion: completion)
            })
            prefetch.replace(with: [candidate], maxPixelSize: 256); settle(prefetch)
            precondition(pump { shared.cachedImage(forKey: exact) != nil || loads == 1 })
            prefetch.replace(with: [candidate], maxPixelSize: 256); settle(prefetch)
            checks["steam-preheat-recognizes-borrowed-ready-image-without-rebinding"] = loads == 1
            let cancellation = SteamWorkshopPreviewLoadCancellation(); cancellation.cancel()
            var cancelledDelivery = false
            steamWorkshopLoadPreviewImage(from: source, maxPixelSize: 256, cancellation: cancellation) { _ in cancelledDelivery = true }
            checks["steam-cancelled-warm-borrow-does-not-deliver"] = !cancelledDelivery
            prefetch.cancelAll(); steamWorkshopInvalidatePreview(source)
            checks["steam-invalidation-retires-all-compatible-ready-tiers"] = steamWorkshopCachedPreviewImage(for: source, maxPixelSize: 256) == nil
                && steamWorkshopCachedPreviewImage(for: source, maxPixelSize: 800) == nil
            var fresh: NSImage?
            steamWorkshopLoadPreviewImage(from: source, maxPixelSize: 256) { fresh = $0 }
            precondition(pump { fresh != nil })
            let beforeLarge = ReuseInputObservation.counter.count("steam-decode-800")
            var larger: NSImage?
            steamWorkshopLoadPreviewImage(from: source, maxPixelSize: 800) { larger = $0 }
            checks["steam-smaller-ready-image-cannot-satisfy-a-larger-request"] = pump { larger != nil }
                && larger !== fresh && larger?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width == 800
                && ReuseInputObservation.counter.count("steam-decode-800") == beforeLarge + 1
        }

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
        settle(prefetch)
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
        do {
            let targetCounter = ReuseCounter()
            let master = NSImage(data: stillBytes(width: 1600, height: 800))!
            func pixels(_ image: NSImage?) -> NSSize? {
                image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { NSSize(width: $0.width, height: $0.height) }
            }
            func square(_ side: Int) -> ThumbnailRequest { .init(width: side, height: side, mode: .fill) }
            func targetLoad(_ store: ThumbnailCache, _ key: String, _ request: ThumbnailRequest?, _ input: ThumbnailInput) -> NSImage? {
                var result: NSImage?, complete = false
                store.load(forKey: key, request: request, input: input, completion: {
                    targetCounter.increment("callback")
                    if !Thread.isMainThread { targetCounter.increment("off-main") }
                    result = $0; complete = true
                })
                if !pump(8, { complete }) { targetCounter.increment("timeout") }
                return result
            }
            let sized = ThumbnailCache(countLimit: 8, totalCostLimit: 16 * 1024 * 1024,
                namespace: "request-target-" + UUID().uuidString)
            let seedFinish = ReuseInputObservation.counter.count("finish:source")
            let small = targetLoad(sized, "source", square(128), .image(master))
            checks["firstSquareDiskSeedFinishesAfterOneImageCallback"] = pump {
                ReuseInputObservation.counter.count("finish:source") > seedFinish
            } && targetCounter.count("callback") == 1
            checks["squareTargetIsOwnedPixelsAndCannotSatisfyLargerOrUncropped"] = pixels(small) == NSSize(width: 128, height: 128)
                && sized.cachedImage(forKey: "source", request: square(128)) === small
                && sized.cachedImage(forKey: "source", request: square(320)) == nil && sized.cachedImage(forKey: "source") == nil
            var returned = false, synchronous = false
            var smaller: NSImage?
            let sourcesBeforeWarm = ReuseInputObservation.counter.count("input")
            sized.load(forKey: "source", request: square(64), input: .image(master)) {
                smaller = $0; synchronous = !returned && Thread.isMainThread
            }
            returned = true
            checks["largerWarmSquareSatisfiesSmallerWithoutReplacementOrSource"] = synchronous && smaller === small
                && ReuseInputObservation.counter.count("input") == sourcesBeforeWarm
            let callbacksBeforeLarge = targetCounter.count("callback")
            let large = targetLoad(sized, "source", square(320), .image(master))
            checks["largerTargetUsesUncroppedDiskWithOneFinalCallback"] = pixels(large) == NSSize(width: 320, height: 320)
                && ReuseInputObservation.counter.count("input") == sourcesBeforeWarm && targetCounter.count("callback") == callbacksBeforeLarge + 1
            checks["dominatedSquareSizeRetiresInsteadOfKeepingSizeHistory"] = large != nil && large !== small
                && sized.cachedImage(forKey: "source", request: square(128)) === large
                && sized.cachedImage(forKey: "source", request: square(320)) === large
            let fitRequest = ThumbnailRequest(width: 128, height: 128, mode: .fit)
            let fit = targetLoad(sized, "source", fitRequest, .image(master))
            checks["necessaryUncroppedAndSquareCompositionsCoexist"] = pixels(fit) == NSSize(width: 128, height: 64)
                && sized.cachedImage(forKey: "source", request: fitRequest) === fit
                && sized.cachedImage(forKey: "source", request: square(320)) === large
            let fullRequest = ThumbnailRequest(width: 1600, height: 800, mode: .fit)
            let uncropped = targetLoad(sized, "source", fullRequest, .image(master))
            checks["uncroppedReadyFrameServesGridWithoutRoleConflict"] = pixels(uncropped) == NSSize(width: 1600, height: 800)
                && sized.cachedImage(forKey: "source") === uncropped
                && sized.cachedImage(forKey: "source", request: square(320)) === uncropped
                && ReuseInputObservation.counter.count("input") == sourcesBeforeWarm
            sized.imageCache.removeAllObjects()
            _ = targetLoad(sized, "source", square(128), .image(master))
            let uncroppedAgain = targetLoad(sized, "source", fullRequest, .image(master))
            checks["smallerDiskDecodeNeverPersistsItsCroppedPixels"] = pixels(uncroppedAgain) == NSSize(width: 1600, height: 800)
                && ReuseInputObservation.counter.count("input") == sourcesBeforeWarm
            let nativeSmall = NSImage(data: stillBytes(width: 96, height: 64))!
            let native = targetLoad(sized, "native-small", square(320), .image(nativeSmall, nativeSize: CGSize(width: 96, height: 64)))
            let afterNative = ReuseInputObservation.counter.count("input")
            checks["nativeSmallSourceCompletesAtRealShortSideAndStaysWarm"] = pixels(native) == NSSize(width: 64, height: 64)
                && sized.cachedImage(forKey: "native-small", request: square(640)) === native
                && targetLoad(sized, "native-small", square(128), .image(master)) === native && ReuseInputObservation.counter.count("input") == afterNative
            let legacyFinish = ReuseInputObservation.counter.count("finish:legacy-small")
            _ = targetLoad(sized, "legacy-small", nil, .image(nativeSmall))
            checks["legacySmallDiskSeedFinishesBeforeMemoryEviction"] = pump {
                ReuseInputObservation.counter.count("finish:legacy-small") > legacyFinish
            }
            sized.imageCache.removeAllObjects()
            let beforeUpgrade = ReuseInputObservation.counter.count("input")
            let upgraded = targetLoad(sized, "legacy-small", square(320), .image(master))
            checks["oldSmallDiskDerivativeFallsBackToSourceOnce"] = pixels(upgraded) == NSSize(width: 320, height: 320)
                && ReuseInputObservation.counter.count("input") == beforeUpgrade + 1
            let prepared = root.appendingPathComponent("prepared-master.jpg")
            let preparedBytes = stillBytes(width: 800, height: 400)
            try preparedBytes.write(to: prepared)
            let preparedWrites = ReuseCounter()
            let preparedStore = ThumbnailCache(namespace: "prepared-" + UUID().uuidString, writeEncodedData: { data, url in
                preparedWrites.increment("write"); try data.write(to: url)
            })
            let preparedImage = targetLoad(preparedStore, "prepared", square(320), .preparedFile(prepared, nativeSize: nil))
            let preparedAfterLoad = try Data(contentsOf: prepared)
            checks["preparedJPEGDeliversPixelsWithoutEncodingOrCopying"] = pixels(preparedImage) == CGSize(width: 320, height: 320)
                && preparedWrites.count("write") == 0 && preparedAfterLoad == preparedBytes
            for operation in ["both", "cancel-small", "remove", "clear"] {
                let started = ReuseCounter(), release = DispatchSemaphore(value: 0)
                let store = ThumbnailCache(countLimit: 8, totalCostLimit: 16 * 1024 * 1024,
                    namespace: "request-flight-" + operation + UUID().uuidString, writeEncodedData: { data, url in
                        started.increment("write")
                        if release.wait(timeout: .now() + 5) != .success { started.increment("timeout") }
                        try data.write(to: url)
                    })
                let smallToken = ThumbnailCacheRequestCancellation(), largeToken = ThumbnailCacheRequestCancellation()
                var first: NSImage?, second: NSImage?, firstCalls = 0, secondCalls = 0
                let inputsBefore = ReuseInputObservation.counter.count("input")
                let finishesBefore = ReuseInputObservation.counter.count("finish:same-source")
                store.load(forKey: "same-source", request: square(128), cancellation: smallToken,
                    input: .image(master), completion: { first = $0; firstCalls += 1 })
                let firstHeld = pump { started.count("write") == 1 }
                let firstEarly = pump(0.25) { firstCalls == 1 }
                store.load(forKey: "same-source", request: square(320), cancellation: largeToken,
                    input: .image(master), completion: { second = $0; secondCalls += 1 })
                let bothHeld = pump { started.count("write") == 2 }
                let secondEarly = pump(0.25) { secondCalls == 1 }
                checks["different-target-\(operation)-publishes-each-shape-once-before-derived-writes-finish"] = firstHeld && bothHeld && firstEarly && secondEarly
                    && firstCalls == 1 && secondCalls == 1 && pixels(first) == NSSize(width: 128, height: 128)
                    && pixels(second) == NSSize(width: 320, height: 320)
                checks["different-target-\(operation)-prepares-two-inputs-while-master-disk-is-pending"] =
                    ReuseInputObservation.counter.count("input") == inputsBefore + 2
                if operation == "cancel-small", firstCalls == 1 { smallToken.cancel() }
                if operation == "remove" { store.remove(forKey: "same-source") }
                if operation == "clear" { store.clearAll() }
                release.signal(); release.signal()
                let finished = pump {
                    firstCalls == 1 && secondCalls == 1 && ReuseInputObservation.counter.count("finish:same-source") == finishesBefore + 2
                }
                // The older comparison reaches Ready only after releasing its writer.
                if operation == "cancel-small", !smallToken.cancelled { smallToken.cancel() }
                checks["different-target-\(operation)-keeps-each-consumer-shape-and-cancellation"] = firstHeld && bothHeld && finished
                    && started.count("timeout") == 0 && secondCalls == 1 && pixels(second) == NSSize(width: 320, height: 320)
                    && firstCalls == 1 && pixels(first) == NSSize(width: 128, height: 128)
                if operation == "remove" || operation == "clear" {
                    checks["different-target-\(operation)-revokes-all-target-cache-writes"] = store.cachedImage(forKey: "same-source", request: square(128)) == nil
                        && store.cachedImage(forKey: "same-source", request: square(320)) == nil && store.cachedImage(forKey: "same-source") == nil
                } else {
                    checks["different-target-\(operation)-leaves-one-current-square"] = second != nil
                        && store.cachedImage(forKey: "same-source", request: square(128)) === second
                        && store.cachedImage(forKey: "same-source", request: square(320)) === second && store.cachedImage(forKey: "same-source") == nil
                }
            }
            let decoded = GridThumbnailDecoder.Image(master, nativeSize: CGSize(width: 1600, height: 800))!
            let crops = [square(100), ThumbnailRequest(width: 120, height: 80, mode: .fill), ThumbnailRequest(width: 80, height: 120, mode: .fill)]
            let frames = crops.map { GridThumbnailDecoder.render(decoded, request: $0)! }
            let cost = frames.reduce(0) { $0 + $1.cost }
            let variants = DecodedThumbnailMemoryCache(countLimit: 8, totalCostLimit: cost)
            for frame in frames {
                variants.setObject(frame.image, forKey: "variants", cost: frame.cost, pixels: frame.pixels,
                    nativeSize: frame.nativeSize, crop: frame.crop, preservingCompatibleResults: true)
            }
            checks["thirdNecessaryCompositionSharesTheSameLRU"] = zip(crops, frames).allSatisfy {
                variants.object(forKey: "variants", request: $0.0) === $0.1.image
            }
            checks["membershipPeekFindsCurrentVariant"] = variants.containsObject(forKey: "variants", request: crops[0])
            let added = GridThumbnailDecoder.render(decoded, request: square(32))!
            variants.setObject(added.image, forKey: "another-source", cost: added.cost, pixels: added.pixels,
                nativeSize: added.nativeSize, crop: added.crop, preservingCompatibleResults: true)
            checks["allVariantsShareByteBudgetAndPeekDoesNotPromote"] = variants.object(forKey: "variants", request: crops[0]) == nil
                && variants.object(forKey: "variants", request: crops[1]) === frames[1].image
                && variants.object(forKey: "variants", request: crops[2]) === frames[2].image
            variants.setObject(master, forKey: "variants", cost: cost + 1, preservingCompatibleResults: true)
            checks["oversizeCannotDeleteValidSameSourceVariants"] = variants.object(forKey: "variants", request: crops[1]) === frames[1].image
                && variants.object(forKey: "variants", request: crops[2]) === frames[2].image
            variants.removeObject(forKey: "variants")
            checks["singleSourceRemoveClearsEveryComposition"] = crops.allSatisfy { variants.object(forKey: "variants", request: $0) == nil }
            let largeFit = GridThumbnailDecoder.render(decoded, request: .init(width: 640, height: 640, mode: .fit))!
            let smallFit = GridThumbnailDecoder.render(decoded, request: fitRequest)!
            let fitStore = DecodedThumbnailMemoryCache(countLimit: 8, totalCostLimit: 4 * 1024 * 1024)
            for frame in [largeFit, smallFit] {
                fitStore.setObject(frame.image, forKey: "late-fit", cost: frame.cost, pixels: frame.pixels,
                    nativeSize: frame.nativeSize, crop: frame.crop, preservingCompatibleResults: true)
            }
            checks["lateSmallFitCannotReplaceLargerReadyFit"] = fitStore.object(forKey: "late-fit", request: .init(width: 600, height: 300, mode: .fit)) === largeFit.image
                && fitStore.object(forKey: "late-fit", request: fitRequest) === largeFit.image
            fitStore.setObject(nativeSmall, forKey: "proof", cost: 96 * 64 * 4)
            checks["unknownPixelsDoNotInventNativeLimit"] = fitStore.object(forKey: "proof", request: square(320)) == nil
            fitStore.setObject(nativeSmall, forKey: "proof", cost: 96 * 64 * 4, nativeSize: CGSize(width: 96, height: 64), preservingCompatibleResults: true)
            checks["samePixelsCanGainRealNativeProof"] = fitStore.object(forKey: "proof", request: square(320)) === nativeSmall
            fitStore.removeAllObjects()
            checks["pressureReleasePathClearsEveryVariant"] = fitStore.object(forKey: "proof") == nil && fitStore.object(forKey: "late-fit") == nil
            checks["squareTargetCallbacksStayOnMainWithoutTimeout"] = targetCounter.count("off-main") == 0 && targetCounter.count("timeout") == 0
        }
        do {
            let source = root.appendingPathComponent("task-row-still.jpg")
            try stillBytes(width: 1200, height: 800).write(to: source)
            let store = ThumbnailCache(namespace: "task-row-fit-" + UUID().uuidString)
            let targets: [(String, ThumbnailRequest?)] = [("still-legacy", nil), ("still-row", .init(width: 96, height: 96, mode: .fit))]
            for (name, request) in targets {
                var image: NSImage?
                store.load(forKey: name, request: request, input: .sourceFile(source)) { image = $0 }
                let complete = pump { image != nil }
                let pixels = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                checks["\(name)-real-source-file-load-completes"] = complete && pixels != nil
                if let pixels {
                    taskRowPixels[name] = ["width": pixels.width, "height": pixels.height,
                        "bytes": pixels.bytesPerRow * pixels.height]
                }
            }
            checks["task-row-fit-keeps-whole-frame-with-smaller-delivery"] = taskRowPixels["still-row"]?["width"] == 96
                && taskRowPixels["still-row"]?["height"] == 64
                && taskRowPixels["still-row"]!["bytes"]! < taskRowPixels["still-legacy"]!["bytes"]!
            let beforeWarm = ReuseInputObservation.counter.count("input")
            var warm: NSImage?, synchronous = false, returned = false
            store.load(forKey: "still-row", request: .init(width: 48, height: 48, mode: .fit), input: .sourceFile(source)) {
                warm = $0; synchronous = !returned
            }
            returned = true
            checks["task-row-fit-warm-return-borrows-compatible-pixels-without-source-work"] = warm != nil && synchronous
                && ReuseInputObservation.counter.count("input") == beforeWarm
            if let pixels = warm?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                taskRowPixels["still-row-warm"] = ["width": pixels.width, "height": pixels.height,
                    "bytes": pixels.bytesPerRow * pixels.height]
            }
            store.clearAll(cancelInFlight: true)
        }
        var retention: [String: [String: Int]] = [:]
        do {
            var didClear = false
            SteamWorkshopPreviewImageCache.shared.clearAll(cancelInFlight: true) { DispatchQueue.main.async { didClear = true } }
            precondition(pump { didClear })
            let sourceURLs = try (0..<96).map { index -> URL in
                let url = root.appendingPathComponent("prefetch-retention-\(index).jpg")
                let color = NSColor(calibratedHue: CGFloat(index) / 96, saturation: 0.7, brightness: 0.8, alpha: 1)
                try autoreleasepool { try stillBytes(width: 800, height: 800, color: color).write(to: url) }
                return url
            }
            var demands = sourceURLs.enumerated().map { index, url in
                makeAdapterSteamPrefetch(record(item("retention-\(index)", url), preview: url), pixels: 800)
            }
            precondition(pump { AdapterPrefetchRetentionProbe.entries.count == 96 })
            let displayed = SteamWorkshopPreviewState()
            displayed.configure(previewURL: sourceURLs.last!, fallbackVideoURL: nil, maxPixelSize: 800)
            precondition(pump { displayed.image != nil })
            retention["ready-with-cache-and-live-view"] = AdapterPrefetchRetentionProbe.live
            didClear = false
            SteamWorkshopPreviewImageCache.shared.clearAll(cancelInFlight: true) { DispatchQueue.main.async { didClear = true } }
            precondition(pump { didClear })
            checks["completed-nondisplaying-prefetch-does-not-pin-evicted-pixels"] = pump { AdapterPrefetchRetentionProbe.live["images"] == 1 }
            retention["cache-cleared-live-view-held"] = AdapterPrefetchRetentionProbe.live
            checks["cache-clear-keeps-the-actual-displayed-image"] = displayed.image != nil
            checks["completed-steam-preheat-keeps-best-effort-interest-without-refill-loop"] = demands.allSatisfy { $0.isWarm() }
            demands.forEach { $0.cancel() }; demands.removeAll(); displayed.reset()
            checks["releasing-all-actual-consumers-releases-observed-pixels"] = pump { AdapterPrefetchRetentionProbe.live["images"] == 0 }
            retention["all-consumers-released"] = AdapterPrefetchRetentionProbe.live
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks, "retention": retention, "taskRowPixels": taskRowPixels, "counts": [
            "network": counter.count("network"), "originalDecodes": counter.count("original-decode"),
            "stillDecodes": counter.count("still-decode")]], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
