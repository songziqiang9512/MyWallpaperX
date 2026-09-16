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
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    var boxSelectionBeginHandler: ((IndexPath?) -> Bool)?
    var boxSelectionUpdateHandler: ((NSRect) -> Void)?
    var boxSelectionEndHandler: (() -> Void)?
    var isBoxSelectionEnabled = false
    private(set) var lastPrimaryClickIndexPath: IndexPath?
    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

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
            // 这次点击属于卡片交互，外层 SwiftUI 的 TapGesture 需要把它当成内部点击而不是背景清空。
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
            pressedCardIndexPath = indexPath
            pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
            cardPressStateHandler?(indexPath, true)
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
        if let pressedCardIndexPath {
            pendingPressReleaseWorkItem = VideoLibraryCollectionInteractionSupport.schedulePressRelease(
                pressedAt: pressedCardTimestamp
            ) { [weak self] in
                guard let self else { return }
                self.cardPressStateHandler?(pressedCardIndexPath, false)
                self.pressedCardIndexPath = nil
            }
        }
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
        // 回车键：将当前选中的卡片设为壁纸。
        if event.keyCode == 36,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            let manager = WallpaperManager.shared
            if let id = manager.selectedWallpaperId,
               let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
                manager.markCardInteraction()
                manager.requestSetAsWallpaper(wallpaper)
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

final class AppKitThumbnailProvider {
    private let wallpaperManager: WallpaperManager
    private let decodeQueue = DispatchQueue(
        label: "com.mywallpaper.videolibrary.thumbnail.provider",
        qos: .userInitiated
    )

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
    }

    func loadThumbnail(for wallpaper: VideoWallpaper, completion: @escaping (NSImage?) -> Void) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let image: NSImage?
            if let thumbPath = self.wallpaperManager.resolvedThumbnailPath(for: wallpaper) {
                image = NSImage(contentsOfFile: thumbPath)
            } else {
                image = nil
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func prefetchThumbnail(for wallpaper: VideoWallpaper) {
        loadThumbnail(for: wallpaper) { _ in }
    }

    func cancelPrefetch(id: String) {
        _ = id  // ThumbnailCache 不支持取消，保留接口兼容性
    }
}
