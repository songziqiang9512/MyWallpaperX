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
    init(root: URL) throws {
        thumbnailCacheDirectory = root.appendingPathComponent("thumbnails", isDirectory: true)
        staticFrameCacheDirectory = root.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailCacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staticFrameCacheDirectory, withIntermediateDirectories: true)
    }
    // ACTUAL_PATH_METHODS
    // ACTUAL_CLEAR_METHOD
    // ACTUAL_STATIC_FRAME_OUTPUT
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
    var onceOnMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return allMain && counts.values.allSatisfy { $0 == 1 }
    }
}

@main enum VideoThumbnailGeneratorChecks {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
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
            (owner ?? manager).generateThumbnail(for: url) { results.record(name, $0) }
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
        manager.bumpCacheGeneration()
        staleHold.release.signal()
        checks["generationChangeRejectsLateJPEG"] = staleEntered && pump { results.count("stale") == 1 }
            && results.path("stale") == nil && !fm.fileExists(atPath: expectedOutput(stale).path)
        request("stale-retry", stale)
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
        checks["clearWithdrawsOldCallbacksAndLateJPEG"] = clearEntered && queueDrained && drained
            && results.count("withdrawn-by-clear") == 0 && !fm.fileExists(atPath: expectedOutput(cleared).path)
        request("after-clear", cleared)
        checks["freshRequestAfterClearRepairsOutput"] = pump { results.count("after-clear") == 1 }
            && realJPEG(results.path("after-clear"))
        checks["callbacksOnceOnMain"] = results.onceOnMain
        checks["realDecodeRemainsBoundedOffMain"] = observed.boundedOffMain
        let output: [String: Any] = ["checks": checks, "work": work,
            "jpegFailures": jpegFailures,
            "initialJPEGSHA256": SHA256.hash(data: firstJPEG).map { String(format: "%02x", $0) }.joined(),
            "scope": "real CachePipeline/AV/JPEG and clear-generation; provider/Prefs/App absent"]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
