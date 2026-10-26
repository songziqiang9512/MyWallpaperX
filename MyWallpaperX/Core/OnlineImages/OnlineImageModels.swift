import Foundation

nonisolated enum OnlineImageSource: String, Codable, CaseIterable, Sendable {
    case wallhaven, pixiv
    var provider: WallpaperProvider { self == .wallhaven ? .wallhaven : .pixiv }
    var displayName: String { self == .wallhaven ? "Wallhaven" : "Pixiv" }
}

nonisolated struct OnlineImageAssetID: Hashable, Codable, Sendable {
    let source: OnlineImageSource
    let artworkID: String
    var pageIndex: Int = 0
    var reference: WallpaperReference {
        .init(provider: source.provider, sourceID: source == .wallhaven ? artworkID : "\(artworkID):p\(pageIndex)")
    }
    init(source: OnlineImageSource, artworkID: String, pageIndex: Int = 0) {
        self.source = source; self.artworkID = artworkID; self.pageIndex = pageIndex
    }
    init?(reference: WallpaperReference) {
        switch reference.provider {
        case .wallhaven:
            guard !reference.sourceID.isEmpty else { return nil }
            self.init(source: .wallhaven, artworkID: reference.sourceID)
        case .pixiv:
            guard let marker = reference.sourceID.range(of: ":p", options: .backwards),
                  let page = Int(reference.sourceID[marker.upperBound...]), page >= 0,
                  String(page) == reference.sourceID[marker.upperBound...], marker.lowerBound != reference.sourceID.startIndex else { return nil }
            self.init(source: .pixiv, artworkID: String(reference.sourceID[..<marker.lowerBound]), pageIndex: page)
        default: return nil
        }
    }
}

nonisolated enum OnlineImageKind: String, Codable, Sendable { case image, animation, unknown }
nonisolated enum OnlineImageRating: String, Codable, Sendable { case safe, sensitive, adult, unknown }

/// Browsing values are not local publications and never grant organization or playback.
nonisolated struct OnlineImageArtwork: Identifiable, Equatable, Sendable {
    let source: OnlineImageSource
    let artworkID: String
    var title: String
    var sourceURL: URL
    var thumbnailURL: URL? = nil
    var previewURL: URL? = nil
    var originalURL: URL? = nil
    var author: String? = nil
    var authorID: String? = nil
    var tags: [String] = []
    var width: Int? = nil
    var height: Int? = nil
    var fileSizeBytes: Int64? = nil
    var pageCount: Int? = nil
    var kind: OnlineImageKind = .unknown
    var rating: OnlineImageRating = .unknown
    var isMasked: Bool? = nil
    var createdAt: Date? = nil
    var id: String { source.rawValue + ":" + artworkID }
    var firstAssetID: OnlineImageAssetID { .init(source: source, artworkID: artworkID) }
}

nonisolated struct OnlineImageAsset: Equatable, Sendable {
    let id: OnlineImageAssetID
    var title: String
    var sourceURL: URL
    var originalURL: URL
    var previewURL: URL? = nil
    var author: String? = nil
    var authorID: String? = nil
    var tags: [String] = []
    var width: Int? = nil
    var height: Int? = nil
    var expectedBytes: Int64? = nil
}

/// Named response continuation facts; each source consumes only its own seed/date.
nonisolated struct OnlineImagePageRequest: Equatable, Sendable {
    var page: Int = 1
    var seed: String? = nil
    var date: String? = nil
    var offset: Int? = nil
}

nonisolated struct OnlineImagePage: Sendable {
    var items: [OnlineImageArtwork]
    var next: OnlineImagePageRequest?
    var total: Int? = nil
    var notice: String? = nil
}

/// The manifest owns downloaded images; credentials and expiring CDN URLs are never persisted.
nonisolated struct OnlineImageLocalRecord: Codable, Equatable, Sendable, Identifiable {
    let assetID: OnlineImageAssetID
    let title: String
    let sourceURL: URL
    let author: String?
    let authorID: String?
    let tags: [String]
    let relativePath: String
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSizeBytes: Int64
    let firstDownloadedAt: Date
    let revision: UUID
    var id: OnlineImageAssetID { assetID }
}

nonisolated struct OnlineImageLocalSnapshot: Equatable, Sendable {
    var records: [OnlineImageLocalRecord] = []
    var unavailable: Set<OnlineImageAssetID> = []
    var status: WallpaperSourceScanStatus = .initial
    var revision: UInt64 = 0
}

nonisolated enum OnlineImageError: LocalizedError, Sendable {
    case invalidResponse, unsupported, loginRequired, forbidden, rateLimited, message(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "网站返回了无法识别的内容，请稍后重试。"
        case .unsupported: return "当前作品类型暂不支持下载或设为壁纸。"
        case .loginRequired: return "请登录后继续访问此内容。"
        case .forbidden: return "此内容目前不可访问，请检查账号权限或打开原站。"
        case .rateLimited: return "请求过于频繁，请稍后重试。"
        case .message(let message): return message
        }
    }
}
