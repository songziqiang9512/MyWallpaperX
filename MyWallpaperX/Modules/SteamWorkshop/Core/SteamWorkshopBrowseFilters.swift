import Foundation

nonisolated struct SteamWorkshopBrowserContentMode: OptionSet, CaseIterable, Identifiable, Hashable {
    let rawValue: Int
    nonisolated init(rawValue: Int) { self.rawValue = rawValue }
    nonisolated static let video = Self(rawValue: 1)
    nonisolated static let web = Self(rawValue: 2)
    nonisolated static let scene = Self(rawValue: 4)
    nonisolated static let all: Self = [.video, .web, .scene]
    nonisolated static let allCases: [Self] = [.all, .video, .web, .scene]

    nonisolated var id: Int { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .all: return String(localized: "All Wallpapers")
        case .video: return String(localized: "Video Wallpaper")
        case .web: return String(localized: "Web Wallpaper")
        case .scene: return String(localized: "Scene Wallpaper")
        default: return Self.allCases.dropFirst().filter { contains($0) }.map(\.displayName).joined(separator: "、")
        }
    }

    nonisolated var shortDisplayName: String {
        switch self {
        case .all: return String(localized: "All")
        case .video: return String(localized: "Videos")
        case .web: return "WEB"
        case .scene: return String(localized: "Scene")
        default: return displayName
        }
    }

    nonisolated var requiredTagValue: String {
        switch self {
        case .all: return ""
        case .video: return "Video"
        case .web: return "Web"
        case .scene: return "Scene"
        default: return ""
        }
    }

    nonisolated var isAll: Bool { self == .all }

    /// Stable order keeps query keys independent of the order of checkbox clicks.
    nonisolated var queryTags: [String] {
        isAll ? [] : Self.allCases.dropFirst().filter { contains($0) }.map(\.requiredTagValue)
    }

    nonisolated func allows(tags: [String]) -> Bool {
        isAll || queryTags.contains { selected in
            tags.contains { $0.caseInsensitiveCompare(selected) == .orderedSame }
        }
    }

    nonisolated mutating func toggle(_ option: Self) {
        if option == .all { self = .all; return }
        if isAll { self = option; return }
        formSymmetricDifference(option)
        if isEmpty { self = .all }
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
        case .featured: return String(localized: "Most Popular")
        case .recent: return String(localized: "Latest Published")
        case .mostSubscribed: return String(localized: "Most Subscribed")
        case .updated: return String(localized: "Last Updated")
        case .mySubscriptions: return String(localized: "My Subscriptions")
        case .myFavorites: return String(localized: "My Favorites")
        }
    }

    nonisolated var toolbarDisplayName: String {
        switch self {
        case .mySubscriptions: return String(localized: "Subscribe")
        case .myFavorites: return String(localized: "Favorites")
        default: return displayName
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
        case .mySubscriptions: return String(localized: "My Subscriptions")
        case .myFavorites: return String(localized: "My Favorites")
        default: return String(localized: "Steam Workshop")
        }
    }
}

/// 个人来源排序（GetUserFiles 匿名+登录实测可用的字段）。「分级/收藏」
/// 无对应返回字段（评分/收藏计数不随列表返回），2026-09-16 从菜单移除，
/// 不再以「暂不支持」占位。
enum SteamWorkshopPersonalSort: String, CaseIterable, Identifiable {
    case name = "alpha"
    case fileSize = "filesize"
    case subscriptionDate = "subscriptiondate"
    case lastUpdated = "lastupdated"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .name: return String(localized: "File Name")
        case .fileSize: return String(localized: "File Size")
        case .subscriptionDate: return String(localized: "Subscription Date")
        case .lastUpdated: return String(localized: "Recently Updated")
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
        case .today: return String(localized: "Today")
        case .week: return String(localized: "One Week")
        case .month: return String(localized: "30 days")
        case .quarter: return String(localized: "Three Months")
        case .halfYear: return String(localized: "Six Months")
        case .year: return String(localized: "One Year")
        case .allTime: return String(localized: "All Time")
        }
    }

    /// Valve defines the trend window as a remote ranking interval, not a
    /// publication-date cutoff. `nil` leaves the all-time/default ranking.
    nonisolated var rankingDays: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .halfYear: return 180
        case .year: return 365
        case .allTime: return nil
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
        case .all: return String(localized: "All")
        case .abstract: return String(localized: "Abstract")
        case .anime: return String(localized: "Anime")
        case .animal: return String(localized: "Animals")
        case .city: return String(localized: "City")
        case .technology: return String(localized: "Technology")
        case .landscape: return String(localized: "Landscape")
        case .space: return String(localized: "Space")
        case .scifi: return String(localized: "Sci-Fi")
        case .cgi: return "CGI"
        case .cyberpunk: return String(localized: "Cyberpunk")
        case .fantasy: return String(localized: "Fantasy")
        case .game: return String(localized: "Games")
        case .movie: return String(localized: "Movies")
        case .music: return String(localized: "Music")
        case .nature: return String(localized: "Nature")
        case .relaxing: return String(localized: "Relaxing")
        case .cartoon: return String(localized: "Cartoon")
        case .cute: return String(localized: "Cute")
        case .vehicle: return String(localized: "Vehicles")
        case .girls: return String(localized: "People")
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
        case .everyone: return String(localized: "Everyone (G)")
        case .questionable: return String(localized: "PG-13 (Parental Guidance)")
        case .mature: return String(localized: "Restricted / Adult (R-18)")
        default: return String(localized: "All Ages")
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
        case .all: return String(localized: "All Resolutions")
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
        case .all: return String(localized: "All Categories")
        case .wallpaper: return String(localized: "Wallpaper")
        case .scene: return String(localized: "Scene")
        case .web: return String(localized: "Web")
        case .application: return String(localized: "Application")
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

/// 浏览分面筛选的唯一状态Owner（类型/分级/分辨率）。内容模式不在其中：
/// 它由 `browserContentMode`（Key.contentTypeTags）单独承载，筛选面板的
/// 「类型」区直接绑定该属性。
/// 合同：面内多选 = 任一命中（OR），跨面 = 全部命中（AND）。
/// 空集 = 该面不筛选；ageRating 以 OptionSet 表达（.all = 不筛选），
/// 集合成员永不包含各枚举的 `.all` case。
/// discovery route 由服务端 taggroups 执行（2026-09-16 实测语义与
/// 本合同一致）；author/personal route 由 `allows(tags:)` 后置执行。
struct SteamWorkshopBrowseFacetFilters: Equatable {
    var themes: Set<SteamWorkshopThemeFilter> = []
    var ageRating: SteamWorkshopAgeRatingFilter = .all
    var resolutions: Set<SteamWorkshopResolutionFilter> = []

    static let none = Self()

    var isEmpty: Bool {
        themes.isEmpty && ageRating == .all && resolutions.isEmpty
    }

    /// discovery 服务端分组；组顺序固定（类型→分级→分辨率），保证键稳定。
    var tagGroups: [[String]] {
        var groups: [[String]] = []
        if !themes.isEmpty {
            groups.append(canonical(themes).map(\.rawValue))
        }
        if ageRating != .all, !ageRating.isEmpty {
            groups.append(
                SteamWorkshopAgeRatingFilter.selectableRatings
                    .filter { ageRating.contains($0) }
                    .map(\.tagValue)
            )
        }
        if !resolutions.isEmpty {
            groups.append(canonical(resolutions).map(\.rawValue))
        }
        return groups
    }

    /// 客户端后置筛选（author/personal route）：每面命中任一选择即通过，
    /// 跨面 AND；ageRating 复用唯一判定 `.allows(tags:)`。
    func allows(tags: [String]) -> Bool {
        let matches: ([String]) -> Bool = { selections in
            tags.contains { tag in selections.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        }
        if !themes.isEmpty, !matches(canonical(themes).map(\.rawValue)) { return false }
        if !ageRating.allows(tags: tags) { return false }
        if !resolutions.isEmpty, !matches(canonical(resolutions).map(\.rawValue)) { return false }
        return true
    }

    /// 面选择按枚举声明序展开（集合本身无序，展示/分组需要稳定顺序）。
    private func canonical<T: CaseIterable & Equatable>(_ set: Set<T>) -> [T] {
        T.allCases.filter { set.contains($0) }
    }
}
