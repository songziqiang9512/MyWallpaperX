import Foundation
import SQLite3

@_silgen_name("mwx_playlist_fail_next_commit") nonisolated private func failNextCommit()
@_silgen_name("mwx_playlist_commit_failure_count") nonisolated private func commitFailureCount() -> Int32

@main enum LibraryPlaylistMetadataHarness {
    nonisolated static func sql(_ url: URL, _ sql: String) throws -> [[String]] {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        var tail: UnsafePointer<CChar>?
        // Statements in fixture setup intentionally use sqlite3_exec; rows use
        // prepare/step so assertions observe real persisted schema and values.
        if sql.contains(";") {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
            return []
        }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, &tail) == SQLITE_OK, let statement else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "NULL"
            })
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw CocoaError(.fileReadUnknown) }
        return rows
    }

    nonisolated static func legacyDatabase(_ url: URL, epoch: UUID, playlist: WallpaperPlaylist) throws {
        let source = WallpaperReference(provider: .videoLibrary, sourceID: "legacy-backing").storageKey
        let canonical = WallpaperReference(provider: .steamWorkshop, sourceID: "42").storageKey
        let locator = try JSONEncoder().encode(WallpaperLocator(path: "/offline/legacy", mediaKind: .scene))
            .map { String(format: "%02x", $0) }.joined()
        _ = try sql(url, """
            PRAGMA application_id=1297569859; PRAGMA user_version=1;
            CREATE TABLE collections_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE playlists(id TEXT PRIMARY KEY,name TEXT NOT NULL,created_at REAL NOT NULL,modified_at REAL NOT NULL,sidebar_rank INTEGER NOT NULL);
            CREATE TABLE members(playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,ref_key TEXT NOT NULL,position INTEGER NOT NULL,added_at REAL NOT NULL,PRIMARY KEY(playlist_id,ref_key));
            CREATE TABLE favorites(ref_key TEXT PRIMARY KEY,favorited_at REAL,migration_order INTEGER);
            CREATE TABLE recent(ref_key TEXT PRIMARY KEY,last_success_at REAL,commit_sequence INTEGER NOT NULL,migration_order INTEGER);
            CREATE TABLE aliases(alias_key TEXT PRIMARY KEY,canonical_key TEXT NOT NULL,proof TEXT NOT NULL);
            CREATE TABLE locators(ref_key TEXT PRIMARY KEY,payload BLOB NOT NULL);
            INSERT INTO collections_meta VALUES('revision','7'),('reset_epoch','\(epoch.uuidString)'),('recent_sequence','3'),('migration_manifest','legacy-kept');
            INSERT INTO playlists VALUES('\(playlist.id.uuidString)','Legacy',100,120,4);
            INSERT INTO members VALUES('\(playlist.id.uuidString)','\(canonical)',0,110);
            INSERT INTO favorites VALUES('\(canonical)',90,NULL);
            INSERT INTO recent VALUES('\(canonical)',115,3,NULL);
            INSERT INTO aliases VALUES('\(source)','\(canonical)','publishedDownload');
            INSERT INTO locators VALUES('\(canonical)',X'\(locator)');
            """
        )
    }

    nonisolated static func item(_ reference: WallpaperReference) -> WallpaperOrganizationItem {
        .init(reference: reference, locator: .init(path: "/isolated/\(reference.sourceID)", mediaKind: .video),
              isPublishedLocally: true, isAvailable: true)
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let date = Date(timeIntervalSince1970: 100)
        var checks: [String: Bool] = [:]
        let legacyURL = root.appendingPathComponent("legacy.sqlite")
        let legacyEpoch = UUID(), old = WallpaperPlaylist(name: "Legacy", createdAt: date,
            modifiedAt: date.addingTimeInterval(20), sidebarRank: 4)
        try legacyDatabase(legacyURL, epoch: legacyEpoch, playlist: old)
        let legacy = UserCollectionsStore(url: legacyURL, allowCreate: false)
        failNextCommit()
        do {
            _ = try await legacy.snapshot()
            checks["schema-upgrade-commit-failure-is-reported"] = false
        } catch { checks["schema-upgrade-commit-failure-is-reported"] = true }
        let failedVersion = try sql(legacyURL, "PRAGMA user_version")
        let failedColumns = try sql(legacyURL, "PRAGMA table_info(playlists)")
        let failedRows = try sql(legacyURL, "SELECT name,sidebar_rank FROM playlists")
        let failedMarker = try sql(legacyURL, "SELECT value FROM collections_meta WHERE key='migration_manifest'")
        let failedNewTables = try sql(legacyURL, "SELECT name FROM sqlite_master WHERE name IN ('playlist_cover_assets','library_exclusions')")
        checks["failed-v1-upgrade-keeps-original-schema-rows-and-marker"] = failedVersion == [["1"]]
            && failedColumns.count == 5 && failedRows == [["Legacy", "4"]] && failedMarker == [["legacy-kept"]] && failedNewTables.isEmpty
        let upgraded = try await legacy.snapshot()
        let upgradedVersion = try sql(legacyURL, "PRAGMA user_version")
        checks["known-v1-upgrade-retains-uuid-rank-epoch-revision-and-migration-marker"] = upgraded.playlists == [old]
            && upgraded.resetEpoch == legacyEpoch && upgraded.revision == 7 && upgraded.migrationManifestID == "legacy-kept"
            && upgradedVersion == [["2"]]
        checks["old-playlist-and-snapshot-default-to-no-description-auto-cover-and-no-exclusions"] = upgraded.playlists[0].descriptionText == nil
            && upgraded.playlists[0].customCoverAssetID == nil && upgraded.excludedLibraryReferences.isEmpty
        let oldCanonical = WallpaperReference(provider: .steamWorkshop, sourceID: "42")
        let oldMembers: [WallpaperPlaylistMember] = [.init(playlistID: old.id, reference: oldCanonical, position: 0, addedAt: Date(timeIntervalSince1970: 110))]
        let oldFavorites: [WallpaperFavorite] = [.init(reference: oldCanonical, favoritedAt: Date(timeIntervalSince1970: 90), migrationOrder: nil)]
        let oldRecent: [WallpaperRecentUse] = [.init(reference: oldCanonical, lastSuccessfulUseAt: Date(timeIntervalSince1970: 115), commitSequence: 3, migrationOrder: nil)]
        let oldAliases: [WallpaperReferenceAlias] = [.init(alias: .init(provider: .videoLibrary, sourceID: "legacy-backing"), canonical: oldCanonical, proof: .publishedDownload)]
        let oldLocators: [WallpaperReferenceLocator] = [.init(reference: oldCanonical, locator: .init(path: "/offline/legacy", mediaKind: .scene))]
        checks["v1-upgrade-retains-member-favorite-recent-alias-and-locator-fields"] = upgraded.members == oldMembers
            && upgraded.favorites == oldFavorites && upgraded.recent == oldRecent && upgraded.aliases == oldAliases && upgraded.locators == oldLocators
        for (name, corruption) in [
            ("missing-members-table", "DROP TABLE members;"),
            ("invalid-reference", "UPDATE favorites SET ref_key='not-a-reference';"),
            ("invalid-alias-proof", "UPDATE aliases SET proof='unsupported-proof';")
        ] {
            let corruptURL = root.appendingPathComponent(name + ".sqlite")
            try legacyDatabase(corruptURL, epoch: legacyEpoch, playlist: old)
            _ = try sql(corruptURL, corruption)
            let schemaQuery = "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name"
            let originalSchema = try sql(corruptURL, schemaQuery)
            let originalTables = try sql(corruptURL, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            var originalRows: [String: [[String]]] = [:]
            for table in originalTables { originalRows[table[0]] = try sql(corruptURL, "SELECT * FROM \(table[0]) ORDER BY rowid") }
            let corruptStore = UserCollectionsStore(url: corruptURL, allowCreate: false)
            do {
                _ = try await corruptStore.snapshot()
                checks["v1-" + name + "-rejects-before-upgrade-commit"] = false
            } catch { checks["v1-" + name + "-rejects-before-upgrade-commit"] = true }
            var retainedRows: [String: [[String]]] = [:]
            for table in originalTables { retainedRows[table[0]] = try sql(corruptURL, "SELECT * FROM \(table[0]) ORDER BY rowid") }
            // WAL coordination may change physical bytes. The failed upgrade
            // must commit no schema/version or relationship-row changes.
            let retainedSchema = try sql(corruptURL, schemaQuery)
            let retainedVersion = try sql(corruptURL, "PRAGMA user_version")
            let retainedIdentity = try sql(corruptURL, "PRAGMA application_id")
            checks["v1-" + name + "-rolls-back-schema-version-and-all-original-rows"] = retainedVersion == [["1"]]
                && retainedIdentity == [["1297569859"]] && retainedSchema == originalSchema && retainedRows == originalRows
        }
        let oldJSON = Data("{\"id\":\"\(old.id.uuidString)\",\"name\":\"Legacy\",\"createdAt\":0,\"modifiedAt\":0,\"sidebarRank\":4}".utf8)
        let oldDecoded = try JSONDecoder().decode(WallpaperPlaylist.self, from: oldJSON)
        checks["genuinely-old-playlist-json-decodes-missing-new-fields"] = oldDecoded.descriptionText == nil && oldDecoded.customCoverAssetID == nil

        let budgetStore = UserCollectionsStore(url: root.appendingPathComponent("cover-budget.sqlite"))
        let budgetEpoch = try await budgetStore.snapshot().resetEpoch
        let boundedCover = WallpaperPlaylistCoverAsset(imageData: Data([1]), pixelWidth: 512, pixelHeight: 256)
        let budgetPlaylist = WallpaperPlaylist(name: "Bounded copy", createdAt: date, sidebarRank: 0,
            customCoverAssetID: boundedCover.id)
        let budgetState = try await budgetStore.apply(.createPlaylistWithCover(budgetPlaylist, boundedCover), expectedEpoch: budgetEpoch)
        let persistedBoundedCover = try await budgetStore.playlistCoverAsset(id: boundedCover.id, expectedEpoch: budgetEpoch)
        checks["controlled-copy-budget-keeps-normal-512-by-256-metadata-and-bytes"] = persistedBoundedCover == boundedCover
            && budgetState.playlists == [budgetPlaylist]
        for (name, invalid) in [
            ("empty-data", WallpaperPlaylistCoverAsset(imageData: Data(), pixelWidth: 1, pixelHeight: 1)),
            ("zero-width", WallpaperPlaylistCoverAsset(imageData: Data([1]), pixelWidth: 0, pixelHeight: 1)),
            ("zero-height", WallpaperPlaylistCoverAsset(imageData: Data([1]), pixelWidth: 1, pixelHeight: 0)),
            ("oversized-width", WallpaperPlaylistCoverAsset(imageData: Data([1]), pixelWidth: 8192, pixelHeight: 1)),
            ("oversized-height", WallpaperPlaylistCoverAsset(imageData: Data([1]), pixelWidth: 1, pixelHeight: 8192)),
            ("oversized-encoded-bytes", WallpaperPlaylistCoverAsset(imageData: Data(repeating: 0,
                count: WallpaperPlaylistCoverAsset.maxEncodedBytes + 1), pixelWidth: 1, pixelHeight: 1))
        ] {
            let rejected = WallpaperPlaylist(name: "Rejected", createdAt: date, sidebarRank: 1, customCoverAssetID: invalid.id)
            do {
                _ = try await budgetStore.apply(.createPlaylistWithCover(rejected, invalid), expectedEpoch: budgetEpoch)
                checks["store-rejects-" + name + "-without-asset-or-playlist-publication"] = false
            } catch UserCollectionsError.invalidCoverAsset {
                let retained = try await budgetStore.snapshot()
                let absent = try await budgetStore.playlistCoverAsset(id: invalid.id, expectedEpoch: budgetEpoch)
                checks["store-rejects-" + name + "-without-asset-or-playlist-publication"] = retained == budgetState && absent == nil
            }
        }

        let url = root.appendingPathComponent("metadata.sqlite")
        let store = UserCollectionsStore(url: url)
        let initial = try await store.snapshot(), epoch = initial.resetEpoch
        let controller = UserCollectionsController(store: store, snapshot: initial)
        var undoEvents: [(LibraryCollectionsOrganizationState, LibraryCollectionsOrganizationState, String)] = []
        controller.onOrganizationTransaction = { before, after, name, _ in undoEvents.append((before, after, name)) }
        // This gate owns copied bytes and durability, not the App's ImageIO
        // preparation. The native editor gate verifies real image decoding.
        let original = root.appendingPathComponent("selected-copy.data")
        try Data([1,2,3,4]).write(to: original)
        let firstCover = WallpaperPlaylistCoverAsset(imageData: try Data(contentsOf: original), pixelWidth: 2, pixelHeight: 2)
        let id = try await controller.createPlaylist(metadata: .init(name: "  List  ", descriptionText: "  Notes\n  ", customCoverAssetID: firstCover.id),
            coverAsset: firstCover, at: date, expectedEpoch: epoch)
        try FileManager.default.removeItem(at: original)
        var state = controller.snapshot
        checks["create-commits-trimmed-name-description-and-cover-in-one-publication"] = state.playlists[0].id == id
            && state.playlists[0].name == "List" && state.playlists[0].descriptionText == "Notes"
            && state.playlists[0].customCoverAssetID == firstCover.id && undoEvents.count == 1
        checks["controlled-cover-copy-remains-readable-after-original-input-is-removed"] = try await controller.playlistCoverAsset(id: firstCover.id, expectedEpoch: epoch) == firstCover
        let a = WallpaperReference(provider: .videoLibrary, sourceID: "42")
        let b = WallpaperReference(provider: .steamWorkshop, sourceID: "42")
        let expected = state.playlists[0].metadata
        _ = try await controller.perform(.addMembers(id, [item(a)], date.addingTimeInterval(1)))
        let secondCover = WallpaperPlaylistCoverAsset(imageData: Data([5,6,7]), pixelWidth: 3, pixelHeight: 1)
        state = try await controller.editPlaylistMetadata(id: id, expected: expected,
            replacement: .init(name: "Renamed", descriptionText: "\n ", customCoverAssetID: secondCover.id),
            coverAsset: secondCover, at: date.addingTimeInterval(2), expectedEpoch: epoch)
        checks["member-change-does-not-invalidate-an-otherwise-current-metadata-draft"] = state.members.map(\.reference) == [a]
            && state.playlists[0].name == "Renamed" && state.playlists[0].descriptionText == nil
        checks["metadata-edit-emits-one-original-organization-undo-transaction"] = undoEvents.count == 2 && undoEvents.last?.2 == "编辑播放列表"
        let editEvent = undoEvents.last!
        let restored = try await controller.restoreOrganization(expected: editEvent.1, replacement: editEvent.0, expectedEpoch: epoch)
        let retainedSecondCover = try await controller.playlistCoverAsset(id: secondCover.id, expectedEpoch: epoch)
        checks["metadata-undo-restores-original-description-and-asset-with-members-intact"] = restored.playlists[0].metadata == expected
            && restored.members.map(\.reference) == [a] && retainedSecondCover == secondCover
        let copiedID = try await controller.duplicatePlaylist(id, at: date.addingTimeInterval(3))
        state = controller.snapshot
        checks["duplicate-shares-immutable-cover-and-copies-description-with-new-uuid"] = state.playlists.first { $0.id == copiedID }?.customCoverAssetID == firstCover.id
            && state.playlists.first { $0.id == copiedID }?.descriptionText == "Notes"
            && state.members.filter { $0.playlistID == copiedID }.map(\.reference) == [a]
        let beforeFailure = state
        let conflicting = WallpaperPlaylistCoverAsset(id: firstCover.id, imageData: Data([9]), pixelWidth: 1, pixelHeight: 1)
        do {
            _ = try await controller.editPlaylistMetadata(id: id, expected: expected,
                replacement: .init(name: "Wrong", customCoverAssetID: firstCover.id), coverAsset: conflicting, expectedEpoch: epoch)
            checks["same-asset-id-with-different-bytes-cannot-reinterpret-duplicates"] = false
        } catch UserCollectionsError.invalidCoverAsset {
            let unchangedCover = try await controller.playlistCoverAsset(id: firstCover.id, expectedEpoch: epoch)
            checks["same-asset-id-with-different-bytes-cannot-reinterpret-duplicates"] = controller.snapshot == beforeFailure
                && unchangedCover == firstCover
        }
        let thirdCover = WallpaperPlaylistCoverAsset(imageData: Data([8,9]), pixelWidth: 1, pixelHeight: 2)
        failNextCommit()
        do {
            _ = try await controller.editPlaylistMetadata(id: id, expected: expected,
                replacement: .init(name: "Unacknowledged", customCoverAssetID: thirdCover.id), coverAsset: thirdCover, expectedEpoch: epoch)
            checks["commit-failure-rolls-back-new-asset-metadata-and-published-snapshot"] = false
        } catch {
            let disk = try await store.snapshot()
            let missing = try await store.playlistCoverAsset(id: thirdCover.id, expectedEpoch: epoch)
            checks["commit-failure-rolls-back-new-asset-metadata-and-published-snapshot"] = disk == beforeFailure && controller.snapshot == beforeFailure && missing == nil
        }
        let newerMetadata = controller.snapshot.playlists.first { $0.id == id }!.metadata
        var newerReplacement = newerMetadata; newerReplacement.name = "Newer"
        _ = try await controller.perform(.editPlaylistMetadata(id: id, expected: newerMetadata,
            replacement: newerReplacement, coverAsset: nil, at: date))
        let newer = controller.snapshot
        do {
            _ = try await controller.editPlaylistMetadata(id: id, expected: expected, replacement: .init(name: "Stale"), expectedEpoch: epoch)
            checks["competing-metadata-edit-is-rejected-without-overwriting-newer-fields"] = false
        } catch UserCollectionsError.playlistMetadataConflict { checks["competing-metadata-edit-is-rejected-without-overwriting-newer-fields"] = controller.snapshot == newer }

        state = try await controller.perform(.setLibraryExcluded([a,b], true))
        let aRevision = state.excludedLibraryReferences.first { $0.reference == a }!.revision
        checks["same-opaque-id-in-different-providers-has-independent-hide-records"] = state.excludedLibraryReferences.count == 2
        state = try await controller.perform(.clearLibraryExclusion(a, expectedRevision: nil))
        checks["originally-visible-late-restore-cannot-clear-a-new-hide"] = state.excludedLibraryReferences.contains { $0.reference == a }
        state = try await controller.perform(.setLibraryExcluded([a], true))
        let renewed = state.excludedLibraryReferences.first { $0.reference == a }!.revision
        state = try await controller.perform(.clearLibraryExclusion(a, expectedRevision: aRevision))
        checks["repeated-hide-revokes-an-earlier-success-receipt"] = renewed > aRevision
            && state.excludedLibraryReferences.first { $0.reference == a }?.revision == renewed
        state = try await controller.perform(.setLibraryExcluded([b], true))
        let bRevision = state.excludedLibraryReferences.first { $0.reference == b }!.revision
        state = try await controller.perform(.linkAlias(.init(alias: a, canonical: b, proof: .publishedDownload), date))
        checks["alias-or-merges-hide-records-and-keeps-the-newer-hide-identity"] = state.excludedLibraryReferences == [.init(reference: b, revision: bRevision)]
        state = try await controller.perform(.clearLibraryExclusion(a, expectedRevision: renewed))
        checks["old-backing-restore-cannot-clear-a-later-canonical-hide"] = state.excludedLibraryReferences == [.init(reference: b, revision: bRevision)]
        state = try await controller.perform(.clearLibraryExclusion(a, expectedRevision: bRevision))
        checks["matching-explicit-restore-clears-current-canonical-hide-through-alias"] = state.excludedLibraryReferences.isEmpty
        let nfc = WallpaperReference(provider: .staticImageLibrary, sourceID: "é")
        let nfd = WallpaperReference(provider: .staticImageLibrary, sourceID: "e\u{301}")
        state = try await controller.perform(.setLibraryExcluded([nfc,nfd], true))
        checks["exclusion-primary-keys-retain-exact-utf8-source-identity"] = Set(state.excludedLibraryReferences.map(\.reference)) == [nfc,nfd]
        let beforeUndo = state
        state = try await controller.perform(.deletePlaylist(copiedID))
        let expectedUndo = state.organizationState
        state = try await controller.perform(.setLibraryExcluded([b], true))
        state = try await controller.restoreOrganization(expected: expectedUndo, replacement: beforeUndo.organizationState, expectedEpoch: epoch)
        checks["organization-undo-restores-cover-without-undoing-independent-library-hides"] = state.playlists == beforeUndo.playlists
            && state.excludedLibraryReferences.count == 3
        let oldProfile = LibraryCollectionsPersonalSettingsImport(playlists: [WallpaperPlaylist(id: id, name: "Old profile", createdAt: date, sidebarRank: 0)])
        state = try await controller.applyPersonalSettings(oldProfile, commandID: UUID(), expectedOrganization: state.organizationState, expectedEpoch: epoch)
        checks["old-profile-missing-new-fields-preserves-existing-cover-description-and-hides"] = state.playlists.first { $0.id == id }?.customCoverAssetID == firstCover.id
            && state.playlists.first { $0.id == id }?.descriptionText == "Notes" && state.excludedLibraryReferences.count == 3
        var profile = LibraryCollectionsPersonalSettingsImport(playlists: [WallpaperPlaylist(id: id, name: "Explicit automatic", createdAt: date, sidebarRank: 0)],
            playlistMetadataIsExplicit: true, libraryExclusionStates: [.init(reference: b, isExcluded: false)],
            expectedLibraryExclusions: state.excludedLibraryReferences)
        _ = try await controller.perform(.setLibraryExcluded([b], true))
        let laterHide = controller.snapshot
        do {
            _ = try await controller.applyPersonalSettings(profile, commandID: UUID(), expectedOrganization: state.organizationState, expectedEpoch: epoch)
            checks["profile-recovery-cannot-clear-an-intervening-explicit-hide"] = false
        } catch UserCollectionsError.personalSettingsConflict { checks["profile-recovery-cannot-clear-an-intervening-explicit-hide"] = controller.snapshot == laterHide }
        profile.expectedLibraryExclusions = laterHide.excludedLibraryReferences
        state = try await controller.applyPersonalSettings(profile, commandID: UUID(), expectedOrganization: laterHide.organizationState, expectedEpoch: epoch)
        checks["new-profile-explicit-auto-and-false-hide-clear-only-declared-fields"] = state.playlists.first { $0.id == id }?.customCoverAssetID == nil
            && state.playlists.first { $0.id == id }?.descriptionText == nil
            && Set(state.excludedLibraryReferences.map(\.reference)) == [nfc,nfd]
            && state.playlists.first { $0.id == copiedID }?.customCoverAssetID == firstCover.id
        let reopened = UserCollectionsStore(url: url, allowCreate: false)
        let reopenedState = try await reopened.snapshot()
        let reopenedCover = try await reopened.playlistCoverAsset(id: firstCover.id, expectedEpoch: epoch)
        checks["reopen-preserves-metadata-assets-and-hidden-record-identities"] = reopenedState == state && reopenedCover == firstCover
        try await controller.pruneUnreferencedPlaylistCoverAssets(expectedEpoch: epoch)
        let retainedForRedo = try await controller.playlistCoverAsset(id: secondCover.id, expectedEpoch: epoch)
        checks["gc-fifo-guard-skips-after-a-real-organization-undo-transaction"] = retainedForRedo == secondCover
        // Simulate the documented next-startup/no-Undo safe point. The shared
        // live cover remains; the replaced, now unreferenced copy can leave.
        let nextStartup = UserCollectionsController(store: reopened, snapshot: state)
        try await nextStartup.pruneUnreferencedPlaylistCoverAssets(expectedEpoch: epoch)
        let afterGC = try await reopened.snapshot()
        let retainedLiveCover = try await reopened.playlistCoverAsset(id: firstCover.id, expectedEpoch: epoch)
        let removedOldCover = try await reopened.playlistCoverAsset(id: secondCover.id, expectedEpoch: epoch)
        checks["startup-safe-gc-removes-only-unreferenced-copies-without-changing-relationships"] = afterGC == state
            && retainedLiveCover == firstCover && removedOldCover == nil
        try await controller.reset()
        let resetState = controller.snapshot
        let resetCover = try await store.playlistCoverAsset(id: firstCover.id, expectedEpoch: resetState.resetEpoch)
        checks["reset-clears-cover-copies-exclusions-and-old-epoch-actions"] = resetState.excludedLibraryReferences.isEmpty && resetState.playlists.isEmpty
            && resetCover == nil
        do {
            _ = try await controller.editPlaylistMetadata(id: id, expected: expected, replacement: .init(name: "Late"), expectedEpoch: epoch)
            checks["late-editor-after-reset-cannot-recreate-a-deleted-playlist"] = false
        } catch UserCollectionsError.staleResetEpoch { checks["late-editor-after-reset-cannot-recreate-a-deleted-playlist"] = controller.snapshot == resetState }
        checks["both-injected-commit-failures-reached-real-rollback-boundaries"] = commitFailureCount() == 2
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
