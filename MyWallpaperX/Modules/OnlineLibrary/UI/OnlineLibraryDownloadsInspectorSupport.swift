//
//  OnlineLibraryDownloadsInspectorSupport.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//

import AppKit
import AVFoundation
import QuartzCore

nonisolated struct OnlineLibraryDownloadedAssetMetadata: Sendable {
    let fileSize: Int
    let durationSeconds: Int
    let resolutionString: String?

    static func load(from url: URL) async -> OnlineLibraryDownloadedAssetMetadata {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let asset = AVURLAsset(url: url)
        return OnlineLibraryDownloadedAssetMetadata(
            fileSize: fileSize,
            durationSeconds: await durationSeconds(for: asset),
            resolutionString: await resolutionString(for: asset)
        )
    }

    static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remain = seconds % 60
        if minutes > 0, remain > 0 { return "\(minutes)m\(remain)s" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(max(0, seconds))s"
    }

    private static func durationSeconds(for asset: AVAsset) async -> Int {
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        guard seconds.isFinite else { return 0 }
        return max(0, Int(seconds.rounded()))
    }

    private static func resolutionString(for asset: AVAsset) async -> String? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else {
            return nil
        }
        let transformed = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        guard width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }
}

struct OnlineLibraryDownloadsInspectorSnapshot {
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
    let previewImage: NSImage?

    static func load(itemID: Int) async -> OnlineLibraryDownloadsInspectorSnapshot? {
        let url = OnlineLibraryService.downloadDirectory.appendingPathComponent("online_\(itemID).mp4")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let creationDate = attributes[.creationDate] as? Date
        let metadata = await OnlineLibraryDownloadedAssetMetadata.load(from: url)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        return OnlineLibraryDownloadsInspectorSnapshot(
            id: itemID,
            title: url.lastPathComponent,
            fileExtension: url.pathExtension.uppercased(),
            fileSizeText: ByteCountFormatter.string(fromByteCount: Int64(metadata.fileSize), countStyle: .file),
            durationText: metadata.durationSeconds > 0 ? OnlineLibraryDownloadedAssetMetadata.formatDuration(metadata.durationSeconds) : "未知",
            resolutionText: metadata.resolutionString ?? "未知",
            creationDateText: creationDate.map(formatter.string(from:)) ?? "未知",
            platformText: "Pixabay",
            path: url.path,
            fileURL: url,
            previewImage: OLDownloadedThumbnailStore.sharedCache.cachedImage(
                forKey: OLDownloadedThumbnailStore.cacheKey(for: url)
            )
        )
    }
}

enum OnlineLibraryDownloadsInspectorViews {
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

    static func makeBadge(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.layer?.borderWidth = 0.6
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])

        return container
    }

    static func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([divider.heightAnchor.constraint(equalToConstant: 1)])
        return divider
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

final class OnlineLibraryDownloadsPreviewSurfaceView: NSView {
    private let previewImage: NSImage?
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0.22),
            ending: NSColor(calibratedRed: 0.84, green: 0.91, blue: 1, alpha: 0.20)
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
