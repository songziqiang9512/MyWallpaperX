import AppKit
import Foundation

struct PixabayDownloadedEntry { let localURL: URL; let thumbnailSourceKey: String? }
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
@main private struct PixabayDownloadedIdentityHarness {
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
    static func fingerprint(_ url: URL) async -> String { await Task.detached { PixabayDownloadedThumbnailStore.cacheKey(for: url) }.value }
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = directory.appendingPathComponent("replacement.mp4")
        let cache = PixabayDownloadedThumbnailStore.sharedCache
        let gate = IdentityMediaGate.shared
        try Data(repeating: 1, count: 10).write(to: source)
        let oldKey = await fingerprint(source)
        try Data(repeating: 2, count: 23).write(to: source, options: .atomic)
        let actualKey = await fingerprint(source)
        try expect(oldKey != actualKey, "fixture replacement must change source fingerprint")
        var result: (String, NSImage?)?
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: source, thumbnailSourceKey: oldKey),
            priority: .prefetch, cancellation: ThumbnailCacheRequestCancellation()) { result = ($0, $1) }
        try await wait("replacement miss must complete") { result != nil }
        try expect(result?.0 == actualKey && result?.1 != nil && cache.cachedImage(forKey: oldKey) == nil
            && cache.cachedImage(forKey: actualKey) != nil, "scan hint published replacement pixels under the old key")

        let shared = directory.appendingPathComponent("shared.mp4")
        try Data(repeating: 3, count: 31).write(to: shared)
        let sharedKey = await fingerprint(shared)
        await gate.block()
        let near = ThumbnailCacheRequestCancellation()
        var nearDelivered = false
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: shared, thumbnailSourceKey: sharedKey), priority: .prefetch, cancellation: near) { _, _ in nearDelivered = true }
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
        var staleResults: [(String, NSImage?)] = []
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: active, thumbnailSourceKey: activeOldKey), priority: .prefetch, cancellation: activeToken) { staleResults.append(($0, $1)) }
        try await wait("active source generation must begin") { await gate.waitingCount == 1 }
        try Data(repeating: 5, count: 57).write(to: active, options: .atomic)
        await gate.release()
        try await wait("source replaced during generation must finish the active consumer") { staleResults.count == 1 }
        try expect(!activeToken.cancelled && staleResults[0].0 == activeOldKey && staleResults[0].1 == nil
            && !cache.hasCachedResult(forKey: activeOldKey),
            "source replacement must finish once with nil, without pixels or a false negative cache")
        let activeNewKey = await fingerprint(active)
        var retry: (String, NSImage?)?
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: active, thumbnailSourceKey: activeOldKey),
            priority: .prefetch, cancellation: ThumbnailCacheRequestCancellation()) { retry = ($0, $1) }
        try await wait("changed source must remain retryable") { retry != nil }
        try expect(retry?.0 == activeNewKey && retry?.1 != nil, "stale-key result poisoned later replacement")

        await gate.block()
        var blockerDone = false
        cache.loadImageAsync(forKey: "generation-blocker", loader: { await gate.frame() }) { _ in blockerDone = true }
        try await wait("generation blocker must start") { await gate.waitingCount == 1 }
        let queued = directory.appendingPathComponent("queued.mp4")
        try Data(repeating: 6, count: 63).write(to: queued)
        let queuedKey = await fingerprint(queued)
        let before = IdentityProbe.shared.count(queued.path)
        let queuedToken = ThumbnailCacheRequestCancellation()
        var queuedResults: [(String, NSImage?)] = []
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: queued, thumbnailSourceKey: queuedKey), priority: .prefetch, cancellation: queuedToken) { queuedResults.append(($0, $1)) }
        try await wait("queued key resolution must run") { IdentityProbe.shared.count(queued.path) > before }
        try await Task.sleep(for: .milliseconds(60))
        let generatedBefore = await gate.count
        try Data(repeating: 7, count: 79).write(to: queued, options: .atomic)
        await gate.release()
        try await wait("queued replacement must terminate before sampling") { queuedResults.count == 1 && blockerDone }
        let generatedAfter = await gate.count
        try expect(!queuedToken.cancelled && queuedResults[0].0 == queuedKey && queuedResults[0].1 == nil
            && generatedBefore == generatedAfter && !cache.hasCachedResult(forKey: queuedKey),
            "stale queued identity sampled a new source, failed to finish or cached a false failure")

        let checksBefore = IdentityProbe.shared.count(source.path)
        let framesBeforeWarm = await gate.count
        var readyResult: NSImage?
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: source, thumbnailSourceKey: actualKey),
            priority: .prefetch, cancellation: ThumbnailCacheRequestCancellation()) { _, image in readyResult = image }
        try await wait("current warm key must complete") { readyResult != nil }
        let framesAfterWarm = await gate.count
        try expect(IdentityProbe.shared.count(source.path) == checksBefore + 1 && framesAfterWarm == framesBeforeWarm,
            "warm current source must resolve one live key without another AV generation")

        try Data(repeating: 8, count: 91).write(to: source, options: .atomic)
        let warmReplacementKey = await fingerprint(source)
        let beforeWarmReplacement = IdentityProbe.shared.count(source.path)
        var warmReplacement: (String, NSImage?)?
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: source, thumbnailSourceKey: actualKey),
            priority: .visible, cancellation: ThumbnailCacheRequestCancellation()) { warmReplacement = ($0, $1) }
        try await wait("warm old hint must resolve the replacement") { warmReplacement != nil }
        try expect(warmReplacement?.0 == warmReplacementKey && warmReplacement?.0 != actualKey && warmReplacement?.1 != nil,
            "a warm old scan hint bypassed the current file identity")
        try expect(IdentityProbe.shared.count(source.path) == beforeWarmReplacement + 3,
            "cold replacement must use only admission plus original before/after generation boundaries")
        let warmPrefetchReads = IdentityProbe.shared.count(source.path)
        let warmPrefetchFrames = await gate.count
        var warmPrefetch: (String, NSImage?)?
        PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: source, thumbnailSourceKey: actualKey),
            priority: .prefetch, cancellation: ThumbnailCacheRequestCancellation()) { warmPrefetch = ($0, $1) }
        try await wait("prefetch must share the same current identity semantics") { warmPrefetch != nil }
        let finalFrames = await gate.count
        try expect(warmPrefetch?.0 == warmReplacementKey && IdentityProbe.shared.count(source.path) == warmPrefetchReads + 1
            && finalFrames == warmPrefetchFrames, "priority changed live identity or re-generated a current warm image")
        let failedKey = "owned-failed-\(UUID().uuidString)"
        var failedTerminals = 0
        cache.loadImageAsync(forKey: failedKey, loader: { nil }) { image in
            precondition(image == nil); failedTerminals += 1
        }
        try await wait("real decode nil must cache its terminal conclusion") { failedTerminals == 1 }
        try expect(cache.hasCachedResult(forKey: failedKey) && cache.cachedImage(forKey: failedKey) == nil,
            "the original negative cache must count as a warm terminal conclusion")
        cache.loadImageAsync(forKey: failedKey, loader: { preconditionFailure("negative cache must not regenerate") }) { image in
            precondition(image == nil); failedTerminals += 1
        }
        try expect(failedTerminals == 2 && cache.hasCachedResult(forKey: failedKey), "cached failure did not finish without work")
        cache.remove(forKey: failedKey)
        try expect(!cache.hasCachedResult(forKey: failedKey), "single-key invalidation retained its old negative conclusion")
        var recoveredImage: NSImage?
        cache.loadImageAsync(forKey: failedKey, loader: { await gate.frame() }) { recoveredImage = $0 }
        try await wait("explicitly invalidated failure must remain retryable") { recoveredImage != nil }
        try expect(cache.hasCachedResult(forKey: failedKey), "a recovered image must be a warm original-cache conclusion")
        try expect(IdentityProbe.shared.mainThreadCalls == 0, "downloaded producer performed source validation on the main thread")
        print("{\"scanReplacementUsesActualIdentity\":true,\"sameKeyVisibleSurvivesPrefetchCancel\":true,\"activeReplacementFinishesUncachedAndRetries\":true,\"queuedReplacementFinishesBeforeSampling\":true,\"currentWarmKeyResolvesOnceWithoutAV\":true,\"warmOldHintUsesCurrentSource\":true,\"prefetchAndVisibleShareLiveIdentity\":true,\"cachedFailureAndSingleKeyInvalidationUseOriginalResult\":true,\"fingerprintOffMain\":true}")
    }
}
