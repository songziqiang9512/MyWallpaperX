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

struct SteamWorkshopDiscoveryBrowseSnapshot {
    let browserContentMode: SteamWorkshopBrowserContentMode
    let browserItems: [SteamWorkshopBrowserItem]
    let browserState: SteamWorkshopBrowserLoadState
    let hasMoreBrowserItems: Bool
    let statusMessage: String
    let currentPageTitle: String
    let browserQuery: String
    let currentWorkshopItemID: String?
    let selectedBrowserItem: SteamWorkshopBrowserItem?
    let scrollOffsetY: CGFloat
    let steamKitBrowseSnapshot: SteamKitBrowseStore.Snapshot
}

nonisolated struct SteamWorkshopDetailCacheSnapshot: Codable {
    let fetchedAt: Date
    let item: SteamWorkshopBrowserItem
}
