import Foundation

nonisolated struct WallhavenSearchResponse: Decodable {
    let data: [WallhavenWallpaperDTO]
    let meta: Meta

    struct Meta: Decodable {
        let currentPage: Int
        let lastPage: Int
        let total: Int
        let seed: String?
        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page", lastPage = "last_page", total, seed
        }
    }
}

nonisolated struct WallhavenDetailResponse: Decodable { let data: WallhavenWallpaperDTO }

nonisolated struct WallhavenWallpaperDTO: Decodable {
    let id: String
    let url: String
    let path: String?
    let purity: String?
    let fileType: String?
    let dimensionX: Int?
    let dimensionY: Int?
    let fileSize: Int64?
    let thumbs: Thumbs?
    let uploader: Uploader?
    let tags: [Tag]?

    struct Thumbs: Decodable { let large: String?; let original: String?; let small: String? }
    struct Uploader: Decodable { let username: String? }
    struct Tag: Decodable { let name: String }
    enum CodingKeys: String, CodingKey {
        case id, url, path, purity, thumbs, uploader, tags
        case fileType = "file_type", dimensionX = "dimension_x", dimensionY = "dimension_y", fileSize = "file_size"
    }

    func artwork() -> OnlineImageArtwork? {
        guard !id.isEmpty, let sourceURL = Self.webURL(url) else { return nil }
        let thumbnail = Self.webURL(thumbs?.large) ?? Self.webURL(thumbs?.small)
        let original = Self.webURL(path)
        let username = uploader?.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = username.flatMap { $0.isEmpty ? nil : $0 }
        let rating: OnlineImageRating
        switch purity {
        case "sfw": rating = .safe
        case "sketchy": rating = .sensitive
        case "nsfw": rating = .adult
        default: rating = .unknown
        }
        return OnlineImageArtwork(source: .wallhaven, artworkID: id, title: "Wallhaven #\(id)",
            sourceURL: sourceURL, thumbnailURL: thumbnail,
            previewURL: Self.webURL(thumbs?.original) ?? thumbnail, originalURL: original,
            author: author, authorID: author, tags: tags?.map(\.name) ?? [],
            width: dimensionX.flatMap { $0 > 0 ? $0 : nil }, height: dimensionY.flatMap { $0 > 0 ? $0 : nil },
            fileSizeBytes: fileSize.flatMap { $0 > 0 ? $0 : nil }, pageCount: 1,
            kind: fileType?.hasPrefix("image/") == true ? .image : .unknown, rating: rating)
    }

    private static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), let host = url.host, !host.isEmpty,
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}
