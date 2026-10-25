import AppKit
import Foundation

/// 视频库缩略图共享缓存，模式与 SILThumbnailStore 一致：
/// NSCache 内存缓存 + in-flight 去重 + 磁盘层都由 ThumbnailCache 承担。
nonisolated enum VideoLibraryThumbnailStore {
    static let sharedCache = ThumbnailCache(
        label: "com.mywallpaper.videolibrary.thumbnail",
        countLimit: 360,
        // 网格 + Inspector 共用，128MB 封顶防止长会话膨胀（预算总表见 ThumbnailCache.init 注释）
        totalCostLimit: 128 * 1024 * 1024,
        namespace: "videolibrary"
    )
}

final class AppKitThumbnailProvider {
    private let wallpaperManager: WallpaperManager
    private let cache = VideoLibraryThumbnailStore.sharedCache
    private let decodeQueue = DispatchQueue(
        label: "com.mywallpaper.videolibrary.thumbnail.provider",
        qos: .userInitiated
    )

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
    }

    private struct Prefetch {
        let path: String
        let thumbnailPath: String?
        let cancellation: ThumbnailCacheRequestCancellation
        var readyKey: String?
    }
    private var prefetches: [Data: Prefetch] = [:]

    private final class VisiblePreview {
        let wallpaper: VideoWallpaper
        let cancellation = ThumbnailCacheRequestCancellation()
        var isChecking = false
        init(_ wallpaper: VideoWallpaper) { self.wallpaper = wallpaper }
    }
    private var visiblePreviews: [Data: VisiblePreview] = [:]

    deinit {
        prefetches.values.forEach { $0.cancellation.cancel() }
        visiblePreviews.values.forEach { $0.cancellation.cancel() }
    }

    /// Visibility grants this provider permission to repair its derived asset.
    /// Repeated geometry/state input retains the same lease and does no I/O.
    func updateVisiblePreviewDemand(with wallpapers: [VideoWallpaper]) {
        let wanted = Set(wallpapers.map { Data($0.id.utf8) })
        for id in Array(visiblePreviews.keys) where !wanted.contains(id) {
            visiblePreviews.removeValue(forKey: id)?.cancellation.cancel()
        }
        for wallpaper in wallpapers {
            let id = Data(wallpaper.id.utf8)
            if let old = visiblePreviews[id], old.wallpaper.path == wallpaper.path,
               old.wallpaper.thumbnailPath == wallpaper.thumbnailPath { continue }
            visiblePreviews.removeValue(forKey: id)?.cancellation.cancel()
            let demand = VisiblePreview(wallpaper)
            visiblePreviews[id] = demand
            checkVisiblePreview(demand, identity: id)
        }
    }

    /// Catalog's existing visible-source cadence can request another check.
    /// This does not own a timer or broaden the current visible scope.
    func repairVisiblePreviews() {
        for (id, demand) in visiblePreviews { checkVisiblePreview(demand, identity: id) }
    }

    private func checkVisiblePreview(_ demand: VisiblePreview, identity: Data) {
        guard !demand.isChecking, !demand.cancellation.cancelled else { return }
        demand.isChecking = true
        let manager = wallpaperManager
        let snapshot = demand.wallpaper
        let cancellation = demand.cancellation
        decodeQueue.async { [weak self, weak demand] in
            guard !cancellation.cancelled else { return }
            let exists = manager.normalizedSourcePathExists(snapshot.path)
            let needsPreview = exists && manager.resolvedThumbnailPath(for: snapshot) == nil
            DispatchQueue.main.async { [weak self, weak demand] in
                guard let self, let demand else { return }
                demand.isChecking = false
                guard !cancellation.cancelled, self.visiblePreviews[identity] === demand, needsPreview,
                      let current = manager.wallpapers.first(where: { $0.id.utf8.elementsEqual(snapshot.id.utf8) }),
                      current.path == snapshot.path, current.thumbnailPath == snapshot.thumbnailPath else { return }
                manager.ensurePreviewAssetsForWallpaper(current)
            }
        }
    }

    @discardableResult
    func loadThumbnail(for wallpaper: VideoWallpaper, priority: ThumbnailCacheRequestPriority = .visible,
                       completion: @escaping (NSImage?) -> Void) -> ThumbnailCacheRequestCancellation {
        let cancellation = ThumbnailCacheRequestCancellation()
        loadThumbnail(for: wallpaper, priority: priority, cancellation: cancellation) { image, _ in completion(image) }
        return cancellation
    }

    private func loadThumbnail(for wallpaper: VideoWallpaper, priority: ThumbnailCacheRequestPriority,
                               cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (NSImage?, String?) -> Void) {
        decodeQueue.async { [weak self] in
            guard let self, !cancellation.cancelled else { return }
            // The derived asset must remain valid after clear/rebuild. A source
            // video path alone cannot identify a reusable thumbnail.
            guard let thumbPath = self.wallpaperManager.resolvedThumbnailPath(for: wallpaper) else {
                DispatchQueue.main.async { if !cancellation.cancelled { completion(nil, nil) } }
                return
            }
            guard !cancellation.cancelled else { return }
            self.cache.load(forKey: thumbPath, priority: priority, cancellation: cancellation, loader: {
                NSImage(contentsOfFile: thumbPath)
            }, completion: { image in
                DispatchQueue.main.async { if !cancellation.cancelled { completion(image, thumbPath) } }
            })
        }
    }

    /// A grid owns one desired set. Removed consumers release their lease;
    /// another visible consumer of the same derived path remains unaffected.
    func replacePrefetch(with wallpapers: [VideoWallpaper], retainingVisible visible: [VideoWallpaper] = []) {
        let wanted = Set((wallpapers + visible).map { Data($0.id.utf8) })
        for id in Array(prefetches.keys) where !wanted.contains(id) { prefetches.removeValue(forKey: id)?.cancellation.cancel() }
        for (wallpaper, startsIfMissing) in wallpapers.map({ ($0, true) }) + visible.map({ ($0, false) }) {
            let identity = Data(wallpaper.id.utf8)
            if let old = prefetches[identity], old.path == wallpaper.path,
               old.thumbnailPath == wallpaper.thumbnailPath,
               old.readyKey.map({ cache.cachedImage(forKey: $0) != nil }) ?? true { continue }
            cancelPrefetch(id: wallpaper.id)
            guard startsIfMissing else { continue }
            let cancellation = ThumbnailCacheRequestCancellation()
            prefetches[identity] = Prefetch(path: wallpaper.path, thumbnailPath: wallpaper.thumbnailPath,
                                               cancellation: cancellation, readyKey: nil)
            loadThumbnail(for: wallpaper, priority: .prefetch, cancellation: cancellation) { [weak self] image, key in
                guard let self, !cancellation.cancelled, image != nil,
                      self.prefetches[identity]?.cancellation === cancellation else { return }
                self.prefetches[identity]?.readyKey = key
            }
        }
    }

    func cancelPrefetch(id: String) { prefetches.removeValue(forKey: Data(id.utf8))?.cancellation.cancel() }
    func cancelAllPrefetch() {
        prefetches.values.forEach { $0.cancellation.cancel() }
        prefetches.removeAll()
    }
}
