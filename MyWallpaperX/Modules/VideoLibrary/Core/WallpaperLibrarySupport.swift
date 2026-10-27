//
//  WallpaperLibrarySupport.swift
//  MyWallpaperX
//

import Foundation
import AVFoundation
import CoreMedia

struct ImportSummary {
    let requestedCount: Int
    let importedCount: Int
    let linkedCount: Int
    let skippedCount: Int
    let thumbnailFailureCount: Int
    let failureBreakdown: [String]

    var informativeText: String {
        var lines: [String] = [
            "总选择：\(requestedCount) 个",
            "新增导入：\(importedCount) 个"
        ]

        if linkedCount > 0 {
            lines.append("已加入当前列表：\(linkedCount) 个")
        }

        lines.append("未处理：\(skippedCount) 个")

        if importedCount > 0 {
            if thumbnailFailureCount > 0 {
                lines.append("缩略图未生成：\(thumbnailFailureCount) 个")
            } else {
                lines.append("缩略图与静帧已开始后台生成")
            }
        }

        if !failureBreakdown.isEmpty {
            lines.append("")
            lines.append(contentsOf: failureBreakdown)
        }

        return lines.joined(separator: "\n")
    }
}

enum ImportContext: Equatable {
    case library
    case onlinePlayback  // 在线库静默导入并立即播放，不弹任何提示
    case steamPlayback   // Steam 创意工坊静默导入并立即播放，不弹任何提示
}


enum ManualNavigationDirection {
    case previous
    case next
}

struct WallpaperDeletionFailure: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    let reason: String

    var displayText: String {
        let fileName = title.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : title
        return "\(fileName)：\(reason)"
    }
}

struct WallpaperInspectorDetails: Equatable {
    let fileSizeText: String
    let formatText: String
    let durationText: String
    let codecText: String
    let resolutionText: String
    let addedDateText: String
    let pathText: String
    var isLoading = false
}

@discardableResult
func loadWallpaperInspectorDetails(
    for wallpaper: VideoWallpaper,
    completion: @escaping (WallpaperInspectorDetails) -> Void
) -> Task<Void, Never> {
    let url = URL(fileURLWithPath: wallpaper.path)
    let path = wallpaper.path
    let formatText = url.pathExtension.isEmpty ? "未知" : url.pathExtension.uppercased()
    let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
    let fileSize = attributes[.size] as? Int64 ?? 0
    let fileSizeText = String(format: "%.2f MB", Double(fileSize) / (1024 * 1024))
    let creationDate = attributes[.creationDate] as? Date ?? Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    let addedDateText = dateFormatter.string(from: creationDate)

    // Publish the complete layout template before the view is mounted. AV
    // fills values later, without adding/removing metadata or path sections.
    completion(WallpaperInspectorDetails(fileSizeText: fileSizeText, formatText: formatText,
        durationText: wallpaper.duration.map { formattedDuration(Double($0)) } ?? "读取中…",
        codecText: "读取中…", resolutionText: wallpaper.resolution ?? "读取中…",
        addedDateText: addedDateText, pathText: path, isLoading: true))

    return Task {
        let asset = AVURLAsset(url: url)
        var durationText = wallpaper.duration.map { formattedDuration(Double($0)) } ?? "未知"
        if let duration = try? await asset.load(.duration) {
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite && durationSeconds > 0 {
                durationText = formattedDuration(durationSeconds)
            }
        }
        guard !Task.isCancelled else { return }

        let resolutionText = await videoResolutionText(for: asset, fallback: wallpaper.resolution)
        let codecText = await videoCodecText(for: asset)

        let details = WallpaperInspectorDetails(
            fileSizeText: fileSizeText,
            formatText: formatText,
            durationText: durationText,
            codecText: codecText,
            resolutionText: resolutionText,
            addedDateText: addedDateText,
            pathText: path
        )

        await MainActor.run {
            guard !Task.isCancelled else { return }
            completion(details)
        }
    }
}

private func formattedDuration(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

private func videoResolutionText(for asset: AVAsset, fallback: String? = nil) async -> String {
    guard let tracks = try? await asset.loadTracks(withMediaType: .video),
          let track = tracks.first else {
        return fallback ?? "未知"
    }
    guard let naturalSize = try? await track.load(.naturalSize),
          let preferredTransform = try? await track.load(.preferredTransform) else {
        return fallback ?? "未知"
    }
    let transformedSize = naturalSize.applying(preferredTransform)
    let width = Int(abs(transformedSize.width).rounded())
    let height = Int(abs(transformedSize.height).rounded())
    guard width > 0, height > 0 else { return fallback ?? "未知" }
    return "\(width) × \(height)"
}

private func videoCodecText(for asset: AVAsset) async -> String {
    guard let tracks = try? await asset.loadTracks(withMediaType: .video),
          let track = tracks.first,
          let formatDescriptions = try? await track.load(.formatDescriptions),
          let formatDescription = formatDescriptions.first else {
        return "未知"
    }
    let codec = CMFormatDescriptionGetMediaSubType(formatDescription)
    switch codec {
    case kCMVideoCodecType_H264:
        return "H.264"
    case kCMVideoCodecType_HEVC:
        return "HEVC"
    case kCMVideoCodecType_HEVCWithAlpha:
        return "HEVC with Alpha"
    case kCMVideoCodecType_MPEG4Video:
        return "MPEG-4 Part 2"
    case kCMVideoCodecType_H263:
        return "H.263"
    default:
        return String(format: "0x%08X", codec)
    }
}
