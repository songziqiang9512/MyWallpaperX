import Combine
import Foundation

extension SteamWorkshopService {
    func observeWebPlaybackFailures() {
        NotificationCenter.default.publisher(for: WallpaperEngine.playbackFailedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let contentKind = notification.userInfo?["contentKind"] as? String,
                      contentKind == "web" else { return }
                self.lastWebPlaybackFailureRecordID = notification.userInfo?["recordID"] as? String
                self.lastWebPlaybackFailurePath =
                    notification.userInfo?["path"] as? String
                    ?? notification.userInfo?["videoPath"] as? String
                self.lastWebPlaybackFailureMessage = notification.userInfo?["message"] as? String
            }
            .store(in: &cancellables)
    }
}
