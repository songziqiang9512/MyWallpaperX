import AppKit
import Foundation

struct OLDownloadedEntry { let localURL: URL; let thumbnailSourceKey: String? }
nonisolated private final class IdentityProbe: @unchecked Sendable {
    static let shared = IdentityProbe()
    private let lock = NSLock()
    private var calls: [(String, Bool)] = []
    func record(_ path: String) { lock.lock(); calls.append((path, Thread.isMainThread)); lock.unlock() }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return calls.filter { $0.0 == path }.count }
    var mainThreadCalls: Int { lock.lock(); defer { lock.unlock() }; return calls.filter(\.1).count }
}
private actor IdentityMediaGate {
    static let shared = IdentityMediaGate()
    var blocked = false
    var count = 0
    var waiting: [CheckedContinuation<NSImage?, Never>] = []
    let image: NSImage
    init() {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 40, bitsPerPixel: 32)!
        image = NSImage(size: NSSize(width: 10, height: 10)); image.addRepresentation(bitmap)
    }
    func frame() async -> NSImage? {
        count += 1
        if blocked { return await withCheckedContinuation { waiting.append($0) } }
        return image
    }
    func block() { blocked = true }
    func release() { blocked = false; let old = waiting; waiting.removeAll(); old.forEach { $0.resume(returning: image) } }
    var waitingCount: Int { waiting.count }
}
private enum Failure: Error { case assertion(String) }
@main private struct OnlineDownloadedIdentityHarness {
    @MainActor static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.assertion(message) }
    }
    @MainActor static func wait(_ message: String, _ condition: () async -> Bool) async throws {
        let until = Date().addingTimeInterval(4)
        while Date() < until {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Failure.assertion(message)
    }
    static func fingerprint(_ url: URL) async -> String { await Task.detached { OLDownloadedThumbnailStore.cacheKey(for: url) }.value }
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = directory.appendingPathComponent("replacement.mp4")
        let cache = OLDownloadedThumbnailStore.sharedCache
        let gate = IdentityMediaGate.shared
        try Data(repeating: 1, count: 10).write(to: source)
        let oldKey = await fingerprint(source)
        try Data(repeating: 2, count: 23).write(to: source, options: .atomic)
        let actualKey = await fingerprint(source)
        try expect(oldKey != actualKey, "fixture replacement must change source fingerprint")
        var result: (String, NSImage?)?
        OLDownloadedThumbnailStore.prefetch(.init(localURL: source, thumbnailSourceKey: oldKey),
            cancellation: ThumbnailCacheRequestCancellation()) { result = ($0, $1) }
        try await wait("replacement miss must complete") { result != nil }
        try expect(result?.0 == actualKey && result?.1 != nil && cache.cachedImage(forKey: oldKey) == nil
            && cache.cachedImage(forKey: actualKey) != nil, "scan hint published replacement pixels under the old key")

        let shared = directory.appendingPathComponent("shared.mp4")
        try Data(repeating: 3, count: 31).write(to: shared)
        let sharedKey = await fingerprint(shared)
        await gate.block()
        let near = ThumbnailCacheRequestCancellation()
        var nearDelivered = false
        OLDownloadedThumbnailStore.prefetch(.init(localURL: shared, thumbnailSourceKey: sharedKey), cancellation: near) { _, _ in nearDelivered = true }
        try await wait("prefetch producer must start") { await gate.waitingCount == 1 }
        let visible = ThumbnailCacheRequestCancellation()
        var visibleImage: NSImage?
        cache.loadImageAsync(forKey: sharedKey, priority: .visible, cancellation: visible,
            loader: { preconditionFailure("same identity started a second producer") }) { visibleImage = $0 }
        near.cancel()
        await gate.release()
        try await wait("visible consumer must survive prefetch cancellation") { visibleImage != nil }
        try expect(!nearDelivered && !visible.cancelled && cache.cachedImage(forKey: sharedKey) != nil,
            "cancelling one prefetch harmed the same-source visible consumer")

        let active = directory.appendingPathComponent("active.mp4")
        try Data(repeating: 4, count: 45).write(to: active)
        let activeOldKey = await fingerprint(active)
        await gate.block()
        let activeToken = ThumbnailCacheRequestCancellation()
        var staleDelivered = false
        OLDownloadedThumbnailStore.prefetch(.init(localURL: active, thumbnailSourceKey: activeOldKey), cancellation: activeToken) { _, _ in staleDelivered = true }
        try await wait("active source generation must begin") { await gate.waitingCount == 1 }
        try Data(repeating: 5, count: 57).write(to: active, options: .atomic)
        await gate.release()
        try await wait("source replaced during generation must cancel stale consumer") { activeToken.cancelled }
        try await Task.sleep(for: .milliseconds(50))
        try expect(!staleDelivered && cache.cachedImage(forKey: activeOldKey) == nil,
            "generation published stale-key pixels after source replacement")
        let activeNewKey = await fingerprint(active)
        var retry: (String, NSImage?)?
        OLDownloadedThumbnailStore.prefetch(.init(localURL: active, thumbnailSourceKey: activeOldKey),
            cancellation: ThumbnailCacheRequestCancellation()) { retry = ($0, $1) }
        try await wait("changed source must remain retryable") { retry != nil }
        try expect(retry?.0 == activeNewKey && retry?.1 != nil, "stale-key cancellation poisoned later replacement")

        await gate.block()
        var blockerDone = false
        cache.loadImageAsync(forKey: "generation-blocker", loader: { await gate.frame() }) { _ in blockerDone = true }
        try await wait("generation blocker must start") { await gate.waitingCount == 1 }
        let queued = directory.appendingPathComponent("queued.mp4")
        try Data(repeating: 6, count: 63).write(to: queued)
        let queuedKey = await fingerprint(queued)
        let before = IdentityProbe.shared.count(queued.path)
        let queuedToken = ThumbnailCacheRequestCancellation()
        OLDownloadedThumbnailStore.prefetch(.init(localURL: queued, thumbnailSourceKey: queuedKey), cancellation: queuedToken) { _, _ in staleDelivered = true }
        try await wait("queued key resolution must run") { IdentityProbe.shared.count(queued.path) > before }
        try await Task.sleep(for: .milliseconds(60))
        let generatedBefore = await gate.count
        try Data(repeating: 7, count: 79).write(to: queued, options: .atomic)
        await gate.release()
        try await wait("queued replacement must cancel before sampling") { queuedToken.cancelled && blockerDone }
        let generatedAfter = await gate.count
        try expect(generatedBefore == generatedAfter && cache.cachedImage(forKey: queuedKey) == nil,
            "stale queued identity still sampled new source or published wrong-key output")

        let checksBefore = IdentityProbe.shared.count(source.path)
        try FileManager.default.removeItem(at: source)
        var readyResult: NSImage?
        OLDownloadedThumbnailStore.prefetch(.init(localURL: source, thumbnailSourceKey: actualKey),
            cancellation: ThumbnailCacheRequestCancellation()) { _, image in readyResult = image }
        try expect(readyResult != nil && IdentityProbe.shared.count(source.path) == checksBefore,
            "prepared ready-memory hit unnecessarily inspected the filesystem")
        try expect(IdentityProbe.shared.mainThreadCalls == 0, "prefetch performed source validation on the main thread")
        print("{\"scanReplacementUsesActualIdentity\":true,\"sameKeyVisibleSurvivesPrefetchCancel\":true,\"activeReplacementRejectsStaleAndRetries\":true,\"queuedReplacementRejectsBeforeSampling\":true,\"readyHintAvoidsFilesystem\":true,\"prefetchFingerprintOffMain\":true}")
    }
}
