import AppKit

struct VideoWallpaper {
    let id: String; var title: String; var path: String
    var tags: [String] = []; var thumbnailPath: String?; var staticFramePath: String?
}
@MainActor final class WallpaperManager {
    // VIDEO_FILTER
}
@MainActor final class AppKitThumbnailProvider {
    var image: NSImage?
    var loaded: [String] = []; var priorities: [TintThumbnailPriority] = []
    func loadThumbnail(for item: VideoWallpaper, priority: TintThumbnailPriority,
                       completion: @escaping (NSImage?) -> Void) -> ThumbnailCacheRequestCancellation {
        loaded.append(item.path); priorities.append(priority); completion(image)
        return ThumbnailCacheRequestCancellation()
    }
    func cancelAllPrefetch() {}
}
@MainActor final class VideoProjection {
    let listThumbnailTintSource = ListThumbnailTintSource()
    let wallpaperManager = WallpaperManager(), thumbnailProvider = AppKitThumbnailProvider()
    var sourceWallpapers: [VideoWallpaper] = []
    var orderedIDs: [String] = [], wallpapersByID: [String: VideoWallpaper] = [:]
    var orderedIndexByID: [String: Int] = [:], lastAppliedQuery = ""
    let emptyStateLabel = NSTextField()
    var snapshotIDs: [String] = []
    func rebuildPathIndex(_ items: [VideoWallpaper]) {}
    func applySnapshot(ids: [String]) { snapshotIDs = ids }
    func scheduleViewportPrefetch() {}
    // VIDEO_METHODS
}
struct SILWallpaper {
    let id: String; let path: String
    var fileSize: Int64 = 1; var addedAt = Date.distantPast
}
@MainActor final class SILProjection {
    let listThumbnailTintSource = ListThumbnailTintSource()
    let thumbnailCache = TintRecordingThumbnailCache()
    var orderedIDs: [String] = [], wallpapersByID: [String: SILWallpaper] = [:]
    // SIL_METHODS
}
struct OnlineLibraryVideoItem { let id: Int; var previewThumbnailURL: URL? }
@MainActor final class OnlineProjection {
    let listThumbnailTintSource = ListThumbnailTintSource()
    var orderedIDs: [Int] = [], itemsByID: [Int: OnlineLibraryVideoItem] = [:]
    // ONLINE_METHODS
}
struct OLDownloadedEntry { let id: Int; let localURL: URL; var thumbnailSourceKey: String? }
@MainActor enum OLDownloadedThumbnailStore {
    static var loaded: [Int] = [], image: NSImage?
    static func prefetch(_ entry: OLDownloadedEntry, cancellation: ThumbnailCacheRequestCancellation,
                         completion: @escaping (String, NSImage?) -> Void) {
        loaded.append(entry.id); completion(entry.thumbnailSourceKey ?? "", image)
    }
}
@MainActor final class OnlineDownloadsProjection {
    let listThumbnailTintSource = ListThumbnailTintSource()
    var orderedIDs: [Int] = [], entriesByID: [Int: OLDownloadedEntry] = [:]
    // ONLINE_DOWNLOAD_METHODS
}
struct SteamWorkshopBrowserItem: Equatable { let id: String; var previewImageURL: URL? }
enum TintDownloadStatus { case ready, downloading }
struct SteamWorkshopDownloadRecord {
    let id: String; var status: TintDownloadStatus = .ready
    var previewURL: URL?; var browserItem: SteamWorkshopBrowserItem?
    var displayItem: SteamWorkshopBrowserItem? { browserItem }
    var exportedVideoURL: URL?; var sourceVideoURL: URL?
    var videoURL: URL? { exportedVideoURL ?? sourceVideoURL }
    var updatedAt = Date(timeIntervalSince1970: 123)
}
@MainActor final class SteamTintService {
    var previewReloadToken = 0
    var records: [String: SteamWorkshopDownloadRecord] = [:]
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { records[id] }
}
enum SteamWorkshopDownloadGridSupport {
    static func fallbackDisplayItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(id: record.id)
    }
}
@MainActor final class SteamProjection {
    let listThumbnailTintSource = ListThumbnailTintSource(), service = SteamTintService()
    var orderedIDs: [String] = [], itemsByID: [String: SteamWorkshopBrowserItem] = [:]
    // STEAM_METHODS
}
@MainActor final class SteamDownloadsProjection {
    let listThumbnailTintSource = ListThumbnailTintSource(), service = SteamTintService()
    var orderedIDs: [String] = [], recordsByID: [String: SteamWorkshopDownloadRecord] = [:]
    // STEAM_DOWNLOAD_METHODS
}

@main struct ListThumbnailTintProjectionChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        func check(_ key: String, _ value: Bool) { checks[key] = value }
        func load(_ source: ListThumbnailTintSource) -> NSImage? {
            var image: NSImage?
            let cancel = source.request?.load { image = $0 }
            let deadline = Date().addingTimeInterval(1)
            while image == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            cancel?(); return image
        }
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let video = VideoProjection(); video.thumbnailProvider.image = image
        video.sourceWallpapers = [VideoWallpaper(id: "skip", title: "not matched", path: "/skip"),
            VideoWallpaper(id: "B", title: "keep first", path: "/first", thumbnailPath: "/thumb"),
            VideoWallpaper(id: "B", title: "keep duplicate", path: "/wrong"),
            VideoWallpaper(id: "A", title: "keep next", path: "/last")]
        video.applyFilterAndSnapshot(usingNormalizedQuery: "keep")
        check("videoRealFilterAndDedupChooseDisplayedFirst", video.snapshotIDs == ["B", "A"]
            && video.listThumbnailTintSource.request?.identity.itemID == "B")
        check("videoLoadsFirstRetainedAssetAtPrefetchPriority", load(video.listThumbnailTintSource) === image
            && video.thumbnailProvider.loaded == ["/first"] && video.thumbnailProvider.priorities == [.prefetch])
        let beforeAsset = video.listThumbnailTintSource.request!.revision
        video.sourceWallpapers[1].thumbnailPath = "/replacement"
        video.applyFilterAndSnapshot(usingNormalizedQuery: "keep")
        check("videoSameIDNewThumbnailRevises", video.listThumbnailTintSource.request?.revision != beforeAsset)
        video.applyFilterAndSnapshot(usingNormalizedQuery: "not-present")
        check("videoEmptyFilterClears", video.listThumbnailTintSource.request == nil)

        let sil = SILProjection(); sil.thumbnailCache.image = image
        sil.orderedIDs = ["second", "first"]
        sil.wallpapersByID = ["first": SILWallpaper(id: "first", path: "/wrong"), "second": SILWallpaper(id: "second", path: "/right")]
        sil.publishListThumbnailTint()
        check("silUsesOrderedFirstAndPrefetch", sil.listThumbnailTintSource.request?.identity.itemID == "second"
            && load(sil.listThumbnailTintSource) === image && sil.thumbnailCache.keys == ["/right"] && sil.thumbnailCache.priorities == [.prefetch])
        let silRevision = sil.listThumbnailTintSource.request!.revision
        sil.wallpapersByID["second"]?.fileSize = 99; sil.publishListThumbnailTint()
        check("silSamePathFileRevisionChangesRequest", sil.listThumbnailTintSource.request?.revision != silRevision)
        sil.orderedIDs = []; sil.publishListThumbnailTint()
        check("silEmptyClears", sil.listThumbnailTintSource.request == nil)

        let url = URL(string: "https://fixture.invalid/right.jpg")!
        let online = OnlineProjection(); OLThumbnailCache.shared.result = image
        online.itemsByID = [8: OnlineLibraryVideoItem(id: 8, previewThumbnailURL: url), 1: OnlineLibraryVideoItem(id: 1)]
        online.orderedIDs = [8, 1]; online.publishListThumbnailTint()
        check("onlineUsesOrderedFirstAndPrefetch", online.listThumbnailTintSource.request?.identity.itemID == "8"
            && load(online.listThumbnailTintSource) === image && OLThumbnailCache.shared.urls == [url]
            && OLThumbnailCache.shared.priorities == [.prefetch])
        online.orderedIDs = [1, 8]; online.publishListThumbnailTint()
        var absent: NSImage? = image
        let absentCancel = online.listThumbnailTintSource.request!.load { absent = $0 }; absentCancel()
        check("onlineMissingFirstImageDoesNotSelectSecond", absent == nil && OLThumbnailCache.shared.urls == [url])
        online.orderedIDs = []; online.publishListThumbnailTint()
        check("onlineEmptyClears", online.listThumbnailTintSource.request == nil)

        let downloads = OnlineDownloadsProjection(); OLDownloadedThumbnailStore.image = image
        downloads.orderedIDs = [9, 2]
        downloads.entriesByID = [9: OLDownloadedEntry(id: 9, localURL: URL(fileURLWithPath: "/right.mp4"), thumbnailSourceKey: "v1"),
                                2: OLDownloadedEntry(id: 2, localURL: URL(fileURLWithPath: "/wrong.mp4"))]
        downloads.publishListThumbnailTint()
        check("onlineDownloadsUseOrderedFirst", load(downloads.listThumbnailTintSource) === image
            && downloads.listThumbnailTintSource.request?.identity.itemID == "9" && OLDownloadedThumbnailStore.loaded == [9])
        let downloadRevision = downloads.listThumbnailTintSource.request!.revision
        downloads.entriesByID[9]?.thumbnailSourceKey = "v2"; downloads.publishListThumbnailTint()
        check("onlineDownloadedAssetRevisionChangesRequest", downloads.listThumbnailTintSource.request?.revision != downloadRevision)
        downloads.orderedIDs = []; downloads.publishListThumbnailTint()
        check("onlineDownloadsEmptyClears", downloads.listThumbnailTintSource.request == nil)

        TintSteamTransport.image = image
        let item = SteamWorkshopBrowserItem(id: "second", previewImageURL: url)
        let local = URL(fileURLWithPath: "/preview.jpg")
        var record = SteamWorkshopDownloadRecord(id: item.id, previewURL: local, browserItem: item)
        let wrongItem = SteamWorkshopBrowserItem(id: "first", previewImageURL: URL(string: "https://fixture.invalid/wrong.jpg")!)
        let steam = SteamProjection(); steam.orderedIDs = [item.id, wrongItem.id]; steam.itemsByID = [item.id: item, wrongItem.id: wrongItem]
        steam.service.records[item.id] = record; steam.publishListThumbnailTint()
        check("steamActualAdapterUsesLocalReadyFirstAtPrefetch", load(steam.listThumbnailTintSource) === image
            && steam.listThumbnailTintSource.request?.identity.itemID == item.id && TintSteamTransport.loads.last == local
            && TintSteamTransport.priorities.last == .prefetch && TintSteamTransport.animationLoads == 0)
        let readyRevision = steam.listThumbnailTintSource.request!.revision
        record.updatedAt = Date(timeIntervalSince1970: 456); steam.service.records[item.id] = record; steam.publishListThumbnailTint()
        check("steamReadyRevisionAndRefreshTokenInvalidate", steam.listThumbnailTintSource.request?.revision != readyRevision)
        let refreshed = steam.listThumbnailTintSource.request!.revision
        steam.service.previewReloadToken += 1; steam.publishListThumbnailTint()
        check("steamRefreshTokenRevises", steam.listThumbnailTintSource.request?.revision != refreshed)
        TintSteamTransport.image = nil; TintSteamTransport.images[url.absoluteString] = image
        let beforeFallback = TintSteamTransport.loads.count
        check("steamMissingInstalledPreviewFallsThroughRealStateToRemote", load(steam.listThumbnailTintSource) === image
            && Array(TintSteamTransport.loads.dropFirst(beforeFallback)) == [local, url])
        record.status = .downloading; steam.service.records[item.id] = record; steam.publishListThumbnailTint()
        let progressRevision = steam.listThumbnailTintSource.request!.revision
        record.updatedAt = Date(timeIntervalSince1970: 999); steam.service.records[item.id] = record; steam.publishListThumbnailTint()
        check("steamProgressTimestampDoesNotRecolor", steam.listThumbnailTintSource.request?.revision == progressRevision)
        record.status = .ready
        let sd = SteamDownloadsProjection(); sd.orderedIDs = [item.id, wrongItem.id]
        sd.recordsByID = [item.id: record, wrongItem.id: SteamWorkshopDownloadRecord(id: wrongItem.id, browserItem: wrongItem)]
        sd.publishListThumbnailTint()
        check("steamDownloadsActualAdapterUsesDisplayedFirst", load(sd.listThumbnailTintSource) === image
            && sd.listThumbnailTintSource.request?.identity.itemID == item.id && TintSteamTransport.loads.last == url)
        record.browserItem = nil; sd.recordsByID[item.id] = record; sd.publishListThumbnailTint()
        check("steamDownloadsFallbackRetainsRecordID", sd.listThumbnailTintSource.request?.identity.itemID == item.id)
        steam.orderedIDs = []; steam.publishListThumbnailTint(); sd.orderedIDs = []; sd.publishListThumbnailTint()
        check("bothSteamEmptyListsClear", steam.listThumbnailTintSource.request == nil && sd.listThumbnailTintSource.request == nil)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["checks": checks], options: [.sortedKeys]))
    }
}
