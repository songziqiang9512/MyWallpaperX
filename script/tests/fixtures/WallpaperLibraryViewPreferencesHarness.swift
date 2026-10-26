import Foundation

@main struct WallpaperLibraryViewPreferencesHarness {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        func ref(_ id: String) -> WallpaperReference { .init(provider: .videoLibrary, sourceID: id) }
        let a = ref("a"), b = ref("b"), new = ref("new")
        let shared = UUID(), imageOnly = UUID()
        let manifest = LibraryCollectionsMigrationManifest(schemaVersion: 1, sourceManifestID: "frozen", capturedAt: Date(timeIntervalSince1970: 100), tagMappings: [
            .init(normalizedName: "Shared", playlistID: shared, displayName: "Shared", origins: [
                .init(provider: .videoLibrary, originalName: " Shared ", isDeclared: true),
                .init(provider: .staticImageLibrary, originalName: "Shared", isDeclared: true)]),
            .init(normalizedName: "Images", playlistID: imageOnly, displayName: "Images", origins: [
                .init(provider: .staticImageLibrary, originalName: "Images", isDeclared: true)])])
        func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        func seed(_ values: [String: Any]) throws -> LibraryCollectionsViewPreferencesSeed {
            .init(preferences: .init(auxiliaryPreferences: try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0),
                videoTimeOrder: [b, a], imageTimeOrder: [.init(provider: .staticImageLibrary, sourceID: "image")]), manifest: manifest)
        }
        let frozen = try seed([
            "WallpaperSettings": data(["sortMode": "name", "sortAscending": false]),
            "PerSelectionSortStates": data([
                "category.myWallpapers": ["mode": "dateAdded", "ascending": true],
                "category.favorites": ["mode": "size", "ascending": false],
                "category.recentlyUsed": ["mode": "name", "ascending": false],
                "tag. Shared ": ["mode": "dateAdded", "ascending": false]]),
            "SILSortState": data(["mode": "addedAt", "ascending": true]),
            "gridZoomOffset": 2, "SILGridZoomOffset": -1,
            "OLDownloadsSortMode": "size", "OLDownloadsSortAscending": true,
            "onlineLibrary.gridZoomOffset": 4])
        let mapped = WallpaperLibraryViewPreferencesMigration.map(frozen)
        checks["valid-frozen-preferences-have-no-warning"] = mapped.warnings.isEmpty
        checks["video-independent-sort-survives-with-new-default-density"] = mapped.queries[.videos]?.sort == .legacyTime
            && mapped.queries[.videos]?.legacyTimeOrder == [b, a] && mapped.queries[.videos]?.preferredColumns == 5
        checks["favorite-independent-size-and-direction-survive"] = mapped.queries[.favorites]?.sort == .fileSize && mapped.queries[.favorites]?.ascending == false
        checks["shared-tag-prefers-exact-video-origin-and-keeps-uuid"] = mapped.queries[.playlist(shared)]?.sort == .legacyTime
            && mapped.queries[.playlist(shared)]?.ascending == false && mapped.queries[.playlist(shared)]?.preferredColumns == 5
        checks["image-only-tag-inherits-original-image-sort-with-new-default-density"] = mapped.queries[.playlist(imageOnly)]?.sort == .createdAt
            && mapped.queries[.playlist(imageOnly)]?.preferredColumns == 5 && mapped.queries[.images]?.sort == .createdAt
        checks["recent-retains-new-success-order-without-old-sort-or-fake-anchor"] = mapped.queries[.recent]?.sort == nil
            && mapped.queries[.recent]?.legacyTimeOrder == nil && mapped.queries.values.allSatisfy { $0.scrollAnchor == nil }
        checks["downloads-never-borrow-pixabay-only-sort-or-retired-density"] = mapped.queries[.downloads] == nil
        let fallback = WallpaperLibraryViewPreferencesMigration.map(try seed([
            "WallpaperSettings": data(["sortMode": "name", "sortAscending": false]),
            "PerSelectionSortStates": data(["category.myWallpapers": ["bad": "value"]]),
            "SILSortState": "bad opaque bytes", "gridZoomOffset": true]))
        checks["invalid-individual-preference-preserves-valid-global-fallback"] = fallback.queries[.videos]?.sort == .name
            && fallback.queries[.videos]?.ascending == false && fallback.queries[.videos]?.preferredColumns == 5 && !fallback.warnings.isEmpty
        checks["missing-legacy-input-keeps-new-defaults"] = WallpaperLibraryViewPreferencesMigration.map(
            .init(preferences: .init(), manifest: manifest)).queries[.videos]?.sort == nil
        let oldMissingDirection = WallpaperLibraryViewPreferencesMigration.map(try seed([
            "WallpaperSettings": data(["sortMode": "name"])]))
        checks["valid-ancient-global-settings-default-missing-direction-to-original-true"] = oldMissingDirection.queries[.videos]?.sort == .name
            && oldMissingDirection.queries[.videos]?.ascending == true && oldMissingDirection.warnings.isEmpty
        let oldNullDefaults = WallpaperLibraryViewPreferencesMigration.map(try seed([
            "WallpaperSettings": data(["sortMode": NSNull(), "sortAscending": NSNull()])]))
        checks["global-null-sort-fields-follow-original-decodeIfPresent-defaults"] = oldNullDefaults.queries[.videos]?.sort == .sourceOrder
            && oldNullDefaults.queries[.videos]?.ascending == true && oldNullDefaults.warnings.isEmpty
        let invalidEnum = WallpaperLibraryViewPreferencesMigration.map(try seed([
            "WallpaperSettings": data(["sortMode": "name", "sortAscending": false]),
            "PerSelectionSortStates": data(["category.myWallpapers": ["mode": "future-invalid", "ascending": true]])]))
        checks["unknown-per-selection-mode-cannot-overwrite-valid-global-sort-or-direction"] = invalidEnum.queries[.videos]?.sort == .name
            && invalidEnum.queries[.videos]?.ascending == false && !invalidEnum.warnings.isEmpty
        let invalidBoolean = WallpaperLibraryViewPreferencesMigration.map(try seed([
            "WallpaperSettings": data(["sortMode": "name", "sortAscending": 1]),
            "PerSelectionSortStates": data(["category.myWallpapers": ["mode": "size", "ascending": false]])]))
        checks["bad-global-type-cannot-overwrite-valid-per-selection-values"] = invalidBoolean.queries[.videos]?.sort == .fileSize
            && invalidBoolean.queries[.videos]?.ascending == false && !invalidBoolean.warnings.isEmpty
        let missingLocalDirection = WallpaperLibraryViewPreferencesMigration.map(try seed([
            "WallpaperSettings": data(["sortMode": "name", "sortAscending": false]),
            "PerSelectionSortStates": data(["category.myWallpapers": ["mode": "size"]]),
            "SILSortState": data(["mode": "lastUsed"])]))
        checks["strict-old-local-sort-records-do-not-invent-missing-direction"] = missingLocalDirection.queries[.videos]?.sort == .name
            && missingLocalDirection.queries[.videos]?.ascending == false && missingLocalDirection.queries[.images]?.sort == nil
        let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: "frozen", playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        func item(_ reference: WallpaperReference, date: TimeInterval) -> WallpaperContentItem {
            .init(reference: reference, providerReference: reference, locator: .init(), title: reference.sourceID, kind: .video,
                publishedAvailability: .available, capabilities: [.play, .organize], metadata: .init(createdAt: Date(timeIntervalSince1970: date)),
                acquisition: .idle, update: .idle, aliases: [])
        }
        let catalog = WallpaperLibraryCatalog(videos: [item(a, date: 500), item(b, date: 1000), item(new, date: 1)])
        var query = mapped.queries[.videos]!
        checks["legacy-time-sequence-does-not-invent-created-or-success-time"] = try WallpaperLibraryQuery.project(page: .videos, state: query, catalog: catalog, relationships: relationships).items.map(\.reference) == [b, a, new]
            && relationships.recent.isEmpty
        query.ascending = false
        checks["legacy-direction-reverses-frozen-members-with-new-items-still-last"] = try WallpaperLibraryQuery.project(page: .videos, state: query, catalog: catalog, relationships: relationships).items.map(\.reference) == [a, b, new]
        let canonical = WallpaperReference(provider: .steamWorkshop, sourceID: "published")
        let mixed = WallpaperPlaylist(id: shared, name: "Mixed", sidebarRank: 0)
        let aliased = UserCollectionsSnapshot(revision: 2, resetEpoch: relationships.resetEpoch, migrationManifestID: "frozen",
            playlists: [mixed], members: [a, b, new].enumerated().map {
                .init(playlistID: shared, reference: $0.element, position: $0.offset, addedAt: Date())
            }, favorites: [], recent: [], aliases: [.init(alias: b, canonical: canonical, proof: .publishedDownload)], locators: [])
        var mixedCatalog = catalog; mixedCatalog.downloads = [item(canonical, date: 1)]
        query.legacyTimeOrder = [b, canonical, a]
        checks["legacy-time-canonicalizes-alias-once-and-leaves-new-mixed-members-last"] = try WallpaperLibraryQuery.project(
            page: .playlist(shared), state: query, catalog: mixedCatalog, relationships: aliased).items.map(\.reference) == [a, canonical, new]
        query.ascending = true
        checks["legacy-alias-order-is-independent-of-metadata-created-time"] = try WallpaperLibraryQuery.project(
            page: .playlist(shared), state: query, catalog: mixedCatalog, relationships: aliased).items.map(\.reference) == [canonical, a, new]
        let scopeSeed = try seed([
            "WallpaperSettings": data(["sortMode": "dateAdded", "sortAscending": true]),
            "SILSortState": data(["mode": "lastUsed", "ascending": true])])
        let narrowRelations = UserCollectionsSnapshot(revision: 3, resetEpoch: relationships.resetEpoch, migrationManifestID: "frozen",
            playlists: [mixed, .init(id: imageOnly, name: "Images", sidebarRank: 1)],
            members: [canonical, new].enumerated().map { .init(playlistID: shared, reference: $0.element, position: $0.offset, addedAt: Date()) },
            favorites: [.init(reference: a, favoritedAt: nil, migrationOrder: nil)], recent: [], aliases: aliased.aliases, locators: [])
        let scoped = WallpaperLibraryViewPreferencesMigration.map(scopeSeed, relationships: narrowRelations)
        checks["published-member-scope-keeps-original-raw-alias-and-favorite-ranks-only"] = scoped.queries[.playlist(shared)]?.legacyTimeOrder == [b]
            && scoped.queries[.favorites]?.legacyTimeOrder == [a]
            && scoped.queries[.videos]?.legacyTimeOrder == [b, a]
            && scoped.queries[.images]?.legacyTimeOrder == scopeSeed.preferences.imageTimeOrder
        checks["empty-playlist-has-empty-frozen-rank-without-losing-its-sort"] = scoped.queries[.playlist(imageOnly)]?.legacyTimeOrder == []
            && scoped.queries[.playlist(imageOnly)]?.sort == .legacyTime
        checks["scoped-alias-rank-still-orders-current-canonical-member-before-new-member"] = try WallpaperLibraryQuery.project(
            page: .playlist(shared), state: scoped.queries[.playlist(shared)]!, catalog: mixedCatalog,
            relationships: narrowRelations).items.map(\.reference) == [canonical, new]
        let largeRank = (0..<64).map { ref("rank-\($0)") }
        let manyLists = (0..<12).map { WallpaperPlaylist(name: "List \($0)", sidebarRank: $0) }
        let manyManifest = LibraryCollectionsMigrationManifest(schemaVersion: 1, sourceManifestID: "many", capturedAt: Date(), tagMappings:
            manyLists.map { .init(normalizedName: $0.name, playlistID: $0.id, displayName: $0.name,
                origins: [.init(provider: .videoLibrary, originalName: $0.name, isDeclared: true)]) })
        let manySeed = LibraryCollectionsViewPreferencesSeed(preferences: .init(
            auxiliaryPreferences: scopeSeed.preferences.auxiliaryPreferences, videoTimeOrder: largeRank), manifest: manyManifest)
        let manyRelations = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: "many", playlists: manyLists,
            members: manyLists.enumerated().map { .init(playlistID: $0.element.id, reference: largeRank[$0.offset], position: 0, addedAt: Date()) },
            favorites: [], recent: [], aliases: [], locators: [])
        let compact = WallpaperLibraryViewPreferencesMigration.map(manySeed, relationships: manyRelations)
        checks["saved-frozen-ranks-grow-with-members-not-library-times-playlists"] = compact.queries.values.compactMap(\.legacyTimeOrder).reduce(0) { $0 + $1.count } == 76
            && manyLists.enumerated().allSatisfy { compact.queries[.playlist($0.element.id)]?.legacyTimeOrder == [largeRank[$0.offset]] }
        let corruptRelations = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: "bad", playlists: [], members: [],
            favorites: [], recent: [], aliases: [.init(alias: a, canonical: b, proof: .publishedDownload), .init(alias: b, canonical: a, proof: .publishedDownload)], locators: [])
        let invalidScope = WallpaperLibraryViewPreferencesMigration.map(scopeSeed, relationships: corruptRelations)
        checks["invalid-optional-member-scope-warns-without-guessing-or-truncating-frozen-preference"] = !invalidScope.warnings.isEmpty
            && invalidScope.queries[.favorites]?.legacyTimeOrder == [b, a]
        let suite = "mwx.view-preferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = WallpaperLibraryPresentation(collections: nil, defaults: defaults, migratedQueries: mapped.queries)
        checks["only-absent-new-key-admits-frozen-seed"] = model.queryState == mapped.queries[.videos]
        _ = model.update(catalog: catalog, relationships: relationships)
        var edited = model.queryState; edited.sort = .name; edited.legacyTimeOrder = nil
        _ = model.setQueryState(edited)
        let reopened = WallpaperLibraryPresentation(collections: nil, defaults: defaults, migratedQueries: mapped.queries)
        checks["existing-new-state-wins-over-frozen-seed"] = reopened.queryState == edited
        model.resetViewState()
        checks["reset-persists-empty-new-state-and-blocks-reseed"] = WallpaperLibraryPresentation(collections: nil, defaults: defaults, migratedQueries: mapped.queries).queryState == .init()
        let invalid = Data("unsupported future bytes".utf8)
        defaults.set(invalid, forKey: WallpaperLibraryPresentation.settingsKey)
        let recovery = WallpaperLibraryPresentation(collections: nil, defaults: defaults, migratedQueries: mapped.queries)
        _ = recovery.update(catalog: catalog, relationships: relationships)
        checks["corrupt-new-state-is-preserved-with-warning-and-never-seeded"] = recovery.queryState == .init()
            && recovery.lastError != nil && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == invalid
        let future = try data(["version": 99, "page": ["videos": [:]], "queries": []])
        defaults.set(future, forKey: WallpaperLibraryPresentation.settingsKey)
        let futureModel = WallpaperLibraryPresentation(collections: nil, defaults: defaults, migratedQueries: mapped.queries)
        _ = futureModel.update(catalog: catalog, relationships: relationships)
        checks["future-new-settings-never-replay-legacy-seed-or-overwrite-original-bytes"] = futureModel.queryState == .init()
            && futureModel.lastError != nil && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == future

        // Exercise the persisted product codec, not a replica of its migration.
        func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
        let geometryQuery = WallpaperLibraryQueryState(search: "preserve all fields", provider: .steamWorkshop, kind: .scene,
            status: .failed, sort: .legacyTime, ascending: false, legacyTimeOrder: [b, a], preferredColumns: 3,
            scrollAnchor: b, scrollOffset: -27.5, scrollAtTop: false)
        var allDensitiesRoundTrip = true
        for columns in 3...6 {
            var state = geometryQuery; state.preferredColumns = columns
            let decoded = try JSONDecoder().decode(WallpaperLibraryQueryState.self, from: JSONEncoder().encode(state))
            allDensitiesRoundTrip = allDensitiesRoundTrip && decoded == state
        }
        checks["all-explicit-column-preferences-round-trip-with-independent-query-fields"] = allDensitiesRoundTrip
        let queryObject = try object(geometryQuery) as! [String: Any]
        checks["current-query-encodes-one-column-preference-and-no-retired-zoom"] = queryObject["preferredColumns"] as? Int == 3 && queryObject["zoomOffset"] == nil
        var legacyQueryObject = queryObject
        legacyQueryObject.removeValue(forKey: "preferredColumns")
        legacyQueryObject.removeValue(forKey: "scrollOffset")
        legacyQueryObject.removeValue(forKey: "scrollAtTop")
        legacyQueryObject["zoomOffset"] = -2
        var expectedLegacyQuery = geometryQuery
        expectedLegacyQuery.preferredColumns = 5; expectedLegacyQuery.scrollOffset = nil; expectedLegacyQuery.scrollAtTop = nil
        let pageObject = try object(WallpaperLibraryPage.videos)
        let imagePageObject = try object(WallpaperLibraryPage.images)
        var legacyImageQuery = legacyQueryObject; legacyImageQuery["zoomOffset"] = 4; legacyImageQuery["search"] = "image session"
        let legacyEnvelope: [String: Any] = ["version": 1, "page": pageObject,
            "queries": [["page": pageObject, "query": legacyQueryObject], ["page": imagePageObject, "query": legacyImageQuery]],
            "directoryScrollAnchor": shared.uuidString]
        let legacyBytes = try data(legacyEnvelope)
        defaults.set(legacyBytes, forKey: WallpaperLibraryPresentation.settingsKey)
        let migrated = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        let upgradedBytes = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!
        let upgradedEnvelope = try JSONSerialization.jsonObject(with: upgradedBytes) as! [String: Any]
        let upgradedQueries = upgradedEnvelope["queries"] as! [[String: Any]]
        checks["known-v1-upgrades-same-key-to-v2-without-guessing-scroll-or-density"] = migrated.queryState == expectedLegacyQuery
            && migrated.directoryScrollAnchor == shared && migrated.directoryScrollOffset == nil && migrated.directoryScrollAtTop == nil
            && upgradedEnvelope["version"] as? Int == 2 && upgradedBytes != legacyBytes
            && upgradedQueries.allSatisfy { ($0["query"] as? [String: Any])?["preferredColumns"] as? Int == 5
                && ($0["query"] as? [String: Any])?["zoomOffset"] == nil }
        let upgradedAgain = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["v1-upgrade-is-once-and-retains-other-page-session-without-replaying-seed"] = upgradedAgain.queryState == expectedLegacyQuery
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == upgradedBytes
            && upgradedAgain.switchPage(.images) && upgradedAgain.queryState.search == "image session" && upgradedAgain.queryState.preferredColumns == 5
            && upgradedAgain.queryState.scrollOffset == nil && upgradedAgain.queryState.scrollAtTop == nil
        defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
        let geometryModel = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        _ = geometryModel.setQueryState(geometryQuery)
        geometryModel.setDirectoryScrollAnchor(imageOnly, offset: -19.25, atTop: false)
        let preciseBytes = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!
        let precise = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["known-v2-restores-finite-negative-query-and-directory-offsets-exactly"] = precise.queryState == geometryQuery
            && precise.directoryScrollAnchor == imageOnly && precise.directoryScrollOffset == -19.25 && precise.directoryScrollAtTop == false
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == preciseBytes
        precise.setDirectoryScrollAnchor(imageOnly, offset: -19.25, atTop: true)
        let atTop = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["directory-explicit-top-is-not-confused-with-same-first-card-and-offset"] = atTop.directoryScrollAnchor == imageOnly
            && atTop.directoryScrollOffset == -19.25 && atTop.directoryScrollAtTop == true
        let anchoredRelations = UserCollectionsSnapshot(revision: 10, resetEpoch: relationships.resetEpoch, migrationManifestID: "frozen",
            playlists: [.init(id: imageOnly, name: "Images", sidebarRank: 0)], members: [], favorites: [], recent: [], aliases: [], locators: [])
        _ = atTop.update(catalog: catalog, relationships: anchoredRelations)
        let removedRelations = UserCollectionsSnapshot(revision: 11, resetEpoch: relationships.resetEpoch, migrationManifestID: "frozen",
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        _ = atTop.update(catalog: catalog, relationships: removedRelations)
        checks["deleted-directory-reference-retires-its-offset-but-preserves-explicit-true-top"] = atTop.directoryScrollAnchor == nil
            && atTop.directoryScrollOffset == nil && atTop.directoryScrollAtTop == true
        let v2Envelope = try JSONSerialization.jsonObject(with: preciseBytes) as! [String: Any]
        func invalidEnvelope(_ query: [String: Any], version: Int = 2) throws -> Data {
            var envelope = v2Envelope; envelope["version"] = version
            envelope["queries"] = [["page": pageObject, "query": query]]
            return try data(envelope)
        }
        var pagePayloadsRejected = true
        for payload in [42, NSNull(), []] as [Any] {
            for key in ["workshop", "workshopSubscriptions"] {
                let bytes = try data([key: payload])
                pagePayloadsRejected = pagePayloadsRejected && (try? JSONDecoder().decode(WallpaperLibraryPage.self, from: bytes)) == nil
            }
        }
        checks["retired-and-current-page-codecs-still-reject-nonobject-enum-payloads"] = pagePayloadsRejected
        var currentPagesRoundTrip = true
        for page in [WallpaperLibraryPage.videos, .images, .downloads, .recent, .workshop, .pixabay, .playlists, .favorites, .playlist(shared)] {
            let decoded = try JSONDecoder().decode(WallpaperLibraryPage.self, from: JSONEncoder().encode(page))
            currentPagesRoundTrip = currentPagesRoundTrip && decoded == page
        }
        checks["all-current-page-cases-keep-the-original-associated-value-codec"] = currentPagesRoundTrip
        let publicQuery = WallpaperLibraryQueryState(search: "public", sort: .name, preferredColumns: 6,
            scrollAnchor: a, scrollOffset: 14, scrollAtTop: false)
        let privateQuery = WallpaperLibraryQueryState(search: "private", provider: .steamWorkshop, kind: .scene,
            status: .failed, sort: .fileSize, ascending: false, preferredColumns: 3,
            scrollAnchor: b, scrollOffset: -12, scrollAtTop: false)
        let publicEntry: [String: Any] = ["page": ["workshop": [:]], "query": try object(publicQuery)]
        let oldPersonalEntry: [String: Any] = ["page": ["workshopSubscriptions": [:]], "query": try object(privateQuery)]
        func oldSubscriptionsEnvelope(_ entries: [[String: Any]]) throws -> Data {
            try data(["version": 2, "page": ["workshopSubscriptions": [:]], "queries": entries])
        }
        var publicAlwaysWins = true
        for entries in [[publicEntry, oldPersonalEntry], [oldPersonalEntry, publicEntry]] {
            defaults.set(try oldSubscriptionsEnvelope(entries), forKey: WallpaperLibraryPresentation.settingsKey)
            let restored = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
            let canonicalBytes = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!
            let reopened = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
            publicAlwaysWins = publicAlwaysWins && restored.page == .workshop && restored.queryState == publicQuery
                && restored.lastError == nil && reopened.queryState == publicQuery
                && !String(decoding: canonicalBytes, as: UTF8.self).contains("workshopSubscriptions")
        }
        checks["legacy-subscriptions-folds-into-public-session-independently-of-array-order"] = publicAlwaysWins
        defaults.set(try oldSubscriptionsEnvelope([oldPersonalEntry]), forKey: WallpaperLibraryPresentation.settingsKey)
        let personalOnly = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["legacy-personal-only-session-migrates-geometry-without-private-search-or-facets"] = personalOnly.page == .workshop
            && personalOnly.lastError == nil && personalOnly.queryState == .init(preferredColumns: 3,
                scrollAnchor: b, scrollOffset: -12, scrollAtTop: false)
        var duplicateSessionsRejected = true
        for entries in [[publicEntry, publicEntry], [oldPersonalEntry, oldPersonalEntry]] {
            let duplicateBytes = try oldSubscriptionsEnvelope(entries)
            defaults.set(duplicateBytes, forKey: WallpaperLibraryPresentation.settingsKey)
            let rejected = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
            duplicateSessionsRejected = duplicateSessionsRejected && rejected.lastError != nil
                && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == duplicateBytes
        }
        checks["legacy-folding-does-not-admit-genuine-duplicate-page-records"] = duplicateSessionsRejected
        var invalidStatesStayReadOnly = true
        for badValue in [2, 7, "5", true] as [Any] {
            var invalidQuery = queryObject; invalidQuery["preferredColumns"] = badValue
            let bytes = try invalidEnvelope(invalidQuery)
            defaults.set(bytes, forKey: WallpaperLibraryPresentation.settingsKey)
            let refused = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
            _ = refused.setQueryState(.init(preferredColumns: 6))
            invalidStatesStayReadOnly = invalidStatesStayReadOnly && refused.lastError != nil
                && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == bytes
        }
        checks["known-invalid-column-count-or-type-preserves-original-bytes-during-browsing"] = invalidStatesStayReadOnly
        var badLegacy = legacyQueryObject; badLegacy["zoomOffset"] = "not an old integer"
        let badLegacyBytes = try invalidEnvelope(badLegacy, version: 1)
        defaults.set(badLegacyBytes, forKey: WallpaperLibraryPresentation.settingsKey)
        let refusedLegacy = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["v1-retired-zoom-bad-type-is-not-silently-accepted-or-rewritten"] = refusedLegacy.lastError != nil
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == badLegacyBytes
        var missingColumns = queryObject; missingColumns.removeValue(forKey: "preferredColumns")
        checks["missing-column-key-decodes-new-five-column-default-without-other-loss"] = try JSONDecoder().decode(
            WallpaperLibraryQueryState.self, from: data(missingColumns)).preferredColumns == 5
        var nonFiniteObject = queryObject; nonFiniteObject["scrollOffset"] = "NaN"
        let nonFiniteDecoder = JSONDecoder()
        nonFiniteDecoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        checks["query-codec-refuses-nonfinite-offset-even-with-custom-float-decoding"] = (try? nonFiniteDecoder.decode(
            WallpaperLibraryQueryState.self, from: data(nonFiniteObject))) == nil
        let futureGeometryBytes = try invalidEnvelope(queryObject, version: 3)
        defaults.set(futureGeometryBytes, forKey: WallpaperLibraryPresentation.settingsKey)
        let futureGeometry = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        futureGeometry.setScrollAnchor(a, offset: 0, atTop: true)
        futureGeometry.setDirectoryScrollAnchor(shared, offset: 0, atTop: true)
        checks["future-version-geometry-is-never-rewritten-through-scroll-setters"] = futureGeometry.lastError != nil
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == futureGeometryBytes

        defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
        let facets = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        func facet(_ id: String, provider: WallpaperProvider, kind: WallpaperMediaKind, title: String, available: Bool) -> WallpaperContentItem {
            let ref = WallpaperReference(provider: provider, sourceID: id)
            return .init(reference: ref, providerReference: ref, locator: .init(mediaKind: kind), title: title, kind: kind,
                publishedAvailability: available ? .available : .unavailable, capabilities: available ? [.inspect, .play] : [.inspect],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        let facetCatalog = WallpaperLibraryCatalog(downloads: [
            facet("video", provider: .steamWorkshop, kind: .video, title: "needle", available: true),
            facet("scene", provider: .steamWorkshop, kind: .scene, title: "needle", available: false),
            facet("web", provider: .steamWorkshop, kind: .web, title: "background", available: true),
            facet("stock", provider: .pixabay, kind: .video, title: "needle", available: true)])
        _ = facets.update(catalog: facetCatalog, relationships: relationships)
        _ = facets.switchPage(.downloads)
        let facetQuery = WallpaperLibraryQueryState(search: "needle", provider: .steamWorkshop, kind: .scene,
            status: .playable, sort: .name, ascending: false)
        _ = facets.setQueryState(facetQuery)
        checks["type-counts-remove-only-kind-filter-and-preserve-search-provider-status"] = facets.mediaKindCounts == [.video: 1]
            && facets.queryResult.items.isEmpty && facets.queryState == facetQuery
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
