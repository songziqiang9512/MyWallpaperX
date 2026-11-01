import AppKit
import AVFoundation
import Darwin

@main
enum SystemWallpaperRuntimeChecks {
    @MainActor static func main() async {
        do { try await check() }
        catch { print("FAIL:", error); exit(1) }
    }

    @MainActor static func check() async throws {
        guard CGMainDisplayID() != 0 else { print("SKIP: no desktop display server"); return }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let runtime = SystemWallpaperRuntime(root: root.appendingPathComponent("unpublished"))
        let geometry = SystemWallpaperGeometry(displayID: CGMainDisplayID(), size: CGSize(width: 64, height: 48), scale: 1, isPreview: false)
        let first = UUID(), second = UUID()
        let context = try runtime.acquire(connection: first, request: UUID(), geometry: geometry)
        let shared = try runtime.acquire(connection: second, request: UUID(), geometry: geometry)
        guard context == shared else { throw CocoaError(.validationMultipleErrors) }
        runtime.invalidate(connection: first)
        let surviving = try runtime.acquire(connection: second, request: UUID(), geometry: geometry)
        guard surviving == shared else { throw CocoaError(.validationMultipleErrors) }
        runtime.invalidate(connection: second)

        let mediaRoot = root.appendingPathComponent("missing-video")
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        try Data().write(to: mediaRoot.appendingPathComponent(".lease"))
        let poster = mediaRoot.appendingPathComponent("poster.png")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[2]), to: poster)
        let configuration = ScreenSaverConfiguration(content: .init(kind: .video, mediaGeneration: UUID().uuidString,
            title: "missing file after publication", entryRelativePath: "missing.mp4", posterRelativePath: "poster.png"))
        let media = SystemWallpaperMedia(configuration: configuration, root: mediaRoot,
            video: mediaRoot.appendingPathComponent("missing.mp4"), poster: poster)
        let surface = try SystemWallpaperVideoSurface(displayID: CGMainDisplayID(), size: geometry.size, scale: 1, isPreview: false)
        try surface.apply(media, animate: true)
        let descriptor = open(mediaRoot.appendingPathComponent(".lease").path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(descriptor); surface.stop() }
        var released = false
        for _ in 0..<200 {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { released = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard released, surface.layer.contents != nil else { throw CocoaError(.fileReadUnknown) }
        try catalogChanges(root: root.appendingPathComponent("unpublished"), runtime: runtime, poster: poster)
        try await hostState(root: root.appendingPathComponent("host-state"), poster: poster)
        print("PASS: live context survives other connection; failed playback releases lease and retains poster")
        withExtendedLifetime(runtime) {}
    }

    @MainActor private static func catalogChanges(root: URL, runtime: SystemWallpaperRuntime, poster: URL) throws {
        let value = ScreenSaverConfiguration(content: .init(kind: .video, mediaGeneration: UUID().uuidString,
            title: "updated catalog", entryRelativePath: "video.mp4", posterRelativePath: "poster.png"))
        let media = try ScreenSaverPaths.mediaRoot(in: root, generation: value.content!.mediaGeneration)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: poster, to: media.appendingPathComponent("poster.png"))
        try Data().write(to: media.appendingPathComponent("video.mp4"))
        let changes = Counter()
        let token = NotificationCenter.default.addObserver(forName: ScreenSaverConfiguration.changedNotification,
            object: runtime, queue: nil) { _ in MainActor.assumeIsolated { changes.count += 1 } }
        defer { NotificationCenter.default.removeObserver(token) }
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        guard try SystemWallpaperMedia.load(from: root)?.configuration.content?.title == "updated catalog" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        runtime.reload()
        runtime.reload()
        guard changes.count == 1, runtime.media?.configuration.content?.title == "updated catalog" else {
            throw NSError(domain: "CatalogFixture", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "update notifications=\(changes.count), title=\(runtime.media?.configuration.content?.title ?? "nil")"])
        }
        try JSONEncoder().encode(ScreenSaverConfiguration(content: nil)).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        runtime.reload()
        guard changes.count == 2, runtime.media == nil else { throw CocoaError(.coderReadCorrupt) }
        print("PASS: publication and clear notify the catalog once; unchanged reload does not notify")
    }

    @MainActor private final class Counter { var count = 0 }

    @MainActor private static func hostState(root: URL, poster: URL) async throws {
        let value = ScreenSaverConfiguration(content: .init(kind: .video, mediaGeneration: UUID().uuidString,
            title: "host state", entryRelativePath: "video.mov", posterRelativePath: "poster.png"), playsOnBattery: true)
        let media = try ScreenSaverPaths.mediaRoot(in: root, generation: value.content!.mediaGeneration)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: poster, to: media.appendingPathComponent("poster.png"))
        try Data().write(to: media.appendingPathComponent(".lease"))
        try await makeVideo(media.appendingPathComponent("video.mov"))
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        let descriptor = open(media.appendingPathComponent(".lease").path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(descriptor) }
        func leased() -> Bool {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { flock(descriptor, LOCK_UN); return false }
            return true
        }
        let runtime = SystemWallpaperRuntime(root: root)
        let a = UUID(), b = UUID(), requestA = UUID(), requestB = UUID()
        var active = SystemWallpaperGeometry(displayID: CGMainDisplayID(), size: CGSize(width: 64, height: 48),
            scale: 1, isPreview: false, presentation: .screenSaver)
        let context = try runtime.acquire(connection: a, request: requestA, geometry: active)
        if !ProcessInfo.processInfo.isLowPowerModeEnabled {
            guard leased() else { throw CocoaError(.fileReadUnknown) }
        }
        let other = try runtime.acquire(connection: b, request: requestB, geometry: active)
        guard context == other else { throw CocoaError(.validationMultipleErrors) }
        var suspended = active; suspended.isActive = false
        try runtime.update(connection: a, request: requestA, geometry: suspended)
        if !ProcessInfo.processInfo.isLowPowerModeEnabled {
            guard leased() else { throw CocoaError(.fileReadUnknown) }
        }
        runtime.invalidate(connection: b)
        guard !leased() else { throw CocoaError(.fileLocking) }
        active = .init(displayID: active.displayID, size: CGSize(width: 96, height: 64), scale: 2,
                       isPreview: false, presentation: .screenSaver)
        try runtime.update(connection: a, request: requestA, geometry: active)
        if !ProcessInfo.processInfo.isLowPowerModeEnabled {
            guard leased() else { throw CocoaError(.fileReadUnknown) }
        }
        runtime.invalidate(connection: a)
        try runtime.update(connection: a, request: requestA, geometry: active)
        guard !leased() else { throw CocoaError(.fileLocking) }
        active.isPreview = true
        let previewID = try runtime.acquire(connection: a, request: requestA, geometry: active)
        // Observe the real retained surface without adding a product-only test API.
        let contexts = Mirror(reflecting: runtime).children.first { $0.label == "contexts" }!.value
        let entry = Mirror(reflecting: contexts).children.first!.value
        let record = Mirror(reflecting: entry).children.first { $0.label == "value" }!.value
        let surface = Mirror(reflecting: record).children.first { $0.label == "surface" }!.value as! SystemWallpaperVideoSurface
        active = .init(displayID: active.displayID, size: CGSize(width: 128, height: 72), scale: 2, isPreview: false,
                       presentation: .screenSaver)
        try runtime.update(connection: a, request: requestA, geometry: active)
        guard !leased(), surface.contextID == previewID, surface.layer.bounds.size == active.size,
              (surface.context.value(forKey: "layer") as? CALayer) === surface.layer else {
            throw CocoaError(.fileLocking)
        }
        runtime.invalidate(connection: a)
        print("PASS: cold active host without App/notifications, suspend/resume, competing requests, stale update and preview")
    }

    private static func makeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<3 {
            for _ in 0..<500 where !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
                  let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer)!, 0x55, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
