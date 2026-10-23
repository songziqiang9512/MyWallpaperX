import AppKit

// Existing grid harness data has no preview assets. Keep those scenarios neutral.
enum TintSteamDownloadStatus { case ready, pending }
extension SteamWorkshopBrowserItem {
    var previewImageURL: URL? { nil }
}
extension SteamWorkshopDownloadRecord {
    var status: TintSteamDownloadStatus { .pending }
    var previewURL: URL? { nil }
    var browserItem: SteamWorkshopBrowserItem? { nil }
    var displayItem: SteamWorkshopBrowserItem? { nil }
    var exportedVideoURL: URL? { nil }
    var sourceVideoURL: URL? { nil }
    var videoURL: URL? { nil }
    var updatedAt: Date { .distantPast }
}
