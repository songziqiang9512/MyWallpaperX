import Foundation

/// Retain an unrecognized numeric string rather than silently turning it into 0.
nonisolated enum PixivInteger: Decodable, Sendable {
    case number(Int), text(String), unknown
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Int.self) { self = .number(number) }
        else if let text = try? value.decode(String.self) { self = .text(text) }
        else { self = .unknown }
    }
    var value: Int? {
        switch self { case .number(let value): return value; case .text(let text): return Int(text); case .unknown: return nil }
    }
    var identifier: String? {
        switch self { case .number(let value): return String(value); case .text(let text): return text; case .unknown: return nil }
    }
}

nonisolated struct PixivEnvelope<Body: Decodable>: Decodable {
    let error: Bool
    let body: Body?
    enum CodingKeys: String, CodingKey { case error, body }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        error = try values.decode(Bool.self, forKey: .error)
        // Error responses may use [] or null instead of the successful body's type.
        body = error ? nil : try values.decode(Body.self, forKey: .body)
    }
}

nonisolated struct PixivEntries<Element: Decodable>: Decodable {
    let values: [Element]
    let rejectedCount: Int
    private struct Entry: Decodable {
        let value: Element?
        init(from decoder: Decoder) throws { value = try? Element(from: decoder) }
    }
    init(from decoder: Decoder) throws {
        let entries = try [Entry](from: decoder)
        values = entries.compactMap(\.value)
        rejectedCount = entries.count - values.count
    }
}

nonisolated struct PixivRankingResponse: Decodable {
    let contents: PixivEntries<PixivArtworkDTO>
    let next: PixivInteger?
    let date: String?
    let total: Int?
    enum CodingKeys: String, CodingKey { case contents, next, date; case total = "rank_total" }
}

nonisolated struct PixivSearchBody: Decodable {
    struct Block: Decodable {
        let data: PixivEntries<PixivArtworkDTO>
        let total: Int?
        let lastPage: Int?
    }
    let block: Block
    enum CodingKeys: String, CodingKey { case illustManga, manga }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try values.decodeIfPresent(Block.self, forKey: .illustManga) { block = value }
        else { block = try values.decode(Block.self, forKey: .manga) }
    }
}

nonisolated struct PixivArtworkDTO: Decodable {
    let id: String
    let title: String?
    let type: PixivInteger?
    let pageCount: PixivInteger?
    let xRestrict: PixivInteger?
    let restrict: PixivInteger?
    let sexualLevel: PixivInteger?
    let aiType: PixivInteger?
    let masked: Bool?
    let locationMask: Bool?
    let thumbnail: String?
    let urls: [String: String]?
    let author: String?
    let authorID: String?
    let tags: [String]
    let width: PixivInteger?
    let height: PixivInteger?
    let createdAt: String?

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
    private struct TagContainer: Decodable {
        struct Tag: Decodable { let tag: String }
        let tags: [Tag]
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        func number(_ names: String...) -> PixivInteger? {
            for name in names where values.contains(Key(name)) {
                return try? values.decodeIfPresent(PixivInteger.self, forKey: Key(name))
            }
            return nil
        }
        func string(_ names: String...) -> String? {
            for name in names where values.contains(Key(name)) {
                return try? values.decodeIfPresent(String.self, forKey: Key(name))
            }
            return nil
        }
        guard let decodedID = number("illustId", "id", "illust_id")?.identifier,
              PixivRequestURL.validID(decodedID) else { throw OnlineImageError.invalidResponse }
        id = decodedID
        title = string("illustTitle", "title")
        type = number("illustType", "illust_type")
        pageCount = number("pageCount", "illust_page_count")
        xRestrict = number("xRestrict")
        restrict = number("restrict")
        sexualLevel = number("sl")
        aiType = number("aiType")
        masked = (try? values.decodeIfPresent(Bool.self, forKey: Key("isMasked")))
            ?? (try? values.decodeIfPresent(Bool.self, forKey: Key("is_masked")))
        locationMask = try? values.decodeIfPresent(Bool.self, forKey: Key("locationMask"))
        thumbnail = string("url")
        urls = (try? values.decodeIfPresent(PixivImageURLs.self, forKey: Key("urls")))?.values
        author = string("userName", "user_name")
        authorID = number("userId", "user_id")?.identifier
        if let tags = try? values.decode([String].self, forKey: Key("tags")) { self.tags = tags }
        else { tags = (try? values.decode(TagContainer.self, forKey: Key("tags")))?.tags.map(\.tag) ?? [] }
        width = number("width"); height = number("height")
        createdAt = string("createDate")
    }

    func artwork() -> OnlineImageArtwork {
        let kind: OnlineImageKind
        switch type?.value { case 0, 1: kind = .image; case 2: kind = .animation; default: kind = .unknown }
        // xRestrict == 0 excludes age restriction, but does not establish a
        // potentially-sensitive work's rating. Do not guess sl thresholds.
        let rating: WallpaperContentRating = [1, 2].contains(xRestrict?.value ?? -1) ? .adult : .unknown
        let mask = masked == true || locationMask == true
        let isAI: Bool?
        switch aiType?.value { case 1: isAI = false; case 2: isAI = true; default: isAI = nil }
        return OnlineImageArtwork(source: .pixiv, artworkID: id, title: title ?? "Pixiv #\(id)",
            sourceURL: URL(string: "https://www.pixiv.net/artworks/\(id)")!,
            thumbnailURL: PixivRequestURL.imageURL(urls?["thumb"] ?? urls?["mini"] ?? thumbnail),
            previewURL: PixivRequestURL.imageURL(urls?["regular"] ?? thumbnail),
            originalURL: mask || kind != .image ? nil : PixivRequestURL.imageURL(urls?["original"]),
            author: author, authorID: authorID, tags: tags,
            width: width?.value.flatMap { $0 > 0 ? $0 : nil },
            height: height?.value.flatMap { $0 > 0 ? $0 : nil },
            pageCount: pageCount?.value.flatMap { $0 > 0 ? $0 : nil }, kind: kind,
            rating: rating, isAIGenerated: isAI, isMasked: mask ? true : masked,
            createdAt: createdAt.flatMap { ISO8601DateFormatter().date(from: $0) })
    }
}

nonisolated struct PixivPageDTO: Decodable {
    let urls: [String: String]
    let width: Int?
    let height: Int?
    enum CodingKeys: String, CodingKey { case urls, width, height }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        urls = try values.decode(PixivImageURLs.self, forKey: .urls).values
        width = (try? values.decodeIfPresent(PixivInteger.self, forKey: .width))?.value
        height = (try? values.decodeIfPresent(PixivInteger.self, forKey: .height))?.value
    }
}

nonisolated struct PixivImageURLs: Decodable {
    let values: [String: String]
    enum CodingKeys: String, CodingKey, CaseIterable { case mini, thumb, small, regular, original; case thumbMini = "thumb_mini" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var result: [String: String] = [:]
        for key in CodingKeys.allCases {
            if let value = try? container.decode(String.self, forKey: key) { result[key.rawValue] = value }
        }
        values = result
    }
}

nonisolated struct PixivAuthorProfile: Decodable {
    let illustrations: [String]
    let manga: [String]
    private struct IDKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    enum CodingKeys: String, CodingKey { case illusts, manga }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func keys(_ key: CodingKeys) throws -> [String] {
            guard values.contains(key), try !values.decodeNil(forKey: key) else { return [] }
            // Empty work categories are also represented as [] by the site.
            if let empty = try? values.nestedUnkeyedContainer(forKey: key), empty.isAtEnd { return [] }
            return try values.nestedContainer(keyedBy: IDKey.self, forKey: key).allKeys.map(\.stringValue)
                .filter(PixivRequestURL.validID)
        }
        illustrations = try keys(.illusts); manga = try keys(.manga)
    }
}

nonisolated struct PixivAuthorWorks: Decodable {
    let works: [String: PixivArtworkDTO]
    private struct Entry: Decodable {
        let value: PixivArtworkDTO?
        init(from decoder: Decoder) throws { value = try? PixivArtworkDTO(from: decoder) }
    }
    enum CodingKeys: String, CodingKey { case works }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        works = try values.decode([String: Entry].self, forKey: .works).compactMapValues(\.value)
    }
}

/// Only the official document's current-user payload qualifies as identity.
/// Author preloads, absent metadata and malformed responses remain unknown.
nonisolated enum PixivOfficialMetadata: Equatable, Sendable {
    case authenticated(userID: String, displayName: String?)
    case anonymous, unknown

    private struct Payload: Decodable {
        struct User: Decodable { let id: PixivInteger; let name: String? }
        let userData: User?
        enum CodingKeys: String, CodingKey { case userData }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // decodeIfPresent alone conflates missing with explicitly null.
            guard values.contains(.userData) else { throw OnlineImageError.invalidResponse }
            userData = try values.decodeIfPresent(User.self, forKey: .userData)
        }
    }

    static func parse(raw: String?, url: URL) -> Self {
        guard isOfficialDocument(url), let raw,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(raw.utf8)) else { return .unknown }
        guard let user = payload.userData else { return .anonymous }
        guard let id = user.id.identifier, PixivRequestURL.validID(id), id.utf8.contains(where: { $0 != 48 }) else { return .unknown }
        return .authenticated(userID: id, displayName: user.name)
    }

    static func isOfficialDocument(_ url: URL) -> Bool {
        url.scheme == "https" && ["www.pixiv.net", "pixiv.net"].contains(url.host?.lowercased() ?? "")
    }
}
