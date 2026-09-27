/// 壁纸引擎命令多路分发器：持有各引擎处理端，支持定向与广播。
/// UI/设置/状态栏只与本类型交互（程序文档 M0.1）；注册点在
/// App 装配（MyWallpaperXApplication）。
final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()

    private(set) var isUserPaused = false
    private(set) var isSystemPaused = false
    var isPlaybackPaused: Bool { isUserPaused || isSystemPaused }

    func setSystemPaused(_ paused: Bool) {
        let previous = isPlaybackPaused
        isSystemPaused = paused
        if previous != isPlaybackPaused { dispatch(.setPlaybackPaused(isPlaybackPaused)) }
    }

    private var handlers: [PlaybackEngineKind: PlaybackEngineControlling] = [:]

    func register(_ handler: PlaybackEngineControlling) {
        register(handler, as: handler.engineKind)
    }

    /// E2c: 同一 handler 可另名注册到别的 kind——web 与 video 共享
    /// WallpaperEngine 执行端（引擎方法按 currentPlaybackContentKind
    /// 内部路由），定向 `to: .web` 因此可达。
    func register(_ handler: PlaybackEngineControlling, as kind: PlaybackEngineKind) {
        handlers[kind] = handler
        _ = handler.handle(.setPlaybackPaused(isPlaybackPaused))
    }

    func unregister(_ kind: PlaybackEngineKind) {
        handlers[kind] = nil
    }

    func handler(for kind: PlaybackEngineKind) -> PlaybackEngineControlling? {
        handlers[kind]
    }

    /// 广播到全部已注册引擎；返回各引擎是否真实消费。同一 handler
    /// 实例以多 kind 注册时只执行一次（引擎内部按活跃 kind 路由，
    /// 重复执行会双倍生效）。
    @discardableResult
    func dispatch(_ command: WallpaperEngineCommand) -> [PlaybackEngineKind: Bool] {
        let effective: WallpaperEngineCommand
        switch command {
        case .pause, .resume:
            isUserPaused = command == .pause
            effective = .setPlaybackPaused(isPlaybackPaused)
        default:
            effective = command
        }
        var outcomes: [PlaybackEngineKind: Bool] = [:]
        var executed: [ObjectIdentifier: Bool] = [:]
        for (kind, handler) in handlers {
            let identity = ObjectIdentifier(handler)
            let result = executed[identity] ?? handler.handle(effective)
            executed[identity] = result
            outcomes[kind] = result
        }
        return outcomes
    }

    /// 定向到单个引擎。
    @discardableResult
    func dispatch(
        _ command: WallpaperEngineCommand, to kind: PlaybackEngineKind
    ) -> Bool {
        // Pause/resume is a global user intent even when initiated by one engine's UI.
        if command == .pause || command == .resume { return dispatch(command)[kind] ?? false }
        return handler(for: kind)?.handle(command) ?? false
    }

    /// 是否存在任一引擎报告"正在播放"。用于全局播放/暂停切换的
    /// 状态判定；引擎未注册或未消费时按未播放处理。
    var isAnyEnginePlaying: Bool {
        handlers.values.contains { $0.isPlaying }
    }
}

extension PlaybackEngineControlling {
    /// 引擎可选实现：默认未播放。播放态判定供全局切换使用。
    var isPlaying: Bool { false }
}
