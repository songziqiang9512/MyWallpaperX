import Foundation

nonisolated struct AnimationFrameRate: RawRepresentable, Equatable, Sendable {
    static let minimum = 10
    static let maximum = 120
    static let standard = Self(rawValue: 60)!

    let rawValue: Int

    init?(rawValue: Int) {
        guard (Self.minimum...Self.maximum).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    static func legacyValue(_ rawValue: Int?) -> Int? {
        rawValue == 30 || rawValue == 60 ? rawValue : nil
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

nonisolated enum SceneShadowQuality: String, Sendable {
    case disabled
    case low
    case medium
    case high
    case adaptive = "ultra"
}

nonisolated enum SceneVolumeLightingQuality: String, Sendable {
    case disabled
    case enabled
}

nonisolated enum SceneReflectionQuality: String, Sendable {
    case disabled
    case enabled
}

nonisolated enum SceneTextureQuality: String, Sendable {
    case full = "quality"
    case performance

    var ordinaryColorMipLongEdge: Int? { self == .performance ? 2_048 : nil }
}

nonisolated enum SceneAntiAliasingMode: String, CaseIterable, Sendable {
    case none
    case msaa2
    case msaa4

    var sampleCount: Int {
        switch self {
        case .none: 1
        case .msaa2: 2
        case .msaa4: 4
        }
    }
}

nonisolated struct SceneRenderQuality: Equatable, Sendable {
    var postProcessing: ScenePostProcessingMode = .ultra
    var shadows: SceneShadowQuality = .adaptive
    var volumeLighting: SceneVolumeLightingQuality = .enabled
    var reflections: SceneReflectionQuality = .enabled
    var textures: SceneTextureQuality = .full
    var antiAliasing: SceneAntiAliasingMode = .none
}

nonisolated enum SceneQualityPreset: String, CaseIterable, Sendable {
    case low
    case medium
    case high
    case ultra

    func apply(to preference: inout PlaybackQualityPreference) {
        let settings = projection
        preference.animationFrameRate = settings.animationFrameRate
        preference.scene = settings.scene
    }

    static func matching(_ preference: PlaybackQualityPreference) -> Self? {
        allCases.first { preset in
            let settings = preset.projection
            return settings.animationFrameRate == preference.animationFrameRate && settings.scene == preference.scene
        }
    }

    private var projection: (animationFrameRate: AnimationFrameRate, scene: SceneRenderQuality) {
        let (fps, postProcessing, shadows, reflections, antiAliasing): (
            Int, ScenePostProcessingMode, SceneShadowQuality, SceneReflectionQuality, SceneAntiAliasingMode
        ) = switch self {
        case .low: (10, .disabled, .low, .disabled, .none)
        case .medium: (15, .enabled, .medium, .enabled, .none)
        case .high: (25, .enabled, .high, .enabled, .msaa2)
        case .ultra: (30, .ultra, .adaptive, .enabled, .msaa2)
        }
        return (AnimationFrameRate(rawValue: fps)!, .init(postProcessing: postProcessing, shadows: shadows,
            volumeLighting: .enabled, reflections: reflections, textures: .full, antiAliasing: antiAliasing))
    }
}

nonisolated struct PlaybackQualityPreference: Equatable, Sendable {
    static let userDefaultsKey = "mwx.playback.quality"
    static let defaults = Self(animationFrameRate: .standard, webFrameRateMode: .display)
    static let legacyFrameRateKey = "mwx.playback.performanceProfile"
    private static let legacySceneDisplayHDRKey = "sceneHDRDisplayEnabled"

    var animationFrameRate: AnimationFrameRate
    var webFrameRateMode: WebFrameRateMode
    var scene: SceneRenderQuality = .init()
    var keepsLegacySceneDecodeLimit = false

    var webFrameRateSuggestion: Int? {
        webFrameRateMode == .followAnimationFrameRate ? animationFrameRate.rawValue : nil
    }

    static var current: Self { read(from: .standard) }

    static func read(from defaults: UserDefaults) -> Self {
        let record = defaults.dictionary(forKey: userDefaultsKey)
        let fps = record == nil
            ? AnimationFrameRate.legacyValue(defaults.integer(forKey: legacyFrameRateKey))
            : record?["animationFramesPerSecond"] as? Int
        let postProcessing = (record?["scenePostProcessingMode"] as? String)
            .flatMap(ScenePostProcessingMode.init(rawValue:))
            ?? (defaults.object(forKey: legacySceneDisplayHDRKey) as? Bool == true ? .ultraDisplayHDR : .ultra)
        return Self(
            animationFrameRate: fps.flatMap(AnimationFrameRate.init(rawValue:)) ?? .standard,
            webFrameRateMode: (record?["webFrameRateMode"] as? String)
                .flatMap(WebFrameRateMode.init(rawValue:)) ?? .display,
            scene: .init(
                postProcessing: postProcessing,
                shadows: (record?["sceneShadowQuality"] as? String)
                    .flatMap(SceneShadowQuality.init(rawValue:)) ?? .adaptive,
                volumeLighting: (record?["scenePointVolumeQuality"] as? String)
                    .flatMap(SceneVolumeLightingQuality.init(rawValue:)) ?? .enabled,
                reflections: (record?["sceneReflectionQuality"] as? String)
                    .flatMap(SceneReflectionQuality.init(rawValue:)) ?? .enabled,
                textures: (record?["sceneTextureQuality"] as? String)
                    .flatMap(SceneTextureQuality.init(rawValue:)) ?? .full,
                antiAliasing: (record?["sceneAntiAliasingMode"] as? String)
                    .flatMap(SceneAntiAliasingMode.init(rawValue:)) ?? .none
            ),
            keepsLegacySceneDecodeLimit: (record?["keepsLegacySceneDecodeLimit"] as? Bool) ?? (fps == 30)
        )
    }

    func write(to defaults: UserDefaults) {
        defaults.set([
            "animationFramesPerSecond": animationFrameRate.rawValue,
            "keepsLegacySceneDecodeLimit": keepsLegacySceneDecodeLimit,
            "webFrameRateMode": webFrameRateMode.rawValue,
            "scenePostProcessingMode": scene.postProcessing.rawValue,
            "sceneShadowQuality": scene.shadows.rawValue,
            "scenePointVolumeQuality": scene.volumeLighting.rawValue,
            "sceneReflectionQuality": scene.reflections.rawValue,
            "sceneTextureQuality": scene.textures.rawValue,
            "sceneAntiAliasingMode": scene.antiAliasing.rawValue,
        ], forKey: Self.userDefaultsKey)
    }
}
