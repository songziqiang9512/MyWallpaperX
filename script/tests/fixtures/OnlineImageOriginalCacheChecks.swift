import Foundation

/// Pause only the filesystem copy leaf. The actual transfer owner chooses its
/// cache URL and publishes the real copied bytes through ImageIO and Store.
nonisolated final class OriginalCacheCopyProbe: @unchecked Sendable {
    static let shared = OriginalCacheCopyProbe()
    private let condition = NSCondition()
    private var source: URL?
    private var entered = false
    var hasEntered: Bool { condition.lock(); defer { condition.unlock() }; return entered }
    func arm(_ url: URL) { condition.lock(); source = url; entered = false; condition.unlock() }
    func release() { condition.lock(); source = nil; condition.broadcast(); condition.unlock() }
    func copyItem(at url: URL, to destination: URL) throws {
        condition.lock()
        if source == url {
            entered = true
            while source != nil { condition.wait() }
        }
        condition.unlock()
        try FileManager.default.copyItem(at: url, to: destination)
    }
}

extension OnlineImageLibraryHarness {
    static func originalCacheAsset(_ id: String) -> OnlineImageAsset {
        .init(id: .init(source: .wallhaven, artworkID: id), title: id,
              sourceURL: URL(string: "https://example.invalid/work/" + id)!,
              originalURL: URL(string: "https://example.invalid/original/" + id)!)
    }

    static func cacheOriginal(_ item: OnlineImageAsset, in value: OnlineImageLibrary) async throws -> URL {
        let expected = transfer.starts(item.id.artworkID) + 1
        let pending = Task { try await value.originalPreviewURL(item) }
        try await eventually("seed original " + item.id.artworkID) { transfer.starts(item.id.artworkID) == expected }
        transfer.finish(item.id.artworkID, bytes: png)
        return try await pending.value
    }

    static func clearOriginalPreviewCaches() async throws {
        let value = try await library("clear-original-previews")
        _ = await value.prepareWallhaven()
        let files = FileManager.default, probe = OriginalCacheCopyProbe.shared
        let copyItem = originalCacheAsset("clear-active-copy"), staleItem = originalCacheAsset("clear-unused-original")
        let copyURL = try await cacheOriginal(copyItem, in: value)
        let staleURL = try await cacheOriginal(staleItem, in: value)
        let publishedItem = originalCacheAsset("clear-published-download")
        let publishedRecord = try await save(publishedItem, in: value)
        let publishedURL = value.localURL(for: publishedRecord)!
        let temporaryRoot = files.temporaryDirectory.appendingPathComponent("MyWallpaperX-OriginalPreviews", isDirectory: true)
        try files.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let fallback = temporaryRoot.appendingPathComponent("clear-unused-fallback.img")
        try png.write(to: fallback)

        probe.arm(copyURL)
        defer { probe.release() }
        value.download(copyItem)
        try await eventually("download holds actual cached-file copy") { probe.hasEntered }
        let oldItem = originalCacheAsset("clear-cancelled-preview")
        transfer.ignoreCancel(for: oldItem.id.artworkID)
        var oldWasCancelled = false
        let oldPreview = Task {
            do { _ = try await value.originalPreviewURL(oldItem) }
            catch is CancellationError { oldWasCancelled = true }
            catch { }
        }
        try await eventually("old preview original in flight") { transfer.starts(oldItem.id.artworkID) == 1 }
        oldPreview.cancel()
        let clearing = value.clearOriginalPreviewCache(after: oldPreview)
        let newItem = originalCacheAsset("clear-new-preview")
        let nextPreview = Task { try await value.originalPreviewURL(newItem) }
        try await settle()
        check("cache-clear-joins-only-the-cancelled-preview-without-starting-the-new-one-early",
              transfer.cancels(oldItem.id.artworkID) == 1 && transfer.starts(newItem.id.artworkID) == 0
              && files.fileExists(atPath: staleURL.path) && files.fileExists(atPath: fallback.path))
        transfer.finish(oldItem.id.artworkID, bytes: png)
        await clearing.value
        try await eventually("new preview resumes after cache clear") { transfer.starts(newItem.id.artworkID) == 1 }
        check("cache-clear-removes-unused-originals-and-fallbacks-without-touching-published-downloads",
              oldWasCancelled && !files.fileExists(atPath: staleURL.path) && !files.fileExists(atPath: fallback.path)
              && value.record(for: publishedItem.id.reference) == publishedRecord && (try? Data(contentsOf: publishedURL)) == png)
        check("cache-clear-retains-the-real-download-copy-source-until-that-transfer-finishes",
              probe.hasEntered && files.fileExists(atPath: copyURL.path) && value.activeDownloadCount == 1)
        probe.release()
        try await drained(value, "cached copy across clear")
        check("download-copy-across-clear-publishes-original-bytes-without-an-extra-transfer",
              value.record(for: copyItem.id.reference).flatMap(value.localURL).flatMap { try? Data(contentsOf: $0) } == png
              && transfer.starts(copyItem.id.artworkID) == 1)
        transfer.finish(newItem.id.artworkID, bytes: png)
        let nextURL = try await nextPreview.value
        let warm = await value.cachedOriginalPreviewURL(for: newItem.id)
        check("clear-does-not-delete-the-new-preview-publication-after-the-barrier",
              warm == nextURL && (try? Data(contentsOf: nextURL)) == png)
        await value.clearOriginalPreviewCache().value
        check("a-later-clear-releases-formerly-active-cache-without-removing-either-download",
              !files.fileExists(atPath: copyURL.path) && !files.fileExists(atPath: nextURL.path)
              && files.fileExists(atPath: publishedURL.path) && value.record(for: copyItem.id.reference) != nil)
        try await clearDuringOriginalPublication(value)
        try await clearWhileOldScopeCopying()
    }

    static func clearDuringOriginalPublication(_ value: OnlineImageLibrary) async throws {
        let oldItem = originalCacheAsset("clear-publish-old"), nextItem = originalCacheAsset("clear-publish-next")
        transfer.ignoreCancel(for: oldItem.id.artworkID)
        let old = Task { do { _ = try await value.originalPreviewURL(oldItem) } catch { } }
        let next = Task { try await value.originalPreviewURL(nextItem) }
        try await eventually("two original acquisitions before clear") {
            transfer.starts(oldItem.id.artworkID) == 1 && transfer.starts(nextItem.id.artworkID) == 1
        }
        old.cancel()
        let clearing = value.clearOriginalPreviewCache(after: old)
        var published: URL?
        let receipt = Task { published = try await next.value }
        transfer.finish(nextItem.id.artworkID, bytes: png)
        try await settle()
        check("an-inflight-original-waits-at-final-cache-publication-while-clear-joins-the-old-request", published == nil)
        transfer.finish(oldItem.id.artworkID, bytes: png)
        await clearing.value
        try await receipt.value
        let cached = await value.cachedOriginalPreviewURL(for: nextItem.id)
        check("an-inflight-original-publishes-once-after-clear-and-remains-a-warm-hit",
              cached == published && cached != nil && cached.flatMap { try? Data(contentsOf: $0) } == png
              && transfer.starts(nextItem.id.artworkID) == 1)
    }

    static func clearWhileOldScopeCopying() async throws {
        let value = try await library("clear-original-old-scope"), probe = OriginalCacheCopyProbe.shared
        _ = await value.prepareWallhaven()
        let item = originalCacheAsset("clear-old-scope-copy")
        let original = try await cacheOriginal(item, in: value)
        probe.arm(original)
        defer { probe.release() }
        value.download(item)
        try await eventually("old-scope cached copy") { probe.hasEntered }
        try await value.setWallhavenKey("new-cache-scope")
        await value.clearOriginalPreviewCache().value
        check("scope-change-does-not-let-cache-clear-unlink-an-already-selected-copy-url",
              FileManager.default.fileExists(atPath: original.path))
        probe.release()
        try await drained(value, "cancelled old-scope copy")
        check("cancelled-old-scope-copy-ends-without-a-false-cache-clear-failure-or-publication",
              value.record(for: item.id.reference) == nil && value.errorMessage == nil)
        await value.clearOriginalPreviewCache().value
        check("finished-old-scope-copy-no-longer-pins-its-optional-cache",
              !FileManager.default.fileExists(atPath: original.path))
    }
}
