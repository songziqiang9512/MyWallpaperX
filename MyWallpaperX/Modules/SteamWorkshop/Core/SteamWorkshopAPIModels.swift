import Foundation
import CoreGraphics

enum SteamWorkshopBrowseContext: Equatable {
    case discovery
    case authorWorkshop(authorName: String, workshopURL: URL)

    var isAuthorWorkshop: Bool {
        if case .authorWorkshop = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .discovery:
            return "Steam 创意工坊"
        case .authorWorkshop(let authorName, _):
            return "\(authorName) 的工坊"
        }
    }

    var cacheKeyComponent: String {
        switch self {
        case .discovery:
            return "discovery"
        case .authorWorkshop(_, let workshopURL):
            let normalized = workshopURL.absoluteString
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let slug = normalized.isEmpty ? "author-workshop" : normalized
            return "author-v2-\(String(slug.prefix(120)))"
        }
    }
}

nonisolated struct SteamWorkshopProjectGeneral: Decodable {
    let hasProperties: Bool

    enum CodingKeys: String, CodingKey {
        case properties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasProperties = container.contains(.properties)
    }
}

nonisolated struct SteamWorkshopProject: Decodable {
    let title: String?
    let description: String?
    let preview: String?
    let file: String?
    let tags: [String]?
    let workshopid: String?
    let type: String?
    let dependency: String?
    let general: SteamWorkshopProjectGeneral?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case preview
        case file
        case tags
        case workshopid
        case type
        case dependency
        case general
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = Self.decodeLossyString(from: container, forKey: .title)
        description = Self.decodeLossyString(from: container, forKey: .description)
        preview = Self.decodeLossyString(from: container, forKey: .preview)
        file = Self.decodeLossyString(from: container, forKey: .file)
        tags = Self.decodeLossyStringArray(from: container, forKey: .tags)
        workshopid = Self.decodeLossyString(from: container, forKey: .workshopid)
        type = Self.decodeLossyString(from: container, forKey: .type)
        dependency = Self.decodeLossyString(from: container, forKey: .dependency)
        general = try? container.decodeIfPresent(SteamWorkshopProjectGeneral.self, forKey: .general)
    }

    private static func decodeLossyString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            if floor(value) == value {
                return String(Int(value))
            }
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    private static func decodeLossyStringArray(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String]? {
        if let value = try? container.decodeIfPresent([String].self, forKey: key) {
            return value
        }
        if let rawArray = try? container.decodeIfPresent([Int].self, forKey: key) {
            return rawArray.map(String.init)
        }
        if let rawArray = try? container.decodeIfPresent([Double].self, forKey: key) {
            return rawArray.map { value in
                floor(value) == value ? String(Int(value)) : String(value)
            }
        }
        return nil
    }
}

struct SteamWorkshopDownloadMetadataSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
    let sourceVideoRelativePath: String?
    let previewRelativePath: String?
    let exportedVideoURL: URL?
    let legacyFolderURL: URL?
    var commit: SteamWorkshopLibraryCommit? = nil
}

struct SteamWorkshopDetailParseResult {
    let title: String
    let author: String
    let authorProfileURL: URL?
    let authorWorkshopURL: URL?
    let summary: String
    let descriptionText: String
    let tags: [String]
    let workshopTypeText: String?
    let ageRatingText: String?
    let genreText: String?
    let categoryText: String?
    let previewImageURL: URL?
    let previewVideoURL: URL?
    let fileSizeText: String?
    let resolutionText: String?
    let postedText: String?
    let updatedText: String?
    let favoritesText: String?
    let subscriptionsText: String?
    let scoreText: String?
    let dependencyIDs: [String]
    let detailFields: [SteamWorkshopDetailField]
}

nonisolated struct SteamWorkshopPublishedFileResponseEnvelope: Decodable {
    let response: SteamWorkshopPublishedFileResponse
}

nonisolated struct SteamWorkshopPublishedFileResponse: Decodable {
    let result: Int?
    let resultcount: Int?
    let publishedfiledetails: [SteamWorkshopPublishedFileDetail]
}

nonisolated struct SteamWorkshopPublishedFileTag: Decodable {
    let tag: String
}

nonisolated struct SteamWorkshopPublishedFileDetail: Decodable {
    let publishedfileid: String
    let result: Int
    let creator: String?
    let creatorAppID: Int?
    let consumerAppID: Int?
    let fileSize: Int64?
    let previewURL: URL?
    let title: String?
    let description: String?
    let timeCreated: Int64?
    let timeUpdated: Int64?
    let visibility: Int?
    let banned: Int?
    let banReason: String?
    let subscriptions: Int?
    let favorited: Int?
    let lifetimeSubscriptions: Int?
    let lifetimeFavorited: Int?
    let views: Int?
    let tags: [SteamWorkshopPublishedFileTag]

    enum CodingKeys: String, CodingKey {
        case publishedfileid
        case result
        case creator
        case creator_app_id
        case consumer_app_id
        case file_size
        case preview_url
        case title
        case description
        case time_created
        case time_updated
        case visibility
        case banned
        case ban_reason
        case subscriptions
        case favorited
        case lifetime_subscriptions
        case lifetime_favorited
        case views
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publishedfileid = try container.decode(String.self, forKey: .publishedfileid)
        result = Self.decodeLossyInt(from: container, forKey: .result) ?? 0
        creator = try container.decodeIfPresent(String.self, forKey: .creator)
        creatorAppID = Self.decodeLossyInt(from: container, forKey: .creator_app_id)
        consumerAppID = Self.decodeLossyInt(from: container, forKey: .consumer_app_id)
        fileSize = Self.decodeLossyInt64(from: container, forKey: .file_size)
        if let preview = try container.decodeIfPresent(String.self, forKey: .preview_url),
           !preview.isEmpty {
            previewURL = URL(string: preview)
        } else {
            previewURL = nil
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        timeCreated = Self.decodeLossyInt64(from: container, forKey: .time_created)
        timeUpdated = Self.decodeLossyInt64(from: container, forKey: .time_updated)
        visibility = Self.decodeLossyInt(from: container, forKey: .visibility)
        banned = Self.decodeLossyInt(from: container, forKey: .banned)
        banReason = try container.decodeIfPresent(String.self, forKey: .ban_reason)
        subscriptions = Self.decodeLossyInt(from: container, forKey: .subscriptions)
        favorited = Self.decodeLossyInt(from: container, forKey: .favorited)
        lifetimeSubscriptions = Self.decodeLossyInt(from: container, forKey: .lifetime_subscriptions)
        lifetimeFavorited = Self.decodeLossyInt(from: container, forKey: .lifetime_favorited)
        views = Self.decodeLossyInt(from: container, forKey: .views)
        tags = (try? container.decode([SteamWorkshopPublishedFileTag].self, forKey: .tags)) ?? []
    }

    private static func decodeLossyInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let string = try? container.decode(String.self, forKey: key) {
            return Int(string)
        }
        return nil
    }

    private static func decodeLossyInt64(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Int64(value)
        }
        if let string = try? container.decode(String.self, forKey: key) {
            return Int64(string)
        }
        return nil
    }
}

nonisolated struct SteamWorkshopBrowserCacheSnapshot: Codable {
    let fetchedAt: Date
    let items: [SteamWorkshopBrowserItem]
}

nonisolated struct SteamWorkshopBrowseStubPage {
    let stubs: [SteamWorkshopBrowseStub]
    let hasMore: Bool
}

nonisolated struct SteamWorkshopDiscoveryBrowseSnapshot {
    let browserContentMode: SteamWorkshopBrowserContentMode
    let browserItems: [SteamWorkshopBrowserItem]
    let browserState: SteamWorkshopBrowserLoadState
    let hasMoreBrowserItems: Bool
    let browserNextPage: Int
    let statusMessage: String
    let currentPageTitle: String
    let requestedURL: URL
    let browserQuery: String
    let currentWorkshopItemID: String?
    let selectedBrowserItem: SteamWorkshopBrowserItem?
    let prefetchedBrowserPageKeys: Set<String>
    let scrollOffsetY: CGFloat
}

nonisolated struct SteamWorkshopBrowseStub: Equatable {
    let id: String
    let title: String?
    let author: String?
    let authorProfileURL: URL?
    let authorWorkshopURL: URL?
    let hasAdultContent: Bool
    let summary: String?
    let previewImageURL: URL?
}

nonisolated struct SteamWorkshopDetailCacheSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
}

nonisolated struct SteamWorkshopBundledRuntimeMetadata: Codable {
    let channel: String
    let version: String
    let releaseDate: String
    let notes: String
}
