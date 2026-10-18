//
//  WallpaperManager+PlaybackEvents.swift
//  MyWallpaperX
//

import Combine
import Foundation

extension WallpaperManager {
    func observePlaybackEvents(storeIn cancellables: inout Set<AnyCancellable>) {
        NotificationCenter.default.publisher(for: WallpaperEngine.playbackFailedNotification)
            .sink { [weak self] notification in
                self?.handleEnginePlaybackFailure(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: WallpaperEngine.playbackEndedNotification)
            .sink { [weak self] notification in
                guard self?.requestedRuntime == .video,
                      let videoPath = notification.userInfo?["videoPath"] as? String else { return }
                self?.handlePlaybackEnded(forPath: videoPath)
            }
            .store(in: &cancellables)


    }

    private func handleEnginePlaybackFailure(_ notification: Notification) {
        // Native endpoint failures settle through the transaction callback.
        // Playlist recovery may only act on an already committed video.
        guard playbackSwitch.pending == nil, activeWallpaperRuntime == .video,
              let videoPath = notification.userInfo?["videoPath"] as? String,
              currentWallpaper.map({ normalizedPath($0.path) }) == normalizedPath(videoPath) else { return }
        handlePlaybackFailure(forPath: videoPath)
    }
}
