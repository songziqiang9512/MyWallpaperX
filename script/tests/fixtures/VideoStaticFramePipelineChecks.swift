import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO

// Complete production cache/static-frame methods are compiled beside this
// state shell. Desktop application records its argument; NSWorkspace is never
// called. Original AV generation, queues, epochs and sync callback bodies run.
nonisolated final class WallpaperManager: @unchecked Sendable {
    // ACTUAL_CACHE_FIELDS
    // ACTUAL_STATIC_QUEUE
    let thumbnailCacheDirectory: URL
    let staticFrameCacheDirectory: URL
    struct Settings { var syncSystemWallpaper = true }
    struct SwitchState { var committed: Int? = 1 }
    var settings = Settings()
    var playbackSwitch = SwitchState()
    var currentWallpaper: VideoWallpaper?
    var updates: [(String, String?, Bool)] = []
    var applied: [String] = []
    init(root: URL) throws {
        thumbnailCacheDirectory = root.appendingPathComponent("thumbnails", isDirectory: true)
        staticFrameCacheDirectory = root.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staticFrameCacheDirectory, withIntermediateDirectories: true)
    }
    func updateWallpaperAssetPaths(forPath path: String, thumbnailPath: String? = nil, staticFramePath: String? = nil) {
        updates.append((path, staticFramePath, Thread.isMainThread))
    }
    private func applySystemWallpaperSync(from path: String) {
        precondition(Thread.isMainThread)
        applied.append(path)
    }
    // ACTUAL_PATH_METHODS
    // ACTUAL_CLEAR_METHOD
    // ACTUAL_SYNC_METHOD
    // ACTUAL_REMOVAL_METHODS
}

// ACTUAL_DELETION_FAILURE

@main enum VideoStaticFramePipelineChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        let a = root.appendingPathComponent("a.mp4"), b = root.appendingPathComponent("b.mp4")
        let invalid = root.appendingPathComponent("invalid.mp4"), missing = root.appendingPathComponent("missing.mp4")
        let observed = VideoThumbnailObservations.shared, callbacks = ThumbnailCompletions()
        var checks: [String: Bool] = [:], work: [String: [String: Int]] = [:]
        func pump(_ condition: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(15)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
            return condition()
        }
        func owner(_ name: String, source: URL? = nil) throws -> WallpaperManager {
            let value = try WallpaperManager(root: root.appendingPathComponent(name))
            value.currentWallpaper = .init(title: name, path: (source ?? a).path)
            return value
        }
        func expected(_ owner: WallpaperManager, _ url: URL, suffix: String = "_frame.jpg") -> URL {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
            return (suffix == "_frame.jpg" ? owner.staticFrameCacheDirectory : owner.thumbnailCacheDirectory)
                .appendingPathComponent(key + suffix)
        }
        func signature(_ path: String?) -> String? {
            guard let path, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  CGImageSourceGetType(source) as String? == "public.jpeg",
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width == 512, image.height == 288 else { return nil }
            var bytes = [UInt8](repeating: 0, count: 16 * 9 * 4)
            let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 9,
                    bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 9))
                return true
            }
            guard valid else { return nil }
            return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        }
        func request(_ manager: WallpaperManager, _ url: URL, _ name: String) {
            manager.generateStaticFrameIfNeeded(for: url) { callbacks.record(name, $0) }
        }
        func generate(_ manager: WallpaperManager, _ url: URL, _ name: String) -> String? {
            manager.staticFrameQueue.async {
                let path = manager.generateStaticFrame(for: url)
                DispatchQueue.main.async { callbacks.record(name, path) }
            }
            precondition(pump { callbacks.count(name) == 1 }, "direct AV worker did not finish")
            return callbacks.path(name)
        }
        func hold(_ manager: WallpaperManager) -> DispatchSemaphore {
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            manager.staticFrameQueue.async {
                entered.signal()
                precondition(release.wait(timeout: .now() + 12) == .success, "owned queue gate timed out")
            }
            precondition(entered.wait(timeout: .now() + 3) == .success)
            return release
        }
        let reference = try owner("reference")
        let referenceA = generate(reference, a, "reference-a")
        let referenceB = generate(reference, b, "reference-b")
        let pixelsA = signature(referenceA), pixelsB = signature(referenceB)
        precondition(pixelsA != nil && pixelsB != nil && pixelsA != pixelsB, "distinct real JPEG controls required")

        let basic = try owner("basic")
        request(basic, a, "cold")
        checks["coldRealAVJPEGAndMainCallback"] = pump { callbacks.count("cold") == 1 }
            && signature(callbacks.path("cold")) == pixelsA
            && callbacks.path("cold") == expected(basic, a).path
        let decodes = observed.count(a)
        request(basic, a, "cached")
        checks["cacheHitCompletesSynchronouslyWithoutDecode"] = callbacks.count("cached") == 1
            && callbacks.path("cached") == callbacks.path("cold") && observed.count(a) == decodes
        try fm.removeItem(at: expected(basic, a))
        request(basic, a, "repaired")
        checks["deletedOutputRegeneratesActualJPEG"] = pump { callbacks.count("repaired") == 1 }
            && signature(callbacks.path("repaired")) == pixelsA && observed.count(a) == decodes + 1
        request(basic, missing, "missing"); request(basic, invalid, "invalid")
        checks["missingAndCorruptCompleteOnceWithNil"] = pump {
            callbacks.count("missing") == 1 && callbacks.count("invalid") == 1
        } && callbacks.path("missing") == nil && callbacks.path("invalid") == nil

        let queuedAlias = root.appendingPathComponent("queued-alias.mp4")
        try fm.createSymbolicLink(at: queuedAlias, withDestinationURL: a)
        let queued = try owner("queued", source: queuedAlias)
        let releaseQueued = hold(queued)
        request(queued, queuedAlias, "retargeted")
        try fm.removeItem(at: queuedAlias)
        try fm.createSymbolicLink(at: queuedAlias, withDestinationURL: b)
        releaseQueued.signal()
        checks["queuedWorkerResolvesRetargetAndLabelsCurrentBytes"] = pump { callbacks.count("retargeted") == 1 }
            && callbacks.path("retargeted") == expected(queued, b).path
            && signature(callbacks.path("retargeted")) == pixelsB
            && !fm.fileExists(atPath: expected(queued, a).path)

        let scheduledAlias = root.appendingPathComponent("scheduled-alias.mp4")
        try fm.createSymbolicLink(at: scheduledAlias, withDestinationURL: a)
        let scheduled = try owner("scheduled", source: scheduledAlias)
        let beforeSchedule = observed.count(b)
        observed.resetWork()
        scheduled.scheduleStaticFrameGeneration(for: scheduledAlias)
        scheduled.scheduleStaticFrameGeneration(for: scheduledAlias)
        work["scheduleTwoSynchronousMisses"] = observed.work
        try fm.removeItem(at: scheduledAlias)
        try fm.createSymbolicLink(at: scheduledAlias, withDestinationURL: b)
        checks["delayedWorkerRetargetAndOriginalScheduleRetirement"] = pump { scheduled.updates.count == 1 }
            && scheduled.updates.first?.0 == scheduledAlias.path
            && scheduled.updates.first?.1 == expected(scheduled, b).path
            && signature(scheduled.updates.first?.1) == pixelsB
            && observed.count(b) == beforeSchedule + 1 && scheduled.scheduledStaticFramePaths.isEmpty
            && !fm.fileExists(atPath: expected(scheduled, a).path)

        let cleared = try owner("cleared")
        let releaseClear = hold(cleared), beforeClear = observed.count(a)
        request(cleared, a, "cleared-before-worker")
        cleared.clearPreviewCacheArtifacts(); releaseClear.signal()
        checks["clearBeforeQueueRejectsWithoutDecodeOrUpdate"] = pump { callbacks.count("cleared-before-worker") == 1 }
            && callbacks.path("cleared-before-worker") == nil && cleared.updates.isEmpty
            && observed.count(a) == beforeClear && !fm.fileExists(atPath: expected(cleared, a).path)
        let late = try owner("late")
        let decodeHold = observed.holdNext(a)
        request(late, a, "cleared-during-decode")
        precondition(pump { decodeHold.didEnter })
        late.clearPreviewCacheArtifacts(); decodeHold.release.signal()
        checks["startedOldWorkerCannotPublishCurrentGeneration"] = pump { callbacks.count("cleared-during-decode") == 1 }
            && callbacks.path("cleared-during-decode") == nil && late.updates.isEmpty
        // A started old worker may recreate a derived JPEG; the existing epoch
        // rejects its publication. This test does not invent a no-write promise.
        request(late, a, "new-generation")
        checks["newGenerationCanUseActualCurrentOutput"] = pump { callbacks.count("new-generation") == 1 }
            && signature(callbacks.path("new-generation")) == pixelsA

        let synced = try owner("synced")
        let releaseSync = hold(synced)
        observed.resetWork()
        synced.syncSystemWallpaper(with: synced.currentWallpaper!)
        work["systemSyncSynchronousMiss"] = observed.work
        releaseSync.signal()
        checks["systemSyncMissUsesActualGeneratedCallback"] = pump { synced.applied.count == 1 }
            && signature(synced.applied.first) == pixelsA && synced.updates.count == 1
        synced.applied = []; synced.updates = []
        synced.syncSystemWallpaper(with: synced.currentWallpaper!)
        checks["systemSyncDiskHitUpdatesAndAppliesOnceSynchronously"] = synced.applied == [expected(synced, a).path]
            && synced.updates.count == 1 && synced.updates.first?.1 == expected(synced, a).path
        for change in ["execution", "selection", "setting"] {
            let stopped = try owner("stopped-" + change)
            let release = hold(stopped)
            stopped.syncSystemWallpaper(with: stopped.currentWallpaper!)
            if change == "execution" { stopped.playbackSwitch.committed = 2 }
            if change == "selection" { stopped.currentWallpaper = .init(title: "other", path: b.path) }
            if change == "setting" { stopped.settings.syncSystemWallpaper = false }
            release.signal()
            checks["systemSyncRejectsChanged-" + change] = pump { stopped.updates.count == 1 } && stopped.applied.isEmpty
        }
        let declared = try owner("declared")
        var declaredWallpaper = declared.currentWallpaper!
        declaredWallpaper.staticFramePath = referenceA
        declared.syncSystemWallpaper(with: declaredWallpaper)
        checks["configuredFrameRemainsImmediateAndDoesNotGenerate"] = declared.applied == [referenceA!]
            && declared.updates.isEmpty

        let removed = try owner("removed")
        let frame = generate(removed, a, "removal-frame"), neighbor = generate(removed, b, "removal-neighbor")
        let thumbnail = expected(removed, a, suffix: "_thumb.jpg")
        try Data([1, 2, 3]).write(to: thumbnail)
        let record = WallpaperManager.RemovalRecord(id: "owned", title: "owned", path: a.path,
            thumbnailPath: nil, staticFramePath: nil)
        observed.resetWork()
        let failures = removed.removeDerivedAssets(for: record)
        work["derivedRemoval"] = observed.work
        checks["derivedRemovalKeepsSourceNeighborAndOriginalNamespaces"] = failures.isEmpty
            && !fm.fileExists(atPath: frame!) && !fm.fileExists(atPath: thumbnail.path)
            && fm.fileExists(atPath: a.path) && signature(neighbor) == pixelsB
        checks["allCallbacksOnceOnMainAndUpdatesOnMain"] = callbacks.onceOnMain
            && [basic, queued, scheduled, cleared, late, synced, declared, removed].allSatisfy { $0.updates.allSatisfy { $0.2 } }
        checks["realDecodeOffMainAndNoOutstandingDecode"] = observed.boundedOffMain
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks, "work": work,
            "referencePixels": [pixelsA!, pixelsB!]], options: [.sortedKeys]), as: UTF8.self))
    }
}
