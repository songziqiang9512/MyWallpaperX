//
//  WallpaperControls.swift
//  MyWallpaperX
//
//  用户控制词汇：壁纸库侧栏分类（Category）、F1-F12 功能键与系统
//  热键动作。Category 被 Shell 侧栏/选择上下文与 App 协调器消费；
//  热键两枚举被 Core 的 GlobalHotkeyManager 与 Shared 设置面板/
//  Modules 共享（Models 底层值类型层，见 WallpaperSettings.swift 头注）。
//

import Foundation

public enum Category: String, CaseIterable, Identifiable, Hashable {
    case myWallpapers, favorites, recentlyUsed, tags, settings
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .myWallpapers: return "我的壁纸"
        case .favorites: return "特别喜爱"
        case .recentlyUsed: return "最近使用"
        case .tags: return "标签"
        case .settings: return "设置"
        }
    }
}

public enum FunctionKeyShortcut: String, Codable, CaseIterable, Identifiable {
    case none
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "无"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        }
    }
}

public enum SystemHotkeyAction: String, CaseIterable, Identifiable {
    case previous
    case next
    case playPause
    case muteToggle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .previous: return "-  上一张"
        case .next: return "-  下一张"
        case .playPause: return "-  播放/暂停"
        case .muteToggle: return "-  开启静音/关闭静音"
        }
    }
}
