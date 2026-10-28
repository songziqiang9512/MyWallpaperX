import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func revealDownloadsDirectory() {
        FinderRevealCoordinator.shared.reveal([libraryRootURL])
    }

    func openWorkshopDetailPage(for item: SteamWorkshopBrowserItem) {
        NSWorkspace.shared.open(item.detailURL)
    }

    func recoveryWorkshopDetailURL(itemID: String) -> URL? {
        guard isValidWorkshopItemID(itemID), itemID.utf8.contains(where: { $0 != 48 }) else { return nil }
        var components = URLComponents(string: "https://steamcommunity.com/sharedfiles/filedetails/")
        components?.queryItems = [URLQueryItem(name: "id", value: itemID)]
        return components?.url
    }

    func openWorkshopDetailPage(itemID: String) {
        guard let url = recoveryWorkshopDetailURL(itemID: itemID) else { return }
        NSWorkspace.shared.open(url)
    }

    func openAuthorProfilePage(for item: SteamWorkshopBrowserItem) {
        if let authorProfileURL = item.authorProfileURL {
            NSWorkspace.shared.open(authorProfileURL)
            return
        }
        if let authorWorkshopURL = item.authorWorkshopURL {
            NSWorkspace.shared.open(authorWorkshopURL)
        }
    }

    func openAuthorWorksPage(for item: SteamWorkshopBrowserItem) {
        showAuthorWorkshop(for: item)
    }
}
