import Foundation

enum SteamWorkshopDownloadsSortMode: String, CaseIterable, Equatable {
    case updatedAt
    case title
    case size

    var displayName: String {
        switch self {
        case .updatedAt:
            return "修改时间"
        case .title:
            return "名称"
        case .size:
            return "文件大小"
        }
    }
}

enum SteamWorkshopDownloadContentType: String, CaseIterable, Equatable {
    case video
    case web
    case scene
    case unknown

    var displayName: String {
        switch self {
        case .video:
            return "视频壁纸"
        case .web:
            return "WEB壁纸"
        case .scene:
            return "Scene壁纸"
        case .unknown:
            return "未知类型"
        }
    }
}

enum SteamWorkshopDownloadsDisplayMode: String, CaseIterable, Equatable {
    case all
    case video
    case web
    case scene

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .video:
            return "视频"
        case .web:
            return "Web"
        case .scene:
            return "场景"
        }
    }

    var emptyStateText: String {
        switch self {
        case .all:
            return "当前 workshop 目录里还没有已下载项目"
        case .video:
            return "当前 workshop 目录里还没有已下载的视频项目"
        case .web:
            return "当前 workshop 目录里还没有已下载的WEB壁纸项目"
        case .scene:
            return "当前 workshop 目录里还没有已下载的Scene项目"
        }
    }
}

nonisolated enum SteamWorkshopPreviewAssetKind: String, Equatable, Codable {
    case unknown
    case stillImage
    case animatedImage
    case video

    var isAnimated: Bool {
        self == .animatedImage || self == .video
    }
}

nonisolated struct SteamWorkshopDetailField: Identifiable, Equatable, Codable {
    let label: String
    let value: String

    var id: String { "\(label):\(value)" }
}

nonisolated struct SteamWorkshopBrowserItem: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let author: String
    let authorProfileURL: URL?
    let authorWorkshopURL: URL?
    let hasAdultContent: Bool
    let summary: String
    let descriptionText: String
    let tags: [String]
    let workshopTypeText: String?
    let ageRatingText: String?
    let genreText: String?
    let categoryText: String?
    let dependencyIDs: [String]
    let previewImageURL: URL?
    let previewVideoURL: URL?
    let previewAssetKind: SteamWorkshopPreviewAssetKind
    let fileSizeText: String?
    let resolutionText: String?
    let postedText: String?
    let updatedText: String?
    let favoritesText: String?
    let subscriptionsText: String?
    let scoreText: String?
    let lifetimeFavoritesText: String?
    let lifetimeSubscriptionsText: String?
    let visibilityText: String?
    let moderationText: String?
    let detailFields: [SteamWorkshopDetailField]
    let detailURL: URL

    var primaryMetaText: String {
        [fileSizeText, resolutionText]
            .compactMap { $0 }
            .joined(separator: "  ")
    }

    var secondaryMetaText: String {
        [workshopTypeText, ageRatingText, genreText, updatedText]
            .compactMap { $0 }
            .joined(separator: "  ")
    }
}

struct SteamWorkshopDownloadRecord: Identifiable, Equatable {
    enum Status: Equatable {
        case queued
        case downloading
        case ready
        case failed(String)
    }

    let id: String
    let title: String
    let description: String
    let tags: [String]
    let folderURL: URL
    let projectFileURL: URL?
    let ownEntryHTMLURL: URL?
    let dependencyHostEntryHTMLURL: URL?
    let dependencyHostFolderURL: URL?
    let entryHTMLURL: URL?
    let resolvedWebRootURL: URL?
    let previewURL: URL?
    let sourceVideoURL: URL?
    let exportedVideoURL: URL?
    let updatedAt: Date
    let sizeText: String
    let status: Status
    let browserItem: SteamWorkshopBrowserItem?
    let contentType: SteamWorkshopDownloadContentType
    let dependencyItemID: String?
    let dependencyStatus: SteamWorkshopWebDependencyStatus

    var videoURL: URL? {
        if let exportedVideoURL,
           FileManager.default.fileExists(atPath: exportedVideoURL.path) {
            return exportedVideoURL
        }
        if let sourceVideoURL,
           FileManager.default.fileExists(atPath: sourceVideoURL.path) {
            return sourceVideoURL
        }
        return nil
    }

    var statusText: String {
        switch status {
        case .queued:
            return "等待下载"
        case .downloading:
            return "下载中"
        case .ready:
            return "已下载"
        case .failed:
            return "下载失败"
        }
    }

    var failureMessage: String? {
        guard case let .failed(message) = status else { return nil }
        return message
    }

    var isPlayable: Bool {
        status == .ready && videoURL != nil
    }

    var displayItem: SteamWorkshopBrowserItem? {
        guard let browserItem else { return nil }
        return SteamWorkshopBrowserItem(
            id: browserItem.id,
            title: browserItem.title,
            author: browserItem.author,
            authorProfileURL: browserItem.authorProfileURL,
            authorWorkshopURL: browserItem.authorWorkshopURL,
            hasAdultContent: browserItem.hasAdultContent,
            summary: browserItem.summary,
            descriptionText: browserItem.descriptionText,
            tags: browserItem.tags,
            workshopTypeText: browserItem.workshopTypeText,
            ageRatingText: browserItem.ageRatingText,
            genreText: browserItem.genreText,
            categoryText: browserItem.categoryText,
            dependencyIDs: browserItem.dependencyIDs,
            previewImageURL: previewURL ?? browserItem.previewImageURL,
            previewVideoURL: browserItem.previewVideoURL,
            previewAssetKind: browserItem.previewAssetKind,
            fileSizeText: sizeText.isEmpty ? browserItem.fileSizeText : sizeText,
            resolutionText: browserItem.resolutionText,
            postedText: browserItem.postedText,
            updatedText: browserItem.updatedText,
            favoritesText: browserItem.favoritesText,
            subscriptionsText: browserItem.subscriptionsText,
            scoreText: browserItem.scoreText,
            lifetimeFavoritesText: browserItem.lifetimeFavoritesText,
            lifetimeSubscriptionsText: browserItem.lifetimeSubscriptionsText,
            visibilityText: browserItem.visibilityText,
            moderationText: browserItem.moderationText,
            detailFields: browserItem.detailFields,
            detailURL: browserItem.detailURL
        )
    }

    var displayItemForToolbar: SteamWorkshopBrowserItem {
        let fallbackWorkshopTypeText = contentType.displayName
        return displayItem ?? SteamWorkshopBrowserItem(
            id: id,
            title: title,
            author: "未知作者",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: description,
            descriptionText: description,
            tags: tags,
            workshopTypeText: fallbackWorkshopTypeText,
            ageRatingText: nil,
            genreText: nil,
            categoryText: "Wallpaper",
            dependencyIDs: [],
            previewImageURL: previewURL,
            previewVideoURL: nil,
            previewAssetKind: .stillImage,
            fileSizeText: sizeText,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!
        )
    }
}
