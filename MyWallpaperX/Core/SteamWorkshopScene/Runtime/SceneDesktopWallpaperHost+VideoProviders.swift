import QuartzCore

extension SceneDesktopWallpaperHost {
    func setPlaybackPaused(_ paused: Bool) {
        let hostTime = CACurrentMediaTime()
#if DEBUG
        if launchContext != nil, paused != sceneClock.isPaused {
            NSLog(
                "MWX DEBUG SCENE: phase=playback-state requested=%@ timer=%@",
                paused ? "paused" : "resumed",
                frameTimer?.isValid == true ? "active" : "inactive"
            )
        }
#endif
        if paused {
            guard !sceneClock.isPaused else { return }
            sceneClock.pause(hostTime: hostTime)
            videoTextureSourceRegistry?.pause(
                sceneTime: sceneClock.currentSceneTime(hostTime: hostTime),
                hostTime: hostTime
            )
            soundPlaybackRegistry?.pause()
            frameTimer?.invalidate()
            frameTimer = nil
            frameDriverDeadline = nil
        } else {
            guard sceneClock.isPaused else { return }
            sceneClock.resume(hostTime: hostTime)
            videoTextureSourceRegistry?.resume(
                sceneTime: sceneClock.currentSceneTime(hostTime: hostTime),
                hostTime: hostTime
            )
            soundPlaybackRegistry?.resume()
            if launchContext != nil {
                startFrameDriver()
            }
        }
    }
}
