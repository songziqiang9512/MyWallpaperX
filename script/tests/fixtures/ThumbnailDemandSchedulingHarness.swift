import AppKit
import ImageIO

@MainActor func demandImage(_ width: Int, color: NSColor = .systemRed) -> NSImage {
    let context = CGContext(data: nil, width: width, height: 30, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: 30))
    return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: 30))
}

nonisolated final class DemandEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func record(_ name: String) { lock.lock(); entries.append(name); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return entries }
}

nonisolated final class DemandBlockingGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var hasStarted = false
    private var hasFinished = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return hasStarted }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return hasFinished }
    func wait() {
        lock.lock(); hasStarted = true; lock.unlock()
        _ = semaphore.wait(timeout: .now() + 8)
        lock.lock(); hasFinished = true; lock.unlock()
    }
    func release() { semaphore.signal() }
}

// Only the copied source's final recursive filesystem leaf is observed/held.
// Cache invalidation, detachment, locking and queue scheduling stay production.
nonisolated enum ThumbnailClearObservation {
    static let gate = DemandBlockingGate(), events = DemandEvents()
    static func remove(_ directory: URL) {
        if directory.lastPathComponent.hasPrefix("asynchronous-clear-") {
            events.record(Thread.isMainThread ? "delete-main" : "delete-background")
            gate.wait()
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

nonisolated enum ThumbnailEncodingObservation {
    static let encodings = DemandEvents(), finishes = DemandEvents()
    static func count(_ format: String) -> Int { encodings.values.filter { $0 == format }.count }
    static func finished(_ key: String) -> Int { finishes.values.filter { $0 == key }.count }
}

// Hold real staged files by encoded image width; source admission stays production.
nonisolated private final class DemandStagingObservation: @unchecked Sendable {
    let events = DemandEvents()
    let gates: [Int: DemandBlockingGate]
    init(widths: [Int]) { gates = Dictionary(uniqueKeysWithValues: widths.map { ($0, DemandBlockingGate()) }) }
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        let width = NSBitmapImageRep(data: data)!.pixelsWide
        events.record(String(width))
        gates[width]?.wait()
    }
    func releaseAll() { gates.values.forEach { $0.release() } }
}

nonisolated final class DemandImageGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSImage?, Never>?
    private var stopped = false
    private var isWaiting = false
    var waiting: Bool { lock.lock(); defer { lock.unlock() }; return isWaiting }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func image() async -> NSImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                isWaiting = true
                if stopped { lock.unlock(); continuation.resume(returning: nil) }
                else { self.continuation = continuation; lock.unlock() }
            }
        } onCancel: { self.cancel() }
    }
    private func cancel() {
        lock.lock(); stopped = true
        let pending = continuation; continuation = nil
        lock.unlock(); pending?.resume(returning: nil)
    }
    func resume(_ image: NSImage?) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(returning: image)
    }
}

nonisolated final class DemandDataGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { lock.lock(); defer { lock.unlock() }; return continuation != nil }
    func wait() async { await withCheckedContinuation { lock.lock(); continuation = $0; lock.unlock() } }
    func release() { lock.lock(); let pending = continuation; continuation = nil; lock.unlock(); pending?.resume() }
}

@main struct ThumbnailDemandSchedulingHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func makeImage(_ width: Int) -> NSImage {
            demandImage(width)
        }
        let image = makeImage(40)
        let bytes = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            .representation(using: .png, properties: [:])!
        func sourceInput(_ width: Int) throws -> ThumbnailInput {
            let source = makeImage(width)
            let data = NSBitmapImageRep(cgImage: source.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                .representation(using: .png, properties: [:])!
            let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("known-source-\(width).png", isDirectory: false)
            try data.write(to: url)
            return .sourceFile(url)
        }
        func pump(_ seconds: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
            let until = Date().addingTimeInterval(seconds)
            while !condition(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            return condition()
        }
        var checks: [String: Bool] = [:]
        var metrics: [String: Double] = [:]
        let cache = ThumbnailCache(namespace: "demand-" + UUID().uuidString)
        var warm: NSImage?
        let initialWarmFinishes = ThumbnailEncodingObservation.finished("warm")
        cache.load(forKey: "warm", input: .image(image)) { warm = $0 }
        checks["warmImageSeeded"] = pump { warm != nil && ThumbnailEncodingObservation.finished("warm") > initialWarmFinishes }
        cache.imageCache.removeAllObjects(); warm = nil
        let heavy = DemandImageGate()
        var heavyFinished = false
        cache.loadImageAsync(forKey: "slow-generator", loader: { (await heavy.image()).map { .image($0) } }) { heavyFinished = $0 != nil }
        checks["slowGeneratorStarted"] = pump { heavy.waiting }
        let started = Date()
        cache.load(forKey: "warm", input: .sourceData(Data())) { warm = $0 }
        let warmBeforeRelease = pump(0.25) { warm != nil }
        metrics["warmReadBeforeGeneratorRelease"] = warmBeforeRelease ? 1 : 0
        metrics["warmReadObservationMilliseconds"] = Date().timeIntervalSince(started) * 1000
        heavy.resume(image)
        checks["slowAndWarmFinishAfterRelease"] = pump { heavyFinished && warm != nil }
        checks["warmDiskReadDoesNotWaitForBlockedGenerator"] = warmBeforeRelease

        let coldStages = DemandStagingObservation(widths: Array(41...45))
        let cold = ThumbnailCache(namespace: "known-source-cap-" + UUID().uuidString,
            writeEncodedData: { try coldStages.write($0, to: $1) })
        var coldFinished = 0, diskReturn: NSImage?
        let coldWarmFinishes = ThumbnailEncodingObservation.finished("warm")
        cold.load(forKey: "warm", input: .image(image)) { diskReturn = $0 }
        checks["knownSourceWarmDiskSeeded"] = pump { diskReturn != nil && ThumbnailEncodingObservation.finished("warm") > coldWarmFinishes }
        cold.imageCache.removeAllObjects(); diskReturn = nil
        for index in 0..<4 {
            cold.load(forKey: "cold-\(index)", input: try sourceInput(41 + index)) { _ in coldFinished += 1 }
        }
        checks["fourKnownColdInputsOccupySourceSlots"] = pump(0.5) { (41...44).allSatisfy { coldStages.gates[$0]!.started } }
        cold.load(forKey: "cold-fifth", input: try sourceInput(45)) { _ in coldFinished += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["heldDerivedWritesDeliverFourImagesButFifthKnownInputStillWaits"] = pump(0.3) { coldFinished == 4 }
            && !coldStages.gates[45]!.started
        cold.load(forKey: "warm", input: .sourceData(Data())) { diskReturn = $0 }
        checks["warmDiskReturnsWhileKnownColdSourcesRemainHeld"] = pump(0.25) { diskReturn != nil }
            && coldFinished == 4 && diskReturn?.size.width == 40
        coldStages.gates[41]!.release()
        checks["oneKnownSourceReleaseAdmitsTheFifthInput"] = pump(0.5) { coldStages.gates[45]!.started }
            && !(42...44).contains { coldStages.gates[$0]!.finished }
        coldStages.releaseAll()
        checks["allKnownColdInputsDrainAfterRelease"] = pump { coldFinished == 5 }
        cold.clearAll()

        let priorityStages = DemandStagingObservation(widths: Array(51...56))
        let priorityCache = ThumbnailCache(namespace: "known-source-priority-" + UUID().uuidString,
            writeEncodedData: { try priorityStages.write($0, to: $1) })
        var blockersFinished = 0
        for index in 0..<2 {
            priorityCache.load(forKey: "priority-blocker-\(index)", priority: .prefetch,
                input: try sourceInput(51 + index)) { _ in blockersFinished += 1 }
        }
        checks["twoKnownPrefetchInputsCanOccupyBackgroundSlots"] = pump(0.5) { (51...52).allSatisfy { priorityStages.gates[$0]!.started } }
        let dropped = ThumbnailCacheRequestCancellation()
        priorityCache.load(forKey: "cancel-queued", priority: .prefetch, cancellation: dropped,
            input: try sourceInput(57)) { _ in priorityStages.events.record("cancelled-callback") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["thirdKnownPrefetchCannotUseReservedVisibleCapacity"] = !priorityStages.events.values.contains("57")
        for index in 2..<4 {
            priorityCache.load(forKey: "priority-blocker-\(index)", input: try sourceInput(51 + index)) { _ in blockersFinished += 1 }
        }
        checks["knownPrioritySourcesHoldAllFourSlots"] = pump(0.5) { (51...54).allSatisfy { priorityStages.gates[$0]!.started } }
        let low = ThumbnailCacheRequestCancellation(), promoted = ThumbnailCacheRequestCancellation()
        var promotedImage: NSImage?, survivorDelivered = false, olderFinished = false
        priorityCache.load(forKey: "older-prefetch", priority: .prefetch, cancellation: low,
            input: try sourceInput(55)) { _ in olderFinished = true }
        priorityCache.load(forKey: "promoted-prefetch", priority: .prefetch, cancellation: promoted,
            input: try sourceInput(56)) { _ in }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let visible = ThumbnailCacheRequestCancellation()
        priorityCache.load(forKey: "promoted-prefetch", priority: .visible, cancellation: visible,
            input: .image(makeImage(58))) { promotedImage = $0 }
        dropped.cancel(); promoted.cancel()
        priorityStages.gates[51]!.release()
        checks["visibleKnownJoinUsesTheFirstReleasedSourceSlot"] = pump(0.5) { priorityStages.gates[56]!.started }
        priorityStages.releaseAll()
        checks["remainingConsumerReceivesPromotedResult"] = pump { promotedImage != nil && olderFinished && blockersFinished == 4 }
        checks["lastCancelledQueuedConsumerNeverStagesOrCallsBack"] = !priorityStages.events.values.contains("57")
            && !priorityStages.events.values.contains("cancelled-callback") && priorityCache.cachedImage(forKey: "cancel-queued") == nil
        checks["visibleJoinPromotesPendingPrefetchAheadOfOlderPrefetch"] = priorityStages.events.values.filter { $0 == "55" || $0 == "56" }.first == "56"
        checks["sameKeyUsesOnlyTheFirstKnownInput"] = promotedImage?.size.width == 56
            && priorityStages.events.values.filter { $0 == "56" }.count == 1 && !priorityStages.events.values.contains("58")
        priorityCache.load(forKey: "cancel-queued", input: .image(image)) { survivorDelivered = $0 != nil }
        checks["cancellationDoesNotPoisonFailureCache"] = pump { survivorDelivered }
        low.cancel(); visible.cancel(); priorityCache.clearAll()

        let sharedGate = DemandImageGate()
        let first = ThumbnailCacheRequestCancellation(), second = ThumbnailCacheRequestCancellation()
        var firstFinished = false, secondFinished = false
        cache.loadImageAsync(forKey: "shared-unknown", cancellation: first,
            loader: { (await sharedGate.image()).map { .image($0) } }) { firstFinished = $0 != nil }
        checks["sharedUnknownProducerStarted"] = pump { sharedGate.waiting }
        cache.load(forKey: "shared-unknown", cancellation: second, input: .image(makeImage(60))) { secondFinished = $0 === image }
        let sharedJPEGCount = ThumbnailEncodingObservation.count("jpeg")
        first.cancel(); sharedGate.resume(image)
        checks["cancelOnePreservesOtherConsumer"] = pump { secondFinished && ThumbnailEncodingObservation.finished("shared-unknown") > 0 } && !firstFinished
        checks["remainingConsumerStillEncodesJPEG"] = ThumbnailEncodingObservation.count("jpeg") == sharedJPEGCount + 1
        let lateGate = DemandImageGate(), lateToken = ThumbnailCacheRequestCancellation()
        var lateDelivered = false
        cache.loadImageAsync(forKey: "late-unknown", cancellation: lateToken,
            loader: { (await lateGate.image()).map { .image($0) } }) { _ in lateDelivered = true }
        checks["lateUnknownProducerStarted"] = pump { lateGate.waiting }
        let lateJPEGCount = ThumbnailEncodingObservation.count("jpeg")
        lateToken.cancel()
        checks["lateUnknownProducerCancelled"] = pump { lateGate.cancelled }
        checks["cancelledRunningGeneratorSkipsJPEGEncoding"] = ThumbnailEncodingObservation.count("jpeg") == lateJPEGCount
        checks["cancelledRunningGeneratorCannotPublish"] = !lateDelivered && cache.cachedImage(forKey: "late-unknown") == nil
        var replacement: NSImage?
        cache.load(forKey: "late-unknown", input: .image(image)) { replacement = $0 }
        checks["sameKeyAfterCancelledProducerCanStartFresh"] = pump { replacement != nil }

        let pinnedGate = DemandImageGate(), pinnedToken = ThumbnailCacheRequestCancellation()
        var pinnedImage: NSImage?
        cache.loadImageAsync(forKey: "pinned-unknown", cancellation: pinnedToken,
            loader: { (await pinnedGate.image()).map { .image($0) } }) { _ in }
        checks["pinnedUnknownProducerStarted"] = pump { pinnedGate.waiting }
        cache.load(forKey: "pinned-unknown", input: .image(makeImage(60))) { pinnedImage = $0 }
        let pinnedJPEGCount = ThumbnailEncodingObservation.count("jpeg")
        pinnedToken.cancel(); pinnedGate.resume(image)
        checks["uncancellableLoadPinsOriginalProducer"] = pump { pinnedImage != nil && ThumbnailEncodingObservation.finished("pinned-unknown") > 0 } && pinnedImage === image
        checks["pinnedConsumerStillEncodesJPEG"] = ThumbnailEncodingObservation.count("jpeg") == pinnedJPEGCount + 1

        for mode in ["cancelled", "peer", "pinned"] {
            let key = "png-decoder-" + mode
            let gate = DemandBlockingGate(), token = ThumbnailCacheRequestCancellation()
            var originalDelivered = false, survivorImage: NSImage?
            cache.loadImageDataAsync(forKey: key, sourceDataKey: key + "-source", loader: { bytes },
                decoder: { data in gate.wait(); return NSImage(data: data) }, cancellation: token) { _ in originalDelivered = true }
            checks[key + "Started"] = pump { gate.started }
            let pngCount = ThumbnailEncodingObservation.count("png")
            if mode == "peer" {
                cache.loadImageDataAsync(forKey: key, loader: { nil }, cancellation: ThumbnailCacheRequestCancellation()) {
                    survivorImage = $0
                }
            } else if mode == "pinned" {
                cache.loadImageDataAsync(forKey: key, loader: { nil }) { survivorImage = $0 }
            }
            token.cancel(); gate.release()
            checks[key + "Finished"] = pump {
                ThumbnailEncodingObservation.finishes.values.contains(key) && (mode == "cancelled" || survivorImage != nil)
            }
            checks[key + "EncodingAndPublication"] = !originalDelivered && (mode == "cancelled"
                ? ThumbnailEncodingObservation.count("png") == pngCount && cache.cachedImage(forKey: key) == nil
                : ThumbnailEncodingObservation.count("png") == pngCount + 1 && cache.cachedImage(forKey: key) != nil)
        }

        let originalBytes = bytes + Data("original-encoded-suffix".utf8)
        let originalJPEGCount = ThumbnailEncodingObservation.count("jpeg")
        var originalImage: NSImage?, originalDisk: Data?, originalDiskFinished = false
        cache.loadImageDataAsync(forKey: "original-encoded", loader: { originalBytes }) { originalImage = $0 }
        checks["asyncImageDataRetainsOriginalEncoding"] = pump { originalImage != nil }
            && ThumbnailEncodingObservation.count("jpeg") == originalJPEGCount
        cache.loadRawDataAsync(forKey: "original-encoded", loader: { nil }) { originalDisk = $0; originalDiskFinished = true }
        checks["asyncImageDataPreservesOriginalDiskBytes"] = pump { originalDiskFinished } && originalDisk == originalBytes

        for clear in [false, true] {
            let gate = DemandImageGate()
            let writes = DemandEvents()
            let isolated = ThumbnailCache(namespace: "sync-clear-" + UUID().uuidString, writeEncodedData: { data, url in
                writes.record("write"); try data.write(to: url)
            })
            var delivered = false
            var originalCallbacks = 0, joinedCallbacks = 0
            isolated.loadImageAsync(forKey: "invalidated", loader: { (await gate.image()).map { .image($0) } }) {
                delivered = $0 != nil; originalCallbacks += 1
            }
            let label = clear ? "clear" : "remove"
            checks[label + "UnknownProducerStarted"] = pump { gate.waiting }
            if clear { isolated.clearAll() } else { isolated.remove(forKey: "invalidated") }
            var joined: NSImage?
            isolated.load(forKey: "invalidated", input: .image(makeImage(60))) {
                joined = $0; joinedCallbacks += 1
            }
            let jpegCount = ThumbnailEncodingObservation.count("jpeg")
            gate.resume(image)
            checks[label + "PreservesExistingConsumer"] = pump { delivered }
            checks[label + "InvalidatedConsumerSkipsOptionalJPEGEncoding"] = ThumbnailEncodingObservation.count("jpeg") == jpegCount
            checks[label + "InvalidatedConsumerSkipsStagedWrites"] = writes.values.isEmpty
            checks[label + "JoinAfterInvalidationStillReceivesOneCurrentResult"] = pump { joined != nil }
                && originalCallbacks == 1 && joinedCallbacks == 1 && joined === image
            checks[label + "ResultDoesNotRepopulateMemory"] = isolated.cachedImage(forKey: "invalidated") == nil
            var readFinished = false, disk: Data?
            isolated.loadRawDataAsync(forKey: "invalidated", loader: { nil }) { disk = $0; readFinished = true }
            checks[label + "ResultDoesNotRepopulateDisk"] = pump { readFinished } && disk == nil
            var fresh: NSImage?
            isolated.load(forKey: "invalidated", input: .image(image)) { fresh = $0 }
            checks[label + "CompletedInvalidatedRequestAllowsFreshCachedRequest"] = pump { fresh != nil }
                && isolated.cachedImage(forKey: "invalidated") != nil
            isolated.clearAll()
        }
        for clear in [false, true] {
            let gate = DemandDataGate(), writes = DemandEvents()
            let rawCache = ThumbnailCache(namespace: "raw-invalidated-" + UUID().uuidString, writeEncodedData: { data, url in
                writes.record("write"); try data.write(to: url)
            })
            let label = clear ? "clearRaw" : "removeRaw"
            var original: Data?, joined: Data?, originalCallbacks = 0, joinedCallbacks = 0
            rawCache.loadRawDataAsync(forKey: "raw", loader: { await gate.wait(); return bytes }) {
                original = $0; originalCallbacks += 1
            }
            checks[label + "SourceHeldBeforeInvalidation"] = pump { gate.waiting }
            if clear { rawCache.clearAll() } else { rawCache.remove(forKey: "raw") }
            rawCache.loadRawDataAsync(forKey: "raw", loader: { preconditionFailure("invalidated live raw request must still coalesce") }) {
                joined = $0; joinedCallbacks += 1
            }
            gate.release()
            checks[label + "ExistingAndJoinedConsumersReceiveOriginalBytesOnce"] = pump { original != nil && joined != nil }
                && original == bytes && joined == bytes && originalCallbacks == 1 && joinedCallbacks == 1
            checks[label + "SkipsStagedWrite"] = writes.values.isEmpty
            var finished = false, persisted: Data?
            rawCache.loadRawDataAsync(forKey: "raw", loader: { nil }) { persisted = $0; finished = true }
            checks[label + "DoesNotRepopulateDisk"] = pump { finished } && persisted == nil
            rawCache.clearAll()
        }
        let derivedGate = DemandBlockingGate(), derivedWrites = DemandEvents()
        let derived = ThumbnailCache(namespace: "derived-invalidated-" + UUID().uuidString, writeEncodedData: { data, url in
            derivedWrites.record("write"); try data.write(to: url)
        })
        var derivedImage: NSImage?, derivedJoin: NSImage?, derivedCallbacks = 0, derivedJoinCallbacks = 0
        derived.loadImageDataAsync(forKey: "still", sourceDataKey: "original", loader: { bytes }, decoder: {
            derivedGate.wait(); return NSImage(data: $0)
        }) { derivedImage = $0; derivedCallbacks += 1 }
        checks["derivedDecoderHeldBeforeSourceKeyInvalidation"] = pump { derivedGate.started }
        derived.remove(forKey: "original")
        derived.loadImageDataAsync(forKey: "still", sourceDataKey: "original",
            loader: { preconditionFailure("source-key invalidation must not create a second producer") }) {
            derivedJoin = $0; derivedJoinCallbacks += 1
        }
        let invalidatedPNGCount = ThumbnailEncodingObservation.count("png")
        derivedGate.release()
        checks["sourceKeyInvalidationPreservesExistingAndJoinedConsumers"] = pump { derivedImage != nil && derivedJoin != nil }
            && derivedCallbacks == 1 && derivedJoinCallbacks == 1 && derivedImage === derivedJoin
        checks["sourceKeyInvalidationSkipsOptionalPNGEncoding"] = ThumbnailEncodingObservation.count("png") == invalidatedPNGCount
        checks["sourceKeyInvalidationSkipsStillAndRawStagedWrites"] = derivedWrites.values.isEmpty
        checks["sourceKeyInvalidationDoesNotRepopulateDerivedMemory"] = derived.cachedImage(forKey: "still") == nil
        var derivedReads = 0, derivedFiles: [Data] = []
        for key in ["still", "original"] {
            derived.loadRawDataAsync(forKey: key, loader: { nil }) {
                if let data = $0 { derivedFiles.append(data) }
                derivedReads += 1
            }
        }
        checks["sourceKeyInvalidationDoesNotRepopulateEitherDiskKey"] = pump { derivedReads == 2 } && derivedFiles.isEmpty
        derived.clearAll()
        for clear in [false, true] {
            let stageGate = DemandBlockingGate(), writes = DemandEvents()
            let late = ThumbnailCache(namespace: "late-invalidation-" + UUID().uuidString, writeEncodedData: { data, url in
                stageGate.wait(); try data.write(to: url); writes.record("write")
            })
            let label = clear ? "clearAfterEncoding" : "removeAfterEncoding"
            var delivered: NSImage?, callbacks = 0
            let jpegCount = ThumbnailEncodingObservation.count("jpeg")
            late.load(forKey: "encoded", input: .image(image)) { delivered = $0; callbacks += 1 }
            checks[label + "HasAlreadyEncodedBeforeInvalidation"] = pump { stageGate.started }
                && ThumbnailEncodingObservation.count("jpeg") == jpegCount + 1
            checks[label + "ImageIsPublishedBeforeBlockedDerivedWrite"] = pump(0.3) { callbacks == 1 }
            if clear { late.clearAll() } else { late.remove(forKey: "encoded") }
            stageGate.release()
            checks[label + "StillDeliversOriginalConsumerExactlyOnce"] = pump { delivered != nil && stageGate.finished && writes.values == ["write"] }
                && callbacks == 1 && delivered === image && writes.values == ["write"]
            checks[label + "InvalidationClearsAlreadyPublishedMemory"] = late.cachedImage(forKey: "encoded") == nil
            var finished = false, persisted: Data?
            late.loadRawDataAsync(forKey: "encoded", loader: { nil }) { persisted = $0; finished = true }
            checks[label + "FinalPermissionCheckStillBlocksDiskPublication"] = pump { finished } && persisted == nil
            late.clearAll()
        }
        let negative = ThumbnailCache(namespace: "failure-" + UUID().uuidString, usesFailureCache: true)
        let deleteGate = ThumbnailClearObservation.gate, deletionEvents = ThumbnailClearObservation.events
        let asynchronousClear = ThumbnailCache(namespace: "asynchronous-clear-" + UUID().uuidString)
        var beforeClear: NSImage?
        asynchronousClear.load(forKey: "before-clear", input: .image(image)) { beforeClear = $0 }
        checks["asynchronousClearSeededRealDiskAndMemory"] = pump { beforeClear != nil && ThumbnailEncodingObservation.finished("before-clear") > 0 }
        asynchronousClear.clearAll {
            deletionEvents.record(Thread.isMainThread ? "clear-completed-main" : "clear-completed-background")
        }
        checks["recursiveDeletionStartsOnlyOnExistingMaintenanceQueue"] = pump { deleteGate.started }
            && deletionEvents.values == ["delete-background"]
        DispatchQueue.main.async { deletionEvents.record("main-remains-responsive") }
        checks["mainRunloopRemainsUsableDuringBlockedRecursiveDeletion"] = pump(0.2) {
            deletionEvents.values.contains("main-remains-responsive")
        }
        var duringClear: NSImage?
        asynchronousClear.load(forKey: "new-generation", input: .image(image)) { duringClear = $0 }
        checks["newGenerationCanPublishWhileOldDirectoryDeletionIsBlocked"] = pump(0.3) { duringClear != nil }
            && !deleteGate.finished && !deletionEvents.values.contains("clear-completed-main")
        deleteGate.release()
        checks["clearCompletionWaitsForTheRetiredDirectoryDeletion"] = pump {
            deletionEvents.values.contains("clear-completed-main") && ThumbnailEncodingObservation.finished("new-generation") > 0
        }
        var newDiskFinished = false, newDiskData: Data?
        asynchronousClear.loadRawDataAsync(forKey: "new-generation", loader: { nil }) {
            newDiskData = $0; newDiskFinished = true
        }
        checks["deletingTheRetiredDirectoryCannotDeletePostClearDiskWrites"] = pump { newDiskFinished } && newDiskData != nil
        let failures = DemandEvents()
        let badSource = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("bad-source.png", isDirectory: false)
        try Data("invalid-image".utf8).write(to: badSource)
        var failureCount = 0
        negative.load(forKey: "bad", input: .sourceFile(badSource, onFailure: { failures.record("generated") })) { _ in failureCount += 1 }
        checks["firstNilCompletes"] = pump { failureCount == 1 }
        negative.load(forKey: "bad", input: .sourceFile(badSource, onFailure: { failures.record("generated-again") })) { _ in failureCount += 1 }
        checks["nilLoadRetainsOriginalNegativeCacheSemantics"] = failureCount == 2 && failures.values == ["generated"]
        checks["negativeCacheIsWarmBeforeExplicitClear"] = negative.hasCachedResult(forKey: "bad")

        let neighboring = ThumbnailCache(namespace: "neighbor-" + UUID().uuidString, usesFailureCache: true)
        var neighborImage: NSImage?, neighborFailure = false
        neighboring.load(forKey: "neighbor-image", input: .image(image)) { neighborImage = $0 }
        neighboring.load(forKey: "neighbor-failure", input: .sourceData(Data())) { _ in neighborFailure = true }
        checks["neighborNamespaceHasImageAndFailureBeforeClear"] = pump {
            neighborImage != nil && neighborFailure && ThumbnailEncodingObservation.finished("neighbor-image") > 0
        }
            && neighboring.hasCachedResult(forKey: "neighbor-failure")
        negative.clearAll()
        checks["atomicClearRemovesItsNegativeConclusion"] = !negative.hasCachedResult(forKey: "bad")
        checks["atomicClearKeepsOtherNamespaceMemoryAndFailure"] = neighboring.cachedImage(forKey: "neighbor-image") != nil
            && neighboring.hasCachedResult(forKey: "neighbor-failure")
        neighboring.imageCache.removeAllObjects()
        neighborImage = nil
        neighboring.load(forKey: "neighbor-image", input: .sourceData(Data())) { neighborImage = $0 }
        checks["atomicClearKeepsOtherNamespaceDisk"] = pump { neighborImage != nil }
        var afterClear: NSImage?
        let afterClearJPEGCount = ThumbnailEncodingObservation.count("jpeg")
        negative.load(forKey: "bad", input: .image(image)) { afterClear = $0 }
        checks["sameKeySucceedsAfterExplicitClearWithoutChangingIdentity"] = pump { afterClear != nil && ThumbnailEncodingObservation.finished("bad") > 1 }
            && ThumbnailEncodingObservation.count("jpeg") == afterClearJPEGCount + 1
        negative.imageCache.removeAllObjects()
        afterClear = nil
        negative.load(forKey: "bad", input: .sourceData(Data())) { afterClear = $0 }
        checks["atomicClearRecreatesDirectoryForNewDiskReturns"] = pump { afterClear != nil }

        let clearNil = ThumbnailCache(namespace: "clear-held-nil-" + UUID().uuidString, usesFailureCache: true)
        let heldNil = DemandImageGate(), heldNilToken = ThumbnailCacheRequestCancellation()
        var heldNilCompletions = 0, heldNilImages = 0
        clearNil.loadImageAsync(forKey: "same-key", cancellation: heldNilToken, loader: { (await heldNil.image()).map { .image($0) } }) { result in
            heldNilCompletions += 1
            if result != nil { heldNilImages += 1 }
        }
        checks["oldNilProducerIsHeldBeforeAtomicClear"] = pump { heldNil.waiting }
        clearNil.clearAll()
        heldNil.resume(nil)
        checks["atomicClearPreservesExactlyOneOldNilConsumerCompletion"] = pump { heldNilCompletions == 1 }
            && heldNilImages == 0 && !heldNilToken.cancelled
        checks["oldNilProducerCannotRefillFailureAfterAtomicClear"] = !clearNil.hasCachedResult(forKey: "same-key")
        var heldNilRecovery: NSImage?
        clearNil.load(forKey: "same-key", input: .image(image)) { heldNilRecovery = $0 }
        checks["sameKeyAfterHeldNilClearCanGenerateAndCacheSuccess"] = pump { heldNilRecovery != nil }
            && clearNil.hasCachedResult(forKey: "same-key") && heldNilCompletions == 1
        clearNil.clearAll(); neighboring.clearAll()

        let cancelledFailureGate = DemandImageGate(), cancelledFailure = ThumbnailCacheRequestCancellation()
        var failureWasDelivered = false, failureRecovered = false
        negative.loadImageAsync(forKey: "cancelled-failure", cancellation: cancelledFailure,
            loader: { (await cancelledFailureGate.image()).map { .image($0) } }) { _ in failureWasDelivered = true }
        checks["negativeCacheCandidateStarted"] = pump { cancelledFailureGate.waiting }
        cancelledFailure.cancel()
        checks["cancelledNilGeneratorReturns"] = pump { cancelledFailureGate.cancelled }
        negative.load(forKey: "cancelled-failure", input: .image(image)) { failureRecovered = $0 != nil }
        checks["cancelledNilCannotPopulateNegativeCache"] = pump { failureRecovered } && !failureWasDelivered

        let decodeEvents = DemandEvents(), decodeGate = DemandBlockingGate()
        var decodedCount = 0
        for index in 0..<3 {
            cache.loadImageDataAsync(forKey: "bounded-decode-\(index)", loader: { bytes }, decoder: { data in
                decodeEvents.record("decode-\(index)"); decodeGate.wait(); return NSImage(data: data)
            }) { _ in decodedCount += 1 }
        }
        checks["twoIndependentShortDecodesCanRun"] = pump { decodeEvents.values.count >= 2 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["thirdDecodeWaitsForBoundedLane"] = decodeEvents.values.count == 2
        for _ in 0..<3 { decodeGate.release() }
        checks["allShortDecodesFinishAfterSlotsRelease"] = pump { decodedCount == 3 }

        let asyncGate = DemandImageGate(), asyncToken = ThumbnailCacheRequestCancellation()
        var oldAsyncDelivered = false, queuedAsyncDelivered = false
        cache.loadImageAsync(forKey: "async-generator", cancellation: asyncToken,
            loader: { (await asyncGate.image()).map { .image($0) } }) { _ in oldAsyncDelivered = true }
        checks["asyncGenerationStartedWithoutBlockingThread"] = pump { asyncGate.waiting }
        cache.loadImageAsync(forKey: "next-async-generator", loader: { .image(image) }) { queuedAsyncDelivered = $0 != nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["asyncGenerationKeepsBoundedSlotUntilCallback"] = !queuedAsyncDelivered
        asyncToken.cancel()
        checks["lastAsyncConsumerCancelsTaskAndReleasesSlot"] = pump { queuedAsyncDelivered && asyncGate.cancelled }
        checks["cancelledAsyncGenerationDoesNotPublish"] = !oldAsyncDelivered && cache.cachedImage(forKey: "async-generator") == nil

        let congested = ThumbnailCache(countLimit: 2, namespace: "congested-" + UUID().uuidString)
        let firstGeneration = DemandImageGate(), congestionGate = DemandBlockingGate(), congestionEvents = DemandEvents()
        let generationOrder = DemandEvents()
        var firstPublished = false, pendingGenerated = 0, shortFinished = 0, priorMissesFinished = false
        congested.loadImageAsync(forKey: "first-image", loader: { (await firstGeneration.image()).map { .image($0) } }) { firstPublished = $0 != nil }
        checks["congestionFirstGeneratorHoldsSlot"] = pump { firstGeneration.waiting }
        for index in 0..<8 {
            congested.loadImageAsync(forKey: "congested-image-\(index)", loader: {
                let previous = generationOrder.values.last ?? "first-image"
                generationOrder.record("congested-image-\(index)")
                congestionEvents.record(congested.cachedImage(forKey: previous) == nil ? "ran-ahead" : "publication-ordered")
                return NSImage(data: bytes).map { .image($0) }
            }) { _ in pendingGenerated += 1 }
        }
        congested.loadRawDataAsync(forKey: "miss-barrier", loader: { nil }) { _ in priorMissesFinished = true }
        checks["congestionQueuedImageMissesHaveFinished"] = pump { priorMissesFinished }
        for index in 0..<2 {
            congested.loadImageDataAsync(forKey: "short-blocker-\(index)", loader: { bytes }, decoder: { data in
                congestionEvents.record("short-blocked"); congestionGate.wait(); return NSImage(data: data)
            }) { _ in shortFinished += 1 }
        }
        checks["congestionBothShortSlotsOccupied"] = pump { congestionEvents.values.filter { $0 == "short-blocked" }.count == 2 }
        firstGeneration.resume(image)
        checks["generationPublicationContinuesDuringShortLaneCongestion"] = pump(0.6) { firstPublished && pendingGenerated == 8 }
        checks["generatedImagesNeverRunAheadOfPublication"] = !congestionEvents.values.contains("ran-ahead")
        for _ in 0..<2 { congestionGate.release() }
        checks["congestionFinishesAfterShortSlotsRelease"] = pump { firstPublished && pendingGenerated == 8 && shortFinished == 2 }
        congested.clearAll()

        let handoffGate = DemandBlockingGate(), handoffEvents = DemandEvents()
        let handoff = ThumbnailCache(namespace: "generation-handoff-" + UUID().uuidString,
            writeEncodedData: { data, url in
                try data.write(to: url)
                if handoffEvents.values.isEmpty { handoffEvents.record("blocked-first"); handoffGate.wait() }
            })
        let handoffToken = ThumbnailCacheRequestCancellation()
        var cancelledHandoffDelivered = false, followingHandoffFinished = false
        handoff.loadImageAsync(forKey: "cancel-before-publish", cancellation: handoffToken,
            loader: { NSImage(data: bytes).map { .image($0) } }) { _ in cancelledHandoffDelivered = true }
        checks["asyncHandoffDerivedWriteHeldAfterImagePublication"] = pump { handoffGate.started }
            && pump(0.3) { cancelledHandoffDelivered }
        handoff.loadImageAsync(forKey: "next-after-handoff", loader: {
            handoffEvents.record("next-started"); return NSImage(data: bytes).map { .image($0) }
        }) { followingHandoffFinished = $0 != nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["generationSlotRetainedThroughPublishedDerivedTail"] = !handoffEvents.values.contains("next-started")
        handoffToken.cancel(); handoffGate.release()
        checks["cancelledHandoffReturnsSlotForNextGenerator"] = pump { followingHandoffFinished }
        checks["cancellingAlreadyDeliveredConsumerKeepsReadyImage"] = cancelledHandoffDelivered && handoff.cachedImage(forKey: "cancel-before-publish") != nil
        handoff.clearAll()

        let ingress = ThumbnailCache(namespace: "source-ingress-" + UUID().uuidString)
        let inputGates = (0..<4).map { _ in DemandDataGate() }
        let blockedDecoders = DemandBlockingGate(), sourceEvents = DemandEvents()
        let rawTokens = (0..<2).map { _ in ThumbnailCacheRequestCancellation() }
        var sourceBlockersFinished = 0, cancelledRawCallbacks = 0, siblingImage: NSImage?, siblingRaw: Data?
        for index in 0..<2 {
            ingress.loadImageDataAsync(forKey: "ingress-blocker-\(index)", loader: {
                await inputGates[index].wait(); return bytes
            }, decoder: { data in
                sourceEvents.record("decoder-blocked"); blockedDecoders.wait(); return NSImage(data: data)
            }) { _ in sourceBlockersFinished += 1 }
            ingress.loadRawDataAsync(forKey: "pending-raw-\(index)", loader: {
                await inputGates[index + 2].wait(); sourceEvents.record("raw-returned"); return bytes
            }, cancellation: rawTokens[index]) { _ in cancelledRawCallbacks += 1 }
        }
        checks["fourAsyncSourcesEnterWithoutExceedingCap"] = pump { inputGates.allSatisfy(\.waiting) }
        let siblingImageGate = DemandDataGate(), siblingRawGate = DemandDataGate()
        ingress.loadImageDataAsync(forKey: "still-sibling", sourceDataKey: "raw-sibling", loader: {
            sourceEvents.record("sibling-image-started"); await siblingImageGate.wait(); return bytes
        }) { siblingImage = $0 }
        ingress.loadRawDataAsync(forKey: "raw-sibling", loader: {
            sourceEvents.record("sibling-raw-started"); await siblingRawGate.wait(); return bytes
        }) { siblingRaw = $0 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["laterAsyncSourcesWaitAtBoundedIngress"] = !siblingImageGate.waiting && !siblingRawGate.waiting
        inputGates[0].release(); inputGates[1].release()
        checks["sourceIngressBothDecodeSlotsAreBlocked"] = pump { sourceEvents.values.filter { $0 == "decoder-blocked" }.count == 2 }
        inputGates[2].release(); inputGates[3].release()
        checks["sourceIngressRawDataReturned"] = pump { sourceEvents.values.filter { $0 == "raw-returned" }.count == 2 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["sourceSlotsRemainHeldWhileRawPublicationQueued"] = !siblingImageGate.waiting && !siblingRawGate.waiting
        rawTokens.forEach { $0.cancel() }
        checks["cancelledQueuedPublicationReturnsSourceSlots"] = pump { siblingImageGate.waiting && siblingRawGate.waiting }
        siblingImageGate.release(); siblingRawGate.release()
        for _ in 0..<2 { blockedDecoders.release() }
        checks["rawAndStillSiblingSourcesDrainWithoutDeadlock"] = pump {
            sourceBlockersFinished == 2 && siblingImage != nil && siblingRaw == bytes
        }
        checks["cancelledQueuedRawDoesNotPublishOrCallback"] = cancelledRawCallbacks == 0
            && ingress.cachedImage(forKey: "pending-raw-0") == nil
        ingress.clearAll()

        let reserved = ThumbnailCache(namespace: "source-priority-" + UUID().uuidString)
        let lowGates = (0..<3).map { _ in DemandDataGate() }, visibleGate = DemandDataGate()
        let lowTokens = (0..<3).map { _ in ThumbnailCacheRequestCancellation() }
        var reservedFinished = 0
        for index in 0..<2 {
            reserved.loadImageDataAsync(forKey: "low-source-\(index)", priority: .prefetch,
                loader: { await lowGates[index].wait(); return bytes }, cancellation: lowTokens[index]) { _ in reservedFinished += 1 }
        }
        checks["twoPrefetchSourcesCanOccupyBackgroundSlots"] = pump { lowGates[0].waiting && lowGates[1].waiting }
        reserved.loadImageDataAsync(forKey: "low-source-2", priority: .prefetch,
            loader: { await lowGates[2].wait(); return bytes }, cancellation: lowTokens[2]) { _ in reservedFinished += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["prefetchCannotConsumeAllVisibleSourceCapacity"] = !lowGates[2].waiting
        reserved.loadImageDataAsync(forKey: "low-source-2", priority: .visible, loader: { nil }) { _ in reservedFinished += 1 }
        reserved.loadRawDataAsync(forKey: "visible-source", loader: { await visibleGate.wait(); return bytes }) { _ in reservedFinished += 1 }
        checks["pendingPrefetchPromotionUsesReservedSourceSlot"] = pump { lowGates[2].waiting }
        checks["newVisibleSourceUsesOtherReservedSlot"] = pump { visibleGate.waiting }
        lowGates.forEach { $0.release() }; visibleGate.release()
        checks["allReservedSourceConsumersFinish"] = pump { reservedFinished == 5 }
        reserved.clearAll()

        let admissions = ThumbnailCache(namespace: "fixed-source-admission-" + UUID().uuidString)
        let admissionGates = (0..<4).map { _ in DemandDataGate() }, newVisibleGate = DemandDataGate()
        let admissionLowTokens = (0..<4).map { _ in ThumbnailCacheRequestCancellation() }
        let admissionVisibleTokens = (0..<2).map { _ in ThumbnailCacheRequestCancellation() }
        var admissionCompleted = 0, cancelledVisibleDelivered = false
        // Confirm A/B have entered as prefetch before any promotion or C/D.
        for index in 0..<2 {
            admissions.loadImageDataAsync(forKey: "admitted-low-\(index)", priority: .prefetch,
                loader: { await admissionGates[index].wait(); return bytes }, cancellation: admissionLowTokens[index]) { _ in admissionCompleted += 1 }
            checks["fixedAdmissionPrefetch\(index)Entered"] = pump { admissionGates[index].waiting }
            admissions.loadImageDataAsync(forKey: "admitted-low-\(index)", priority: .visible,
                loader: { nil }, cancellation: admissionVisibleTokens[index]) { _ in cancelledVisibleDelivered = true }
        }
        for index in 2..<4 {
            admissions.loadImageDataAsync(forKey: "admitted-low-\(index)", priority: .prefetch,
                loader: { await admissionGates[index].wait(); return bytes }, cancellation: admissionLowTokens[index]) { _ in admissionCompleted += 1 }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["promotionDoesNotRefundPrefetchAdmissionPermits"] = !admissionGates[2].waiting && !admissionGates[3].waiting
        admissionVisibleTokens.forEach { $0.cancel() }
        admissions.loadRawDataAsync(forKey: "visible-after-demotion", loader: {
            await newVisibleGate.wait(); return bytes
        }) { _ in admissionCompleted += 1 }
        checks["visibleCanEnterAfterEarlierPrefetchConsumersDemote"] = pump(0.15) { newVisibleGate.waiting }
        admissionGates[0].release(); admissionGates[1].release()
        checks["fixedAdmissionPendingWorkCanStartAfterPermitsReturn"] = pump {
            admissionGates[2].waiting && admissionGates[3].waiting && newVisibleGate.waiting
        }
        admissionGates[2].release(); admissionGates[3].release(); newVisibleGate.release()
        checks["fixedAdmissionsDrainExactlyOnce"] = pump { admissionCompleted == 5 } && !cancelledVisibleDelivered
        admissions.clearAll()

        for joinsBeforeProviderRead in [true, false] {
            let gate = DemandDataGate(), hook = DemandEvents(), observed = DemandEvents()
            let key = joinsBeforeProviderRead ? "priority-before" : "priority-after"
            let prefetch = ThumbnailCacheRequestCancellation(), visible = ThumbnailCacheRequestCancellation()
            var finished = false
            cache.loadImageDataAsync(forKey: key, priority: .prefetch,
                onPriorityPromotion: { hook.record("promote") }, loader: { provider in
                    if joinsBeforeProviderRead { await gate.wait() }
                    observed.record(provider() == .visible ? "visible" : "prefetch")
                    if !joinsBeforeProviderRead { await gate.wait() }
                    return bytes
                }, cancellation: prefetch) { _ in }
            checks[key + "LoaderWaiting"] = pump { gate.waiting }
            cache.loadImageDataAsync(forKey: key, priority: .visible, loader: { nil }, cancellation: visible) { finished = $0 != nil }
            gate.release()
            checks[key + "OneProducerFinishes"] = pump { finished }
            checks[key + "PromotionHookRuns"] = hook.values == ["promote"]
            checks[key + "ProviderReflectsLatestAtRegistration"] = observed.values == [joinsBeforeProviderRead ? "visible" : "prefetch"]
            prefetch.cancel(); visible.cancel()
        }
        negative.clearAll()
        cache.clearAll()
        checks.merge(try ThumbnailImagePublicationChecks.run(), uniquingKeysWith: { _, current in current })
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks, "metrics": metrics], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
