//
//  PixabayDownloadsInspectorSupport.swift
//  MyWallpaperX — Modules/Pixabay/UI
//

import AppKit

struct PixabayDownloadsInspectorSnapshot {
    let entry: PixabayDownloadedEntry
    let id: Int
    let title: String
    let fileExtension: String
    let fileSizeText: String
    let durationText: String
    let resolutionText: String
    let creationDateText: String
    let platformText: String
    let path: String
    let fileURL: URL

    @MainActor static func load(itemID: Int, service: PixabayService? = nil) -> PixabayDownloadsInspectorSnapshot? {
        let service = service ?? .shared
        guard let entry = service.downloadedContent.entries.first(where: { $0.id == itemID }),
              entry.isAvailable else { return nil }
        return .init(entry: entry)
    }

    init(entry: PixabayDownloadedEntry) {
        let url = entry.localURL
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        self.entry = entry
        id = entry.id
        title = url.lastPathComponent
        fileExtension = url.pathExtension.uppercased()
        fileSizeText = ByteCountFormatter.string(fromByteCount: Int64(entry.fileSize), countStyle: .file)
        durationText = entry.duration.map(PixabayDownloadedAssetMetadata.formatDuration) ?? "未知"
        resolutionText = entry.resolutionString ?? "未知"
        creationDateText = entry.creationDate.map(formatter.string(from:)) ?? "未知"
        platformText = "Pixabay"
        path = url.path
        fileURL = url
    }
}

enum PixabayDownloadsInspectorViews {

    static func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.backgroundColor = .clear
        label.isBordered = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }



    static func makeFooterButton(
        title: String,
        symbolName: String,
        target: AnyObject?,
        action: Selector,
        kind: InspectorFooterButtonKind = .secondary
    ) -> InspectorFooterButton {
        let button = InspectorFooterButton(
            title: title,
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title),
            kind: kind,
            target: target,
            action: action
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
