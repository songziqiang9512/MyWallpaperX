import Darwin
import Foundation

nonisolated struct LibraryCollectionsMigrationPublicationPaths: Sendable {
    let inputSnapshotURL: URL
    let mappingManifestURL: URL
    let stagingDatabaseURL: URL
    let finalDatabaseURL: URL
    let publicationLockURL: URL
}

nonisolated struct LibraryCollectionsMigrationPublicationResult: Sendable {
    enum Disposition: String, Sendable { case published, alreadyPublished }
    let store: UserCollectionsStore
    let snapshot: UserCollectionsSnapshot
    let disposition: Disposition
    var viewPreferencesSeed: LibraryCollectionsViewPreferencesSeed? = nil
    var viewPreferencesWarning: String? = nil
}

nonisolated enum LibraryCollectionsMigrationPublicationError: Error, LocalizedError {
    case invalidPaths
    case publicationBusy
    case recoveryInputMissing
    case stagedDatabaseConflict
    case filesystem(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPaths: return "迁移文件路径重叠，或暂存库与最终库不在同一目录。"
        case .publicationBusy: return "另一个资料库迁移仍在进行，请稍后重试。"
        case .recoveryInputMissing: return "迁移恢复材料已存在，但缺少完整输入；已保留原件，不能重新读取可能已清洗的资料库。"
        case .stagedDatabaseConflict: return "迁移暂存库已变化或不匹配，不能覆盖。"
        case .filesystem(let action, let code): return "迁移文件操作失败：\(action)（\(code)）"
        }
    }
}

/// Standalone publication only. App startup supplies its frozen source snapshot
/// and the explicit recovery paths while the legacy writers are not admitted.
/// A staged handle never escapes; the returned owner opens the final path anew.
nonisolated enum LibraryCollectionsMigrationPublication {
    /// This one lease covers initial capture as well as publication. The
    /// closure is deliberately lazy: a published/reset database never asks an
    /// obsolete UserDefaults or source index to prove its validity again.
    @concurrent static func openOrMigrate(
        paths: LibraryCollectionsMigrationPublicationPaths,
        backupDirectoryURL: URL,
        needsViewPreferencesSeed: Bool = true,
        captureIfNeeded: @Sendable () async throws -> LegacyLibrarySnapshot
    ) async throws -> LibraryCollectionsMigrationPublicationResult {
        try validate(paths)
        let lease = try PublicationLease.acquire(paths.publicationLockURL)
        defer { lease.release() }
        if try exists(paths.finalDatabaseURL) {
            return try await existingFinal(paths, manifestID: nil, needsViewPreferencesSeed: needsViewPreferencesSeed)
        }
        if let input: LibraryCollectionsMigrationInput = try readRecord(paths.inputSnapshotURL) {
            return try await publishInput(input, paths: paths, needsViewPreferencesSeed: needsViewPreferencesSeed)
        }
        guard try !exists(paths.stagingDatabaseURL), try !exists(paths.mappingManifestURL), try !exists(backupDirectoryURL) else {
            throw LibraryCollectionsMigrationPublicationError.recoveryInputMissing
        }
        let captured = try await captureIfNeeded()
        try Task.checkCancellation()
        guard let input: LibraryCollectionsMigrationInput = try readRecord(paths.inputSnapshotURL),
              input == captured.migrationInput else {
            throw LibraryCollectionsMigrationPublicationError.recoveryInputMissing
        }
        return try await publishInput(input, paths: paths, needsViewPreferencesSeed: needsViewPreferencesSeed)
    }

    private static func publishInput(_ input: LibraryCollectionsMigrationInput,
                                     paths: LibraryCollectionsMigrationPublicationPaths,
                                     needsViewPreferencesSeed: Bool) async throws -> LibraryCollectionsMigrationPublicationResult {
        try Task.checkCancellation()
        let saved: LibraryCollectionsMigrationManifest? = try readRecord(paths.mappingManifestURL)
        if saved == nil, try exists(paths.stagingDatabaseURL) {
            throw LibraryCollectionsMigrationPublicationError.stagedDatabaseConflict
        }
        let manifest = try LibraryCollectionsMigration.prepareManifest(for: input, reusing: saved)
        if saved == nil { try writeRecord(manifest, to: paths.mappingManifestURL) }
        let migration = try LibraryCollectionsMigration.build(input, manifest: manifest)
        let stagedExists = try exists(paths.stagingDatabaseURL)
        let staged = UserCollectionsStore(url: paths.stagingDatabaseURL, allowCreate: !stagedExists)
        do {
            let initial = try await staged.snapshot()
            let installed = try await staged.installMigration(migration.payload, manifestID: input.manifestID,
                                                               expectedEpoch: initial.resetEpoch)
            // A staging file belongs exclusively to this migration. If its saved
            // mapping disappeared or an edit reached it, do not publish new UUIDs
            // over an older relationship set merely because the source ID agrees.
            let persistedPlaylists = migration.payload.playlists.map { playlist in
                WallpaperPlaylist(id: playlist.id, name: playlist.name,
                    createdAt: Date(timeIntervalSince1970: playlist.createdAt.timeIntervalSince1970),
                    modifiedAt: Date(timeIntervalSince1970: playlist.modifiedAt.timeIntervalSince1970),
                    sidebarRank: playlist.sidebarRank)
            }
            guard installed.revision == 1, installed.playlists == persistedPlaylists else {
                throw LibraryCollectionsMigrationPublicationError.stagedDatabaseConflict
            }
            try Task.checkCancellation()
            try await staged.finishMigrationPublication()
            try Task.checkCancellation()
            try requireNoWAL(paths.stagingDatabaseURL)
            // RENAME_EXCL is one same-volume atomic operation and cannot replace
            // a final database that appeared after the check above.
            let moved = paths.stagingDatabaseURL.path.withCString { source in
                paths.finalDatabaseURL.path.withCString { destination in
                    renamex_np(source, destination, UInt32(RENAME_EXCL))
                }
            }
            if moved != 0 {
                let code = errno
                if code == EEXIST {
                    return try await existingFinal(paths, manifestID: input.manifestID, needsViewPreferencesSeed: needsViewPreferencesSeed)
                }
                throw LibraryCollectionsMigrationPublicationError.filesystem("publish database", code)
            }
            try syncDirectory(paths.finalDatabaseURL.deletingLastPathComponent())
            let final = UserCollectionsStore(url: paths.finalDatabaseURL, allowCreate: false)
            let state = try await final.snapshot()
            guard state.migrationManifestID == input.manifestID else { throw UserCollectionsError.migrationConflict }
            var result = LibraryCollectionsMigrationPublicationResult(store: final, snapshot: state, disposition: .published)
            if needsViewPreferencesSeed {
                result.viewPreferencesSeed = input.viewPreferences.map { .init(preferences: $0, manifest: manifest) }
                if result.viewPreferencesSeed == nil { result.viewPreferencesWarning = viewPreferencesUnavailable }
            }
            return result
        } catch {
            // Preserve the original failure and owned recovery files. A failed
            // checkpoint may leave WAL recovery pages; no final path is moved.
            // A sealed actor refuses to reopen even if rename already happened.
            try? await staged.finishMigrationPublication()
            throw error
        }
    }

    private static func existingFinal(_ paths: LibraryCollectionsMigrationPublicationPaths, manifestID: String?,
                                      needsViewPreferencesSeed: Bool) async throws -> LibraryCollectionsMigrationPublicationResult {
        let url = paths.finalDatabaseURL
        let store = UserCollectionsStore(url: url, allowCreate: false)
        let state = try await store.snapshot()
        if let manifestID {
            guard state.migrationManifestID == manifestID else { throw UserCollectionsError.migrationConflict }
        } else {
            guard let marker = state.migrationManifestID, !marker.isEmpty else { throw UserCollectionsError.migrationConflict }
        }
        // A previous rename may have succeeded before directory fsync failed.
        // Confirm that publication is durable on retry before reporting success.
        try syncDirectory(url.deletingLastPathComponent())
        // Subsequent user edits are authoritative. Never reinstall the old payload.
        var result = LibraryCollectionsMigrationPublicationResult(store: store, snapshot: state, disposition: .alreadyPublished)
        guard needsViewPreferencesSeed, state.migrationManifestID != "reset-complete" else { return result }
        // Preferences are optional recovery metadata. A missing/corrupt seed
        // must never invalidate an already published and subsequently edited DB.
        do {
            guard let input: LibraryCollectionsMigrationInput = try readRecord(paths.inputSnapshotURL),
                  input.manifestID == state.migrationManifestID,
                  let manifest: LibraryCollectionsMigrationManifest = try readRecord(paths.mappingManifestURL),
                  let preferences = input.viewPreferences else {
                result.viewPreferencesWarning = viewPreferencesUnavailable
                return result
            }
            _ = try LibraryCollectionsMigration.prepareManifest(for: input, reusing: manifest)
            result.viewPreferencesSeed = .init(preferences: preferences, manifest: manifest)
        } catch {
            result.viewPreferencesWarning = viewPreferencesUnavailable
        }
        return result
    }

    private static let viewPreferencesUnavailable = "旧版界面偏好的冻结恢复材料缺失或无法读取，资料库内容已保留；将使用当前界面设置。"

    private static func validate(_ paths: LibraryCollectionsMigrationPublicationPaths) throws {
        let urls = [paths.inputSnapshotURL, paths.mappingManifestURL, paths.stagingDatabaseURL,
                    paths.finalDatabaseURL, paths.publicationLockURL]
        guard urls.allSatisfy(\.isFileURL) else { throw LibraryCollectionsMigrationPublicationError.invalidPaths }
        let normalized = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        guard Set(normalized).count == urls.count,
              paths.stagingDatabaseURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL ==
                paths.finalDatabaseURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL else {
            throw LibraryCollectionsMigrationPublicationError.invalidPaths
        }
    }

    private static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return false }
    }

    private static func readRecord<T: Decodable>(_ url: URL) throws -> T? {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func writeRecord<T: Encodable>(_ record: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        try syncDirectory(url.deletingLastPathComponent())
    }

    private static func requireNoWAL(_ url: URL) throws {
        let wal = URL(fileURLWithPath: url.path + "-wal")
        if try exists(wal) {
            let attributes = try FileManager.default.attributesOfItem(atPath: wal.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value == 0 else {
                throw LibraryCollectionsMigrationPublicationError.stagedDatabaseConflict
            }
            // SQLite can keep an empty truncated WAL after a successful close.
            // Only this sealed staging database is owned here; dirty pages above
            // are never discarded. The final path has never been opened yet.
            try FileManager.default.removeItem(at: wal)
        }
        let shm = URL(fileURLWithPath: url.path + "-shm")
        if try exists(shm) { try FileManager.default.removeItem(at: shm) }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
        guard descriptor >= 0 else { throw LibraryCollectionsMigrationPublicationError.filesystem("open directory", errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw LibraryCollectionsMigrationPublicationError.filesystem("sync directory", errno) }
    }

    private struct PublicationLease {
        let descriptor: Int32

        static func acquire(_ url: URL) throws -> Self {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let descriptor = url.path.withCString { Darwin.open($0, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR) }
            guard descriptor >= 0 else { throw LibraryCollectionsMigrationPublicationError.filesystem("open migration lock", errno) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                let code = errno
                Darwin.close(descriptor)
                if code == EWOULDBLOCK { throw LibraryCollectionsMigrationPublicationError.publicationBusy }
                throw LibraryCollectionsMigrationPublicationError.filesystem("lock migration", code)
            }
            return Self(descriptor: descriptor)
        }

        func release() {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
            // Keep this stable inode so concurrent retry processes use one lock.
        }
    }
}
