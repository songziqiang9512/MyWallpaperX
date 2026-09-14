import Foundation

/// 跨引擎性能预算档（engine-refactor-program.md §4.1）：
/// 60 = standard（全量预算），30 = efficient（帧率减半 + 资源预算束）。
/// 用户可见项只有设置里的"最高帧率"；档位即预算束。持久化于
/// UserDefaults，引擎经 `.setPerformanceProfile` 命令消费。
enum PlaybackPerformanceProfile: Int, Sendable, CaseIterable {
    case efficient = 30
    case standard = 60

    static let userDefaultsKey = "mwx.playback.performanceProfile"

    static var current: PlaybackPerformanceProfile {
        PlaybackPerformanceProfile(
            rawValue: UserDefaults.standard.integer(forKey: userDefaultsKey)
        ) ?? .standard
    }

    static func save(_ profile: PlaybackPerformanceProfile) {
        UserDefaults.standard.set(profile.rawValue, forKey: userDefaultsKey)
    }

    var maxFPS: Int { rawValue }

    var sceneTextureDecodeCacheByteBudget: Int {
        switch self {
        case .standard: 1_024 * 1_024 * 1_024
        case .efficient: 512 * 1_024 * 1_024
        }
    }
}
