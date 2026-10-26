import Foundation

nonisolated enum PixivRankingMode: String, CaseIterable, Codable, Sendable {
    case daily, weekly, monthly
}

nonisolated enum PixivWorkType: String, CaseIterable, Codable, Sendable {
    case illustrations = "illust"
    case manga
}

/// Source controls remain separate from the library's local search/sort state.
nonisolated struct PixivQuery: Hashable, Codable, Sendable {
    var search: String = ""
    var ranking: PixivRankingMode = .daily
    var authorID: String? = nil
    var workType: PixivWorkType = .illustrations

    var searchWord: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated enum PixivRequestURL {
    static func artwork(_ id: String, suffix: String = "") throws -> URL {
        guard validID(id) else { throw OnlineImageError.invalidResponse }
        return try make(path: "/ajax/illust/\(id)\(suffix)")
    }

    static func make(path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.pixiv.net"
        components.path = path
        components.queryItems = query + [URLQueryItem(name: "lang", value: "zh")]
        guard let url = components.url else { throw OnlineImageError.invalidResponse }
        return url
    }

    static func search(_ word: String, type: PixivWorkType, page: Int) throws -> URL {
        // A word is one path segment. URLComponents.path alone does not escape '/'.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        guard let segment = word.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw OnlineImageError.invalidResponse
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.pixiv.net"
        components.percentEncodedPath = "/ajax/search/\(type == .manga ? "manga" : "artworks")/\(segment)"
        components.queryItems = [
            .init(name: "word", value: word), .init(name: "order", value: "date_d"),
            .init(name: "mode", value: "safe"), .init(name: "p", value: String(page)),
            .init(name: "s_mode", value: "s_tag"), .init(name: "lang", value: "zh")
        ]
        guard let url = components.url else { throw OnlineImageError.invalidResponse }
        return url
    }

    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func imageURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              let host = url.host?.lowercased(), host == "pximg.net" || host.hasSuffix(".pximg.net") else { return nil }
        return url
    }
}
