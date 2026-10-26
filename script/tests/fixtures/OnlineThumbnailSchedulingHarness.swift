import AppKit
import Foundation

// Only maintenance trimming is excluded. Request actors, decoder, memory owner,
// source publication, cancellation handlers and permits are production code.
nonisolated enum ThumbnailCache {
    static func trimDiskCache(directory: URL, sizeLimit: UInt64, expireBefore: Date? = nil) -> Bool { false }
}

nonisolated private final class ProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String: [ControlledThumbnailProtocol]] = [:]
    private var starts: [String: Int] = [:]
    private var stops: [String: Int] = [:]
    func start(_ value: ControlledThumbnailProtocol) {
        lock.lock(); defer { lock.unlock() }
        let key = value.request.url!.absoluteString
        requests[key, default: []].append(value)
        starts[key, default: 0] += 1
    }
    func stop(_ value: ControlledThumbnailProtocol) {
        lock.lock(); defer { lock.unlock() }
        let key = value.request.url!.absoluteString
        requests[key]?.removeAll { $0 === value }
        stops[key, default: 0] += 1
    }
    func count(_ url: URL, stopped: Bool = false) -> Int {
        lock.lock(); defer { lock.unlock() }
        return (stopped ? stops : starts)[url.absoluteString, default: 0]
    }
    func pendingRequests(_ url: URL) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests[url.absoluteString, default: []].map(\.request)
    }
    func deliver(_ url: URL, data: Data, status: Int = 200) {
        lock.lock()
        let pending = requests.removeValue(forKey: url.absoluteString) ?? []
        lock.unlock()
        for value in pending {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            value.client?.urlProtocol(value, didReceive: response, cacheStoragePolicy: .notAllowed)
            value.client?.urlProtocol(value, didLoad: data)
            value.client?.urlProtocolDidFinishLoading(value)
        }
    }
}
nonisolated private final class ControlledThumbnailProtocol: URLProtocol, @unchecked Sendable {
    static let state = ProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "thumbnail.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state.start(self) }
    override func stopLoading() { Self.state.stop(self) }
}

extension OLThumbnailRequestCoordinator {
    fileprivate func consumerCount(_ url: URL) -> Int { inFlight[url.absoluteString]?.consumers.count ?? 0 }
    fileprivate func schedulerForAudit() -> OLThumbnailRequestScheduler { scheduler }
}

extension OLThumbnailRequestScheduler {
    fileprivate func auditState() -> (Int, Int, Int, Int) {
        (active.values.filter { $0 == .visible }.count, active.values.filter { $0 == .prefetch }.count,
         waiting.filter { $0.priority == .visible }.count, waiting.filter { $0.priority == .prefetch }.count)
    }
    fileprivate func occupy(_ id: UUID, priority: OLThumbnailRequestPriority) async {
        _ = await acquire(id: id, priority: priority)
    }
    fileprivate func vacate(_ id: UUID) { release(id: id) }
}

extension OLThumbnailCache {
    fileprivate func hasDiskEntry(_ resource: URL) -> Bool { FileManager.default.fileExists(atPath: cacheFile(for: resource).path) }
    fileprivate func seedScopedRaw(_ request: OLThumbnailRequest, data: Data) {
        _ = register(request)
        store(data: data, for: request.cacheURL, generation: cacheGeneration, scopeID: request.scopeID)
    }
    fileprivate func evictRawMemory(_ resource: URL) { memCache.removeObject(forKey: resource.absoluteString as NSString) }
    fileprivate func scopeAudit(_ id: String, resource: URL) -> (count: Int, receipts: Int, contains: Bool) {
        (scopes.count, scopes[id]?.urls.count ?? 0, scopes[id]?.urls.contains(resource) == true)
    }
    fileprivate func compactScopeThroughRealStores(_ requests: [OLThumbnailRequest], data: Data) {
        // Raw-memory eviction is controlled, as in diskReadContract below.
        // Scope insertion, threshold compaction, filenames and disk publication
        // all run through their production bodies.
        for request in requests {
            seedScopedRaw(request, data: data)
            evictRawMemory(request.cacheURL)
        }
    }
    fileprivate func allDiskEntriesExist(_ resources: [URL]) -> Bool { resources.allSatisfy(hasDiskEntry) }
    fileprivate func noDiskEntriesExist(_ resources: [URL]) -> Bool { resources.allSatisfy { !hasDiskEntry($0) } }
    fileprivate func drainDecodeQueue() async {
        await withCheckedContinuation { continuation in
            decodeQueue.addBarrierBlock { continuation.resume() }
        }
    }
    fileprivate func diskReadContract() throws {
        let resource = url("disk-read")
        let file = cacheFile(for: resource)
        let data = Data("disk snapshot".utf8)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try expect(cachedData(for: resource) == nil, "missing disk cache must miss")
        try data.write(to: file)
        try expect(cachedData(for: resource) == data, "fresh disk cache must load")
        try FileManager.default.removeItem(at: file)
        try expect(cachedData(for: resource) == data, "loaded memory snapshot must remain usable")
        memCache.removeObject(forKey: resource.absoluteString as NSString)
        try expect(cachedData(for: resource) == nil, "missing disk cache must not survive memory eviction")
        try data.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-maxAge - 1)],
                                             ofItemAtPath: file.path)
        try expect(cachedData(for: resource) == nil, "expired disk cache must miss")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try expect(cachedData(for: resource) == nil, "unreadable cache entry must miss")
        try FileManager.default.removeItem(at: file)
    }
    fileprivate func suspendDecodeQueue(_ value: Bool) { decodeQueue.isSuspended = value }
    fileprivate func decodeAudit() -> (requests: Int, consumers: Int, concurrency: Int, promoted: Int) {
        (decoding.count, decoding.values.reduce(0) { $0 + $1.consumers.count },
         decodeQueue.maxConcurrentOperationCount,
         decoding.values.filter { $0.operation.queuePriority == .veryHigh }.count)
    }
}

private enum Failure: Error { case assertion(String) }
private func expect(_ condition: Bool, _ label: String) throws {
    if !condition { throw Failure.assertion(label) }
}
private func eventually(_ label: String, _ condition: @Sendable () async -> Bool) async throws {
    for _ in 0..<3000 {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw Failure.assertion("timed out: " + label)
}
private func url(_ name: String) -> URL { URL(string: "https://thumbnail.test/" + name)! }

@main private struct OnlineThumbnailSchedulingHarness {
    static func coordinator() -> OLThumbnailRequestCoordinator {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ControlledThumbnailProtocol.self]
        return OLThumbnailRequestCoordinator(session: WallpaperNetworkSession(URLSession(configuration: config)))
    }
    static func pngData(width: Int = 32, height: Int = 18) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }
    static func leases() async throws {
        let coordinator = coordinator()
        let resource = url("leases")
        let first = Task { await coordinator.loadData(from: resource, priority: .prefetch) }
        try await eventually("first started") { ControlledThumbnailProtocol.state.count(resource) == 1 }
        let second = Task { await coordinator.loadData(from: resource, priority: .visible) }
        try await eventually("both consumers") { await coordinator.consumerCount(resource) == 2 }
        first.cancel()
        try expect(await first.value == nil, "cancelled consumer must return without waiting for shared HTTP")
        try expect(ControlledThumbnailProtocol.state.count(resource, stopped: true) == 0,
            "one consumer cancellation terminated another consumer")
        ControlledThumbnailProtocol.state.deliver(resource, data: Data([7]))
        try expect(await second.value == Data([7]), "remaining consumer lost shared result")
        try expect(ControlledThumbnailProtocol.state.count(resource) == 1, "same URL requested twice")

        let lastURL = url("last-consumer")
        let last = Task { await coordinator.loadData(from: lastURL, priority: .visible) }
        try await eventually("last started") { ControlledThumbnailProtocol.state.count(lastURL) == 1 }
        last.cancel()
        try expect(await last.value == nil, "last cancellation did not return")
        try await eventually("HTTP cancelled") { ControlledThumbnailProtocol.state.count(lastURL, stopped: true) == 1 }
        let retry = Task { await coordinator.loadData(from: lastURL, priority: .visible) }
        try await eventually("retry started") { ControlledThumbnailProtocol.state.count(lastURL) == 2 }
        ControlledThumbnailProtocol.state.deliver(lastURL, data: Data([9]))
        try expect(await retry.value == Data([9]), "cancelled request poisoned later retry")
    }
    static func scheduler() async throws {
        let scheduler = OLThumbnailRequestScheduler()
        let first = UUID(), second = UUID(), promotion = UUID()
        await scheduler.occupy(first, priority: .visible)
        await scheduler.occupy(second, priority: .visible)
        let cancelled = Task { await scheduler.run(priority: .prefetch) { 11 } }
        let promoted = Task { await scheduler.run(id: promotion, priority: .prefetch) { 13 } }
        try await eventually("queued prefetch") { await scheduler.auditState().3 == 2 }
        cancelled.cancel()
        try expect(await cancelled.value == nil, "cancelled queue executed an obsolete operation")
        await scheduler.promote(promotion)
        try await eventually("promoted pending") { await scheduler.auditState().2 == 1 }
        await scheduler.vacate(first)
        try expect(await promoted.value == 13, "promoted work waited for all visible permits to drain")
        await scheduler.vacate(second)
        try expect(await scheduler.auditState() == (0, 0, 0, 0), "permits leaked")
    }
    static func decode() async throws {
        let cache = OLThumbnailCache(requestCoordinator: coordinator())
        await cache.clearAll()
        await cache.suspendDecodeQueue(true)
        let generation = await cache.publicationGeneration()
        let data = pngData(), resource = url("decode")
        let first = Task { await cache.storeAndDecode(data: data, for: resource, maxPixelSize: 256,
            generation: generation, priority: .prefetch) }
        try await eventually("queued first decode") { await cache.decodeAudit().requests == 1 }
        let second = Task { await cache.storeAndDecode(data: data, for: resource, maxPixelSize: 256,
            generation: generation, priority: .visible) }
        try await eventually("joined decode") { await cache.decodeAudit().consumers == 2 }
        let audit = await cache.decodeAudit()
        try expect(audit.requests == 1 && audit.concurrency == 2 && audit.promoted == 1,
            "decode did not coalesce, bound, or promote")
        first.cancel()
        try expect(await first.value == nil, "cancelled decode consumer waited on suspended queue")
        try expect(await cache.decodeAudit().requests == 1, "one cancellation removed live shared decode")
        await cache.suspendDecodeQueue(false)
        try expect(await second.value != nil, "remaining decode consumer lost result")
        try expect(cache.readyImage(for: resource, maxPixelSize: 256) != nil, "ready pixels not published")

        await cache.suspendDecodeQueue(true)
        let stale = Task { await cache.storeAndDecode(data: data, for: url("clear-decode"),
            maxPixelSize: 512, generation: generation, priority: .prefetch) }
        try await eventually("stale decode queued") { await cache.decodeAudit().requests == 1 }
        await cache.clearAll()
        try expect(await stale.value == nil, "clear did not release suspended decode consumer")
        await cache.suspendDecodeQueue(false)
        try expect(await cache.cachedData(for: url("clear-decode")) == nil, "clear stale decode wrote raw cache")
    }
    static func fullRequestEpoch() async throws {
        let cache = OLThumbnailCache(requestCoordinator: coordinator())
        await cache.clearAll()
        let resource = url("clear-network"), data = pngData()
        let old = Task { await cache.image(for: resource, maxPixelSize: 256, priority: .visible) }
        try await eventually("old HTTP") { ControlledThumbnailProtocol.state.count(resource) == 1 }
        await cache.clearAll()
        ControlledThumbnailProtocol.state.deliver(resource, data: data)
        try expect(await old.value == nil, "late HTTP request crossed cache clear epoch")
        try expect(await cache.cachedData(for: resource) == nil, "late HTTP repopulated raw cache")
        try expect(cache.readyImage(for: resource, maxPixelSize: 256) == nil, "late HTTP repopulated decoded cache")
        let fresh = Task { await cache.image(for: resource, maxPixelSize: 256, priority: .visible) }
        try await eventually("fresh HTTP") { ControlledThumbnailProtocol.state.count(resource) == 2 }
        ControlledThumbnailProtocol.state.deliver(resource, data: data)
        try expect(await fresh.value != nil, "fresh request failed after clear")
        try expect(await cache.cachedData(for: resource) == data, "fresh request did not persist")
        await cache.clearAll()
    }
    static func scopes() async throws {
        let coordinator = coordinator()
        let cache = OLThumbnailCache(requestCoordinator: coordinator)
        await cache.clearAll()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ControlledThumbnailProtocol.self]
        let transport = WallpaperNetworkSession(URLSession(configuration: config))
        defer { transport.retire() }
        let resource = url("scoped-shared"), other = url("scope-unrelated"), data = pngData()
        let a = OLThumbnailRequest(url: resource, scopeID: "account-A-fixture", session: transport,
            referer: URL(string: "https://www.pixiv.net/artworks/1"))
        let b = OLThumbnailRequest(url: resource, scopeID: "account-B-fixture", session: transport,
            referer: URL(string: "https://www.pixiv.net/artworks/2"))
        try expect(OLThumbnailRequest(url: resource).cacheURL == resource, "anonymous URL key changed")
        try expect(a.cacheURL != resource && a.cacheURL != b.cacheURL
            && !a.cacheURL.absoluteString.contains("account-A-fixture")
            && !a.cacheURL.absoluteString.contains("pixiv"), "scope key exposes source/session text or aliases another scope")
        let invalid = OLThumbnailRequest(url: resource, scopeID: "missing-transport")
        try expect(await cache.image(for: invalid, maxPixelSize: 256, priority: .visible) == nil,
            "scoped request used default transport")
        try expect(ControlledThumbnailProtocol.state.count(resource) == 0, "invalid transport reached network")

        let unaffected = Task { await cache.image(for: other, maxPixelSize: 256, priority: .visible) }
        try await eventually("unrelated request") { ControlledThumbnailProtocol.state.count(other) == 1 }
        ControlledThumbnailProtocol.state.deliver(other, data: data)
        try expect(await unaffected.value != nil, "anonymous image did not load")
        let first = Task { await cache.image(for: a, maxPixelSize: 256, priority: .prefetch) }
        try await eventually("scope A") { ControlledThumbnailProtocol.state.count(resource) == 1 }
        let joined = Task { await cache.image(for: a, maxPixelSize: 256, priority: .visible) }
        try await eventually("scope A shares producer") { await coordinator.consumerCount(a.cacheURL) == 2 }
        first.cancel()
        try expect(await first.value == nil, "scoped consumer did not cancel independently")
        ControlledThumbnailProtocol.state.deliver(resource, data: data)
        try expect(await joined.value != nil, "remaining scoped consumer lost result")
        let secondScope = Task { await cache.image(for: b, maxPixelSize: 256, priority: .visible) }
        try await eventually("scope B uses separate producer") { ControlledThumbnailProtocol.state.count(resource) == 2 }
        let pending = ControlledThumbnailProtocol.state.pendingRequests(resource)
        try expect(pending.first?.value(forHTTPHeaderField: "Referer") == b.referer?.absoluteString,
            "source Referer missing from explicit transport")
        ControlledThumbnailProtocol.state.deliver(resource, data: data)
        try expect(await secondScope.value != nil, "second scope failed")
        try expect(cache.readyImage(for: a, maxPixelSize: 256) != nil && cache.readyImage(for: b, maxPixelSize: 256) != nil,
            "scoped ready pixels missing")
        try expect(cache.readyImage(for: resource, maxPixelSize: 256) == nil, "scoped image leaked to anonymous URL key")
        try expect(await cache.image(for: a, maxPixelSize: 256, priority: .visible) != nil
            && ControlledThumbnailProtocol.state.count(resource) == 2, "scoped warm hit refetched")
        let aFile = await cache.hasDiskEntry(a.cacheURL), bFile = await cache.hasDiskEntry(b.cacheURL)
        try expect(aFile && bFile, "scoped raw data not persisted")
        let generation = await cache.publicationGeneration()
        await cache.invalidate(scopeID: "account-A-fixture")
        try expect(await cache.publicationGeneration() == generation, "scope invalidation cleared global generation")
        try expect(cache.readyImage(for: a, maxPixelSize: 256) == nil
            && cache.readyImage(for: b, maxPixelSize: 256) != nil
            && cache.readyImage(for: other, maxPixelSize: 256) != nil, "scope invalidation crossed sources")
        let oldRaw = await cache.cachedData(for: a.cacheURL)
        let oldFile = await cache.hasDiskEntry(a.cacheURL), survivingFile = await cache.hasDiskEntry(b.cacheURL)
        try expect(oldRaw == nil && !oldFile && survivingFile, "scope disk/raw invalidation crossed sources or left old data")

        await cache.suspendDecodeQueue(true)
        let staleDecode = Task { await cache.image(for: a, maxPixelSize: 512, priority: .visible) }
        try await eventually("scope A fresh producer") { ControlledThumbnailProtocol.state.count(resource) == 3 }
        ControlledThumbnailProtocol.state.deliver(resource, data: data)
        try await eventually("scope A suspended decode") { await cache.decodeAudit().requests == 1 }
        await cache.invalidate(scopeID: "account-A-fixture")
        try expect(await staleDecode.value == nil, "revoked scoped decode delivered pixels")
        await cache.suspendDecodeQueue(false)
        try expect(cache.readyImage(for: a, maxPixelSize: 512) == nil
            && cache.readyImage(for: b, maxPixelSize: 256) != nil, "stale decode republished or removed other scope")

        let staleNetwork = Task { await cache.image(for: a, maxPixelSize: 256, priority: .visible) }
        try await eventually("scope A pending network") { ControlledThumbnailProtocol.state.count(resource) == 4 }
        let stoppedBeforeInvalidation = ControlledThumbnailProtocol.state.count(resource, stopped: true)
        await cache.invalidate(scopeID: "account-A-fixture")
        try expect(await staleNetwork.value == nil, "scope network cancellation did not release consumer")
        try await eventually("scope transport cancelled") {
            ControlledThumbnailProtocol.state.count(resource, stopped: true) > stoppedBeforeInvalidation
        }
        try expect(cache.readyImage(for: b, maxPixelSize: 256) != nil, "scope network cancellation removed another scope")
        await cache.clearAll()
    }

    static func scopeIndexCompaction() async throws {
        let cache = OLThumbnailCache(requestCoordinator: coordinator())
        await cache.clearAll()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ControlledThumbnailProtocol.self]
        let transport = WallpaperNetworkSession(URLSession(configuration: config))
        defer { transport.retire() }
        let scope = "compaction-A-fixture", otherScope = "compaction-B-fixture"
        func scoped(_ name: String, _ id: String) -> OLThumbnailRequest {
            OLThumbnailRequest(url: url(name), scopeID: id, session: transport,
                referer: URL(string: "https://www.pixiv.net/"))
        }
        let original = scoped("compaction-original", scope)
        let neighbor = scoped("compaction-neighbor", otherScope)
        let anonymous = url("compaction-anonymous")
        let data = pngData(), freshData = pngData(width: 64, height: 36)
        await cache.seedScopedRaw(original, data: data)
        try expect(await cache.image(for: original, maxPixelSize: 256, priority: .visible) != nil,
            "first scoped pixel tier did not decode")
        try expect(await cache.image(for: original, maxPixelSize: 512, priority: .visible) != nil,
            "second scoped pixel tier did not decode")
        await cache.evictRawMemory(original.cacheURL)
        let fillers = (0..<600).map { scoped("compaction-filler-\($0)", scope) }
        await cache.compactScopeThroughRealStores(fillers, data: data)
        let audit = await cache.scopeAudit(scope, resource: original.cacheURL)
        try expect(audit.receipts <= 1 && !audit.contains,
            "scope raw receipts retained evicted history beyond the compaction threshold")
        let oldFiles = [original.cacheURL] + fillers.map(\.cacheURL)
        try expect(await cache.allDiskEntriesExist(oldFiles),
            "metadata compaction must not delete real disk entries")
        try expect(cache.readyImage(for: original, maxPixelSize: 256) != nil
            && cache.readyImage(for: original, maxPixelSize: 512) != nil,
            "raw receipt compaction unexpectedly discarded resident decoded tiers")

        await cache.seedScopedRaw(neighbor, data: data)
        try expect(await cache.image(for: neighbor, maxPixelSize: 256, priority: .visible) != nil,
            "neighbor scope did not warm")
        let generation = await cache.publicationGeneration()
        try expect(await cache.storeAndDecode(data: data, for: anonymous, maxPixelSize: 256,
            generation: generation) != nil, "anonymous source did not warm")
        await cache.suspendDecodeQueue(true)
        let lateRequest = fillers[0]
        let stale = Task { await cache.image(for: lateRequest, maxPixelSize: 1200, priority: .visible) }
        let survivor = Task { await cache.image(for: neighbor, maxPixelSize: 1200, priority: .visible) }
        try await eventually("two scoped decodes suspended") { await cache.decodeAudit().requests == 2 }
        await cache.invalidate(scopeID: scope)
        try expect(await stale.value == nil, "compacted scope invalidation retained its decode consumer")
        try expect(await cache.publicationGeneration() == generation,
            "compacted scope invalidation changed the anonymous clear epoch")
        try expect(await cache.noDiskEntriesExist(oldFiles),
            "scope namespace invalidation left disk files omitted from compacted metadata")
        try expect(cache.readyImage(for: original, maxPixelSize: 256) == nil
            && cache.readyImage(for: original, maxPixelSize: 512) == nil,
            "prefix removal left a resident pixel tier without a raw receipt")
        let remaining = await cache.decodeAudit()
        try expect(remaining.requests == 1 && cache.readyImage(for: neighbor, maxPixelSize: 256) != nil
            && cache.readyImage(for: anonymous, maxPixelSize: 256) != nil,
            "one scope invalidation removed an unrelated decode or ready image")
        let neighborFile = await cache.hasDiskEntry(neighbor.cacheURL)
        let anonymousFile = await cache.hasDiskEntry(anonymous)
        try expect(neighborFile && anonymousFile, "scope disk scan removed another source's original filename")

        // Reuse the same opaque scope and URL while its cancelled operation is
        // still queued. Only the new revision may publish its larger source.
        await cache.seedScopedRaw(lateRequest, data: freshData)
        let fresh = Task { await cache.image(for: lateRequest, maxPixelSize: 1200, priority: .visible) }
        try await eventually("replacement scope decode queued") { await cache.decodeAudit().requests == 2 }
        await cache.suspendDecodeQueue(false)
        try expect(await survivor.value != nil, "neighbor decode lost its consumer during another scope's retirement")
        let image = await fresh.value
        // The decoder sets NSImage.size from its decoded CGImage dimensions.
        // NSImage may expose a Retina representation with twice that width.
        try expect(image?.size == NSSize(width: 64, height: 36),
            "old scope decode replaced the new same-URL revision: size=\(String(describing: image?.size))")
        await cache.drainDecodeQueue()
        try expect(await cache.cachedData(for: lateRequest.cacheURL) == freshData,
            "cancelled scope decode overwrote the fresh raw publication")
        try expect(cache.readyImage(for: neighbor, maxPixelSize: 1200) != nil,
            "neighbor pixel tier failed to publish after the scope disk scan")

        await cache.suspendDecodeQueue(true)
        let cleared = Task { await cache.image(for: lateRequest, maxPixelSize: 1600, priority: .visible) }
        try await eventually("scoped clear decode queued") { await cache.decodeAudit().requests == 1 }
        await cache.clearAll()
        try expect(await cleared.value == nil, "clearAll retained a scoped decode consumer")
        try expect(await cache.scopeAudit(scope, resource: lateRequest.cacheURL).count == 0,
            "clearAll retained scope registration metadata")
        await cache.suspendDecodeQueue(false)
        await cache.drainDecodeQueue()
        try expect(cache.readyImage(for: lateRequest, maxPixelSize: 1200) == nil
            && cache.readyImage(for: lateRequest, maxPixelSize: 1600) == nil
            && cache.readyImage(for: neighbor, maxPixelSize: 1200) == nil,
            "clearAll or a late scoped decode revived cleared ready pixels")
        try expect(await cache.noDiskEntriesExist(oldFiles + [neighbor.cacheURL, anonymous]),
            "clearAll or a late scoped decode revived cleared disk namespaces")

        let decoded = DecodedThumbnailMemoryCache(countLimit: 3, totalCostLimit: 30)
        let sample = NSImage(size: NSSize(width: 1, height: 1))
        decoded.setObject(sample, forKey: "scope-A/one@256", cost: 10)
        decoded.setObject(sample, forKey: "scope-B/one@256", cost: 10)
        decoded.setObject(sample, forKey: "scope-A/one@512", cost: 10)
        decoded.removeObjects(withKeyPrefix: "scope-A/")
        decoded.setObject(sample, forKey: "scope-C/one@256", cost: 10)
        decoded.setObject(sample, forKey: "scope-C/two@256", cost: 10)
        try expect(decoded.object(forKey: "scope-A/one@256") == nil
            && decoded.object(forKey: "scope-A/one@512") == nil
            && decoded.object(forKey: "scope-B/one@256") != nil
            && decoded.object(forKey: "scope-C/one@256") != nil
            && decoded.object(forKey: "scope-C/two@256") != nil,
            "decoded prefix deletion damaged another namespace or retained deleted cost")
    }

    static func retiredTransport() async throws {
        let coordinator = coordinator(), cache = OLThumbnailCache(requestCoordinator: coordinator)
        await cache.clearAll()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ControlledThumbnailProtocol.self]
        let transport = WallpaperNetworkSession(URLSession(configuration: config))
        let queuedURL = url("retired-queued"), tintURL = url("retired-tint")
        let neighborURL = url("retired-neighbor-public"), data = pngData()
        let queuedRequest = OLThumbnailRequest(url: queuedURL, scopeID: "retired-account-fixture", session: transport,
            referer: URL(string: "https://www.pixiv.net/"))
        let tintRequest = OLThumbnailRequest(url: tintURL, scopeID: "retired-account-fixture", session: transport,
            referer: URL(string: "https://www.pixiv.net/"))
        let tint = ListThumbnailTintSource()
        tint.update(id: "retired-tint", assets: [tintRequest.cacheURL.absoluteString]) { completion in
            let task = Task {
                completion(await cache.image(for: tintRequest, maxPixelSize: 256, priority: .prefetch))
            }
            return { task.cancel() }
        }
        let delayedTint = tint.request!
        let scheduler = await coordinator.schedulerForAudit()
        let first = UUID(), second = UUID()
        await scheduler.occupy(first, priority: .visible)
        await scheduler.occupy(second, priority: .visible)
        let queued = Task { await cache.image(for: queuedRequest, maxPixelSize: 256, priority: .prefetch) }
        try await eventually("old scoped transport waits behind visible work") { await scheduler.auditState().3 == 1 }
        try expect(ControlledThumbnailProtocol.state.count(queuedURL) == 0, "queue boundary did not delay task creation")

        // Both old request values retain the same session-owned handle. Scope
        // cancellation/cache invalidation is deliberately absent: retirement at
        // the actual task-creation boundary must be sufficient to prevent a crash.
        transport.retire()
        await scheduler.vacate(first)
        await scheduler.vacate(second)
        try expect(await queued.value == nil, "retired request resumed from scheduler instead of cancelling")
        let tintImage: NSImage? = await withCheckedContinuation { continuation in
            _ = delayedTint.load { continuation.resume(returning: $0) }
        }
        try expect(tintImage == nil, "retained tint loader reused a retired session")
        try expect(ControlledThumbnailProtocol.state.count(queuedURL) == 0
            && ControlledThumbnailProtocol.state.count(tintURL) == 0,
            "retired captured requests reached HTTP")
        try expect(cache.readyImage(for: queuedRequest, maxPixelSize: 256) == nil
            && cache.readyImage(for: tintRequest, maxPixelSize: 256) == nil,
            "retired captured requests published pixels")

        let neighbor = Task { await cache.image(for: neighborURL, maxPixelSize: 256, priority: .visible) }
        try await eventually("neighbor source remains live") { ControlledThumbnailProtocol.state.count(neighborURL) == 1 }
        ControlledThumbnailProtocol.state.deliver(neighborURL, data: data)
        try expect(await neighbor.value != nil, "retirement blocked the adjacent public source")
        try expect(await scheduler.auditState() == (0, 0, 0, 0), "retired requests leaked scheduler permits")
        await cache.clearAll()
    }

    static func redirects() throws {
        let origin = URL(string: "https://i.pximg.net/example.jpg")!
        let policy = OLThumbnailRedirectPolicy(origin: origin)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: origin)
        let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var redirected: URLRequest?
        var request = URLRequest(url: URL(string: "https://unrelated.test/image.jpg")!)
        request.setValue("fixture-cookie", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer")
        policy.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected = $0 }
        try expect(redirected == nil, "cross-origin redirect forwarded authentication headers")
        request.url = URL(string: "https://i.pximg.net/next.jpg")!
        policy.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected = $0 }
        try expect(redirected?.url == request.url, "same-origin redirect was unnecessarily blocked")
    }
    static func main() async throws {
        try await leases()
        try await scheduler()
        try await decode()
        try await fullRequestEpoch()
        try await scopes()
        try await scopeIndexCompaction()
        try await retiredTransport()
        try redirects()
        let cache = OLThumbnailCache(requestCoordinator: coordinator())
        try await cache.diskReadContract()
        await cache.clearAll()
        print("{\"networkConsumerLeases\":true,\"pendingCancellationAndPromotion\":true,\"boundedCoalescedDecode\":true,\"fullRequestClearEpoch\":true,\"diskReadContract\":true,\"scopedTransportAndInvalidation\":true,\"scopedRedirectPolicy\":true,\"retiredScopedTransportAfterQueueAndTintDelay\":true}")
    }
}
