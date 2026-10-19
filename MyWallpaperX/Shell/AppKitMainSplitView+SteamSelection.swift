import Foundation

extension AppKitMainSplitViewController {
    func prepareSteamBrowseSelection(_ item: SelectedItem, preservingContext: Bool = false) {
        guard !preservingContext else { return }
        let service = SteamWorkshopService.shared
        if service.isBrowsingAuthorWorkshop {
            service.returnToDiscoveryBrowse(selectOrigin: false)
        }
        service.pendingDownloadsScrollRestoreOffsetY = nil
        switch item {
        case .steamSubscribed:
            service.enterBrowseSection(.personal)
            service.prepareForBrowserEntry()
        case .steamWorkshop:
            service.enterBrowseSection(.discovery)
            service.prepareForBrowserEntry()
        default:
            break
        }
    }
}
