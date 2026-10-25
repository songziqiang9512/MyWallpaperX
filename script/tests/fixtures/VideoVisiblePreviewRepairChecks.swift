import AppKit

struct VideoWallpaper {
    let id: String
    let path: String
    let thumbnailPath: String?
}
final class WallpaperManager: @unchecked Sendable {
    var wallpapers: [VideoWallpaper] = []
    var prepared: [String] = []
    var preparationOnMain = true
    private let lock = NSLock()
    private var blockPath: String?
    private var calls: [String] = []
    private var previewCalls: [String] = []
    private var checksOffMain = true
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func block(_ path: String) { lock.lock(); blockPath = path; lock.unlock() }
    var observations: ([String], [String], Bool) { lock.lock(); defer { lock.unlock() }; return (calls, previewCalls, checksOffMain) }
    func normalizedSourcePathExists(_ path: String) -> Bool {
        lock.lock(); calls.append(path); checksOffMain = checksOffMain && !Thread.isMainThread
        let blocked = blockPath == path
        if blocked { blockPath = nil }
        lock.unlock()
        if blocked { entered.signal(); release.wait() }
        return !path.contains("absent")
    }
    func resolvedThumbnailPath(for value: VideoWallpaper) -> String? {
        lock.lock(); previewCalls.append(value.path); checksOffMain = checksOffMain && !Thread.isMainThread; lock.unlock()
        return value.thumbnailPath
    }
    func ensurePreviewAssetsForWallpaper(_ value: VideoWallpaper) { preparationOnMain = preparationOnMain && Thread.isMainThread; prepared.append(value.id) }
}

@main enum VideoVisiblePreviewRepairChecks {
    static func pump(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.004)) }
        return predicate()
    }
    static func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.06)) }
    static func main() throws {
        var checks: [String: Bool] = [:]
        let manager = WallpaperManager()
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        let a = VideoWallpaper(id: "a", path: "/a", thumbnailPath: nil)
        manager.wallpapers = [a]
        provider.updateVisiblePreviewDemand(with: []); provider.repairVisiblePreviews(); spin()
        checks["empty-visible-scope-performs-no-source-or-preview-io"] = manager.observations.0.isEmpty && manager.observations.1.isEmpty
        manager.block(a.path)
        provider.updateVisiblePreviewDemand(with: [a])
        checks["visible-repair-enters-original-background-provider"] = manager.entered.wait(timeout: .now() + 2) == .success
        var mainRan = false
        DispatchQueue.main.async { mainRan = true }
        _ = pump { mainRan }
        for _ in 0..<20 { provider.repairVisiblePreviews(); provider.updateVisiblePreviewDemand(with: [a]) }
        checks["slow-visible-repair-never-blocks-main-or-stacks-same-lease"] = mainRan && manager.observations.0 == [a.path]
        manager.release.signal()
        checks["missing-derived-preview-is-prepared-by-original-manager-on-main"] = pump { manager.prepared == ["a"] }
            && manager.preparationOnMain && manager.observations.2
        let count = manager.observations.0.count
        for _ in 0..<20 { provider.updateVisiblePreviewDemand(with: [a]) }; spin()
        checks["repeated-viewport-input-does-not-poll-finished-resource"] = manager.observations.0.count == count
        provider.repairVisiblePreviews()
        checks["existing-source-cadence-can-recheck-without-owning-another-timer"] = pump { manager.prepared == ["a", "a"] }
        let absent = VideoWallpaper(id: "absent", path: "/absent", thumbnailPath: nil)
        manager.wallpapers = [absent]
        provider.updateVisiblePreviewDemand(with: [absent]); _ = pump { manager.observations.0.last == absent.path }; spin()
        checks["missing-source-never-resolves-or-prepares-derived-assets"] = !manager.observations.1.contains(absent.path) && manager.prepared == ["a", "a"]
        let ready = VideoWallpaper(id: "ready", path: "/ready", thumbnailPath: "/ready.png")
        manager.wallpapers = [ready]
        provider.updateVisiblePreviewDemand(with: [ready]); _ = pump { manager.observations.1.last == ready.path }; spin()
        checks["existing-derived-preview-never-schedules-preparation"] = !manager.prepared.contains(ready.id)
        for mutation in ["hidden", "deleted", "path", "thumbnail"] {
            let row = VideoWallpaper(id: mutation, path: "/" + mutation, thumbnailPath: nil)
            manager.wallpapers = [row]
            manager.block(row.path)
            provider.updateVisiblePreviewDemand(with: [row])
            let entered = manager.entered.wait(timeout: .now() + 2) == .success
            switch mutation {
            case "hidden": provider.updateVisiblePreviewDemand(with: [])
            case "deleted": manager.wallpapers = []
            case "path": manager.wallpapers = [VideoWallpaper(id: row.id, path: row.path + "-new", thumbnailPath: nil)]
            default: manager.wallpapers = [VideoWallpaper(id: row.id, path: row.path, thumbnailPath: "/new.png")]
            }
            let before = manager.prepared
            manager.release.signal(); spin()
            checks[mutation + "-rejects-old-preview-repair-at-main-commit"] = entered && manager.prepared == before
        }
        let reordered = VideoWallpaper(id: "reordered", path: "/reordered", thumbnailPath: nil)
        manager.wallpapers = [reordered, ready]; manager.block(reordered.path)
        provider.updateVisiblePreviewDemand(with: [reordered])
        let reorderEntered = manager.entered.wait(timeout: .now() + 2) == .success
        manager.wallpapers.reverse()
        manager.release.signal()
        checks["reorder-repairs-original-id-at-new-index-without-touching-old-index-occupant"] = reorderEntered
            && pump { manager.prepared.last == reordered.id } && !manager.prepared.contains(ready.id)
        provider.updateVisiblePreviewDemand(with: [])
        let beforeReleased = manager.prepared
        let released = VideoWallpaper(id: "released", path: "/released", thumbnailPath: nil)
        manager.wallpapers = [released]; manager.block(released.path)
        weak var weakProvider: AppKitThumbnailProvider?
        autoreleasepool {
            var temporary: AppKitThumbnailProvider? = AppKitThumbnailProvider(wallpaperManager: manager)
            weakProvider = temporary
            temporary?.updateVisiblePreviewDemand(with: [released])
            checks["released-provider-worker-starts"] = manager.entered.wait(timeout: .now() + 2) == .success
            temporary = nil
        }
        checks["slow-worker-does-not-retain-provider-or-visible-lease"] = weakProvider == nil
        manager.release.signal(); spin()
        checks["late-worker-cannot-revive-released-provider-or-prepare-media"] = weakProvider == nil && manager.prepared == beforeReleased
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
