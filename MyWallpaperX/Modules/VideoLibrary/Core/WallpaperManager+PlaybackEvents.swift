//
//  WallpaperManager+PlaybackEvents.swift
//  MyWallpaperX
//

import Combine
import Foundation

extension WallpaperManager {
    func observePlaybackEvents(storeIn cancellables: inout Set<AnyCancellable>) {
        NotificationCenter.default.publisher(for: WallpaperEngine.playbackEndedNotification)
            .sink { [weak self] notification in
                guard self?.requestedRuntime == .video,
                      let videoPath = notification.userInfo?["videoPath"] as? String else { return }
                self?.handlePlaybackEnded(forPath: videoPath)
            }
            .store(in: &cancellables)


    }


}
