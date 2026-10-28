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
import QuartzCore
import Combine
import Foundation

// MARK: - 视图消费面桩（不复制产品逻辑）

struct InspectorSelectionStub {}

enum UIActionHelper {
    static var favoriteWrites = 0
    static var tagWrites = 0
    static func toggleFavoriteSelection(manager: WallpaperManager, selection: InspectorSelectionStub) { favoriteWrites += 1 }
    static func presentTagPicker(
        manager: WallpaperManager,
        window: NSWindow?,
        completion: @escaping () -> Void
    ) { tagWrites += 1 }
}

struct WallpaperInspectorDetails: Equatable {
    let fileSizeText: String
    let formatText: String
    let durationText: String
    let codecText: String
    let resolutionText: String
    let addedDateText: String
    let pathText: String
    var isLoading = false
}

@MainActor
private enum InspectorMetadataProbe {
    static var starts: [String: Int] = [:]
    static var terminals: [String: Int] = [:]
    static var heldPaths: Set<String> = []
    static var pending: [String: [CheckedContinuation<Void, Never>]] = [:]
    static func waitIfHeld(_ path: String) async {
        if heldPaths.contains(path) {
            await withCheckedContinuation { pending[path, default: []].append($0) }
        }
    }
    static func release(_ path: String) {
        heldPaths.remove(path)
        let waiters = pending.removeValue(forKey: path) ?? []
        waiters.forEach { $0.resume() }
    }
}

@MainActor
@discardableResult
func loadWallpaperInspectorDetails(
    for wallpaper: VideoWallpaper,
    completion: @escaping (WallpaperInspectorDetails) -> Void
) -> Task<Void, Never> {
    InspectorMetadataProbe.starts[wallpaper.path, default: 0] += 1
    completion(WallpaperInspectorDetails(fileSizeText: "1 MB", formatText: "MP4", durationText: "读取中…",
        codecText: "读取中…", resolutionText: "读取中…", addedDateText: "2026年10月25日 20:30", pathText: wallpaper.path, isLoading: true))
    return Task {
        await InspectorMetadataProbe.waitIfHeld(wallpaper.path)
        await MainActor.run {
            guard !Task.isCancelled else { return }
            InspectorMetadataProbe.terminals[wallpaper.path, default: 0] += 1
            completion(WallpaperInspectorDetails(
                fileSizeText: "1 MB",
                formatText: "MP4",
                durationText: "0:30",
                codecText: "High Efficiency Video Coding Long Value",
                resolutionText: "3840×2160",
                addedDateText: "2026年10月25日 20:30",
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

/// Observes real cache API registrations and controlled producer leaves. The
/// production cache still chooses, coalesces and cancels every queued request.
nonisolated final class InspectorCacheDemandProbe: @unchecked Sendable {
    static let shared = InspectorCacheDemandProbe()
    private struct Registration { let cancellation: (any ThumbnailCacheLoadCancellation)? }
    private let lock = NSLock()
    private var registrations: [String: [Registration]] = [:]
    private var loads: [String: Int] = [:]
    func registered(_ key: String, cancellation: (any ThumbnailCacheLoadCancellation)?) {
        lock.lock(); defer { lock.unlock() }
        registrations[key, default: []].append(.init(cancellation: cancellation))
    }
    func registrationCount(_ key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return registrations[key]?.count ?? 0
    }
    func allRegistrationsCancelled(_ key: String) -> Bool {
        lock.lock(); let values = registrations[key] ?? []; lock.unlock()
        return !values.isEmpty && values.allSatisfy { $0.cancellation?.cancelled == true }
    }
    func loaded(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        loads[key, default: 0] += 1
    }
    func loadCount(_ key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return loads[key] ?? 0
    }
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
    var primaryWrites = 0
    func stopCurrentPlayback() { primaryWrites += 1 }
    func requestSetAsWallpaper(_ wallpaper: VideoWallpaper) { primaryWrites += 1 }
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
        (view as? NSTextField)?.stringValue.contains("未找到缩略图") == true && !view.isHiddenOrHasHiddenAncestor
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
        let runtimeHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let isolatedRoot = URL(fileURLWithPath: runtimeHome).resolvingSymlinksInPath().path
        precondition(caches.resolvingSymlinksInPath().path.hasPrefix(isolatedRoot + "/"),
                     "cache root must be isolated: \(caches.path)")
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
        let wallpaperA = VideoWallpaper(id: "card-a", title: "A", path: videoA, tags: ["保留原标签"])
        manager.wallpapers = [wallpaperA]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 640))
        window.contentView = container

        let previewActions = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: false,
            canPerformPrimary: false, canFavorite: false, canOrganize: false, playlistNames: ["已迁移列表"]),
            onPrimary: {}, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        let inspector = VideoLibraryInspectorView(wallpaper: wallpaperA, wallpaperManager: manager, libraryActions: previewActions)
        container.addSubview(inspector)
        NSLayoutConstraint.activate([
            inspector.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: container.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        container.layoutSubtreeIfNeeded()
        let initialPreview = firstSubview(of: inspector) { $0 is VideoLibraryInspectorPreviewSurfaceView }!
        let initialFrame = initialPreview.convert(initialPreview.bounds, to: container)
        let initialPreviewConstraintCount = initialPreview.constraints.count
        let detailScroll = firstSubview(of: inspector) { $0 is InspectorFadingScrollView } as! InspectorFadingScrollView
        let detailDocument = detailScroll.documentView!
        let initialViewport = detailDocument.convert(detailScroll.contentView.bounds, from: detailScroll.contentView)
        let initialImageRect = initialPreview.convert(initialPreview.bounds, to: detailDocument)
        let topColors = (detailScroll.layer?.mask as? CAGradientLayer)?.colors as? [CGColor]
        check(detailDocument.isFlipped && initialViewport.contains(initialImageRect)
            && abs(initialImageRect.minY - initialViewport.minY - 8) <= 1 / window.backingScaleFactor
            && topColors?.first?.alpha == 1,
            "s11-first-video-preview-starts-at-safe-unfaded-top")

        // 场景 1：初始缺图——「未找到缩略图」提示出现，占位可见
        let initialNotice = waitFor(timeout: 4.0) { noticeVisible(in: inspector) }
        check(initialNotice, "s1-initial-missing-notice")
        check(placeholderVisible(in: inspector), "s1-initial-placeholder-visible")
        container.layoutSubtreeIfNeeded()
        let missingSurface = firstSubview(of: inspector) { $0 is VideoLibraryInspectorPreviewSurfaceView }!
        let missingText = firstSubview(of: missingSurface) { ($0 as? NSTextField)?.stringValue.contains("未找到缩略图") == true }!
        let missingGlyph = firstSubview(of: missingSurface) { $0 is NSImageView }!
        let textRect = missingText.convert(missingText.bounds, to: missingSurface)
        let glyphRect = missingGlyph.convert(missingGlyph.bounds, to: missingSurface)
        check(missingSurface.bounds.contains(textRect) && !textRect.intersects(glyphRect),
              "s10-missing-preview-message-fits-without-covering-its-placeholder")
        container.layoutSubtreeIfNeeded()
        let metadataPreview = firstSubview(of: inspector) { $0 is VideoLibraryInspectorPreviewSurfaceView }!
        let metadataFrame = metadataPreview.convert(metadataPreview.bounds, to: container)
        print("DETAIL metadata-layout before=\(initialFrame) after=\(metadataFrame)")
        check(initialPreview === metadataPreview && initialFrame == metadataFrame, "s10-metadata-and-missing-preview-keep-native-preview-frame")
        check(firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "已迁移列表" } != nil
            && firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "保留原标签" } == nil,
              "s1-required-store-membership-only")

        precondition(waitFor(timeout: 4) {
            firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "High Efficiency Video Coding Long Value" } != nil
        }, "metadata layout requires the completed source values")
        container.layoutSubtreeIfNeeded()
        let codecValue = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "High Efficiency Video Coding Long Value" } as! NSTextField
        let resolutionValue = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "3840×2160" } as! NSTextField
        let addedTitle = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "添加时间" } as! NSTextField
        let addedValue = (addedTitle.superview as! NSStackView).arrangedSubviews.last as! NSTextField
        let metadataTitle = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "原数据" }!
        let metadataSection = metadataTitle.superview as! NSStackView
        let metadataGrid = metadataSection.arrangedSubviews.last as! NSStackView
        let rows = metadataGrid.arrangedSubviews.map { $0.convert($0.bounds, to: detailDocument) }.sorted { $0.minY < $1.minY }
        let singleLineHeight = ceil(addedValue.font!.ascender - addedValue.font!.descender + addedValue.font!.leading) + 4
        check(addedValue.bounds.height <= singleLineHeight && resolutionValue.bounds.height <= singleLineHeight
            && codecValue.bounds.height <= 2 * singleLineHeight && !codecValue.stringValue.isEmpty
            && codecValue.bounds.width > 0 && addedValue.isSelectable && resolutionValue.isSelectable,
            "s14-metadata-uses-natural-single-line-height-with-two-line-long-values-preserved")
        check(rows.count == 2 && rows[1].minY - rows[0].maxY >= 8 && rows[1].minY - rows[0].maxY <= 16
            && metadataGrid.bounds.height <= 8 * singleLineHeight,
            "s14-metadata-rows-stay-compact-without-stretching-to-fill-the-panel")
        let secondaryFacts = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue.contains(" · ") == true } as! NSTextField
        let secondaryLineHeight = ceil(secondaryFacts.font!.ascender - secondaryFacts.font!.descender + secondaryFacts.font!.leading) + 4
        check(secondaryFacts.bounds.height <= secondaryLineHeight,
            "s14-single-line-file-summary-does-not-reserve-a-blank-second-line")

        // 场景 2：缩略图生成完成（磁盘补齐 + thumbnailReady 事件）→ 不重开面板即显示
        manager.setResolvedThumbnail(thumbRed, for: videoA)
        manager.notifyThumbnailReady(forPath: videoA)
        let reloaded = waitFor(timeout: 4.0) { !noticeVisible(in: inspector) && !placeholderVisible(in: inspector) }
        let redPixel = centerPixel(in: inspector)
        print("DETAIL s2-pixel \(redPixel.map { "\($0.red) \($0.green) \($0.blue)" } ?? "nil")")
        check(reloaded && looksRed(redPixel), "s2-preview-reloads-on-thumbnail-ready")
        container.layoutSubtreeIfNeeded()
        let filledPreview = firstSubview(of: inspector) { $0 is VideoLibraryInspectorPreviewSurfaceView }!
        check(filledPreview === initialPreview && filledPreview.convert(filledPreview.bounds, to: container) == initialFrame,
              "s10-thumbnail-arrival-updates-only-the-same-fixed-preview")

        // 场景 3：无关 publish（收藏切换，资产身份不变）不重复读取预览
        _ = manager.drainResolveLog()
        manager.wallpapers = [
            VideoWallpaper(id: "card-a", title: "A", path: videoA, isFavorite: true, tags: ["保留原标签"])
        ]
        drain(0.5)
        check(!noticeVisible(in: inspector) && looksRed(centerPixel(in: inspector))
              && manager.drainResolveLog().isEmpty, "s3-unrelated-publish-keeps-preview")

        check(initialPreview.constraints.count == initialPreviewConstraintCount,
              "s10-preview-constraints-do-not-grow-on-metadata-or-source-echoes")

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

        // 同路径静帧后到只发布模型，不发送 thumbnailReady。
        manager.wallpapers = [VideoWallpaper(
            id: "card-a", title: "A", path: videoD, staticFramePath: thumbRed
        )]
        check(waitFor(timeout: 4.0) { looksRed(centerPixel(in: inspector)) },
              "s8-same-path-static-frame-arrives")
        manager.wallpapers = [VideoWallpaper(
            id: "card-a", title: "A", path: videoD, staticFramePath: thumbBlue
        )]
        check(waitFor(timeout: 4.0) { looksBlue(centerPixel(in: inspector)) },
              "s8-same-path-static-frame-replaced")
        manager.wallpapers = [VideoWallpaper(id: "card-a", title: "A", path: videoD)]
        check(waitFor(timeout: 4.0) { noticeVisible(in: inspector) && placeholderVisible(in: inspector) },
              "s8-same-path-derived-assets-cleared")

        let originalSize = window.contentView!.bounds.size
        window.setContentSize(NSSize(width: originalSize.width, height: 320))
        container.layoutSubtreeIfNeeded()
        let maximumOffset = detailDocument.bounds.height - detailScroll.contentView.bounds.height
        detailScroll.contentView.scroll(to: NSPoint(x: 0, y: min(37, maximumOffset)))
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
        let scrolledColors = (detailScroll.layer?.mask as? CAGradientLayer)?.colors as? [CGColor]
        detailScroll.contentView.scroll(to: .zero)
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
        let returnedColors = (detailScroll.layer?.mask as? CAGradientLayer)?.colors as? [CGColor]
        let returnedViewport = detailDocument.convert(detailScroll.contentView.bounds, from: detailScroll.contentView)
        let returnedImageRect = initialPreview.convert(initialPreview.bounds, to: detailDocument)
        check(maximumOffset >= 37 && scrolledColors?.first?.alpha == 0 && returnedColors?.first?.alpha == 1
            && returnedViewport.contains(returnedImageRect) && returnedImageRect.minY == 8
            && initialPreview === firstSubview(of: inspector) { $0 is VideoLibraryInspectorPreviewSurfaceView },
            "s11-native-video-scroll-enables-fade-only-away-from-top")
        window.setContentSize(originalSize); container.layoutSubtreeIfNeeded()

        // 场景 7：面板关闭（视图释放）后的迟到回调安全
        manager.blockResolvedThumbnail(for: videoE)
        weak var weakInspector: VideoLibraryInspectorView?
        autoreleasepool {
            let second = VideoLibraryInspectorView(
                wallpaper: VideoWallpaper(id: "card-e", title: "E", path: videoE),
                wallpaperManager: manager, libraryActions: previewActions
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

        var newFavorite = 0, newMembership = 0, newPrimary = 0
        let actions = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: true, canPerformPrimary: true,
            canFavorite: true, canOrganize: true, playlistNames: ["New Store List"]), onPrimary: { newPrimary += 1 },
            onToggleFavorite: { newFavorite += 1 }, onChoosePlaylist: { _ in newMembership += 1 })
        let organized = VideoLibraryInspectorView(wallpaper: wallpaperA, wallpaperManager: manager, libraryActions: actions)
        container.addSubview(organized)
        organized.updateLibraryActions(actions)
        check(firstSubview(of: organized) { ($0 as? NSTextField)?.stringValue == "New Store List" } != nil
            && firstSubview(of: organized) { ($0 as? NSTextField)?.stringValue == "保留原标签" } == nil,
            "s9-injected-membership-replaces-old-tags-with-new-store-names")
        _ = organized.perform(NSSelectorFromString("toggleFavorite"))
        _ = organized.perform(NSSelectorFromString("presentTagPicker"))
        _ = organized.perform(NSSelectorFromString("setAsWallpaper"))
        check(newFavorite == 1 && newMembership == 1 && newPrimary == 1 && UIActionHelper.favoriteWrites == 0
            && UIActionHelper.tagWrites == 0 && manager.primaryWrites == 0, "s9-fixed-actions-never-write-old-selection-owners")
        let readonly = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: true, canPerformPrimary: true,
            canFavorite: false, canOrganize: false, playlistNames: ["New Store List"]), onPrimary: { newPrimary += 1 },
            onToggleFavorite: { newFavorite += 1 }, onChoosePlaylist: { _ in newMembership += 1 })
        organized.updateLibraryActions(readonly)
        _ = organized.perform(NSSelectorFromString("toggleFavorite"))
        _ = organized.perform(NSSelectorFromString("presentTagPicker"))
        check(newFavorite == 1 && newMembership == 1 && UIActionHelper.favoriteWrites == 0 && UIActionHelper.tagWrites == 0,
            "s9-readonly-injected-actions-refuse-organization")
        check(firstSubview(of: organized) { ($0 as? NSScrollView).map { !$0.hasVerticalScroller && !$0.hasHorizontalScroller } == true } != nil,
            "s9-original-hidden-inspector-scrollbars-preserved")
        let offlineFavorite = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: true, canPerformPrimary: false,
            canFavorite: true, canOrganize: false, playlistNames: ["New Store List"]), onPrimary: { newPrimary += 1 },
            onToggleFavorite: { newFavorite += 1 }, onChoosePlaylist: { _ in newMembership += 1 })
        organized.updateLibraryActions(offlineFavorite)
        let favoriteControl = firstSubview(of: organized) { ($0 as? InspectorFooterButton)?.action == NSSelectorFromString("toggleFavorite") } as? InspectorFooterButton
        let playlistControl = firstSubview(of: organized) { ($0 as? InspectorFooterButton)?.action == NSSelectorFromString("presentTagPicker") } as? InspectorFooterButton
        let offlinePress = favoriteControl?.accessibilityPerformPress() == true
        _ = organized.perform(NSSelectorFromString("presentTagPicker"))
        check(favoriteControl?.isEnabled == true && offlinePress && newFavorite == 2 && playlistControl?.isEnabled == false
            && newMembership == 1 && newPrimary == 1, "s9-native-offline-favorite-removes-without-enabling-list-or-playback")
        organized.updateLibraryActions(readonly)
        let readonlyFavoriteControl = firstSubview(of: organized) { ($0 as? InspectorFooterButton)?.action == NSSelectorFromString("toggleFavorite") } as? InspectorFooterButton
        check(readonlyFavoriteControl?.isEnabled == false && readonlyFavoriteControl?.accessibilityPerformPress() == false
            && newFavorite == 2, "s9-native-readonly-favorite-refuses-accessibility-press")
        organized.removeFromSuperview()

        // Hold the actual single generation lane. A separate public consumer
        // supplies the queued producer leaf, then withdraws once the real view
        // has joined. No private cache state or product cancellation is mocked.
        let demandProbe = InspectorCacheDemandProbe.shared
        let demandCache = VideoLibraryThumbnailStore.sharedCache
        func makeDemandView(_ key: String, manager: WallpaperManager) -> VideoLibraryInspectorView {
            let value = VideoWallpaper(id: key, title: "Lease", path: videoA)
            manager.wallpapers = [value]
            manager.setResolvedThumbnail(key, for: videoA)
            let view = VideoLibraryInspectorView(wallpaper: value, wallpaperManager: manager, libraryActions: previewActions)
            container.addSubview(view)
            view.frame = container.bounds
            view.layoutSubtreeIfNeeded()
            return view
        }
        func blockGeneration(_ name: String) -> DispatchSemaphore {
            let release = DispatchSemaphore(value: 0)
            demandCache.load(forKey: name, loader: {
                demandProbe.loaded(name)
                precondition(release.wait(timeout: .now() + 10) == .success, "generation blocker was not released")
                return nil
            }, completion: { _ in })
            precondition(waitFor(timeout: 3) { demandProbe.loadCount(name) == 1 })
            return release
        }
        let queuedPath = root.appendingPathComponent("cancelled-inspector.jpg").path
        writeJPEG(queuedPath, red: 0.1, green: 0.8, blue: 0.2, width: 24, height: 24)
        let queuedRelease = blockGeneration("queue-blocker-\(UUID().uuidString)")
        let queuedConsumer = ThumbnailCacheRequestCancellation()
        demandCache.load(forKey: queuedPath, cancellation: queuedConsumer, loader: {
            demandProbe.loaded(queuedPath)
            return NSImage(contentsOfFile: queuedPath)
        }, completion: { _ in })
        let queuedManager = WallpaperManager()
        let queuedView = makeDemandView(queuedPath, manager: queuedManager)
        precondition(waitFor(timeout: 3) { demandProbe.registrationCount(queuedPath) == 2 })
        queuedConsumer.cancel()
        queuedView.removeFromSuperview()
        let requestsBeforeNotification = demandProbe.registrationCount(queuedPath)
        queuedManager.notifyThumbnailReady(forPath: videoA)
        drain(0.1)
        check(demandProbe.registrationCount(queuedPath) == requestsBeforeNotification,
              "s12-removed-inspector-does-not-reacquire-on-thumbnail-notification")
        queuedRelease.signal()
        var queueDrained = false
        demandCache.load(forKey: "queue-drain-\(UUID().uuidString)", loader: { nil }, completion: { _ in queueDrained = true })
        precondition(waitFor(timeout: 3) { queueDrained })
        check(demandProbe.allRegistrationsCancelled(queuedPath) && demandProbe.loadCount(queuedPath) == 0
            && demandCache.cachedImage(forKey: queuedPath) == nil,
              "s12-removed-only-consumer-detaches-before-queued-loader")

        let sharedPath = root.appendingPathComponent("shared-inspector.jpg").path
        writeJPEG(sharedPath, red: 0.1, green: 0.8, blue: 0.2, width: 24, height: 24)
        let sharedRelease = blockGeneration("shared-blocker-\(UUID().uuidString)")
        let producerConsumer = ThumbnailCacheRequestCancellation()
        demandCache.load(forKey: sharedPath, cancellation: producerConsumer, loader: {
            demandProbe.loaded(sharedPath)
            return NSImage(contentsOfFile: sharedPath)
        }, completion: { _ in })
        let sharedManager = WallpaperManager()
        let withdrawn = makeDemandView(sharedPath, manager: sharedManager)
        let remaining = makeDemandView(sharedPath, manager: sharedManager)
        precondition(waitFor(timeout: 3) { demandProbe.registrationCount(sharedPath) == 3 })
        producerConsumer.cancel()
        withdrawn.removeFromSuperview()
        sharedRelease.signal()
        precondition(waitFor(timeout: 3) { !placeholderVisible(in: remaining) })
        check(demandProbe.loadCount(sharedPath) == 1 && looksGreen(centerPixel(in: remaining)),
              "s12-other-consumer-keeps-the-shared-producer-alive")
        check(placeholderVisible(in: withdrawn), "s12-removed-consumer-does-not-receive-shared-result")
        container.addSubview(withdrawn)
        withdrawn.frame = container.bounds; withdrawn.layoutSubtreeIfNeeded()
        precondition(waitFor(timeout: 3) { !placeholderVisible(in: withdrawn) })
        let shownImage = firstSubview(of: withdrawn) { $0 is VideoLibraryInspectorPreviewSurfaceView }
        withdrawn.removeFromSuperview()
        container.addSubview(withdrawn); withdrawn.layoutSubtreeIfNeeded()
        check(!placeholderVisible(in: withdrawn) && demandProbe.loadCount(sharedPath) == 1
            && shownImage === firstSubview(of: withdrawn) { $0 is VideoLibraryInspectorPreviewSurfaceView },
              "s12-remount-reacquires-without-clearing-or-decoding-current-image")
        withdrawn.removeFromSuperview(); remaining.removeFromSuperview()

        let releasedPath = root.appendingPathComponent("released-inspector.jpg").path
        writeJPEG(releasedPath, red: 0.8, green: 0.1, blue: 0.2, width: 24, height: 24)
        let releasedManager = WallpaperManager()
        weak var releasedDemandView: VideoLibraryInspectorView?
        autoreleasepool {
            let value = makeDemandView(releasedPath, manager: releasedManager)
            releasedDemandView = value
            precondition(waitFor(timeout: 3) { demandProbe.registrationCount(releasedPath) == 1 })
            value.removeFromSuperview()
        }
        drain(0.05)
        check(releasedDemandView == nil && demandProbe.allRegistrationsCancelled(releasedPath),
              "s12-released-view-cancels-its-registered-consumer")

        let metadataPath = root.appendingPathComponent("pending-metadata.mp4").path
        try! Data("pending-metadata".utf8).write(to: URL(fileURLWithPath: metadataPath))
        let metadataManager = WallpaperManager()
        let metadataWallpaper = VideoWallpaper(id: "pending-metadata", title: "Metadata", path: metadataPath)
        metadataManager.wallpapers = [metadataWallpaper]
        metadataManager.setResolvedThumbnail(thumbGreen, for: metadataPath)
        InspectorMetadataProbe.heldPaths.insert(metadataPath)
        let metadataView = VideoLibraryInspectorView(wallpaper: metadataWallpaper, wallpaperManager: metadataManager, libraryActions: previewActions)
        container.addSubview(metadataView); metadataView.frame = container.bounds
        precondition(waitFor(timeout: 3) { InspectorMetadataProbe.pending[metadataPath]?.count == 1 })
        check(InspectorMetadataProbe.starts[metadataPath] == 1,
              "s13-first-mount-does-not-duplicate-inflight-metadata")
        metadataView.removeFromSuperview()
        container.addSubview(metadataView); metadataView.layoutSubtreeIfNeeded()
        precondition(waitFor(timeout: 3) { InspectorMetadataProbe.pending[metadataPath]?.count == 2 })
        InspectorMetadataProbe.release(metadataPath)
        precondition(waitFor(timeout: 3) {
            firstSubview(of: metadataView) { ($0 as? NSTextField)?.stringValue == "High Efficiency Video Coding Long Value" } != nil
        })
        check(InspectorMetadataProbe.starts[metadataPath] == 2 && InspectorMetadataProbe.terminals[metadataPath] == 1,
              "s13-pending-metadata-remount-restarts-and-reaches-final-values")
        metadataView.removeFromSuperview()
        container.addSubview(metadataView); metadataView.layoutSubtreeIfNeeded(); drain(0.05)
        check(InspectorMetadataProbe.starts[metadataPath] == 2 && InspectorMetadataProbe.terminals[metadataPath] == 1,
              "s13-completed-metadata-remount-does-not-reread")
        metadataView.removeFromSuperview()

        if failureNames.isEmpty {
            print("ALL SCENARIOS PASS")
        } else {
            print("FAILED: \(failureNames.joined(separator: ","))")
        }
    }
}
