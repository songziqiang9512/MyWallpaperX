import CryptoKit
import Darwin
import Foundation
import SQLite3

/// Frozen before constructing either legacy library owner. Absence differs from
/// a complete empty fallback. Wrong types and undecodable values remain errors.
nonisolated struct LegacyLibraryFrozenDefaults: Codable, Sendable {
    let wallpaperFallback: Data?
    let startupChanges: Data?
    let videoTags: Data?
    let staticImageTags: [String]?
    let recentWallpapers: Data?
    /// Opaque noncredential values for later sort/restore adapters.
    let auxiliaryPreferences: Data?

    /// The whitelist is frozen without interpreting relation values. A wrong
    /// legacy type must remain recoverable before typed admission can fail.
    @MainActor static func rawValues(defaults: UserDefaults) throws -> Data {
        let keys = ["Wallpapers", "WallpaperIndexStartupChangesV1", "WallpaperTags", "SILTags", "RecentWallpapers",
                    "WallpaperSettings", "PerSelectionSortStates", "SILSortState", "gridZoomOffset",
                    "SILGridZoomOffset", "CurrentWallpaper", "PlaybackState", "ActiveWallpaperRuntime",
                    "LastWorkshopPlaybackRecordID", "OLDownloadsSortMode", "OLDownloadsSortAscending",
                    "onlineLibrary.gridZoomOffset"]
        let values = keys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    @MainActor init(defaults: UserDefaults) throws {
        try self.init(rawValues: Self.rawValues(defaults: defaults))
    }

    init(rawValues: Data) throws {
        guard let frozenValues = try PropertyListSerialization.propertyList(from: rawValues, options: [], format: nil)
            as? [String: Any] else { throw LegacyLibraryCaptureError.invalidDefaults("raw defaults") }
        func data(_ key: String) throws -> Data? {
            guard let value = frozenValues[key] else { return nil }
            guard let value = value as? Data else { throw LegacyLibraryCaptureError.invalidDefaults(key) }
            return value
        }
        wallpaperFallback = try data("Wallpapers")
        startupChanges = try data("WallpaperIndexStartupChangesV1")
        videoTags = try data("WallpaperTags")
        recentWallpapers = try data("RecentWallpapers")
        if let value = frozenValues["SILTags"] {
            guard let value = value as? [String] else { throw LegacyLibraryCaptureError.invalidDefaults("SILTags") }
            staticImageTags = value
        } else { staticImageTags = nil }
        let auxiliaryKeys = ["WallpaperSettings", "PerSelectionSortStates", "SILSortState", "gridZoomOffset",
                             "SILGridZoomOffset", "CurrentWallpaper", "PlaybackState", "ActiveWallpaperRuntime",
                             "LastWorkshopPlaybackRecordID", "OLDownloadsSortMode", "OLDownloadsSortAscending",
                             "onlineLibrary.gridZoomOffset"]
        let auxiliary = auxiliaryKeys.reduce(into: [String: Any]()) { values, key in
            if let value = frozenValues[key] { values[key] = value }
        }
        auxiliaryPreferences = auxiliary.isEmpty ? nil : try PropertyListSerialization.data(
            fromPropertyList: auxiliary, format: .binary, options: 0)
    }

    init(wallpaperFallback: Data? = nil, startupChanges: Data? = nil, videoTags: Data? = nil,
         staticImageTags: [String]? = nil, recentWallpapers: Data? = nil, auxiliaryPreferences: Data? = nil) {
        self.wallpaperFallback = wallpaperFallback
        self.startupChanges = startupChanges
        self.videoTags = videoTags
        self.staticImageTags = staticImageTags
        self.recentWallpapers = recentWallpapers
        self.auxiliaryPreferences = auxiliaryPreferences
    }
}

nonisolated enum LegacyLibraryCaptureError: Error, LocalizedError {
    case invalidDefaults(String)
    case invalidPayload(String)
    case database(String)
    case backupAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidDefaults(let key): return "旧资料库设置类型无效：\(key)"
        case .invalidPayload(let source): return "旧资料库快照无法完整读取：\(source)"
        case .database(let message): return "旧视频索引一致快照失败：\(message)"
        case .backupAlreadyExists: return "迁移备份目录已存在，不能覆盖原始快照。"
        }
    }
}

nonisolated struct LegacyLibrarySnapshotManifest: Codable, Sendable, Equatable {
    struct Source: Codable, Sendable, Equatable {
        let name: String
        let present: Bool
        let sha256: String?
        let byteCount: Int
        let recordCount: Int?
        let interpretation: String?
        let backupRelativePath: String?
    }
    let schemaVersion: Int
    let id: String
    let capturedAt: Date
    let sources: [Source]
    let videoIndexInitialized: Bool
    let usedCompleteVideoFallback: Bool
}

/// Metadata only. It never opens media, checks file existence or instantiates a
/// service. Capture admission belongs to App startup; call before legacy owners
/// can normalize, purge, inject seeds or rewrite their stores.
nonisolated struct LegacyLibrarySnapshot: Sendable {
    let manifest: LegacyLibrarySnapshotManifest
    let backupDirectoryURL: URL
    let videos: [LibraryCollectionsMigrationItem]
    let videoTags: [String]
    let staticImages: [LibraryCollectionsMigrationItem]
    let staticImageTags: [String]
    let recent: [LibraryCollectionsMigrationItem]
    let viewPreferences: LibraryCollectionsLegacyViewPreferences

    var manifestID: String { manifest.id }
    var capturedAt: Date { manifest.capturedAt }
    var migrationInput: LibraryCollectionsMigrationInput {
        LibraryCollectionsMigrationInput(manifestID: manifestID, capturedAt: capturedAt,
                                        videos: videos, videoTags: videoTags, staticImages: staticImages,
                                        staticImageTags: staticImageTags, recent: recent, viewPreferences: viewPreferences)
    }

    /// `defaults` must already be frozen at the caller's serial admission
    /// boundary. The I/O below belongs on a worker, while no legacy owner exists.
    /// Startup uses this overload while holding the publication lease. The
    /// durable typed input precedes the completion manifest, so a crash cannot
    /// leave a completed capture that requires rereading a cleaned live source.
    static func capture(rawDefaults: Data, indexURL: URL, staticImageURL: URL, backupDirectoryURL: URL,
                        inputSnapshotURL: URL, capturedAt: Date = Date()) throws -> Self {
        try prepareDirectory(backupDirectoryURL)
        try writeDurable(rawDefaults, to: backupDirectoryURL.appendingPathComponent("raw-defaults.plist"))
        let defaults = try LegacyLibraryFrozenDefaults(rawValues: rawDefaults)
        return try capturePrepared(defaults: defaults, indexURL: indexURL, staticImageURL: staticImageURL,
                                   backupDirectoryURL: backupDirectoryURL, inputSnapshotURL: inputSnapshotURL,
                                   capturedAt: capturedAt)
    }

    private static func prepareDirectory(_ backupDirectoryURL: URL) throws {
        let fm = FileManager.default
        do {
            _ = try fm.attributesOfItem(atPath: backupDirectoryURL.path)
            throw LegacyLibraryCaptureError.backupAlreadyExists
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            try fm.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private static func capturePrepared(defaults: LegacyLibraryFrozenDefaults, indexURL: URL, staticImageURL: URL,
                                        backupDirectoryURL: URL, inputSnapshotURL: URL, capturedAt: Date) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let defaultsData = try encoder.encode(defaults)
        try writeDurable(defaultsData, to: backupDirectoryURL.appendingPathComponent("defaults.json"))
        // Preserve raw inputs before interpretation. A later error leaves this
        // bounded recovery directory intact and never publishes a valid manifest.
        let imageData = try readOptional(staticImageURL)
        if let imageData {
            try writeDurable(imageData, to: backupDirectoryURL.appendingPathComponent("sil_wallpapers.json"))
        }
        let decoder = JSONDecoder()
        let fallback: [VideoWallpaper]? = try decodeOptional(defaults.wallpaperFallback, decoder, "Wallpapers")
        let index = try LegacyVideoIndexSnapshot.readAndBackup(
            sourceURL: indexURL, backupURL: backupDirectoryURL.appendingPathComponent("wallpaper_index.sqlite3"),
            requiresIndex: fallback == nil)
        let changes: WallpaperIndexStartupChanges
        if fallback != nil {
            // Legacy startup restores a complete failed-save snapshot even when
            // a superseded journal is unreadable. Preserve those raw bytes above.
            changes = WallpaperIndexStartupChanges()
        } else {
            changes = try decodeOptional(defaults.startupChanges, decoder, "WallpaperIndexStartupChangesV1")
                ?? WallpaperIndexStartupChanges()
            guard changes.isValid(normalize: normalizedPath) else {
                throw LegacyLibraryCaptureError.invalidPayload("WallpaperIndexStartupChangesV1")
            }
        }
        let legacyTags: [String] = try decodeOptional(defaults.videoTags, decoder, "WallpaperTags") ?? []
        let legacyRecent: [VideoWallpaper] = try decodeOptional(defaults.recentWallpapers, decoder, "RecentWallpapers") ?? []
        let images: [ImageRecord] = try decodeOptional(imageData, decoder, "sil_wallpapers.json") ?? []
        // The complete failed-save snapshot supersedes both SQLite and journal,
        // including []. Otherwise reuse the original ordered merger unchanged.
        let materialized: [VideoWallpaper]
        if let fallback {
            materialized = WallpaperIndexStartupChanges().merged(with: fallback) {
                URL(fileURLWithPath: $0).standardizedFileURL.path
            }
        }
        else {
            materialized = changes.merged(with: index.initialized ? index.videos : changes.seeds,
                                          normalize: normalizedPath)
        }
        let sources: [LegacyLibrarySnapshotManifest.Source] = [
            source("defaults", defaultsData, records: materialized.count),
            source("video-index", index.backupData, records: index.recordCount,
                   interpretation: index.interpretation, backupRelativePath: index.backupRelativePath),
            source("static-images", imageData, records: images.count),
            source("recent", defaults.recentWallpapers, records: legacyRecent.count)
        ] + index.recoverySources
        // Bind the marker to frozen source contents and interpretation version;
        // repeated capture dates do not turn the same input into a new migration.
        let identity = try encoder.encode(Identity(schemaVersion: 1, sources: sources,
                                                  videoIndexInitialized: index.initialized,
                                                  usedCompleteVideoFallback: fallback != nil))
        let manifest = LegacyLibrarySnapshotManifest(
            schemaVersion: 1, id: digest(identity), capturedAt: capturedAt, sources: sources,
            videoIndexInitialized: index.initialized, usedCompleteVideoFallback: fallback != nil)
        let snapshot = Self(manifest: manifest, backupDirectoryURL: backupDirectoryURL,
                    videos: materialized.map(videoItem), videoTags: legacyTags,
                    staticImages: images.map { image in
                        LibraryCollectionsMigrationItem(
                            reference: WallpaperReference(provider: .staticImageLibrary, sourceID: image.id),
                            locator: WallpaperLocator(path: image.path, titleHint: image.title,
                                                      mediaKind: .image, provenance: "legacy-static-image-library"),
                            tags: image.tags)
                    }, staticImageTags: defaults.staticImageTags ?? [], recent: legacyRecent.map(videoItem),
                    viewPreferences: .init(auxiliaryPreferences: defaults.auxiliaryPreferences,
                        videoTimeOrder: materialized.enumerated().sorted {
                            $0.element.lastUsed == $1.element.lastUsed ? $0.offset < $1.offset : $0.element.lastUsed < $1.element.lastUsed
                        }.map { WallpaperReference(provider: .videoLibrary, sourceID: $0.element.id) },
                        imageTimeOrder: images.enumerated().sorted {
                            switch ($0.element.lastUsed, $1.element.lastUsed) {
                            case let (.some(a), .some(b)): return a == b ? $0.offset < $1.offset : a < b
                            case (.some, nil): return true
                            case (nil, .some): return false
                            case (nil, nil): return $0.offset < $1.offset
                            }
                        }.map { WallpaperReference(provider: .staticImageLibrary, sourceID: $0.element.id) }))
        try writeDurable(encoder.encode(snapshot.migrationInput), to: inputSnapshotURL)
        try writeDurable(encoder.encode(manifest), to: backupDirectoryURL.appendingPathComponent("manifest.json"))
        return snapshot
    }

    static func writeDurable(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
        let directory = url.deletingLastPathComponent()
        let fd = directory.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private struct Identity: Encodable {
        let schemaVersion: Int
        let sources: [LegacyLibrarySnapshotManifest.Source]
        let videoIndexInitialized: Bool
        let usedCompleteVideoFallback: Bool
    }

    private struct ImageRecord: Decodable {
        let id: String
        let path: String
        let title: String
        let tags: [String]
        let lastUsed: Date?

        private enum CodingKeys: String, CodingKey { case id, path, title, tags, lastUsed }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            path = try values.decode(String.self, forKey: .path)
            title = try values.decode(String.self, forKey: .title)
            tags = try values.decode([String].self, forKey: .tags)
            // A malformed display clock must not discard valid relationships.
            lastUsed = (try? values.decodeIfPresent(Date.self, forKey: .lastUsed)) ?? nil
        }
    }

    private static func videoItem(_ video: VideoWallpaper) -> LibraryCollectionsMigrationItem {
        LibraryCollectionsMigrationItem(
            reference: WallpaperReference(provider: .videoLibrary, sourceID: video.id),
            locator: WallpaperLocator(path: video.path, titleHint: video.title,
                                      mediaKind: .video, provenance: "legacy-video-library"),
            tags: video.tags, isFavorite: video.isFavorite)
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func readOptional(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private static func decodeOptional<T: Decodable>(_ data: Data?, _ decoder: JSONDecoder,
                                                    _ name: String) throws -> T? {
        guard let data else { return nil }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw LegacyLibraryCaptureError.invalidPayload(name) }
    }

    fileprivate static func source(_ name: String, _ data: Data?, records: Int?, interpretation: String? = nil,
                                   backupRelativePath: String? = nil) -> LegacyLibrarySnapshotManifest.Source {
        .init(name: name, present: data != nil, sha256: data.map(digest), byteCount: data?.count ?? 0,
              recordCount: records, interpretation: interpretation, backupRelativePath: backupRelativePath)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Independent read-only connection pins a WAL-consistent read transaction.
/// sqlite3_backup copies that same view, including committed WAL pages, without
/// opening the legacy store's CREATE/schema-repair or cleanup path.
private nonisolated enum LegacyVideoIndexSnapshot {
    struct Result {
        let videos: [VideoWallpaper]
        let initialized: Bool
        let backupData: Data?
        let recordCount: Int?
        let interpretation: String
        let backupRelativePath: String?
        let recoverySources: [LegacyLibrarySnapshotManifest.Source]
    }

    static func readAndBackup(sourceURL: URL, backupURL: URL, requiresIndex: Bool) throws -> Result {
        // SQLite may rebuild SHM even for a read-only WAL connection. Freeze
        // superseded recovery bytes before asking SQLite to interpret anything.
        let rawSources: [(suffix: String, data: Data?)] = requiresIndex ? [] : try ["", "-wal", "-shm"].map { suffix in
            let source = URL(fileURLWithPath: sourceURL.path + suffix)
            do { return (suffix, try Data(contentsOf: source)) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { return (suffix, nil) }
        }
        do { return try read(sourceURL: sourceURL, backupURL: backupURL, requiresIndex: requiresIndex) }
        catch {
            guard !requiresIndex else { throw error }
            // A valid complete fallback owns all video relationships. An unreadable
            // superseded index is recovery material only, never an empty baseline
            // or a purported WAL-consistent logical backup. Reads may still fail.
            guard let data = rawSources.first?.data else { throw error }
            let rawName = backupURL.lastPathComponent + ".raw"
            let directory = backupURL.deletingLastPathComponent()
            try LegacyLibrarySnapshot.writeDurable(data, to: directory.appendingPathComponent(rawName))
            var recovery: [LegacyLibrarySnapshotManifest.Source] = []
            for (suffix, raw) in rawSources.dropFirst() {
                let name = rawName + suffix
                if let raw { try LegacyLibrarySnapshot.writeDurable(raw, to: directory.appendingPathComponent(name)) }
                recovery.append(LegacyLibrarySnapshot.source("video-index" + suffix, raw, records: nil,
                    interpretation: "superseded-raw-unreadable", backupRelativePath: raw == nil ? nil : name))
            }
            return Result(videos: [], initialized: false, backupData: data, recordCount: nil,
                          interpretation: "superseded-raw-unreadable", backupRelativePath: rawName,
                          recoverySources: recovery)
        }
    }

    private static func read(sourceURL: URL, backupURL: URL, requiresIndex: Bool) throws -> Result {
        do { _ = try FileManager.default.attributesOfItem(atPath: sourceURL.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return Result(videos: [], initialized: false, backupData: nil, recordCount: 0,
                          interpretation: "absent", backupRelativePath: nil, recoverySources: [])
        }
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(sourceURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard opened == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let db { sqlite3_close(db) }
            throw LegacyLibraryCaptureError.database(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3000)
        try execute("BEGIN;", db)
        defer { try? execute("ROLLBACK;", db) }
        // Pin the read view before backup. Decode errors must still leave the
        // exact raw SQLite view available for recovery.
        let pin = try prepare("SELECT count(*) FROM sqlite_schema;", db)
        defer { sqlite3_finalize(pin) }
        guard sqlite3_step(pin) == SQLITE_ROW else { throw error(db) }
        try backup(db, to: backupURL)
        if !requiresIndex {
            return Result(videos: [], initialized: false, backupData: try Data(contentsOf: backupURL), recordCount: nil,
                          interpretation: "superseded-consistent-backup",
                          backupRelativePath: backupURL.lastPathComponent, recoverySources: [])
        }
        let columns = try tableColumns(db)
        let required: Set<String> = ["sort_index", "id", "title", "path", "is_favorite", "last_used", "tags_json"]
        guard required.isSubset(of: columns) else {
            throw LegacyLibraryCaptureError.invalidPayload("wallpapers schema")
        }
        let optional = ["thumbnail_path", "static_frame_path", "file_size", "duration", "resolution", "first_indexed_at_reference"]
        let sql = "SELECT id,title,path,is_favorite,last_used,tags_json," +
            optional.map { columns.contains($0) ? $0 : "NULL" }.joined(separator: ",") +
            " FROM wallpapers ORDER BY sort_index ASC;"
        let statement = try prepare(sql, db)
        defer { sqlite3_finalize(statement) }
        var videos: [VideoWallpaper] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            guard let id = string(statement, 0), !id.isEmpty, let title = string(statement, 1),
                  let path = string(statement, 2), !path.isEmpty,
                  let tagsJSON = string(statement, 5), let tagsData = tagsJSON.data(using: .utf8),
                  let tags = try? JSONDecoder().decode([String].self, from: tagsData) else {
                throw LegacyLibraryCaptureError.invalidPayload("wallpapers row")
            }
            videos.append(VideoWallpaper(
                id: id, title: title, path: path, thumbnailPath: string(statement, 6), staticFramePath: string(statement, 7),
                isFavorite: sqlite3_column_int(statement, 3) != 0,
                lastUsed: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)), tags: tags,
                fileSize: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 8),
                duration: sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 9)),
                resolution: string(statement, 10),
                firstIndexedAt: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil
                    : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 11))))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw error(db) }
        let meta = try prepare("SELECT value FROM meta WHERE key='library_initialized' LIMIT 1;", db)
        defer { sqlite3_finalize(meta) }
        let metaStep = sqlite3_step(meta)
        guard metaStep == SQLITE_ROW || metaStep == SQLITE_DONE else { throw error(db) }
        let initialized = (metaStep == SQLITE_ROW && string(meta, 0) == "1") || !videos.isEmpty
        return Result(videos: videos, initialized: initialized, backupData: try Data(contentsOf: backupURL),
                      recordCount: videos.count, interpretation: "authoritative-consistent-backup",
                      backupRelativePath: backupURL.lastPathComponent, recoverySources: [])
    }

    private static func tableColumns(_ db: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(wallpapers);", db)
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let name = string(statement, 1) { columns.insert(name) }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw error(db) }
        return columns
    }

    private static func backup(_ source: OpaquePointer, to url: URL) throws {
        var target: OpaquePointer?
        guard sqlite3_open_v2(url.path, &target, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let target else {
            if let target { sqlite3_close(target) }
            throw LegacyLibraryCaptureError.database("backup destination open failed")
        }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", source, "main") else { throw error(target) }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE, finish == SQLITE_OK else { throw error(target) }
        // A portable backup is a closed single file. Its header must not retain
        // WAL mode, which would recreate sidecars when a later reader opens it.
        try execute("PRAGMA journal_mode=DELETE;", target)
    }

    private static func prepare(_ sql: String, _ db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error(db) }
        return statement
    }

    private static func execute(_ sql: String, _ db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error(db) }
    }

    private static func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private static func error(_ db: OpaquePointer) -> LegacyLibraryCaptureError {
        .database(String(cString: sqlite3_errmsg(db)))
    }
}
