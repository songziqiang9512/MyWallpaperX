// VideoInspectorPreviewHarness.swift
// 视频详情面板预览刷新行为 harness（问题 6）。
//
// 编译真实产品文件（VideoLibraryInspectorView 及其共享 UI/缓存依赖），
// 只对视图实际消费的 manager/helper 面提供最小桩：
// - WallpaperManager 桩保留 $wallpapers / thumbnailReadyPublisher /
//   resolvedThumbnailPath / normalizedPath / 播放与选择动作的同一消费面，
//   resolvedThumbnailPath 可按源路径注入结果或阻塞（迟到回调用）；
// - 缩略图共享缓存用独立 namespace 的真实 ThumbnailCache，保留后台解码行为。
//
// 场景输出 `RESULT <name> PASS|FAIL`，由 test_video_inspector_preview_reload 断言。

import AppKit
import Combine
import Foundation

// MARK: - 视图消费面桩（不复制产品逻辑）

struct InspectorSelectionStub {}

enum UIActionHelper {
    static func toggleFavoriteSelection(manager: WallpaperManager, selection: InspectorSelectionStub) {}
    static func presentTagPicker(
        manager: WallpaperManager,
        window: NSWindow?,
        completion: @escaping () -> Void
    ) {}
}

struct WallpaperInspectorDetails: Equatable {
    let fileName: String
    let fileSizeText: String
    let formatText: String
    let durationText: String
    let codecText: String
    let resolutionText: String
    let addedDateText: String
    let pathText: String
}

@discardableResult
func loadWallpaperInspectorDetails(
    for wallpaper: VideoWallpaper,
    completion: @escaping (WallpaperInspectorDetails) -> Void
) -> Task<Void, Never> {
    Task {
        await MainActor.run {
            completion(WallpaperInspectorDetails(
                fileName: wallpaper.lastComponent,
                fileSizeText: "",
                formatText: "",
                durationText: "",
                codecText: "",
                resolutionText: "",
                addedDateText: "",
                pathText: wallpaper.path
            ))
        }
    }
}

enum VideoLibraryThumbnailStore {
    static let sharedCache = ThumbnailCache(
        label: "com.mywallpaper.test.videolibrary.thumbnail",
        namespace: "videolibrary-inspector-test"
    )
}

final class WallpaperManager: ObservableObject {
    @Published var wallpapers: [VideoWallpaper] = []
    var effectiveCurrentWallpaper: VideoWallpaper? { wallpapers.first }
    var currentSelectionContext: InspectorSelectionStub { InspectorSelectionStub() }

    /// 源路径 -> 已解析缩略图路径。主线程写、后台队列读，锁保护。
    private var resolvedPlan: [String: String] = [:]
    private let planLock = NSLock()
    /// resolvedThumbnailPath 调用记录（诊断用）
    private var resolveLog: [String] = []
    private let resolveLogLock = NSLock()

    func drainResolveLog() -> [String] {
        resolveLogLock.lock()
        defer { resolveLogLock.unlock() }
        let copy = resolveLog
        resolveLog.removeAll()
        return copy
    }
    /// 需要在 resolvedThumbnailPath 内阻塞的源路径（构造确定性迟到回调）。
    private var blockingPaths: Set<String> = []
    private var blockSignals: [String: DispatchSemaphore] = [:]
    private let blockingLock = NSLock()

    private let thumbnailReadySubject = PassthroughSubject<String, Never>()
    var thumbnailReadyPublisher: AnyPublisher<String, Never> { thumbnailReadySubject.eraseToAnyPublisher() }

    func setResolvedThumbnail(_ path: String?, for source: String) {
        planLock.lock()
        if let path {
            resolvedPlan[source] = path
        } else {
            resolvedPlan.removeValue(forKey: source)
        }
        planLock.unlock()
    }

    func blockResolvedThumbnail(for source: String) {
        blockingLock.lock()
        blockingPaths.insert(source)
        blockSignals[source] = DispatchSemaphore(value: 0)
        blockingLock.unlock()
    }

    func releaseResolvedThumbnail(for source: String) {
        blockingLock.lock()
        let signal = blockSignals[source]
        blockingPaths.remove(source)
        blockSignals.removeValue(forKey: source)
        blockingLock.unlock()
        signal?.signal()
    }

    func resolvedThumbnailPath(for wallpaper: VideoWallpaper) -> String? {
        blockingLock.lock()
        let signal = blockingPaths.contains(wallpaper.path) ? blockSignals[wallpaper.path] : nil
        blockingLock.unlock()
        if let signal { signal.wait() }
        planLock.lock()
        let result = resolvedPlan[wallpaper.path]
        planLock.unlock()
        resolveLogLock.lock()
        resolveLog.append("\(wallpaper.lastComponent) -> \(result.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "nil")")
        resolveLogLock.unlock()
        return result
    }

    func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    func notifyThumbnailReady(forPath path: String) {
        let normalized = normalizedPath(path)
        if Thread.isMainThread {
            thumbnailReadySubject.send(normalized)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.thumbnailReadySubject.send(normalized)
            }
        }
    }

    func markCardInteraction() {}
    func stopCurrentPlayback() {}
    func requestSetAsWallpaper(_ wallpaper: VideoWallpaper) {}
}

// MARK: - 断言辅助

@MainActor
private var failureNames: [String] = []

@MainActor
private func check(_ condition: Bool, _ name: String) {
    print("RESULT \(name) \(condition ? "PASS" : "FAIL")")
    if !condition { failureNames.append(name) }
}

@MainActor
private func drain(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
private func waitFor(timeout: TimeInterval, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if predicate() { return true }
    }
    return predicate()
}

private func firstSubview(of root: NSView, matching test: (NSView) -> Bool) -> NSView? {
    if test(root) { return root }
    for subview in root.subviews {
        if let found = firstSubview(of: subview, matching: test) { return found }
    }
    return nil
}

/// 「未找到缩略图」提示是否可见（面板唯一的预览缺失提示词条）。
private func noticeVisible(in root: NSView) -> Bool {
    firstSubview(of: root) { view in
        (view as? NSTextField)?.stringValue.contains("未找到缩略图") == true
    } != nil
}

/// 预览面板的占位图（film 图标）是否可见——image != nil 时占位被隐藏。
private func placeholderVisible(in root: NSView) -> Bool {
    guard let surface = firstSubview(of: root, matching: { $0 is VideoLibraryInspectorPreviewSurfaceView }),
          let icon = surface.subviews.first(where: { $0 is NSImageView }) else {
        return false
    }
    return !icon.isHidden
}

/// 预览面板中心像素（aspect-fill 后中心必然落在图片内），用于区分“哪张图”。
private func centerPixel(in root: NSView) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
    guard let surface = firstSubview(of: root, matching: { $0 is VideoLibraryInspectorPreviewSurfaceView }),
          let rep = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else {
        return nil
    }
    surface.cacheDisplay(in: surface.bounds, to: rep)
    guard let color = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2) else { return nil }
    return (color.redComponent, color.greenComponent, color.blueComponent)
}

private func looksRed(_ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat)?) -> Bool {
    guard let pixel else { return false }
    return pixel.red > 0.55 && pixel.green < 0.45 && pixel.blue < 0.45
}

private func looksBlue(_ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat)?) -> Bool {
    guard let pixel else { return false }
    return pixel.blue > 0.55 && pixel.red < 0.45 && pixel.green < 0.45
}

private func looksGreen(_ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat)?) -> Bool {
    guard let pixel else { return false }
    return pixel.green > 0.55 && pixel.red < 0.45 && pixel.blue < 0.5
}

private func writeJPEG(_ path: String, red: CGFloat, green: CGFloat, blue: CGFloat, width: Int, height: Int) {
    // CGContext 直接填充 sRGB 像素，避免逐像素 setColor 的色彩空间转换噪声
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else {
        fatalError("context creation failed")
    }
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let cgImage = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: cgImage).representation(
              using: .jpeg,
              properties: [.compressionFactor: 1.0]
          ) else {
        fatalError("jpeg encoding failed")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: - 场景

@main
enum Harness {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-video-inspector-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let videoA = root.appendingPathComponent("a.mp4").path
        let videoC = root.appendingPathComponent("c.mp4").path
        let videoD = root.appendingPathComponent("d.mp4").path
        let videoE = root.appendingPathComponent("e.mp4").path
        for path in [videoA, videoC, videoD, videoE] {
            try! Data("stub-video".utf8).write(to: URL(fileURLWithPath: path))
        }
        let thumbRed = root.appendingPathComponent("thumb-red.jpg").path
        let thumbBlue = root.appendingPathComponent("thumb-blue.jpg").path
        let thumbGreen = root.appendingPathComponent("thumb-green.jpg").path
        writeJPEG(thumbRed, red: 0.85, green: 0.10, blue: 0.10, width: 60, height: 40)
        writeJPEG(thumbBlue, red: 0.10, green: 0.15, blue: 0.87, width: 90, height: 50)
        writeJPEG(thumbGreen, red: 0.10, green: 0.82, blue: 0.25, width: 70, height: 44)

        let manager = WallpaperManager()
        let wallpaperA = VideoWallpaper(id: "card-a", title: "A", path: videoA)
        manager.wallpapers = [wallpaperA]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 640))
        window.contentView = container

        let inspector = VideoLibraryInspectorView(wallpaper: wallpaperA, wallpaperManager: manager)
        container.addSubview(inspector)
        NSLayoutConstraint.activate([
            inspector.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: container.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        container.layoutSubtreeIfNeeded()

        // 场景 1：初始缺图——「未找到缩略图」提示出现，占位可见
        let initialNotice = waitFor(timeout: 4.0) { noticeVisible(in: inspector) }
        check(initialNotice, "s1-initial-missing-notice")
        check(placeholderVisible(in: inspector), "s1-initial-placeholder-visible")

        // 场景 2：缩略图生成完成（磁盘补齐 + thumbnailReady 事件）→ 不重开面板即显示
        manager.setResolvedThumbnail(thumbRed, for: videoA)
        manager.notifyThumbnailReady(forPath: videoA)
        let reloaded = waitFor(timeout: 4.0) { !noticeVisible(in: inspector) && !placeholderVisible(in: inspector) }
        let redPixel = centerPixel(in: inspector)
        print("DETAIL s2-pixel \(redPixel.map { "\($0.red) \($0.green) \($0.blue)" } ?? "nil")")
        check(reloaded && looksRed(redPixel), "s2-preview-reloads-on-thumbnail-ready")

        // 场景 3：无关 publish（收藏切换，资产身份不变）不破坏已显示预览
        manager.wallpapers = [
            VideoWallpaper(id: "card-a", title: "A", path: videoA, isFavorite: true)
        ]
        drain(0.5)
        check(!noticeVisible(in: inspector) && looksRed(centerPixel(in: inspector)), "s3-unrelated-publish-keeps-preview")

        // 场景 4：资源替换（同 id 换源路径，新源无预览）→ 旧图清空、缺失提示回归
        manager.setResolvedThumbnail(nil, for: videoD)
        _ = manager.drainResolveLog()
        manager.wallpapers = [VideoWallpaper(id: "card-a", title: "A", path: videoD, isFavorite: true)]
        let cleared = waitFor(timeout: 4.0) { noticeVisible(in: inspector) && placeholderVisible(in: inspector) }
        print("DETAIL s4-resolves \(manager.drainResolveLog())")
        print("DETAIL s4-state notice=\(noticeVisible(in: inspector)) placeholder=\(placeholderVisible(in: inspector))")
        check(cleared && !looksRed(centerPixel(in: inspector)), "s4-replacement-clears-stale-preview")

        // 场景 5：新源的缩略图后到 → 再次按事件刷新为新图
        manager.setResolvedThumbnail(thumbBlue, for: videoD)
        manager.notifyThumbnailReady(forPath: videoD)
        let blueShown = waitFor(timeout: 4.0) { !noticeVisible(in: inspector) && !placeholderVisible(in: inspector) }
        let bluePixel = centerPixel(in: inspector)
        print("DETAIL s5-pixel \(bluePixel.map { "\($0.red) \($0.green) \($0.blue)" } ?? "nil")")
        check(blueShown && looksBlue(bluePixel), "s5-late-ready-swaps-to-new-image")

        // 场景 6：旧代数异步完成不得覆盖新资源状态——
        // 切到 C（解析阻塞在旧请求）再切到 D（无预览），D 完成后释放 C 的解析，
        // C 的图片即使解码完成也必须被丢弃
        manager.setResolvedThumbnail(nil, for: videoD)
        manager.blockResolvedThumbnail(for: videoC)
        manager.setResolvedThumbnail(thumbGreen, for: videoC)
        manager.wallpapers = [VideoWallpaper(id: "card-a", title: "A", path: videoC, isFavorite: true)]
        drain(0.5)
        manager.wallpapers = [VideoWallpaper(id: "card-a", title: "A", path: videoD, isFavorite: true)]
        let backToMissing = waitFor(timeout: 4.0) { noticeVisible(in: inspector) && placeholderVisible(in: inspector) }
        manager.releaseResolvedThumbnail(for: videoC)
        drain(1.5)
        let latePixel = centerPixel(in: inspector)
        print("DETAIL s6-pixel \(latePixel.map { "\($0.red) \($0.green) \($0.blue)" } ?? "nil")")
        print("DETAIL s6-resolves \(manager.drainResolveLog())")
        print("DETAIL s6-state notice=\(noticeVisible(in: inspector)) placeholder=\(placeholderVisible(in: inspector))")
        check(backToMissing && !looksGreen(latePixel) && noticeVisible(in: inspector), "s6-stale-async-completion-dropped")

        // 场景 7：面板关闭（视图释放）后的迟到回调安全
        manager.blockResolvedThumbnail(for: videoE)
        weak var weakInspector: VideoLibraryInspectorView?
        autoreleasepool {
            let second = VideoLibraryInspectorView(
                wallpaper: VideoWallpaper(id: "card-e", title: "E", path: videoE),
                wallpaperManager: manager
            )
            weakInspector = second
            container.addSubview(second)
            drain(0.5)
            second.removeFromSuperview()
        }
        drain(0.2)
        let released = weakInspector == nil
        manager.releaseResolvedThumbnail(for: videoE)
        drain(1.0)
        check(released, "s7-closed-panel-view-released")
        check(true, "s7-late-callback-after-close-safe")

        if failureNames.isEmpty {
            print("ALL SCENARIOS PASS")
        } else {
            print("FAILED: \(failureNames.joined(separator: ","))")
        }
    }
}
