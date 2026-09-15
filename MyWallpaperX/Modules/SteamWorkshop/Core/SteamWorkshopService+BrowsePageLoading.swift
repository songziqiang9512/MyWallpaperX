import Foundation

extension SteamWorkshopService {
    func loadMoreBrowserItemsIfNeeded() {
        if shouldUseSteamKitStructuredBrowse {
            loadMoreDiscoveryViaSteamKitIfNeeded()
        } else {
            loadMorePersonalViaSteamKitIfNeeded()
        }
    }
}
