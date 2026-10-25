import Darwin
import Foundation
import SQLite3

@main struct LibraryCollectionsPublicationHarness {
    private static var pinnedReader: OpaquePointer?
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let item = VideoWallpaper(id: "video", title: "Video", path: "/offline/video.mp4", isFavorite: true,
                                  lastUsed: Date(timeIntervalSince1970: 10), tags: ["Shared", "Unlisted"])
        let defaultValues: [String: Any] = [
            "Wallpapers": try encoder.encode([item]), "WallpaperTags": try encoder.encode(["Shared", "Empty"]),
            "SILTags": ["Shared", "Image empty"]
        ]
        let rawDefaults = try PropertyListSerialization.data(fromPropertyList: defaultValues, format: .binary, options: 0)
        let paths = pathsFor(root)
        let backupURL = root.appendingPathComponent("capture-" + mode)
        let capturedAt = mode == "fractional-date" ? Date(timeIntervalSinceReferenceDate: 800_000_000.0000001) : Date(timeIntervalSince1970: 100)
        let captureInput: @Sendable () throws -> LegacyLibrarySnapshot = {
            try LegacyLibrarySnapshot.capture(rawDefaults: rawDefaults, indexURL: root.appendingPathComponent("legacy.sqlite3"),
                staticImageURL: root.appendingPathComponent("sil.json"), backupDirectoryURL: backupURL,
                inputSnapshotURL: paths.inputSnapshotURL, capturedAt: capturedAt)
        }
        func publish() async throws -> LibraryCollectionsMigrationPublicationResult {
            try await LibraryCollectionsMigrationPublication.openOrMigrate(paths: paths, backupDirectoryURL: backupURL,
                captureIfNeeded: captureInput)
        }
        var checks: [String: Bool] = [:]
        switch mode {
        case "view-preferences":
            let result = try await publish()
            let originalInput = try Data(contentsOf: paths.inputSnapshotURL)
            let input = try JSONDecoder().decode(LibraryCollectionsMigrationInput.self, from: originalInput)
            let originalMap = try Data(contentsOf: paths.mappingManifestURL)
            checks["new publication binds preferences to frozen input and mapping"] = result.viewPreferencesSeed?.preferences == input.viewPreferences
                && result.viewPreferencesSeed?.manifest.sourceManifestID == result.snapshot.migrationManifestID
                && result.viewPreferencesSeed?.manifest.tagMappings.map(\.playlistID) == result.snapshot.playlists.map(\.id)
                && result.viewPreferencesWarning == nil
            let playlist = result.snapshot.playlists[0]
            var replacement = playlist.metadata; replacement.name = "Keep user changes"
            let edited = try await result.store.apply(.editPlaylistMetadata(id: playlist.id, expected: playlist.metadata,
                replacement: replacement, coverAsset: nil, at: Date()), expectedEpoch: result.snapshot.resetEpoch)
            func reopen(needsSeed: Bool = true) async throws -> LibraryCollectionsMigrationPublicationResult {
                try await LibraryCollectionsMigrationPublication.openOrMigrate(paths: paths,
                    backupDirectoryURL: backupURL, needsViewPreferencesSeed: needsSeed) {
                    throw CocoaError(.coderReadCorrupt) // A final DB must not recapture live sources.
                }
            }
            let repeated = try await reopen()
            checks["existing final can recover only original seed without rewriting user relations"] = repeated.snapshot == edited
                && repeated.viewPreferencesSeed == result.viewPreferencesSeed
                && repeated.viewPreferencesWarning == nil
            try FileManager.default.removeItem(at: paths.inputSnapshotURL)
            let missing = try await reopen()
            checks["missing frozen input warns without invalidating published DB"] = missing.snapshot == edited
                && missing.viewPreferencesSeed == nil && missing.viewPreferencesWarning != nil
            let bypass = try await reopen(needsSeed: false)
            checks["existing modern preferences bypass old recovery materials"] = bypass.snapshot == edited
                && bypass.viewPreferencesSeed == nil && bypass.viewPreferencesWarning == nil
            try Data("bad saved input".utf8).write(to: paths.inputSnapshotURL)
            let brokenInput = try await reopen()
            checks["corrupt optional preference input cannot invalidate final DB"] = brokenInput.snapshot == edited
                && brokenInput.viewPreferencesSeed == nil && brokenInput.viewPreferencesWarning != nil
            try originalInput.write(to: paths.inputSnapshotURL)
            try Data("bad saved map".utf8).write(to: paths.mappingManifestURL)
            let brokenMap = try await reopen()
            checks["corrupt optional preference map cannot invalidate final DB"] = brokenMap.snapshot == edited
                && brokenMap.viewPreferencesSeed == nil && brokenMap.viewPreferencesWarning != nil
            let wrongInput = LibraryCollectionsMigrationInput(manifestID: "another manifest", capturedAt: capturedAt,
                viewPreferences: input.viewPreferences)
            try encoder.encode(wrongInput).write(to: paths.inputSnapshotURL)
            try originalMap.write(to: paths.mappingManifestURL)
            let mismatch = try await reopen()
            checks["preference seed cannot cross final migration identity"] = mismatch.snapshot == edited
                && mismatch.viewPreferencesSeed == nil && mismatch.viewPreferencesWarning != nil
            struct OldInput: Encodable {
                let manifestID: String
                let capturedAt: Date
                let videos: [LibraryCollectionsMigrationItem]
                let videoTags: [String]
                let staticImages: [LibraryCollectionsMigrationItem]
                let staticImageTags: [String]
                let recent: [LibraryCollectionsMigrationItem]
                let aliases: [WallpaperReferenceAlias]
            }
            let oldInput = try encoder.encode(OldInput(manifestID: input.manifestID, capturedAt: input.capturedAt,
                videos: input.videos, videoTags: input.videoTags, staticImages: input.staticImages,
                staticImageTags: input.staticImageTags, recent: input.recent, aliases: input.aliases))
            let decodedOld = try JSONDecoder().decode(LibraryCollectionsMigrationInput.self, from: oldInput)
            let reencodedOld = try encoder.encode(decodedOld)
            checks["old input missing optional preferences preserves canonical bytes"] = decodedOld.viewPreferences == nil
                && reencodedOld == oldInput
            try oldInput.write(to: paths.inputSnapshotURL)
            let old = try await reopen()
            checks["old input without preferences keeps DB and reports absent seed"] = old.snapshot == edited
                && old.viewPreferencesSeed == nil && old.viewPreferencesWarning != nil
            let reset = try await result.store.reset(expectedEpoch: edited.resetEpoch)
            let resetOpen = try await reopen()
            checks["reset completion never revives frozen page preferences"] = resetOpen.snapshot == reset
                && resetOpen.viewPreferencesSeed == nil && resetOpen.viewPreferencesWarning == nil
        case "publish", "fractional-date":
            let result = try await publish()
            checks["realCaptureToPublishedRelations"] = result.disposition == .published && result.snapshot.playlists.count == 4
                && result.snapshot.members.count == 3 && result.snapshot.favorites.count == 1
            checks["stagingMovedAndLegacyBackupRetained"] = !exists(paths.stagingDatabaseURL)
                && exists(backupURL.appendingPathComponent("manifest.json"))
            checks["publishedMainFileHasAllRowsWithoutWAL"] = try mainRowCount(paths.finalDatabaseURL) == 4
            let originalInput = try Data(contentsOf: paths.inputSnapshotURL)
            let originalMapping = try Data(contentsOf: paths.mappingManifestURL)
            let mapping = try JSONDecoder().decode(LibraryCollectionsMigrationManifest.self, from: originalMapping)
            checks["savedMappingOwnsStablePlaylistUUIDs"] = result.snapshot.playlists.map(\.id) == mapping.tagMappings.map(\.playlistID)
            let id = result.snapshot.playlists[0].id
            let metadata = result.snapshot.playlists[0].metadata
            var replacement = metadata; replacement.name = "User edited"
            let edited = try await result.store.apply(.editPlaylistMetadata(id: id, expected: metadata,
                replacement: replacement, coverAsset: nil, at: Date(timeIntervalSince1970: 200)), expectedEpoch: result.snapshot.resetEpoch)
            let repeated = try await publish()
            checks["repeatDoesNotOverwriteUserEditOrRevision"] = repeated.disposition == .alreadyPublished
                && repeated.snapshot == edited && repeated.snapshot.playlists.first?.name == "User edited"
            checks["repeatDoesNotRewriteInputOrUUIDManifest"] = try Data(contentsOf: paths.inputSnapshotURL) == originalInput
                && Data(contentsOf: paths.mappingManifestURL) == originalMapping
            checks["repeatDoesNotRecreateStaging"] = !exists(paths.stagingDatabaseURL)
        case "checkpoint-retry":
            let prepared = try await prepareStage(captureInput(), paths: paths, pinReader: true)
            let savedMapping = try Data(contentsOf: paths.mappingManifestURL)
            let reader = pinnedReader
            do {
                _ = try await publish()
                checks["pinnedReaderRefusesPublication"] = false
            } catch {
                checks["pinnedReaderRefusesPublication"] = !exists(paths.finalDatabaseURL)
                    && exists(paths.stagingDatabaseURL) && exists(paths.mappingManifestURL)
            }
            sqlite3_exec(reader, "ROLLBACK;", nil, nil, nil)
            sqlite3_close(reader)
            pinnedReader = nil
            let result = try await publish()
            checks["retryPublishesOriginalUUIDs"] = result.disposition == .published
                && result.snapshot.playlists.map(\.id) == prepared.playlists.map(\.id)
            checks["retryPreservesMappingAndClosedMainFile"] = try Data(contentsOf: paths.mappingManifestURL) == savedMapping
                && mainRowCount(paths.finalDatabaseURL) == 4
        case "fsync-retry":
            PublicationFsyncFault.shared.failOnceAfterPublication(finalURL: paths.finalDatabaseURL)
            do {
                _ = try await publish()
                checks["directoryFailureReportedAfterAtomicRename"] = false
            } catch LibraryCollectionsMigrationPublicationError.filesystem(_, let code) {
                checks["directoryFailureReportedAfterAtomicRename"] = code == EIO && exists(paths.finalDatabaseURL)
                    && !exists(paths.stagingDatabaseURL)
            }
            let published = UserCollectionsStore(url: paths.finalDatabaseURL, allowCreate: false)
            let state = try await published.snapshot()
            let id = state.playlists[0].id
            let metadata = state.playlists[0].metadata
            var replacement = metadata; replacement.name = "User edit before durability retry"
            let edited = try await published.apply(.editPlaylistMetadata(id: id, expected: metadata,
                replacement: replacement, coverAsset: nil, at: Date(timeIntervalSince1970: 250)), expectedEpoch: state.resetEpoch)
            let calls = PublicationFsyncFault.shared.publicationSyncCalls
            let retried = try await publish()
            checks["retryRepeatsPublicationDirectorySync"] = PublicationFsyncFault.shared.publicationSyncCalls == calls + 1
            checks["durabilityRetryKeepsUUIDAndUserEdits"] = retried.disposition == .alreadyPublished && retried.snapshot == edited
        case "bad-final", "future-final", "empty-final", "foreign-final":
            let before = try Data(contentsOf: paths.finalDatabaseURL)
            do {
                _ = try await publish()
                checks["invalidFinalRefused"] = false
            } catch {
                checks["invalidFinalRefused"] = true
            }
            checks["invalidFinalBytesPreserved"] = try Data(contentsOf: paths.finalDatabaseURL) == before
            checks["invalidFinalDoesNotCreateStageOrRecoveryRecord"] = !exists(paths.stagingDatabaseURL)
                && !exists(paths.inputSnapshotURL) && !exists(paths.mappingManifestURL)
        case "conflicting-final":
            let final = UserCollectionsStore(url: paths.finalDatabaseURL)
            let initial = try await final.snapshot()
            let before = try await final.apply(.createPlaylist(WallpaperPlaylist(name: "Existing user content", sidebarRank: 0)),
                                               expectedEpoch: initial.resetEpoch)
            do {
                _ = try await publish()
                checks["unrelatedFinalRefused"] = false
            } catch UserCollectionsError.migrationConflict { checks["unrelatedFinalRefused"] = true }
            checks["unrelatedUserStatePreserved"] = try await final.snapshot() == before
            checks["conflictDoesNotCreateStage"] = !exists(paths.stagingDatabaseURL)
        case "lock":
            do {
                _ = try await publish()
                checks["parallelPublisherRefused"] = false
            } catch LibraryCollectionsMigrationPublicationError.publicationBusy { checks["parallelPublisherRefused"] = true }
            checks["busyHasNoDatabaseOrRecords"] = !exists(paths.finalDatabaseURL) && !exists(paths.stagingDatabaseURL)
                && !exists(paths.inputSnapshotURL) && !exists(paths.mappingManifestURL)
        case "lost-mapping":
            let initial = try await prepareStage(captureInput(), paths: paths)
            try FileManager.default.removeItem(at: paths.mappingManifestURL)
            do {
                _ = try await publish()
                checks["lostMappingCannotReplaceStagedUUIDs"] = false
            } catch LibraryCollectionsMigrationPublicationError.stagedDatabaseConflict {
                checks["lostMappingCannotReplaceStagedUUIDs"] = !exists(paths.finalDatabaseURL)
            }
            let retained = try await UserCollectionsStore(url: paths.stagingDatabaseURL, allowCreate: false).snapshot()
            checks["stagedRelationsRemainRecoverable"] = retained == initial
        case "bad-recovery-input":
            try FileManager.default.createDirectory(at: paths.inputSnapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data("not a complete saved input".utf8)
            try data.write(to: paths.inputSnapshotURL)
            do {
                _ = try await publish()
                checks["corruptInputRefused"] = false
            } catch { checks["corruptInputRefused"] = !exists(paths.finalDatabaseURL) && !exists(paths.stagingDatabaseURL) }
            checks["corruptInputPreserved"] = try Data(contentsOf: paths.inputSnapshotURL) == data
        case "bad-recovery-map":
            try encoder.encode(captureInput().migrationInput).write(to: paths.inputSnapshotURL)
            let data = Data("not a complete map".utf8)
            try data.write(to: paths.mappingManifestURL)
            do {
                _ = try await publish()
                checks["corruptMapRefused"] = false
            } catch { checks["corruptMapRefused"] = !exists(paths.finalDatabaseURL) && !exists(paths.stagingDatabaseURL) }
            checks["corruptMapPreserved"] = try Data(contentsOf: paths.mappingManifestURL) == data
        default: fatalError("Unknown mode")
        }
        print(String(decoding: try encoder.encode(checks), as: UTF8.self))
    }

    private static func pathsFor(_ root: URL) -> LibraryCollectionsMigrationPublicationPaths {
        let directory = root.appendingPathComponent("migration")
        return LibraryCollectionsMigrationPublicationPaths(
            inputSnapshotURL: directory.appendingPathComponent("source-input.json"),
            mappingManifestURL: directory.appendingPathComponent("mapping.json"),
            stagingDatabaseURL: directory.appendingPathComponent("relations.staged.sqlite3"),
            finalDatabaseURL: directory.appendingPathComponent("relations.sqlite3"),
            publicationLockURL: directory.appendingPathComponent("publication.lock"))
    }

    private static func prepareStage(_ capture: LegacyLibrarySnapshot,
                                     paths: LibraryCollectionsMigrationPublicationPaths, pinReader: Bool = false) async throws -> UserCollectionsSnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let input = capture.migrationInput
        let map = try LibraryCollectionsMigration.prepareManifest(for: input)
        try encoder.encode(input).write(to: paths.inputSnapshotURL)
        try encoder.encode(map).write(to: paths.mappingManifestURL)
        let migration = try LibraryCollectionsMigration.build(input, manifest: map)
        var store: UserCollectionsStore? = UserCollectionsStore(url: paths.stagingDatabaseURL)
        let epoch = try await store!.snapshot().resetEpoch
        let installed = try await store!.installMigration(migration.payload, manifestID: input.manifestID, expectedEpoch: epoch)
        if pinReader {
            precondition(sqlite3_open_v2(paths.stagingDatabaseURL.path, &pinnedReader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
            precondition(sqlite3_exec(pinnedReader, "BEGIN; SELECT * FROM playlists;", nil, nil, nil) == SQLITE_OK)
        }
        // Deinit closes the test's preparation handle without invoking the
        // publication checkpoint. A reader below can pin the recovery WAL view.
        store = nil
        return installed
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private static func mainRowCount(_ url: URL) throws -> Int {
        var db: OpaquePointer?
        precondition(sqlite3_open_v2("file:" + url.path + "?immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM playlists", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        precondition(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }
}

// Controlled OS leaf only. All Store, capture, install, rename and retry logic
// above comes from product sources; ordinary calls still execute real fsync.
nonisolated final class PublicationFsyncFault: @unchecked Sendable {
    static let shared = PublicationFsyncFault()
    private let lock = NSLock()
    private var finalURL: URL?
    private var failures = 0
    private var calls = 0

    var publicationSyncCalls: Int { lock.lock(); defer { lock.unlock() }; return calls }

    func failOnceAfterPublication(finalURL: URL) {
        lock.lock(); defer { lock.unlock() }
        self.finalURL = finalURL
        failures = 1
        calls = 0
    }

    func sync(_ descriptor: Int32, directory: URL) -> Int32 {
        lock.lock()
        if let finalURL, directory == finalURL.deletingLastPathComponent(),
           FileManager.default.fileExists(atPath: finalURL.path) {
            calls += 1
            if failures > 0 {
                failures -= 1
                lock.unlock()
                errno = EIO
                return -1
            }
        }
        lock.unlock()
        return Darwin.fsync(descriptor)
    }
}
