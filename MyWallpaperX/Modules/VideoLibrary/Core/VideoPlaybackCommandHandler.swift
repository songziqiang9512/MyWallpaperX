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
            // E2a-2: stop 回收选择权威真值（引用/定时器/播放态/纪元），
            // 不再裸停引擎——stopped 状态归 Manager 单点归属。
            WallpaperManager.shared.stopCurrentPlayback()
            return true
        case let .setVolume(volume):
            let sanitized = volume.isFinite
                ? min(max(volume, 0), 100)
                : PlaybackVolumeState.shared.normalizedVolume * 100
            let normalized = sanitized / 100
            PlaybackVolumeState.shared.setNormalizedVolume(normalized)
            WallpaperEngine.shared.setVolume(sanitized)
            return true
        case let .setMuted(muted):
            PlaybackMuteState.shared.setMuted(muted)
            WallpaperManager.shared.setMuted(muted)
            return true
        case let .setSystemAudioSpectrumEnabled(enabled):
            WallpaperEngine.shared.setSystemAudioSpectrumEnabled(enabled)
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
