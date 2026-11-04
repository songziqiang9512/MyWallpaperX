import AppKit
import AVFoundation
import ImageIO

struct PixabayDownloadedEntry { let localURL: URL; let thumbnailSourceKey: String? }

nonisolated final class PixabayAVProbe: @unchecked Sendable {
    static let shared = PixabayAVProbe()
    private let lock = NSLock()
    private var values: [String: [[String: Double]]] = [:]
    static func time(_ time: CMTime, generator: AVAssetImageGenerator) -> CMTime {
        let name = (generator.asset as! AVURLAsset).url.lastPathComponent
        shared.lock.lock()
        shared.values[name, default: []].append(["seconds": time.seconds,
            "maximumWidth": generator.maximumSize.width, "maximumHeight": generator.maximumSize.height,
            "onMain": Thread.isMainThread ? 1 : 0])
        shared.lock.unlock()
        return time
    }
    func count(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[name]?.count ?? 0 }
    var observations: [String: [[String: Double]]] { lock.lock(); defer { lock.unlock() }; return values }
}

@main enum PixabayThumbnailGenerationChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let cache = PixabayDownloadedThumbnailStore.sharedCache
        var checks: [String: Bool] = [:], images: [String: [String: Int]] = [:]
        func pixels(_ image: NSImage, _ name: String) -> CGSize {
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            images[name] = ["width": cg.width, "height": cg.height, "bytes": cg.bytesPerRow * cg.height]
            return CGSize(width: cg.width, height: cg.height)
        }
        @MainActor func wait(_ condition: () -> Bool) async throws -> Bool {
            let deadline = Date().addingTimeInterval(8)
            while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
            return condition()
        }
        func load(_ name: String, _ request: ThumbnailRequest?) async throws -> NSImage {
            let url = root.appendingPathComponent(name), cancellation = ThumbnailCacheRequestCancellation()
            var completed = false, result: NSImage?
            PixabayDownloadedThumbnailStore.loadThumbnail(.init(localURL: url, thumbnailSourceKey: nil),
                request: request, priority: .visible, cancellation: cancellation) { _, image in
                    result = image; completed = true
                }
            let finished = try await wait { completed }
            guard let result, finished else {
                throw NSError(domain: "PixabayAVFixture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No thumbnail: \(name), \(String(describing: request))"])
            }
            return result
        }
        let small = ThumbnailRequest(width: 64, height: 64, mode: .fill)
        let large = ThumbnailRequest(width: 512, height: 512, mode: .fill)
        let first = try await load("landscape.mp4", small)
        let firstPixels = pixels(first, "small")
        checks["small-card-prepares-only-the-requested-visible-pixels"] = firstPixels == CGSize(width: 64, height: 64)
            && PixabayAVProbe.shared.count("landscape.mp4") == 1
        let enlarged = try await load("landscape.mp4", large)
        checks["larger-card-upgrades-the-same-source-without-a-failure-entry"] = pixels(enlarged, "large") == CGSize(width: 512, height: 512)
            && PixabayAVProbe.shared.count("landscape.mp4") == 2
        let landscapeKey = PixabayDownloadedThumbnailStore.cacheKey(for: root.appendingPathComponent("landscape.mp4"))
        let largeMasterReady = try await wait {
            autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(cache.diskCacheURL(for: landscapeKey) as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
                return image.width >= large.width && image.height >= large.height && image.width > image.height
            }
        }
        precondition(largeMasterReady, "The large uncropped derivative must commit before its disk-reuse checks")
        let fit = try await load("landscape.mp4", .init(width: 128, height: 128, mode: .fit))
        let fitPixels = pixels(fit, "fit")
        checks["fit-reuses-the-uncropped-master-without-another-AV-frame"] = fitPixels.width > fitPixels.height
            && abs(fitPixels.width / fitPixels.height - 16 / 9) < 0.03
            && PixabayAVProbe.shared.count("landscape.mp4") == 2
        let returned = try await load("landscape.mp4", small)
        checks["returning-small-card-reuses-the-ready-compatible-image"] = (returned === first || returned === enlarged || returned === fit)
            && PixabayAVProbe.shared.count("landscape.mp4") == 2

        let legacy = try await load("legacy.mp4", nil)
        let legacyPixels = pixels(legacy, "legacy")
        checks["nil-request-retains-the-installed-legacy-maximum"] = legacyPixels.width <= 520 && legacyPixels.height <= 300
            && PixabayAVProbe.shared.count("legacy.mp4") == 1
        let upgraded = try await load("legacy.mp4", large)
        checks["legacy-small-derivative-upgrades-instead-of-poisoning-the-source"] = pixels(upgraded, "legacy-upgrade") == CGSize(width: 512, height: 512)
            && PixabayAVProbe.shared.count("legacy.mp4") == 2

        let capped = try await load("tiny.mp4", large)
        let tinyPixels = pixels(capped, "tiny")
        let tinyKey = PixabayDownloadedThumbnailStore.cacheKey(for: root.appendingPathComponent("tiny.mp4"))
        checks["native-small-source-remains-a-valid-ready-result"] = tinyPixels == CGSize(width: 90, height: 90)
            && cache.hasCachedResult(forKey: tinyKey, request: large)
        let tinyReturn = try await load("tiny.mp4", large)
        checks["native-cap-warm-return-does-not-retry-AV"] = tinyReturn === capped
            && PixabayAVProbe.shared.count("tiny.mp4") == 1

        let portrait = try await load("portrait.mp4", .init(width: 180, height: 320, mode: .fit))
        let portraitPixels = pixels(portrait, "portrait")
        checks["preferred-track-rotation-controls-the-requested-native-size"] = abs(portraitPixels.width - 180) <= 1
            && abs(portraitPixels.height - 320) <= 1 && PixabayAVProbe.shared.count("portrait.mp4") == 1
        let metadata = await PixabayDownloadedAssetMetadata.load(from: root.appendingPathComponent("portrait.mp4"))
        checks["metadata-and-frame-use-the-same-oriented-size-reader"] = metadata.resolutionString == "720×1280"

        await withCheckedContinuation { continuation in
            cache.clearAll(cancelInFlight: true) { continuation.resume() }
        }
        let rebuilt = try await load("landscape.mp4", small)
        checks["clear-rebuilds-from-the-original-source-while-held-view-keeps-its-image"] = pixels(rebuilt, "after-clear") == firstPixels
            && PixabayAVProbe.shared.count("landscape.mp4") == 3
            && pixels(enlarged, "held-large") == CGSize(width: 512, height: 512)
        await withCheckedContinuation { continuation in
            cache.clearAll(cancelInFlight: true) { continuation.resume() }
        }
        let taskRow = try await load("landscape.mp4", .init(width: 96, height: 96, mode: .fit))
        checks["task-row-fit-prepares-a-small-complete-frame"] = pixels(taskRow, "task-row") == CGSize(width: 96, height: 54)
            && images["task-row"]!["bytes"]! < images["legacy"]!["bytes"]! && PixabayAVProbe.shared.count("landscape.mp4") == 4
        let warmRow = try await load("landscape.mp4", .init(width: 48, height: 48, mode: .fit))
        checks["task-row-fit-warm-return-reuses-pixels-without-another-frame"] = warmRow === taskRow
            && PixabayAVProbe.shared.count("landscape.mp4") == 4
        let observations = PixabayAVProbe.shared.observations
        checks["actual-AV-requests-retain-half-second-frame-and-background-work"] = observations.values.flatMap { $0 }
            .allSatisfy { $0["seconds"] == 0.5 && $0["onMain"] == 0 }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks,
            "images": images, "generation": observations], options: [.sortedKeys]), as: UTF8.self))
    }
}
