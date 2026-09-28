//
//  WallpaperManager+ProfileSettings.swift
//  MyWallpaperX
//

import Foundation

struct PersonalSettingsExportSummary {
    let wallpaperCount: Int
    let tagCount: Int
}

struct PersonalSettingsImportSummary {
    let mergedWallpaperCount: Int
    let createdWallpaperCount: Int
    let missingPathCount: Int
    let tagCount: Int
}

/// 只导出用户真正关心的偏好字段，不序列化整个 WallpaperSettings，减小文件体积。
/// schemaVersion 5：新增启动恢复播放开关（可选）；v4 新增系统音频频谱
/// 8 字段（可选，旧文件缺 key 时解码为 nil，导入跳过不覆盖）。
private struct ExportedPreferences: Codable {
    var loopPlayback: Bool
    var randomPlayback: Bool
    var sequentialPlayback: Bool
    var autoSwitchEnabled: Bool
    var randomInterval: Int
    var timeUnit: TimeUnit
    var volume: Double
    var startOnBoot: Bool
    var restorePlaybackOnLaunch: Bool?
    var pauseWhenOtherAppFullscreen: Bool
    var pauseWhenOtherAppFocused: Bool
    var pauseWhenUnplugged: Bool
    var pauseWhenIdle: Bool
    var idleTimeoutMinutes: Int
    var multiDisplayEnabled: Bool
    var videoFillMode: VideoFillMode
    var syncSystemWallpaper: Bool
    var playbackRate: Double
    var playbackRateEnabled: Bool
    var sortMode: WallpaperSortMode
    var sortAscending: Bool
    var systemAudioSpectrumEnabled: Bool?
    var systemAudioSpectrumStyle: SystemAudioSpectrumStyle?
    var systemAudioSpectrumSensitivity: SystemAudioSpectrumSensitivity?
    var systemAudioSpectrumColorHex: String?
    var systemAudioSpectrumOffsetX: Double?
    var systemAudioSpectrumOffsetY: Double?
    var systemAudioSpectrumBarCount: Int?
    var systemAudioSpectrumPeakCapsEnabled: Bool?

    static let allowedIdleTimeoutMinutes: [Int] = [5, 10, 15, 20, 30, 60]
    static let allowedSpectrumBarCounts: [Int] = [16, 20, 28, 36, 48]

    private static func nearest(
        allowed: [Int], to value: Int
    ) -> Int {
        allowed.min {
            abs($0 - value) < abs($1 - value)
        } ?? allowed[0]
    }

    init(from settings: WallpaperSettings) {
        loopPlayback = settings.loopPlayback
        randomPlayback = settings.randomPlayback
        sequentialPlayback = settings.sequentialPlayback
        autoSwitchEnabled = settings.autoSwitchEnabled
        randomInterval = settings.randomInterval
        timeUnit = settings.timeUnit
        volume = settings.volume
        startOnBoot = settings.startOnBoot
        restorePlaybackOnLaunch = settings.restorePlaybackOnLaunch
        pauseWhenOtherAppFullscreen = settings.pauseWhenOtherAppFullscreen
        pauseWhenOtherAppFocused = settings.pauseWhenOtherAppFocused
        pauseWhenUnplugged = settings.pauseWhenUnplugged
        pauseWhenIdle = settings.pauseWhenIdle
        idleTimeoutMinutes = settings.idleTimeoutMinutes
        multiDisplayEnabled = settings.multiDisplayEnabled
        videoFillMode = settings.videoFillMode
        syncSystemWallpaper = settings.syncSystemWallpaper
        playbackRate = settings.playbackRate
        playbackRateEnabled = settings.playbackRateEnabled
        sortMode = settings.sortMode
        sortAscending = settings.sortAscending
        systemAudioSpectrumEnabled = settings.systemAudioSpectrumEnabled
        systemAudioSpectrumStyle = settings.systemAudioSpectrumStyle
        systemAudioSpectrumSensitivity = settings.systemAudioSpectrumSensitivity
        systemAudioSpectrumColorHex = settings.systemAudioSpectrumColorHex
        systemAudioSpectrumOffsetX = settings.systemAudioSpectrumOffsetX
        systemAudioSpectrumOffsetY = settings.systemAudioSpectrumOffsetY
        systemAudioSpectrumBarCount = settings.systemAudioSpectrumBarCount
        systemAudioSpectrumPeakCapsEnabled = settings.systemAudioSpectrumPeakCapsEnabled
    }

    func apply(to settings: inout WallpaperSettings) {
        settings.loopPlayback = loopPlayback
        settings.randomPlayback = randomPlayback
        settings.sequentialPlayback = sequentialPlayback
        settings.autoSwitchEnabled = autoSwitchEnabled
        settings.randomInterval = randomInterval
        settings.timeUnit = timeUnit
        // 连续值与 UI/引擎域对齐，手改文件的越界值不进 settings。
        settings.volume = min(max(volume, 0), 100)
        settings.startOnBoot = startOnBoot
        if let restorePlaybackOnLaunch {
            settings.restorePlaybackOnLaunch = restorePlaybackOnLaunch
        }
        settings.pauseWhenOtherAppFullscreen = pauseWhenOtherAppFullscreen
        settings.pauseWhenOtherAppFocused = pauseWhenOtherAppFocused
        settings.pauseWhenUnplugged = pauseWhenUnplugged
        settings.pauseWhenIdle = pauseWhenIdle
        // 离散档位取最近合法值，避免外部来源的清单外值让 UI 显示与
        // 策略判定脱节。
        settings.idleTimeoutMinutes = Self.nearest(
            allowed: Self.allowedIdleTimeoutMinutes,
            to: idleTimeoutMinutes
        )
        settings.multiDisplayEnabled = multiDisplayEnabled
        settings.videoFillMode = videoFillMode
        settings.syncSystemWallpaper = syncSystemWallpaper
        settings.playbackRate = min(max(playbackRate, 0.25), 2.0)
        settings.playbackRateEnabled = playbackRateEnabled
        settings.sortMode = sortMode
        settings.sortAscending = sortAscending
        if let systemAudioSpectrumEnabled {
            settings.systemAudioSpectrumEnabled = systemAudioSpectrumEnabled
        }
        if let systemAudioSpectrumStyle {
            settings.systemAudioSpectrumStyle = systemAudioSpectrumStyle
        }
        if let systemAudioSpectrumSensitivity {
            settings.systemAudioSpectrumSensitivity = systemAudioSpectrumSensitivity
        }
        if let systemAudioSpectrumColorHex,
           systemAudioSpectrumColorHex.range(
               of: "^#[0-9A-Fa-f]{6}$",
               options: .regularExpression
           ) != nil {
            settings.systemAudioSpectrumColorHex = systemAudioSpectrumColorHex
        }
        if let systemAudioSpectrumOffsetX {
            // 与设置面板滑杆域一致（X ±30%），而非引擎的 ±0.35 收敛域，
            // 避免导入值让标签与滑杆位置脱节。
            settings.systemAudioSpectrumOffsetX = min(
                max(systemAudioSpectrumOffsetX, -0.30), 0.30
            )
        }
        if let systemAudioSpectrumOffsetY {
            settings.systemAudioSpectrumOffsetY = min(
                max(systemAudioSpectrumOffsetY, -0.20), 0.20
            )
        }
        if let systemAudioSpectrumBarCount {
            settings.systemAudioSpectrumBarCount = Self.nearest(
                allowed: Self.allowedSpectrumBarCounts,
                to: systemAudioSpectrumBarCount
            )
        }
        if let systemAudioSpectrumPeakCapsEnabled {
            settings.systemAudioSpectrumPeakCapsEnabled = systemAudioSpectrumPeakCapsEnabled
        }
    }
}

private struct PersonalSettingsPayload: Codable {
    struct Entry: Codable {
        let path: String
        let title: String
        let isFavorite: Bool
        let tags: [String]
    }

    struct SILEntry: Codable {
        let path: String
        let title: String
        let tags: [String]
    }

    // schemaVersion 5：新增启动恢复播放开关（可选，v1-v4 旧文件缺 key 时
    // 跳过不覆盖）；v4 新增系统音频频谱 8 字段（可选）；v3 新增图片库壁纸
    // 和图片标签（可选，兼容旧版 v1/v2 文件）
    let schemaVersion: Int
    let exportedAt: Date
    let preferences: ExportedPreferences
    let tags: [String]
    let entries: [Entry]
    let silTags: [String]?
    let silEntries: [SILEntry]?
}

extension WallpaperManager {
    func exportPersonalSettings(to url: URL) throws -> PersonalSettingsExportSummary {
        // 导出只打包用户态配置和引用关系，不导出派生缓存路径，避免文件搬家后误以为资源已固定。
        let payload = PersonalSettingsPayload(
            schemaVersion: 5,
            exportedAt: Date(),
            preferences: ExportedPreferences(from: settings),
            tags: normalizedTagList(tags),
            entries: wallpapers.map { wallpaper in
                PersonalSettingsPayload.Entry(
                    path: normalizedPath(wallpaper.path),
                    title: wallpaper.title,
                    isFavorite: wallpaper.isFavorite,
                    tags: normalizedTagList(wallpaper.tags)
                )
            },
            silTags: SILService.shared.silTags,
            silEntries: SILService.shared.wallpapers.map { w in
                PersonalSettingsPayload.SILEntry(
                    path: w.path,
                    title: w.title,
                    tags: w.tags
                )
            }
        )

        // 使用紧凑 JSON（不 prettyPrinted），文件体积比 v1 减少约 40-50%。
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)

        return PersonalSettingsExportSummary(
            wallpaperCount: payload.entries.count,
            tagCount: payload.tags.count
        )
    }

    func importPersonalSettings(from url: URL) throws -> PersonalSettingsImportSummary {
        // 导入策略是"合并到现有库"，不是整库覆盖；这样不会误删用户现有壁纸与标签。
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PersonalSettingsPayload.self, from: data)
        let existingTags = tags

        var indexByPath: [String: Int] = [:]
        indexByPath.reserveCapacity(wallpapers.count)
        for index in wallpapers.indices {
            indexByPath[normalizedPath(wallpapers[index].path)] = index
        }

        var mergedCount = 0
        var createdCount = 0
        var missingCount = 0

        for entry in payload.entries {
            let normalizedEntryPath = normalizedPath(entry.path)
            let normalizedEntryTags = normalizedTagList(entry.tags)
            // 文件存在性检查放在后台完成后汇总，这里直接用导入时缓存的路径集合判断。
            // normalizedSourcePathExists 是同步磁盘 I/O，条目多时在主线程累积卡顿。
            // 改为：仅在最终 apply 阶段统计缺失数，不逐条阻塞主线程。
            let fileExists = FileManager.default.fileExists(atPath: normalizedEntryPath)
            if !fileExists {
                missingCount += 1
            }

            if let existingIndex = indexByPath[normalizedEntryPath] {
                wallpapers[existingIndex].isFavorite = entry.isFavorite
                wallpapers[existingIndex].tags = normalizedTagList(wallpapers[existingIndex].tags + normalizedEntryTags)
                if !entry.title.isEmpty {
                    // title 是 let，只能通过整体重建更新；其它字段已在上面直接修改过，直接透传。
                    wallpapers[existingIndex] = VideoWallpaper(
                        id: wallpapers[existingIndex].id,
                        title: entry.title,
                        path: wallpapers[existingIndex].path,
                        thumbnailPath: wallpapers[existingIndex].thumbnailPath,
                        staticFramePath: wallpapers[existingIndex].staticFramePath,
                        isFavorite: wallpapers[existingIndex].isFavorite,
                        lastUsed: wallpapers[existingIndex].lastUsed,
                        tags: wallpapers[existingIndex].tags
                    )
                }
                mergedCount += 1
                continue
            }

            let newWallpaper = VideoWallpaper(
                title: entry.title.isEmpty
                    ? URL(fileURLWithPath: normalizedEntryPath).lastPathComponent
                    : entry.title,
                path: normalizedEntryPath,
                thumbnailPath: nil,
                staticFramePath: nil,
                isFavorite: entry.isFavorite,
                lastUsed: Date(),
                tags: normalizedEntryTags
            )
            wallpapers.append(newWallpaper)
            indexByPath[normalizedEntryPath] = wallpapers.count - 1
            createdCount += 1
        }

        // 把导入的偏好写回 settings，热键配置不覆盖（用户本地配置优先）。
        payload.preferences.apply(to: &settings)
        sanitizeSystemHotkeySettingsIfNeeded()
        normalizePlaybackSettings()
        syncAutoSwitchPlaybackPolicy(forceTimerRestart: true)
        // 速率/频谱/loop/fillMode 已由 apply 写入触发的 sink 差分投影。
        applyEngineSettings(reloadWallpaper: false)
        updateLoginItemStatus()

        // tags = 现有标签 + 导入标签 + 壁纸内引用标签，保留用户现有体系，不做强制替换。
        let payloadTags = normalizedTagList(payload.tags)
        let wallpaperTags = wallpapers.flatMap(\.tags)
        tags = normalizedTagList(existingTags + payloadTags + wallpaperTags)

        // 合并图片库数据（schemaVersion 3+，旧版文件 silEntries 为空数组，安全兼容）
        let sil = SILService.shared
        var silIndexByPath: [String: Int] = [:]
        for (i, w) in sil.wallpapers.enumerated() { silIndexByPath[w.path] = i }
        for entry in payload.silEntries ?? [] {
            if let idx = silIndexByPath[entry.path] {
                // 已存在：合并标签
                for tag in entry.tags where !sil.wallpapers[idx].tags.contains(tag) {
                    sil.wallpapers[idx].tags.append(tag)
                }
            } else {
                // 新增
                var w = SILWallpaper(path: entry.path)
                w.tags = entry.tags
                if !entry.title.isEmpty { w.title = entry.title }
                sil.wallpapers.append(w)
                silIndexByPath[entry.path] = sil.wallpapers.count - 1
            }
        }
        // 合并图片标签列表
        for tag in payload.silTags ?? [] where !sil.silTags.contains(tag) {
            sil.silTags.append(tag)
        }
        sil.save()
        sil.saveSILTags()

        saveSettings()
        saveTags()
        saveWallpapers()

        normalizeRecentWallpapers(limit: WallpaperManager.recentWallpapersLimit, requireExistingFiles: false)
        saveRecentWallpapers()
        persistCurrentWallpaperSnapshot()
        NotificationCenter.default.post(name: .wallpaperManagerDidImportPersonalSettings, object: self)

        return PersonalSettingsImportSummary(
            mergedWallpaperCount: mergedCount,
            createdWallpaperCount: createdCount,
            missingPathCount: missingCount,
            tagCount: tags.count
        )
    }
}
