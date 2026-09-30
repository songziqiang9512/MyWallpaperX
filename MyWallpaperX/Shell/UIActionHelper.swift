//
//  UIActionHelper.swift
//  MyWallpaperX
//

import AppKit

enum UIActionHelper {
    struct SelectedItemAccessor {
        // 侧边栏 / SwiftUI 之间只通过这对闭包同步选中项，不共享 view 实例。
        let get: () -> SelectedItem
        let set: (SelectedItem) -> Void
    }

    static func handleImportOrSelectAll(
        manager: WallpaperManager,
        selection: WallpaperSelectionContext,
        window: NSWindow?
    ) {
        // 导入按钮在多选模式下复用为“全选/取消全选”，非多选才打开导入面板。
        if manager.isMultiSelectMode {
            let targetWallpapers = selection.sourceWallpapers(from: manager)
            let targetIds = Set(targetWallpapers.map(\.id))
            if manager.effectiveSelectedWallpaperIDs == targetIds && !targetWallpapers.isEmpty {
                manager.replaceMultiSelection(with: [])
            } else {
                manager.replaceMultiSelection(with: targetIds)
            }
            return
        }

        manager.importVideos(
            presentingIn: resolvedHostWindow(window),
            context: selection.importContext
        )
    }

    static func performDelete(
        manager: WallpaperManager,
        selection: WallpaperSelectionContext,
        window: NSWindow?
    ) {
        // 删除动作统一在一个入口弹确认框，并根据 selection 的删除范围决定具体 scope。
        let alert = makeAppAlert(
            title: "确认删除",
            message: manager.isMultiSelectMode ? "确定要删除选中的所有壁纸吗？" : "确定要删除选中的壁纸吗？",
            style: .warning,
            buttons: ["删除", "取消"]
        )

        presentAppAlert(alert, in: resolvedHostWindow(window)) { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let scope = selection.deletionScope else { return }
            let sourceWallpapers = selection.sourceWallpapers(from: manager)
            let wallpapersToRemove = selectedWallpapers(from: sourceWallpapers, manager: manager)

            manager.removeWallpapers(wallpapersToRemove, in: scope) { summary in
                guard summary.hasFailures else { return }
                let failureAlert = makeAppAlert(
                    title: "部分清理失败",
                    message: summary.informativeText,
                    style: .warning,
                    buttons: ["知道了"]
                )
                presentAppAlert(failureAlert, in: resolvedHostWindow(window))
            }
            exitMultiSelectIfNeeded(manager: manager)
        }
    }

    /// 无确认弹窗的直接删除，用于快捷键场景。
    static func performDeleteWithoutConfirmation(
        manager: WallpaperManager,
        selection: WallpaperSelectionContext,
        window: NSWindow?
    ) {
        guard !manager.effectiveSelectedWallpaperIDs.isEmpty else { return }
        guard let scope = selection.deletionScope else { return }
        let sourceWallpapers = selection.sourceWallpapers(from: manager)
        let wallpapersToRemove = selectedWallpapers(from: sourceWallpapers, manager: manager)
        guard !wallpapersToRemove.isEmpty else { return }

        manager.removeWallpapers(wallpapersToRemove, in: scope) { summary in
            guard summary.hasFailures else { return }
            let failureAlert = makeAppAlert(
                title: "部分清理失败",
                message: summary.informativeText,
                style: .warning,
                buttons: ["知道了"]
            )
            presentAppAlert(failureAlert, in: resolvedHostWindow(window))
        }
        exitMultiSelectIfNeeded(manager: manager)
    }

    static func toggleFavoriteSelection(
        manager: WallpaperManager,
        selection: WallpaperSelectionContext
    ) {
        // 收藏切换只改选中集合对应的主库项，不让卡片视图自己持有收藏状态。
        let indices = manager.selectedLibraryWallpaperIndices(for: selection)
        guard !indices.isEmpty else { return }

        let shouldUnfavorite = indices.allSatisfy { manager.wallpapers[$0].isFavorite }
        var updatedWallpapers = manager.wallpapers
        for index in indices {
            updatedWallpapers[index].isFavorite = !shouldUnfavorite
        }
        manager.wallpapers = updatedWallpapers

        exitMultiSelectIfNeeded(manager: manager)
    }

    static func presentTagPicker(
        manager: WallpaperManager,
        window: NSWindow?,
        completion: @escaping () -> Void
    ) {
        // 添加标签是批量引用动作，作用范围来自当前 selection，而不是当前可见卡片。
        let pickerView = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        pickerView.addItems(withTitles: manager.tags)
        pickerView.selectItem(at: 0)
        let alert = makeAppAlert(
            title: "选择标签",
            message: manager.tags.isEmpty ? "标签库为空，请先在侧边栏新建标签。" : "请选择要添加的标签",
            buttons: ["确定", "取消"],
            accessoryView: pickerView
        )
        // 标签库被删空时不加任何条目，点确定会因 titleOfSelectedItem 为 nil 静默
        // 无操作；这里禁用下拉与确定按钮并给出空态提示，让空态可见可理解。
        if manager.tags.isEmpty {
            pickerView.isEnabled = false
            alert.buttons.first?.isEnabled = false
        }

        presentAppAlert(alert, in: resolvedHostWindow(window)) { response in
            guard response == .alertFirstButtonReturn,
                  let selectedTag = pickerView.titleOfSelectedItem,
                  !selectedTag.isEmpty else { return }

            mutateSelectedLibraryWallpapers(manager: manager, selection: manager.currentSelectionContext) { wallpaper in
                guard !wallpaper.tags.contains(selectedTag) else { return }
                wallpaper.tags.append(selectedTag)
            }

            exitMultiSelectIfNeeded(manager: manager)
            completion()
        }
    }

    static func presentInfo(manager: WallpaperManager, window: NSWindow?) {
        // 信息面板只展示单选项；多选态没有进入这个入口的意义。
        guard let selectedId = manager.selectedWallpaperId,
              let wallpaper = manager.wallpapers.first(where: { $0.id == selectedId }) else { return }
        // AVAsset 读取放到后台，完成后再弹窗，避免主线程卡顿。
        wallpaperDetailInfoText(for: wallpaper) { infoText in
            let alert = makeAppAlert(
                title: "壁纸信息",
                message: infoText
            )
            presentAppAlert(alert, in: resolvedHostWindow(window))
        }
    }

    static func presentCreateTag(
        manager: WallpaperManager,
        window: NSWindow?
    ) {
        // 新建标签只负责收集用户输入，不在这里直接改侧边栏节点。
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let alert = makeAppAlert(
            title: "新建视频标签",
            message: "请输入视频标签名称",
            buttons: ["确定", "取消"],
            accessoryView: inputField
        )

        presentAppAlert(alert, in: resolvedHostWindow(window)) { response in
            guard response == .alertFirstButtonReturn else { return }
            _ = manager.createTagIfNeeded(inputField.stringValue)
        }
    }

    static func presentRenameTag(
        manager: WallpaperManager,
        oldTag: String,
        selectedItem: SelectedItemAccessor,
        window: NSWindow?
    ) {
        // 重命名标签要同时修正外部 selection，避免侧边栏选中旧 tag 后和数据源脱节。
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.stringValue = oldTag
        let alert = makeAppAlert(
            title: "重命名标签",
            message: "请输入新的标签名称",
            buttons: ["确定", "取消"],
            accessoryView: inputField
        )

        presentAppAlert(alert, in: resolvedHostWindow(window)) { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let newName = manager.renameTag(oldTag, to: inputField.stringValue) else { return }
            var currentSelection = selectedItem.get()
            if currentSelection.applyTagRename(from: oldTag, to: newName) {
                selectedItem.set(currentSelection)
                manager.selectTag(newName)
            }
        }
    }

    static func presentDeleteTag(
        manager: WallpaperManager,
        tag: String,
        selectedItem: SelectedItemAccessor,
        window: NSWindow?
    ) {
        // 删除标签时要同时回写 selection，避免 UI 还停留在已删除的 tag 上。
        let alert = makeAppAlert(
            title: "删除标签",
            message: "确定要删除标签 \(tag) 吗？",
            style: .warning,
            buttons: ["删除", "取消"]
        )

        presentAppAlert(alert, in: resolvedHostWindow(window)) { response in
            guard response == .alertFirstButtonReturn else { return }
            guard manager.removeTagFromLibrary(tag) else { return }
            var currentSelection = selectedItem.get()
            if currentSelection.applyTagRemoval(tag) {
                selectedItem.set(currentSelection)
                manager.selectCategory(.tags)
            }
        }
    }

    private static func selectedWallpapers(
        from sourceWallpapers: [VideoWallpaper],
        manager: WallpaperManager
    ) -> [VideoWallpaper] {
        // 先从 selection 的有效 ID 集合里筛选，再回到当前 source 列表取对象。
        let selectedIDs = manager.effectiveSelectedWallpaperIDs
        guard !selectedIDs.isEmpty else { return [] }
        return sourceWallpapers.filter { selectedIDs.contains($0.id) }
    }

    private static func mutateSelectedLibraryWallpapers(
        manager: WallpaperManager,
        selection: WallpaperSelectionContext,
        _ mutate: (inout VideoWallpaper) -> Void
    ) {
        // 所有批量引用修改都走这一层，确保只改主库快照，不碰源文件。
        let indices = manager.selectedLibraryWallpaperIndices(for: selection)
        guard !indices.isEmpty else { return }
        for index in indices {
            mutate(&manager.wallpapers[index])
        }
    }

    private static func resolvedHostWindow(_ window: NSWindow?) -> NSWindow? {
        // 调用方可以不传 window，但最好让弹窗归属到当前主窗口。
        window ?? appModalHostWindow()
    }

    private static func exitMultiSelectIfNeeded(manager: WallpaperManager) {
        // 只要执行了会改变集合内容的动作，就退出多选，避免后续选区和按钮状态残留。
        guard manager.isMultiSelectMode else { return }
        manager.exitMultiSelectMode()
    }
}
