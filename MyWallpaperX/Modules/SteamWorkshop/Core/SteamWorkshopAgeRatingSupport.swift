import Foundation

/// Classify only official metadata tags, never titles or author project tags.
nonisolated enum SteamWorkshopContentRatingSupport {
    static func hasAdultContent(tags: [String], isMarkedAdult: Bool = false) -> Bool {
        contentRating(tags: tags, isMarkedAdult: isMarkedAdult) == .adult
    }

    static func contentRating(tags: [String], isMarkedAdult: Bool = false) -> WallpaperContentRating {
        if isMarkedAdult { return .adult }
        var rating = WallpaperContentRating.unknown
        for tag in tags {
            switch tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "mature", "nudity": return .adult
            case "questionable": rating = .sensitive
            case "everyone": if rating == .unknown { rating = .safe }
            default: break
            }
        }
        return rating
    }
}

extension SteamWorkshopAgeRatingFilter {
    func allows(tags: [String]) -> Bool {
        guard self != .all else { return true }
        guard !isEmpty else { return false }
        guard let rating = Self.selectableRatings.first(where: { candidate in
            tags.contains { $0.caseInsensitiveCompare(candidate.tagValue) == .orderedSame }
        }) else {
            return false
        }
        return contains(rating)
    }

    var activeDisplayName: String? {
        guard self != .all else { return nil }
        guard !isEmpty else { return "不显示任何年龄分级" }
        return Self.selectableRatings
            .filter(contains)
            .map(\.displayName)
            .joined(separator: "、")
    }
}
