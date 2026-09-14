/// video 引擎的命令处理端（engine-refactor-program.md M0.1）。
/// 播放控制走 WallpaperEngine，静音与"下一张"走 WallpaperManager
/// （当前选中权威）；Scene 专属命令显式不消费。
final class VideoPlaybackCommandHandler: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind = .video

    var isPlaying: Bool { WallpaperEngine.shared.isPlaying() }

    @discardableResult
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        switch command {
        case .pause:
            WallpaperEngine.shared.pauseAllPlayers()
            return true
        case .resume:
            WallpaperEngine.shared.resumeAllPlayers()
            return true
        case .stop:
            WallpaperEngine.shared.stopPlayback()
            return true
        case let .setMuted(muted):
            PlaybackMuteState.shared.setMuted(muted)
            WallpaperManager.shared.setMuted(muted)
            return true
        case .switchNext:
            WallpaperManager.shared.navigateWallpaperManually(
                .next, userInitiated: true
            )
            return true
        case .loadScene, .setProperty, .cancelSceneLaunch,
             .setPerformanceProfile:
            return false
        }
    }
}
