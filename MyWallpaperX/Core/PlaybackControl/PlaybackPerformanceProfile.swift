import Foundation

/// Scene 当前帧率和解码缓存仍使用同一个档。
nonisolated enum PlaybackPerformanceProfile: Int, Sendable, CaseIterable {
    case efficient = 30
    case standard = 60

    static let userDefaultsKey = "mwx.playback.performanceProfile"

    static var current: PlaybackPerformanceProfile { PlaybackQualityPreference.current.profile }

    var maxFPS: Int { rawValue }

    var sceneTextureDecodeCacheByteBudget: Int {
        switch self {
        case .standard: 1_024 * 1_024 * 1_024
        case .efficient: 512 * 1_024 * 1_024
        }
    }
}

nonisolated enum WebFrameRateMode: String, Sendable {
    case display
    case followAnimationFrameRate
}

nonisolated struct PlaybackQualityPreference: Equatable, Sendable {
    static let userDefaultsKey = "mwx.playback.quality"
    static let defaults = Self(profile: .standard, webFrameRateMode: .display)

    var profile: PlaybackPerformanceProfile
    var webFrameRateMode: WebFrameRateMode

    var webFrameRateSuggestion: Int? {
        webFrameRateMode == .followAnimationFrameRate ? profile.rawValue : nil
    }

    static var current: Self { read(from: .standard) }

    static func read(from defaults: UserDefaults) -> Self {
        if let record = defaults.dictionary(forKey: userDefaultsKey) {
            return Self(
                profile: (record["animationFramesPerSecond"] as? Int)
                    .flatMap(PlaybackPerformanceProfile.init(rawValue:)) ?? .standard,
                webFrameRateMode: (record["webFrameRateMode"] as? String)
                    .flatMap(WebFrameRateMode.init(rawValue:)) ?? .display
            )
        }
        return Self(
            profile: PlaybackPerformanceProfile(rawValue: defaults.integer(forKey: PlaybackPerformanceProfile.userDefaultsKey)) ?? .standard,
            webFrameRateMode: .display
        )
    }

    func write(to defaults: UserDefaults) {
        defaults.set([
            "animationFramesPerSecond": profile.rawValue,
            "webFrameRateMode": webFrameRateMode.rawValue,
        ], forKey: Self.userDefaultsKey)
    }
}
