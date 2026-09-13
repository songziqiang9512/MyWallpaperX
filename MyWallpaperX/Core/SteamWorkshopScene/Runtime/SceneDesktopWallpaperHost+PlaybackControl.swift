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
            guard launchContext != nil else { return false }
            stop()
            return true
        case .setMuted, .setPerformanceProfile, .setProperty, .switchNext:
            // M0.2 / M0.3 / M0.6 接入；switchNext 属选中层，不走引擎。
            return false
        }
    }
}
