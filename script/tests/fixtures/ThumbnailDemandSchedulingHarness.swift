import AppKit
import ImageIO

private final class DemandEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func record(_ name: String) { lock.lock(); entries.append(name); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return entries }
}

private final class DemandBlockingGate: @unchecked Sendable {
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

private final class DemandImageGate: @unchecked Sendable {
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
    func resume(_ image: NSImage) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(returning: image)
    }
}

private final class DemandDataGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { lock.lock(); defer { lock.unlock() }; return continuation != nil }
    func wait() async { await withCheckedContinuation { lock.lock(); continuation = $0; lock.unlock() } }
    func release() { lock.lock(); let pending = continuation; continuation = nil; lock.unlock(); pending?.resume() }
}

@main struct ThumbnailDemandSchedulingHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 40, height: 30))
        let bytes = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        func pump(_ seconds: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
            let until = Date().addingTimeInterval(seconds)
            while !condition(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            return condition()
        }
        var checks: [String: Bool] = [:]
        var metrics: [String: Double] = [:]
        // This probe deliberately uses the pre-D17 public API too. Compile the
        // same fixture against baseline without -D D17_SCHEDULING for comparison.
        let cache = ThumbnailCache(namespace: "demand-" + UUID().uuidString)
        var warm: NSImage?
        cache.load(forKey: "warm", loader: { image }) { warm = $0 }
        checks["warmImageSeeded"] = pump { warm != nil }
        cache.imageCache.removeAllObjects(); warm = nil
        let heavy = DemandBlockingGate()
        var heavyFinished = false
        cache.load(forKey: "slow-generator", loader: { heavy.wait(); return image }) { heavyFinished = $0 != nil }
        checks["slowGeneratorStarted"] = pump { heavy.started }
        let started = Date()
        cache.load(forKey: "warm", loader: { preconditionFailure("warm disk must not regenerate") }) { warm = $0 }
        let warmBeforeRelease = pump(0.25) { warm != nil }
        metrics["warmReadBeforeGeneratorRelease"] = warmBeforeRelease ? 1 : 0
        metrics["warmReadObservationMilliseconds"] = Date().timeIntervalSince(started) * 1000
        heavy.release()
        checks["slowAndWarmFinishAfterRelease"] = pump { heavyFinished && warm != nil }
        #if D17_SCHEDULING
        checks["warmDiskReadDoesNotWaitForBlockedGenerator"] = warmBeforeRelease
        let events = DemandEvents(), generation = DemandBlockingGate()
        cache.load(forKey: "generation-blocker", loader: { generation.wait(); return image }) { _ in }
        checks["serialGenerationBlockerStarted"] = pump { generation.started }
        let dropped = ThumbnailCacheRequestCancellation()
        cache.load(forKey: "cancel-queued", priority: .prefetch, cancellation: dropped,
            loader: { events.record("cancelled-loader"); return image }) { _ in events.record("cancelled-callback") }
        let low = ThumbnailCacheRequestCancellation(), promoted = ThumbnailCacheRequestCancellation()
        var promotedDelivered = false, survivorDelivered = false
        cache.load(forKey: "older-prefetch", priority: .prefetch, cancellation: low,
            loader: { events.record("older"); return image }) { _ in }
        cache.load(forKey: "promoted-prefetch", priority: .prefetch, cancellation: promoted,
            loader: { events.record("promoted"); return image }) { _ in }
        // Let the short disk misses reach the occupied generation lane.
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let visible = ThumbnailCacheRequestCancellation()
        cache.load(forKey: "promoted-prefetch", priority: .visible, cancellation: visible,
            loader: { events.record("duplicate-promoted-loader"); return image }) { promotedDelivered = $0 != nil }
        dropped.cancel(); promoted.cancel()
        generation.release()
        checks["remainingConsumerReceivesPromotedResult"] = pump { promotedDelivered && events.values.contains("older") }
        checks["lastCancelledQueuedConsumerNeverRunsLoaderOrCallback"] = !events.values.contains("cancelled-loader")
            && !events.values.contains("cancelled-callback") && cache.cachedImage(forKey: "cancel-queued") == nil
        checks["visibleJoinPromotesPendingPrefetchAheadOfOlderPrefetch"] = events.values.first == "promoted"
        checks["sameKeyHasOnlyOneGenerator"] = !events.values.contains("duplicate-promoted-loader")
        cache.load(forKey: "cancel-queued", loader: { image }) { survivorDelivered = $0 != nil }
        checks["cancellationDoesNotPoisonFailureCache"] = pump { survivorDelivered }
        low.cancel(); visible.cancel()

        let sharedGate = DemandBlockingGate()
        let first = ThumbnailCacheRequestCancellation(), second = ThumbnailCacheRequestCancellation()
        var firstFinished = false, secondFinished = false
        cache.load(forKey: "shared-sync", cancellation: first,
            loader: { sharedGate.wait(); return image }) { firstFinished = $0 != nil }
        checks["sharedSyncGeneratorStarted"] = pump { sharedGate.started }
        cache.load(forKey: "shared-sync", cancellation: second,
            loader: { preconditionFailure("shared key regenerated") }) { secondFinished = $0 != nil }
        first.cancel(); sharedGate.release()
        checks["cancelOnePreservesOtherConsumer"] = pump { secondFinished } && !firstFinished
        let lateGate = DemandBlockingGate(), lateToken = ThumbnailCacheRequestCancellation()
        var lateDelivered = false
        cache.load(forKey: "late-sync", cancellation: lateToken,
            loader: { lateGate.wait(); return image }) { _ in lateDelivered = true }
        checks["lateSyncGeneratorStarted"] = pump { lateGate.started }
        lateToken.cancel(); lateGate.release()
        checks["lateSyncGeneratorReturns"] = pump { lateGate.finished }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["cancelledRunningGeneratorCannotPublish"] = !lateDelivered && cache.cachedImage(forKey: "late-sync") == nil
        var replacement: NSImage?
        cache.load(forKey: "late-sync", loader: { image }) { replacement = $0 }
        checks["sameKeyAfterCancelledSyncCanStartFresh"] = pump { replacement != nil }

        let pinnedGate = DemandBlockingGate(), pinnedToken = ThumbnailCacheRequestCancellation()
        var legacyDelivered = false
        cache.load(forKey: "pinned-sync", cancellation: pinnedToken,
            loader: { pinnedGate.wait(); return image }) { _ in }
        checks["pinnedSyncGeneratorStarted"] = pump { pinnedGate.started }
        cache.load(forKey: "pinned-sync", loader: { nil }) { legacyDelivered = $0 != nil }
        pinnedToken.cancel(); pinnedGate.release()
        checks["legacyUncancellableLoadPinsGenerator"] = pump { legacyDelivered }

        for clear in [false, true] {
            let gate = DemandBlockingGate()
            let isolated = ThumbnailCache(namespace: "sync-clear-" + UUID().uuidString)
            var delivered = false
            isolated.load(forKey: "invalidated", loader: { gate.wait(); return image }) { delivered = $0 != nil }
            let label = clear ? "clear" : "remove"
            checks[label + "SyncLoadStarted"] = pump { gate.started }
            if clear { isolated.clearAll() } else { isolated.remove(forKey: "invalidated") }
            gate.release()
            checks[label + "PreservesExistingSyncConsumer"] = pump { delivered }
            checks[label + "SyncResultDoesNotRepopulateMemory"] = isolated.cachedImage(forKey: "invalidated") == nil
            var readFinished = false, disk: Data?
            isolated.loadRawDataAsync(forKey: "invalidated", loader: { nil }) { disk = $0; readFinished = true }
            checks[label + "SyncResultDoesNotRepopulateDisk"] = pump { readFinished } && disk == nil
            isolated.clearAll()
        }
        let negative = ThumbnailCache(namespace: "failure-" + UUID().uuidString, usesFailureCache: true)
        let failures = DemandEvents()
        var failureCount = 0
        negative.load(forKey: "bad", loader: { failures.record("generated"); return nil }) { _ in failureCount += 1 }
        checks["firstNilCompletes"] = pump { failureCount == 1 }
        negative.load(forKey: "bad", loader: { failures.record("generated-again"); return image }) { _ in failureCount += 1 }
        checks["nilLoadRetainsOriginalNegativeCacheSemantics"] = failureCount == 2 && failures.values == ["generated"]
        checks["negativeCacheIsWarmBeforeExplicitClear"] = negative.hasCachedResult(forKey: "bad")

        let neighboring = ThumbnailCache(namespace: "neighbor-" + UUID().uuidString, usesFailureCache: true)
        var neighborImage: NSImage?, neighborFailure = false
        neighboring.load(forKey: "neighbor-image", loader: { image }) { neighborImage = $0 }
        neighboring.load(forKey: "neighbor-failure", loader: { nil }) { _ in neighborFailure = true }
        checks["neighborNamespaceHasImageAndFailureBeforeClear"] = pump { neighborImage != nil && neighborFailure }
            && neighboring.hasCachedResult(forKey: "neighbor-failure")
        negative.clearAll()
        checks["atomicClearRemovesItsNegativeConclusion"] = !negative.hasCachedResult(forKey: "bad")
        checks["atomicClearKeepsOtherNamespaceMemoryAndFailure"] = neighboring.cachedImage(forKey: "neighbor-image") != nil
            && neighboring.hasCachedResult(forKey: "neighbor-failure")
        neighboring.imageCache.removeAllObjects()
        neighborImage = nil
        neighboring.load(forKey: "neighbor-image", loader: { preconditionFailure("another namespace's disk was cleared") }) { neighborImage = $0 }
        checks["atomicClearKeepsOtherNamespaceDisk"] = pump { neighborImage != nil }
        var afterClear: NSImage?
        negative.load(forKey: "bad", loader: { failures.record("generated-after-clear"); return image }) { afterClear = $0 }
        checks["sameKeySucceedsAfterExplicitClearWithoutChangingIdentity"] = pump { afterClear != nil }
            && failures.values == ["generated", "generated-after-clear"]
        negative.imageCache.removeAllObjects()
        afterClear = nil
        negative.load(forKey: "bad", loader: { preconditionFailure("clearAll did not recreate its namespace directory") }) { afterClear = $0 }
        checks["atomicClearRecreatesDirectoryForNewDiskReturns"] = pump { afterClear != nil }

        let clearNil = ThumbnailCache(namespace: "clear-held-nil-" + UUID().uuidString, usesFailureCache: true)
        let heldNil = DemandBlockingGate(), heldNilToken = ThumbnailCacheRequestCancellation()
        var heldNilCompletions = 0, heldNilImages = 0
        clearNil.load(forKey: "same-key", cancellation: heldNilToken, loader: { heldNil.wait(); return nil }) { result in
            heldNilCompletions += 1
            if result != nil { heldNilImages += 1 }
        }
        checks["oldNilProducerIsHeldBeforeAtomicClear"] = pump { heldNil.started }
        clearNil.clearAll()
        heldNil.release()
        checks["atomicClearPreservesExactlyOneOldNilConsumerCompletion"] = pump { heldNilCompletions == 1 }
            && heldNilImages == 0 && !heldNilToken.cancelled
        checks["oldNilProducerCannotRefillFailureAfterAtomicClear"] = !clearNil.hasCachedResult(forKey: "same-key")
        var heldNilRecovery: NSImage?
        clearNil.load(forKey: "same-key", loader: { image }) { heldNilRecovery = $0 }
        checks["sameKeyAfterHeldNilClearCanGenerateAndCacheSuccess"] = pump { heldNilRecovery != nil }
            && clearNil.hasCachedResult(forKey: "same-key") && heldNilCompletions == 1
        clearNil.clearAll(); neighboring.clearAll()

        let cancelledFailureGate = DemandBlockingGate(), cancelledFailure = ThumbnailCacheRequestCancellation()
        var failureWasDelivered = false, failureRecovered = false
        negative.load(forKey: "cancelled-failure", cancellation: cancelledFailure,
            loader: { cancelledFailureGate.wait(); return nil }) { _ in failureWasDelivered = true }
        checks["negativeCacheCandidateStarted"] = pump { cancelledFailureGate.started }
        cancelledFailure.cancel(); cancelledFailureGate.release()
        checks["cancelledNilGeneratorReturns"] = pump { cancelledFailureGate.finished }
        negative.load(forKey: "cancelled-failure", loader: { image }) { failureRecovered = $0 != nil }
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
            loader: { await asyncGate.image() }) { _ in oldAsyncDelivered = true }
        checks["asyncGenerationStartedWithoutBlockingThread"] = pump { asyncGate.waiting }
        cache.loadImageAsync(forKey: "next-async-generator", loader: { image }) { queuedAsyncDelivered = $0 != nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["asyncGenerationKeepsBoundedSlotUntilCallback"] = !queuedAsyncDelivered
        asyncToken.cancel()
        checks["lastAsyncConsumerCancelsTaskAndReleasesSlot"] = pump { queuedAsyncDelivered && asyncGate.cancelled }
        checks["cancelledAsyncGenerationDoesNotPublish"] = !oldAsyncDelivered && cache.cachedImage(forKey: "async-generator") == nil

        let congested = ThumbnailCache(countLimit: 2, namespace: "congested-" + UUID().uuidString)
        let firstGeneration = DemandImageGate(), congestionGate = DemandBlockingGate(), congestionEvents = DemandEvents()
        let generationOrder = DemandEvents()
        var firstPublished = false, pendingGenerated = 0, shortFinished = 0, priorMissesFinished = false
        congested.loadImageAsync(forKey: "first-image", loader: { await firstGeneration.image() }) { firstPublished = $0 != nil }
        checks["congestionFirstGeneratorHoldsSlot"] = pump { firstGeneration.waiting }
        for index in 0..<8 {
            congested.loadImageAsync(forKey: "congested-image-\(index)", loader: {
                let previous = generationOrder.values.last ?? "first-image"
                generationOrder.record("congested-image-\(index)")
                congestionEvents.record(congested.cachedImage(forKey: previous) == nil ? "ran-ahead" : "publication-ordered")
                return NSImage(data: bytes)
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
            loader: { NSImage(data: bytes) }) { _ in cancelledHandoffDelivered = true }
        checks["asyncHandoffStagedBeforePublication"] = pump { handoffGate.started }
        handoff.loadImageAsync(forKey: "next-after-handoff", loader: {
            handoffEvents.record("next-started"); return NSImage(data: bytes)
        }) { followingHandoffFinished = $0 != nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        checks["generationSlotRetainedUntilPublication"] = !handoffEvents.values.contains("next-started")
        handoffToken.cancel(); handoffGate.release()
        checks["cancelledHandoffReturnsSlotForNextGenerator"] = pump { followingHandoffFinished }
        checks["cancelledHandoffDoesNotPublishImage"] = !cancelledHandoffDelivered && handoff.cachedImage(forKey: "cancel-before-publish") == nil
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
        #endif
        cache.clearAll()
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks, "metrics": metrics], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
