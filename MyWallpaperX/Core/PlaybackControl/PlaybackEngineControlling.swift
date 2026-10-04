/// 壁纸引擎类别。命令层按类别定向或广播，不感知引擎内部实现。
enum PlaybackEngineKind: String, CaseIterable, Sendable {
    case video
    case web
    case scene
}

/// 引擎命令处理端契约。依赖方向：本协议位于 Core 公共层，
/// 各引擎模块提供 conformer，UI 只对命令层发命令
/// （engine-refactor-program.md M0.1；未消费的命令返回 false，
/// 由调用方决定提示或忽略——禁止静默半实现）。
protocol PlaybackEngineControlling: AnyObject {
    var engineKind: PlaybackEngineKind { get }
    var isPlaying: Bool { get }

    /// 处理一条命令；返回是否被该引擎真实消费。
    @discardableResult
    func handle(_ command: WallpaperEngineCommand) -> Bool

    @MainActor @discardableResult
    func applyUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool

    @MainActor @discardableResult
    func reloadUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool
}

extension PlaybackEngineControlling {
    @MainActor func applyUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool { false }

    @MainActor func reloadUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) -> Bool { false }
}
