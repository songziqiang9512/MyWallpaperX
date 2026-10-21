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
    typealias Loader = @MainActor (URL, Int, SteamWorkshopPreviewLoadCancellation, @escaping (NSImage?) -> Void) -> Void
    private let load: Loader
    private var demands: [String: Demand] = [:]

    init(load: @escaping Loader = { url, pixels, cancellation, completion in
        steamWorkshopLoadPreviewImage(from: url, maxPixelSize: pixels, priority: .prefetch,
                                      cancellation: cancellation, completion: completion)
    }) { self.load = load }

    deinit { demands.values.forEach { $0.cancellation.cancel() } }

    func replace(with candidates: [Candidate], maxPixelSize: Int) {
        let wanted = Set(candidates.map(\.id))
        for id in Array(demands.keys) where !wanted.contains(id) {
            demands.removeValue(forKey: id)?.cancellation.cancel()
        }
        for candidate in candidates {
            let sources = steamWorkshopPreviewSources(item: candidate.item, record: candidate.record)
            guard let primary = sources.primary else {
                demands.removeValue(forKey: candidate.id)?.cancellation.cancel(); continue
            }
            let primaryKey = steamWorkshopPreviewStillKey(for: primary, maxPixelSize: maxPixelSize)
            let fallbackKey = sources.fallback.map { steamWorkshopPreviewStillKey(for: $0, maxPixelSize: maxPixelSize) }
            let identity = primaryKey + "|" + (fallbackKey ?? "")
            if let old = demands[candidate.id], old.identity == identity,
               old.readyKey.map({ SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: $0) != nil }) ?? true { continue }
            demands.removeValue(forKey: candidate.id)?.cancellation.cancel()
            guard candidate.startsIfMissing else { continue }
            let cancellation = SteamWorkshopPreviewLoadCancellation()
            demands[candidate.id] = Demand(identity: identity, cancellation: cancellation, readyKey: nil)
            let load = self.load
            load(primary, maxPixelSize, cancellation) { [weak self] image in
                guard !cancellation.cancelled else { return }
                if image != nil {
                    self?.recordReady(primaryKey, for: candidate.id, cancellation: cancellation)
                } else if let fallback = sources.fallback, fallback != primary, let fallbackKey {
                    load(fallback, maxPixelSize, cancellation) { [weak self] image in
                        if image != nil { self?.recordReady(fallbackKey, for: candidate.id, cancellation: cancellation) }
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
        demands.values.forEach { $0.cancellation.cancel() }
        demands.removeAll()
    }
}
