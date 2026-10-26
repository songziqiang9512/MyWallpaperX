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
        case .unsupportedSchema(let version): return "个人设置版本 \(version) 高于本 App 支持范围，请保留原文件。"
        case .invalidPayload(let field): return "个人设置内容无效：\(field)"
        case .importInProgress: return "个人设置正在导入，请等待完成。"
        case .recoveryRequired(let stage): return "个人设置导入未完成（\(stage)）。恢复依据已保留，暂不能继续整理资料库。"
        case .sourceChanged: return "来源资料已在导入后发生变化，不能用旧配置覆盖，请保留恢复文件。"
        case .preferencesChanged: return "偏好已在导入后发生变化，不能用旧配置覆盖，请保留恢复文件。"
        case .indexLoading: return "资料库仍在载入，请载入完成后再导入或导出设置。"
        }
    }
}

/// Optional fields preserve local preferences when reading older profiles.
/// Hotkeys, current playback, history and window state have no representation.
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
    var idleTimeoutMinutes: Int?
    var multiDisplayEnabled: Bool?
    var videoFillMode: String?
    var syncSystemWallpaper: Bool?
    var playbackRate: Double?
    var playbackRateEnabled: Bool?
    var sortMode: String?
    var sortAscending: Bool?
    var libraryBackgroundStyle: String?
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
        idleTimeoutMinutes = settings.idleTimeoutMinutes
        multiDisplayEnabled = settings.multiDisplayEnabled
        videoFillMode = settings.videoFillMode.rawValue
        syncSystemWallpaper = settings.syncSystemWallpaper
        playbackRate = settings.playbackRate
        playbackRateEnabled = settings.playbackRateEnabled
        sortMode = settings.sortMode.rawValue
        sortAscending = settings.sortAscending
        libraryBackgroundStyle = settings.libraryBackgroundStyle.rawValue
        systemAudioSpectrumEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumStyle = settings.systemAudioSpectrumStyle.rawValue
        systemAudioSpectrumSensitivity = settings.systemAudioSpectrumSensitivity.rawValue
        systemAudioSpectrumColorHex = settings.systemAudioSpectrumColorHex
        systemAudioSpectrumOffsetX = settings.systemAudioSpectrumOffsetX
        systemAudioSpectrumOffsetY = settings.systemAudioSpectrumOffsetY
        systemAudioSpectrumBarCount = settings.systemAudioSpectrumBarCount
        systemAudioSpectrumPeakCapsEnabled = settings.systemAudioSpectrumPeakCapsEnabled
    }

    /// Recovery written before the background preference existed has no claim
    /// over that field. All older fields and explicit background values retain
    /// the original full-snapshot conflict check.
    func matchesForRecovery(_ current: Self) -> Bool {
        var comparable = current
        if libraryBackgroundStyle == nil { comparable.libraryBackgroundStyle = nil }
        return self == comparable
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
        if let idleTimeoutMinutes { result.idleTimeoutMinutes = Self.nearest([5, 10, 15, 20, 30, 60], to: idleTimeoutMinutes) }
        if let multiDisplayEnabled { result.multiDisplayEnabled = multiDisplayEnabled }
        if let videoFillMode, let value = VideoFillMode(rawValue: videoFillMode) { result.videoFillMode = value }
        if let syncSystemWallpaper { result.syncSystemWallpaper = syncSystemWallpaper }
        if let playbackRate { result.playbackRate = min(max(playbackRate, 0.25), 2) }
        if let playbackRateEnabled { result.playbackRateEnabled = playbackRateEnabled }
        if let sortMode, let value = WallpaperSortMode(rawValue: sortMode) { result.sortMode = value }
        if let sortAscending { result.sortAscending = sortAscending }
        if let libraryBackgroundStyle, let value = LibraryBackgroundStyle(rawValue: libraryBackgroundStyle) {
            result.libraryBackgroundStyle = value
        }
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

    /// Legacy dateAdded was actually Video.lastUsed order. Preserve the one
    /// pre-import reference sequence without inventing an admission/use time.
    func videoSortPatch(before: WallpaperLibraryVideoSortPreference, legacyTimeOrder: [WallpaperReference],
                        remapping: [WallpaperReference: WallpaperReference]) throws -> WallpaperLibraryVideoSortPatch? {
        var target = before
        if let imported = videoLibrarySort {
            target = imported
            if imported.mode == .legacyTime {
                guard let order = imported.legacyTimeOrder else { throw PersonalSettingsError.invalidPayload("旧时间排序缺少固定顺序") }
                var seen = Set<WallpaperReference>()
                target.legacyTimeOrder = order.map { remapping[$0] ?? $0 }.filter { seen.insert($0).inserted }
            } else { target.legacyTimeOrder = nil }
        } else {
            var mode: WallpaperLibraryVideoSortPreference.Mode?
            switch sortMode {
            case "none": mode = .sourceOrder
            case "name": mode = .name
            case "size": mode = .fileSize
            case "dateAdded": mode = .legacyTime
            default: break
            }
            guard mode != nil || sortAscending != nil else { return nil }
            if let mode {
                target.mode = mode
                target.legacyTimeOrder = mode == .legacyTime ? legacyTimeOrder : nil
            }
            if let sortAscending { target.ascending = sortAscending }
        }
        guard target.legacyTimeOrder?.contains(where: { $0.sourceID.isEmpty }) != true else {
            throw PersonalSettingsError.invalidPayload("排序引用")
        }
        return WallpaperLibraryVideoSortPatch(before: before, target: target)
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
    /// Video source metadata; omitted by legacy profiles and for still images.
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
    struct LegacyEntry: Codable, Sendable {
        let path: String
        let title: String?
        let isFavorite: Bool?
        let tags: [String]?
    }
    let schemaVersion: Int
    let exportedAt: Date
    let preferences: PersonalSettingsPreferences
    let sources: [PersonalSettingsLocalSource]
    let collections: LibraryCollectionsPersonalSettingsImport?
    let tags: [String]
    let entries: [LegacyEntry]
    let silTags: [String]
    let silEntries: [LegacyEntry]

    init(exportedAt: Date, preferences: PersonalSettingsPreferences,
         sources: [PersonalSettingsLocalSource], collections: LibraryCollectionsPersonalSettingsImport) {
        schemaVersion = 8
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.sources = sources
        var portable = collections
        portable.playlistMetadataIsExplicit = true
        portable.libraryExclusionStates = portable.libraryExclusionStates ?? []
        portable.expectedLibraryExclusions = nil
        self.collections = portable
        tags = []; entries = []; silTags = []; silEntries = []
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...8).contains(schemaVersion) else { throw PersonalSettingsError.unsupportedSchema(schemaVersion) }
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        preferences = try values.decode(PersonalSettingsPreferences.self, forKey: .preferences)
        sources = try values.decodeIfPresent([PersonalSettingsLocalSource].self, forKey: .sources) ?? []
        collections = try values.decodeIfPresent(LibraryCollectionsPersonalSettingsImport.self, forKey: .collections)
        if schemaVersion >= 6, collections == nil { throw PersonalSettingsError.invalidPayload("collections") }
        if schemaVersion >= 7, collections?.playlistMetadataIsExplicit != true || collections?.libraryExclusionStates == nil {
            throw PersonalSettingsError.invalidPayload("列表元数据或库隐藏状态")
        }
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        entries = try values.decodeIfPresent([LegacyEntry].self, forKey: .entries) ?? []
        silTags = try values.decodeIfPresent([String].self, forKey: .silTags) ?? []
        silEntries = try values.decodeIfPresent([LegacyEntry].self, forKey: .silEntries) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, preferences, sources, collections, tags, entries, silTags, silEntries
    }
}
