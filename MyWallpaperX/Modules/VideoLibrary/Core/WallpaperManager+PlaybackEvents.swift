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
                guard let videoPath = notification.userInfo?["videoPath"] as? String else { return }
                self?.handlePlaybackEnded(forPath: videoPath)
            }
            .store(in: &cancellables)

        // E2a-3: daemon ready 提交延后的选择真值。
        NotificationCenter.default.publisher(for: WallpaperEngine.playbackReadyNotification)
            .sink { [weak self] notification in
                guard let self,
                      let videoPath = notification.userInfo?["videoPath"] as? String,
                      let pending = self.pendingWallpaper,
                      self.normalizedPath(pending.path) == self.normalizedPath(videoPath)
                else { return }
                self.currentWallpaper = pending
                self.pendingWallpaper = nil
            }
            .store(in: &cancellables)
    }

    private func handleEnginePlaybackFailure(_ notification: Notification) {
        if notification.userInfo?["contentKind"] as? String == "web" {
            guard activeWallpaperRuntime == .web else { return }
            // E2a-4 引擎已把 retained video 表面恢复为当前输出；选择权威
            // 的真值同步回退到该视频，轮换策略对"实际在播的视频"重新成立，
            // 不再永久停摆（之前 stopAutoSwitchTimer 后无人重启 timer）。
            if let restoredVideo = WallpaperEngine.shared.currentWallpaper,
               normalizedSourcePathExists(restoredVideo.path) {
                currentWallpaper = restoredVideo
                activeWallpaperRuntime = .video
                lastWorkshopPlaybackRecordID = nil
                refreshAutoSwitchTimerIfNeeded()
            } else {
                stopAutoSwitchTimer()
            }
            isPlaying = WallpaperEngine.shared.isPlaying()
            return
        }
        guard let videoPath = notification.userInfo?["videoPath"] as? String else { return }
        // E2a-3: 失败项不提交——committed 保持旧项。回退守卫按 effective
        // 匹配（pending 仍在），回退触发后再撤销 requested 层。
        handlePlaybackFailure(forPath: videoPath)
        if let pending = pendingWallpaper,
           normalizedPath(pending.path) == normalizedPath(videoPath) {
            pendingWallpaper = nil
        }
    }
}
