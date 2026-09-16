import Foundation

extension AppKitMainSplitViewController {
    func prepareSteamBrowseSelection(_ item: SelectedItem) {
        guard item.isInSteamWorkshopContext else { return }
        let service = SteamWorkshopService.shared
        if service.isBrowsingAuthorWorkshop {
            service.returnToDiscoveryBrowse()
        }
        switch item {
        case .steamSubscribed:
            if service.source != .mySubscriptions {
                service.suppressAutomaticBrowseNavigation = true
                service.browserContentMode = .all
                service.facetFilters = .none
                service.setBrowserQuery("")
                service.suppressAutomaticBrowseNavigation = false
                service.source = .mySubscriptions
            }
        case .steamWorkshop where service.source.isPersonal:
            service.source = .featured
        default:
            break
        }
    }
}
