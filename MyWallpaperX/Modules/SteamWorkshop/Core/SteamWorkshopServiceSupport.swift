import Foundation

struct SteamWorkshopPendingDownloadRequest {
    let id: String
    let pageTitle: String?
    let item: SteamWorkshopBrowserItem?
    /// Created only at an explicit user download admission. Recovered jobs
    /// have no in-memory callback and cannot revive a later library exclusion.
    var libraryRestoration: (() -> Void)? = nil
}
