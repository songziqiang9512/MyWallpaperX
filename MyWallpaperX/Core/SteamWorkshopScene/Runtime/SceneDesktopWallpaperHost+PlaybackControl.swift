/// Scene 引擎的命令处理端（engine-refactor-program.md M0.1）。
/// 语义映射全部落在既有真实入口上；未接入的命令显式返回 false
/// （M0.2 静音 / M0.3 性能档 / M0.6 属性热更新），禁止静默半实现。
extension SceneDesktopWallpaperHost: PlaybackEngineControlling {
    var engineKind: PlaybackEngineKind { .scene }

    var isPlaying: Bool { isPlaybackActive }

    @discardableResult
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        switch command {
        case let .loadScene(rootURL, propertyOverrides):
            requestLaunch(
                rootURL: rootURL,
                propertyOverrides: propertyOverrides.compactMapValues {
                    SceneUserPropertyValue.parse($0)
                },
                recordID: nil
            ) { _ in }
            return true
        case .pause:
            guard launchContext != nil else { return false }
            setPlaybackPaused(true)
            return true
        case .resume:
            guard launchContext != nil else { return false }
            setPlaybackPaused(false)
            return true
        case .stop:
            // A pending launch has no active context yet; stop must still cancel it.
            stop()
            return true
        case let .setMuted(muted):
            // M0.2：静音公共权威 + Scene Sound 层 0 增益实现。
            PlaybackMuteState.shared.setMuted(muted)
            soundPlaybackRegistry?.setMuted(muted)
            return true
        case let .setPerformanceProfile(maxFPS):
            // M0.7：帧节奏与预算束热切换，下一次排帧生效。
            guard let profile = PlaybackPerformanceProfile(rawValue: maxFPS) else {
                return false
            }
            applyPerformanceProfile(profile)
            return true
        case .setProperty, .switchNext:
            // M0.6 接入；switchNext 属选中层，不走引擎。
            return false
        }
    }
}
