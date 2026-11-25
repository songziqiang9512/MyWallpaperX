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
            String(localized: "Total selected: \(requestedCount)"),
            String(localized: "Newly imported: \(importedCount)")
        ]

        if linkedCount > 0 {
            lines.append(String(localized: "Added to the current list: \(linkedCount)"))
        }

        lines.append(String(localized: "Skipped: \(skippedCount)"))

        if importedCount > 0 {
            if thumbnailFailureCount > 0 {
                lines.append(String(localized: "Thumbnails not generated: \(thumbnailFailureCount)"))
            } else {
                lines.append(String(localized: "Thumbnails and still frames are being generated in the background"))
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
    case pixabayPlayback  // 在线库静默导入并立即播放，不弹任何提示
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

nonisolated struct WallpaperInspectorDetails: Equatable, Sendable {
    let fileSizeText: String
    let formatText: String
    let durationText: String
    let codecText: String
    let resolutionText: String
    let addedDateText: String
    let pathText: String
    var isLoading = false
    var nominalFrameRateText: String? = nil
}

@MainActor
@discardableResult
func loadWallpaperInspectorDetails(
    for wallpaper: VideoWallpaper,
    completion: @escaping (WallpaperInspectorDetails) -> Void
) -> Task<Void, Never> {
    let url = URL(fileURLWithPath: wallpaper.path, isDirectory: false)
    let path = wallpaper.path
    let formatText = url.pathExtension.isEmpty ? String(localized: "Unknown") : url.pathExtension.uppercased()

    // Keep every section present before mounting; file facts arrive with AV metadata.
    completion(WallpaperInspectorDetails(
        fileSizeText: wallpaper.fileSize.map { String(format: "%.2f MB", Double($0) / (1024 * 1024)) } ?? String(localized: "Reading…"),
        formatText: formatText, durationText: wallpaper.duration.map { formattedDuration(Double($0)) } ?? String(localized: "Reading…"),
        codecText: String(localized: "Reading…"), resolutionText: wallpaper.resolution ?? String(localized: "Reading…"),
        addedDateText: String(localized: "Reading…"), pathText: path, isLoading: true))

    return Task { @MainActor in
        guard !Task.isCancelled,
              let details = await prepareWallpaperInspectorDetails(for: wallpaper) else { return }
        guard !Task.isCancelled else { return }
        completion(details)
    }
}

@concurrent
nonisolated private func prepareWallpaperInspectorDetails(for wallpaper: VideoWallpaper) async -> WallpaperInspectorDetails? {
    guard !Task.isCancelled else { return nil }
    let path = wallpaper.path
    let url = URL(fileURLWithPath: path, isDirectory: false)
    let formatText = url.pathExtension.isEmpty ? String(localized: "Unknown") : url.pathExtension.uppercased()
    let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
    let fileSize = attributes[.size] as? Int64 ?? 0
    let fileSizeText = String(format: "%.2f MB", Double(fileSize) / (1024 * 1024))
    let creationDate = attributes[.creationDate] as? Date ?? Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    let addedDateText = dateFormatter.string(from: creationDate)
    guard !Task.isCancelled else { return nil }

    let asset = AVURLAsset(url: url)
    var durationText = wallpaper.duration.map { formattedDuration(Double($0)) } ?? String(localized: "Unknown")
    if let duration = try? await asset.load(.duration) {
        let durationSeconds = CMTimeGetSeconds(duration)
        if durationSeconds.isFinite && durationSeconds > 0 {
            durationText = formattedDuration(durationSeconds)
        }
    }
    guard !Task.isCancelled else { return nil }

    let trackDetails = await WallpaperVideoTrackDetails.load(from: asset)

    return WallpaperInspectorDetails(
        fileSizeText: fileSizeText,
        formatText: formatText,
        durationText: durationText,
        codecText: trackDetails?.codecText ?? String(localized: "Unknown"),
        resolutionText: trackDetails?.resolutionText ?? wallpaper.resolution ?? String(localized: "Unknown"),
        addedDateText: addedDateText,
        pathText: path,
        nominalFrameRateText: trackDetails?.nominalFrameRateText
    )
}

nonisolated private func formattedDuration(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
}
