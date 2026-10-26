//
//  MainMenuBuilder.swift
//  MyWallpaperX
//

import AppKit

@MainActor enum MainMenuCommand: String, CaseIterable {
    case about, settings, closeWindow, createPlaylist, importFiles, undo, redo
    case selectAll, toggleSelection, deleteSelected, search, zoomIn, zoomOut
    case applyWallpaper, nextWallpaper, previousWallpaper, favorite, addToPlaylist, info, preview, revealOrRefresh
    case videos, images, downloads, recent, workshop, pixabay, wallhaven, pixiv, playlists, favorites

    var identifier: NSUserInterfaceItemIdentifier { .init("MyWallpaperX.Menu." + rawValue) }
    var page: WallpaperLibraryPage? {
        switch self {
        case .videos: return .videos
        case .images: return .images
        case .downloads: return .downloads
        case .recent: return .recent
        case .workshop: return .workshop
        case .pixabay: return .pixabay
        case .wallhaven: return .wallhaven
        case .pixiv: return .pixiv
        case .playlists: return .playlists
        case .favorites: return .favorites
        default: return nil
        }
    }
    var action: Selector {
        switch self {
        case .about: return #selector(AppDelegate.showAboutMenuAction(_:))
        case .settings: return #selector(AppDelegate.showSettingsMenuAction(_:))
        case .closeWindow: return #selector(AppDelegate.closeWindowMenuAction(_:))
        case .createPlaylist: return #selector(AppDelegate.createPlaylistMenuAction(_:))
        case .importFiles: return #selector(AppDelegate.importMenuAction(_:))
        case .undo: return #selector(AppDelegate.undoMenuAction(_:))
        case .redo: return #selector(AppDelegate.redoMenuAction(_:))
        case .selectAll: return #selector(AppDelegate.selectAllMenuAction(_:))
        case .toggleSelection: return #selector(AppDelegate.toggleMultiSelectMenuAction(_:))
        case .deleteSelected: return #selector(AppDelegate.deleteSelectedMenuAction(_:))
        case .search: return #selector(AppDelegate.focusSearchMenuAction(_:))
        case .zoomIn: return #selector(AppDelegate.zoomInMenuAction(_:))
        case .zoomOut: return #selector(AppDelegate.zoomOutMenuAction(_:))
        case .applyWallpaper: return #selector(AppDelegate.setAsWallpaperMenuAction(_:))
        case .nextWallpaper: return #selector(AppDelegate.nextWallpaperMenuAction(_:))
        case .previousWallpaper: return #selector(AppDelegate.previousWallpaperMenuAction(_:))
        case .favorite: return #selector(AppDelegate.toggleFavoriteMenuAction(_:))
        case .addToPlaylist: return #selector(AppDelegate.addToPlaylistMenuAction(_:))
        case .info: return #selector(AppDelegate.showInfoMenuAction(_:))
        case .preview: return #selector(AppDelegate.previewMenuAction(_:))
        case .revealOrRefresh: return #selector(AppDelegate.revealInFinderMenuAction(_:))
        default: return #selector(AppDelegate.navigateLibraryPageMenuAction(_:))
        }
    }
    static func resolve(_ item: NSMenuItem) -> Self? {
        if let identifier = item.identifier {
            if let command = allCases.first(where: { $0.identifier == identifier }) { return command }
            // AppKit supplies an action-name identifier when none was assigned.
            // Accept that native identity; an unrelated explicit ID stays unknown.
            guard let action = item.action, identifier.rawValue == NSStringFromSelector(action) else { return nil }
        }
        // Selector fallback supports standard overflow items without matching
        // any translated or mutable display title. Page entries require IDs.
        return allCases.first { $0.page == nil && $0.action == item.action }
    }
}

@MainActor
enum MainMenuBuilder {
    static func installMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        addAppMenu(to: mainMenu)
        addFileMenu(to: mainMenu)
        addEditMenu(to: mainMenu)
        addViewMenu(to: mainMenu)
        addWallpaperMenu(to: mainMenu)
        addWindowMenu(to: mainMenu)
        addHelpMenu(to: mainMenu)
    }

    private static func addAppMenu(to mainMenu: NSMenu) {
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        appMenu.addItem(
            title: "关于 \(appName)",
            action: #selector(AppDelegate.showAboutMenuAction(_:)),
            keyEquivalent: "",
            systemImageName: "info.circle"
        )
        appMenu.addItem(
            title: "检查更新…",
            action: #selector(AppUpdateController.checkForUpdates(_:)),
            keyEquivalent: "",
            target: AppUpdateController.shared,
            systemImageName: "arrow.triangle.2.circlepath"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            title: "偏好设置",
            action: #selector(AppDelegate.showSettingsMenuAction(_:)),
            keyEquivalent: ",",
            systemImageName: "gearshape"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            title: "隐藏 \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
            target: NSApp
        )
        appMenu.addItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifierMask: [.command, .option],
            target: NSApp
        )
        appMenu.addItem(
            title: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "",
            target: NSApp
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            title: "退出 \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApp
        )

        mainMenu.addItem(withTitle: appName, submenu: appMenu)
    }

    private static func addFileMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "文件")
        menu.addItem(
            title: "新建播放列表…",
            action: #selector(AppDelegate.createPlaylistMenuAction(_:)),
            keyEquivalent: "n"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "导入",
            action: #selector(AppDelegate.importMenuAction(_:)),
            keyEquivalent: "o"
        )
        mainMenu.addItem(withTitle: "文件", submenu: menu)
    }

    private static func addEditMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "编辑")
        menu.addItem(title: "撤销", action: #selector(AppDelegate.undoMenuAction(_:)), keyEquivalent: "z")
        menu.addItem(title: "重做", action: #selector(AppDelegate.redoMenuAction(_:)), keyEquivalent: "z", modifierMask: [.command, .shift])
        menu.addItem(.separator())
        menu.addItem(
            title: "剪切",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x",
            target: nil
        )
        menu.addItem(
            title: "拷贝",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c",
            target: nil
        )
        menu.addItem(
            title: "粘贴",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v",
            target: nil
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "全选",
            action: #selector(AppDelegate.selectAllMenuAction(_:)),
            keyEquivalent: "a"
        )
        menu.addItem(
            title: "进入 / 退出多选",
            action: #selector(AppDelegate.toggleMultiSelectMenuAction(_:)),
            keyEquivalent: "e"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "删除选中",
            action: #selector(AppDelegate.deleteSelectedMenuAction(_:)),
            keyEquivalent: "\u{8}"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "搜索",
            action: #selector(AppDelegate.focusSearchMenuAction(_:)),
            keyEquivalent: "f"
        )
        mainMenu.addItem(withTitle: "编辑", submenu: menu)
    }

    private static func addViewMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "显示")
        menu.addItem(
            title: "放大缩略图",
            action: #selector(AppDelegate.zoomInMenuAction(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(
            title: "缩小缩略图",
            action: #selector(AppDelegate.zoomOutMenuAction(_:)),
            keyEquivalent: "-"
        )
        menu.addItem(.separator())
        let navigation = NSMenu(title: "前往")
        for (command, title) in [(MainMenuCommand.videos, "我的视频"), (.images, "我的图片"), (.downloads, "我的下载"),
                                  (.recent, "最近使用"), (.workshop, "创意工坊"),
                                  (.wallhaven, "Wallhaven"), (.pixiv, "Pixiv"), (.pixabay, "Pixabay"), (.playlists, "所有播放列表"), (.favorites, "特别喜爱")] {
            navigation.addItem(title: title, action: command.action, keyEquivalent: "", command: command)
        }
        menu.addItem(withTitle: "前往", submenu: navigation)
        mainMenu.addItem(withTitle: "显示", submenu: menu)
    }

    private static func addWallpaperMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "壁纸")
        menu.addItem(
            title: "设为当前壁纸",
            action: #selector(AppDelegate.setAsWallpaperMenuAction(_:)),
            keyEquivalent: "\r",
            modifierMask: []
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "切换下一张",
            action: #selector(AppDelegate.nextWallpaperMenuAction(_:)),
            keyEquivalent: NSRightArrowFunctionKey.unicodeScalarString
        )
        menu.addItem(
            title: "切换上一张",
            action: #selector(AppDelegate.previousWallpaperMenuAction(_:)),
            keyEquivalent: NSLeftArrowFunctionKey.unicodeScalarString
        )
        menu.addItem(.separator())
        menu.addItem(
            title: "特别喜爱 / 取消特别喜爱",
            action: #selector(AppDelegate.toggleFavoriteMenuAction(_:)),
            keyEquivalent: "d"
        )
        menu.addItem(
            title: "添加到列表…",
            action: #selector(AppDelegate.addToPlaylistMenuAction(_:)),
            keyEquivalent: "t"
        )
        menu.addItem(
            title: "查看信息",
            action: #selector(AppDelegate.showInfoMenuAction(_:)),
            keyEquivalent: "i"
        )
        menu.addItem(
            title: "预览",
            action: #selector(AppDelegate.previewMenuAction(_:)),
            keyEquivalent: " ",
            modifierMask: []
        )
        menu.addItem(
            title: "查看文件",
            action: #selector(AppDelegate.revealInFinderMenuAction(_:)),
            keyEquivalent: "r"
        )
        mainMenu.addItem(withTitle: "壁纸", submenu: menu)
    }

    private static func addWindowMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "窗口")
        menu.addItem(
            title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m",
            target: nil
        )
        menu.addItem(
            title: "关闭窗口",
            action: #selector(AppDelegate.closeWindowMenuAction(_:)),
            keyEquivalent: "w"
        )
        mainMenu.addItem(withTitle: "窗口", submenu: menu)
        NSApp.windowsMenu = menu
    }

    private static func addHelpMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "帮助")
        menu.addItem(
            title: "MyWallpaperX 帮助",
            action: #selector(NSApplication.showHelp(_:)),
            keyEquivalent: "?",
            target: NSApp
        )
        mainMenu.addItem(withTitle: "帮助", submenu: menu)
        NSApp.helpMenu = menu
    }
}

private extension NSMenu {
    func addItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifierMask: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = NSApp.delegate as AnyObject?,
        systemImageName: String? = nil,
        command: MainMenuCommand? = nil
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = target
        item.identifier = (command ?? MainMenuCommand.allCases.first { $0.page == nil && $0.action == action })?.identifier
        if let systemImageName,
           let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            item.image = image
        }
        addItem(item)
    }
}

private extension NSMenu {
    func addItem(withTitle title: String, submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

private extension Int {
    var unicodeScalarString: String {
        String(UnicodeScalar(self) ?? " ")
    }
}
