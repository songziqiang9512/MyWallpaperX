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
    /// 主音量百分比（0...100）。由各引擎把同一用户意图投影到自身播放层。
    case setVolume(Float)
    case setMuted(Bool)
    /// 全局系统频谱策略门。开启只允许已有作者/overlay demand 使用共享
    /// producer；不会凭空为 Web/Scene 创建消费者。
    case setSystemAudioSpectrumEnabled(Bool)
    case pause
    case resume
    /// 选中层"下一张壁纸"；由当前选中权威消费，非引擎内部语义。
    case switchNext
    /// 停止当前引擎播放（不退出 App）。
    case stop
}

/// 跨引擎静音意图（M0.2）。这是静音的公共权威：引擎各自决定
/// 如何实现静音（video=音量归零/恢复；scene=Sound 层 0 增益），
/// UI 图标、设置面板与音量滑杆 0 边界同步只读本状态/经命令写入。
final class PlaybackMuteState {
    static let shared = PlaybackMuteState()

    static let persistenceKey = "PlaybackMuteState"

    private let defaults: UserDefaults
    private(set) var isMuted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMuted = defaults.object(forKey: Self.persistenceKey) as? Bool ?? false
    }

    /// 写入静音意图；状态变化时广播，供各引擎与 UI 即时消费。
    func setMuted(_ muted: Bool) {
        let didChange = isMuted != muted
        isMuted = muted
        defaults.set(muted, forKey: Self.persistenceKey)
        guard didChange else { return }
        NotificationCenter.default.post(
            name: .playbackMuteStateDidChange, object: nil
        )
    }

    /// 为升级自旧版本 `settings.volume == 0` 的用户提供一次性迁移。
    /// 新版本之后，静音意图只由本对象持久化，不再从主音量反推。
    func migrateLegacyVolumeMuteIfNeeded(volume: Double) {
        guard defaults.object(forKey: Self.persistenceKey) == nil,
              volume.isFinite else { return }
        setMuted(volume <= 0)
    }
}

/// 跨引擎主音量公共权威。值为 0...1 的归一化增益，避免 Video/Web
/// 的百分比设置与 Scene 的 AVPlayer 音量在命令边界发生二次解释。
final class PlaybackVolumeState {
    static let shared = PlaybackVolumeState()

    private(set) var normalizedVolume: Float = 0.5

    func setNormalizedVolume(_ volume: Float) {
        let clamped = volume.isFinite ? min(max(volume, 0), 1) : normalizedVolume
        guard normalizedVolume.bitPattern != clamped.bitPattern else { return }
        normalizedVolume = clamped
    }
}

extension Notification.Name {
    static let playbackMuteStateDidChange = Notification.Name(
        "playbackMuteStateDidChange"
    )
}
