//
//  OnlineLibraryModels.swift
//  MyWallpaperX — Modules/OnlineLibrary/Core
//

import Foundation

// MARK: - 分类

enum OnlineLibraryCategory: String, CaseIterable, Identifiable {
    case all            = ""
    case nature         = "nature"
    case science        = "science"
    case education      = "education"
    case feelings       = "feelings"
    case health         = "health"
    case people         = "people"
    case religion       = "religion"
    case places         = "places"
    case animals        = "animals"
    case industry       = "industry"
    case computer       = "computer"
    case food           = "food"
    case sports         = "sports"
    case transportation = "transportation"
    case travel         = "travel"
    case buildings      = "buildings"
    case business       = "business"
    case music          = "music"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:            return "全部"
        case .nature:         return "自然"
        case .science:        return "科学"
        case .education:      return "教育"
        case .feelings:       return "情感"
        case .health:         return "健康"
        case .people:         return "人物"
        case .religion:       return "宗教"
        case .places:         return "地点"
        case .animals:        return "动物"
        case .industry:       return "工业"
        case .computer:       return "科技"
        case .food:           return "美食"
        case .sports:         return "运动"
        case .transportation: return "交通"
        case .travel:         return "旅行"
        case .buildings:      return "建筑"
        case .business:       return "商业"
        case .music:          return "音乐"
        }
    }
}

// MARK: - 排序

enum OnlineLibraryOrder: String, CaseIterable, Identifiable {
    case popular = "popular"
    case latest  = "latest"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .popular: return "热门"
        case .latest:  return "最新"
        }
    }
}

// MARK: - 搜索参数

/// OL-11：消除魔法数字，统一 perPage 默认值
let kOLDefaultPerPage = 30

struct OnlineLibrarySearchParams: Equatable {
    var query:    String                 = ""
    var category: OnlineLibraryCategory  = .all
    var page:     Int                    = 1
    var perPage:  Int                    = kOLDefaultPerPage
    var order:    OnlineLibraryOrder     = .popular
}

// MARK: - 数据模型

struct OnlineLibraryVideoItem: Identifiable, Equatable {
    let id:           Int
    let pageURL:      String
    let tags:         String
    let duration:     Int
    let user:         String
    let videos:       OnlineLibraryVideoFiles

    var bestVideoURL: URL? {
        if let u = videos.large?.url,  !u.isEmpty { return URL(string: u) }
        if let u = videos.medium?.url, !u.isEmpty { return URL(string: u) }
        if let u = videos.small?.url,  !u.isEmpty { return URL(string: u) }
        if let u = videos.tiny?.url,   !u.isEmpty { return URL(string: u) }
        return nil
    }

    var previewThumbnailURL: URL? {
        if let u = videos.medium?.thumbnail, !u.isEmpty { return URL(string: u) }
        if let u = videos.small?.thumbnail,  !u.isEmpty { return URL(string: u) }
        if let u = videos.tiny?.thumbnail,   !u.isEmpty { return URL(string: u) }
        return nil
    }

    /// 悬停预览用视频 URL，优先 small（画质/体积平衡），fallback tiny
    var videoPreviewURL: URL? {
        if let u = videos.small?.url, !u.isEmpty { return URL(string: u) }
        if let u = videos.tiny?.url,  !u.isEmpty { return URL(string: u) }
        return nil
    }

    var displayTitle: String {
        let parts = tags.split(separator: ",").prefix(3)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
        return parts.isEmpty ? "Pixabay #\(id)" : parts
    }

    var durationString: String {
        let m = duration / 60, s = duration % 60
        if m > 0, s > 0 { return "\(m)m\(s)s" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    var resolutionString: String? {
        let f = videos.large ?? videos.medium ?? videos.small ?? videos.tiny
        guard let f, f.width > 0, f.height > 0 else { return nil }
        return "\(f.width)×\(f.height)"
    }

    var fileSizeString: String? {
        let f = videos.large ?? videos.medium ?? videos.small ?? videos.tiny
        guard let bytes = f?.size, bytes > 0 else { return nil }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1fGB", mb / 1024)
        }
        if mb >= 100 {
            return String(format: "%.0fMB", mb)
        }
        if mb >= 10 {
            return String(format: "%.1fMB", mb)
        }
        return String(format: "%.2fMB", mb)
    }
}

struct OnlineLibraryVideoFiles: Equatable {
    let large:  OnlineLibraryVideoFile?
    let medium: OnlineLibraryVideoFile?
    let small:  OnlineLibraryVideoFile?
    let tiny:   OnlineLibraryVideoFile?
}

struct OnlineLibraryVideoFile: Equatable {
    let url:       String
    let width:     Int
    let height:    Int
    let size:      Int
    let thumbnail: String
}
