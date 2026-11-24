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

nonisolated enum ScenePostProcessingMode: String, Sendable {
    case disabled
    case enabled
    case ultra
    case ultraDisplayHDR = "displayHDR"

    var requestsDisplayHDR: Bool { self == .ultraDisplayHDR }
    var usesHDRWorkingDomain: Bool { self == .ultra || self == .ultraDisplayHDR }
    var appliesBloom: Bool { self != .disabled }
}

nonisolated struct PlaybackQualityPreference: Equatable, Sendable {
    static let userDefaultsKey = "mwx.playback.quality"
    static let defaults = Self(profile: .standard, webFrameRateMode: .display)
    private static let legacySceneDisplayHDRKey = "sceneHDRDisplayEnabled"

    var profile: PlaybackPerformanceProfile
    var webFrameRateMode: WebFrameRateMode
    var scenePostProcessing: ScenePostProcessingMode = .ultra

    var webFrameRateSuggestion: Int? {
        webFrameRateMode == .followAnimationFrameRate ? profile.rawValue : nil
    }

    static var current: Self { read(from: .standard) }

    static func read(from defaults: UserDefaults) -> Self {
        let record = defaults.dictionary(forKey: userDefaultsKey)
        let fps = record == nil ? defaults.integer(forKey: PlaybackPerformanceProfile.userDefaultsKey)
            : record?["animationFramesPerSecond"] as? Int
        let postProcessing = (record?["scenePostProcessingMode"] as? String)
            .flatMap(ScenePostProcessingMode.init(rawValue:))
            ?? (defaults.object(forKey: legacySceneDisplayHDRKey) as? Bool == true ? .ultraDisplayHDR : .ultra)
        return Self(
            profile: fps.flatMap(PlaybackPerformanceProfile.init(rawValue:)) ?? .standard,
            webFrameRateMode: (record?["webFrameRateMode"] as? String)
                .flatMap(WebFrameRateMode.init(rawValue:)) ?? .display,
            scenePostProcessing: postProcessing
        )
    }

    func write(to defaults: UserDefaults) {
        defaults.set([
            "animationFramesPerSecond": profile.rawValue,
            "webFrameRateMode": webFrameRateMode.rawValue,
            "scenePostProcessingMode": scenePostProcessing.rawValue,
        ], forKey: Self.userDefaultsKey)
    }
}
