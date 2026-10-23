//
//  AppKitLibraryGridSupport.swift
//  MyWallpaperX
//

import AppKit
import Foundation

final class AppKitWallpaperCollectionView: NSCollectionView, GridCollectionViewProtocol {
    var onBackgroundLeftClick: (() -> Void)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var cardInteractionHandler: (() -> Void)?
    var playRequestHandler: ((IndexPath) -> Void)?
    var primaryClickHandler: ((IndexPath) -> Bool)?
    var boxSelectionBeginHandler: ((IndexPath?) -> Bool)?
    var boxSelectionUpdateHandler: ((NSRect) -> Void)?
    var boxSelectionEndHandler: (() -> Void)?
    var isBoxSelectionEnabled = false
    private(set) var lastPrimaryClickIndexPath: IndexPath?

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        lastPrimaryClickIndexPath = indexPath

        if isBoxSelectionEnabled,
           event.clickCount == 1,
           boxSelectionBeginHandler?(indexPath) == true {
            handleBoxSelectionLoop(startPoint: point)
            return
        }

        if let indexPath {
            // 将卡片区域交互交给协议提供的可选处理器。
            cardInteractionHandler?()

            if let item = item(at: indexPath) as? AppKitWallpaperItem {
                let itemPoint = item.view.convert(point, from: self)
                if item.shouldTriggerPlayAction(at: itemPoint) {
                    playRequestHandler?(indexPath)
                    return // Playback consumes this click; never also open the inspector.
                }
            }
        }

        if let indexPath {
            if primaryClickHandler?(indexPath) == true {
                return
            }
        }

        super.mouseDown(with: event)
    }

    private func handleBoxSelectionLoop(startPoint: NSPoint) {
        guard let window else {
            boxSelectionEndHandler?()
            return
        }

        boxSelectionUpdateHandler?(selectionRect(from: startPoint, to: startPoint))
        while true {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                boxSelectionEndHandler?()
                return
            }

            let point = convert(nextEvent.locationInWindow, from: nil)
            boxSelectionUpdateHandler?(selectionRect(from: startPoint, to: point))

            if nextEvent.type == .leftMouseUp {
                boxSelectionEndHandler?()
                lastPrimaryClickIndexPath = nil
                return
            }
        }
    }

    private func selectionRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        let origin = NSPoint(x: min(start.x, end.x), y: min(start.y, end.y))
        let size = NSSize(width: abs(start.x - end.x), height: abs(start.y - end.y))
        return NSRect(origin: origin, size: size)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp else { return }
        let point = convert(event.locationInWindow, from: nil)
        if lastPrimaryClickIndexPath == nil, indexPathForItem(at: point) == nil {
            onBackgroundLeftClick?()
        }
        lastPrimaryClickIndexPath = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        return contextMenuProvider?(indexPath)
    }

    override func keyDown(with event: NSEvent) {
        // 方向键由 WallpaperManager 统一处理选中态移动，不走 NSCollectionView 默认行为。
        if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            switch event.keyCode {
            case 123, 124, 125, 126:
                WallpaperManager.shared.moveSingleSelectionByArrowKey(event.keyCode)
                return
            default:
                break
            }
        }
        // 回车键：将当前选中的卡片设为壁纸；正在播放则停止（与卡片点击
        // 同一互斥语义）。
        if event.keyCode == 36,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            let manager = WallpaperManager.shared
            if let id = manager.selectedWallpaperId,
               let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
                if manager.effectiveCurrentWallpaper?.path == wallpaper.path {
                    manager.stopCurrentPlayback()
                } else {
                    manager.requestSetAsWallpaper(wallpaper)
                }
            }
            return
        }
        // ⌘A：多选模式下全选当前分类所有壁纸。
        if event.keyCode == 0,
           event.modifierFlags.intersection([.command]) == .command,
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty {
            let manager = WallpaperManager.shared
            if manager.isMultiSelectMode {
                let selection = manager.currentSelectionContext
                let targetIDs = Set(selection.sourceWallpapers(from: manager).map(\.id))
                manager.replaceMultiSelection(with: targetIDs)
                return
            }
        }
        super.keyDown(with: event)
    }
}

/// 视频库缩略图共享缓存，模式与 SILThumbnailStore 一致：
/// NSCache 内存缓存 + in-flight 去重 + 磁盘层都由 ThumbnailCache 承担。
enum VideoLibraryThumbnailStore {
    static let sharedCache = ThumbnailCache(
        label: "com.mywallpaper.videolibrary.thumbnail",
        countLimit: 360,
        // 网格 + Inspector 共用，128MB 封顶防止长会话膨胀（预算总表见 ThumbnailCache.init 注释）
        totalCostLimit: 128 * 1024 * 1024,
        namespace: "videolibrary"
    )
}

final class AppKitThumbnailProvider {
    private let wallpaperManager: WallpaperManager
    private let cache = VideoLibraryThumbnailStore.sharedCache
    private let decodeQueue = DispatchQueue(
        label: "com.mywallpaper.videolibrary.thumbnail.provider",
        qos: .userInitiated
    )

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
    }

    private struct Prefetch {
        let path: String
        let thumbnailPath: String?
        let cancellation: ThumbnailCacheRequestCancellation
        var readyKey: String?
    }
    private var prefetches: [String: Prefetch] = [:]

    deinit { prefetches.values.forEach { $0.cancellation.cancel() } }

    @discardableResult
    func loadThumbnail(for wallpaper: VideoWallpaper, priority: ThumbnailCacheRequestPriority = .visible,
                       completion: @escaping (NSImage?) -> Void) -> ThumbnailCacheRequestCancellation {
        let cancellation = ThumbnailCacheRequestCancellation()
        loadThumbnail(for: wallpaper, priority: priority, cancellation: cancellation) { image, _ in completion(image) }
        return cancellation
    }

    private func loadThumbnail(for wallpaper: VideoWallpaper, priority: ThumbnailCacheRequestPriority,
                               cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (NSImage?, String?) -> Void) {
        decodeQueue.async { [weak self] in
            guard let self, !cancellation.cancelled else { return }
            // The derived asset must remain valid after clear/rebuild. A source
            // video path alone cannot identify a reusable thumbnail.
            guard let thumbPath = self.wallpaperManager.resolvedThumbnailPath(for: wallpaper) else {
                DispatchQueue.main.async { if !cancellation.cancelled { completion(nil, nil) } }
                return
            }
            guard !cancellation.cancelled else { return }
            self.cache.load(forKey: thumbPath, priority: priority, cancellation: cancellation, loader: {
                NSImage(contentsOfFile: thumbPath)
            }, completion: { image in
                DispatchQueue.main.async { if !cancellation.cancelled { completion(image, thumbPath) } }
            })
        }
    }

    /// A grid owns one desired set. Removed consumers release their lease;
    /// another visible consumer of the same derived path remains unaffected.
    func replacePrefetch(with wallpapers: [VideoWallpaper], retainingVisible visible: [VideoWallpaper] = []) {
        let wanted = Set((wallpapers + visible).map(\.id))
        for id in Array(prefetches.keys) where !wanted.contains(id) { cancelPrefetch(id: id) }
        for (wallpaper, startsIfMissing) in wallpapers.map({ ($0, true) }) + visible.map({ ($0, false) }) {
            if let old = prefetches[wallpaper.id], old.path == wallpaper.path,
               old.thumbnailPath == wallpaper.thumbnailPath,
               old.readyKey.map({ cache.cachedImage(forKey: $0) != nil }) ?? true { continue }
            cancelPrefetch(id: wallpaper.id)
            guard startsIfMissing else { continue }
            let cancellation = ThumbnailCacheRequestCancellation()
            prefetches[wallpaper.id] = Prefetch(path: wallpaper.path, thumbnailPath: wallpaper.thumbnailPath,
                                               cancellation: cancellation, readyKey: nil)
            loadThumbnail(for: wallpaper, priority: .prefetch, cancellation: cancellation) { [weak self] image, key in
                guard let self, !cancellation.cancelled, image != nil,
                      self.prefetches[wallpaper.id]?.cancellation === cancellation else { return }
                self.prefetches[wallpaper.id]?.readyKey = key
            }
        }
    }

    func cancelPrefetch(id: String) { prefetches.removeValue(forKey: id)?.cancellation.cancel() }
    func cancelAllPrefetch() {
        prefetches.values.forEach { $0.cancellation.cancel() }
        prefetches.removeAll()
    }
}
