import AVFoundation
import Darwin
import Foundation

/// Source-owned local publication. File dates describe the file itself; there
/// is no persisted Pixabay download/record timestamp to infer from them.
nonisolated struct PixabayDownloadedEntry: Equatable, Sendable {
    let id: Int
    let localURL: URL
    let fileSize: Int
    var duration: Int?
    var displaySize: CGSize?
    var nominalFrameRateText: String?
    var thumbnailSourceKey: String? = nil
    var creationDate: Date? = nil
    var modificationDate: Date? = nil
    var isAvailable = true

    var displayTitle: String { localURL.lastPathComponent }
    var durationString: String { duration.map(PixabayDownloadedAssetMetadata.formatDuration) ?? "" }
    var resolutionString: String? { displaySize.map { "\(Int($0.width))×\(Int($0.height))" } }
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
    let displaySize: CGSize?
    let nominalFrameRateText: String?

    static func load(from url: URL) async -> Self {
        let asset = AVURLAsset(url: url)
        let duration = await durationSeconds(for: asset)
        let track = await WallpaperVideoTrackDetails.load(from: asset, includesCodec: false)
        return Self(durationSeconds: duration, displaySize: track?.displaySize, nominalFrameRateText: track?.nominalFrameRateText)
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

    static func nativeSize(for asset: AVAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        return await WallpaperVideoTrackDetails.displaySize(for: track)
    }
}

/// Scanning and thumbnail generation use the same observed file revision.
nonisolated enum PixabayDownloadedFileIdentity {
    static func observe(path: String) throws -> stat {
        var file = stat()
        if stat(path, &file) == 0 { return file }
        let code = errno
        // Preserve the row for a symlink whose target is unavailable.
        if lstat(path, &file) == 0, file.st_mode & S_IFMT == S_IFLNK { return file }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }

    static func key(path: String, file: stat) -> String {
        "ol-downloaded-preview:\(path):\(file.st_dev):\(file.st_ino):\(file.st_size):\(file.st_mtimespec.tv_sec):\(file.st_mtimespec.tv_nsec)"
    }

    static func key(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard let file = try? observe(path: path) else { return "ol-downloaded-preview:\(path):missing" }
        return key(path: path, file: file)
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
            let path = url.standardizedFileURL.path
            let file = try PixabayDownloadedFileIdentity.observe(path: path)
            let key = PixabayDownloadedFileIdentity.key(path: path, file: file)
            let kind = file.st_mode & S_IFMT
            let available = kind != S_IFDIR && kind != S_IFLNK && FileManager.default.isReadableFile(atPath: path)
            let metadata: PixabayDownloadedAssetMetadata?
            // Restoring read permission can preserve size/mtime even though the
            // unavailable prior publication never had its AV metadata read.
            if available, prior[id]?.thumbnailSourceKey != key || prior[id]?.isAvailable != true {
                metadata = await PixabayDownloadedAssetMetadata.load(from: url)
            }
            else { metadata = nil }
            try Task.checkCancellation()
            if metadata != nil, PixabayDownloadedFileIdentity.key(for: url) != key {
                throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: String(localized: "The file changed while its metadata was being read. Refresh and try again.")])
            }
            let reused = prior[id].flatMap { $0.thumbnailSourceKey == key ? $0 : nil }
            let birth = file.st_birthtimespec
            let creationDate = birth.tv_sec == 0 && birth.tv_nsec == 0 ? nil : date(from: birth)
            entries.append(PixabayDownloadedEntry(id: id, localURL: url, fileSize: Int(file.st_size),
                duration: metadata.map { $0.durationSeconds > 0 ? $0.durationSeconds : nil } ?? reused?.duration,
                displaySize: metadata?.displaySize ?? reused?.displaySize,
                nominalFrameRateText: metadata?.nominalFrameRateText ?? reused?.nominalFrameRateText, thumbnailSourceKey: key,
                creationDate: creationDate, modificationDate: date(from: file.st_mtimespec), isAvailable: available))
        }
        return entries
    }

    private static func date(from time: timespec) -> Date {
        Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
    }
}
