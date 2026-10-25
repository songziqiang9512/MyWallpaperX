import AppKit

struct OnlineLibraryVideoItem { let id: Int; var previewThumbnailURL: URL? }
@MainActor final class OnlineProjection {
    let listThumbnailTintSource = ListThumbnailTintSource()
    var orderedIDs: [Int] = [], itemsByID: [Int: OnlineLibraryVideoItem] = [:]
    // ONLINE_METHODS
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
        steam.orderedIDs = []; steam.publishListThumbnailTint()
        check("steamEmptyListClears", steam.listThumbnailTintSource.request == nil)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["checks": checks], options: [.sortedKeys]))
    }
}
