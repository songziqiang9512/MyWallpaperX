//
//  WallpaperIndexStore.swift
//  MyWallpaperX
//

import Foundation
import SQLite3

final class WallpaperIndexStore {
    static var startupMigrationReadOnly = false
    static let shared = WallpaperIndexStore()

    nonisolated struct LoadedIndex {
        let wallpapers: [VideoWallpaper]
        let initialized: Bool
    }

    private enum StoreError: Error {
        case openFailed(String)
        case statementPrepareFailed(String)
        case statementStepFailed(String)
        case transactionFailed(String)
        case invalidDatabasePath
        case migrationRecoveryReadOnly
    }

    private let dbURL: URL
    private let migrationReadOnly: Bool
    // SQLite 只承载壁纸索引主表；设置仍留 UserDefaults，避免把轻量配置也拖进数据库事务。
    private let queue = DispatchQueue(label: "com.mywallpaper.persistence.wallpaper-index", qos: .utility)
    private var db: OpaquePointer?

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        migrationReadOnly = Self.startupMigrationReadOnly
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appDir = (appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
        if !migrationReadOnly { try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true) }
        dbURL = appDir.appendingPathComponent("wallpaper_index.sqlite3", isDirectory: false)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func loadWallpapers() throws -> [VideoWallpaper] {
        // 读取时只按 sort_index 还原顺序，不在这里做去重或业务修补。
        // 此方法在调用方线程同步阻塞；启动路径使用 loadInitialIndexAsync。
        try queue.sync { try loadWallpapersInternal() }
    }

    func loadInitialIndex() throws -> LoadedIndex {
        try queue.sync { try loadInitialIndexInternal() }
    }

    func loadInitialIndexAsync(completion: @escaping (Result<LoadedIndex, Error>) -> Void) {
        queue.async {
            let result = Result { try self.loadInitialIndexInternal() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func loadInitialIndexInternal() throws -> LoadedIndex {
        let wallpapers = try loadWallpapersInternal()
        if migrationReadOnly {
            // Old readable rows remain useful even when their optional meta
            // table predates schema repair, which is forbidden in recovery.
            let initialized = (try? selectMetaValue(forKey: "library_initialized")) == "1" || !wallpapers.isEmpty
            return LoadedIndex(wallpapers: wallpapers, initialized: initialized)
        }
        let initialized = try selectMetaValue(forKey: "library_initialized") == "1" || !wallpapers.isEmpty
        return LoadedIndex(wallpapers: wallpapers, initialized: initialized)
    }

    // 完整 SQL 读取由同步查询和初始索引加载共用。
    private func loadWallpapersInternal() throws -> [VideoWallpaper] {
        try openIfNeeded()
        let metadataColumns = ["file_size", "duration", "resolution", "first_indexed_at_reference"].map {
            migrationReadOnly && !hasColumn($0, inTable: "wallpapers") ? "NULL" : $0
        }.joined(separator: ",")
        let sql = """
        SELECT id, title, path, thumbnail_path, static_frame_path, is_favorite, last_used, tags_json, \(metadataColumns)
        FROM wallpapers
        ORDER BY sort_index ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        var items: [VideoWallpaper] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            let id = stringColumn(statement, index: 0) ?? UUID().uuidString
            let title = stringColumn(statement, index: 1) ?? ""
            let path = stringColumn(statement, index: 2) ?? ""
            let thumbnailPath = nullableStringColumn(statement, index: 3)
            let staticFramePath = nullableStringColumn(statement, index: 4)
            let isFavorite = sqlite3_column_int(statement, 5) != 0
            let lastUsed = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            let tags = decodeTags(nullableStringColumn(statement, index: 7))
            let fileSize: Int64? = sqlite3_column_type(statement, 8) != SQLITE_NULL
                ? sqlite3_column_int64(statement, 8)
                : nil
            let duration: Int? = sqlite3_column_type(statement, 9) != SQLITE_NULL
                ? Int(sqlite3_column_int(statement, 9))
                : nil
            let resolution = nullableStringColumn(statement, index: 10)
            let firstIndexedAt = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil
                : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 11))

            items.append(VideoWallpaper(
                id: id, title: title, path: path,
                thumbnailPath: thumbnailPath, staticFramePath: staticFramePath,
                isFavorite: isFavorite, lastUsed: lastUsed, tags: tags,
                fileSize: fileSize, duration: duration, resolution: resolution, firstIndexedAt: firstIndexedAt
            ))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw StoreError.statementStepFailed(lastSQLiteErrorMessage()) }
        return items
    }

    func saveWallpapers(_ wallpapers: [VideoWallpaper]) throws {
        try queue.sync { try saveWallpapersInternal(wallpapers) }
    }

    func saveWallpapersAsync(
        _ wallpapers: [VideoWallpaper],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async {
            let result = Result { try self.saveWallpapersInternal(wallpapers) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func saveWallpapersInternal(_ wallpapers: [VideoWallpaper]) throws {
        guard !migrationReadOnly else { throw StoreError.migrationRecoveryReadOnly }
        // 全量替换采用显式事务，避免中途失败写出半截索引。
        try openIfNeeded()
        // 全量替换 + sort_index 持久化，保证重排后的顺序可跨启动稳定恢复。
        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try exec("DELETE FROM wallpapers;")
            try insertWallpapers(wallpapers)
            try upsertMetaValue("1", forKey: "library_initialized")
            try exec("COMMIT;")
        } catch {
            _ = try? exec("ROLLBACK;")
            throw error
        }
    }

    func resetStore() {
        guard !migrationReadOnly else { return }
        // queue.async 避免在已持有队列锁的调用链上 sync 造成死锁。
        queue.async {
            if let db = self.db {
                sqlite3_close(db)
                self.db = nil
            }
            do {
                try self.removeDatabaseFiles()
            } catch {
                // 删除失败时不崩溃，但记录日志以便排查；下次启动会覆盖旧数据。
#if DEBUG
                NSLog("[WallpaperIndexStore] resetStore: failed to remove database files: %@", error.localizedDescription)
#endif
            }
        }
    }

    private func openIfNeeded() throws {
        // 数据库只在首次需要时打开并初始化 schema，避免启动期无谓占用 SQLite 资源。
        if db != nil { return }

        guard !dbURL.path.isEmpty else {
            throw StoreError.invalidDatabasePath
        }

        var openedDB: OpaquePointer?
        let flags = migrationReadOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        if sqlite3_open_v2(dbURL.path, &openedDB, flags | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = openedDB.map { String(cString: sqlite3_errmsg($0)) } ?? "open database failed"
            if let openedDB {
                sqlite3_close(openedDB)
            }
            throw StoreError.openFailed(message)
        }
        db = openedDB
        guard !migrationReadOnly else { return }

        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA temp_store=MEMORY;")
        try createSchemaIfNeeded()
    }

    private func createSchemaIfNeeded() throws {
        // Schema 保持极简：主表 + meta，避免把设置、缓存等非索引数据混进来。
        try exec(
            """
            CREATE TABLE IF NOT EXISTS wallpapers (
                sort_index INTEGER NOT NULL,
                id TEXT NOT NULL PRIMARY KEY,
                title TEXT NOT NULL,
                path TEXT NOT NULL,
                thumbnail_path TEXT,
                static_frame_path TEXT,
                is_favorite INTEGER NOT NULL,
                last_used REAL NOT NULL,
                tags_json TEXT NOT NULL,
                file_size INTEGER,
                duration INTEGER,
                resolution TEXT,
                first_indexed_at_reference REAL
            );
            """
        )
        // 兼容旧库：file_size 列可能已存在，先检查再补加，避免重复执行时报错。
        let needsFileSizeColumn = !hasColumn("file_size", inTable: "wallpapers")
        if needsFileSizeColumn {
            try exec("ALTER TABLE wallpapers ADD COLUMN file_size INTEGER;")
        }
        if !hasColumn("duration", inTable: "wallpapers") {
            try exec("ALTER TABLE wallpapers ADD COLUMN duration INTEGER;")
        }
        if !hasColumn("resolution", inTable: "wallpapers") {
            try exec("ALTER TABLE wallpapers ADD COLUMN resolution TEXT;")
        }
        if !hasColumn("first_indexed_at_reference", inTable: "wallpapers") {
            try exec("ALTER TABLE wallpapers ADD COLUMN first_indexed_at_reference REAL;")
        }
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_wallpapers_path ON wallpapers(path);")
        try exec("CREATE INDEX IF NOT EXISTS idx_wallpapers_sort ON wallpapers(sort_index);")
        try exec(
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
    }

    private func insertWallpapers(_ wallpapers: [VideoWallpaper]) throws {
        // 逐条绑定参数，确保 JSON tags、布尔值和时间戳都能稳定落盘。
        let sql = """
        INSERT INTO wallpapers (
            sort_index, id, title, path, thumbnail_path, static_frame_path, is_favorite, last_used, tags_json, file_size, duration, resolution, first_indexed_at_reference
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        for (index, wallpaper) in wallpapers.enumerated() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            sqlite3_bind_int64(statement, 1, sqlite3_int64(index))
            bindText(wallpaper.id, to: statement, index: 2)
            bindText(wallpaper.title, to: statement, index: 3)
            bindText(wallpaper.path, to: statement, index: 4)
            bindOptionalText(wallpaper.thumbnailPath, to: statement, index: 5)
            bindOptionalText(wallpaper.staticFramePath, to: statement, index: 6)
            sqlite3_bind_int(statement, 7, wallpaper.isFavorite ? 1 : 0)
            sqlite3_bind_double(statement, 8, wallpaper.lastUsed.timeIntervalSince1970)
            bindText(encodeTags(wallpaper.tags), to: statement, index: 9)
            if let fileSize = wallpaper.fileSize {
                sqlite3_bind_int64(statement, 10, sqlite3_int64(fileSize))
            } else {
                sqlite3_bind_null(statement, 10)
            }
            if let duration = wallpaper.duration {
                sqlite3_bind_int(statement, 11, Int32(duration))
            } else {
                sqlite3_bind_null(statement, 11)
            }
            bindOptionalText(wallpaper.resolution, to: statement, index: 12)
            if let firstIndexedAt = wallpaper.firstIndexedAt {
                sqlite3_bind_double(statement, 13, firstIndexedAt.timeIntervalSinceReferenceDate)
            } else {
                sqlite3_bind_null(statement, 13)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.statementStepFailed(lastSQLiteErrorMessage())
            }
        }
    }

    private func removeDatabaseFiles() throws {
        // 重置索引时要连同 WAL/SHM 一起删掉，否则下次启动可能继续读到旧事务痕迹。
        let fileManager = FileManager.default
        let relatedURLs = [
            dbURL,
            URL(fileURLWithPath: dbURL.path + "-wal"),
            URL(fileURLWithPath: dbURL.path + "-shm")
        ]
        for url in relatedURLs {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func selectMetaValue(forKey key: String) throws -> String? {
        // meta 表只存少量状态标记，适合做“是否已初始化”这类轻量查询。
        let sql = "SELECT value FROM meta WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        bindText(key, to: statement, index: 1)

        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            return nullableStringColumn(statement, index: 0)
        }
        if step == SQLITE_DONE {
            return nil
        }
        throw StoreError.statementStepFailed(lastSQLiteErrorMessage())
    }

    private func upsertMetaValue(_ value: String, forKey key: String) throws {
        // meta 写入使用 upsert，避免初始化状态因为重复执行而失败。
        let sql = """
        INSERT INTO meta (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        bindText(key, to: statement, index: 1)
        bindText(value, to: statement, index: 2)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.statementStepFailed(lastSQLiteErrorMessage())
        }
    }

    private func exec(_ sql: String) throws {
        // 原始 SQL 执行仅用于建表 / 事务 / pragma，不承载业务查询。
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.transactionFailed(lastSQLiteErrorMessage())
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) {
        // 字符串参数统一按 SQLite transient 语义绑定，避免 statement 复用后悬挂指针。
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        // 可选字段统一映射为 NULL，保持 schema 简洁。
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, to: statement, index: index)
    }

    private func nullableStringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cText = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cText)
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        nullableStringColumn(statement, index: index)
    }

    private func encodeTags(_ tags: [String]) -> String {
        // tags 作为 JSON 存储，方便保持顺序并兼容未来扩展字段。
        guard let data = try? JSONEncoder().encode(tags),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private func decodeTags(_ payload: String?) -> [String] {
        // 解码失败直接回空数组，不让损坏的 tags 字段阻塞整条壁纸记录读取。
        guard let payload,
              let data = payload.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tags
    }

    private func hasColumn(_ column: String, inTable table: String) -> Bool {
        // PRAGMA table_info 返回每列的元数据，name 字段在 index 1。
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cName = sqlite3_column_text(statement, 1),
               String(cString: cName) == column {
                return true
            }
        }
        return false
    }

    private func lastSQLiteErrorMessage() -> String {
        guard let db else { return "sqlite error" }
        return String(cString: sqlite3_errmsg(db))
    }
}
