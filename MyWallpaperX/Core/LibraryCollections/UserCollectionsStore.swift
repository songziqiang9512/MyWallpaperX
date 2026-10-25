import Foundation
import CryptoKit
import SQLite3

/// The sole durable owner of user relationships. Opening, queries and writes
/// run on this actor, never in card layout or on the AppKit main actor.
actor UserCollectionsStore {
    private let url: URL
    private let allowCreate: Bool
    private var sealedForPublication = false
    private var database: OpaquePointer?
    private static let applicationID: Int32 = 0x4D575843
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, allowCreate: Bool = true) { self.url = url; self.allowCreate = allowCreate }
    deinit { if let database { sqlite3_close(database) } }

    func snapshot() throws -> UserCollectionsSnapshot {
        try open()
        return try transaction("DEFERRED") { try readSnapshot() }
    }

    func playlistCoverAsset(id: UUID, expectedEpoch: UUID) throws -> WallpaperPlaylistCoverAsset? {
        try playlistCoverAssets(ids: [id], expectedEpoch: expectedEpoch).first
    }

    func playlistCoverAssets(ids: Set<UUID>, expectedEpoch: UUID) throws -> [WallpaperPlaylistCoverAsset] {
        try open()
        return try transaction("DEFERRED") {
            try requireEpoch(expectedEpoch)
            return try ids.sorted { $0.uuidString < $1.uuidString }.compactMap { try readCoverAsset($0) }
        }
    }

    /// The App invokes this only at startup after pending profile recovery has
    /// completed, before its new Undo stack can retain an old cover identity.
    func pruneUnreferencedPlaylistCoverAssets(expectedEpoch: UUID) throws {
        try open()
        try transaction {
            try requireEpoch(expectedEpoch)
            try execute("DELETE FROM playlist_cover_assets WHERE id NOT IN (SELECT custom_cover_asset_id FROM playlists WHERE custom_cover_asset_id IS NOT NULL)")
        }
    }

    func apply(_ command: UserCollectionsCommand, expectedEpoch: UUID) throws -> UserCollectionsSnapshot {
        try apply([command], expectedEpoch: expectedEpoch)
    }

    /// A sheet can create a playlist and add its selected members as one change.
    /// A failed member admission leaves neither rows nor a ghost empty playlist.
    func apply(_ commands: [UserCollectionsCommand], expectedEpoch: UUID) throws -> UserCollectionsSnapshot {
        try open()
        return try transaction {
            try requireEpoch(expectedEpoch)
            guard !commands.isEmpty else { return try readSnapshot() }
            for command in commands {
                switch command {
                case .createPlaylist(let playlist):
                    try insertPlaylist(playlist)
                case .createPlaylistWithCover(let playlist, let asset):
                    try prepareCover(asset, for: playlist.customCoverAssetID)
                    try insertPlaylist(playlist)
                case .duplicatePlaylist(let sourceID, let playlist):
                    let source = try readPlaylist(sourceID)
                    var copy = playlist
                    copy.descriptionText = source.descriptionText; copy.customCoverAssetID = source.customCoverAssetID
                    try insertPlaylist(copy)
                    // Existing unavailable members are still valid relationships.
                    // Copying a list never acquires, opens or deletes media.
                    try execute("INSERT INTO members SELECT ?,ref_key,position,? FROM members WHERE playlist_id=?",
                                [.text(playlist.id.uuidString), .real(playlist.createdAt.timeIntervalSince1970), .text(sourceID.uuidString)])
                case .editPlaylistMetadata(let id, let expected, let replacement, let asset, let date):
                    let current = try readPlaylist(id)
                    guard current.metadata == expected else { throw UserCollectionsError.playlistMetadataConflict }
                    var updated = current
                    updated.name = replacement.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.descriptionText = WallpaperPlaylistMetadata.normalizedDescription(replacement.descriptionText)
                    updated.customCoverAssetID = replacement.customCoverAssetID
                    try validateName(updated.name); try requireFinite(date)
                    try prepareCover(asset, for: updated.customCoverAssetID)
                    if updated.metadata != current.metadata {
                        try execute("UPDATE playlists SET name=?,description_text=?,custom_cover_asset_id=?,modified_at=? WHERE id=?",
                            [.text(updated.name), updated.descriptionText.map(Value.text) ?? .null,
                             updated.customCoverAssetID.map { .text($0.uuidString) } ?? .null,
                             .real(date.timeIntervalSince1970), .text(id.uuidString)])
                    }
                case .deletePlaylist(let id):
                    try execute("DELETE FROM playlists WHERE id=?", [.text(id.uuidString)])
                case .reorderPlaylists(let ids):
                    let current = try strings("SELECT id FROM playlists")
                    guard Set(ids.map(\.uuidString)) == Set(current), ids.count == current.count else { throw UserCollectionsError.invalidOrder }
                    for (rank, id) in ids.enumerated() {
                        try execute("UPDATE playlists SET sidebar_rank=? WHERE id=?", [.integer(Int64(rank)), .text(id.uuidString)])
                    }
                case .addMembers(let id, let items, let date):
                    try requirePlaylist(id)
                    var position = try integer("SELECT COALESCE(MAX(position),-1)+1 FROM members WHERE playlist_id=?", [.text(id.uuidString)])
                    var changed = false
                    for item in items {
                        try requireOrganizable(item)
                        let reference = try canonical(item.reference)
                        try remember(reference, locator: item.locator, replacing: false)
                        try execute("INSERT OR IGNORE INTO members VALUES(?,?,?,?)", [.text(id.uuidString), .text(reference.storageKey), .integer(position), .real(date.timeIntervalSince1970)])
                        if sqlite3_changes(database) > 0 { position += 1; changed = true }
                    }
                    if changed { try touchPlaylist(id, at: date) }
                case .removeMembers(let id, let references, let date):
                    try requirePlaylist(id)
                    var changed = false
                    for reference in references {
                        try execute("DELETE FROM members WHERE playlist_id=? AND ref_key=?", [.text(id.uuidString), .text(try canonical(reference).storageKey)])
                        changed = changed || sqlite3_changes(database) > 0
                    }
                    if changed { try normalizePositions(id); try touchPlaylist(id, at: date) }
                case .setFavorite(let item, let enabled, let date):
                    let reference = try canonical(item.reference)
                    if enabled {
                        try requireOrganizable(item)
                        try remember(reference, locator: item.locator, replacing: false)
                        try execute("INSERT OR IGNORE INTO favorites VALUES(?,?,NULL)", [.text(reference.storageKey), .real(date.timeIntervalSince1970)])
                    } else {
                        try execute("DELETE FROM favorites WHERE ref_key=?", [.text(reference.storageKey)])
                    }
                case .linkAlias(let alias, let date): try link(alias, editedAt: date)
                case .relocateLocalReference(let source, let replacement, let date):
                    try relocateLocalReference(source, replacement: replacement, at: date)
                case .rememberLocator(let item): try remember(try canonical(item.reference), locator: item.locator, replacing: true)
                case .removeRecent(let references):
                    for reference in references {
                        try execute("DELETE FROM recent WHERE ref_key=?", [.text(try canonical(reference).storageKey)])
                    }
                case .clearRecent: try execute("DELETE FROM recent")
                case .setLibraryExcluded(let references, let excluded):
                    try setLibraryExcluded(references, excluded)
                case .clearLibraryExclusion(let reference, let expectedRevision):
                    let key = try canonical(reference).storageKey
                    let current = try exclusionRevision(key)
                    if current == expectedRevision, current != nil {
                        try execute("DELETE FROM library_exclusions WHERE ref_key=?", [.text(key)])
                    }
                case .restoreOrganization(let expected, let replacement):
                    guard try readSnapshot().organizationState == expected, replacement.aliases == expected.aliases else {
                        throw UserCollectionsError.organizationConflict
                    }
                    try replaceOrganization(replacement)
                }
            }
            try advanceRevision()
            return try readSnapshot()
        }
    }

    /// Only the relationship portion is atomic here. The App's durable recovery
    /// coordinator still has to apply source metadata and preferences separately.
    /// A repeated committed command returns current data, preserving later edits.
    func applyPersonalSettings(_ payload: LibraryCollectionsPersonalSettingsImport, commandID: UUID,
                              expectedOrganization: LibraryCollectionsOrganizationState,
                              expectedEpoch: UUID) throws -> UserCollectionsSnapshot {
        try open()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(payload)).map { String(format: "%02x", $0) }.joined()
        return try transaction {
            try requireEpoch(expectedEpoch)
            if try meta("profile-last-id") == commandID.uuidString {
                guard try meta("profile-last-digest") == digest else { throw UserCollectionsError.personalSettingsConflict }
                return try readSnapshot()
            }
            let before = try readSnapshot()
            guard before.organizationState == expectedOrganization else { throw UserCollectionsError.organizationConflict }
            if payload.libraryExclusionStates != nil {
                guard payload.expectedLibraryExclusions == before.excludedLibraryReferences else { throw UserCollectionsError.personalSettingsConflict }
            }
            let referencedCovers = Set(payload.playlists.compactMap(\.customCoverAssetID))
            guard payload.coverAssets.allSatisfy({ payload.playlistMetadataIsExplicit && referencedCovers.contains($0.id) }) else {
                throw UserCollectionsError.personalSettingsConflict
            }
            for asset in payload.coverAssets { try saveCoverAsset(asset) }
            var declaredAliases = Dictionary(uniqueKeysWithValues: before.aliases.map { ($0.alias, $0) })
            var incomingAliases = Set<WallpaperReference>()
            for alias in payload.aliases {
                guard alias.proof != .publishedDownload, incomingAliases.insert(alias.alias).inserted,
                      !alias.alias.sourceID.isEmpty, !alias.canonical.sourceID.isEmpty else {
                    throw UserCollectionsError.personalSettingsConflict
                }
                let existing = try canonical(alias.alias), target = try canonical(alias.canonical)
                guard existing == alias.alias || existing == target else { throw UserCollectionsError.personalSettingsConflict }
                if let prior = declaredAliases[alias.alias] {
                    guard try canonical(prior.canonical) == target else { throw UserCollectionsError.personalSettingsConflict }
                } else { declaredAliases[alias.alias] = alias }
            }
            try validateAliasGraph(Array(declaredAliases.values))
            let targets = declaredAliases.mapValues(\.canonical)
            // An old backup must not indirectly redirect an established alias
            // by adding an edge from its current canonical root elsewhere.
            for prior in before.aliases {
                var resolved = prior.alias
                while let target = targets[resolved] { resolved = target }
                guard try canonical(prior.alias) == resolved else { throw UserCollectionsError.personalSettingsConflict }
            }
            for alias in payload.aliases { try link(alias) }
            let incomingIDs = Set(payload.playlists.map(\.id))
            guard incomingIDs.count == payload.playlists.count,
                  Set(payload.legacyOrigins.map(\.playlistID)).count == payload.legacyOrigins.count,
                  payload.legacyOrigins.allSatisfy({ incomingIDs.contains($0.playlistID) }) else {
                throw UserCollectionsError.personalSettingsConflict
            }
            var resolvedIDs: [UUID: UUID] = [:]
            for origin in payload.legacyOrigins {
                let name = normalizedLegacyTag(origin.tag)
                guard !origin.sourceKey.isEmpty, !name.isEmpty,
                      payload.playlists.first(where: { $0.id == origin.playlistID }).map({ normalizedLegacyTag($0.name) == name }) == true else {
                    throw UserCollectionsError.personalSettingsConflict
                }
                let key = "profile-legacy:" + Data(origin.sourceKey.utf8).base64EncodedString() + ":" + Data(name.utf8).base64EncodedString()
                let id: UUID
                if let raw = try meta(key) {
                    guard let saved = UUID(uuidString: raw) else { throw UserCollectionsError.corruptData("profile legacy UUID") }
                    id = saved
                } else {
                    id = before.playlists.first(where: { normalizedLegacyTag($0.name) == name })?.id ?? origin.playlistID
                    try setMeta(key, id.uuidString)
                }
                resolvedIDs[origin.playlistID] = id
            }
            let legacyIDs = Set(payload.legacyOrigins.map(\.playlistID))
            let legacyTargetIDs = Set(resolvedIDs.values)
            var playlistMetadata = Dictionary(uniqueKeysWithValues: before.playlists.map { ($0.id, $0) })
            for imported in payload.playlists {
                let id = resolvedIDs[imported.id] ?? imported.id
                // Old profiles declared tag names, not UUID metadata/order.
                // Preserve a mapped user's later name and original placement.
                let prior = playlistMetadata[id]
                let existing = legacyIDs.contains(imported.id) ? prior : nil
                let playlist = WallpaperPlaylist(id: id, name: existing?.name ?? imported.name,
                    createdAt: existing?.createdAt ?? imported.createdAt,
                    modifiedAt: existing?.modifiedAt ?? imported.modifiedAt, sidebarRank: existing?.sidebarRank ?? imported.sidebarRank,
                    descriptionText: payload.playlistMetadataIsExplicit ? imported.descriptionText : prior?.descriptionText,
                    customCoverAssetID: payload.playlistMetadataIsExplicit ? imported.customCoverAssetID : prior?.customCoverAssetID)
                try validateName(playlist.name)
                guard playlist.sidebarRank >= 0 else { throw UserCollectionsError.personalSettingsConflict }
                try requireFinite(playlist.createdAt); try requireFinite(playlist.modifiedAt)
                try requireCoverAsset(playlist.customCoverAssetID)
                try execute("""
                    INSERT INTO playlists VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                    name=excluded.name,created_at=excluded.created_at,modified_at=excluded.modified_at,sidebar_rank=excluded.sidebar_rank,
                    description_text=excluded.description_text,custom_cover_asset_id=excluded.custom_cover_asset_id
                    """, playlistValues(playlist))
                playlistMetadata[id] = playlist
            }
            for item in payload.locators { try remember(try canonical(item.reference), locator: item.locator, replacing: true) }
            // Existing member order/added dates are retained. Imported positions
            // determine only the order of newly appended, canonicalized members.
            let ordered = payload.members.enumerated().sorted {
                if $0.element.position != $1.element.position { return $0.element.position < $1.element.position }
                return $0.offset < $1.offset
            }
            for (_, member) in ordered {
                let id = resolvedIDs[member.playlistID] ?? member.playlistID
                guard member.position >= 0 else { throw UserCollectionsError.personalSettingsConflict }
                try requirePlaylist(id); try requireFinite(member.addedAt)
                let key = try canonical(member.reference).storageKey
                let position = try integer("SELECT COALESCE(MAX(position),-1)+1 FROM members WHERE playlist_id=?", [.text(id.uuidString)])
                try execute("INSERT OR IGNORE INTO members VALUES(?,?,?,?)", [.text(id.uuidString), .text(key), .integer(position), .real(member.addedAt.timeIntervalSince1970)])
                if legacyTargetIDs.contains(id), sqlite3_changes(database) > 0 { try touchPlaylist(id, at: member.addedAt) }
            }
            var seenFavorites: [WallpaperReference: Bool] = [:]
            for favorite in payload.favoriteStates {
                let reference = try canonical(favorite.reference)
                if let previous = seenFavorites.updateValue(favorite.isFavorite, forKey: reference), previous != favorite.isFavorite {
                    throw UserCollectionsError.personalSettingsConflict
                }
                if let date = favorite.favoritedAt { try requireFinite(date) }
                if favorite.isFavorite {
                    try mergeFavorite(.init(reference: reference, favoritedAt: favorite.favoritedAt, migrationOrder: nil))
                } else { try execute("DELETE FROM favorites WHERE ref_key=?", [.text(reference.storageKey)]) }
            }
            var exclusions: [WallpaperReference: Bool] = [:]
            for state in payload.libraryExclusionStates ?? [] {
                let reference = try canonical(state.reference)
                if let previous = exclusions.updateValue(state.isExcluded, forKey: reference), previous != state.isExcluded {
                    throw UserCollectionsError.personalSettingsConflict
                }
            }
            for (reference, excluded) in exclusions { try setLibraryExcluded([reference], excluded) }
            try setMeta("profile-last-id", commandID.uuidString)
            try setMeta("profile-last-digest", digest)
            try advanceRevision()
            return try readSnapshot()
        }
    }

    /// Called once by the product success subscriber. Its sequence comes from
    /// the original playback ticket. Duplicate/multi-screen ACKs within this publisher cannot reorder history;
    /// reset and a replacement publisher revoke the old writer. The App owns
    /// one FIFO subscriber per launch and must not replay old tickets on rebind.
    func startHistorySession(expectedEpoch: UUID) throws -> LibraryHistoryWriterToken {
        try open()
        let token = LibraryHistoryWriterToken(resetEpoch: expectedEpoch, publisherID: UUID())
        try transaction {
            try requireEpoch(expectedEpoch)
            try setMeta("history_publisher", token.publisherID.uuidString)
            try setMeta("history_high_water", "")
        }
        return token
    }

    @discardableResult
    func recordSuccessfulUse(_ reference: WallpaperReference, locator: WallpaperLocator?,
                             token: LibraryHistoryWriterToken, sequence: UInt64, at date: Date) throws -> Bool {
        try open()
        return try transaction {
            try requireEpoch(token.resetEpoch)
            guard try meta("history_publisher") == token.publisherID.uuidString else { return false }
            if let raw = try meta("history_high_water"), !raw.isEmpty {
                guard let highWater = UInt64(raw) else { throw UserCollectionsError.corruptData("history high water") }
                guard sequence > highWater else { return false }
            }
            let reference = try canonical(reference)
            if let locator { try remember(reference, locator: locator, replacing: false) }
            let serial = try metaInteger("recent_sequence")
            guard serial < Int64.max else { throw UserCollectionsError.corruptData("recent sequence overflow") }
            try execute("INSERT OR REPLACE INTO recent VALUES(?,?,?,NULL)", [.text(reference.storageKey), .real(date.timeIntervalSince1970), .integer(serial + 1)])
            try execute("DELETE FROM recent WHERE ref_key NOT IN (SELECT ref_key FROM recent ORDER BY commit_sequence DESC LIMIT 50)")
            try setMeta("recent_sequence", String(serial + 1))
            try setMeta("history_high_water", String(sequence))
            try advanceRevision()
            return true
        }
    }

    /// Install into a new/untouched relationship database. The marker and all
    /// relationships commit together; an interrupted transaction is retryable.
    func installMigration(_ payload: LibraryCollectionsImport, manifestID: String,
                          expectedEpoch: UUID) throws -> UserCollectionsSnapshot {
        try open()
        return try transaction {
            try requireEpoch(expectedEpoch)
            if let installed = try meta("migration_manifest") {
                guard installed == manifestID else { throw UserCollectionsError.migrationConflict }
                return try readSnapshot()
            }
            guard try metaInteger("revision") == 0 else { throw UserCollectionsError.migrationConflict }
            for playlist in payload.playlists {
                try insertPlaylist(playlist)
            }
            for item in payload.locators { try remember(item.reference, locator: item.locator, replacing: false) }
            for alias in payload.aliases { try link(alias) }
            for member in payload.members {
                try requirePlaylist(member.playlistID)
                try execute("INSERT INTO members VALUES(?,?,?,?) ON CONFLICT(playlist_id,ref_key) DO UPDATE SET position=MIN(position,excluded.position),added_at=MIN(added_at,excluded.added_at)", [.text(member.playlistID.uuidString), .text(try canonical(member.reference).storageKey), .integer(Int64(member.position)), .real(member.addedAt.timeIntervalSince1970)])
            }
            for favorite in payload.favorites { try mergeFavorite(favorite) }
            for recent in payload.recent { try mergeRecent(recent) }
            for playlist in payload.playlists { try normalizePositions(playlist.id) }
            try execute("DELETE FROM recent WHERE ref_key NOT IN (SELECT ref_key FROM recent ORDER BY commit_sequence DESC,migration_order ASC LIMIT 50)")
            try setMeta("recent_sequence", String(try integer("SELECT COALESCE(MAX(commit_sequence),0) FROM recent")))
            try setMeta("migration_manifest", manifestID)
            try advanceRevision()
            return try readSnapshot()
        }
    }

    /// A reset completion marker prevents old snapshots/journals from being
    /// interpreted as a first install. Late commands carry the former epoch.
    func reset(expectedEpoch: UUID) throws -> UserCollectionsSnapshot {
        try open()
        return try transaction {
            try requireEpoch(expectedEpoch)
            for table in ["members", "playlists", "playlist_cover_assets", "library_exclusions", "favorites", "recent", "aliases", "locators"] { try execute("DELETE FROM \(table)") }
            try execute("DELETE FROM collections_meta WHERE key LIKE 'profile-%'")
            try setMeta("reset_epoch", UUID().uuidString)
            try setMeta("migration_manifest", "reset-complete")
            try setMeta("history_publisher", "")
            try setMeta("history_high_water", "")
            try setMeta("recent_sequence", "0")
            try advanceRevision()
            return try readSnapshot()
        }
    }

    /// A staging owner cannot be reused after its file has been published.
    /// Checkpoint before closing so publication moves exactly one SQLite file.
    func finishMigrationPublication() throws {
        try open()
        var pages: Int32 = 0
        var completed: Int32 = 0
        guard sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, &pages, &completed) == SQLITE_OK,
              completed == pages else { throw databaseError() }
        guard sqlite3_close(database) == SQLITE_OK else { throw databaseError() }
        database = nil
        sealedForPublication = true
    }

    // MARK: Identity and relationship transactions

    private func canonical(_ reference: WallpaperReference) throws -> WallpaperReference {
        guard !reference.sourceID.isEmpty else { throw UserCollectionsError.invalidReference }
        var key = reference.storageKey
        var visited = Set<String>()
        while true {
            guard visited.insert(key).inserted else { throw UserCollectionsError.corruptData("alias cycle") }
            guard let next = try strings("SELECT canonical_key FROM aliases WHERE alias_key=?", [.text(key)]).first else { break }
            key = next
        }
        guard let result = WallpaperReference(storageKey: key) else { throw UserCollectionsError.invalidReference }
        return result
    }

    private func relocateLocalReference(_ source: WallpaperReference, replacement: WallpaperOrganizationItem, at date: Date) throws {
        try requireOrganizable(replacement)
        try requireFinite(date)
        let target = replacement.reference
        let kind: WallpaperMediaKind
        switch source.provider {
        case .videoLibrary: kind = .video
        case .staticImageLibrary: kind = .image
        default: throw UserCollectionsError.invalidReference
        }
        guard source.provider == target.provider, replacement.locator.mediaKind == kind,
              replacement.locator.path?.isEmpty == false,
              try canonical(source) == source, try canonical(target) == target else {
            throw UserCollectionsError.organizationConflict
        }
        let key = source.storageKey
        guard try integer("""
            SELECT (SELECT COUNT(*) FROM members WHERE ref_key=?)
                 + (SELECT COUNT(*) FROM favorites WHERE ref_key=?)
                 + (SELECT COUNT(*) FROM recent WHERE ref_key=?)
            """, [.text(key), .text(key), .text(key)]) > 0 else { throw UserCollectionsError.organizationConflict }
        // The user-confirmed import receipt supplies the real target locator.
        // Do this before link so its old missing locator cannot take precedence.
        try remember(target, locator: replacement.locator, replacing: true)
        try link(.init(alias: source, canonical: target, proof: .explicitUserRelocation), editedAt: date)
    }

    private func link(_ alias: WallpaperReferenceAlias, editedAt: Date? = nil) throws {
        let source = try canonical(alias.alias)
        let target = try canonical(alias.canonical)
        guard source != target else { return }
        // Merge duplicate membership by its earliest position and added time.
        var affected = Set<UUID>()
        try rows("SELECT playlist_id,position,added_at FROM members WHERE ref_key=?", [.text(source.storageKey)]) { statement in
            guard let id = UUID(uuidString: try text(statement, 0)) else { throw UserCollectionsError.corruptData("playlist UUID") }
            affected.insert(id)
            try execute("INSERT INTO members VALUES(?,?,?,?) ON CONFLICT(playlist_id,ref_key) DO UPDATE SET position=MIN(position,excluded.position),added_at=MIN(added_at,excluded.added_at)", [.text(id.uuidString), .text(target.storageKey), .integer(sqlite3_column_int64(statement, 1)), .real(sqlite3_column_double(statement, 2))])
        }
        try execute("DELETE FROM members WHERE ref_key=?", [.text(source.storageKey)])
        try rows("SELECT favorited_at,migration_order FROM favorites WHERE ref_key=?", [.text(source.storageKey)]) { statement in
            try mergeFavorite(WallpaperFavorite(reference: target, favoritedAt: optionalDate(statement, 0), migrationOrder: optionalInt(statement, 1)))
        }
        try execute("DELETE FROM favorites WHERE ref_key=?", [.text(source.storageKey)])
        try rows("SELECT last_success_at,commit_sequence,migration_order FROM recent WHERE ref_key=?", [.text(source.storageKey)]) { statement in
            try mergeRecent(WallpaperRecentUse(reference: target, lastSuccessfulUseAt: optionalDate(statement, 0), commitSequence: sqlite3_column_int64(statement, 1), migrationOrder: optionalInt(statement, 2)))
        }
        try execute("DELETE FROM recent WHERE ref_key=?", [.text(source.storageKey)])
        try rows("SELECT payload FROM locators WHERE ref_key=?", [.text(source.storageKey)]) { statement in
            let locator: WallpaperLocator = try decode(statement, 0)
            try remember(target, locator: locator, replacing: false)
        }
        try execute("DELETE FROM locators WHERE ref_key=?", [.text(source.storageKey)])
        try execute("""
            INSERT INTO library_exclusions SELECT ?,revision FROM library_exclusions WHERE ref_key=?
            ON CONFLICT(ref_key) DO UPDATE SET revision=MAX(revision,excluded.revision)
            """, [.text(target.storageKey), .text(source.storageKey)])
        try execute("DELETE FROM library_exclusions WHERE ref_key=?", [.text(source.storageKey)])
        try execute("UPDATE aliases SET canonical_key=? WHERE canonical_key=?", [.text(target.storageKey), .text(source.storageKey)])
        try execute("INSERT OR REPLACE INTO aliases VALUES(?,?,?)", [.text(source.storageKey), .text(target.storageKey), .text(alias.proof.rawValue)])
        for id in affected {
            try normalizePositions(id)
            if let editedAt { try touchPlaylist(id, at: editedAt) }
        }
    }

    private func requireFinite(_ date: Date) throws {
        guard date.timeIntervalSince1970.isFinite else { throw UserCollectionsError.personalSettingsConflict }
    }

    private func normalizedLegacyTag(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private func replaceOrganization(_ state: LibraryCollectionsOrganizationState) throws {
        let ids = Set(state.playlists.map(\.id))
        guard ids.count == state.playlists.count else { throw UserCollectionsError.organizationConflict }
        for playlist in state.playlists {
            try validateName(playlist.name); try requireFinite(playlist.createdAt); try requireFinite(playlist.modifiedAt)
            try requireCoverAsset(playlist.customCoverAssetID)
        }
        var memberKeys: [UUID: Set<WallpaperReference>] = [:]
        for member in state.members {
            guard ids.contains(member.playlistID), member.position >= 0,
                  try canonical(member.reference) == member.reference,
                  memberKeys[member.playlistID, default: []].insert(member.reference).inserted else {
                throw UserCollectionsError.organizationConflict
            }
            try requireFinite(member.addedAt)
        }
        for id in ids {
            let positions = state.members.filter { $0.playlistID == id }.map(\.position).sorted()
            guard positions == Array(0..<positions.count) else { throw UserCollectionsError.organizationConflict }
        }
        var favorites = Set<WallpaperReference>()
        for favorite in state.favorites {
            guard try canonical(favorite.reference) == favorite.reference, favorites.insert(favorite.reference).inserted else {
                throw UserCollectionsError.organizationConflict
            }
            if let date = favorite.favoritedAt { try requireFinite(date) }
        }
        try execute("DELETE FROM members"); try execute("DELETE FROM playlists"); try execute("DELETE FROM favorites")
        for playlist in state.playlists { try insertPlaylist(playlist) }
        for member in state.members {
            try execute("INSERT INTO members VALUES(?,?,?,?)", [.text(member.playlistID.uuidString), .text(member.reference.storageKey),
                .integer(Int64(member.position)), .real(member.addedAt.timeIntervalSince1970)])
        }
        for favorite in state.favorites { try mergeFavorite(favorite) }
    }

    private func touchPlaylist(_ id: UUID, at date: Date) throws {
        try execute("UPDATE playlists SET modified_at=? WHERE id=?", [.real(date.timeIntervalSince1970), .text(id.uuidString)])
    }

    private func mergeFavorite(_ favorite: WallpaperFavorite) throws {
        let key = try canonical(favorite.reference).storageKey
        // Unknown legacy timestamps remain unknown. Among known values keep
        // the earliest true favorite, never manufacture a migration date.
        try execute("""
            INSERT INTO favorites VALUES(?,?,?) ON CONFLICT(ref_key) DO UPDATE SET
            favorited_at=CASE WHEN favorited_at IS NULL THEN excluded.favorited_at WHEN excluded.favorited_at IS NULL THEN favorited_at ELSE MIN(favorited_at,excluded.favorited_at) END,
            migration_order=CASE WHEN migration_order IS NULL THEN excluded.migration_order WHEN excluded.migration_order IS NULL THEN migration_order ELSE MIN(migration_order,excluded.migration_order) END
            """, [.text(key), favorite.favoritedAt.map { .real($0.timeIntervalSince1970) } ?? .null, favorite.migrationOrder.map { .integer(Int64($0)) } ?? .null])
    }

    private func mergeRecent(_ recent: WallpaperRecentUse) throws {
        let key = try canonical(recent.reference).storageKey
        try execute("""
            INSERT INTO recent VALUES(?,?,?,?) ON CONFLICT(ref_key) DO UPDATE SET
            last_success_at=CASE WHEN excluded.commit_sequence>commit_sequence THEN excluded.last_success_at ELSE last_success_at END,
            migration_order=CASE WHEN excluded.commit_sequence>commit_sequence THEN excluded.migration_order ELSE migration_order END,
            commit_sequence=MAX(commit_sequence,excluded.commit_sequence)
            """, [.text(key), recent.lastSuccessfulUseAt.map { .real($0.timeIntervalSince1970) } ?? .null, .integer(recent.commitSequence), recent.migrationOrder.map { .integer(Int64($0)) } ?? .null])
    }

    private func remember(_ reference: WallpaperReference, locator: WallpaperLocator, replacing: Bool) throws {
        guard !reference.sourceID.isEmpty else { throw UserCollectionsError.invalidReference }
        let data = try JSONEncoder().encode(locator)
        try execute(replacing ? "INSERT OR REPLACE INTO locators VALUES(?,?)" : "INSERT OR IGNORE INTO locators VALUES(?,?)", [.text(reference.storageKey), .blob(data)])
    }

    private func normalizePositions(_ id: UUID) throws {
        let keys = try strings("SELECT ref_key FROM members WHERE playlist_id=? ORDER BY position,added_at,rowid", [.text(id.uuidString)])
        for (position, key) in keys.enumerated() {
            try execute("UPDATE members SET position=? WHERE playlist_id=? AND ref_key=?", [.integer(Int64(position)), .text(id.uuidString), .text(key)])
        }
    }

    private func requireOrganizable(_ item: WallpaperOrganizationItem) throws {
        guard item.isPublishedLocally && item.isAvailable else { throw UserCollectionsError.unavailableForOrganization }
        guard !item.reference.sourceID.isEmpty else { throw UserCollectionsError.invalidReference }
    }
    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UserCollectionsError.invalidName }
    }
    private func requirePlaylist(_ id: UUID) throws {
        guard try integer("SELECT COUNT(*) FROM playlists WHERE id=?", [.text(id.uuidString)]) == 1 else { throw UserCollectionsError.missingPlaylist }
    }
    private func requireEpoch(_ epoch: UUID) throws {
        guard try meta("reset_epoch") == epoch.uuidString else { throw UserCollectionsError.staleResetEpoch }
    }
    private func advanceRevision() throws {
        let current = try metaInteger("revision")
        guard current < Int64.max else { throw UserCollectionsError.corruptData("revision overflow") }
        try setMeta("revision", String(current + 1))
    }
    private func playlistValues(_ playlist: WallpaperPlaylist) -> [Value] {
        [.text(playlist.id.uuidString), .text(playlist.name), .real(playlist.createdAt.timeIntervalSince1970),
         .real(playlist.modifiedAt.timeIntervalSince1970), .integer(Int64(playlist.sidebarRank)),
         WallpaperPlaylistMetadata.normalizedDescription(playlist.descriptionText).map(Value.text) ?? .null,
         playlist.customCoverAssetID.map { .text($0.uuidString) } ?? .null]
    }

    private func insertPlaylist(_ playlist: WallpaperPlaylist) throws {
        try validateName(playlist.name)
        try requireFinite(playlist.createdAt); try requireFinite(playlist.modifiedAt)
        try requireCoverAsset(playlist.customCoverAssetID)
        try execute("INSERT INTO playlists VALUES(?,?,?,?,?,?,?)", playlistValues(playlist))
    }

    private func readPlaylist(_ id: UUID) throws -> WallpaperPlaylist {
        var result: WallpaperPlaylist?
        try rows("SELECT id,name,created_at,modified_at,sidebar_rank,description_text,custom_cover_asset_id FROM playlists WHERE id=?", [.text(id.uuidString)]) {
            result = try playlist($0)
        }
        guard let result else { throw UserCollectionsError.missingPlaylist }
        return result
    }

    private func playlist(_ statement: OpaquePointer) throws -> WallpaperPlaylist {
        guard let id = UUID(uuidString: try text(statement, 0)) else { throw UserCollectionsError.corruptData("playlist UUID") }
        let description = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : try text(statement, 5)
        var assetID: UUID?
        if sqlite3_column_type(statement, 6) != SQLITE_NULL {
            guard let value = UUID(uuidString: try text(statement, 6)) else { throw UserCollectionsError.corruptData("cover UUID") }
            assetID = value
        }
        try requireCoverAsset(assetID)
        return WallpaperPlaylist(id: id, name: try text(statement, 1),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            sidebarRank: Int(sqlite3_column_int64(statement, 4)), descriptionText: description, customCoverAssetID: assetID)
    }

    private func prepareCover(_ asset: WallpaperPlaylistCoverAsset?, for id: UUID?) throws {
        if let asset {
            guard asset.id == id else { throw UserCollectionsError.invalidCoverAsset }
            try saveCoverAsset(asset)
        }
        try requireCoverAsset(id)
    }

    private func requireCoverAsset(_ id: UUID?) throws {
        if let id, try integer("SELECT COUNT(*) FROM playlist_cover_assets WHERE id=?", [.text(id.uuidString)]) != 1 {
            throw UserCollectionsError.invalidCoverAsset
        }
    }

    private func readCoverAsset(_ id: UUID) throws -> WallpaperPlaylistCoverAsset? {
        var result: WallpaperPlaylistCoverAsset?
        try rows("SELECT image_data,pixel_width,pixel_height FROM playlist_cover_assets WHERE id=?", [.text(id.uuidString)]) { statement in
            let count = Int(sqlite3_column_bytes(statement, 0))
            let width = Int(sqlite3_column_int64(statement, 1)), height = Int(sqlite3_column_int64(statement, 2))
            guard WallpaperPlaylistCoverAsset.allowsCopy(encodedByteCount: count, pixelWidth: width, pixelHeight: height),
                  let bytes = sqlite3_column_blob(statement, 0) else {
                throw UserCollectionsError.corruptData("cover data")
            }
            result = .init(id: id, imageData: Data(bytes: bytes, count: count), pixelWidth: width, pixelHeight: height)
        }
        return result
    }

    private func saveCoverAsset(_ asset: WallpaperPlaylistCoverAsset) throws {
        guard asset.isValidControlledCopy else { throw UserCollectionsError.invalidCoverAsset }
        if let existing = try readCoverAsset(asset.id) {
            guard existing == asset else { throw UserCollectionsError.invalidCoverAsset }
            return
        }
        try execute("INSERT INTO playlist_cover_assets VALUES(?,?,?,?)", [.text(asset.id.uuidString), .blob(asset.imageData),
            .integer(Int64(asset.pixelWidth)), .integer(Int64(asset.pixelHeight))])
    }

    private func exclusionRevision(_ key: String) throws -> Int64? {
        var result: Int64?
        try rows("SELECT revision FROM library_exclusions WHERE ref_key=?", [.text(key)]) { result = sqlite3_column_int64($0, 0) }
        return result
    }

    private func setLibraryExcluded(_ references: [WallpaperReference], _ excluded: Bool) throws {
        let revision = try metaInteger("revision")
        guard revision < Int64.max else { throw UserCollectionsError.corruptData("revision overflow") }
        for reference in references {
            let key = try canonical(reference).storageKey
            if excluded {
                try execute("INSERT INTO library_exclusions VALUES(?,?) ON CONFLICT(ref_key) DO UPDATE SET revision=excluded.revision",
                    [.text(key), .integer(revision + 1)])
            } else { try execute("DELETE FROM library_exclusions WHERE ref_key=?", [.text(key)]) }
        }
    }

    // MARK: Snapshot / SQLite lifetime

    private func readSnapshot() throws -> UserCollectionsSnapshot {
        guard let epoch = UUID(uuidString: try meta("reset_epoch") ?? "") else { throw UserCollectionsError.corruptData("reset epoch") }
        var playlists: [WallpaperPlaylist] = []
        try rows("SELECT id,name,created_at,modified_at,sidebar_rank,description_text,custom_cover_asset_id FROM playlists ORDER BY sidebar_rank,created_at,id") { statement in
            playlists.append(try playlist(statement))
        }
        var members: [WallpaperPlaylistMember] = []
        try rows("SELECT playlist_id,ref_key,position,added_at FROM members ORDER BY playlist_id,position") { statement in
            guard let id = UUID(uuidString: try text(statement, 0)) else { throw UserCollectionsError.corruptData("member playlist") }
            members.append(WallpaperPlaylistMember(playlistID: id, reference: try reference(statement, 1), position: Int(sqlite3_column_int64(statement, 2)), addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))))
        }
        var favorites: [WallpaperFavorite] = []
        try rows("SELECT ref_key,favorited_at,migration_order FROM favorites ORDER BY favorited_at DESC,migration_order ASC,ref_key") { statement in
            favorites.append(WallpaperFavorite(reference: try reference(statement, 0), favoritedAt: optionalDate(statement, 1), migrationOrder: optionalInt(statement, 2)))
        }
        var recent: [WallpaperRecentUse] = []
        try rows("SELECT ref_key,last_success_at,commit_sequence,migration_order FROM recent ORDER BY commit_sequence DESC,migration_order ASC,ref_key") { statement in
            recent.append(WallpaperRecentUse(reference: try reference(statement, 0), lastSuccessfulUseAt: optionalDate(statement, 1), commitSequence: sqlite3_column_int64(statement, 2), migrationOrder: optionalInt(statement, 3)))
        }
        var aliases: [WallpaperReferenceAlias] = []
        try rows("SELECT alias_key,canonical_key,proof FROM aliases ORDER BY alias_key") { statement in
            guard let proof = WallpaperAliasProof(rawValue: try text(statement, 2)) else { throw UserCollectionsError.corruptData("alias proof") }
            aliases.append(WallpaperReferenceAlias(alias: try reference(statement, 0), canonical: try reference(statement, 1), proof: proof))
        }
        var locators: [WallpaperReferenceLocator] = []
        try validateAliasGraph(aliases)
        try rows("SELECT ref_key,payload FROM locators ORDER BY ref_key") { statement in
            locators.append(WallpaperReferenceLocator(reference: try reference(statement, 0), locator: try decode(statement, 1)))
        }
        var exclusions: [WallpaperLibraryExclusion] = []
        try rows("SELECT ref_key,revision FROM library_exclusions ORDER BY ref_key") { statement in
            let revision = sqlite3_column_int64(statement, 1)
            guard revision > 0 else { throw UserCollectionsError.corruptData("exclusion revision") }
            exclusions.append(.init(reference: try reference(statement, 0), revision: revision))
        }
        return UserCollectionsSnapshot(revision: try metaInteger("revision"), resetEpoch: epoch, migrationManifestID: try meta("migration_manifest"), playlists: playlists, members: members, favorites: favorites, recent: recent, aliases: aliases, locators: locators, excludedLibraryReferences: exclusions)
    }

    private func validateAliasGraph(_ aliases: [WallpaperReferenceAlias]) throws {
        var targets: [WallpaperReference: WallpaperReference] = [:]
        for alias in aliases {
            guard targets.updateValue(alias.canonical, forKey: alias.alias) == nil else { throw UserCollectionsError.corruptData("duplicate alias") }
        }
        var resolved = Set<WallpaperReference>()
        for alias in aliases {
            var path = Set<WallpaperReference>()
            var current = alias.alias
            while let next = targets[current], !resolved.contains(current) {
                guard path.insert(current).inserted else { throw UserCollectionsError.corruptData("alias cycle") }
                current = next
            }
            resolved.formUnion(path)
        }
    }

    private func open() throws {
        guard !sealedForPublication else { throw UserCollectionsError.closedForPublication }
        guard database == nil else { return }
        if allowCreate { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | (allowCreate ? SQLITE_OPEN_CREATE : 0) | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            if let handle { sqlite3_close(handle) }
            throw UserCollectionsError.database(message)
        }
        database = handle
        do {
            sqlite3_busy_timeout(handle, 2500)
            let version = Int32(try integer("PRAGMA user_version"))
            guard (0...2).contains(version) else { throw UserCollectionsError.unsupportedSchema(version) }
            let identity = Int32(try integer("PRAGMA application_id"))
            if version == 0 {
                guard allowCreate, identity == 0, try integer("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") == 0 else { throw UserCollectionsError.corruptData("unrecognized database") }
            } else if identity != Self.applicationID { throw UserCollectionsError.corruptData("database identity") }
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            if version == 0 {
                try transaction {
                    try execute("CREATE TABLE collections_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
                    try execute("CREATE TABLE playlist_cover_assets(id TEXT PRIMARY KEY,image_data BLOB NOT NULL,pixel_width INTEGER NOT NULL,pixel_height INTEGER NOT NULL)")
                    try execute("CREATE TABLE playlists(id TEXT PRIMARY KEY,name TEXT NOT NULL,created_at REAL NOT NULL,modified_at REAL NOT NULL,sidebar_rank INTEGER NOT NULL,description_text TEXT,custom_cover_asset_id TEXT REFERENCES playlist_cover_assets(id))")
                    try execute("CREATE TABLE library_exclusions(ref_key TEXT PRIMARY KEY,revision INTEGER NOT NULL)")
                    try execute("CREATE TABLE members(playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,ref_key TEXT NOT NULL,position INTEGER NOT NULL,added_at REAL NOT NULL,PRIMARY KEY(playlist_id,ref_key))")
                    try execute("CREATE TABLE favorites(ref_key TEXT PRIMARY KEY,favorited_at REAL,migration_order INTEGER)")
                    try execute("CREATE TABLE recent(ref_key TEXT PRIMARY KEY,last_success_at REAL,commit_sequence INTEGER NOT NULL,migration_order INTEGER)")
                    try execute("CREATE TABLE aliases(alias_key TEXT PRIMARY KEY,canonical_key TEXT NOT NULL,proof TEXT NOT NULL)")
                    try execute("CREATE TABLE locators(ref_key TEXT PRIMARY KEY,payload BLOB NOT NULL)")
                    try execute("PRAGMA application_id=\(Self.applicationID)")
                    try execute("PRAGMA user_version=2")
                    try setMeta("revision", "0")
                    try setMeta("reset_epoch", UUID().uuidString)
                    try setMeta("recent_sequence", "0")
                }
            } else if version == 1 {
                try transaction {
                    try execute("CREATE TABLE playlist_cover_assets(id TEXT PRIMARY KEY,image_data BLOB NOT NULL,pixel_width INTEGER NOT NULL,pixel_height INTEGER NOT NULL)")
                    try execute("ALTER TABLE playlists ADD COLUMN description_text TEXT")
                    try execute("ALTER TABLE playlists ADD COLUMN custom_cover_asset_id TEXT REFERENCES playlist_cover_assets(id)")
                    try execute("CREATE TABLE library_exclusions(ref_key TEXT PRIMARY KEY,revision INTEGER NOT NULL)")
                    try execute("PRAGMA user_version=2")
                    // Do not commit an upgrade whose original relationships
                    // cannot be read. DDL/version and rows roll back together.
                    guard try strings("PRAGMA quick_check(1)") == ["ok"] else { throw UserCollectionsError.corruptData("SQLite integrity") }
                    _ = try readSnapshot()
                }
            }
            guard try strings("PRAGMA quick_check(1)") == ["ok"] else { throw UserCollectionsError.corruptData("SQLite integrity") }
        } catch {
            if database == handle {
                sqlite3_close_v2(handle)
                database = nil
            }
            throw error
        }
    }

    private enum Value { case text(String), integer(Int64), real(Double), blob(Data), null }
    private func transaction<T>(_ mode: String = "IMMEDIATE", _ body: () throws -> T) throws -> T {
        try execute("BEGIN \(mode)")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        }
        catch {
            let original = error
            // Rollback failure must not leave an open transaction available to
            // later commands; close the handle and surface both database errors.
            do { try execute("ROLLBACK") }
            catch {
                if let database { sqlite3_close_v2(database) }; database = nil
                throw UserCollectionsError.database("\(original.localizedDescription); rollback: \(error.localizedDescription)")
            }
            throw original
        }
    }
    private func statement(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                guard let length = Int32(exactly: text.utf8.count) else { sqlite3_finalize(statement); throw UserCollectionsError.database("text too large") }
                result = text.withCString { sqlite3_bind_text(statement, index, $0, length, Self.transient) }
            case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
            case .real(let real): result = sqlite3_bind_double(statement, index, real)
            case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Self.transient) }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { sqlite3_finalize(statement); throw databaseError() }
        }
        return statement
    }
    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try statement(sql, values)
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw databaseError() }
    }
    private func rows(_ sql: String, _ values: [Value] = [], body: (OpaquePointer) throws -> Void) throws {
        let statement = try statement(sql, values)
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { try body(statement); result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw databaseError() }
    }
    private func strings(_ sql: String, _ values: [Value] = []) throws -> [String] {
        var result: [String] = []
        try rows(sql, values) { result.append(try text($0, 0)) }
        return result
    }
    private func integer(_ sql: String, _ values: [Value] = []) throws -> Int64 {
        var result: Int64?
        try rows(sql, values) { result = sqlite3_column_int64($0, 0) }
        guard let result else { throw UserCollectionsError.corruptData("missing integer") }
        return result
    }
    private func meta(_ key: String) throws -> String? { try strings("SELECT value FROM collections_meta WHERE key=?", [.text(key)]).first }
    private func metaInteger(_ key: String) throws -> Int64 {
        guard let raw = try meta(key), let value = Int64(raw) else { throw UserCollectionsError.corruptData(key) }
        return value
    }
    private func setMeta(_ key: String, _ value: String) throws {
        try execute("INSERT OR REPLACE INTO collections_meta VALUES(?,?)", [.text(key), .text(value)])
    }
    private func text(_ statement: OpaquePointer, _ index: Int32) throws -> String {
        guard let raw = sqlite3_column_text(statement, index) else { throw UserCollectionsError.corruptData("null text") }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard let text = String(bytes: UnsafeBufferPointer(start: raw, count: count), encoding: .utf8) else { throw UserCollectionsError.corruptData("invalid UTF-8 text") }
        return text
    }
    private func reference(_ statement: OpaquePointer, _ index: Int32) throws -> WallpaperReference {
        guard let value = WallpaperReference(storageKey: try text(statement, index)) else { throw UserCollectionsError.corruptData("reference") }
        return value
    }
    private func optionalDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }
    private func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, index))
    }
    private func decode<T: Decodable>(_ statement: OpaquePointer, _ index: Int32) throws -> T {
        guard let bytes = sqlite3_column_blob(statement, index) else { throw UserCollectionsError.corruptData("null payload") }
        do { return try JSONDecoder().decode(T.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))) }
        catch { throw UserCollectionsError.corruptData("locator payload") }
    }
    private func databaseError() -> UserCollectionsError {
        .database(database.map { String(cString: sqlite3_errmsg($0)) } ?? "closed database")
    }
}
