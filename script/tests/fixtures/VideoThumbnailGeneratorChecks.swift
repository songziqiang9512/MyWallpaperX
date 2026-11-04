import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO

// Only storage/state leaves are supplied. The complete CachePipeline extension,
// original path methods and actual clearPreviewCacheArtifacts body are compiled.
nonisolated final class WallpaperManager: @unchecked Sendable {
    var protectedSystemDesktopURLs = Set<URL>()
    // ACTUAL_CACHE_FIELDS
    let thumbnailCacheDirectory: URL
    let staticFrameCacheDirectory: URL
    var wallpaperIndexSaveEpoch = 0
    let importStages = ThumbnailCompletions()
    init(root: URL) throws {
        thumbnailCacheDirectory = root.appendingPathComponent("thumbnails", isDirectory: true)
        staticFrameCacheDirectory = root.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staticFrameCacheDirectory, withIntermediateDirectories: true)
    }
    // ACTUAL_PATH_METHODS
    // ACTUAL_CLEAR_METHOD
    // ACTUAL_STATIC_FRAME_OUTPUT
    // Downstream desktop/metadata leaves stay inert; the complete original
    // import batch loop and its semaphore waits run against real thumbnails.
    func notifyThumbnailReady(forPath path: String) { importStages.record("ready-" + path, nil) }
    func generateStaticFrame(for url: URL) -> String? { importStages.record("static-" + url.path, nil); return nil }
    func updateWallpaperAssetPaths(forPath: String, staticFramePath: String) {}
    static func collectImportedAssetMetadata(for urls: [URL]) async -> [String] { [] }
    func applyImportedAssetMetadataUpdates(_ updates: [String]) {}
    // ACTUAL_IMPORT_BATCH
}

nonisolated final class DecodeHold: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entered = false
    func arrive() { lock.lock(); entered = true; lock.unlock() }
    var didEnter: Bool { lock.lock(); defer { lock.unlock() }; return entered }
}

/// Observation/gates exist only in the copied source at real key/AV entry leaves.
nonisolated final class VideoThumbnailObservations: @unchecked Sendable {
    static let shared = VideoThumbnailObservations()
    private let lock = NSLock()
    private var normalizations = 0, hashes = 0, active = 0, maximumActive = 0
    private var allDecodeOffMain = true
    private var attempts: [String: Int] = [:]
    private var holds: [String: DecodeHold] = [:]
    func normalized() { lock.lock(); normalizations += 1; lock.unlock() }
    func hashed() { lock.lock(); hashes += 1; lock.unlock() }
    var work: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["normalizations": normalizations, "hashes": hashes]
    }
    func resetWork() { lock.lock(); normalizations = 0; hashes = 0; lock.unlock() }
    private func path(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    func holdNext(_ url: URL) -> DecodeHold {
        let hold = DecodeHold()
        lock.lock(); holds[path(url)] = hold; lock.unlock()
        return hold
    }
    func beginDecode(_ generator: AVAssetImageGenerator) {
        let url = (generator.asset as! AVURLAsset).url
        let key = path(url)
        lock.lock()
        attempts[key, default: 0] += 1
        active += 1; maximumActive = max(maximumActive, active)
        allDecodeOffMain = allDecodeOffMain && !Thread.isMainThread
        let hold = holds.removeValue(forKey: key)
        lock.unlock()
        if let hold {
            hold.arrive()
            precondition(hold.release.wait(timeout: .now() + 15) == .success, "owned decode gate timed out")
        }
    }
    func endDecode() { lock.lock(); active -= 1; lock.unlock() }
    func count(_ url: URL) -> Int { lock.lock(); defer { lock.unlock() }; return attempts[path(url), default: 0] }
    var boundedOffMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return active == 0 && maximumActive <= 2 && allDecodeOffMain
    }
}

nonisolated final class ThumbnailCompletions: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var paths: [String: String] = [:]
    private var allMain = true
    func record(_ name: String, _ path: String?) {
        lock.lock(); defer { lock.unlock() }
        counts[name, default: 0] += 1
        paths[name] = path
        allMain = allMain && Thread.isMainThread
    }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name, default: 0] }
    func path(_ name: String) -> String? { lock.lock(); defer { lock.unlock() }; return paths[name] }
    var recordedCounts: [String: Int] { lock.lock(); defer { lock.unlock() }; return counts }
    var onceOnMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return allMain && counts.values.allSatisfy { $0 == 1 }
    }
}

@main enum VideoThumbnailGeneratorChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        if CommandLine.arguments.contains("--adaptive") { try adaptiveChecks(root: root); return }
        let fm = FileManager.default
        let first = root.appendingPathComponent("first.mp4")
        let second = root.appendingPathComponent("renamed.mp4")
        let invalid = root.appendingPathComponent("invalid.mp4")
        let missing = root.appendingPathComponent("missing.mp4")
        let alias = root.appendingPathComponent("alias.mp4")
        try fm.createSymbolicLink(at: alias, withDestinationURL: first)
        let manager = try WallpaperManager(root: root.appendingPathComponent("cache"))
        let observed = VideoThumbnailObservations.shared, results = ThumbnailCompletions()
        var checks: [String: Bool] = [:], work: [String: [String: Int]] = [:]
        var jpegFailures: [[String: Any]] = []
        func request(_ name: String, _ url: URL, using owner: WallpaperManager? = nil) {
            (owner ?? manager).generateThumbnail(for: url) { results.record(name, $0?.path) }
        }
        func pump(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(15)
            while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
            return predicate()
        }
        func expectedOutput(_ url: URL) -> URL {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            let key = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            return manager.thumbnailCacheDirectory.appendingPathComponent(key + "_thumb.jpg")
        }
        func recordJPEGFailure(_ facts: [String: Any], path: String?) -> Bool {
            var facts = facts
            if let proof = ProcessInfo.processInfo.environment["MWX_VIDEO_THUMBNAIL_GENERATOR_PROOF_DIR"],
               let path, let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let directory = URL(fileURLWithPath: proof, isDirectory: true)
                    .appendingPathComponent(root.lastPathComponent, isDirectory: true)
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let copy = directory.appendingPathComponent("jpeg-failure-\(jpegFailures.count).jpg")
                try? bytes.write(to: copy)
                facts["retainedJPEG"] = copy.path
            }
            jpegFailures.append(facts)
            return false
        }
        func realJPEG(_ path: String?) -> Bool {
            var facts: [String: Any] = ["path": path ?? "nil"]
            guard let path else { return recordJPEGFailure(["stage": "nil-path"], path: nil) }
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
                facts["stage"] = "ImageIO-source"
                return recordJPEGFailure(facts, path: path)
            }
            facts["sourceType"] = CGImageSourceGetType(source).map { String(describing: $0) } ?? "nil"
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                facts["stage"] = "ImageIO-image"
                return recordJPEGFailure(facts, path: path)
            }
            let aspect = Double(image.width) / Double(image.height)
            facts["width"] = image.width; facts["height"] = image.height; facts["aspect"] = aspect
            facts["sourceBitmapInfo"] = image.bitmapInfo.rawValue
            guard image.width > 4, image.height > 4, max(image.width, image.height) <= 400,
                  abs(aspect - 16.0 / 9.0) < 0.02 else {
                facts["stage"] = "dimensions"
                return recordJPEGFailure(facts, path: path)
            }
            var pixels = [UInt8](repeating: 0, count: 16 * 9 * 4)
            return pixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 9,
                    bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    facts["stage"] = "sample-context"
                    return recordJPEGFailure(facts, path: path)
                }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 9))
                let values = bytes.bindMemory(to: UInt8.self)
                let red = stride(from: 0, to: values.count, by: 4).map { Int(values[$0]) }
                let redRange = (red.max() ?? 0) - (red.min() ?? 0)
                if redRange > 40 { return true }
                facts["stage"] = "sample-red-range"; facts["redRange"] = redRange
                facts["sampleBitmapInfo"] = context.bitmapInfo.rawValue
                facts["sampleChannelRanges"] = (0..<4).map { channel in
                    let samples = stride(from: channel, to: values.count, by: 4).map { Int(values[$0]) }
                    return [samples.min() ?? 0, samples.max() ?? 0]
                }
                return recordJPEGFailure(facts, path: path)
            }
        }
        checks["startsWithoutJPEG"] = !fm.fileExists(atPath: expectedOutput(first).path)
        let frameName = expectedOutput(first).lastPathComponent.replacingOccurrences(of: "_thumb.jpg", with: "_frame.jpg")
        let frameKey = manager.cacheKey(forNormalizedPath: manager.normalizedPath(first.path))
        checks["staticFrameCallerRetainsOriginalKeyAndNamespace"] = manager.staticFrameOutputURL(forKey: frameKey)
            == manager.staticFrameCacheDirectory.appendingPathComponent(frameName)
        let firstHold = observed.holdNext(first)
        observed.resetWork()
        request("cold", first)
        let entered = pump { firstHold.didEnter }
        request("alias-coalesced", alias)
        request("renamed-cold", second)
        firstHold.release.signal()
        checks["coldAndAliasComplete"] = entered && pump {
            results.count("cold") == 1 && results.count("alias-coalesced") == 1 && results.count("renamed-cold") == 1
        }
        work["coldThreeRequests"] = observed.work
        checks["aliasSharesOneDecodeAndOutput"] = observed.count(first) == 1
            && results.path("cold") == expectedOutput(first).path
            && results.path("alias-coalesced") == results.path("cold")
        checks["renamedSourceHasIndependentOutput"] = observed.count(second) == 1
            && results.path("renamed-cold") == expectedOutput(second).path
            && results.path("renamed-cold") != results.path("cold")
        checks["coldOutputsAreRealJPEGs"] = realJPEG(results.path("cold")) && realJPEG(results.path("renamed-cold"))
        let firstJPEG = try Data(contentsOf: expectedOutput(first))

        observed.resetWork()
        request("memory", first)
        work["memoryHit"] = observed.work
        checks["memoryHitWithoutDecode"] = results.count("memory") == 1 && observed.count(first) == 1
            && results.path("memory") == results.path("cold")
        let freshManager = try WallpaperManager(root: root.appendingPathComponent("cache"))
        freshManager.markThumbnailGenerationFailure(for: first.resolvingSymlinksInPath().standardizedFileURL.path)
        observed.resetWork()
        request("disk", first, using: freshManager)
        work["diskHit"] = observed.work
        checks["diskHitWithoutDecodeAndClearsFailure"] = results.count("disk") == 1 && observed.count(first) == 1
            && results.path("disk") == results.path("cold")
            && freshManager.recentThumbnailGenerationFailureDate(for: first.resolvingSymlinksInPath().standardizedFileURL.path) == nil
        let diskResolver = try WallpaperManager(root: root.appendingPathComponent("cache"))
        observed.resetWork()
        let resolvedDisk = diskResolver.resolvedThumbnailPath(for: .init(id: "disk", title: "owned", path: first.path))
        work["resolvedDisk"] = observed.work
        checks["resolvedMemoryAndDiskUseSameOutput"] = resolvedDisk == expectedOutput(first).path
            && manager.resolvedThumbnailPath(for: .init(id: "memory", title: "owned", path: first.path)) == resolvedDisk
        checks["configuredThumbnailWins"] = manager.resolvedThumbnailPath(for: .init(id: "configured", title: "owned",
            path: missing.path, thumbnailPath: expectedOutput(second).path)) == expectedOutput(second).path
        checks["missingConfiguredThumbnailUsesRealCache"] = manager.resolvedThumbnailPath(for: .init(id: "fallback",
            title: "owned", path: first.path, thumbnailPath: root.appendingPathComponent("absent.jpg").path)) == resolvedDisk
        checks["warmJPEGBytesUnchanged"] = try Data(contentsOf: expectedOutput(first)) == firstJPEG

        try fm.removeItem(at: alias)
        try fm.createSymbolicLink(at: alias, withDestinationURL: second)
        request("retargeted-alias", alias)
        checks["nextRequestRenormalizesRetargetedAlias"] = results.count("retargeted-alias") == 1
            && results.path("retargeted-alias") == expectedOutput(second).path && observed.count(second) == 1
        try fm.removeItem(at: expectedOutput(first))
        request("repair", first)
        checks["deletedOutputRegenerates"] = pump { results.count("repair") == 1 }
            && observed.count(first) == 2 && results.path("repair") == expectedOutput(first).path
            && realJPEG(results.path("repair"))

        request("missing", missing)
        checks["missingSourceCompletesNilWithoutDecode"] = results.count("missing") == 1
            && results.path("missing") == nil && observed.count(missing) == 0
        request("invalid", invalid)
        checks["invalidSourceCompletesNilAndRecordsFailure"] = pump { results.count("invalid") == 1 }
            && results.path("invalid") == nil && observed.count(invalid) == 5
            && !manager.shouldRetryThumbnailGeneration(for: invalid.resolvingSymlinksInPath().standardizedFileURL.path)

        let stale = root.appendingPathComponent("stale.mp4")
        let staleHold = observed.holdNext(stale)
        request("stale", stale)
        let staleEntered = pump { staleHold.didEnter }
        manager.clearPreviewCacheArtifacts()
        let replacementHold = observed.holdNext(stale)
        request("stale-retry", stale)
        let replacementEntered = pump { replacementHold.didEnter }
        staleHold.release.signal()
        let oldGenerationSettled = pump {
            guard manager.thumbnailGenerationLimiter.wait(timeout: .now()) == .success else { return false }
            manager.thumbnailGenerationLimiter.signal()
            return true
        }
        checks["clearReleasesTheOriginalImportCompletionWithNil"] = staleEntered && pump { results.count("stale") == 1 }
            && results.path("stale") == nil && !fm.fileExists(atPath: expectedOutput(stale).path)
        checks["oldGenerationCannotConsumeTheNewSamePathRequest"] = replacementEntered && oldGenerationSettled
            && results.count("stale-retry") == 0
        replacementHold.release.signal()
        checks["newGenerationCanGenerate"] = pump { results.count("stale-retry") == 1 }
            && realJPEG(results.path("stale-retry"))

        let cleared = root.appendingPathComponent("clear.mp4")
        let clearHold = observed.holdNext(cleared)
        request("withdrawn-by-clear", cleared)
        let clearEntered = pump { clearHold.didEnter }
        manager.clearPreviewCacheArtifacts()
        clearHold.release.signal()
        let settled = DecodeHold()
        manager.thumbnailQueue.async(flags: .barrier) { settled.arrive() }
        let queueDrained = pump { settled.didEnter }
        var mainDrained = false
        DispatchQueue.main.async { mainDrained = true }
        let drained = pump { mainDrained }
        checks["clearCompletesOldCallbacksWithoutLateJPEG"] = clearEntered && queueDrained && drained
            && results.count("withdrawn-by-clear") == 1 && results.path("withdrawn-by-clear") == nil
            && !fm.fileExists(atPath: expectedOutput(cleared).path)
        request("after-clear", cleared)
        checks["freshRequestAfterClearRepairsOutput"] = pump { results.count("after-clear") == 1 }
            && realJPEG(results.path("after-clear"))
        let deletionHold = DecodeHold()
        manager.deletionQueue.async {
            deletionHold.arrive()
            precondition(deletionHold.release.wait(timeout: .now() + 15) == .success)
        }
        precondition(pump { deletionHold.didEnter })
        manager.clearPreviewCacheArtifacts { results.record("clear-completion", nil) }
        DispatchQueue.main.async { results.record("clear-heartbeat", nil) }
        checks["clearReturnsToMainWhileRetiredDirectoryDeletionIsQueued"] = pump { results.count("clear-heartbeat") == 1 }
            && results.count("clear-completion") == 0
        request("during-retired-deletion", cleared)
        checks["postClearJPEGPublishesBeforeOldRecursiveDeletion"] = pump { results.count("during-retired-deletion") == 1 }
            && realJPEG(results.path("during-retired-deletion")) && results.count("clear-completion") == 0
        deletionHold.release.signal()
        checks["retiredDirectoryDeletionPreservesNewJPEGAndCompletesOnMain"] = pump { results.count("clear-completion") == 1 }
            && realJPEG(results.path("during-retired-deletion"))

        let batch = try WallpaperManager(root: root.appendingPathComponent("import-batch-cache"))
        let batchHold = observed.holdNext(first), batchDrained = DecodeHold()
        let secondBeforeBatch = observed.count(second)
        batch.scheduleImportedAssetsProcessing([first, second])
        batch.importAssetPipelineQueue.async { batchDrained.arrive() }
        precondition(pump { batchHold.didEnter })
        batch.clearPreviewCacheArtifacts()
        let batchDrainedBeforeRelease = pump { batchDrained.didEnter }
        let secondDecodeDelta = observed.count(second) - secondBeforeBatch
        // The real import batch normalizes its URLs before either asset stage.
        let firstNormalizedPath = batch.normalizedPath(first.path), secondNormalizedPath = batch.normalizedPath(second.path)
        let firstStaticCount = batch.importStages.count("static-" + firstNormalizedPath)
        let secondStaticCount = batch.importStages.count("static-" + secondNormalizedPath)
        checks["clearReleasesTheRealImportBatchSemaphoreBeforeTheOldDecodeFinishes"] = batchDrainedBeforeRelease
            && secondDecodeDelta == 1 && firstStaticCount == 1 && secondStaticCount == 1
        let batchClearFacts: [String: Any] = ["batchDrainedBeforeOldDecodeRelease": batchDrainedBeforeRelease,
            "secondDecodeDelta": secondDecodeDelta, "firstExpectedStaticCount": firstStaticCount,
            "secondExpectedStaticCount": secondStaticCount, "firstRawPath": first.path, "secondRawPath": second.path,
            "firstNormalizedPath": firstNormalizedPath, "secondNormalizedPath": secondNormalizedPath,
            "actualStageCounts": batch.importStages.recordedCounts]
        FileHandle.standardError.write(Data("Import batch clear facts: ".utf8))
        FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: batchClearFacts, options: [.sortedKeys]))
        FileHandle.standardError.write(Data("\n".utf8))
        batchHold.release.signal()
        let batchDecodeDrained = DecodeHold()
        batch.thumbnailQueue.async(flags: .barrier) { batchDecodeDrained.arrive() }
        precondition(pump { batchDecodeDrained.didEnter })
        checks["callbacksOnceOnMain"] = results.onceOnMain
        checks["realDecodeRemainsBoundedOffMain"] = observed.boundedOffMain
        let output: [String: Any] = ["checks": checks, "work": work,
            "jpegFailures": jpegFailures,
            "initialJPEGSHA256": SHA256.hash(data: firstJPEG).map { String(format: "%02x", $0) }.joined(),
            "scope": "real CachePipeline/AV/JPEG and clear-generation; provider/Prefs/App absent"]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }

    @MainActor static func adaptiveChecks(root: URL) throws {
        let fm = FileManager.default, observed = VideoThumbnailObservations.shared
        let manager = try WallpaperManager(root: root.appendingPathComponent("adaptive-cache"))
        let results = ThumbnailCompletions()
        let large = root.appendingPathComponent("large.mp4"), small = root.appendingPathComponent("small.mp4")
        var checks: [String: Bool] = [:], dimensions: [String: Int] = [:]
        func pump(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(15)
            while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
            return predicate()
        }
        func shortSide(_ path: String?) -> Int {
            guard let path, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return 0 }
            return min(image.width, image.height)
        }
        func request(_ name: String, _ url: URL, _ side: Int?) {
            manager.generateThumbnail(for: url, request: side.map { ThumbnailRequest(width: $0, height: $0, mode: .fill) }) { asset in
                dimensions[name] = shortSide(asset?.path)
                results.record(name, asset?.path)
            }
        }
        let originalHold = observed.holdNext(large)
        request("default", large, nil)
        let entered = pump { originalHold.didEnter }
        request("large", large, 576)
        request("joined-small", large, 128)
        checks["largerConsumerWaitsForOriginal400Worker"] = entered && results.count("large") == 0
        originalHold.release.signal()
        checks["eachConsumerCompletesOnceAfterItsTarget"] = pump {
            results.count("default") == 1 && results.count("large") == 1 && results.count("joined-small") == 1
        } && dimensions["large", default: 0] >= 576 && dimensions["joined-small", default: 0] >= 128
        checks["sameSourceSeriallyUpgradesCanonicalJPEG"] = observed.count(large) == 2
            && results.path("default") == results.path("large") && results.path("large") == results.path("joined-small")
            && shortSide(results.path("large")) >= 576
        let upgradedURL = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(large.path)))
        let upgradedBytes = try? Data(contentsOf: upgradedURL)
        request("smaller-later", large, 384)
        let smallerCompleted = pump { results.count("smaller-later") == 1 }
        let laterBytes = try? Data(contentsOf: upgradedURL)
        checks["existingLargerJPEGNeedsNoNewAV"] = smallerCompleted && upgradedBytes != nil
            && observed.count(large) == 2 && dimensions["smaller-later", default: 0] >= 576 && laterBytes == upgradedBytes
        request("native-small", small, 800)
        checks["nativeSmallSourceIsNotUpsampled"] = pump { results.count("native-small") == 1 }
            && dimensions["native-small"] == 288 && observed.count(small) == 1
        request("native-small-again", small, 800)
        checks["nativeLimitDoesNotRegenerateForever"] = pump { results.count("native-small-again") == 1 }
            && dimensions["native-small-again"] == 288 && observed.count(small) == 1
        let rotated = root.appendingPathComponent("rotated90.mp4")
        request("rotation90", rotated, 576)
        let rotatedCompleted = pump { results.count("rotation90") == 1 }
        let rotatedSource = results.path("rotation90").flatMap { CGImageSourceCreateWithURL(URL(fileURLWithPath: $0) as CFURL, nil) }
        let rotatedImage = rotatedSource.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        var rotationTrack: [String: Double] = [:]
        Task { @MainActor in
            guard let tracks = try? await AVURLAsset(url: rotated).loadTracks(withMediaType: .video), let track = tracks.first,
                  let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) else { return }
            rotationTrack = ["width": size.width, "height": size.height, "a": transform.a, "b": transform.b,
                "c": transform.c, "d": transform.d, "tx": transform.tx, "ty": transform.ty]
        }
        _ = pump { !rotationTrack.isEmpty }
        checks["rotationFixtureCarriesQuarterTurnTrackTransform"] = abs(rotationTrack["a", default: 1]) < 0.000001
            && abs(rotationTrack["d", default: 1]) < 0.000001 && abs(rotationTrack["b", default: 0]) > 0.99
            && abs(rotationTrack["c", default: 0]) > 0.99
        checks["actual90DegreeTrackHasPortraitTargetPixels"] = rotatedCompleted && dimensions["rotation90", default: 0] >= 576
            && (rotatedImage?.width ?? 0) < (rotatedImage?.height ?? 0) && observed.count(rotated) == 1
        let isolation = root.appendingPathComponent("failed-large-isolation.mp4")
        try fm.copyItem(at: large, to: isolation)
        let baseHold = observed.holdNext(isolation)
        request("isolation-default", isolation, nil)
        let baseEntered = pump { baseHold.didEnter }
        let upgradeHold = observed.holdNext(isolation)
        request("isolation-small", isolation, 128)
        request("isolation-large", isolation, 576)
        baseHold.release.signal()
        let upgradeEntered = pump { upgradeHold.didEnter }
        var originalDeliveriesDrained = false
        DispatchQueue.main.async { originalDeliveriesDrained = true }
        checks["actual225PixelsRelease128Before576Finishes"] = baseEntered && upgradeEntered
            && pump { originalDeliveriesDrained } && results.count("isolation-small") == 1
            && dimensions["isolation-small", default: 0] >= 128 && results.count("isolation-large") == 0
        let isolationURL = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(isolation.path)))
        let isolatedBytes = try? Data(contentsOf: isolationURL)
        do {
            let permissions = try fm.attributesOfItem(atPath: manager.thumbnailCacheDirectory.path)[.posixPermissions]!
            defer { try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: manager.thumbnailCacheDirectory.path) }
            try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: manager.thumbnailCacheDirectory.path)
            checks["ownedJPEGDirectoryIsReadOnlyForUpgradeFailure"] = !fm.isWritableFile(atPath: manager.thumbnailCacheDirectory.path)
            upgradeHold.release.signal()
            let failed = pump { results.count("isolation-large") == 1 }
            let retained = try? Data(contentsOf: isolationURL)
            checks["failedLargerUpgradeCannotRevokeSatisfiedSmallConsumer"] = failed && isolatedBytes != nil
                && results.path("isolation-large") == nil && results.count("isolation-small") == 1
                && results.path("isolation-small") == isolationURL.path && dimensions["isolation-small", default: 0] >= 128
                && retained == isolatedBytes && shortSide(isolationURL.path) >= 128
        }
        checks["filesystemFailureDoesNotReextractOtherFrames"] = observed.count(isolation) == 2
        let floorSource = root.appendingPathComponent("small-target-master.mp4")
        try fm.copyItem(at: large, to: floorSource)
        request("small-target", floorSource, 128)
        checks["smallGridTargetKeepsLegacyUncroppedMasterQuality"] = pump { results.count("small-target") == 1 }
            && dimensions["small-target", default: 0] >= 225
        request("default-after-small-target", floorSource, nil)
        checks["defaultRoleRetains400MasterWithoutExtraAV"] = results.count("default-after-small-target") == 1
            && dimensions["default-after-small-target", default: 0] >= 225 && observed.count(floorSource) == 1
        let beforeRetinaUpgrade = observed.count(floorSource)
        let retinaStart = ProcessInfo.processInfo.systemUptime
        request("retina-upgrade", floorSource, 320)
        checks["legacy400MasterUpgradesFor320RetinaDemand"] = pump { results.count("retina-upgrade") == 1 }
            && dimensions["retina-upgrade", default: 0] >= 320 && observed.count(floorSource) == beforeRetinaUpgrade + 1
        let retinaSeconds = ProcessInfo.processInfo.systemUptime - retinaStart
        request("retina-disk-hit", floorSource, 320)
        checks["sameRetinaDemandDoesNotRepeatAV"] = pump { results.count("retina-disk-hit") == 1 }
            && dimensions["retina-disk-hit", default: 0] >= 320 && observed.count(floorSource) == beforeRetinaUpgrade + 1
        let failure = root.appendingPathComponent("upgrade-failure.mp4")
        try fm.copyItem(at: large, to: failure)
        request("failure-base", failure, nil)
        let failureBaseCompleted = pump { results.count("failure-base") == 1 }
        let previousURL = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(failure.path)))
        let previousBytes = try? Data(contentsOf: previousURL)
        try Data("owned invalid replacement".utf8).write(to: failure)
        request("failed-upgrade", failure, 576)
        let failureCompleted = pump { results.count("failed-upgrade") == 1 }
        let retainedBytes = try? Data(contentsOf: previousURL)
        checks["failedUpgradeKeepsOriginalValidJPEG"] = failureBaseCompleted && failureCompleted && previousBytes != nil
            && results.path("failed-upgrade") == nil && shortSide(previousURL.path) > 0 && retainedBytes == previousBytes
        let fitSource = root.appendingPathComponent("rect-fit.mp4")
        try fm.copyItem(at: large, to: fitSource)
        var fitAsset: VideoThumbnailAsset?, fitFinals: [Bool] = []
        manager.generateThumbnail(for: fitSource, request: ThumbnailRequest(width: 576, height: 576, mode: .fit)) {
            fitAsset = $0; fitFinals.append($0 != nil)
        }
        let fitCompleted = pump { fitAsset != nil }
        let fitImage = fitAsset.flatMap { NSImage(contentsOfFile: $0.path) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        checks["fitPreservesWholeUncroppedFrameAndNativeReceipt"] = fitCompleted
            && (575...576).contains(fitImage?.width ?? 0) && fitImage?.height == 324
            && abs(Double(fitImage?.width ?? 0) - Double(fitImage?.height ?? 0) * 16.0 / 9.0) <= 1
            && fitAsset?.nativeSize == CGSize(width: 1280, height: 720) && observed.count(fitSource) == 1
        let fitAttemptsAfterFirst = observed.count(fitSource)
        let fitCanonical = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(fitSource.path)))
        let fitStoredAfterFirst = NSImage(contentsOf: fitCanonical)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        var fittingRectangle: VideoThumbnailAsset?, rectangleFinals: [Bool] = []
        manager.generateThumbnail(for: fitSource, request: ThumbnailRequest(width: 480, height: 320, mode: .fill)) {
            fittingRectangle = $0; rectangleFinals.append($0 != nil)
        }
        checks["existingFitMasterCoversCompatibleRectangleWithoutAV"] = pump { fittingRectangle != nil }
            && fittingRectangle?.path == fitAsset?.path && observed.count(fitSource) == 1
        let fitStoredAfterRectangle = NSImage(contentsOf: fitCanonical)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let fitObservations: [String: Any] = ["callbackArrived": !fitFinals.isEmpty, "callbackFinals": fitFinals,
            "fitPumpSucceeded": fitCompleted, "callbackWidth": fitImage?.width ?? 0, "callbackHeight": fitImage?.height ?? 0,
            "nativeReceiptPresent": fitAsset?.nativeSize != nil,
            "nativeWidth": fitAsset?.nativeSize?.width ?? 0, "nativeHeight": fitAsset?.nativeSize?.height ?? 0,
            "canonicalPath": fitCanonical.path, "storedWidthAfterFit": fitStoredAfterFirst?.width ?? 0,
            "storedHeightAfterFit": fitStoredAfterFirst?.height ?? 0, "AVAttemptsAfterFit": fitAttemptsAfterFirst,
            "compatibleRectangleFinals": rectangleFinals, "AVAttemptsAfterRectangle": observed.count(fitSource),
            "storedWidthAfterRectangle": fitStoredAfterRectangle?.width ?? 0,
            "storedHeightAfterRectangle": fitStoredAfterRectangle?.height ?? 0]

        let rectangleSource = root.appendingPathComponent("rect-fill.mp4")
        try fm.copyItem(at: large, to: rectangleSource)
        var rectangleAsset: VideoThumbnailAsset?
        manager.generateThumbnail(for: rectangleSource, request: ThumbnailRequest(width: 480, height: 320, mode: .fill)) { rectangleAsset = $0 }
        let rectangleCompleted = pump { rectangleAsset != nil }
        let rectangleImage = rectangleAsset.flatMap { NSImage(contentsOfFile: $0.path) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        checks["rectangularFillCoversBothAxesWithoutCroppingMaster"] = rectangleCompleted
            && (rectangleImage?.width ?? 0) >= 480 && (rectangleImage?.height ?? 0) >= 320
            && abs(Double(rectangleImage?.width ?? 0) / Double(max(1, rectangleImage?.height ?? 0)) - 16.0 / 9.0) < 0.01
            && observed.count(rectangleSource) == 1

        let mixedSource = root.appendingPathComponent("mixed-targets.mp4")
        try fm.copyItem(at: large, to: mixedSource)
        let mixedHold = observed.holdNext(mixedSource)
        var mixedDefault: VideoThumbnailAsset?, mixedFit: VideoThumbnailAsset?, mixedFill: VideoThumbnailAsset?
        var mixedCounts = [0, 0, 0]
        manager.generateThumbnail(for: mixedSource) { mixedDefault = $0; mixedCounts[0] += 1 }
        let mixedEntered = pump { mixedHold.didEnter }
        manager.generateThumbnail(for: mixedSource, request: ThumbnailRequest(width: 800, height: 200, mode: .fit)) { mixedFit = $0; mixedCounts[1] += 1 }
        manager.generateThumbnail(for: mixedSource, request: ThumbnailRequest(width: 320, height: 576, mode: .fill)) { mixedFill = $0; mixedCounts[2] += 1 }
        mixedHold.release.signal()
        let mixedCompleted = pump { mixedCounts == [1, 1, 1] }
        let mixedImage = mixedFill.flatMap { NSImage(contentsOfFile: $0.path) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        checks["mixedFillFitConsumersShareOneNecessaryUpgrade"] = mixedEntered && mixedCompleted
            && mixedDefault?.path == mixedFit?.path && mixedFit?.path == mixedFill?.path
            && (mixedImage?.width ?? 0) >= 800 && (mixedImage?.height ?? 0) >= 576
            && observed.count(mixedSource) == 2
        checks["mixedTargetUpgradeLoadsNativeMetadataOnce"] = manager.importStages.count("native-" + mixedSource.path) == 1
        let cleared = root.appendingPathComponent("adaptive-clear.mp4")
        try fm.copyItem(at: large, to: cleared)
        let clearHold = observed.holdNext(cleared)
        request("adaptive-cleared", cleared, 576)
        let clearEntered = pump { clearHold.didEnter }
        manager.clearPreviewCacheArtifacts()
        checks["clearDrainsSizedConsumerOnceWithNil"] = clearEntered && pump { results.count("adaptive-cleared") == 1 }
            && results.path("adaptive-cleared") == nil
        clearHold.release.signal()
        let drained = DecodeHold()
        manager.thumbnailQueue.async(flags: .barrier) { drained.arrive() }
        let clearURL = manager.thumbnailOutputURL(forKey: manager.cacheKey(forNormalizedPath: manager.normalizedPath(cleared.path)))
        checks["clearPreventsLateAdaptiveJPEG"] = pump { drained.didEnter } && !fm.fileExists(atPath: clearURL.path)
        checks["adaptiveWorkStaysBoundedOffMain"] = observed.boundedOffMain && results.onceOnMain
        let output: [String: Any] = ["checks": checks, "callbackShortSides": dimensions,
            "observations": ["unheld400To320Seconds": retinaSeconds, "rotationJPEGWidth": rotatedImage?.width ?? 0,
                "rotationJPEGHeight": rotatedImage?.height ?? 0, "rotationAVAttempts": observed.count(rotated), "rotationTrack": rotationTrack, "fit": fitObservations],
            "AVAttempts": ["large": observed.count(large), "small": observed.count(small), "failed": observed.count(failure), "isolatedFailure": observed.count(isolation), "smallThenRetina": observed.count(floorSource)],
            "scope": "actual AV/JPEG quality, shared source group, native cap and clear; no window/Catalog"]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
