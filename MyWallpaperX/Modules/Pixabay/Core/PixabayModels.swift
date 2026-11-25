//
//  PixabayModels.swift
//  MyWallpaperX — Modules/Pixabay/Core
//

import Foundation

// MARK: - 分类

enum PixabayCategory: String, CaseIterable, Identifiable {
    case all            = ""
    case backgrounds    = "backgrounds"
    case fashion        = "fashion"
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
        case .all:            return String(localized: "All")
        case .backgrounds:    return String(localized: "Background")
        case .fashion:        return String(localized: "Fashion")
        case .nature:         return String(localized: "Nature")
        case .science:        return String(localized: "Science")
        case .education:      return String(localized: "Education")
        case .feelings:       return String(localized: "Feelings")
        case .health:         return String(localized: "Health")
        case .people:         return String(localized: "People")
        case .religion:       return String(localized: "Religion")
        case .places:         return String(localized: "Location")
        case .animals:        return String(localized: "Animals")
        case .industry:       return String(localized: "Industry")
        case .computer:       return String(localized: "Technology")
        case .food:           return String(localized: "Food")
        case .sports:         return String(localized: "Sports")
        case .transportation: return String(localized: "Transportation")
        case .travel:         return String(localized: "Travel")
        case .buildings:      return String(localized: "Architecture")
        case .business:       return String(localized: "Business")
        case .music:          return String(localized: "Music")
        }
    }
}

// MARK: - 排序

enum PixabayOrder: String, CaseIterable, Identifiable {
    case popular = "popular"
    case latest  = "latest"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .popular: return String(localized: "Popular")
        case .latest:  return String(localized: "Newest")
        }
    }
}

// MARK: - 搜索参数

enum PixabayVideoType: String, CaseIterable {
    case all, film, animation
    var displayName: String {
        switch self { case .all: String(localized: "All"); case .film: String(localized: "Film"); case .animation: String(localized: "Animation") }
    }
}

/// OL-11：消除魔法数字，统一 perPage 默认值
let kPixabayDefaultPerPage = 30

struct PixabaySearchParams: Equatable {
    var query:    String                 = ""
    var category: PixabayCategory  = .all
    var page:     Int                    = 1
    var perPage:  Int                    = kPixabayDefaultPerPage
    var order:    PixabayOrder     = .popular
    var videoType: PixabayVideoType = .all
    var minWidth = 0
    var minHeight = 0
    var editorsChoice = false
    var safeSearch = true

    var hasFilters: Bool {
        category != .all || videoType != .all || minWidth > 0 || minHeight > 0 || editorsChoice || !safeSearch
    }
    mutating func clearFilters() {
        category = .all; videoType = .all; minWidth = 0; minHeight = 0
        editorsChoice = false; safeSearch = true
    }
}

// MARK: - 数据模型

struct PixabayVideoItem: Decodable, Identifiable, Equatable {
    let id:           Int
    let pageURL:      String
    let tags:         String
    let duration:     Int
    let user:         String
    let videos:       PixabayVideoFiles

    func videoDownload(tier: PixabayDownloadTier? = nil) -> PixabayVideoDownload? {
        let selected = tier ?? PixabayDownloadTier.allCases.first { videos[$0]?.url.isEmpty == false }
        guard let selected, let file = videos[selected], !file.url.isEmpty,
              let url = URL(string: file.url) else { return nil }
        return .init(tier: selected, url: url, width: file.width, height: file.height,
                     expectedBytes: file.size > 0 ? Int64(file.size) : nil)
    }

    var videoDownloadOptions: [PixabayVideoDownload] {
        var seen: Set<URL> = []
        return PixabayDownloadTier.allCases.compactMap { videoDownload(tier: $0) }
            .filter { seen.insert($0.url).inserted }
    }

    var preferredVideoDownload: PixabayVideoDownload? {
        for tier in PixabayDownloadTier.allCases {
            if let option = videoDownload(tier: tier) { return option }
        }
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
}

struct PixabayVideoFiles: Decodable, Equatable {
    let large:  PixabayVideoFile?
    let medium: PixabayVideoFile?
    let small:  PixabayVideoFile?
    let tiny:   PixabayVideoFile?

    subscript(tier: PixabayDownloadTier) -> PixabayVideoFile? {
        switch tier {
        case .large: large
        case .medium: medium
        case .small: small
        case .tiny: tiny
        }
    }
}

struct PixabayVideoFile: Decodable, Equatable {
    let url:       String
    let width:     Int
    let height:    Int
    let size:      Int
    let thumbnail: String
}

enum PixabayDownloadTier: String, CaseIterable {
    case large, medium, small, tiny
}

struct PixabayVideoDownload {
    let tier: PixabayDownloadTier
    let url: URL
    let width: Int
    let height: Int
    let expectedBytes: Int64?

    var resolutionString: String? {
        guard width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    var fileSizeString: String? {
        guard let expectedBytes else { return nil }
        let mb = Double(expectedBytes) / (1024 * 1024)
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
