import Foundation
import SQLite3

@main struct UserCollectionsStoreHarness {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let store = UserCollectionsStore(url: root.appendingPathComponent("relations.sqlite3"))
        var checks: [String: Bool] = [:]
        let initial = try await store.snapshot()
        let epoch = initial.resetEpoch
        checks["freshDatabaseHasNoMigrationOrRelationships"] = initial.revision == 0 && initial.migrationManifestID == nil && initial.playlists.isEmpty
        let a = WallpaperReference(provider: .videoLibrary, sourceID: "42")
        let b = WallpaperReference(provider: .steamWorkshop, sourceID: "42")
        let synthetic = WallpaperReference(provider: .steamWorkshop, sourceID: "video:风景:α/part")
        let decoded = try JSONDecoder().decode(WallpaperReference.self, from: JSONEncoder().encode(synthetic))
        checks["opaqueIdentityRoundTripsAndNamespacesDoNotCollide"] = a != b
            && WallpaperReference(storageKey: synthetic.storageKey) == synthetic
            && decoded == synthetic
        let nfc = WallpaperReference(provider: .steamWorkshop, sourceID: "video:é")
        let nfd = WallpaperReference(provider: .steamWorkshop, sourceID: "video:e\u{301}")
        checks["opaqueIDHashAndStorageUseTheSameExactUTF8Identity"] = nfc != nfd && Set([nfc,nfd]).count == 2
            && nfc.storageKey != nfd.storageKey && WallpaperReference(storageKey: nfc.storageKey) == nfc
            && WallpaperReference(storageKey: nfd.storageKey) == nfd
        checks["noncanonicalStorageKeysAreRejected"] = WallpaperReference(storageKey: "videoLibrary:YR==") == nil
        let date = Date(timeIntervalSince1970: 100)
        let playlist = WallpaperPlaylist(name: "混合列表", createdAt: date, sidebarRank: 0)
        let duplicateName = WallpaperPlaylist(name: "混合列表", createdAt: date, sidebarRank: 1)
        _ = try await store.apply(.createPlaylist(playlist), expectedEpoch: epoch)
        var state = try await store.apply(.createPlaylist(duplicateName), expectedEpoch: epoch)
        checks["sameNamePlaylistsHaveIndependentUUIDs"] = state.playlists.count == 2 && state.playlists[0].id != state.playlists[1].id
        let originalMetadata = state.playlists.first { $0.id == playlist.id }!.metadata
        var invalidMetadata = originalMetadata; invalidMetadata.name = " \n "
        do {
            _ = try await store.apply(.editPlaylistMetadata(id: playlist.id, expected: originalMetadata,
                replacement: invalidMetadata, coverAsset: nil, at: date), expectedEpoch: epoch)
            checks["invalidNameIsAtomic"] = false
        } catch UserCollectionsError.invalidName { checks["invalidNameIsAtomic"] = try await store.snapshot() == state }
        func item(_ ref: WallpaperReference, available: Bool = true) -> WallpaperOrganizationItem {
            WallpaperOrganizationItem(reference: ref, locator: WallpaperLocator(path: "/offline/\(ref.sourceID)", titleHint: ref.sourceID, mediaKind: .video), isPublishedLocally: true, isAvailable: available)
        }
        do {
            _ = try await store.apply(.addMembers(playlist.id, [item(a), item(b, available: false)], date), expectedEpoch: epoch)
            checks["mixedEligibilityRollsBackEveryMemberAndLocator"] = false
        } catch UserCollectionsError.unavailableForOrganization {
            checks["mixedEligibilityRollsBackEveryMemberAndLocator"] = try await store.snapshot() == state
        }
        state = try await store.apply(.addMembers(playlist.id, [item(a), item(b), item(a)], date), expectedEpoch: epoch)
        checks["memberDedupPreservesProviderIdentityAndInsertionOrder"] = state.members.map(\.reference) == [a,b] && state.members.map(\.position) == [0,1]
        let remote = WallpaperOrganizationItem(reference: synthetic, locator: WallpaperLocator(), isPublishedLocally: false, isAvailable: true)
        do {
            _ = try await store.apply(.setFavorite(remote, true, date), expectedEpoch: epoch)
            checks["remoteFavoriteCannotBypassDownloadRequirement"] = false
        } catch UserCollectionsError.unavailableForOrganization { checks["remoteFavoriteCannotBypassDownloadRequirement"] = try await store.snapshot() == state }
        _ = try await store.apply(.setFavorite(item(a), true, Date(timeIntervalSince1970: 50)), expectedEpoch: epoch)
        _ = try await store.apply(.setFavorite(item(b), true, date), expectedEpoch: epoch)
        let token = try await store.startHistorySession(expectedEpoch: epoch)
        _ = try await store.recordSuccessfulUse(a, locator: nil, token: token, sequence: 1, at: date)
        _ = try await store.recordSuccessfulUse(b, locator: nil, token: token, sequence: 2, at: Date(timeIntervalSince1970: 20))
        state = try await store.apply(.linkAlias(WallpaperReferenceAlias(alias: a, canonical: b, proof: .publishedDownload), Date(timeIntervalSince1970: 200)), expectedEpoch: epoch)
        checks["aliasMembershipMergeUpdatesModifiedTime"] = state.playlists.first(where: { $0.id == playlist.id })?.modifiedAt == Date(timeIntervalSince1970: 200)
        checks["lateAliasMergesMembershipAtEarliestPosition"] = state.members.count == 1 && state.members[0].reference == b && state.members[0].position == 0
        checks["lateAliasPreservesEarliestKnownFavorite"] = state.favorites.count == 1 && state.favorites[0].reference == b && state.favorites[0].favoritedAt == Date(timeIntervalSince1970: 50)
        checks["lateAliasPreservesLatestSuccessEvenWhenClockMovesBack"] = state.recent.count == 1 && state.recent[0].reference == b && state.recent[0].commitSequence == 2 && state.recent[0].lastSuccessfulUseAt == Date(timeIntervalSince1970: 20)
        checks["canonicalLocatorIsNotOverwrittenByBackingHint"] = state.locators.count == 1 && state.locators[0].reference == b
        state = try await store.apply(.linkAlias(WallpaperReferenceAlias(alias: a, canonical: b, proof: .publishedDownload), Date(timeIntervalSince1970: 300)), expectedEpoch: epoch)
        checks["duplicateAliasDoesNotChangePlaylistModificationTime"] = state.playlists.first(where: { $0.id == playlist.id })?.modifiedAt == Date(timeIntervalSince1970: 200)
        _ = try await store.apply(.linkAlias(WallpaperReferenceAlias(alias: synthetic, canonical: a, proof: .restoredSourceRecord), date), expectedEpoch: epoch)
        state = try await store.apply(.addMembers(playlist.id, [item(synthetic)], date), expectedEpoch: epoch)
        checks["aliasChainsDoNotCreateDuplicateMembers"] = state.members.count == 1 && state.members[0].reference == b
        let beforeCanonicalRepeat = state
        state = try await store.apply(.addMembers(playlist.id, [item(a), item(b)], date), expectedEpoch: epoch)
        checks["addingMultipleAliasesCannotDuplicateCanonicalIdentity"] = state.members == beforeCanonicalRepeat.members
            && state.playlists == beforeCanonicalRepeat.playlists
        state = try await store.apply(.setFavorite(item(a, available: false), false, date), expectedEpoch: epoch)
        checks["offlineExistingFavoriteCanBeRemovedByAlias"] = state.favorites.isEmpty
        for sequence in 3...53 {
            _ = try await store.recordSuccessfulUse(WallpaperReference(provider: .staticImageLibrary, sourceID: String(sequence)), locator: nil,
                token: token, sequence: UInt64(sequence), at: Date(timeIntervalSince1970: Double(100-sequence)))
        }
        state = try await store.snapshot()
        checks["recentIsBoundedToFiftyByCommitOrder"] = state.recent.count == 50 && state.recent.first?.reference.sourceID == "53" && state.recent.last?.reference.sourceID == "4"
        let duplicate = try await store.recordSuccessfulUse(a, locator: nil, token: token, sequence: 53, at: Date())
        let stale = try await store.recordSuccessfulUse(a, locator: nil, token: token, sequence: 2, at: Date())
        let afterDuplicate = try await store.snapshot()
        checks["duplicateAndLateSuccessAreNoOps"] = !duplicate && !stale && afterDuplicate == state
        let replacement = try await store.startHistorySession(expectedEpoch: epoch)
        let oldPublisher = try await store.recordSuccessfulUse(a, locator: nil, token: token, sequence: 54, at: Date())
        checks["replacementSubscriberRevokesOldMetadataPublisher"] = !oldPublisher
        _ = try await store.recordSuccessfulUse(a, locator: nil, token: replacement, sequence: 1, at: date)
        state = try await store.apply(.deletePlaylist(playlist.id), expectedEpoch: epoch)
        checks["deletePlaylistCascadesOnlyItsMembers"] = state.playlists.count == 1 && state.members.isEmpty && !state.recent.isEmpty
        let reopened = UserCollectionsStore(url: root.appendingPathComponent("relations.sqlite3"))
        checks["durableReopenMatchesThePublishedSnapshot"] = try await reopened.snapshot() == state
        let reset = try await reopened.reset(expectedEpoch: epoch)
        checks["resetRevokesEpochAndPreservesCompletionMarker"] = reset.resetEpoch != epoch && reset.playlists.isEmpty && reset.recent.isEmpty && reset.aliases.isEmpty && reset.migrationManifestID == "reset-complete"
        do {
            _ = try await store.apply(.createPlaylist(playlist), expectedEpoch: epoch)
            checks["otherConnectionCannotWriteUsingPreResetEpoch"] = false
        } catch UserCollectionsError.staleResetEpoch { checks["otherConnectionCannotWriteUsingPreResetEpoch"] = true }
        do {
            _ = try await store.recordSuccessfulUse(a, locator: nil, token: replacement, sequence: 2, at: date)
            checks["resetRejectsLateHistory"] = false
        } catch UserCollectionsError.staleResetEpoch { checks["resetRejectsLateHistory"] = true }
        let migration = UserCollectionsStore(url: root.appendingPathComponent("migration.sqlite3"))
        let start = try await migration.snapshot()
        var payload = LibraryCollectionsImport()
        payload.playlists = [playlist]
        payload.members = [WallpaperPlaylistMember(playlistID: UUID(), reference: a, position: 0, addedAt: date)]
        do {
            _ = try await migration.installMigration(payload, manifestID: "input-A", expectedEpoch: start.resetEpoch)
            checks["failedMigrationPublishesNeitherPartialRowsNorMarker"] = false
        } catch UserCollectionsError.missingPlaylist { checks["failedMigrationPublishesNeitherPartialRowsNorMarker"] = try await migration.snapshot() == start }
        payload.members[0] = WallpaperPlaylistMember(playlistID: playlist.id, reference: a, position: 0, addedAt: date)
        payload.favorites = [WallpaperFavorite(reference: a, favoritedAt: nil, migrationOrder: 0)]
        payload.recent = [WallpaperRecentUse(reference: a, lastSuccessfulUseAt: nil, commitSequence: 1, migrationOrder: 0)]
        let installed = try await migration.installMigration(payload, manifestID: "input-A", expectedEpoch: start.resetEpoch)
        checks["offlineMigrationPreservesUnknownTimes"] = installed.favorites.first?.favoritedAt == nil && installed.recent.first?.lastSuccessfulUseAt == nil && installed.members.count == 1
        checks["sameManifestMigrationIsExactlyIdempotent"] = try await migration.installMigration(payload, manifestID: "input-A", expectedEpoch: start.resetEpoch) == installed
        do {
            _ = try await migration.installMigration(payload, manifestID: "input-B", expectedEpoch: start.resetEpoch)
            checks["differentMigrationCannotOverwriteRelationships"] = false
        } catch UserCollectionsError.migrationConflict { checks["differentMigrationCannotOverwriteRelationships"] = try await migration.snapshot() == installed }
        let concurrent = UserCollectionsStore(url: root.appendingPathComponent("concurrent.sqlite3"))
        let concurrentEpoch = try await concurrent.snapshot().resetEpoch
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for i in 0..<40 {
                group.addTask {
                    let s = try await concurrent.apply(.createPlaylist(WallpaperPlaylist(name: "\(i)", sidebarRank: i)), expectedEpoch: concurrentEpoch)
                    return s.revision == Int64(s.playlists.count)
                }
            }
            var consistent = true
            for try await value in group { consistent = consistent && value }
            let afterConcurrent = try await concurrent.snapshot()
            checks["concurrentCommandsReturnTheirOwnConsistentRevision"] = consistent && afterConcurrent.playlists.count == 40
        }
        let edits = UserCollectionsStore(url: root.appendingPathComponent("edits.sqlite3"))
        let editsEpoch = try await edits.snapshot().resetEpoch
        let t0 = Date(timeIntervalSince1970: 10)
        let t1 = Date(timeIntervalSince1970: 20)
        let t2 = Date(timeIntervalSince1970: 30)
        let t3 = Date(timeIntervalSince1970: 40)
        let named = WallpaperPlaylist(name: "左\u{0000}右", createdAt: t0, sidebarRank: 0)
        var edited = try await edits.apply(.createPlaylist(named), expectedEpoch: editsEpoch)
        checks["embeddedNULInNameIsPreservedRatherThanRejectedOrTruncated"] = edited.playlists[0].name == named.name
        let namedMetadata = edited.playlists[0].metadata
        var renamedMetadata = namedMetadata; renamedMetadata.name = "新\u{0000}名字"
        edited = try await edits.apply(.editPlaylistMetadata(id: named.id, expected: namedMetadata,
            replacement: renamedMetadata, coverAsset: nil, at: t1), expectedEpoch: editsEpoch)
        let reopenedNames = UserCollectionsStore(url: root.appendingPathComponent("edits.sqlite3"), allowCreate: false)
        let nameSnapshot = try await reopenedNames.snapshot()
        checks["renamedNULSurvivesDurableReopen"] = nameSnapshot.playlists[0].name == "新\u{0000}名字"
        edited = try await edits.apply(.addMembers(named.id, [item(a),item(b)], t1), expectedEpoch: editsEpoch)
        checks["memberInsertionUpdatesPlaylistModificationTime"] = edited.playlists[0].modifiedAt == t1
        let beforeRepeat = edited.members
        edited = try await edits.apply(.addMembers(named.id, [item(a)], t2), expectedEpoch: editsEpoch)
        checks["duplicateInsertionPreservesModificationAndAddedTimes"] = edited.playlists[0].modifiedAt == t1 && edited.members == beforeRepeat
        edited = try await edits.apply([.removeMembers(named.id, [a], t2), .addMembers(named.id, [item(a)], t2)], expectedEpoch: editsEpoch)
        checks["removeAndAppendPreservePersistedMemberOrderAndModificationTime"] = edited.playlists[0].modifiedAt == t2
            && edited.members.map(\.reference) == [b,a] && edited.members.map(\.position) == [0,1]
        edited = try await edits.apply(.removeMembers(named.id, [a], t3), expectedEpoch: editsEpoch)
        checks["removalUpdatesModificationTimeAndKeepsSurvivorPosition"] = edited.playlists[0].modifiedAt == t3 && edited.members.map(\.reference) == [b] && edited.members[0].position == 0
        let aliasInstall = UserCollectionsStore(url: root.appendingPathComponent("alias-import.sqlite3"))
        let aliasEpoch = try await aliasInstall.snapshot().resetEpoch
        let x = WallpaperReference(provider: .videoLibrary, sourceID: "x")
        var noncanonical = LibraryCollectionsImport()
        noncanonical.playlists = [playlist]
        noncanonical.aliases = [WallpaperReferenceAlias(alias: a, canonical: b, proof: .publishedDownload)]
        noncanonical.members = [WallpaperPlaylistMember(playlistID: playlist.id, reference: a, position: 3, addedAt: t0),
            WallpaperPlaylistMember(playlistID: playlist.id, reference: b, position: 1, addedAt: t1),
            WallpaperPlaylistMember(playlistID: playlist.id, reference: x, position: 2, addedAt: t2)]
        let canonicalImport = try await aliasInstall.installMigration(noncanonical, manifestID: "alias-input", expectedEpoch: aliasEpoch)
        checks["noncanonicalImportMergesEarliestPositionAndAddedTime"] = canonicalImport.members.map(\.reference) == [b,x] && canonicalImport.members[0].addedAt == t0
        try await aliasInstall.finishMigrationPublication()
        do {
            _ = try await aliasInstall.snapshot()
            checks["sealedStagingOwnerCannotReopenItsOldPath"] = false
        } catch UserCollectionsError.closedForPublication { checks["sealedStagingOwnerCannotReopenItsOldPath"] = true }
        let emptyURL = root.appendingPathComponent("empty-existing.sqlite3")
        try Data().write(to: emptyURL)
        do {
            _ = try await UserCollectionsStore(url: emptyURL, allowCreate: false).snapshot()
            checks["existingEmptyFinalIsNotInitializedOrOverwritten"] = false
        } catch { checks["existingEmptyFinalIsNotInitializedOrOverwritten"] = try Data(contentsOf: emptyURL).isEmpty }
        let absent = root.appendingPathComponent("does-not-exist.sqlite3")
        do {
            _ = try await UserCollectionsStore(url: absent, allowCreate: false).snapshot()
            checks["existingOnlyOpenDoesNotCreateAbsentFile"] = false
        } catch { checks["existingOnlyOpenDoesNotCreateAbsentFile"] = !FileManager.default.fileExists(atPath: absent.path) }
        let unicodeAlias = UserCollectionsStore(url: root.appendingPathComponent("unicode.sqlite3"))
        let unicodeEpoch = try await unicodeAlias.snapshot().resetEpoch
        _ = try await unicodeAlias.apply(.linkAlias(WallpaperReferenceAlias(alias: nfc, canonical: a, proof: .publishedDownload), date), expectedEpoch: unicodeEpoch)
        _ = try await unicodeAlias.apply(.linkAlias(WallpaperReferenceAlias(alias: nfd, canonical: b, proof: .publishedDownload), date), expectedEpoch: unicodeEpoch)
        let unicodeReopened = UserCollectionsStore(url: root.appendingPathComponent("unicode.sqlite3"), allowCreate: false)
        let unicodeState = try await unicodeReopened.snapshot()
        checks["unicodeDistinctAliasesReopenWithoutDictionaryTrap"] = unicodeState.aliases.count == 2 && Set(unicodeState.aliases.map(\.alias)).count == 2
        let cycleURL = root.appendingPathComponent("cycle.sqlite3")
        let cycleStore = UserCollectionsStore(url: cycleURL)
        _ = try await cycleStore.snapshot()
        var cycleDB: OpaquePointer?
        sqlite3_open(cycleURL.path, &cycleDB)
        let cycleSQL = "INSERT INTO aliases VALUES('\(a.storageKey)','\(b.storageKey)','publishedDownload'); INSERT INTO aliases VALUES('\(b.storageKey)','\(a.storageKey)','publishedDownload')"
        precondition(sqlite3_exec(cycleDB, cycleSQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(cycleDB)
        do {
            _ = try await cycleStore.snapshot()
            checks["snapshotRejectsAliasCycleBeforePublishingValues"] = false
        } catch UserCollectionsError.corruptData { checks["snapshotRejectsAliasCycleBeforePublishingValues"] = true }
        let future = root.appendingPathComponent("future.sqlite3")
        var db: OpaquePointer?
        sqlite3_open(future.path, &db)
        sqlite3_exec(db, "CREATE TABLE keep(value TEXT); INSERT INTO keep VALUES('retain'); PRAGMA user_version=999", nil, nil, nil)
        sqlite3_close(db)
        let bytes = try Data(contentsOf: future)
        do {
            _ = try await UserCollectionsStore(url: future).snapshot()
            checks["unknownSchemaDoesNotOverwriteOriginalDatabase"] = false
        } catch UserCollectionsError.unsupportedSchema(999) { checks["unknownSchemaDoesNotOverwriteOriginalDatabase"] = try Data(contentsOf: future) == bytes }
        let corrupt = root.appendingPathComponent("corrupt.sqlite3")
        try Data("invalid database".utf8).write(to: corrupt)
        do {
            _ = try await UserCollectionsStore(url: corrupt).snapshot()
            checks["corruptDatabaseIsNotReinterpretedAsEmpty"] = false
        } catch { checks["corruptDatabaseIsNotReinterpretedAsEmpty"] = try Data(contentsOf: corrupt) == Data("invalid database".utf8) }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
