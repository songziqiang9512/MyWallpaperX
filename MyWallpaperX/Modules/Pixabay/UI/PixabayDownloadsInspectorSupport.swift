//
//  PixabayDownloadsInspectorSupport.swift
//  MyWallpaperX — Modules/Pixabay/UI
//

import AppKit
import QuartzCore

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
    static func makeFactView(label: String, value: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeLabel(label, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor))
        let valueLabel = makeLabel(value, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        valueLabel.maximumNumberOfLines = 3
        valueLabel.isSelectable = true
        stack.addArrangedSubview(valueLabel)

        return stack
    }

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

final class PixabayDownloadsPreviewSurfaceView: NSView {
    private var previewImage: NSImage?
    private let placeholderView = NSImageView()

    init(itemID: Int, previewImage: NSImage?) {
        self.previewImage = previewImage
        super.init(frame: .zero)
        setup(itemID: itemID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateImage(_ image: NSImage?) {
        previewImage = image
        placeholderView.isHidden = image != nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0.22),
            ending: NSColor.controlAccentColor.withAlphaComponent(0.20)
        )?.draw(in: bounds, angle: -45)

        guard let previewImage else { return }

        let imageSize = previewImage.size
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let targetSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let targetRect = NSRect(
            x: bounds.midX - targetSize.width / 2,
            y: bounds.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        previewImage.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func setup(itemID: Int) {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        layer?.borderWidth = 0.45
        setAccessibilityLabel("在线图库下载项预览 \(itemID)")

        placeholderView.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: nil)
        placeholderView.contentTintColor = .secondaryLabelColor
        placeholderView.symbolConfiguration = .init(pointSize: 28, weight: .medium)
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.isHidden = previewImage != nil

        addSubview(placeholderView)

        NSLayoutConstraint.activate([
            placeholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderView.widthAnchor.constraint(equalToConstant: 36),
            placeholderView.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
}
