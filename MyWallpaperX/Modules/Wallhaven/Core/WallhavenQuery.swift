import Foundation

nonisolated struct WallhavenQuery: Hashable, Codable, Sendable {
    enum Sorting: String, CaseIterable, Codable, Sendable {
        case latest = "date_added", popular = "toplist", relevance, random, views, favorites

        var displayName: String {
            switch self {
            case .latest: return String(localized: "Newest")
            case .popular: return String(localized: "Popular")
            case .relevance: return String(localized: "Related")
            case .random: return String(localized: "Random")
            case .views: return String(localized: "Views")
            case .favorites: return String(localized: "Favorites Count")
            }
        }
    }

    enum Order: String, CaseIterable, Codable, Sendable {
        case desc, asc
        var displayName: String { self == .desc ? String(localized: "Descending") : String(localized: "Ascending") }
    }

    enum TopRange: String, CaseIterable, Codable, Sendable {
        case day = "1d", threeDays = "3d", week = "1w", month = "1M"
        case threeMonths = "3M", sixMonths = "6M", year = "1y"

        var displayName: String {
            switch self {
            case .day: return String(localized: "Today")
            case .threeDays: return String(localized: "Within Three Days")
            case .week: return String(localized: "This Week")
            case .month: return String(localized: "This Month")
            case .threeMonths: return String(localized: "Within Three Months")
            case .sixMonths: return String(localized: "Last 6 Months")
            case .year: return String(localized: "Within One Year")
            }
        }
    }

    var search = ""
    /// Wallhaven identifies uploaders by their actual username, not a numeric user ID.
    var authorUsername: String? = nil
    var sorting: Sorting = .latest
    var order: Order = .desc
    /// Positions are General / Anime / People and SFW / Sketchy / NSFW.
    var categories = "111"
    var purity = "100"
    var minimumResolution: String? = nil
    var ratios: [String] = []
    var topRange: TopRange = .month

    func queryItems(page: Int, seed: String? = nil) throws -> [URLQueryItem] {
        guard page > 0, Self.validMask(categories), Self.validMask(purity) else {
            throw OnlineImageError.message(String(localized: "Choose a valid Wallhaven category, purity, and page number."))
        }
        let minimum = minimumResolution?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (minimum.map { $0.isEmpty || Self.validDimensions($0) } ?? true),
              ratios.allSatisfy(Self.validDimensions) else {
            throw OnlineImageError.message(String(localized: "The Wallhaven resolution or ratio format is invalid."))
        }
        var items: [URLQueryItem] = [
            .init(name: "categories", value: categories), .init(name: "purity", value: purity),
            .init(name: "sorting", value: sorting.rawValue), .init(name: "order", value: order.rawValue),
            .init(name: "page", value: String(page))
        ]
        let author = authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = author.flatMap { $0.isEmpty ? nil : "@" + $0 }
            ?? search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(.init(name: "q", value: text)) }
        if sorting == .popular { items.append(.init(name: "topRange", value: topRange.rawValue)) }
        if sorting == .random, let seed, !seed.isEmpty { items.append(.init(name: "seed", value: seed)) }
        if let minimum, !minimum.isEmpty { items.append(.init(name: "atleast", value: minimum)) }
        if !ratios.isEmpty { items.append(.init(name: "ratios", value: ratios.joined(separator: ","))) }
        // The documented API fixes listings at 24. per_page/include_fields are not sent.
        return items
    }

    private static func validMask(_ value: String) -> Bool {
        value.utf8.count == 3 && value.utf8.allSatisfy { $0 == 48 || $0 == 49 } && value != "000"
    }

    private static func validDimensions(_ value: String) -> Bool {
        let parts = value.split(separator: "x", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && (Int($0) ?? 0) > 0
        }
    }

}
