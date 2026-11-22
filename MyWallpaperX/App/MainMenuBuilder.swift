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
        case .selectAll: return #selector(NSText.selectAll(_:))
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
            title: String(localized: "About \(appName)"),
            action: #selector(AppDelegate.showAboutMenuAction(_:)),
            keyEquivalent: "",
            systemImageName: "info.circle"
        )
        appMenu.addItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(AppUpdateController.checkForUpdates(_:)),
            keyEquivalent: "",
            target: AppUpdateController.shared,
            systemImageName: "arrow.triangle.2.circlepath"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            title: String(localized: "Settings"),
            action: #selector(AppDelegate.showSettingsMenuAction(_:)),
            keyEquivalent: ",",
            systemImageName: "gearshape"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            title: String(localized: "Hide \(appName)"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
            target: NSApp
        )
        appMenu.addItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifierMask: [.command, .option],
            target: NSApp
        )
        appMenu.addItem(
            title: String(localized: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "",
            target: NSApp
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            title: String(localized: "Quit \(appName)"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApp
        )

        mainMenu.addItem(withTitle: appName, submenu: appMenu)
    }

    private static func addFileMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: String(localized: "File"))
        menu.addItem(
            title: String(localized: "New Playlist…"),
            action: #selector(AppDelegate.createPlaylistMenuAction(_:)),
            keyEquivalent: "n"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Import"),
            action: #selector(AppDelegate.importMenuAction(_:)),
            keyEquivalent: "o"
        )
        mainMenu.addItem(withTitle: String(localized: "File"), submenu: menu)
    }

    private static func addEditMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(title: String(localized: "Undo"), action: #selector(AppDelegate.undoMenuAction(_:)), keyEquivalent: "z")
        menu.addItem(title: String(localized: "Redo"), action: #selector(AppDelegate.redoMenuAction(_:)), keyEquivalent: "z", modifierMask: [.command, .shift])
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x",
            target: nil
        )
        menu.addItem(
            title: String(localized: "Copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c",
            target: nil
        )
        menu.addItem(
            title: String(localized: "Paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v",
            target: nil
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Select All"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a",
            target: nil
        )
        menu.addItem(
            title: String(localized: "Toggle Multiple Selection"),
            action: #selector(AppDelegate.toggleMultiSelectMenuAction(_:)),
            keyEquivalent: "e"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Delete Selected"),
            action: #selector(AppDelegate.deleteSelectedMenuAction(_:)),
            keyEquivalent: "\u{8}"
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Search"),
            action: #selector(AppDelegate.focusSearchMenuAction(_:)),
            keyEquivalent: "f"
        )
        mainMenu.addItem(withTitle: String(localized: "Edit"), submenu: menu)
    }

    private static func addViewMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: String(localized: "View"))
        menu.addItem(
            title: String(localized: "Larger Thumbnails"),
            action: #selector(AppDelegate.zoomInMenuAction(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(
            title: String(localized: "Smaller Thumbnails"),
            action: #selector(AppDelegate.zoomOutMenuAction(_:)),
            keyEquivalent: "-"
        )
        menu.addItem(.separator())
        let navigation = NSMenu(title: String(localized: "Go"))
        for (command, title) in [(MainMenuCommand.videos, String(localized: "My Videos")), (.images, String(localized: "My Images")), (.downloads, String(localized: "My Downloads")),
                                  (.recent, String(localized: "Recently Used")), (.workshop, String(localized: "Workshop")),
                                  (.wallhaven, "Wallhaven"), (.pixiv, "Pixiv"), (.pixabay, "Pixabay"), (.playlists, String(localized: "All Playlists")), (.favorites, String(localized: "Favorite"))] {
            navigation.addItem(title: title, action: command.action, keyEquivalent: "", command: command)
        }
        menu.addItem(withTitle: String(localized: "Go"), submenu: navigation)
        mainMenu.addItem(withTitle: String(localized: "View"), submenu: menu)
    }

    private static func addWallpaperMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: String(localized: "Wallpaper"))
        menu.addItem(
            title: String(localized: "Set as Wallpaper"),
            action: #selector(AppDelegate.setAsWallpaperMenuAction(_:)),
            keyEquivalent: "\r",
            modifierMask: []
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Next Wallpaper"),
            action: #selector(AppDelegate.nextWallpaperMenuAction(_:)),
            keyEquivalent: NSRightArrowFunctionKey.unicodeScalarString
        )
        menu.addItem(
            title: String(localized: "Previous Wallpaper"),
            action: #selector(AppDelegate.previousWallpaperMenuAction(_:)),
            keyEquivalent: NSLeftArrowFunctionKey.unicodeScalarString
        )
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Toggle Favorite"),
            action: #selector(AppDelegate.toggleFavoriteMenuAction(_:)),
            keyEquivalent: "d"
        )
        menu.addItem(
            title: String(localized: "Add to Playlist…"),
            action: #selector(AppDelegate.addToPlaylistMenuAction(_:)),
            keyEquivalent: "t"
        )
        menu.addItem(
            title: String(localized: "Get Info"),
            action: #selector(AppDelegate.showInfoMenuAction(_:)),
            keyEquivalent: "i"
        )
        menu.addItem(
            title: String(localized: "Preview"),
            action: #selector(AppDelegate.previewMenuAction(_:)),
            keyEquivalent: " ",
            modifierMask: []
        )
        menu.addItem(
            title: String(localized: "Reveal in Finder"),
            action: #selector(AppDelegate.revealInFinderMenuAction(_:)),
            keyEquivalent: "r"
        )
        mainMenu.addItem(withTitle: String(localized: "Wallpaper"), submenu: menu)
    }

    private static func addWindowMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(
            title: String(localized: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m",
            target: nil
        )
        menu.addItem(
            title: String(localized: "Close Window"),
            action: #selector(AppDelegate.closeWindowMenuAction(_:)),
            keyEquivalent: "w"
        )
        mainMenu.addItem(withTitle: String(localized: "Window"), submenu: menu)
        NSApp.windowsMenu = menu
    }

    private static func addHelpMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: String(localized: "Help"))
        menu.addItem(
            title: String(localized: "MyWallpaperX Help"),
            action: #selector(NSApplication.showHelp(_:)),
            keyEquivalent: "?",
            target: NSApp
        )
        mainMenu.addItem(withTitle: String(localized: "Help"), submenu: menu)
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
