import Foundation
import CoreGraphics
import ImageIO
import AVFoundation
import CoreVideo

// Calls remain real; only their entry thread is observed from either executor.
nonisolated final class InspectorMetadataWorkProbe: @unchecked Sendable {
    static let shared = InspectorMetadataWorkProbe()
    private let lock = NSLock()
    private var entries: [String: [String: [Bool]]] = [:]
    func record(_ path: String, stage: String) {
        let onMain = Thread.isMainThread
        lock.lock(); defer { lock.unlock() }
        entries[path, default: [:]][stage, default: []].append(onMain)
    }
    func snapshot(_ path: String) -> [String: [Bool]] {
        lock.lock(); defer { lock.unlock() }
        return entries[path, default: [:]]
    }
    func avEntries(_ path: String) -> Int { snapshot(path)["av", default: []].count }
}

// Pauses after real AV work, before the original delivery cancellation check.
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

    @available(macOS 26.0, *)
    static func writeH264(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 32])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA), size: CVImageSize(width: 64, height: 32))
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            var buffer = try CVMutablePixelBuffer(attributes)
            buffer.accessUnsafeMutableRawPlaneBytes { planes in
                for plane in planes { _ = plane.bytes.initializeMemory(as: UInt8.self, repeating: 0x55) }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(buffer), with: CMTime(value: Int64(index), timescale: 30))
        }
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        receiver.finish()
        await withCheckedContinuation { done in writer.finishWriting { done.resume() } }
        precondition(writer.status == .completed, "H264 fixture writer did not finish")
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let invalid = root.appendingPathComponent("invalid-video.mp4")
        try Data(repeating: 0, count: 1024 * 1024).write(to: invalid)
        let png = root.appendingPathComponent("not-a-video.png")
        writePNG(png)
        let h264 = root.appendingPathComponent("real-h264.mov")
        var checks: [String: Bool] = [:]
        let missing = root.appendingPathComponent("missing-video.mp4")
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        var cases = [
            ("unknown-video", invalid, Optional<Int>.none, Optional<String>.none, Optional<Int64>.none, "读取中…", "读取中…", "未知", "未知", "未知"),
            ("known-fallback-image", png, Optional(65), Optional("32×16"), Optional<Int64>(2 * 1024 * 1024), "2.00 MB", "1:05", "1:05", "32×16", "未知"),
            ("missing-video", missing, Optional(17), Optional("160×90"), Optional<Int64>.none, "读取中…", "0:17", "0:17", "160×90", "未知")
        ]
        if #available(macOS 26.0, *) {
            try await writeH264(h264)
            cases.append(("real-h264", h264, Optional(65), Optional("320×180"), Optional<Int64>(3 * 1024 * 1024), "3.00 MB", "1:05", "0:01", "32 × 64", "H.264"))
        } else {
            FileHandle.standardError.write(Data("H264 positive skipped: pixel-buffer receiver requires macOS 26; original 38 facts still run.\n".utf8))
        }
        for (label, url, duration, resolution, cachedSize, initialSize, initialDuration, finalDuration, finalResolution, finalCodec) in cases {
            let wallpaper = VideoWallpaper(id: label, title: label, path: url.path, fileSize: cachedSize, duration: duration, resolution: resolution)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let expectedSize = String(format: "%.2f MB", Double(attributes?[.size] as? Int64 ?? 0) / (1024 * 1024))
            let creationDate = attributes?[.creationDate] as? Date
            let started = Date()
            var didReturn = false, firstWasSynchronous = false
            var values: [WallpaperInspectorDetails] = []
            var callbackThreads: [Bool] = []
            let preparationsBefore = InspectorMetadataWorkProbe.shared.avEntries(url.path)
            let beforeTemplate = InspectorMetadataWorkProbe.shared.snapshot(url.path)
            let task = loadWallpaperInspectorDetails(for: wallpaper) { value in
                if values.isEmpty { firstWasSynchronous = !didReturn }
                callbackThreads.append(Thread.isMainThread)
                values.append(value)
            }
            didReturn = true
            let first = values.first!
            checks[label + "-first-completion-is-before-function-return"] = firstWasSynchronous && values.count == 1
            checks[label + "-initial-template-already-has-all-layout-fields-and-source-path"] = first.pathText == url.path
                && !first.fileSizeText.isEmpty && !first.formatText.isEmpty && !first.addedDateText.isEmpty
                && !first.durationText.isEmpty && first.codecText == "读取中…" && !first.resolutionText.isEmpty
                && first.isLoading
            // The immediate template uses indexed hints; real file facts belong to the terminal.
            checks[label + "-known-facts-and-unknown-placeholders-are-preserved"] = first.durationText == initialDuration
                && first.resolutionText == (resolution ?? "读取中…") && first.formatText == url.pathExtension.uppercased()
            checks[label + "-initial-file-facts-use-cache-or-loading-without-file-work"] = first.fileSizeText == initialSize
                && first.addedDateText == "读取中…" && InspectorMetadataWorkProbe.shared.snapshot(url.path) == beforeTemplate
            await task.value
            let terminal = values.last!
            checks[label + "-async-terminal-keeps-source-path-and-prepared-file-facts"] = values.count == 2
                && terminal.pathText == first.pathText && terminal.fileSizeText == expectedSize
                && terminal.formatText == first.formatText && !terminal.isLoading
                && InspectorMetadataWorkProbe.shared.avEntries(url.path) - preparationsBefore == 1
            if let creationDate {
                checks[label + "-terminal-date-matches-real-filesystem-creation-date"] = terminal.addedDateText == dateFormatter.string(from: creationDate)
            } else {
                let decoded = dateFormatter.date(from: terminal.addedDateText)
                checks[label + "-missing-file-terminal-keeps-current-date-fallback"] = terminal.fileSizeText == "0.00 MB"
                    && decoded.map { $0 >= started.addingTimeInterval(-1) && $0 <= Date().addingTimeInterval(1) } == true
            }
            let terminalKey = label == "real-h264" ? "-valid-video-replaces-stale-index-hints" : "-unsupported-media-settles-with-fallback-values"
            checks[label + terminalKey] = terminal.durationText == finalDuration
                && terminal.resolutionText == finalResolution && terminal.codecText == finalCodec
            checks[label + "-both-completions-remain-on-main"] = callbackThreads == [true, true]
            let threads = InspectorMetadataWorkProbe.shared.snapshot(url.path)
            FileHandle.standardError.write(Data(("metadata-work " + label + " " + String(describing: threads) + "\n").utf8))
            for stage in ["attributes", "formatter", "av"] {
                checks[label + "-" + stage + "-initializes-once-off-main"] = threads[stage] == [false]
            }
        }
        let cancelledEntriesBefore = InspectorMetadataWorkProbe.shared.avEntries(invalid.path)
        var cancelledValues: [WallpaperInspectorDetails] = []
        let cancelled = loadWallpaperInspectorDetails(for: .init(id: "cancelled", title: "cancelled", path: invalid.path)) {
            cancelledValues.append($0)
        }
        // Cancel in the same MainActor turn, after the legitimate immediate
        // template but before the Task's AV work can publish a terminal value.
        cancelled.cancel()
        await cancelled.value
        checks["cancelled-before-task-start-does-not-prepare-av-asset"] =
            InspectorMetadataWorkProbe.shared.avEntries(invalid.path) == cancelledEntriesBefore
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
