/// 壁纸引擎命令多路分发器：持有各引擎处理端，支持定向与广播。
/// UI/设置/状态栏只与本类型交互（程序文档 M0.1）；注册点在
/// UI 控制面装配处（当前为 StatusBarController）。
final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()

    private var handlers: [PlaybackEngineKind: PlaybackEngineControlling] = [:]

    func register(_ handler: PlaybackEngineControlling) {
        handlers[handler.engineKind] = handler
    }

    func unregister(_ kind: PlaybackEngineKind) {
        handlers[kind] = nil
    }

    func handler(for kind: PlaybackEngineKind) -> PlaybackEngineControlling? {
        handlers[kind]
    }

    /// 广播到全部已注册引擎；返回各引擎是否真实消费。
    @discardableResult
    func dispatch(_ command: WallpaperEngineCommand) -> [PlaybackEngineKind: Bool] {
        var outcomes: [PlaybackEngineKind: Bool] = [:]
        for (kind, handler) in handlers {
            outcomes[kind] = handler.handle(command)
        }
        return outcomes
    }

    /// 定向到单个引擎。
    @discardableResult
    func dispatch(
        _ command: WallpaperEngineCommand, to kind: PlaybackEngineKind
    ) -> Bool {
        handler(for: kind)?.handle(command) ?? false
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
