//
//  DaemonProtocol.swift
//  MyWallpaperX
//
//  主进程与 WallpaperDaemon 之间的 IPC 协议结构体。
//  此文件同时编译进两个 Target（MyWallpaperX 和 MyWallpaperXWallpaperDaemon），
//  是 IPC 字段的唯一来源，新增字段只需改这里。
//
//  ⚠️ 需要手动操作：在 Xcode 中选中此文件 → File Inspector →
//  Target Membership → 勾选 MyWallpaperXWallpaperDaemon。
//

import Foundation

struct DaemonCommand: Codable {
    let action: String
    let videoPath: String?
    let framePath: String?
    let propertiesJSON: String?
    let fillMode: String?
    let shouldLoopCurrentItem: Bool?
    let volume: Float?
    let playbackRate: Float?
    let spectrumEnabled: Bool?
    let spectrumLevels: [Float]?
    let spectrumBarCount: Int?
    let spectrumColorHex: String?
    let spectrumOffsetX: Float?
    let spectrumOffsetY: Float?
    let spectrumPeakCapsEnabled: Bool?
    let requestID: Int?
}

struct DaemonEvent: Codable {
    let type: String
    let displayID: UInt32
    let requestID: Int?
    let message: String?
    let videoPath: String?
    let contentKind: String?
}
