import AppKit
import ImageIO

final class LeaseURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var pending: [String: LeaseURLProtocol] = [:]
    private static var started = Set<String>()
    private static var stopped = Set<String>()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.url!.lastPathComponent
        Self.lock.lock(); Self.pending[key] = self; Self.started.insert(key); Self.lock.unlock()
    }
    override func stopLoading() {
        let key = request.url!.lastPathComponent
        Self.lock.lock(); Self.pending.removeValue(forKey: key); Self.stopped.insert(key); Self.lock.unlock()
    }
    static func hasStarted(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return started.contains(key) }
    static func hasStopped(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return stopped.contains(key) }
    static func complete(_ key: String, data: Data) {
        lock.lock(); let operation = pending.removeValue(forKey: key); lock.unlock()
        guard let operation else { return }
        let response = HTTPURLResponse(url: operation.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        operation.client?.urlProtocol(operation, didReceive: response, cacheStoragePolicy: .notAllowed)
        operation.client?.urlProtocol(operation, didLoad: data)
        operation.client?.urlProtocolDidFinishLoading(operation)
    }
}

final class LeaseDataGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var finished = false
    private var cancelled = false
    var waiting: Bool { lock.lock(); defer { lock.unlock() }; return continuation != nil }
    var didFinish: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func data() async -> Data? {
        let result: Data? = await withCheckedContinuation { value in
            lock.lock(); continuation = value; lock.unlock()
        }
        noteFinished(cancelled: Task.isCancelled)
        return result
    }
    private func noteFinished(cancelled: Bool) { lock.lock(); finished = true; self.cancelled = cancelled; lock.unlock() }
    func resume(_ data: Data) {
        lock.lock(); let continuation = continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(returning: data)
    }
}

final class LeaseDiskWriteGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isWaiting = false
    private var isFinished = false
    var waiting: Bool { lock.lock(); defer { lock.unlock() }; return isWaiting }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return isFinished }
    func write(_ data: Data, to url: URL, blocking: Bool) throws {
        try data.write(to: url)
        guard blocking else { return }
        lock.lock(); isWaiting = true; lock.unlock()
        _ = semaphore.wait(timeout: .now() + 5)
        lock.lock(); isFinished = true; lock.unlock()
    }
    func release() { semaphore.signal() }
}

@main struct SteamThumbnailLeaseChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func png(_ color: NSColor) -> Data {
            let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(destination))
            return data as Data
        }
        func pump(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            return condition()
        }
        let red = png(.systemRed), blue = png(.systemBlue)
        let cache = ThumbnailCache(namespace: "lease-" + UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LeaseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let coordinator = SteamWorkshopPreviewRequestCoordinator(session: session)
        var checks: [String: Bool] = [:], callbacks: [String: NSImage] = [:]
        func load(_ key: String, token: SteamWorkshopPreviewLoadCancellation, label: String? = nil,
                  priority: SteamWorkshopPreviewRequestPriority = .visible) {
            let url = URL(string: "https://example.invalid/" + key)!
            cache.loadImageDataAsync(forKey: key, loader: {
                await coordinator.loadData(from: url, priority: priority)
            }, decoder: steamWorkshopPreviewImage(from:), cancellation: token) { image in
                if let image { callbacks[label ?? key] = image }
            }
        }
        let old = (0..<4).map { _ in SteamWorkshopPreviewLoadCancellation() }
        for index in 0..<4 { load("slow-\(index)", token: old[index]) }
        checks["fourSlowRequestsOccupyVisibleSlots"] = pump { (0..<4).allSatisfy { LeaseURLProtocol.hasStarted("slow-\($0)") } }
        let fresh = SteamWorkshopPreviewLoadCancellation()
        load("fresh", token: fresh, priority: .userInitiated)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["newDetailInitiallyWaitsBehindFourVisibleRequests"] = !LeaseURLProtocol.hasStarted("fresh")
        old.forEach { $0.cancel() }
        checks["lastConsumersCancelOldHTTPAndReleaseSlot"] = pump {
            (0..<4).allSatisfy { LeaseURLProtocol.hasStopped("slow-\($0)") } && LeaseURLProtocol.hasStarted("fresh")
        }
        LeaseURLProtocol.complete("fresh", data: blue)
        checks["newDetailSucceedsWithoutOldNetworkTimeout"] = pump { callbacks["fresh"] != nil }
        checks["cancelledConsumersNeverReceiveImages"] = (0..<4).allSatisfy { callbacks["slow-\($0)"] == nil }
        let first = SteamWorkshopPreviewLoadCancellation(), second = SteamWorkshopPreviewLoadCancellation()
        load("shared", token: first, label: "first")
        load("shared", token: second, label: "second")
        checks["sharedHTTPStarts"] = pump { LeaseURLProtocol.hasStarted("shared") }
        first.cancel()
        checks["firstConsumerCannotCancelRemainingHTTP"] = !LeaseURLProtocol.hasStopped("shared")
        LeaseURLProtocol.complete("shared", data: red)
        checks["remainingSharedConsumerReceivesImage"] = pump { callbacks["second"] != nil } && callbacks["first"] == nil
        // A cancelled loader that ignores cancellation cannot poison a new
        // producer using the same key or steal its completions.
        let gate = LeaseDataGate(), stale = SteamWorkshopPreviewLoadCancellation()
        var staleDelivered = false, newImage: NSImage?
        cache.loadImageDataAsync(forKey: "replacement", loader: { await gate.data() },
            decoder: steamWorkshopPreviewImage(from:), cancellation: stale) { _ in staleDelivered = true }
        checks["oldProducerWaiting"] = pump { gate.waiting }
        stale.cancel()
        cache.loadImageDataAsync(forKey: "replacement", loader: { blue }, decoder: steamWorkshopPreviewImage(from:)) { newImage = $0 }
        checks["newSameKeyProducerSucceeds"] = pump { newImage != nil }
        gate.resume(red)
        checks["lateCancelledProducerFinishes"] = pump { gate.didFinish }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["lateCancelledProducerCannotPoisonNewImage"] = gate.wasCancelled && !staleDelivered
            && cache.cachedImage(forKey: "replacement") === newImage
        let pinned = LeaseDataGate(), pinnedToken = SteamWorkshopPreviewLoadCancellation()
        var legacyImage: NSImage?
        cache.loadImageDataAsync(forKey: "legacy", loader: { await pinned.data() },
            decoder: steamWorkshopPreviewImage(from:), cancellation: pinnedToken) { _ in }
        checks["legacyJoinProducerWaiting"] = pump { pinned.waiting }
        cache.loadImageData(forKey: "legacy", loader: { nil }, decoder: steamWorkshopPreviewImage(from:)) { legacyImage = $0 }
        pinnedToken.cancel(); pinned.resume(red)
        checks["uncancellableLegacyConsumerPinsSharedProducer"] = pump { legacyImage != nil } && !pinned.wasCancelled
        let rawGate = LeaseDataGate(), rawToken = SteamWorkshopPreviewLoadCancellation()
        var oldRawDelivered = false, newRaw: Data?
        cache.loadRawDataAsync(forKey: "raw-replacement", loader: { await rawGate.data() }, cancellation: rawToken) { _ in oldRawDelivered = true }
        checks["oldRawProducerWaiting"] = pump { rawGate.waiting }
        rawToken.cancel()
        cache.loadRawDataAsync(forKey: "raw-replacement", loader: { blue }) { newRaw = $0 }
        checks["newRawProducerSucceeds"] = pump { newRaw == blue }
        rawGate.resume(red)
        checks["oldRawFinishesCancelled"] = pump { rawGate.didFinish } && rawGate.wasCancelled
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["lateRawCannotStealNewCompletion"] = !oldRawDelivered && newRaw == blue
        let rawFirst = SteamWorkshopPreviewLoadCancellation(), rawSecond = SteamWorkshopPreviewLoadCancellation(), sharedRaw = LeaseDataGate()
        var survivingRaw: Data?
        cache.loadRawDataAsync(forKey: "raw-shared", loader: { await sharedRaw.data() }, cancellation: rawFirst) { _ in }
        cache.loadRawDataAsync(forKey: "raw-shared", loader: { nil }, cancellation: rawSecond) { survivingRaw = $0 }
        checks["sharedRawProducerWaiting"] = pump { sharedRaw.waiting }
        rawFirst.cancel(); sharedRaw.resume(red)
        checks["remainingRawConsumerKeepsProducerAlive"] = pump { survivingRaw == red } && !sharedRaw.wasCancelled
        for raw in [false, true] {
            let diskGate = LeaseDiskWriteGate()
            let diskCache = ThumbnailCache(namespace: "commit-" + UUID().uuidString,
                writeEncodedData: { data, url in try diskGate.write(data, to: url, blocking: data == red) })
            let oldToken = SteamWorkshopPreviewLoadCancellation()
            var oldDelivered = false, freshDelivered = false
            if raw {
                diskCache.loadRawDataAsync(forKey: "same-key", loader: { red }, cancellation: oldToken) { _ in oldDelivered = true }
            } else {
                diskCache.loadImageDataAsync(forKey: "same-key", loader: { red }, decoder: steamWorkshopPreviewImage(from:), cancellation: oldToken) { _ in oldDelivered = true }
            }
            let label = raw ? "raw" : "image"
            checks[label + "OldWriteIsBlockedBeforePublication"] = pump { diskGate.waiting }
            oldToken.cancel()
            if raw {
                diskCache.loadRawDataAsync(forKey: "same-key", loader: { blue }) { freshDelivered = $0 == blue }
            } else {
                diskCache.loadImageDataAsync(forKey: "same-key", loader: { blue }, decoder: steamWorkshopPreviewImage(from:)) { freshDelivered = $0 != nil }
            }
            checks[label + "NewProducerCommitsWhileOldWriteIsBlocked"] = pump { freshDelivered }
            diskGate.release()
            checks[label + "OldWriteFinishes"] = pump { diskGate.finished }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            diskCache.removeAll()
            var persisted: Data?
            diskCache.loadRawDataAsync(forKey: "same-key", loader: { nil }) { persisted = $0 }
            checks[label + "LateWriteCannotOverwriteNewDiskData"] = pump { persisted != nil } && persisted == blue && !oldDelivered
        }
        let invalidationGate = LeaseDiskWriteGate()
        let invalidatedCache = ThumbnailCache(namespace: "invalidate-" + UUID().uuidString,
            writeEncodedData: { data, url in try invalidationGate.write(data, to: url, blocking: true) })
        var survivingImage: NSImage?, afterInvalidation: Data?, invalidationReadFinished = false
        invalidatedCache.loadImageDataAsync(forKey: "invalidated", loader: { red }, decoder: steamWorkshopPreviewImage(from:)) { survivingImage = $0 }
        checks["invalidatedProducerHasStagedData"] = pump { invalidationGate.waiting }
        invalidatedCache.remove(forKey: "invalidated")
        invalidationGate.release()
        checks["invalidationDoesNotStealExistingConsumerCompletion"] = pump { survivingImage != nil }
        invalidatedCache.loadRawDataAsync(forKey: "invalidated", loader: { nil }) { afterInvalidation = $0; invalidationReadFinished = true }
        checks["invalidationRetiresOldCachePublication"] = pump { invalidationReadFinished } && afterInvalidation == nil
            && invalidatedCache.cachedImage(forKey: "invalidated") == nil
        let crossGate = LeaseDiskWriteGate()
        let crossCache = ThumbnailCache(namespace: "cross-" + UUID().uuidString,
            writeEncodedData: { data, url in try crossGate.write(data, to: url, blocking: data == red) })
        var oldAnimationData: Data?, newStatic: NSImage?, crossDisk: Data?
        crossCache.loadRawDataAsync(forKey: "shared-disk-key", loader: { red }) { oldAnimationData = $0 }
        checks["oldAnimationStagesBeforeRefresh"] = pump { crossGate.waiting }
        crossCache.remove(forKey: "shared-disk-key")
        crossCache.loadImageDataAsync(forKey: "shared-disk-key", loader: { blue }, decoder: steamWorkshopPreviewImage(from:)) { newStatic = $0 }
        checks["newStaticCommitsDuringOldAnimationWrite"] = pump { newStatic != nil }
        crossGate.release()
        checks["refreshKeepsOldAnimationConsumersCompletion"] = pump { oldAnimationData == red }
        crossCache.loadRawDataAsync(forKey: "shared-disk-key", loader: { nil }) { crossDisk = $0 }
        checks["oldRawCannotOverwriteRefreshedImageDisk"] = pump { crossDisk != nil } && crossDisk == blue
        let prefetchGate = LeaseDiskWriteGate()
        let prefetchCache = ThumbnailCache(namespace: "prefetch-" + UUID().uuidString,
            writeEncodedData: { data, url in try prefetchGate.write(data, to: url, blocking: data == red) })
        prefetchCache.prefetchRawDataAsync(forKey: "prefetch-key", loader: { red })
        checks["oldRawPrefetchStagesBeforeRefresh"] = pump { prefetchGate.waiting }
        prefetchCache.remove(forKey: "prefetch-key")
        var prefetchedStatic: NSImage?, prefetchDisk: Data?
        prefetchCache.loadImageDataAsync(forKey: "prefetch-key", loader: { blue }, decoder: steamWorkshopPreviewImage(from:)) { prefetchedStatic = $0 }
        checks["newStaticCommitsDuringOldPrefetchWrite"] = pump { prefetchedStatic != nil }
        prefetchGate.release()
        checks["oldRawPrefetchWriteCompletes"] = pump { prefetchGate.finished }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        prefetchCache.loadRawDataAsync(forKey: "prefetch-key", loader: { nil }) { prefetchDisk = $0 }
        checks["oldRawPrefetchCannotOverwriteRefreshedDisk"] = pump { prefetchDisk != nil } && prefetchDisk == blue
        session.invalidateAndCancel()
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
