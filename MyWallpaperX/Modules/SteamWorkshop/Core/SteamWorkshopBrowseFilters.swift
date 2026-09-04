import Foundation

enum SteamWorkshopBrowserContentMode: String, CaseIterable, Identifiable {
    case all
    case video
    case web
    case scene

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .all: return "全部壁纸"
        case .video: return "视频壁纸"
        case .web: return "WEB壁纸"
        case .scene: return "场景壁纸"
        }
    }

    nonisolated var shortDisplayName: String {
        switch self {
        case .all: return "全部"
        case .video: return "视频"
        case .web: return "WEB"
        case .scene: return "场景"
        }
    }

    nonisolated var requiredTagValue: String {
        switch self {
        case .all: return ""
        case .video: return "Video"
        case .web: return "Web"
        case .scene: return "Scene"
        }
    }

    nonisolated var isAll: Bool { self == .all }

    nonisolated var searchPlaceholder: String {
        switch self {
        case .all: return "搜索 Steam 壁纸或输入工坊 ID"
        case .video: return "搜索 Steam 视频或输入工坊 ID"
        case .web: return "搜索 Steam WEB 壁纸或输入工坊 ID"
        case .scene: return "搜索 Steam 场景壁纸或输入工坊 ID"
        }
    }
}

enum SteamWorkshopSource: String, CaseIterable, Identifiable {
    case featured
    case recent
    case mostSubscribed
    case updated
    case mySubscriptions
    case myFavorites

    nonisolated static let publicSources: [Self] = [.featured, .recent, .mostSubscribed, .updated]
    nonisolated static let personalSources: [Self] = [.mySubscriptions, .myFavorites]

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .featured: return "最热门"
        case .recent: return "最新发布"
        case .mostSubscribed: return "最多订阅"
        case .updated: return "最后更新"
        case .mySubscriptions: return "Steam 已订阅"
        case .myFavorites: return "我的收藏"
        }
    }

    nonisolated var browseFilter: String {
        switch self {
        case .featured: return "trend"
        case .recent: return "mostrecent"
        case .mostSubscribed: return "totaluniquesubscribers"
        case .updated: return "lastupdated"
        case .mySubscriptions: return "mysubscriptions"
        case .myFavorites: return "myfavorites"
        }
    }

    nonisolated var supportsTimeRange: Bool {
        self == .featured
    }

    nonisolated var isPersonal: Bool {
        self == .mySubscriptions || self == .myFavorites
    }

    nonisolated var pageTitle: String {
        switch self {
        case .mySubscriptions: return "我的订阅"
        case .myFavorites: return "我的收藏"
        default: return "Steam 创意工坊"
        }
    }
}

enum SteamWorkshopPersonalSort: String, CaseIterable, Identifiable {
    case name = "alpha"
    case rating
    case favorites
    case fileSize = "filesize"
    case subscriptionDate = "subscriptiondate"
    case lastUpdated = "lastupdated"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .name: return "名称"
        case .rating: return "分级"
        case .favorites: return "收藏"
        case .fileSize: return "文件大小"
        case .subscriptionDate: return "订阅日期"
        case .lastUpdated: return "最近更新"
        }
    }
}

enum SteamWorkshopTrendingWindow: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case quarter
    case halfYear
    case year
    case allTime

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .today: return "今天"
        case .week: return "一周"
        case .month: return "30 天"
        case .quarter: return "三个月"
        case .halfYear: return "半年"
        case .year: return "一年"
        case .allTime: return "有史以来"
        }
    }

    nonisolated var daysValue: String {
        switch self {
        case .today: return "1"
        case .week: return "7"
        case .month: return "30"
        case .quarter: return "90"
        case .halfYear: return "180"
        case .year: return "365"
        case .allTime: return "-1"
        }
    }
}

enum SteamWorkshopThemeFilter: String, CaseIterable, Identifiable {
    case all
    case abstract = "Abstract"
    case anime = "Anime"
    case animal = "Animal"
    case city = "City"
    case technology = "Technology"
    case landscape = "Landscape"
    case space = "Space"
    case scifi = "Sci-Fi"
    case cgi = "CGI"
    case cyberpunk = "Cyberpunk"
    case fantasy = "Fantasy"
    case game = "Game"
    case movie = "Movie"
    case music = "Music"
    case nature = "Nature"
    case relaxing = "Relaxing"
    case cartoon = "Cartoon"
    case cute = "Cute"
    case vehicle = "Vehicle"
    case girls = "Girls"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .all: return "全部"
        case .abstract: return "抽象"
        case .anime: return "动漫"
        case .animal: return "动物"
        case .city: return "城市"
        case .technology: return "科技"
        case .landscape: return "风景"
        case .space: return "太空"
        case .scifi: return "科幻"
        case .cgi: return "CGI"
        case .cyberpunk: return "赛博"
        case .fantasy: return "奇幻"
        case .game: return "游戏"
        case .movie: return "影视"
        case .music: return "音乐"
        case .nature: return "自然"
        case .relaxing: return "治愈"
        case .cartoon: return "卡通"
        case .cute: return "可爱"
        case .vehicle: return "汽车"
        case .girls: return "人物"
        }
    }

    nonisolated var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

struct SteamWorkshopAgeRatingFilter: OptionSet, Hashable {
    let rawValue: UInt8

    static let everyone = Self(rawValue: 1 << 0)
    static let questionable = Self(rawValue: 1 << 1)
    static let mature = Self(rawValue: 1 << 2)
    static let all: Self = [.everyone, .questionable, .mature]
    nonisolated static let selectableRatings: [Self] = [.everyone, .questionable, .mature]

    nonisolated var displayName: String {
        switch self {
        case .everyone: return "大众级 (G)"
        case .questionable: return "家长指导级 (PG-13)"
        case .mature: return "限制级 / 成人级 (R-18)"
        default: return "全部年龄"
        }
    }

    nonisolated var tagValue: String {
        switch self {
        case .everyone: return "Everyone"
        case .questionable: return "Questionable"
        case .mature: return "Mature"
        default: return ""
        }
    }

    nonisolated static let ratingTagValues = selectableRatings.map(\.tagValue)
}

enum SteamWorkshopResolutionFilter: String, CaseIterable, Identifiable {
    case all
    case uhd4k = "3840 x 2160"
    case qhd = "2560 x 1440"
    case fhd = "1920 x 1080"
    case portrait4k = "2160 x 3840"
    case portrait2k = "1440 x 2560"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .all: return "全部分辨率"
        default: return rawValue
        }
    }

    nonisolated var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case wallpaper = "Wallpaper"
    case scene = "Scene"
    case web = "Web"
    case application = "Application"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .all: return "全部分类"
        case .wallpaper: return "壁纸"
        case .scene: return "场景"
        case .web: return "网页"
        case .application: return "应用"
        }
    }

    nonisolated var tagValue: String? {
        self == .all ? nil : rawValue
    }
}

enum SteamWorkshopBrowserLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum SteamWorkshopAuthenticationPhase: Equatable {
    case credentials
    case awaitingGuardCode
    case authenticated
}

enum SteamWorkshopAuthSessionState: Equatable {
    case unknown
    case valid
    case expired
    case authenticating
}
