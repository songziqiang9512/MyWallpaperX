import Foundation

nonisolated struct PersonalSettingsExportSummary: Sendable {
    let wallpaperCount: Int
    let tagCount: Int
}

nonisolated struct PersonalSettingsImportSummary: Codable, Equatable, Sendable {
    let mergedWallpaperCount: Int
    let createdWallpaperCount: Int
    let missingPathCount: Int
    let tagCount: Int
}

nonisolated enum PersonalSettingsError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidPayload(String)
    case importInProgress
    case recoveryRequired(String)
    case sourceChanged
    case preferencesChanged
    case indexLoading

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "个人设置版本 \(version) 不受支持，请使用当前版本导出的文件。"
        case .invalidPayload(let field): return "个人设置内容无效：\(field)"
        case .importInProgress: return "个人设置正在导入，请等待完成。"
        case .recoveryRequired(let stage): return "个人设置导入未完成（\(stage)）。恢复依据已保留，暂不能继续整理资料库。"
        case .sourceChanged: return "来源资料已在导入后发生变化，不能用旧配置覆盖，请保留恢复文件。"
        case .preferencesChanged: return "偏好已在导入后发生变化，不能用旧配置覆盖，请保留恢复文件。"
        case .indexLoading: return "资料库仍在载入，请载入完成后再导入或导出设置。"
        }
    }
}

/// Optional fields describe explicitly selected preferences in the current format.
/// Current playback, history, credentials and window state are not preferences.
nonisolated struct PersonalSettingsPreferences: Codable, Equatable, Sendable {
    var loopPlayback: Bool?
    var randomPlayback: Bool?
    var sequentialPlayback: Bool?
    var autoSwitchEnabled: Bool?
    var randomInterval: Int?
    var timeUnit: String?
    var volume: Double?
    var startOnBoot: Bool?
    var restorePlaybackOnLaunch: Bool?
    var pauseWhenOtherAppFullscreen: Bool?
    var pauseWhenOtherAppFocused: Bool?
    var pauseWhenUnplugged: Bool?
    var pauseWhenIdle: Bool?
    var systemHotkeysEnabled: Bool?
    var previousWallpaperHotkey: String?
    var nextWallpaperHotkey: String?
    var togglePlaybackHotkey: String?
    var toggleMuteHotkey: String?
    var sceneHDRDisplayEnabled: Bool?
    var sceneMediaInfoEnabled: Bool?
    var playbackPerformanceProfile: Int?
    var idleTimeoutMinutes: Int?
    var multiDisplayEnabled: Bool?
    var videoFillMode: String?
    var syncSystemWallpaper: Bool?
    var playbackRate: Double?
    var playbackRateEnabled: Bool?
    var libraryBackgroundStyle: String?
    var libraryCardClickAction: String?
    var screenSaver: ScreenSaverPreferences?
    var videoLibrarySort: WallpaperLibraryVideoSortPreference?
    var systemAudioSpectrumEnabled: Bool?
    var systemAudioSpectrumStyle: String?
    var systemAudioSpectrumSensitivity: String?
    var systemAudioSpectrumColorHex: String?
    var systemAudioSpectrumOffsetX: Double?
    var systemAudioSpectrumOffsetY: Double?
    var systemAudioSpectrumBarCount: Int?
    var systemAudioSpectrumPeakCapsEnabled: Bool?

    @MainActor init(from settings: WallpaperSettings) {
        loopPlayback = settings.loopPlayback
        randomPlayback = settings.randomPlayback
        sequentialPlayback = settings.sequentialPlayback
        autoSwitchEnabled = settings.autoSwitchEnabled
        randomInterval = settings.randomInterval
        timeUnit = settings.timeUnit.rawValue
        volume = settings.volume
        startOnBoot = settings.startOnBoot
        restorePlaybackOnLaunch = settings.restorePlaybackOnLaunch
        pauseWhenOtherAppFullscreen = settings.pauseWhenOtherAppFullscreen
        pauseWhenOtherAppFocused = settings.pauseWhenOtherAppFocused
        pauseWhenUnplugged = settings.pauseWhenUnplugged
        pauseWhenIdle = settings.pauseWhenIdle
        systemHotkeysEnabled = settings.systemHotkeysEnabled
        previousWallpaperHotkey = settings.previousWallpaperHotkey.rawValue
        nextWallpaperHotkey = settings.nextWallpaperHotkey.rawValue
        togglePlaybackHotkey = settings.togglePlaybackHotkey.rawValue
        toggleMuteHotkey = settings.toggleMuteHotkey.rawValue
        idleTimeoutMinutes = settings.idleTimeoutMinutes
        multiDisplayEnabled = settings.multiDisplayEnabled
        videoFillMode = settings.videoFillMode.rawValue
        syncSystemWallpaper = settings.syncSystemWallpaper
        playbackRate = settings.playbackRate
        playbackRateEnabled = settings.playbackRateEnabled
        libraryBackgroundStyle = settings.libraryBackgroundStyle.rawValue
        libraryCardClickAction = settings.libraryCardClickAction.rawValue
        screenSaver = settings.screenSaver
        systemAudioSpectrumEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumStyle = settings.systemAudioSpectrumStyle.rawValue
        systemAudioSpectrumSensitivity = settings.systemAudioSpectrumSensitivity.rawValue
        systemAudioSpectrumColorHex = settings.systemAudioSpectrumColorHex
        systemAudioSpectrumOffsetX = settings.systemAudioSpectrumOffsetX
        systemAudioSpectrumOffsetY = settings.systemAudioSpectrumOffsetY
        systemAudioSpectrumBarCount = settings.systemAudioSpectrumBarCount
        systemAudioSpectrumPeakCapsEnabled = settings.systemAudioSpectrumPeakCapsEnabled
    }

    @MainActor func applying(to current: WallpaperSettings) -> WallpaperSettings {
        var result = current
        if let loopPlayback { result.loopPlayback = loopPlayback }
        if let randomPlayback { result.randomPlayback = randomPlayback }
        if let sequentialPlayback { result.sequentialPlayback = sequentialPlayback }
        if let autoSwitchEnabled { result.autoSwitchEnabled = autoSwitchEnabled }
        if let randomInterval { result.randomInterval = max(randomInterval, 1) }
        if let timeUnit, let value = TimeUnit(rawValue: timeUnit) { result.timeUnit = value }
        if let volume { result.volume = min(max(volume, 0), 100) }
        if let startOnBoot { result.startOnBoot = startOnBoot }
        if let restorePlaybackOnLaunch { result.restorePlaybackOnLaunch = restorePlaybackOnLaunch }
        if let pauseWhenOtherAppFullscreen { result.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen }
        if let pauseWhenOtherAppFocused { result.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused }
        if let pauseWhenUnplugged { result.pauseWhenUnplugged = pauseWhenUnplugged }
        if let pauseWhenIdle { result.pauseWhenIdle = pauseWhenIdle }
        if let systemHotkeysEnabled { result.systemHotkeysEnabled = systemHotkeysEnabled }
        if let previousWallpaperHotkey, let key = FunctionKeyShortcut(rawValue: previousWallpaperHotkey) { result.previousWallpaperHotkey = key }
        if let nextWallpaperHotkey, let key = FunctionKeyShortcut(rawValue: nextWallpaperHotkey) { result.nextWallpaperHotkey = key }
        if let togglePlaybackHotkey, let key = FunctionKeyShortcut(rawValue: togglePlaybackHotkey) { result.togglePlaybackHotkey = key }
        if let toggleMuteHotkey, let key = FunctionKeyShortcut(rawValue: toggleMuteHotkey) { result.toggleMuteHotkey = key }
        let hotkeys = WallpaperSettings.normalizedHotkeyBindings(
            previous: result.previousWallpaperHotkey, next: result.nextWallpaperHotkey,
            playPause: result.togglePlaybackHotkey, muteToggle: result.toggleMuteHotkey)
        (result.previousWallpaperHotkey, result.nextWallpaperHotkey,
         result.togglePlaybackHotkey, result.toggleMuteHotkey) = hotkeys
        if let idleTimeoutMinutes { result.idleTimeoutMinutes = Self.nearest([5, 10, 15, 20, 30, 60], to: idleTimeoutMinutes) }
        if let multiDisplayEnabled { result.multiDisplayEnabled = multiDisplayEnabled }
        if let videoFillMode, let value = VideoFillMode(rawValue: videoFillMode) { result.videoFillMode = value }
        if let syncSystemWallpaper { result.syncSystemWallpaper = syncSystemWallpaper }
        if let playbackRate { result.playbackRate = min(max(playbackRate, 0.25), 2) }
        if let playbackRateEnabled { result.playbackRateEnabled = playbackRateEnabled }
        if let libraryBackgroundStyle, let value = LibraryBackgroundStyle(rawValue: libraryBackgroundStyle) {
            result.libraryBackgroundStyle = value
        }
        if let libraryCardClickAction, let value = LibraryCardClickAction(rawValue: libraryCardClickAction) {
            result.libraryCardClickAction = value
        }
        if let screenSaver { result.screenSaver = screenSaver }
        if let systemAudioSpectrumEnabled { result.systemAudioSpectrumEnabled = systemAudioSpectrumEnabled }
        if let systemAudioSpectrumStyle, let value = SystemAudioSpectrumStyle(rawValue: systemAudioSpectrumStyle) { result.systemAudioSpectrumStyle = value }
        if let systemAudioSpectrumSensitivity, let value = SystemAudioSpectrumSensitivity(rawValue: systemAudioSpectrumSensitivity) { result.systemAudioSpectrumSensitivity = value }
        if let systemAudioSpectrumColorHex,
           systemAudioSpectrumColorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil {
            result.systemAudioSpectrumColorHex = systemAudioSpectrumColorHex
        }
        if let systemAudioSpectrumOffsetX { result.systemAudioSpectrumOffsetX = min(max(systemAudioSpectrumOffsetX, -0.30), 0.30) }
        if let systemAudioSpectrumOffsetY { result.systemAudioSpectrumOffsetY = min(max(systemAudioSpectrumOffsetY, -0.20), 0.20) }
        if let systemAudioSpectrumBarCount { result.systemAudioSpectrumBarCount = Self.nearest([16, 20, 28, 36, 48], to: systemAudioSpectrumBarCount) }
        if let systemAudioSpectrumPeakCapsEnabled { result.systemAudioSpectrumPeakCapsEnabled = systemAudioSpectrumPeakCapsEnabled }
        // Preserve the existing import mode precedence without starting playback.
        if result.randomPlayback {
            result.loopPlayback = false; result.sequentialPlayback = false
        } else if result.sequentialPlayback {
            result.loopPlayback = false
        } else {
            result.loopPlayback = true; result.autoSwitchEnabled = false
        }
        return result
    }

    func videoSortPatch(before: WallpaperLibraryVideoSortPreference) -> WallpaperLibraryVideoSortPatch? {
        videoLibrarySort.map { WallpaperLibraryVideoSortPatch(before: before, target: $0) }
    }

    private static func nearest(_ allowed: [Int], to value: Int) -> Int {
        guard let lower = allowed.min(), let upper = allowed.max() else { return value }
        let bounded = min(max(value, lower), upper)
        return allowed.min { abs($0 - bounded) < abs($1 - bounded) } ?? lower
    }
}

/// A declared local source record is recovery metadata, never an instruction to
/// download, decode media or manufacture an alias from a matching filename.
nonisolated struct PersonalSettingsLocalSource: Codable, Equatable, Sendable {
    let reference: WallpaperReference
    let path: String
    let title: String
    /// Video source metadata; unknown values and still images omit it.
    let firstIndexedAt: Date?

    init(reference: WallpaperReference, path: String, title: String, firstIndexedAt: Date? = nil) {
        self.reference = reference
        self.path = path
        self.title = title
        self.firstIndexedAt = firstIndexedAt
    }

    private enum CodingKeys: String, CodingKey { case reference, path, title, firstIndexedAtReferenceDate }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reference = try values.decode(WallpaperReference.self, forKey: .reference)
        path = try values.decode(String.self, forKey: .path)
        title = try values.decode(String.self, forKey: .title)
        firstIndexedAt = try values.decodeIfPresent(Double.self, forKey: .firstIndexedAtReferenceDate).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(reference, forKey: .reference)
        try values.encode(path, forKey: .path)
        try values.encode(title, forKey: .title)
        // Date stores a reference-date Double. Preserve those exact bits across
        // an interrupted import; adding the Unix epoch offset can lose one ULP
        // and make an unchanged source fail its recovery precondition.
        try values.encodeIfPresent(firstIndexedAt?.timeIntervalSinceReferenceDate, forKey: .firstIndexedAtReferenceDate)
    }
}

nonisolated struct PersonalSettingsSourcePatch: Codable, Equatable, Sendable {
    let before: PersonalSettingsLocalSource?
    let target: PersonalSettingsLocalSource
}

nonisolated struct PersonalSettingsPayload: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let preferences: PersonalSettingsPreferences
    let sources: [PersonalSettingsLocalSource]
    let collections: LibraryCollectionsPersonalSettingsImport

    init(exportedAt: Date, preferences: PersonalSettingsPreferences,
         sources: [PersonalSettingsLocalSource], collections: LibraryCollectionsPersonalSettingsImport) {
        schemaVersion = 8
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.sources = sources
        var portable = collections
        portable.expectedLibraryExclusions = nil
        self.collections = portable
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 8 else { throw PersonalSettingsError.unsupportedSchema(schemaVersion) }
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        preferences = try values.decode(PersonalSettingsPreferences.self, forKey: .preferences)
        sources = try values.decode([PersonalSettingsLocalSource].self, forKey: .sources)
        collections = try values.decode(LibraryCollectionsPersonalSettingsImport.self, forKey: .collections)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, preferences, sources, collections
    }
}
