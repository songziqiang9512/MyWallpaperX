import Foundation

/// A SceneTexture selection stays a coarse control-plane value. The bookmark
/// lets the sandboxed child resolve the same user-selected file access; the
/// URL is the stable fallback for app-owned and Downloads content.
nonisolated struct ScenePlaybackTextureReference: Equatable, Sendable {
    let url: URL
    let bookmarkData: Data?
}

nonisolated struct ScenePlaybackLoadRequest: Equatable, Sendable {
    let rootURL: URL
    var propertyOverrides: [String: SceneUserPropertyValue]
    let userPropertyTextures: [String: ScenePlaybackTextureReference]
    let recordID: String?
}

/// 粗粒度壁纸引擎命令：UI 与控制面只发命令，不直触引擎内部。
/// 该枚举是 Scene daemon IPC 合同（engine-refactor-program.md M5.4）
/// 的应用层草案；新增命令时必须同时补齐两个引擎处理端的语义映射。
enum WallpaperEngineCommand: Equatable, Sendable {
    /// 加载 Scene 壁纸；typed 属性在 App 持久化权威与 daemon 间保真。
    case loadScene(ScenePlaybackLoadRequest)
    /// 属性热更新：不重启当前壁纸，由运行时 value-only 路径消费。
    case setProperty(
        [String: SceneUserPropertyValue],
        revision: UInt64,
        recordID: String
    )
    case cancelSceneLaunch(recordID: String)
    /// 性能预算档：60 = standard，30 = efficient。
    case setPerformanceProfile(maxFPS: Int)
    case setMuted(Bool)
    case pause
    case resume
    /// 选中层"下一张壁纸"；由当前选中权威消费，非引擎内部语义。
    case switchNext
    /// 停止当前引擎播放（不退出 App）。
    case stop
}

/// 跨引擎静音意图（M0.2）。这是静音的公共权威：引擎各自决定
/// 如何实现静音（video=音量归零/恢复；scene=Sound 层 0 增益），
/// UI 图标与设置面板只读本状态。video 音量滑杆直接归零产生的
/// 派生静音不经此处，其与命令态的同步属 M0.3 设置打通。
final class PlaybackMuteState {
    static let shared = PlaybackMuteState()

    private(set) var isMuted = false

    /// 写入静音意图；状态变化时广播，供各引擎与 UI 即时消费。
    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        NotificationCenter.default.post(
            name: .playbackMuteStateDidChange, object: nil
        )
    }
}

extension Notification.Name {
    static let playbackMuteStateDidChange = Notification.Name(
        "playbackMuteStateDidChange"
    )
}
