//
//  WallpaperControls.swift
//  MyWallpaperX
//
//  F1-F12 功能键与系统热键动作，供 Core、Modules 与 Shared 设置使用。
//

import Foundation


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
        case .none: return String(localized: "None")
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

    var settingsKeyPath: WritableKeyPath<WallpaperSettings, FunctionKeyShortcut> {
        switch self {
        case .previous: \.previousWallpaperHotkey
        case .next: \.nextWallpaperHotkey
        case .playPause: \.togglePlaybackHotkey
        case .muteToggle: \.toggleMuteHotkey
        }
    }

    public var displayName: String {
        switch self {
        case .previous: return String(localized: "Previous Wallpaper")
        case .next: return String(localized: "Next Wallpaper")
        case .playPause: return String(localized: "Play/Pause")
        case .muteToggle: return String(localized: "Mute/Unmute")
        }
    }
}
