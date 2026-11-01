import Foundation

struct SystemWallpaperCatalog: Encodable {
    private static let provider = Bundle.main.bundleIdentifier ?? "com.songziqiang.MyWallpaperX.WallpaperExtension"
    // Empty replaces the previously advertised wallpaper catalog in the host cache.
    let desktop = View(groups: [])
    let screenSaver: View
    init(media: SystemWallpaperMedia?) {
        screenSaver = View(groups: media.map { [Group(media: $0)] } ?? [])
    }

    struct View: Encodable {
        let groups: [Group]
        let refreshPolicy = ["default": [String: String]()]
        let isModificationDisabled = false
    }
    struct Identifier: Encodable { let id: String }
    struct Group: Encodable {
        let id = Identifier(id: provider + ".saved-video")
        let items: [Item]
        let localizedName = "MyWallpaperX"
        let disposability = ["none": [String: String]()]
        let sortOrder = 0
        let sortID = Identifier(id: provider + ".saved-video")
        let allChoiceID = Absent()
        let shouldHideItemLabels = false
        let contextMenu = Absent()
        let thumbnail = Absent()
        init(media: SystemWallpaperMedia) { items = [Item(media: media)] }
    }
    struct ChoiceID: Encodable {
        let id = provider + ".saved-video"
        let descriptor = Descriptor()
    }
    struct Descriptor: Encodable {
        let provider = SystemWallpaperCatalog.provider
        let identifier = "saved-video"
        let files: [URL] = []
        let configuration = Data()
    }
    struct Thumbnail: Encodable {
        struct Image: Encodable { let url: URL }
        let image: Image
        init(url: URL) { image = Image(url: url) }
    }
    struct Choice: Encodable {
        let id = ChoiceID()
        let provider = SystemWallpaperCatalog.provider
        let identifier = "saved-video"
        let name: String
        let localizedDescription = "视频动态锁屏"
        let thumbnail: Thumbnail
        let isDownloaded = true
        let options: [String] = []
    }
    struct Item: Encodable {
        let id = ChoiceID()
        let localizedName: String
        let thumbnail: Thumbnail
        let choice: Choice
        let contentBadge = ["video": [String: String]()]
        let showInTopLevel = true
        let sortOrder = 0
        let disposability = ["none": [String: String]()]
        init(media: SystemWallpaperMedia) {
            localizedName = media.configuration.content?.title ?? "视频动态锁屏"
            thumbnail = Thumbnail(url: media.poster)
            choice = Choice(name: localizedName, thumbnail: thumbnail)
        }
    }

    // The host's keyed decoder requires optional keys to be present with nil.
    struct Absent: Encodable {
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}
