//
//  WallpaperSelectionContext.swift
//  MyWallpaperX
//

enum WallpaperSelectionContext: Equatable {
    case category(Category)
    case tag(String)

    var displayTitle: String {
        switch self {
        case .category(.myWallpapers):
            return "我的壁纸"
        case .category(.favorites):
            return "特别喜爱"
        case .category(.recentlyUsed):
            return "最近使用"
        case .category(.tags):
            return "标签"
        case .category(.settings):
            return "设置"
        case .tag(let tag):
            return tag
        }
    }

    var isSettings: Bool {
        if case .category(.settings) = self {
            return true
        }
        return false
    }

    var scrollPersistenceKey: String {
        switch self {
        case .category(let category):
            switch category {
            case .myWallpapers:
                return "category.myWallpapers"
            case .favorites:
                return "category.favorites"
            case .recentlyUsed:
                return "category.recentlyUsed"
            case .tags:
                return "category.tags"
            case .settings:
                return "category.settings"
            }
        case .tag(let tag):
            return "tag.\(tag)"
        }
    }

    var importContext: ImportContext {
        switch self {
        case .category(.favorites):
            return .favorites
        case .tag(let tag):
            return .tag(tag)
        default:
            return .library
        }
    }

    var deletionScope: WallpaperRemovalScope? {
        switch self {
        case .category(.myWallpapers):
            return .library
        case .category(.recentlyUsed):
            return .recentlyUsed
        case .category(.favorites):
            return .favorites
        case .tag(let tag):
            return .tag(tag)
        default:
            return nil
        }
    }

    func sourceWallpapers(from manager: WallpaperManager) -> [VideoWallpaper] {
        switch self {
        case .category(.myWallpapers):
            return manager.wallpapers
        case .category(.favorites):
            return manager.favoriteWallpapers
        case .category(.recentlyUsed):
            return manager.recentlyUsedWallpapers
        case .category(.tags):
            return manager.wallpapers
        case .category(.settings):
            return []
        case .tag(let tag):
            return manager.wallpapers.filter { $0.tags.contains(tag) }
        }
    }

    func hasWallpapers(in manager: WallpaperManager) -> Bool {
        switch self {
        case .category(.myWallpapers), .category(.tags):
            return !manager.wallpapers.isEmpty
        case .category(.favorites):
            return manager.wallpapers.contains { $0.isFavorite }
        case .category(.recentlyUsed):
            return !manager.recentlyUsedWallpapers.isEmpty
        case .category(.settings):
            return false
        case .tag(let tag):
            return manager.wallpapers.contains { $0.tags.contains(tag) }
        }
    }
}

extension WallpaperManager {
    var currentSelectionContext: WallpaperSelectionContext {
        if let tag = selectedTag {
            return .tag(tag)
        }
        // 设置页现在统一使用独立窗口语义；主窗口选择态若残留旧的 `.settings` 持久化值，回退到视频库默认入口。
        let sanitizedCategory: Category = (selectedCategory == .settings) ? .myWallpapers : selectedCategory
        return .category(sanitizedCategory)
    }
}

extension SelectedItem {
    var selectionContext: WallpaperSelectionContext {
        switch self {
        case .category(let category):
            return .category(category)
        case .tag(let tag):
            return .tag(tag)
        case .onlineLibrary:
            return .category(.myWallpapers)
        case .onlineDownloads:
            return .category(.myWallpapers)
        case .steamWorkshop:
            return .category(.myWallpapers)
        case .steamSubscribed:
            return .category(.myWallpapers)
        case .steamDownloads:
            return .category(.myWallpapers)
        case .staticImageLibrary:
            return .category(.myWallpapers)
        case .silTag:
            // 图片库专属标签不参与 WallpaperSelectionContext
            return .category(.myWallpapers)
        }
    }

    init(selectionContext: WallpaperSelectionContext) {
        switch selectionContext {
        case .category(let category):
            self = .category(category)
        case .tag(let tag):
            self = .tag(tag)
        }
    }

    func apply(to manager: WallpaperManager) {
        switch self {
        case .category(let category):
            manager.selectCategory(category)
        case .tag(let tag):
            manager.selectTag(tag)
        case .onlineLibrary:
            break
        case .onlineDownloads:
            break
        case .steamWorkshop:
            break
        case .steamSubscribed:
            break
        case .steamDownloads:
            break
        case .staticImageLibrary:
            break
        case .silTag:
            break  // 图片库标签不需要同步到 WallpaperManager
        }
    }

    mutating func applyTagRename(from oldTag: String, to newTag: String) -> Bool {
        guard case .tag(let selectedTag) = self, selectedTag == oldTag else {
            return false
        }
        self = .tag(newTag)
        return true
    }

    mutating func applyTagRemoval(_ tag: String) -> Bool {
        guard case .tag(let selectedTag) = self, selectedTag == tag else {
            return false
        }
        self = .category(.tags)
        return true
    }

    /// 当前选中项是否属于视频库上下文（library/tags 分区）
    var isInVideoLibraryContext: Bool {
        switch self {
        case .category, .tag:
            return true
        case .staticImageLibrary, .silTag, .onlineLibrary, .onlineDownloads, .steamWorkshop, .steamSubscribed, .steamDownloads:
            return false
        }
    }

    /// 当前选中项是否属于图片库上下文（images 分区）
    var isInStaticImageLibraryContext: Bool {
        switch self {
        case .staticImageLibrary, .silTag:
            return true
        case .category, .tag, .onlineLibrary, .onlineDownloads, .steamWorkshop, .steamSubscribed, .steamDownloads:
            return false
        }
    }

    var isInSteamWorkshopContext: Bool {
        switch self {
        case .steamWorkshop, .steamSubscribed, .steamDownloads:
            return true
        case .category, .tag, .staticImageLibrary, .silTag, .onlineLibrary, .onlineDownloads:
            return false
        }
    }

    mutating func applySILTagRename(from oldTag: String, to newTag: String) -> Bool {
        guard case .silTag(let selectedTag) = self, selectedTag == oldTag else { return false }
        self = .silTag(newTag)
        return true
    }

    mutating func applySILTagRemoval(_ tag: String) -> Bool {
        guard case .silTag(let selectedTag) = self, selectedTag == tag else { return false }
        self = .staticImageLibrary
        return true
    }
}
