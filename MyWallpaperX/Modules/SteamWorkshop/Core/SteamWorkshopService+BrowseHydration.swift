import AppKit

extension SteamWorkshopService {
    func mergeBrowserItem(_ item: SteamWorkshopBrowserItem) {
        if let index = browserItems.firstIndex(where: { $0.id == item.id }) {
            browserItems[index] = item
        }
    }
}

/// A view owns these consumers, not the service's lifetime. Both Steam grids
/// use the exact card source decision and static pixel tier; hover stays separate.
@MainActor final class SteamWorkshopPreviewPrefetchController {
    struct Candidate {
        let id: String
        let item: SteamWorkshopBrowserItem
        let record: SteamWorkshopDownloadRecord?
        var startsIfMissing = true
    }
    private struct Demand {
        let identity: String
        let cancellation: SteamWorkshopPreviewLoadCancellation
        var readyKey: String?
    }
    private nonisolated struct Source: Equatable, Sendable {
        let id: String
        let primary: URL
        let fallback: URL?
        let pixels: Int
        let startsIfMissing: Bool
    }
    private nonisolated struct Prepared: Sendable {
        let source: Source
        let primaryKey: String
        let fallbackKey: String?
        var identity: String { primaryKey + "|" + (fallbackKey ?? "") }
    }
    private static let preparationQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.preview.prefetch-source", qos: .utility)
    typealias Loader = @MainActor (URL, Int, SteamWorkshopPreviewLoadCancellation, @escaping (NSImage?) -> Void) -> Void
    private let load: Loader
    private var demands: [String: Demand] = [:]
    private var desiredSources: [String: Source] = [:]
    private var pendingSources: [Source]?
    private var preparationIsRunning = false
    private var lifecycle: UInt64 = 0

    init(load: @escaping Loader = { url, pixels, cancellation, completion in
        steamWorkshopLoadPreviewImage(from: url, maxPixelSize: pixels, priority: .prefetch,
                                      cancellation: cancellation, completion: completion)
    }) { self.load = load }

    deinit { demands.values.forEach { $0.cancellation.cancel() } }

    func replace(with candidates: [Candidate], maxPixelSize: Int) {
        let sources = candidates.compactMap { candidate -> Source? in
            let urls = steamWorkshopPreviewSources(item: candidate.item, record: candidate.record)
            guard let primary = urls.primary else { return nil }
            return Source(id: candidate.id, primary: primary, fallback: urls.fallback,
                          pixels: maxPixelSize, startsIfMissing: candidate.startsIfMissing)
        }
        let previousSources = desiredSources
        desiredSources = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        // Cancel obsolete leases immediately, before asynchronous file checks.
        for id in Array(demands.keys) {
            let old = previousSources[id]
            let new = desiredSources[id]
            if new == nil || old?.primary != new?.primary || old?.fallback != new?.fallback || old?.pixels != new?.pixels {
                demands.removeValue(forKey: id)?.cancellation.cancel()
            }
        }
        pendingSources = sources
        prepareNextSources()
    }

    private func prepareNextSources() {
        guard !preparationIsRunning, let sources = pendingSources else { return }
        pendingSources = nil
        guard !sources.isEmpty else { return }
        preparationIsRunning = true
        let epoch = lifecycle
        Self.preparationQueue.async { [weak self] in
            let prepared = sources.map { source in
                Prepared(source: source,
                    primaryKey: steamWorkshopPreviewStillKey(for: source.primary, maxPixelSize: source.pixels),
                    fallbackKey: source.fallback.map { steamWorkshopPreviewStillKey(for: $0, maxPixelSize: source.pixels) })
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.preparationIsRunning = false
                if self.lifecycle == epoch { self.apply(prepared) }
                self.prepareNextSources()
            }
        }
    }

    private func apply(_ prepared: [Prepared]) {
        for prepared in prepared {
            let source = prepared.source
            guard desiredSources[source.id] == source else { continue }
            let candidateID = source.id
            let primary = source.primary
            let fallback = source.fallback
            let primaryKey = prepared.primaryKey
            let fallbackKey = prepared.fallbackKey
            let identity = prepared.identity
            if let old = demands[candidateID], old.identity == identity,
               old.readyKey.map({ SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: $0) != nil }) ?? true { continue }
            demands.removeValue(forKey: candidateID)?.cancellation.cancel()
            guard source.startsIfMissing else { continue }
            let cancellation = SteamWorkshopPreviewLoadCancellation()
            demands[candidateID] = Demand(identity: identity, cancellation: cancellation, readyKey: nil)
            let load = self.load
            load(primary, source.pixels, cancellation) { [weak self] image in
                guard !cancellation.cancelled else { return }
                if image != nil {
                    self?.recordReady(primaryKey, for: candidateID, cancellation: cancellation)
                } else if let fallback, fallback != primary, let fallbackKey {
                    load(fallback, source.pixels, cancellation) { [weak self] image in
                        if image != nil { self?.recordReady(fallbackKey, for: candidateID, cancellation: cancellation) }
                    }
                }
            }
        }
    }

    private func recordReady(_ key: String, for id: String, cancellation: SteamWorkshopPreviewLoadCancellation) {
        guard !cancellation.cancelled, demands[id]?.cancellation === cancellation else { return }
        demands[id]?.readyKey = key
    }

    func cancelAll() {
        lifecycle &+= 1
        desiredSources.removeAll()
        pendingSources = nil
        demands.values.forEach { $0.cancellation.cancel() }
        demands.removeAll()
    }
}
