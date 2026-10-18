import Foundation

extension AppKitMainSplitViewController {
    func prepareSteamBrowseSelection(_ item: SelectedItem, preservingContext: Bool = false) {
        guard item.isInSteamWorkshopContext, !preservingContext else { return }
        let service = SteamWorkshopService.shared
        if service.isBrowsingAuthorWorkshop {
            service.returnToDiscoveryBrowse()
        }
        switch item {
        case .steamSubscribed:
            service.enterBrowseSection(.personal)
        case .steamWorkshop:
            service.enterBrowseSection(.discovery)
        default:
            break
        }
    }
}
