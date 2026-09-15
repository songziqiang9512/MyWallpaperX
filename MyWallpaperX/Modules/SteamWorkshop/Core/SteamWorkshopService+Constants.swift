import Foundation

extension SteamWorkshopService {
    enum Constants {
        nonisolated static let workshopAppID = "431960"
        nonisolated static let detailBase = "https://steamcommunity.com/sharedfiles/filedetails/"
        nonisolated static let loadMoreRetryCooldown: TimeInterval = 2.0
        nonisolated static let detailCacheTTL: TimeInterval = 60 * 60 * 24
    }
}
