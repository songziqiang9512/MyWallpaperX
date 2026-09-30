//
//  MainWindowMenuCommands.swift
//  MyWallpaperX
//

import AppKit

// 主菜单命令的语义分发：按激活模块把命令路由到对应模块服务。
// 实现从 MainWindowCoordinator 拆出；AppDelegate 仍经 MainWindowCoordinator 门面调用。
enum MainWindowMenuCommands {
    // coordinator 状态简写：菜单实现体保持按短名引用。
    private static var activeModule: MainWindowController.ActiveModule { MainWindowCoordinator.activeModule }
    private static var isSteamDownloadsMode: Bool { MainWindowCoordinator.isSteamDownloadsMode }
    private static var mainWindowController: MainWindowController? { MainWindowCoordinator.mainWindowController }

    /// 当前模块是否为视频库（视频库专属菜单项的启用判断）
    static var isVideoLibraryActive: Bool { activeModule == .videoLibrary }

    /// 视频库专属命令（设为壁纸 / 上下切换 / 收藏）是否可用
    static var canUseVideoLibraryOnlyCommands: Bool { isVideoLibraryActive }

    /// 「进入/退出多选」菜单项是否可用
    static var canToggleMultiSelect: Bool {
        switch activeModule {
        case .videoLibrary, .staticImageLibrary:
            return true
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive
        case .steamWorkshop:
            return isSteamDownloadsMode
        }
    }

    /// 「全选」菜单项是否可用
    static var canSelectAll: Bool {
        switch activeModule {
        case .videoLibrary, .staticImageLibrary:
            return true
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.isMultiSelectMode
        case .steamWorkshop:
            return isSteamDownloadsMode && SteamWorkshopService.shared.canSelectAllDownloads
        }
    }

    static var revealInFinderMenuTitle: String {
        switch activeModule {
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive ? "查看文件" : "刷新"
        case .steamWorkshop:
            return isSteamDownloadsMode ? "查看文件" : "刷新"
        default:
            return "查看文件"
        }
    }

    /// 「设为壁纸」- 仅视频库
    static func menuSetAsWallpaper() {
        guard isVideoLibraryActive else { return }
        let manager = WallpaperManager.shared
        if let id = manager.selectedWallpaperId,
           let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
            manager.markCardInteraction()
            manager.requestSetAsWallpaper(wallpaper)
        }
    }

    /// 「切换上一张/下一张」——跨引擎统一轮换（视频库 + 工坊 web/scene），
    /// 与 F1-F12 热键、状态栏同一切换源。
    static func menuNavigate(_ direction: ManualNavigationDirection) {
        CrossRuntimeWallpaperNavigator.navigate(direction)
    }

    /// 「收藏 / 取消收藏」- 仅视频库
    static func menuToggleFavorite() {
        guard isVideoLibraryActive else { return }
        let manager = WallpaperManager.shared
        UIActionHelper.toggleFavoriteSelection(
            manager: manager,
            selection: manager.currentSelectionContext
        )
    }

    /// 「导入」- Cmd+O，根据当前模块决定导入视频还是图片
    static func menuImport() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            manager.importVideos(
                presentingIn: appModalHostWindow(),
                context: manager.currentImportContext
            )
        case .staticImageLibrary:
            SILService.shared.importFromPanel(presentingIn: appModalHostWindow())
        case .onlineLibrary:
            break  // 在线库无本地导入
        case .steamWorkshop:
            break
        }
    }

    /// 「新建标签」- Cmd+N，根据当前模块决定新建视频标签还是图片标签
    static func menuCreateTag() {
        switch activeModule {
        case .videoLibrary:
            UIActionHelper.presentCreateTag(
                manager: WallpaperManager.shared,
                window: appModalHostWindow()
            )
        case .staticImageLibrary:
            let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            let alert = makeAppAlert(
                title: "新建图片标签",
                message: "请输入图片标签名称",
                buttons: ["确定", "取消"],
                accessoryView: inputField
            )
            presentAppAlert(alert, in: appModalHostWindow()) { r in
                guard r == .alertFirstButtonReturn else { return }
                SILService.shared.createSILTag(inputField.stringValue)
            }
        case .onlineLibrary:
            break  // 在线库无标签系统
        case .steamWorkshop:
            break
        }
    }

    /// 「添加标签」- 视频库专属；图片库预留接口（后续实现侧边栏专属标签系统）
    static func menuAddTag() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            UIActionHelper.presentTagPicker(
                manager: manager,
                window: appModalHostWindow()
            ) {}
        case .staticImageLibrary:
            // 图片库标签系统已实现，触发工具栏标签按钮动作
            let svc = SILService.shared
            let ids = svc.silSelectedIDs
            guard !ids.isEmpty else { return }
            let tags = svc.silTags
            guard !tags.isEmpty else {
                let alert = makeAppAlert(title: "无可用标签", message: "请先在侧边栏右键新建图片标签。", buttons: ["好"])
                presentAppAlert(alert, in: appModalHostWindow())
                return
            }
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            picker.addItems(withTitles: tags)
            picker.selectItem(at: 0)
            let alert = makeAppAlert(
                title: "添加图片标签",
                message: "请选择要添加的标签",
                buttons: ["确定", "取消"],
                accessoryView: picker
            )
            presentAppAlert(alert, in: appModalHostWindow()) { r in
                guard r == .alertFirstButtonReturn,
                      let tag = picker.titleOfSelectedItem, !tag.isEmpty else { return }
                // addSILTag 内部已调用 clearSelectionState()，多选会自动退出
                SILService.shared.addSILTag(tag, toSelected: ids)
            }
        case .onlineLibrary:
            break
        case .steamWorkshop:
            break
        }
    }

    /// 「添加标签」菜单项是否可用
    static var canAddTag: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.hasSingleWallpaperSelection || WallpaperManager.shared.hasAnyWallpaperSelection
        case .staticImageLibrary:
            // 图片库标签系统已实现：有选中且有标签时可用
            return SILService.shared.hasAnySelection && !SILService.shared.silTags.isEmpty
        case .onlineLibrary:
            return false
        case .steamWorkshop:
            return false
        }
    }

    /// 「查看信息」- 视频库和图片库各自实现
    static func menuShowInfo() {
        switch activeModule {
        case .videoLibrary:
            WallpaperManager.shared.presentInspectorForSelectedWallpaper()
        case .staticImageLibrary:
            SILService.shared.presentInspectorForSelectedWallpaper()
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.showInfo()
            }
        case .steamWorkshop:
            if isSteamDownloadsMode {
                SteamWorkshopService.shared.presentSelectedDownloadInfo()
            }
        }
    }

    /// 「查看信息」菜单项是否可用
    static var canShowInfo: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.hasSingleWallpaperSelection
        case .staticImageLibrary:
            return SILService.shared.selectedID != nil
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.hasSingleSelection
        case .steamWorkshop:
            return isSteamDownloadsMode && SteamWorkshopService.shared.canShowSelectedDownloadInfo
        }
    }

    /// 「进入/退出多选」- 视频库和图片库各自实现
    static func menuToggleMultiSelect() {
        switch activeModule {
        case .videoLibrary:
            WallpaperManager.shared.toggleMultiSelectMode()
        case .staticImageLibrary:
            let svc = SILService.shared
            if svc.isMultiSelectMode { svc.exitMultiSelectMode() } else { svc.enterMultiSelectMode() }
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.toggleMultiSelect()
            }
        case .steamWorkshop:
            if isSteamDownloadsMode {
                SteamWorkshopService.shared.toggleDownloadsMultiSelectMode()
            }
        }
    }

    /// 「全选」- 多选模式下各模块实现
    static func menuSelectAll() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            guard manager.isMultiSelectMode else { return }
            let selection = manager.currentSelectionContext
            let targetIDs = Set(selection.sourceWallpapers(from: manager).map(\.id))
            manager.replaceMultiSelection(with: targetIDs)
        case .staticImageLibrary:
            let svc = SILService.shared
            // 未进入多选模式时自动先进入再全选
            if !svc.isMultiSelectMode { svc.enterMultiSelectMode() }
            svc.selectAll()
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.selectAll()
            }
        case .steamWorkshop:
            if isSteamDownloadsMode {
                SteamWorkshopService.shared.selectAllDownloads()
            }
        }
    }

    /// 「删除选中」- 视频库和图片库各自实现
    static func menuDeleteSelected() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            let selection = manager.currentSelectionContext
            UIActionHelper.performDeleteWithoutConfirmation(
                manager: manager,
                selection: selection,
                window: appModalHostWindow()
            )
        case .staticImageLibrary:
            let svc = SILService.shared
            let ids = svc.silSelectedIDs
            guard !ids.isEmpty else { return }
            if let tag = svc.currentContextTag {
                SILService.shared.removeFromSILTag(tag, ids: ids)
            } else {
                SILService.shared.remove(ids: ids)
            }
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.deleteSelected()
            }
        case .steamWorkshop:
            if isSteamDownloadsMode {
                SteamWorkshopService.shared.deleteSelectedDownload()
            }
        }
    }

    static var canDeleteSelected: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.hasAnyWallpaperSelection
        case .staticImageLibrary:
            return SILService.shared.hasAnySelection
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.hasAnySelection
        case .steamWorkshop:
            return isSteamDownloadsMode && SteamWorkshopService.shared.canDeleteSelectedDownload
        }
    }

    /// 「搜索」- 各模块聚焦搜索框
    static func menuFocusSearch() {
        mainWindowController?.toolbarController.focusSearch()
    }

    /// 「查看文件」- 视频库和图片库各自实现
    static func menuRevealInFinder() {
        switch activeModule {
        case .videoLibrary:
            let manager = WallpaperManager.shared
            if let id = manager.selectedWallpaperId,
               let wallpaper = manager.wallpapers.first(where: { $0.id == id }) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
            }
        case .staticImageLibrary:
            let svc = SILService.shared
            if let id = svc.selectedID,
               let wallpaper = svc.wallpapers.first(where: { $0.id == id }) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
            }
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                OnlineDownloadsBridge.shared.revealInFinder()
            } else {
                OnlineLibraryService.shared.refresh()
            }
        case .steamWorkshop:
            if isSteamDownloadsMode {
                SteamWorkshopService.shared.revealSelectedDownload()
            } else {
                SteamWorkshopService.shared.refresh()
            }
        }
    }

    /// 「查看文件」菜单项是否可用
    static var canRevealInFinder: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.selectedWallpaperId != nil
        case .staticImageLibrary:
            return SILService.shared.selectedID != nil
        case .onlineLibrary:
            if OnlineDownloadsBridge.shared.isActive {
                return OnlineDownloadsBridge.shared.hasAnySelection
            }
            return true
        case .steamWorkshop:
            return !isSteamDownloadsMode || SteamWorkshopService.shared.canRevealSelectedDownload
        }
    }

    /// 「预览」菜单项是否可用
    static var canPreview: Bool {
        switch activeModule {
        case .videoLibrary:
            return WallpaperManager.shared.selectedWallpaperId != nil
        case .staticImageLibrary:
            return SILService.shared.selectedID != nil
        case .onlineLibrary:
            return OnlineDownloadsBridge.shared.isActive && OnlineDownloadsBridge.shared.hasAnySelection
        case .steamWorkshop:
            return SteamWorkshopDownloadsBridge.shared.isActive && SteamWorkshopDownloadsBridge.shared.hasPreviewableSelection
        }
    }

    /// 菜单命令：预览选中项（QuickLook）
    static func menuPreview() {
        let module = activeModule
        if module == .videoLibrary {
            _ = QuickLookPreviewController.shared.openPreview(for: WallpaperManager.shared.selectedWallpaperForQuickLook)
        } else if module == .staticImageLibrary {
            _ = SILKeyboardHandler.shared.handleSpace()
        } else if module == .onlineLibrary && OnlineDownloadsBridge.shared.isActive {
            OnlineDownloadsBridge.shared.previewSelected()
        } else if module == .steamWorkshop && SteamWorkshopDownloadsBridge.shared.isActive {
            SteamWorkshopDownloadsBridge.shared.previewSelected()
        }
    }
}
