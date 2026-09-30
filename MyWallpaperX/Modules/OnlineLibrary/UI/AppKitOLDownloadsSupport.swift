//
//  AppKitOLDownloadsSupport.swift
//  MyWallpaperX - Modules/OnlineLibrary/UI
//

import AppKit
import QuickLook
import QuickLookUI

final class OnlineDownloadsBridge {
    static let shared = OnlineDownloadsBridge()
    weak var container: AppKitOLDownloadsContainerView?
    weak var toolbarController: OnlineLibraryToolbarController?
    /// 当前「已下载项」视图是否挂载在窗口中（用于框架层区分浏览页 vs 已下载项）
    var isActive: Bool = false

    func focusGrid() { container?.focusGrid() }
    func focusSearch() { container?.focusSearch() }
    func selectAll() { container?.selectAll(); refreshToolbar() }
    func toggleMultiSelect() { container?.toggleMultiSelect(); refreshToolbar() }
    func deleteSelected() { container?.deleteSelected(); refreshToolbar() }
    func previewSelected() { container?.previewSelected() }
    func setSelectedAsWallpaper() { container?.setSelectedAsWallpaper() }
    func moveSelection(_ keyCode: UInt16) { container?.moveSelectionByArrowKey(keyCode); refreshToolbar() }
    func showInfo() { container?.showInfo() }
    func revealInFinder() { container?.revealInFinder() }

    var hasAnySelection: Bool { container?.hasAnySelection ?? false }
    var hasSingleSelection: Bool { container?.hasSingleSelection ?? false }
    var isMultiSelectMode: Bool { container?.isMultiSelectModeEnabled ?? false }
    var hasAnyItems: Bool { container?.hasAnyItems ?? false }
    var selectedCount: Int { container?.selectedCount ?? 0 }
    var primarySelectedID: Int? { container?.primarySelectedID }

    func refreshToolbar() {
        toolbarController?.refreshDownloadsToolbarState()
    }
}

final class OLDownloadsQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = OLDownloadsQuickLookController()
    private var previewIDs: [Int] = []
    private var previewItems: [URL] = []
    private var activeIndex: Int = 0
    private var selectionSync: ((Int) -> Void)?

    func open(ids: [Int], urls: [URL], index: Int, selectionSync: @escaping (Int) -> Void) {
        guard !urls.isEmpty, ids.count == urls.count else { return }
        previewIDs = ids
        previewItems = urls
        activeIndex = min(max(0, index), urls.count - 1)
        self.selectionSync = selectionSync
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = activeIndex
        panel.makeKeyAndOrderFront(nil)
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index] as NSURL
    }

    func previewPanelCurrentPreviewItemIndexDidChange(_ panel: QLPreviewPanel!) {
        let index = panel.currentPreviewItemIndex
        guard index >= 0, index < previewIDs.count else { return }
        activeIndex = index
        selectionSync?(previewIDs[index])
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let disallowed: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowed).isEmpty else { return false }

        // 这里接管空格/方向键/ESC，避免系统把事件交回主窗口后再次触发预览开关。
        switch event.keyCode {
        case 49: // Space
            close()
            return true
        case 123, 124, 125, 126: // Arrows
            OnlineDownloadsBridge.shared.moveSelection(event.keyCode)
            panel.reloadData()
            // 网格选择已移动，把新选中项同步进预览面板，保证预览画面跟随方向键浏览。
            if let id = OnlineDownloadsBridge.shared.primarySelectedID,
               let index = previewIDs.firstIndex(of: id) {
                activeIndex = index
                panel.currentPreviewItemIndex = index
            }
            return true
        case 53: // ESC
            close()
            return true
        default:
            return false
        }
    }
}

final class AppKitOLDownloadsCollectionView: NSCollectionView {
    var onBackgroundLeftClick: (() -> Void)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    var primaryClickHandler: ((IndexPath, NSEvent) -> Void)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var deleteHandler: (() -> Void)?
    var spaceHandler: (() -> Void)?
    var enterHandler: (() -> Void)?
    var selectAllHandler: (() -> Void)?
    var arrowHandler: ((UInt16) -> Void)?
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

        if let ip = indexPathForItem(at: point) {
            pressedCardIndexPath = ip
            pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
            cardPressStateHandler?(ip, true)
            primaryClickHandler?(ip, event)
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp else { return }

        if let ip = pressedCardIndexPath {
            pendingPressReleaseWorkItem = OnlineLibraryCollectionInteractionSupport.schedulePressRelease(
                pressedAt: pressedCardTimestamp
            ) { [weak self] in
                self?.cardPressStateHandler?(ip, false)
            }
            pressedCardIndexPath = nil
        }

        let point = convert(event.locationInWindow, from: nil)
        if lastPrimaryClickIndexPath == nil, indexPathForItem(at: point) == nil {
            onBackgroundLeftClick?()
        }
        lastPrimaryClickIndexPath = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, // Return
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            enterHandler?(); return
        }
        if event.keyCode == 0, // Cmd+A
           event.modifierFlags.intersection([.command]) == .command,
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty {
            selectAllHandler?(); return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete
            deleteHandler?(); return
        }
        if event.keyCode == 49 { // Space
            spaceHandler?(); return
        }
        switch event.keyCode {
        case 123, 124, 125, 126:
            arrowHandler?(event.keyCode); return
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        return contextMenuProvider?(indexPath)
    }

    override func selectAll(_ sender: Any?) {
        // 拦截系统 Cmd+A 分发，走自定义全选路径（不触发 NSCollectionView 默认全选行为）
        selectAllHandler?()
    }
}
