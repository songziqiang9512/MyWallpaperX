//
//  VideoWallpaper.swift
//  MyWallpaperX
//
//  视频壁纸条目模型（视频库的条目数据与展示词汇）。
//  设置/控制等全局值类型见同目录 WallpaperSettings.swift 与
//  WallpaperControls.swift。
//

import Foundation

public struct VideoWallpaper: Identifiable, Equatable, Codable {
    public let id: String
    public let title: String
    public let path: String
    public var thumbnailPath: String?
    public var staticFramePath: String?
    public var isFavorite: Bool
    public var lastUsed: Date
    public var tags: [String] = []
    /// 文件大小缓存，导入后后台填充。nil 表示尚未读取，排序时视为 Int64.max。
    public var fileSize: Int64?
    /// 视频时长（秒）
    public var duration: Int?
    /// 视频分辨率字符串，如 "1920x1080"
    public var resolution: String?

    /// 文件名（不含路径），用于日志输出。
    public var lastComponent: String { URL(fileURLWithPath: path).lastPathComponent }
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        path: String,
        thumbnailPath: String? = nil,
        staticFramePath: String? = nil,
        isFavorite: Bool = false,
        lastUsed: Date = Date(),
        tags: [String] = [],
        fileSize: Int64? = nil,
        duration: Int? = nil,
        resolution: String? = nil
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.thumbnailPath = thumbnailPath
        self.staticFramePath = staticFramePath
        self.isFavorite = isFavorite
        self.lastUsed = lastUsed
        self.tags = tags
        self.fileSize = fileSize
        self.duration = duration
        self.resolution = resolution
    }

    public var displayTitle: String {
        if title.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return title
    }
}

// VideoWallpaper CodingKeys — fileSize 单独列出方便将来迁移
extension VideoWallpaper {
    enum CodingKeys: String, CodingKey {
        case id, title, path, thumbnailPath, staticFramePath
        case isFavorite, lastUsed, tags, fileSize, duration, resolution
    }
}
