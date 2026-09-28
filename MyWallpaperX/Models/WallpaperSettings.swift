//
//  WallpaperSettings.swift
//  MyWallpaperX
//
//  设置面板持久化的全部字段与其词汇类型（时间单位/填充模式/排序/
//  频谱风格/灵敏度/排序状态）。
//
//  Models/ 是全 App 的底层共享值类型层：WallpaperSettings 同时被
//  Core（策略控制器）、Modules（管理器/库）与 Shared（设置面板）
//  下行引用，自身不依赖任何产品层——新增跨层值类型放本目录，不放
//  进 Core/Modules（会制造上行依赖）。
//

import Foundation

public struct WallpaperSettings: Codable, Equatable {
    var loopPlayback: Bool = true
    var randomPlayback: Bool = false
    var sequentialPlayback: Bool = false // 顺序播放
    var autoSwitchEnabled: Bool = false // 自动切换间隔
    var randomInterval: Int = 30 // 切换间隔
    var timeUnit: TimeUnit = .seconds // 时间单位
    var volume: Double = 50.0
    var startOnBoot: Bool = false
    var restorePlaybackOnLaunch: Bool = true // 启动时恢复上次播放的壁纸（video/web/scene；静态图由系统层自保留）
    var pauseWhenOtherAppFullscreen: Bool = true // 其他应用全屏时暂停
    var idleTimeoutMinutes: Int = 10 // 不活跃超时时间（分钟）
    var pauseWhenOtherAppFocused: Bool = false // 其他应用焦点时暂停（默认关：对齐官方 Wallpaper Engine"仅全屏暂停"的默认语义）
    var multiDisplayEnabled: Bool = true // 多屏适配
    var videoFillMode: VideoFillMode = .aspectFill // 视频填充模式
    var syncSystemWallpaper: Bool = false // 同步改变系统壁纸
    var pauseWhenUnplugged: Bool = false // 未连接电源时暂停播放
    var pauseWhenIdle: Bool = false // 电脑不活跃时暂停播放
    var systemHotkeysEnabled: Bool = false // 响应系统快捷键
    var previousWallpaperHotkey: FunctionKeyShortcut = .none
    var nextWallpaperHotkey: FunctionKeyShortcut = .none
    var togglePlaybackHotkey: FunctionKeyShortcut = .none
    var toggleMuteHotkey: FunctionKeyShortcut = .none
    var playbackRate: Double = 1.0 // 播放速率（0.5 慢速 / 1.0 正常 / 3.0 快速）
    var playbackRateEnabled: Bool = false // 是否启用播放速率控制
    var systemAudioSpectrumEnabled: Bool = false // 是否显示系统音频频谱（实验功能）
    var systemAudioSpectrumStyle: SystemAudioSpectrumStyle = .balanced
    var systemAudioSpectrumSensitivity: SystemAudioSpectrumSensitivity = .normal
    var systemAudioSpectrumColorHex: String = "#F4FBFF"
    var systemAudioSpectrumOffsetX: Double = 0.0
    var systemAudioSpectrumOffsetY: Double = 0.0
    var systemAudioSpectrumBarCount: Int = 28
    var systemAudioSpectrumPeakCapsEnabled: Bool = true
    var sortMode: WallpaperSortMode = .none // 壁纸排序方式
    var sortAscending: Bool = true // 排序方向：true=升序，false=降序

    init() {}

    /// 全字段默认值单点（重置/缺 key 回退共用）。
    static let defaults = WallpaperSettings()

    /// 升级兼容解码：每个字段缺 key 时回退字段默认值，新增设置字段
    /// 不再使旧持久化整体解码失败（那会让升级用户一次性丢掉全部设置）。
    /// 历史遗留别名 key 仍然废弃：旧别名在此解码为默认值，不做错乱映射。
    public init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loopPlayback = try container.decodeIfPresent(Bool.self, forKey: .loopPlayback) ?? defaults.loopPlayback
        randomPlayback = try container.decodeIfPresent(Bool.self, forKey: .randomPlayback) ?? defaults.randomPlayback
        sequentialPlayback = try container.decodeIfPresent(Bool.self, forKey: .sequentialPlayback) ?? defaults.sequentialPlayback
        autoSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSwitchEnabled) ?? defaults.autoSwitchEnabled
        randomInterval = try container.decodeIfPresent(Int.self, forKey: .randomInterval) ?? defaults.randomInterval
        timeUnit = try container.decodeIfPresent(TimeUnit.self, forKey: .timeUnit) ?? defaults.timeUnit
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? defaults.volume
        startOnBoot = try container.decodeIfPresent(Bool.self, forKey: .startOnBoot) ?? defaults.startOnBoot
        restorePlaybackOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .restorePlaybackOnLaunch) ?? defaults.restorePlaybackOnLaunch
        pauseWhenOtherAppFullscreen = try container.decodeIfPresent(Bool.self, forKey: .pauseWhenOtherAppFullscreen) ?? defaults.pauseWhenOtherAppFullscreen
        idleTimeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .idleTimeoutMinutes) ?? defaults.idleTimeoutMinutes
        pauseWhenOtherAppFocused = try container.decodeIfPresent(Bool.self, forKey: .pauseWhenOtherAppFocused) ?? defaults.pauseWhenOtherAppFocused
        multiDisplayEnabled = try container.decodeIfPresent(Bool.self, forKey: .multiDisplayEnabled) ?? defaults.multiDisplayEnabled
        videoFillMode = try container.decodeIfPresent(VideoFillMode.self, forKey: .videoFillMode) ?? defaults.videoFillMode
        syncSystemWallpaper = try container.decodeIfPresent(Bool.self, forKey: .syncSystemWallpaper) ?? defaults.syncSystemWallpaper
        pauseWhenUnplugged = try container.decodeIfPresent(Bool.self, forKey: .pauseWhenUnplugged) ?? defaults.pauseWhenUnplugged
        pauseWhenIdle = try container.decodeIfPresent(Bool.self, forKey: .pauseWhenIdle) ?? defaults.pauseWhenIdle
        systemHotkeysEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemHotkeysEnabled) ?? defaults.systemHotkeysEnabled
        previousWallpaperHotkey = try container.decodeIfPresent(FunctionKeyShortcut.self, forKey: .previousWallpaperHotkey) ?? defaults.previousWallpaperHotkey
        nextWallpaperHotkey = try container.decodeIfPresent(FunctionKeyShortcut.self, forKey: .nextWallpaperHotkey) ?? defaults.nextWallpaperHotkey
        togglePlaybackHotkey = try container.decodeIfPresent(FunctionKeyShortcut.self, forKey: .togglePlaybackHotkey) ?? defaults.togglePlaybackHotkey
        toggleMuteHotkey = try container.decodeIfPresent(FunctionKeyShortcut.self, forKey: .toggleMuteHotkey) ?? defaults.toggleMuteHotkey
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? defaults.playbackRate
        playbackRateEnabled = try container.decodeIfPresent(Bool.self, forKey: .playbackRateEnabled) ?? defaults.playbackRateEnabled
        systemAudioSpectrumEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemAudioSpectrumEnabled) ?? defaults.systemAudioSpectrumEnabled
        systemAudioSpectrumStyle = try container.decodeIfPresent(SystemAudioSpectrumStyle.self, forKey: .systemAudioSpectrumStyle) ?? defaults.systemAudioSpectrumStyle
        systemAudioSpectrumSensitivity = try container.decodeIfPresent(SystemAudioSpectrumSensitivity.self, forKey: .systemAudioSpectrumSensitivity) ?? defaults.systemAudioSpectrumSensitivity
        systemAudioSpectrumColorHex = try container.decodeIfPresent(String.self, forKey: .systemAudioSpectrumColorHex) ?? defaults.systemAudioSpectrumColorHex
        systemAudioSpectrumOffsetX = try container.decodeIfPresent(Double.self, forKey: .systemAudioSpectrumOffsetX) ?? defaults.systemAudioSpectrumOffsetX
        systemAudioSpectrumOffsetY = try container.decodeIfPresent(Double.self, forKey: .systemAudioSpectrumOffsetY) ?? defaults.systemAudioSpectrumOffsetY
        systemAudioSpectrumBarCount = try container.decodeIfPresent(Int.self, forKey: .systemAudioSpectrumBarCount) ?? defaults.systemAudioSpectrumBarCount
        systemAudioSpectrumPeakCapsEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemAudioSpectrumPeakCapsEnabled) ?? defaults.systemAudioSpectrumPeakCapsEnabled
        sortMode = try container.decodeIfPresent(WallpaperSortMode.self, forKey: .sortMode) ?? defaults.sortMode
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? defaults.sortAscending
    }

    enum CodingKeys: String, CodingKey {
        // JSON key 与字段名保持一致，避免语义漂移。
        // 解码走 init(from:)：缺 key 回退字段默认值（升级兼容）；
        // 历史遗留别名 key（pauseOnBattery / inactivityTimeout /
        // performanceOptimization / pauseOnBatteryPower / pauseOnInactivity）
        // 仍然废弃——旧别名解码为默认值，不保留错乱映射。
        case loopPlayback
        case randomPlayback
        case sequentialPlayback
        case autoSwitchEnabled
        case randomInterval
        case timeUnit
        case volume
        case startOnBoot
        case restorePlaybackOnLaunch
        case pauseWhenOtherAppFullscreen
        case idleTimeoutMinutes
        case pauseWhenOtherAppFocused
        case multiDisplayEnabled
        case videoFillMode
        case syncSystemWallpaper
        case pauseWhenUnplugged
        case pauseWhenIdle
        case systemHotkeysEnabled
        case previousWallpaperHotkey
        case nextWallpaperHotkey
        case togglePlaybackHotkey
        case toggleMuteHotkey
        case playbackRate
        case playbackRateEnabled
        case systemAudioSpectrumEnabled
        case systemAudioSpectrumStyle
        case systemAudioSpectrumSensitivity
        case systemAudioSpectrumColorHex
        case systemAudioSpectrumOffsetX
        case systemAudioSpectrumOffsetY
        case systemAudioSpectrumBarCount
        case systemAudioSpectrumPeakCapsEnabled
        case sortMode
        case sortAscending
    }
}

public enum TimeUnit: String, Codable, CaseIterable, Identifiable {
    case seconds = "秒"
    case minutes = "分"
    case hours = "时"
    case days = "天"
    public var id: String { rawValue }
    public var secondsValue: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        case .days: return 86400
        }
    }
}

public enum VideoFillMode: String, Codable, CaseIterable, Identifiable {
    case aspectFit = "保持原尺寸"
    case aspectFill = "填充屏幕"
    public var id: String { rawValue }
    public var description: String {
        return rawValue
    }

    /// 用于主进程 ↔ daemon IPC 传输的稳定 ASCII 标识符。
    /// rawValue 是中文 UI 显示值，不应跨进程传输；此属性提供语言无关的协议值。
    public var ipcValue: String {
        switch self {
        case .aspectFit:  return "aspectFit"
        case .aspectFill: return "aspectFill"
        }
    }

    /// 从 IPC 协议值恢复枚举，找不到时回退到默认填充模式。
    public static func fromIPC(_ value: String) -> VideoFillMode {
        switch value {
        case "aspectFit":  return .aspectFit
        case "aspectFill": return .aspectFill
        // 兼容旧版本直接传 rawValue（中文字符串）的情况
        case "保持原尺寸":    return .aspectFit
        case "填充屏幕":     return .aspectFill
        default:           return .aspectFill
        }
    }
}

public enum WallpaperSortMode: String, Codable, CaseIterable, Identifiable {
    case none = "none"         // 默认顺序（导入顺序）
    case name = "name"         // 名称 A-Z
    case size = "size"         // 文件大小
    case dateAdded = "dateAdded" // 添加日期

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "默认顺序"
        case .name: return "文件名称"
        case .size: return "文件大小"
        case .dateAdded: return "添加时间"
        }
    }

    public var symbolName: String {
        switch self {
        case .none: return "line.3.horizontal.decrease"
        case .name: return "textformat.abc"
        case .size: return "internaldrive"
        case .dateAdded: return "calendar"
        }
    }
}

/// 每个列表独立存储的排序状态，key 为 WallpaperSelectionContext.scrollPersistenceKey。
public struct SortState: Codable, Equatable {
    public var mode: WallpaperSortMode
    public var ascending: Bool

    public init(mode: WallpaperSortMode = .none, ascending: Bool = true) {
        self.mode = mode
        self.ascending = ascending
    }
}

public enum SystemAudioSpectrumStyle: String, Codable, CaseIterable, Identifiable {
    case balanced
    case banded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .balanced: return "均衡跳动"
        case .banded: return "频带起伏"
        }
    }
}

public enum SystemAudioSpectrumSensitivity: String, Codable, CaseIterable, Identifiable {
    case soft
    case normal
    case lively

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .soft: return "柔和"
        case .normal: return "标准"
        case .lively: return "增强"
        }
    }
}
