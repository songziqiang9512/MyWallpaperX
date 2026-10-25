import Foundation
import CoreGraphics

enum SteamWorkshopAuthorReturnDestination {
    case discovery, personal, downloads

    var selectionKey: String {
        switch self {
        case .discovery: return "steamWorkshop"
        case .personal: return "steamSubscribed"
        case .downloads: return "steamDownloads"
        }
    }

    var title: String {
        switch self {
        case .discovery: return "返回创意工坊"
        case .personal: return "返回我的订阅"
        case .downloads: return "返回已下载"
        }
    }
}

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
    let presetImagePaths: [String]

    private enum PresetImageKey: String, CodingKey, CaseIterable {
        case backgroundimageb, backgroundimage, background_image, foreground_image, image, bgimage
    }

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
        case preset
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
        if let preset = try? container.nestedContainer(keyedBy: PresetImageKey.self, forKey: .preset) {
            presetImagePaths = PresetImageKey.allCases.compactMap { try? preset.decode(String.self, forKey: $0) }
        } else {
            presetImagePaths = []
        }
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

nonisolated struct SteamWorkshopDownloadMetadataSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
    let sourceVideoRelativePath: String?
    let previewRelativePath: String?
    let exportedVideoURL: URL?
    let legacyFolderURL: URL?
    /// Legacy direct entries have no versioned commit. A durable tombstone
    /// suppresses their scanner projection without unlinking content that an
    /// existing playback owner may still reference.
    var legacyRemoved: Bool? = nil
    var commit: SteamWorkshopLibraryCommit? = nil
    var firstDownloadedAt: Date? = nil

    func resolvedFirstDownloadDate(fallbackCreationDate: Date? = nil) -> Date? {
        firstDownloadedAt ?? commit?.committedAt ?? fallbackCreationDate
            ?? (fetchedAt > .distantPast ? fetchedAt : nil)
    }
}

enum SteamWorkshopBrowseSection: Hashable { case discovery, personal }

struct SteamWorkshopDiscoveryBrowseSnapshot {
    let browserContentMode: SteamWorkshopBrowserContentMode
    let browserItems: [SteamWorkshopBrowserItem]
    let browserState: SteamWorkshopBrowserLoadState
    let hasMoreBrowserItems: Bool
    let browserLoadMoreFailureMessage: String?
    let statusMessage: String
    let currentPageTitle: String
    let browserQuery: String
    let currentWorkshopItemID: String?
    let selectedBrowserItem: SteamWorkshopBrowserItem?
    /// In-memory uncovered document viewport minY; zero means the real top.
    /// This snapshot does not persist a window-specific native toolbar inset.
    let scrollOffsetY: CGFloat
    var steamKitBrowseSnapshot: SteamKitBrowseStore.Snapshot
    var source: SteamWorkshopSource = .featured
    var facetFilters: SteamWorkshopBrowseFacetFilters = .none
    var personalSort: SteamWorkshopPersonalSort = .subscriptionDate
    var trendingWindow: SteamWorkshopTrendingWindow = .week
    var consecutiveEmptyLoadMorePages: Int = 0
    var browserLoadMoreRetryAfter: Date = .distantPast
}

nonisolated struct SteamWorkshopDetailCacheSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
}
