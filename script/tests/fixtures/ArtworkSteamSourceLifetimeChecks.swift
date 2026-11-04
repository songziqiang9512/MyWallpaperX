import AppKit
import CryptoKit
import ImageIO

// Only catalog lookup and URL choice are leaves. The extracted liveLoader body,
// complete Artwork owner, PreviewState, source API and cache remain production.
final class SteamWorkshopService { var downloads: [SteamWorkshopDownloadRecord] = [] }
struct SteamWorkshopBrowserItem { let id: String; let primary: URL?; let fallback: URL? }
struct SteamWorkshopDownloadRecord {
    let id: String
    let displayItem: SteamWorkshopBrowserItem?
    let videoURL: URL?
}
enum SteamWorkshopDownloadGridSupport {
    static func fallbackDisplayItem(for row: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        .init(id: row.id, primary: nil, fallback: nil)
    }
}
func steamWorkshopPreviewSources(item: SteamWorkshopBrowserItem, record: SteamWorkshopDownloadRecord?) -> (primary: URL?, fallback: URL?) {
    (item.primary, item.fallback)
}

@MainActor enum ArtworkSteamObservation {
    final class State {
        weak var value: SteamWorkshopPreviewState?
        init(_ value: SteamWorkshopPreviewState) { self.value = value }
    }
    final class Pixels {
        weak var image: NSImage?
        let bytes: Int
        init(_ image: NSImage) {
            self.image = image
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            bytes = cg.bytesPerRow * cg.height
        }
    }
    static var states: [State] = []
    static var sources: [String: Pixels] = [:]
    static func record(_ image: NSImage, source: URL) { sources[source.absoluteString] = Pixels(image) }
    static func live(_ entries: [Pixels]) -> [String: Int] {
        let held = entries.filter { $0.image != nil }
        return ["alive": held.count, "bytes": held.reduce(0) { $0 + $1.bytes }]
    }
}

@main @MainActor enum ArtworkSteamSourceLifetimeChecks {
    static let cache = SteamWorkshopPreviewImageCache.shared
    static func pump(_ condition: () -> Bool, timeout: TimeInterval = 12) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            autoreleasepool { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        }
        return condition()
    }
    static func drain() {
        for _ in 0..<4 { autoreleasepool { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) } }
    }
    static func clear() -> Bool {
        var done = false
        cache.clearAll { done = true }
        let result = pump { done }; drain(); return result
    }
    static func item(_ id: String, revision: String = "1") -> WallpaperContentItem {
        let reference = WallpaperReference(provider: .steamWorkshop, sourceID: id)
        var metadata = WallpaperContentMetadata(); metadata.resourceRevision = revision
        return .init(reference: reference, providerReference: reference, locator: .init(path: "/" + id), title: id,
            kind: .video, publishedAvailability: .available, capabilities: [.inspect, .play], metadata: metadata,
            acquisition: .idle, update: .idle, aliases: [])
    }
    static func digest(_ image: NSImage?) -> String? {
        guard let pixels = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bytes = pixels.dataProvider?.data else { return nil }
        return SHA256.hash(data: bytes as Data).map { String(format: "%02x", $0) }.joined()
    }
    static func record(_ id: String, _ primary: URL?, fallback: URL? = nil, video: URL? = nil) -> SteamWorkshopDownloadRecord {
        .init(id: id, displayItem: .init(id: id, primary: primary, fallback: fallback), videoURL: video)
    }

    static func terminalCases(root: URL, remote: URL, checks: inout [String: Bool]) throws {
        let coldURL = root.appendingPathComponent("cold.jpg")
        try artworkEncodedSourceData(97).write(to: coldURL)
        let service = SteamWorkshopService()
        service.downloads = [record("cold", coldURL), record("fallback", root.appendingPathComponent("missing.jpg"), fallback: coldURL),
            record("nil", nil, video: root.appendingPathComponent("missing.mp4")), record("retry", remote.appendingPathComponent("retry.jpg"))]
        let loader = makeActualSteamArtworkLoader(service)
        var direct: NSImage?, callbacks = 0, returned = false, asynchronous = false, onMain = true
        var cancel: (() -> Void)? = loader(item("cold")) { image in
            callbacks += 1; direct = image; asynchronous = returned; onMain = Thread.isMainThread && onMain
        }
        returned = true
        checks["cold-source-completes-asynchronously-once-on-main"] = pump { direct != nil } && asynchronous && callbacks == 1 && onMain
        let directDigest = digest(direct)
        checks["direct-image-consumer-keeps-its-necessary-pixels-after-clear"] = clear() && direct != nil && digest(direct) == directDigest
        direct = nil; drain()
        checks["completed-direct-state-does-not-keep-unconsumed-pixels"] = ArtworkSteamObservation.sources[coldURL.absoluteString]?.image == nil
        cancel?(); cancel = nil

        var fallback: NSImage?, fallbackCallbacks = 0
        cancel = loader(item("fallback")) { fallback = $0; fallbackCallbacks += 1 }
        checks["failed-primary-falls-through-to-real-image-source"] = pump { fallback != nil } && fallbackCallbacks == 1
            && digest(fallback) == directDigest
        fallback = nil; cancel?(); cancel = nil

        let synchronous = WallpaperLibraryArtworkProvider(loader: loader), syncID = UUID(), syncDemand = UUID()
        let syncEntry = WallpaperPlaylistDirectoryEntry(id: syncID, name: "Reentrant warm", count: 1, coverReference: item("cold").reference)
        var syncImages = 0, syncEmpty = false
        synchronous.onCoversChanged = { [weak synchronous] covers in
            syncEmpty = covers.isEmpty
            if covers[syncID]?.image != nil {
                syncImages += 1
                synchronous?.setDemand(sourceToken: syncDemand, playlistIDs: [])
            }
        }
        synchronous.update(entries: [syncEntry]) { _ in [item("cold")] }
        synchronous.setDemand(sourceToken: syncDemand, playlistIDs: [syncID])
        drain()
        checks["synchronous-warm-publish-can-reentrantly-remove-last-cover-demand"] = syncImages == 1 && syncEmpty
            && ArtworkSteamObservation.states.last?.value == nil

        var nilCallbacks = 0
        cancel = loader(item("nil")) { _ in nilCallbacks += 1 }
        let unavailable = ArtworkSteamObservation.states.last!
        checks["nil-video-fallback-keeps-terminal-unavailable-state-until-cancel"] = pump { unavailable.value?.placeholder == .unavailable }
            && unavailable.value?.requestedPixelSize == 256 && nilCallbacks == 0
        cancel?(); cancel = nil; drain()
        checks["unavailable-state-releases-on-last-cancel"] = unavailable.value == nil

        var retry: NSImage?, retryCallbacks = 0
        cancel = loader(item("retry")) { retry = $0; retryCallbacks += 1 }
        let retryState = ArtworkSteamObservation.states.last!
        checks["remote-failure-keeps-state-and-request-for-existing-retry"] = pump { retryState.value?.placeholder == .retrying }
            && retryState.value?.requestedPixelSize == 256 && retryCallbacks == 0
        checks["real-remote-retry-eventually-delivers-once"] = pump { retry != nil } && retryCallbacks == 1
        retry = nil; cancel?(); cancel = nil

        // Missing video completion is dispatched asynchronously by the real
        // pipeline, giving cancellation a deterministic late callback.
        var lateCallbacks = 0
        cancel = loader(item("nil")) { _ in lateCallbacks += 1 }
        let late = ArtworkSteamObservation.states.last!
        checks["pending-state-is-held-before-last-consumer-cancels"] = late.value?.requestedPixelSize == 256
            && late.value?.placeholder == .loading
        cancel?(); cancel = nil; drain()
        checks["cancelled-real-video-callback-cannot-deliver-or-resurrect-state"] = lateCallbacks == 0 && late.value == nil

        _ = clear()
        var reentrantCallbacks = 0
        cancel = loader(item("cold")) { image in
            if image != nil { reentrantCallbacks += 1; cancel?(); cancel = nil }
        }
        checks["async-success-allows-reentrant-consumer-cancellation"] = pump { reentrantCallbacks == 1 }
        drain()
        checks["reentrant-cancel-does-not-redeliver-nil-or-late-image"] = reentrantCallbacks == 1
        cancel?(); cancel = nil

        // Match the tint consumer's synchronous CGImage handoff, then run the
        // actual sampler after the NSImage/cache owners have relinquished it.
        _ = clear()
        var tintPixels: CGImage?
        cancel = loader(item("cold")) { image in tintPixels = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let tintReady = pump { tintPixels != nil }
        _ = clear()
        checks["tint-cgimage-handoff-survives-state-and-cache-release"] = tintReady && tintPixels.flatMap(ListThumbnailTintSampler.average) != nil
        checks["tint-source-nsimage-is-not-held-after-cgimage-handoff"] = ArtworkSteamObservation.sources[coldURL.absoluteString]?.image == nil
        tintPixels = nil; cancel?(); cancel = nil
        _ = clear(); drain()
    }

    static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTWORK_STEAM_ROOT"]!)
        let remote = URL(string: ProcessInfo.processInfo.environment["ARTWORK_STEAM_REMOTE"]!)!
        var checks: [String: Bool] = [:]
        let service = SteamWorkshopService()
        let contents = Dictionary(uniqueKeysWithValues: (0..<96).map { index in (item(String(index)).reference, item(String(index))) })
        let entries = (0..<96).map { index in
            WallpaperPlaylistDirectoryEntry(id: UUID(), name: "Steam \(index)", count: 1, coverReference: item(String(index)).reference)
        }
        service.downloads = (0..<96).map { record(String($0), root.appendingPathComponent("cover-\($0).jpg")) }
        let provider = WallpaperLibraryArtworkProvider(loader: makeActualSteamArtworkLoader(service))
        var rendered: [UUID: WallpaperPlaylistArtwork] = [:], publications = 0
        provider.onCoversChanged = { rendered = $0; publications += 1 }
        provider.update(entries: entries) { refs in refs.compactMap { contents[$0] } }
        let demand = UUID()
        var visible = Set<UUID>(), synchronous = true, warm = true
        for index in 0..<96 {
            let url = root.appendingPathComponent("cover-\(index).jpg")
            try artworkEncodedSourceData(index).write(to: url)
            var ready = false
            steamWorkshopLoadPreviewImage(from: url, maxPixelSize: 800, priority: .prefetch) { ready = $0 != nil }
            warm = pump { ready } && warm
            autoreleasepool {
                visible.insert(entries[index].id)
                provider.setDemand(sourceToken: demand, playlistIDs: visible)
                synchronous = rendered[entries[index].id]?.image != nil && synchronous
            }
        }
        drain()
        checks["ninety-six-larger-warm-images-are-borrowed-synchronously-by-real-artwork"] = warm && synchronous && rendered.count == 96
        checks["warm-borrow-does-not-create-redundant-256-cache-aliases"] = (0..<96).allSatisfy { index in
            cache.cachedImage(forKey: steamWorkshopPreviewStillKey(for: root.appendingPathComponent("cover-\(index).jpg"), maxPixelSize: 256)) == nil
        }
        let sources = (0..<96).compactMap { ArtworkSteamObservation.sources[root.appendingPathComponent("cover-\($0).jpg").absoluteString] }
        let outputs = autoreleasepool { entries.compactMap { rendered[$0.id]?.image.map(ArtworkSteamObservation.Pixels.init) } }
        let expected = entries.map { digest(rendered[$0.id]?.image) }
        let readySources = ArtworkSteamObservation.live(sources)
        checks["completed-steam-cover-state-allows-real-lru-eviction"] = sources.count == 96 && readySources["alive"]! < 96
        checks["cache-clear-completes"] = clear()
        let clearedSources = ArtworkSteamObservation.live(sources), clearedOutputs = ArtworkSteamObservation.live(outputs)
        checks["cache-clear-releases-all-unconsumed-steam-source-images"] = clearedSources["alive"] == 0
        checks["independent-square-output-pixels-survive-source-release"] = expected.allSatisfy { $0 != nil }
            && zip(entries, expected).allSatisfy { digest(rendered[$0.0.id]?.image) == $0.1 } && clearedOutputs["alive"] == 96
        let stable = publications
        provider.setDemand(sourceToken: demand, playlistIDs: visible)
        checks["same-visible-demand-keeps-composed-output-without-new-loader"] = publications == stable && ArtworkSteamObservation.states.count == 96
        provider.setDemand(sourceToken: demand, playlistIDs: [])
        drain()
        let retiredSources = ArtworkSteamObservation.live(sources), retiredOutputs = ArtworkSteamObservation.live(outputs)
        checks["last-cover-demand-releases-all-original-and-composed-images"] = retiredSources["alive"] == 0
            && retiredOutputs["alive"] == 0 && ArtworkSteamObservation.states.allSatisfy { $0.value == nil }

        try terminalCases(root: root, remote: remote, checks: &checks)
        drain()
        checks["all-terminal-consumers-retire-with-no-state-or-source-images"] = ArtworkSteamObservation.states.allSatisfy { $0.value == nil }
            && ArtworkSteamObservation.sources.values.allSatisfy { $0.image == nil }
        let resource: [String: Any] = ["inputCount": 96, "readySources": readySources, "clearedSources": clearedSources,
            "clearedOutputs": clearedOutputs, "retiredSources": retiredSources, "retiredOutputs": retiredOutputs,
            "composedPixelDigests": expected.map { $0 ?? "missing" }]
        print(String(data: try JSONSerialization.data(withJSONObject: ["checks": checks, "resource": resource], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
