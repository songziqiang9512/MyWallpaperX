import AppKit
import CryptoKit

nonisolated final class VideoPathObservations: @unchecked Sendable {
    static let shared = VideoPathObservations()
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func record(_ name: String) { lock.lock(); values[name, default: 0] += 1; lock.unlock() }
    var counts: [String: Int] { lock.lock(); defer { lock.unlock() }; return values }
}

// Only Manager storage and unrelated generation-status leaves are controlled.
// Path resolution, provider, cache and card methods come from the source tree.
final class WallpaperManager {
    let thumbnailCacheDirectory: URL
    var wallpapers: [VideoWallpaper] = []
    var preparedIDs: [String] = []
    init(_ directory: URL) { thumbnailCacheDirectory = directory }
    func isThumbnailGenerationInFlight(for path: String) -> Bool { false }
    func hasRecentThumbnailGenerationFailure(for path: String) -> Bool { false }
    func ensurePreviewAssetsForWallpaper(_ wallpaper: VideoWallpaper, completion: ((String?) -> Void)? = nil) { preparedIDs.append(wallpaper.id); completion?(nil) }
    // ACTUAL_PATH_METHODS
}

@main struct VideoNilThumbnailChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VIDEO_NIL_ROOT"]!)
            .resolvingSymlinksInPath().standardizedFileURL
        let directory = root.appendingPathComponent("derived")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.mp4")
        try Data("test-owned source; no AV extraction is requested".utf8).write(to: source)
        let manager = WallpaperManager(directory)
        let nilRecord = VideoWallpaper(id: "historical-nil", title: "nil", path: source.path)
        manager.wallpapers = [nilRecord]
        let key = manager.cacheKey(forNormalizedPath: manager.normalizedPath(source.path))
        let derived = manager.thumbnailOutputURL(forKey: key)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<30 { for x in 0..<40 { rep.setColor(.systemBlue, atX: x, y: y) } }
        try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: derived)
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        func pump(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(5)
            while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            return predicate()
        }
        var controls: [String: Bool] = [:]
        var observations: [String: Bool] = [:]
        var warm: NSImage?
        let warmLease = provider.loadThumbnail(for: nilRecord) { warm = $0 }
        controls["realResolverLoadsNilRecordDerivedJPEG"] = pump { warm != nil }
        controls["canonicalSourcePath"] = source.path == manager.normalizedPath(source.path)
        controls["recordStillHasNoPersistedThumbnailPath"] = nilRecord.thumbnailPath == nil
        controls["originalCacheContainsResolvedImage"] = warm != nil
            && VideoLibraryThumbnailStore.sharedCache.cachedImage(forKey: derived.path) === warm
        let configuredPath = root.appendingPathComponent("configured.jpg")
        for y in 0..<30 { for x in 0..<40 { rep.setColor(.systemRed, atX: x, y: y) } }
        try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: configuredPath)
        let explicit = VideoWallpaper(id: "explicit", title: "explicit", path: source.path, thumbnailPath: configuredPath.path)
        var configuredWarm: NSImage?
        let configuredLease = provider.loadThumbnail(for: explicit) { configuredWarm = $0 }
        controls["distinctConfiguredPathIsActuallyWarmed"] = pump { configuredWarm != nil } && configuredWarm !== warm
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        provider.decodeQueue.async { entered.signal(); release.wait() }
        controls["originalSerialValidationQueueIsHeld"] = entered.wait(timeout: .now() + 2) == .success
        func configure(_ record: VideoWallpaper, _ card: VideoCardProbe) {
            card.configure(wallpaper: record, isSelected: false, isPlaying: false,
                multiSelectMode: false, wallpaperManager: manager, thumbnailProvider: provider)
        }
        let syncBefore = VideoPathObservations.shared.counts
        let nilCard = VideoCardProbe()
        configure(nilRecord, nilCard)
        observations["nilPathReadyInConfigureTurn"] = warm != nil && nilCard.thumbnailImageView.image === warm
        observations["nilPathLoadingLabelHiddenInConfigureTurn"] = nilCard.placeholderLabel.isHidden
        let explicitCard = VideoCardProbe()
        configure(explicit, explicitCard)
        controls["explicitPathKeepsOriginalSameTurnReadyPixels"] = configuredWarm != nil && explicitCard.thumbnailImageView.image === configuredWarm
        let alias = root.appendingPathComponent("alias.mp4")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let aliasRecord = VideoWallpaper(id: "alias", title: "alias", path: alias.path)
        let aliasCard = VideoCardProbe()
        configure(aliasRecord, aliasCard)
        controls["aliasRawKeyDiffersFromNormalizedSourceKey"] = manager.cacheKey(forNormalizedPath: alias.path) != key
        controls["noncanonicalAliasSafelyMissesBeforeValidation"] = aliasCard.thumbnailImageView.image == nil
        let previousCWD = FileManager.default.currentDirectoryPath
        controls["relativeProbeCWDChanged"] = FileManager.default.changeCurrentDirectoryPath(root.path)
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previousCWD) }
        let relativeRecord = VideoWallpaper(id: "relative", title: "relative", path: "source.mp4")
        let relativeCard = VideoCardProbe()
        configure(relativeRecord, relativeCard)
        controls["relativeRawKeyDiffersFromNormalizedSourceKey"] = manager.cacheKey(forNormalizedPath: relativeRecord.path) != key
        controls["relativePathSafelyMissesBeforeValidation"] = relativeCard.thumbnailImageView.image == nil
        let syncAfter = VideoPathObservations.shared.counts
        controls["warmConfigureDoesNotNormalizePaths"] = syncBefore["normalized", default: 0] == syncAfter["normalized", default: 0]
        controls["warmConfigureDoesNotCheckPathExistence"] = syncBefore["exists", default: 0] == syncAfter["exists", default: 0]
        release.signal()
        controls["originalAsyncValidationCompletesAllCards"] = pump {
            !nilCard.thumbnailRequestIsPending && !explicitCard.thumbnailRequestIsPending
                && !aliasCard.thumbnailRequestIsPending && !relativeCard.thumbnailRequestIsPending
        }
        controls["nilAliasAndRelativeEventuallyReceiveRealResolvedPixels"] = warm != nil
            && nilCard.thumbnailImageView.image === warm && aliasCard.thumbnailImageView.image === warm
            && relativeCard.thumbnailImageView.image === warm
        let deletedEntered = DispatchSemaphore(value: 0), deletedRelease = DispatchSemaphore(value: 0)
        provider.decodeQueue.async { deletedEntered.signal(); deletedRelease.wait() }
        controls["deletionValidationQueueIsHeld"] = deletedEntered.wait(timeout: .now() + 2) == .success
        let deletedCard = VideoCardProbe()
        configure(nilRecord, deletedCard)
        observations["readyPixelsBeforeDerivedDeletion"] = deletedCard.thumbnailImageView.image === warm
        try FileManager.default.removeItem(at: derived)
        controls["deletionRetainsMemoryForFinalValidationCounterexample"] = warm != nil
            && VideoLibraryThumbnailStore.sharedCache.cachedImage(forKey: derived.path) === warm
        deletedRelease.signal()
        controls["deletedDerivedFileFinalCallbackClearsPixels"] = pump { !deletedCard.thumbnailRequestIsPending }
            && deletedCard.thumbnailImageView.image == nil
        VideoLibraryThumbnailStore.sharedCache.remove(forKey: derived.path)
        let clearedCard = VideoCardProbe()
        clearedCard.setThumbnailVisible(false)
        configure(nilRecord, clearedCard)
        controls["explicitCacheRemovalCannotSupplyReadyPixels"] = clearedCard.thumbnailImageView.image == nil
        controls["fixtureDoesNotBackfillModelOrPublishSourceRows"] = manager.wallpapers == [nilRecord]
        withExtendedLifetime((warmLease, configuredLease)) {}
        let result: [String: Any] = ["controls": controls, "observations": observations,
            "work": ["beforeWarmConfigure": syncBefore, "afterWarmConfigure": syncAfter],
            "paths": ["source": source.path, "alias": alias.path, "resolvedThumbnail": derived.path],
            "scope": "actual path methods/provider/cache/card configure; Manager state leaves; no AV video decode or real window/screen"]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
