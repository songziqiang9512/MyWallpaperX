import Foundation

/// Classify only official metadata tags, never titles or author project tags.
enum SteamWorkshopContentRatingSupport {
    static func hasAdultContent(tags: [String]) -> Bool {
        tags.contains { tag in
            switch tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "mature", "nudity": return true
            default: return false
            }
        }
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
