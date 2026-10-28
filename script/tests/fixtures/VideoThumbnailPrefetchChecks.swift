import AppKit

struct VideoWallpaper {
    let id: String
    let path: String
    let thumbnailPath: String?
    var displayTitle: String { id }
    var fileSize: Int? { nil }
    var duration: Int? { nil }
    var resolution: String? { nil }
}

/// The fixture controls the real provider's existing derived-asset boundary.
/// ImageIO, image cache, consumer leases and disk publication stay production.
final class WallpaperManager {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var counts: [Data: Int] = [:]
    var wallpapers: [VideoWallpaper] = []
    var preparedIDs: [String] = []
    var blockedID: String?
    func count(_ id: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[Data(id.utf8), default: 0] }
    func normalizedPath(_ path: String) -> String { path }
    func normalizedSourcePathExists(_ path: String) -> Bool { !path.contains("absent") }
    func isThumbnailGenerationInFlight(for path: String) -> Bool { false }
    func hasRecentThumbnailGenerationFailure(for path: String) -> Bool { false }
    func ensurePreviewAssetsForWallpaper(_ wallpaper: VideoWallpaper) { preparedIDs.append(wallpaper.id) }
    func resolvedThumbnailPath(for wallpaper: VideoWallpaper) -> String? {
        lock.lock(); counts[Data(wallpaper.id.utf8), default: 0] += 1
        let block = blockedID == wallpaper.id
        if block { blockedID = nil }
        lock.unlock()
        if block { entered.signal(); release.wait() }
        guard let path = wallpaper.thumbnailPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}

@main struct VideoThumbnailPrefetchChecks {
    @MainActor static func main() throws {
        let root = ProcessInfo.processInfo.environment["VIDEO_DEMAND_ROOT"]!
        let path = root + "/thumb.png"
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        let a = VideoWallpaper(id: "A", path: root + "/a.mp4", thumbnailPath: path)
        let b = VideoWallpaper(id: "B", path: root + "/b.mp4", thumbnailPath: path + ".missing")
        let manager = WallpaperManager()
        manager.blockedID = a.id
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        var checks: [String: Bool] = [:]
        func pump(_ test: () -> Bool) -> Bool {
            let until = Date().addingTimeInterval(5)
            while !test(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            return test()
        }
        provider.replacePrefetch(with: [a])
        checks["controlledSourceValidationEntered"] = manager.entered.wait(timeout: .now() + 2) == .success
        // A's visible card still has to validate its source. Preserve its
        // already-started prefetch until that consumer actually joins.
        provider.replacePrefetch(with: [], retainingVisible: [a])
        provider.replacePrefetch(with: [b], retainingVisible: [a])
        provider.cancelPrefetch(id: b.id)
        manager.release.signal()
        checks["nearToVisibleHandoffKeepsCurrentProducer"] = pump {
            VideoLibraryThumbnailStore.sharedCache.cachedImage(forKey: path) != nil
        }
        checks["removedDemandSkipsQueuedSourceValidation"] = manager.count(b.id) == 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        VideoLibraryThumbnailStore.sharedCache.imageCache.removeAllObjects()
        provider.replacePrefetch(with: [a])
        checks["completedNearbyLeaseRewarmsAfterMemoryRelease"] = pump {
            VideoLibraryThumbnailStore.sharedCache.cachedImage(forKey: path) != nil
        } && manager.count(a.id) == 2
        var image: NSImage?
        provider.loadThumbnail(for: a) { image = $0 }
        checks["visibleConsumerReusesReadyPixelsAfterValidation"] = pump { image != nil } && manager.count(a.id) == 3
        let card = VideoCardProbe()
        func configure(_ wallpaper: VideoWallpaper) {
            card.configure(wallpaper: wallpaper, isSelected: false, isPlaying: false,
                multiSelectMode: false, wallpaperManager: manager, thumbnailProvider: provider)
        }
        configure(a)
        checks["warmCardDoesNotFlashLoadingLabel"] = card.placeholderLabel.isHidden && pump { card.thumbnailImageView.image != nil }
        let slow = VideoWallpaper(id: "slow", path: root + "/slow.mp4", thumbnailPath: path + ".slow")
        try FileManager.default.copyItem(atPath: path, toPath: slow.thumbnailPath!)
        manager.blockedID = slow.id
        configure(slow)
        checks["differentResourceClearsPreviousPixelsImmediately"] = card.thumbnailImageView.image == nil
            && manager.entered.wait(timeout: .now() + 2) == .success
        checks["coldCardStartsWithoutLoadingFlash"] = card.placeholderLabel.isHidden
        RunLoop.main.run(until: Date().addingTimeInterval(0.14))
        checks["realSlowRequestShowsLoadingAfterDelay"] = !card.placeholderLabel.isHidden
        configure(a)
        manager.release.signal()
        checks["fastReturnRejectsOldDelayedCardAndTimer"] = pump { card.thumbnailImageView.image != nil }
            && card.currentWallpaperID == a.id && card.placeholderLabel.isHidden
        manager.blockedID = slow.id
        configure(slow)
        _ = manager.entered.wait(timeout: .now() + 2)
        let offscreenLease = card.imageCancellation!
        card.setThumbnailVisible(false)
        checks["offscreenCardReleasesItsPendingConsumer"] = offscreenLease.cancelled
        configure(a)
        manager.release.signal()
        checks["hiddenCardDoesNotStartNewSourceValidation"] = card.currentWallpaperID == a.id && card.imageCancellation == nil
        card.setThumbnailVisible(true)
        checks["reshowResumesLatestUnfinishedCard"] = pump { card.thumbnailImageView.image != nil } && card.currentWallpaperID == a.id
        let beforeReadyHide = manager.count(a.id)
        card.setThumbnailVisible(false); card.setThumbnailVisible(true)
        checks["readyCardDoesNotReloadOnHideReshow"] = manager.count(a.id) == beforeReadyHide
        configure(VideoWallpaper(id: "absent", path: root + "/absent.mp4", thumbnailPath: nil))
        checks["actualFailureAppearsImmediately"] = pump { card.placeholderLabel.stringValue == "请检查文件路径" }
            && !card.placeholderLabel.isHidden && card.thumbnailImageView.image == nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.14))
        checks["failureCannotBeOverwrittenByDelayedLoading"] = card.placeholderLabel.stringValue == "请检查文件路径"
        let unicodeA = VideoWallpaper(id: "é", path: root + "/nfc.mp4", thumbnailPath: path + ".nfc")
        let unicodeB = VideoWallpaper(id: "e\u{301}", path: root + "/nfd.mp4", thumbnailPath: path + ".nfd")
        try FileManager.default.copyItem(atPath: path, toPath: unicodeA.thumbnailPath!)
        try FileManager.default.copyItem(atPath: path, toPath: unicodeB.thumbnailPath!)
        manager.blockedID = unicodeA.id
        provider.replacePrefetch(with: [unicodeA])
        checks["opaquePrefetchFirstValidationStarts"] = manager.entered.wait(timeout: .now() + 2) == .success
        provider.replacePrefetch(with: [unicodeA, unicodeB])
        manager.release.signal()
        checks["opaqueUnicodePrefetchLeasesDoNotCancelEachOther"] = pump {
            VideoLibraryThumbnailStore.sharedCache.cachedImage(forKey: unicodeA.thumbnailPath!) != nil
                && VideoLibraryThumbnailStore.sharedCache.cachedImage(forKey: unicodeB.thumbnailPath!) != nil
        } && manager.count(unicodeA.id) == 1 && manager.count(unicodeB.id) == 1
        try FileManager.default.removeItem(atPath: path)
        var finished = false
        provider.loadThumbnail(for: a) { image = $0; finished = true }
        checks["deletedDerivedAssetCannotReviveReadyMemoryImage"] = pump { finished } && image == nil
        provider.cancelAllPrefetch()
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
