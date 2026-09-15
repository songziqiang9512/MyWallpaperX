import Foundation

enum SteamWorkshopDownloadControlError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消下载。"
        }
    }
}

struct SteamWorkshopPendingDownloadRequest {
    let id: String
    let pageTitle: String?
    let item: SteamWorkshopBrowserItem?
}
