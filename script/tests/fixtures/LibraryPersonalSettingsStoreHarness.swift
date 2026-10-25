import Foundation
import SQLite3

@main struct LibraryPersonalSettingsStoreHarness {
    static func sql(_ url: URL, _ text: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, text, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "FixtureSQL", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
        }
    }
    static func item(_ ref: WallpaperReference) -> WallpaperOrganizationItem {
        .init(reference: ref, locator: .init(path: "/offline/\(ref.storageKey)", mediaKind: .video), isPublishedLocally: true, isAvailable: true)
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 100)
        let a = WallpaperReference(provider: .videoLibrary, sourceID: "42")
        let b = WallpaperReference(provider: .steamWorkshop, sourceID: "42")
        let c = WallpaperReference(provider: .staticImageLibrary, sourceID: "offline")
        let alias = WallpaperReference(provider: .videoLibrary, sourceID: "backing")
        var checks: [String: Bool] = [:]
        let url = root.appendingPathComponent("profile.sqlite")
        let store = UserCollectionsStore(url: url)
        var state = try await store.snapshot(); let epoch = state.resetEpoch
        let first = WallpaperPlaylist(name: "Original", createdAt: date, sidebarRank: 0)
        let untouched = WallpaperPlaylist(name: "Duplicate name", createdAt: date, sidebarRank: 1)
        state = try await store.apply([.createPlaylist(first), .createPlaylist(untouched), .addMembers(first.id, [item(a), item(b)], date),
            .setFavorite(item(a), true, date), .setFavorite(item(b), true, date),
            .linkAlias(.init(alias: alias, canonical: b, proof: .publishedDownload), date)], expectedEpoch: epoch)
        let token = try await store.startHistorySession(expectedEpoch: epoch)
        _ = try await store.recordSuccessfulUse(a, locator: nil, token: token, sequence: 1, at: date)
        let before = try await store.snapshot()
        let imported = WallpaperPlaylist(id: first.id, name: "Duplicate name", createdAt: date, modifiedAt: date.addingTimeInterval(5), sidebarRank: 2)
        let sameNameNewID = WallpaperPlaylist(name: "Duplicate name", createdAt: date, sidebarRank: 3)
        var payload = LibraryCollectionsPersonalSettingsImport(
            playlists: [imported, sameNameNewID],
            members: [.init(playlistID: first.id, reference: b, position: 0, addedAt: date),
                      .init(playlistID: first.id, reference: c, position: 1, addedAt: date),
                      .init(playlistID: first.id, reference: alias, position: 2, addedAt: date)],
            favoriteStates: [.init(reference: alias, isFavorite: false), .init(reference: c, isFavorite: true)],
            locators: [.init(reference: c, locator: .init(path: "/missing/photo.heic", titleHint: "Offline", mediaKind: .image))])
        let command = UUID()
        state = try await store.applyPersonalSettings(payload, commandID: command, expectedOrganization: before.organizationState, expectedEpoch: epoch)
        checks["profile-upserts-by-uuid-and-retains-same-name-independent-playlists"] = state.playlists.count == 3
            && state.playlists.contains(untouched) && state.playlists.contains(imported) && state.playlists.contains(sameNameNewID)
        checks["profile-keeps-existing-member-order-and-appends-only-new-canonical-references"] = state.members.filter { $0.playlistID == first.id }.map(\.reference) == [a,b,c]
        checks["explicit-false-clears-only-its-canonical-favorite-and-missing-state-is-preserved"] = Set(state.favorites.map(\.reference)) == [a,c]
        checks["explicit-offline-restore-keeps-locator-without-downloading-or-file-admission"] = state.locators.first { $0.reference == c }?.locator.path == "/missing/photo.heic"
        checks["profile-never-replaces-recent-or-identity-aliases"] = state.recent == before.recent && state.aliases == before.aliases
        let laterMetadata = state.playlists.first { $0.id == first.id }!.metadata
        var laterReplacement = laterMetadata; laterReplacement.name = "Later user edit"
        let later = try await store.apply(.editPlaylistMetadata(id: first.id, expected: laterMetadata,
            replacement: laterReplacement, coverAsset: nil, at: date), expectedEpoch: epoch)
        let replay = try await store.applyPersonalSettings(payload, commandID: command, expectedOrganization: before.organizationState, expectedEpoch: epoch)
        checks["repeating-committed-profile-command-preserves-later-edits-and-revision"] = replay == later
        payload.favoriteStates = []
        do {
            _ = try await store.applyPersonalSettings(payload, commandID: command, expectedOrganization: later.organizationState, expectedEpoch: epoch)
            checks["same-command-id-cannot-be-reused-with-a-different-payload"] = false
        } catch UserCollectionsError.personalSettingsConflict { checks["same-command-id-cannot-be-reused-with-a-different-payload"] = try await store.snapshot() == later }
        do {
            _ = try await store.applyPersonalSettings(payload, commandID: UUID(), expectedOrganization: before.organizationState, expectedEpoch: epoch)
            checks["profile-recovery-never-overwrites-an-intervening-organization-edit"] = false
        } catch UserCollectionsError.organizationConflict { checks["profile-recovery-never-overwrites-an-intervening-organization-edit"] = try await store.snapshot() == later }
        let legacyA = WallpaperPlaylist(name: " é ", createdAt: date, sidebarRank: 4)
        let legacyB = WallpaperPlaylist(name: "e\u{301}", createdAt: date.addingTimeInterval(600), sidebarRank: 77)
        let upper = WallpaperPlaylist(name: "É", createdAt: date, sidebarRank: 5)
        let legacy = LibraryCollectionsPersonalSettingsImport(playlists: [legacyA,legacyB,upper],
            members: [.init(playlistID: legacyA.id, reference: a, position: 0, addedAt: date), .init(playlistID: legacyB.id, reference: b, position: 0, addedAt: date)],
            legacyOrigins: [.init(playlistID: legacyA.id, sourceKey: "legacy-file", tag: "é"),
                            .init(playlistID: legacyB.id, sourceKey: "legacy-file", tag: "e\u{301}"),
                            .init(playlistID: upper.id, sourceKey: "legacy-file", tag: "É")])
        state = try await store.applyPersonalSettings(legacy, commandID: UUID(), expectedOrganization: later.organizationState, expectedEpoch: epoch)
        checks["legacy-source-tag-map-merges-unicode-equivalent-video-image-tags-without-case-folding"] = state.playlists.contains { $0.id == legacyA.id }
            && !state.playlists.contains { $0.id == legacyB.id } && state.playlists.contains { $0.id == upper.id }
            && state.members.filter { $0.playlistID == legacyA.id }.map(\.reference) == [a,b]
        checks["equivalent-legacy-tags-retain-the-first-declared-creation-and-order"] = state.playlists.first { $0.id == legacyA.id }?.createdAt == date
            && state.playlists.first { $0.id == legacyA.id }?.sidebarRank == legacyA.sidebarRank
        let legacyMetadata = state.playlists.first { $0.id == legacyA.id }!.metadata
        var legacyReplacement = legacyMetadata; legacyReplacement.name = "User renamed legacy list"
        state = try await store.apply(.editPlaylistMetadata(id: legacyA.id, expected: legacyMetadata,
            replacement: legacyReplacement, coverAsset: nil, at: date.addingTimeInterval(10)), expectedEpoch: epoch)
        let preservedLegacy = state.playlists
        let repeatID = WallpaperPlaylist(name: "é", createdAt: date.addingTimeInterval(120), sidebarRank: 99)
        let legacyRepeat = LibraryCollectionsPersonalSettingsImport(playlists: [repeatID],
            legacyOrigins: [.init(playlistID: repeatID.id, sourceKey: "legacy-file", tag: "é")])
        let count = state.playlists.count
        state = try await store.applyPersonalSettings(legacyRepeat, commandID: UUID(), expectedOrganization: state.organizationState, expectedEpoch: epoch)
        checks["separate-user-imports-reuse-the-durable-legacy-tag-uuid-map"] = state.playlists.count == count && !state.playlists.contains { $0.id == repeatID.id }
        checks["legacy-repeat-preserves-user-name-creation-sidebar-order-and-noop-modified-date"] = state.playlists == preservedLegacy
        let v6Metadata = WallpaperPlaylist(id: legacyA.id, name: "Explicit v6 metadata", createdAt: date.addingTimeInterval(240),
            modifiedAt: date.addingTimeInterval(250), sidebarRank: 0)
        state = try await store.applyPersonalSettings(.init(playlists: [v6Metadata]), commandID: UUID(),
            expectedOrganization: state.organizationState, expectedEpoch: epoch)
        checks["schema-six-same-uuid-still-applies-explicit-imported-metadata"] = state.playlists.first { $0.id == legacyA.id } == v6Metadata
        let rollbackPlaylist = WallpaperPlaylist(name: "Rollback", createdAt: date, sidebarRank: 6)
        let failing = LibraryCollectionsPersonalSettingsImport(playlists: [rollbackPlaylist], favoriteStates: [.init(reference: b, isFavorite: true)],
            legacyOrigins: [.init(playlistID: rollbackPlaylist.id, sourceKey: "failed-import", tag: "Rollback")])
        let failureCommand = UUID(), priorFailure = state
        try sql(url, "CREATE TRIGGER profile_fail BEFORE INSERT ON favorites BEGIN SELECT RAISE(ABORT,'controlled profile failure'); END")
        do {
            _ = try await store.applyPersonalSettings(failing, commandID: failureCommand, expectedOrganization: state.organizationState, expectedEpoch: epoch)
            checks["profile-sql-failure-rolls-back-rows-marker-and-legacy-map"] = false
        } catch { checks["profile-sql-failure-rolls-back-rows-marker-and-legacy-map"] = try await store.snapshot() == priorFailure }
        try sql(url, "DROP TRIGGER profile_fail")
        state = try await store.applyPersonalSettings(failing, commandID: failureCommand, expectedOrganization: state.organizationState, expectedEpoch: epoch)
        checks["failed-profile-command-can-retry-and-commit-once"] = state.playlists.contains { $0.id == rollbackPlaylist.id }
        let aliasSafetyBefore = state
        let redirect = LibraryCollectionsPersonalSettingsImport(aliases: [.init(alias: b, canonical: a, proof: .restoredSourceRecord)])
        do {
            _ = try await store.applyPersonalSettings(redirect, commandID: UUID(), expectedOrganization: state.organizationState, expectedEpoch: epoch)
            checks["old-backup-cannot-indirectly-redirect-a-later-canonical-alias"] = false
        } catch UserCollectionsError.personalSettingsConflict { checks["old-backup-cannot-indirectly-redirect-a-later-canonical-alias"] = try await store.snapshot() == aliasSafetyBefore }
        let reverseCycle = LibraryCollectionsPersonalSettingsImport(aliases: [.init(alias: b, canonical: alias, proof: .restoredSourceRecord)])
        do {
            _ = try await store.applyPersonalSettings(reverseCycle, commandID: UUID(), expectedOrganization: state.organizationState, expectedEpoch: epoch)
            checks["backward-backup-alias-cycle-is-rejected-without-changing-current-provenance"] = false
        } catch { checks["backward-backup-alias-cycle-is-rejected-without-changing-current-provenance"] = try await store.snapshot() == aliasSafetyBefore }
        let undoBefore = state.organizationState
        state = try await store.apply(.deletePlaylist(first.id), expectedEpoch: epoch)
        let undoExpected = state.organizationState
        _ = try await store.recordSuccessfulUse(b, locator: .init(path: "/new-hint", mediaKind: .scene), token: token, sequence: 2, at: date)
        let historyAndHints = try await store.snapshot()
        state = try await store.apply(.restoreOrganization(expected: undoExpected, replacement: undoBefore), expectedEpoch: epoch)
        checks["organization-undo-restores-uuid-manual-order-and-offline-relations-despite-new-playback"] = state.organizationState == undoBefore
        checks["organization-undo-preserves-current-history-locators-and-aliases"] = state.recent == historyAndHints.recent && state.locators == historyAndHints.locators && state.aliases == historyAndHints.aliases
        let newerMetadata = state.playlists.first { $0.id == first.id }!.metadata
        var newerReplacement = newerMetadata; newerReplacement.name = "Newer edit"
        let wrong = try await store.apply(.editPlaylistMetadata(id: first.id, expected: newerMetadata,
            replacement: newerReplacement, coverAsset: nil, at: date), expectedEpoch: epoch)
        do {
            _ = try await store.apply(.restoreOrganization(expected: undoBefore, replacement: undoExpected), expectedEpoch: epoch)
            checks["undo-refuses-intervening-organization-edits-atomically"] = false
        } catch UserCollectionsError.organizationConflict { checks["undo-refuses-intervening-organization-edits-atomically"] = try await store.snapshot() == wrong }
        let aliasChanged = try await store.apply(.linkAlias(.init(alias: .init(provider: .pixabay, sourceID: "42"), canonical: b, proof: .explicitUserRelocation), date), expectedEpoch: epoch)
        do {
            _ = try await store.apply(.restoreOrganization(expected: wrong.organizationState, replacement: undoBefore), expectedEpoch: epoch)
            checks["identity-alias-changes-revoke-old-organization-undo"] = false
        } catch UserCollectionsError.organizationConflict { checks["identity-alias-changes-revoke-old-organization-undo"] = try await store.snapshot() == aliasChanged }
        state = try await store.apply(.removeRecent([alias]), expectedEpoch: epoch)
        checks["remove-recent-canonicalizes-alias-and-does-not-change-organization"] = !state.recent.contains { $0.reference == b } && state.organizationState == aliasChanged.organizationState
        state = try await store.apply(.clearRecent, expectedEpoch: epoch)
        let rejected = try await store.recordSuccessfulUse(b, locator: nil, token: token, sequence: 2, at: date)
        checks["clear-recent-never-rolls-back-history-writer-watermark"] = !rejected && state.recent.isEmpty
        _ = try await store.recordSuccessfulUse(b, locator: nil, token: token, sequence: 3, at: date)
        checks["real-new-playback-can-enter-history-after-clear"] = try await store.snapshot().recent.count == 1
        let reset = try await store.reset(expectedEpoch: epoch)
        do {
            _ = try await store.apply(.restoreOrganization(expected: reset.organizationState, replacement: undoBefore), expectedEpoch: epoch)
            checks["old-undo-cannot-restore-relations-after-reset"] = false
        } catch UserCollectionsError.staleResetEpoch { checks["old-undo-cannot-restore-relations-after-reset"] = try await store.snapshot() == reset }
        do {
            _ = try await store.applyPersonalSettings(failing, commandID: failureCommand, expectedOrganization: reset.organizationState, expectedEpoch: epoch)
            checks["old-profile-recovery-cannot-cross-reset-epoch"] = false
        } catch UserCollectionsError.staleResetEpoch { checks["old-profile-recovery-cannot-cross-reset-epoch"] = try await store.snapshot() == reset }
        try await controllerChecks(root: root, checks: &checks)
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }

    @MainActor static func controllerChecks(root: URL, checks: inout [String: Bool]) async throws {
        let url = root.appendingPathComponent("controller.sqlite"), store = UserCollectionsStore(url: root.appendingPathComponent("controller.sqlite"))
        let initial = try await store.snapshot(), controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let date = Date(timeIntervalSince1970: 20), a = WallpaperPlaylist(name: "A", sidebarRank: 0), b = WallpaperPlaylist(name: "B", sidebarRank: 1)
        var receipts: [(LibraryCollectionsOrganizationState,LibraryCollectionsOrganizationState,String,UUID)] = []
        var hookSawCommittedSnapshot = true
        controller.onOrganizationTransaction = { before, after, name, epoch in
            hookSawCommittedSnapshot = hookSawCommittedSnapshot && controller.snapshot.organizationState == after
            receipts.append((before,after,name,epoch))
        }
        var lock: OpaquePointer?
        guard sqlite3_open(url.path, &lock) == SQLITE_OK, let lock else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(lock) }
        guard sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        var firstAdmitted = false
        let first = Task { firstAdmitted = true; return try await controller.perform(.createPlaylist(a), undoName: "First") }
        while !firstAdmitted { await Task.yield() }
        let second = Task { try await controller.perform(.createPlaylist(b), undoName: "Second") }
        try await Task.sleep(for: .milliseconds(40))
        guard sqlite3_exec(lock, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        _ = try await first.value; _ = try await second.value
        checks["undo-receipts-capture-before-inside-the-actual-fifo-turn"] = receipts.count == 2 && receipts[0].0.playlists.isEmpty
            && receipts[1].0.playlists.map(\.id) == [a.id] && receipts[1].1.playlists.map(\.id) == [a.id,b.id]
            && receipts.map { $0.2 } == ["First","Second"] && hookSawCommittedSnapshot
        let ref = WallpaperReference(provider: .videoLibrary, sourceID: "controller")
        _ = try await controller.perform(.rememberLocator(.init(reference: ref, locator: .init(path: "/hint"))), undoName: "Metadata")
        checks["metadata-never-registers-a-phantom-organization-undo"] = receipts.count == 2
        try sql(url, "CREATE TRIGGER history_fail BEFORE INSERT ON recent BEGIN SELECT RAISE(ABORT,'controlled pending history'); END")
        controller.recordSuccessfulUse(ref, locator: nil, sequence: 1, at: date)
        let error = await controller.flush()
        checks["controlled-history-failure-really-leaves-a-retryable-event"] = error != nil && controller.snapshot.recent.isEmpty
        _ = try await controller.perform(.clearRecent)
        try sql(url, "DROP TRIGGER history_fail")
        let afterClear = await controller.flush()
        checks["successful-clear-retires-earlier-failed-history-before-exit-retry"] = afterClear == nil && controller.snapshot.recent.isEmpty
        controller.recordSuccessfulUse(ref, locator: nil, sequence: 2, at: date)
        _ = await controller.flush()
        checks["new-success-after-clear-is-still-published-without-undo"] = controller.snapshot.recent.count == 1 && receipts.count == 2
        let failedPending = WallpaperReference(provider: .staticImageLibrary, sourceID: "failed-clear")
        try sql(url, "CREATE TRIGGER history_fail BEFORE INSERT ON recent BEGIN SELECT RAISE(ABORT,'pending survives failed clear'); END")
        controller.recordSuccessfulUse(failedPending, locator: nil, sequence: 3, at: date)
        _ = await controller.flush()
        try sql(url, "CREATE TRIGGER clear_fail BEFORE DELETE ON recent BEGIN SELECT RAISE(ABORT,'controlled clear failure'); END")
        do {
            _ = try await controller.perform(.clearRecent)
            checks["failed-clear-keeps-old-pending-history-for-a-real-retry"] = false
        } catch {
            try sql(url, "DROP TRIGGER clear_fail; DROP TRIGGER history_fail")
            let retryError = await controller.flush()
            checks["failed-clear-keeps-old-pending-history-for-a-real-retry"] = retryError == nil
                && Set(controller.snapshot.recent.map(\.reference)) == [ref,failedPending]
        }
        let beforeReset = controller.snapshot
        var preparations = 0, preparationSawOldEpoch = false, preparationSawBarrier = false
        try sql(url, "CREATE TRIGGER reset_fail BEFORE DELETE ON playlists BEGIN SELECT RAISE(ABORT,'controlled reset failure'); END")
        do {
            try await controller.reset {
                preparations += 1
                preparationSawOldEpoch = controller.snapshot.resetEpoch == beforeReset.resetEpoch
                preparationSawBarrier = controller.isResetting
                controller.recordSuccessfulUse(ref, locator: nil, sequence: 99, at: date)
            }
            checks["reset-preparation-is-inside-the-old-epoch-barrier-and-failure-is-reported"] = false
        } catch {
            checks["reset-preparation-is-inside-the-old-epoch-barrier-and-failure-is-reported"] = preparations == 1
                && preparationSawOldEpoch && preparationSawBarrier && !controller.isResetting
                && controller.snapshot == beforeReset && controller.lastError != nil
        }
        try sql(url, "DROP TRIGGER reset_fail")
        try await controller.reset {
            preparations += 1
            preparationSawOldEpoch = controller.snapshot.resetEpoch == beforeReset.resetEpoch
            controller.recordSuccessfulUse(ref, locator: nil, sequence: 100, at: date)
        }
        _ = await controller.flush()
        checks["reset-retry-prepares-once-before-new-epoch-and-rejects-reentrant-metadata"] = preparations == 2
            && preparationSawOldEpoch && controller.snapshot.resetEpoch != beforeReset.resetEpoch
            && controller.snapshot.recent.isEmpty && controller.snapshot.playlists.isEmpty
        do {
            _ = try await controller.restoreOrganization(expected: controller.snapshot.organizationState, replacement: beforeReset.organizationState, expectedEpoch: initial.resetEpoch)
            checks["controller-rejects-old-epoch-before-queueing-undo"] = false
        } catch UserCollectionsError.staleResetEpoch { checks["controller-rejects-old-epoch-before-queueing-undo"] = controller.snapshot.playlists.isEmpty }
    }
}
