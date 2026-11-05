import AVFoundation
import Foundation

/// Source-owned local publication. File dates describe the file itself; there
/// is no persisted Pixabay download/record timestamp to infer from them.
nonisolated struct PixabayDownloadedEntry: Equatable, Sendable {
    let id: Int
    let localURL: URL
    let fileSize: Int
    var duration: Int?
    var resolutionString: String?
    var thumbnailSourceKey: String? = nil
    var creationDate: Date? = nil
    var modificationDate: Date? = nil
    var isAvailable = true

    var displayTitle: String { localURL.lastPathComponent }
    var durationString: String { duration.map(PixabayDownloadedAssetMetadata.formatDuration) ?? "" }
    var fileSizeString: String? {
        guard fileSize > 0 else { return nil }
        let mb = Double(fileSize) / (1024 * 1024)
        if mb >= 1024 { return String(format: "%.1fGB", mb / 1024) }
        if mb >= 100 { return String(format: "%.0fMB", mb) }
        if mb >= 10 { return String(format: "%.1fMB", mb) }
        return String(format: "%.2fMB", mb)
    }
    var metaLine: String {
        [fileSizeString, durationString.isEmpty ? nil : durationString, resolutionString]
            .compactMap { $0 }.joined(separator: "  ")
    }
}

nonisolated struct PixabayDownloadedContentSnapshot: Equatable, Sendable {
    let revision: UInt64
    let entries: [PixabayDownloadedEntry]
    let status: WallpaperSourceScanStatus
}

nonisolated struct PixabayLocalDeletionResult: Equatable, Sendable {
    let localURL: URL
    let id: Int?
    let failureMessage: String?
    var sourceFileDeleted: Bool = false
    var succeeded: Bool { failureMessage == nil }
}

nonisolated struct PixabayDownloadedAssetMetadata: Sendable {
    let durationSeconds: Int
    let resolutionString: String?

    static func load(from url: URL) async -> Self {
        let asset = AVURLAsset(url: url)
        return await Self(durationSeconds: durationSeconds(for: asset), resolutionString: resolutionString(for: asset))
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
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return 0 }
        return Int(seconds.rounded())
    }

    private static func resolutionString(for asset: AVAsset) async -> String? {
        guard let size = await nativeSize(for: asset) else { return nil }
        return "\(Int(size.width))×\(Int(size.height))"
    }

    static func nativeSize(for asset: AVAsset) async -> CGSize? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else { return nil }
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).size
        let width = abs(transformed.width).rounded(), height = abs(transformed.height).rounded()
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max) else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// The same path/size/mtime key is used by scanning and by the thumbnail
/// producer's before/after read checks. It is not another media/cache owner.
nonisolated enum PixabayDownloadedFileIdentity {
    // Preserve existing disk-cache keys across the module rename.
    static func key(url: URL, fileSize: Int, modificationDate: Date?) -> String {
        "ol-downloaded-preview:\(url.standardizedFileURL.path):\(fileSize):\(modificationDate?.timeIntervalSince1970 ?? 0)"
    }

    static func key(for url: URL) -> String {
        var fileURL = url.standardizedFileURL
        fileURL.removeAllCachedResourceValues()
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return key(url: fileURL, fileSize: values?.fileSize ?? 0, modificationDate: values?.contentModificationDate)
    }
}

nonisolated enum PixabayDownloadedContent {
    static func itemID(for url: URL) -> Int? {
        let name = url.lastPathComponent
        guard name.hasPrefix("online_"), name.hasSuffix(".mp4"),
              let id = Int(name.dropFirst("online_".count).dropLast(".mp4".count)),
              name == "online_\(id).mp4" else { return nil }
        return id
    }

    static func scan(in directory: URL, reusing previous: [PixabayDownloadedEntry]) async throws -> [PixabayDownloadedEntry] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [], options: [.skipsHiddenFiles])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            guard previous.isEmpty else { throw error }
            files = []
        }
        let prior = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = files.compactMap { url in itemID(for: url).map { (id: $0, url: url) } }.sorted { $0.id < $1.id }
        var entries: [PixabayDownloadedEntry] = []
        for (id, url) in candidates {
            try Task.checkCancellation()
            var freshURL = url
            freshURL.removeAllCachedResourceValues()
            // A failed per-file read is not an empty successful library scan.
            let values = try freshURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey, .isDirectoryKey])
            let size = values.fileSize ?? 0
            let key = PixabayDownloadedFileIdentity.key(url: url, fileSize: size, modificationDate: values.contentModificationDate)
            let available = values.isDirectory != true && FileManager.default.isReadableFile(atPath: url.path)
            let metadata: PixabayDownloadedAssetMetadata?
            // Restoring read permission can preserve size/mtime even though the
            // unavailable prior publication never had its AV metadata read.
            if available, prior[id]?.thumbnailSourceKey != key || prior[id]?.isAvailable != true {
                metadata = await PixabayDownloadedAssetMetadata.load(from: url)
            }
            else { metadata = nil }
            try Task.checkCancellation()
            if metadata != nil, PixabayDownloadedFileIdentity.key(for: url) != key {
                throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "文件在读取元数据期间发生变化，请刷新后重试。"])
            }
            let reused = prior[id].flatMap { $0.thumbnailSourceKey == key ? $0 : nil }
            entries.append(PixabayDownloadedEntry(id: id, localURL: url, fileSize: size,
                duration: metadata.map { $0.durationSeconds > 0 ? $0.durationSeconds : nil } ?? reused?.duration,
                resolutionString: metadata?.resolutionString ?? reused?.resolutionString, thumbnailSourceKey: key,
                creationDate: values.creationDate, modificationDate: values.contentModificationDate, isAvailable: available))
        }
        return entries
    }
}
