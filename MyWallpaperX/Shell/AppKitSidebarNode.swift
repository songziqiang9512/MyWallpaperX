//
//  AppKitSidebarNode.swift
//  MyWallpaperX
//

import Foundation

enum SidebarSectionID: String {
    case library
    case tags
    case others
    case images
    case online
    case steam

    var title: String {
        switch self {
        case .library: return "库"
        case .tags: return "标签"
        case .others: return "其他"
        case .images: return "图像"
        case .online: return "在线"
        case .steam: return "Steam"
        }
    }
}

enum SidebarNodeKind {
    case section(SidebarSectionID)
    case category(Category)
    case tag(String)
    case silTag(String)      // 图片库专属标签
    case staticImageLibrary
    case onlineLibrary
    case onlineDownloads     // 在线库已下载项
    case steamWorkshop, steamSubscribed
    case steamDownloads
}

final class SidebarNode: NSObject {
    let kind: SidebarNodeKind
    let title: String
    let symbolName: String?
    var count: Int?
    var children: [SidebarNode]

    init(
        kind: SidebarNodeKind,
        title: String,
        symbolName: String? = nil,
        count: Int? = nil,
        children: [SidebarNode] = []
    ) {
        self.kind = kind
        self.title = title
        self.symbolName = symbolName
        self.count = count
        self.children = children
    }

    var selectedItem: SelectedItem? {
        switch kind {
        case .category(let category):
            return .category(category)
        case .tag(let tag):
            return .tag(tag)
        case .silTag(let tag):
            return .silTag(tag)
        case .staticImageLibrary:
            return .staticImageLibrary
        case .onlineLibrary:
            return .onlineLibrary
        case .onlineDownloads:
            return .onlineDownloads
        case .steamWorkshop: return .steamWorkshop
        case .steamSubscribed: return .steamSubscribed
        case .steamDownloads:
            return .steamDownloads
        case .section:
            return nil
        }
    }

    var isGroup: Bool {
        if case .section = kind {
            return true
        }
        return false
    }
}

struct SidebarSnapshotSignature: Equatable {
    let wallpaperCount: Int
    let favoriteCount: Int
    let recentCount: Int
    let tags: [String]
    let tagCounts: [String: Int]
    let silTags: [String]
    let silTagCounts: [String: Int]
    let silWallpapersCount: Int  // 图片库总数，变化时触发侧边栏重建
    let onlineDownloadsCount: Int // 在线库已下载数，变化时更新侧边栏计数
    let steamDownloadsCount: Int
}

struct SidebarLibraryStats {
    let tagCounts: [String: Int]
    let favoriteCount: Int
}
