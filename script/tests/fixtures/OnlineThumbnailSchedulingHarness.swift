import AppKit
import Foundation

// Only maintenance trimming is excluded. Request actors, decoder, memory owner,
// source publication, cancellation handlers and permits are production code.
nonisolated enum ThumbnailCache {
    static func trimDiskCache(directory: URL, sizeLimit: UInt64) -> Bool { false }
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
        return OLThumbnailRequestCoordinator(session: URLSession(configuration: config))
    }
    static func pngData() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
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
    static func main() async throws {
        try await leases()
        try await scheduler()
        try await decode()
        try await fullRequestEpoch()
        print("{\"networkConsumerLeases\":true,\"pendingCancellationAndPromotion\":true,\"boundedCoalescedDecode\":true,\"fullRequestClearEpoch\":true}")
    }
}
