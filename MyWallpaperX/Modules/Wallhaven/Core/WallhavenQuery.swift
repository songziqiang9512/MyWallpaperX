import Foundation

nonisolated struct WallhavenQuery: Hashable, Codable, Sendable {
    enum Sorting: String, CaseIterable, Codable, Sendable {
        case latest = "date_added", popular = "toplist", relevance, random

        var displayName: String {
            switch self {
            case .latest: return "最新"
            case .popular: return "热门"
            case .relevance: return "相关"
            case .random: return "随机"
            }
        }
    }

    enum TopRange: String, CaseIterable, Codable, Sendable {
        case day = "1d", threeDays = "3d", week = "1w", month = "1M"
        case threeMonths = "3M", sixMonths = "6M", year = "1y"
    }

    var search = ""
    var sorting: Sorting = .latest
    /// Positions are General / Anime / People and SFW / Sketchy / NSFW.
    var categories = "111"
    var purity = "100"
    var minimumResolution: String? = nil
    var resolutions: [String] = []
    var ratios: [String] = []
    var color: String? = nil
    var topRange: TopRange = .month

    func queryItems(page: Int) throws -> [URLQueryItem] {
        guard page > 0, Self.validMask(categories), Self.validMask(purity) else {
            throw OnlineImageError.message("请选择有效的 Wallhaven 分类、分级与页码。")
        }
        let minimum = minimumResolution?.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = resolutions.filter { !$0.isEmpty }
        guard minimum?.isEmpty != false || exact.isEmpty else {
            throw OnlineImageError.message("最低分辨率和精确分辨率请择一使用。")
        }
        guard (minimum.map { $0.isEmpty || Self.validDimensions($0) } ?? true),
              exact.allSatisfy(Self.validDimensions), ratios.allSatisfy(Self.validDimensions) else {
            throw OnlineImageError.message("Wallhaven 分辨率或比例格式无效。")
        }
        var items: [URLQueryItem] = [
            .init(name: "categories", value: categories), .init(name: "purity", value: purity),
            .init(name: "sorting", value: sorting.rawValue), .init(name: "order", value: "desc"),
            .init(name: "page", value: String(page))
        ]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(.init(name: "q", value: text)) }
        if sorting == .popular { items.append(.init(name: "topRange", value: topRange.rawValue)) }
        if let minimum, !minimum.isEmpty { items.append(.init(name: "atleast", value: minimum)) }
        if !exact.isEmpty { items.append(.init(name: "resolutions", value: exact.joined(separator: ","))) }
        if !ratios.isEmpty { items.append(.init(name: "ratios", value: ratios.joined(separator: ","))) }
        if let color, !color.isEmpty {
            let normalized = color.replacingOccurrences(of: "#", with: "").lowercased()
            guard Self.colors.contains(normalized) else {
                throw OnlineImageError.message("请选择 Wallhaven 支持的颜色。")
            }
            items.append(.init(name: "colors", value: normalized))
        }
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

    private static let colors: Set<String> = [
        "660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399", "333399",
        "0066cc", "0099cc", "66cccc", "77cc33", "669900", "336600", "666600", "999900",
        "cccc33", "ffff00", "ffcc33", "ff9900", "ff6600", "cc6633", "996633", "663300",
        "000000", "999999", "cccccc", "ffffff", "424153"
    ]
}
