import Foundation
import CoreGraphics
import ImageIO

// The test copy pauses after real AV work, immediately before the original
// MainActor delivery. No AV value or cancellation decision is substituted.
@MainActor enum InspectorMetadataDeliveryProbe {
    static var heldPaths: Set<String> = []
    static var pending: [String: CheckedContinuation<Void, Never>] = [:]
    static func waitIfHeld(_ path: String) async {
        if heldPaths.contains(path) {
            await withCheckedContinuation { pending[path] = $0 }
        }
    }
    static func release(_ path: String) {
        heldPaths.remove(path)
        pending.removeValue(forKey: path)?.resume()
    }
}

@main struct VideoInspectorMetadataHarness {
    static func writePNG(_ url: URL) {
        let context = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination), "failed to create isolated metadata PNG")
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let invalid = root.appendingPathComponent("invalid-video.mp4")
        try Data(repeating: 0, count: 1024 * 1024).write(to: invalid)
        let png = root.appendingPathComponent("not-a-video.png")
        writePNG(png)
        var checks: [String: Bool] = [:]
        for (label, url, duration, resolution) in [
            ("unknown-video", invalid, Optional<Int>.none, Optional<String>.none),
            ("known-fallback-image", png, Optional(65), Optional("32×16"))
        ] {
            let wallpaper = VideoWallpaper(id: label, title: label, path: url.path, duration: duration, resolution: resolution)
            var didReturn = false, firstWasSynchronous = false
            var values: [WallpaperInspectorDetails] = []
            let task = loadWallpaperInspectorDetails(for: wallpaper) { value in
                if values.isEmpty { firstWasSynchronous = !didReturn }
                values.append(value)
            }
            didReturn = true
            let first = values.first!
            checks[label + "-first-completion-is-before-function-return"] = firstWasSynchronous && values.count == 1
            checks[label + "-initial-template-already-has-all-layout-fields-and-source-path"] = first.pathText == url.path
                && !first.fileSizeText.isEmpty && !first.formatText.isEmpty && !first.addedDateText.isEmpty
                && !first.durationText.isEmpty && first.codecText == "读取中…" && !first.resolutionText.isEmpty
                && first.isLoading
            // Existing display format pads seconds, not the minutes field.
            checks[label + "-known-facts-and-unknown-placeholders-are-preserved"] = first.durationText == (duration == nil ? "读取中…" : "1:05")
                && first.resolutionText == (resolution ?? "读取中…") && first.formatText == url.pathExtension.uppercased()
                && (label != "unknown-video" || first.fileSizeText == "1.00 MB")
            await task.value
            let terminal = values.last!
            checks[label + "-async-terminal-keeps-source-path-and-prepared-file-facts"] = values.count == 2
                && terminal.pathText == first.pathText && terminal.fileSizeText == first.fileSizeText
                && terminal.formatText == first.formatText && terminal.addedDateText == first.addedDateText
                && !terminal.isLoading
            checks[label + "-unsupported-media-settles-with-fallback-values"] = terminal.durationText == (duration == nil ? "未知" : "1:05")
                && terminal.resolutionText == (resolution ?? "未知") && terminal.codecText == "未知"
        }
        var cancelledValues: [WallpaperInspectorDetails] = []
        let cancelled = loadWallpaperInspectorDetails(for: .init(id: "cancelled", title: "cancelled", path: invalid.path)) {
            cancelledValues.append($0)
        }
        // Cancel in the same MainActor turn, after the legitimate immediate
        // template but before the Task's AV work can publish a terminal value.
        cancelled.cancel()
        await cancelled.value
        checks["cancelled-real-av-task-cannot-publish-a-late-terminal-after-its-template"] = cancelledValues.count == 1
            && cancelledValues[0].pathText == invalid.path && cancelledValues[0].codecText == "读取中…"
        var replacementValues: [WallpaperInspectorDetails] = []
        let replacement = loadWallpaperInspectorDetails(for: .init(id: "replacement", title: "replacement", path: png.path)) {
            replacementValues.append($0)
        }
        await replacement.value
        checks["later-independent-source-settles-without-reviving-the-cancelled-path"] = replacementValues.count == 2
            && replacementValues.allSatisfy { $0.pathText == png.path } && cancelledValues.count == 1
        let delayed = root.appendingPathComponent("delivery-pending.png")
        try FileManager.default.copyItem(at: png, to: delayed)
        InspectorMetadataDeliveryProbe.heldPaths.insert(delayed.path)
        var delayedValues: [WallpaperInspectorDetails] = []
        let delayedTask = loadWallpaperInspectorDetails(for: .init(id: "delivery-pending", title: "delivery-pending", path: delayed.path)) {
            delayedValues.append($0)
        }
        let deadline = Date().addingTimeInterval(10)
        while InspectorMetadataDeliveryProbe.pending[delayed.path] == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        precondition(InspectorMetadataDeliveryProbe.pending[delayed.path] != nil, "real AV work did not reach its delivery boundary")
        delayedTask.cancel()
        InspectorMetadataDeliveryProbe.release(delayed.path)
        await delayedTask.value
        checks["cancel-after-real-av-work-before-main-actor-delivery-cannot-publish-final"] = delayedValues.count == 1
            && delayedValues[0].isLoading && delayedValues[0].pathText == delayed.path
        InspectorMetadataDeliveryProbe.heldPaths.insert(delayed.path)
        var resumedValues: [WallpaperInspectorDetails] = []
        let resumedTask = loadWallpaperInspectorDetails(for: .init(id: "delivery-live", title: "delivery-live", path: delayed.path)) {
            resumedValues.append($0)
        }
        let resumedDeadline = Date().addingTimeInterval(10)
        while InspectorMetadataDeliveryProbe.pending[delayed.path] == nil && Date() < resumedDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        precondition(InspectorMetadataDeliveryProbe.pending[delayed.path] != nil, "live AV task did not reach its delivery boundary")
        InspectorMetadataDeliveryProbe.release(delayed.path)
        await resumedTask.value
        checks["same-real-av-delivery-boundary-publishes-final-for-live-consumer"] = resumedValues.count == 2
            && resumedValues[0].isLoading && !resumedValues[1].isLoading && resumedValues[1].pathText == delayed.path
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
