import Combine
import Foundation

@main struct WallpaperLibraryPresentationHarness {
    @MainActor static func main() async throws {
        var checks: [String: Bool] = [:]
        let suite = "mwx.presentation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func ref(_ provider: WallpaperProvider, _ id: String) -> WallpaperReference { .init(provider: provider, sourceID: id) }
        func persistedQueryPages(_ defaults: UserDefaults) throws -> [WallpaperLibraryPage] {
            let object = try JSONSerialization.jsonObject(with: defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!) as! [String: Any]
            return try (object["queries"] as! [[String: Any]]).map {
                try JSONDecoder().decode(WallpaperLibraryPage.self, from: JSONSerialization.data(withJSONObject: $0["page"]!))
            }
        }
        func item(_ reference: WallpaperReference, title: String? = nil, kind: WallpaperMediaKind = .video,
                  available: Bool = true, thumbnail: String? = "/isolated/cover.png", owner: WallpaperReference? = nil) -> WallpaperContentItem {
            .init(reference: reference, providerReference: owner ?? reference,
                  locator: .init(path: "/isolated/media", titleHint: title ?? reference.sourceID, mediaKind: kind),
                  title: title ?? reference.sourceID, kind: kind, publishedAvailability: available ? .available : .unavailable,
                  capabilities: available ? [.play, .organize, .inspect] : [.inspect],
                  metadata: .init(thumbnailPath: thumbnail), acquisition: .idle, update: .idle, aliases: [])
        }
        let store = UserCollectionsStore(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let initial = try await store.snapshot()
        let controller = UserCollectionsController(store: store, snapshot: initial)
        let model = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
        var deliveries: [WallpaperLibraryPresentationState] = []
        let observation = model.$state.sink { deliveries.append($0) }
        defer { observation.cancel() }
        let a = ref(.videoLibrary, "a"), b = ref(.videoLibrary, "b"), image = ref(.staticImageLibrary, "a")
        let steam = ref(.steamWorkshop, "a"), backing = ref(.videoLibrary, "backing")
        let missing = ref(.pixabay, "missing"), noCover = ref(.pixabay, "no-cover")
        let nfc = ref(.videoLibrary, "\u{E9}"), nfd = ref(.videoLibrary, "e\u{301}")
        var catalog = WallpaperLibraryCatalog(videos: [item(a, title: "Alpha"), item(b, title: "Beta"), item(backing), item(nfc), item(nfd)],
            images: [item(image, kind: .image, thumbnail: nil)],
            downloads: [item(steam, kind: .scene), item(noCover, thumbnail: nil)])
        let first = try await controller.createPlaylist(name: "Zulu", at: Date(timeIntervalSince1970: 100))
        let second = try await controller.createPlaylist(name: "Alpha list", at: Date(timeIntervalSince1970: 200))
        let refs = [missing, backing, steam, noCover, image, a, b, nfc, nfd]
        try await controller.perform(.addMembers(first, refs.map { .init(reference: $0, locator: .init(titleHint: $0.sourceID), isPublishedLocally: true, isAvailable: true) }, Date(timeIntervalSince1970: 300)))
        try await controller.perform(.linkAlias(.init(alias: backing, canonical: steam, proof: .publishedDownload), Date(timeIntervalSince1970: 400)))
        var relations = controller.snapshot
        checks["injectedControllerIsOnlyRelationshipWriter"] = model.canEditCollections && model.collections === controller
        checks["publishedCatalogIsOnlyQueryInput"] = model.update(catalog: catalog, relationships: relations) && model.queryResult.items.map(\.reference) == [a, b, nfc, nfd]
        checks["relationshipRevisionIsDerivedFromTheAcceptedQuerySnapshot"] = model.relationshipsRevision == relations.revision
        model.setSelection([a, nfc, nfd], focused: a, isSelecting: true)
        let originalSelection = model.selectionState
        model.setSelection([a, nfc, nfd], focused: a, isSelecting: true)
        checks["idempotentSelectionDoesNotRevokeActionSession"] = model.selectionState.sessionID == originalSelection.sessionID
        model.switchPage(.videos)
        checks["choosingTheCurrentPageDoesNotEndItsSelectionSession"] = model.selectionState == originalSelection
        var videoQuery = model.queryState
        videoQuery.preferredColumns = 4
        videoQuery.scrollAnchor = a
        videoQuery.scrollOffset = -14.5
        videoQuery.scrollAtTop = false
        model.setQueryState(videoQuery)
        let validSettingsBeforeBadAnchor = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)
        model.setScrollAnchor(ref(.videoLibrary, ""))
        checks["invalidAnchorCannotPoisonOwnPersistedSettings"] = model.queryState == videoQuery && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == validSettingsBeforeBadAnchor && model.lastError != nil
        model.setQueryState(videoQuery)
        checks["opaqueUnicodeSelectionsRemainDistinct"] = model.selectionState.references.count == 3
        let beforeSwitchDeliveries = deliveries.count
        model.switchPage(.images)
        checks["pagePublisherDeliversOneConsistentNavigationSnapshot"] = deliveries.count == beforeSwitchDeliveries + 1 && deliveries.last?.page == .images && deliveries.last?.queryResult.items.map(\.reference) == [image] && deliveries.last?.selectionState.references.isEmpty == true
        model.setSelection([image], focused: image)
        model.setQueryState(.init(search: "a", preferredColumns: 6, scrollAnchor: image, scrollOffset: 21, scrollAtTop: false))
        model.switchPage(.videos)
        checks["returnVisitRestoresQueryAndScrollWithoutOldSelectionMode"] = model.queryState == videoQuery
            && model.selectionState.references.isEmpty && model.selectionState.focusedReference == nil && !model.selectionState.isSelecting
        checks["returnVisitRevokesOldActionSession"] = model.selectionState.sessionID != originalSelection.sessionID && !model.setSelection([], expectedSessionID: originalSelection.sessionID)
        let visibleBeforeLateScroll = model.queryState
        let selectionBeforeLateScroll = model.selectionState
        let publicationsBeforeLateScroll = deliveries.count
        model.setScrollAnchor(image, offset: -22.5, atTop: false, page: .images)
        checks["settledScrollForDepartedPageDoesNotPublishOverCurrentPageOrRevokeItsAction"] = model.queryState == visibleBeforeLateScroll
            && model.selectionState == selectionBeforeLateScroll && deliveries.count == publicationsBeforeLateScroll
        let lateScrollRestored = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
        _ = lateScrollRestored.switchPage(.images)
        checks["departedPageScrollIsPersistedForItsOwnReturnVisit"] = lateScrollRestored.queryState.scrollAnchor == image
            && lateScrollRestored.queryState.scrollOffset == -22.5 && lateScrollRestored.queryState.scrollAtTop == false
        // Restore the earlier independent-page geometry for the remaining
        // selection/alias/removal checks below.
        model.setScrollAnchor(image, offset: 21, atTop: false, page: .images)
        let currentSession = model.selectionState.sessionID
        model.setSelection([b], focused: b)
        checks["newSelectionRevokesLateCompletionInSamePage"] = !model.setSelection([], expectedSessionID: currentSession) && model.selectionState.references == [b]
        model.setQueryState(.init(search: "Alpha", preferredColumns: 4))
        checks["filterPrunesInvisibleSelectionWithoutRelationshipEdits"] = model.selectionState.references.isEmpty && controller.snapshot == relations
        model.setQueryState(videoQuery)
        model.switchPage(.playlist(first))
        model.setSelection([image], focused: image)
        model.setQueryState(.init(sort: .name, ascending: false, preferredColumns: 3, scrollAnchor: image, scrollOffset: -10, scrollAtTop: false))
        let memberQuery = model.queryState
        model.switchPage(.playlists)
        checks["directoryExcludesCreateCardAndKeepsSidebarRank"] = model.directoryEntries.map(\.id) == [first, second]
        let firstEntry = model.directoryEntries.first!
        checks["directoryCanonicalCountIncludesUnavailableMembers"] = firstEntry.count == 8
        checks["firstUnavailableCanonicalMemberIsCoverCandidateWithoutBorrowingHealthySecond"] = firstEntry.coverReference == missing
            && model.queryResult.items.isEmpty
        func withFirstMember(_ reference: WallpaperReference) -> UserCollectionsSnapshot {
            let reordered = relations.members.map { member -> WallpaperPlaylistMember in
                var copy = member
                if member.playlistID == first { copy.position = member.reference == reference ? -1 : member.position }
                return copy
            }
            return .init(revision: relations.revision, resetEpoch: relations.resetEpoch, migrationManifestID: relations.migrationManifestID,
                playlists: relations.playlists, members: reordered, favorites: relations.favorites, recent: relations.recent,
                aliases: relations.aliases, locators: relations.locators)
        }
        // The real Store has already merged the alias member into its
        // canonical identity. Reorder that stored member, not the retired key.
        checks["aliasStoreSnapshotUsesCanonicalMemberBeforeCoverOwnerProbe"] = relations.members.contains { $0.playlistID == first && $0.reference == steam }
            && !relations.members.contains { $0.playlistID == first && $0.reference == backing }
        let backingFirst = withFirstMember(steam)
        let canonicalDirectory = try WallpaperLibraryQuery.directory(state: .init(), catalog: catalog, relationships: backingFirst)
        checks["firstCanonicalAliasUsesRealPublishedProviderOwnerAndDeduplicatesCount"] = canonicalDirectory.first?.coverReference == steam
            && canonicalDirectory.first?.count == 8
        var backingOnly = catalog
        backingOnly.downloads.removeAll { $0.reference == steam }
        let fallbackDirectory = try WallpaperLibraryQuery.directory(state: .init(), catalog: backingOnly, relationships: backingFirst)
        checks["firstAliasBackingUsesRealThumbnailOwnerNotCanonicalProvider"] = fallbackDirectory.first?.coverReference == backing
            && fallbackDirectory.first?.count == firstEntry.count
        let videoPreviewOnly = WallpaperContentItem(reference: noCover, providerReference: noCover, locator: .init(), title: "Only moving preview", kind: .video,
            publishedAvailability: .available, capabilities: [.inspect], metadata: .init(previewVideoURL: URL(string: "https://example.invalid/preview.mp4")),
            acquisition: .idle, update: .idle, aliases: [])
        var movingOnly = catalog
        movingOnly.downloads = [videoPreviewOnly]
        checks["movingPreviewFirstRetainsIdentityInsteadOfBorrowingLaterStaticCover"] = try WallpaperLibraryQuery.directory(state: .init(), catalog: movingOnly, relationships: withFirstMember(noCover)).first?.coverReference == noCover
        checks["temporaryMemberSortDoesNotChangeManualFirstCoverIdentity"] = firstEntry.coverReference == missing && memberQuery.sort == .name
        model.setDirectoryScrollAnchor(first, offset: -6, atTop: false)
        for sort in [WallpaperLibrarySort.name, .createdAt, .modifiedAt, .fileSize] {
            let query = WallpaperLibraryQueryState(sort: sort, ascending: false, preferredColumns: 4)
            checks["retiredDirectorySortCannotReplaceRankOrder-\(sort.rawValue)"] = model.setQueryState(query)
                && model.directoryEntries.map(\.id) == [first, second] && model.permitsDirectoryReordering
                && model.queryState == query
        }
        let entries = model.directoryEntries
        let validDirectoryQuery = model.queryState
        checks["directoryDoesNotSilentlyIgnoreUnsupportedMediaFilter"] = !model.setQueryState(.init(kinds: [.scene])) && model.directoryEntries == entries && model.queryState == validDirectoryQuery
        model.setQueryState(.init(search: "alpha"))
        checks["directorySearchFiltersOnlyDirectoryNotMembers"] = model.directoryEntries.map(\.id) == [second] && controller.snapshot == relations
        model.switchPage(.playlist(first))
        checks["directoryQueryDoesNotLeakIntoMemberPage"] = model.queryState == memberQuery && model.queryResult.items.count == 8
        model.setSelection([image], focused: image)
        let renameSession = model.selectionState.sessionID
        let renameMetadata = controller.snapshot.playlists.first { $0.id == first }!.metadata
        var renamedMetadata = renameMetadata; renamedMetadata.name = "Renamed"
        try await controller.perform(.editPlaylistMetadata(id: first, expected: renameMetadata,
            replacement: renamedMetadata, coverAsset: nil, at: Date(timeIntervalSince1970: 500)))
        relations = controller.snapshot
        model.update(catalog: catalog, relationships: relations)
        checks["renamePreservesPageQueryAnchorAndSelectionSession"] = model.page == .playlist(first) && model.queryState == memberQuery && model.selectionState.sessionID == renameSession && model.selectionState.references == [image]
        // Alias redirection changes relationship identity, never the source command.
        model.switchPage(.videos)
        model.setSelection([b], focused: b)
        model.setScrollAnchor(b, offset: -17.25, atTop: false)
        try await controller.perform(.linkAlias(.init(alias: b, canonical: a, proof: .explicitUserRelocation), Date(timeIntervalSince1970: 600)))
        relations = controller.snapshot
        model.update(catalog: catalog, relationships: relations)
        checks["aliasUpdateCanonicalizesSelectionAndScrollAnchor"] = model.selectionState.references == [a] && model.selectionState.focusedReference == a && model.queryState.scrollAnchor == a
            && model.queryState.scrollOffset == -17.25 && model.queryState.scrollAtTop == false
        let beforeItems = model.queryResult.items
        let beforeSelection = model.selectionState
        let invalid = UserCollectionsSnapshot(revision: relations.revision + 5, resetEpoch: relations.resetEpoch, migrationManifestID: nil,
            playlists: relations.playlists, members: relations.members, favorites: [], recent: [],
            aliases: [.init(alias: b, canonical: a, proof: .explicitUserRelocation), .init(alias: b, canonical: image, proof: .explicitUserRelocation)], locators: [])
        checks["queryFailureKeepsLastValidItemsPageAndSelection"] = !model.update(catalog: .init(), relationships: invalid)
            && model.relationshipsRevision == relations.revision && model.queryResult.items == beforeItems && model.selectionState == beforeSelection && model.page == .videos
        checks["failedInputDoesNotReplaceLastValidQueryAuthority"] = model.setQueryState(videoQuery) && model.queryResult.items == beforeItems && model.lastError == nil
        catalog.videos.removeAll { $0.reference == a || $0.reference == b }
        model.update(catalog: catalog, relationships: relations)
        checks["samePageRemovalPrunesSelectionButRetainsOtherPageSession"] = model.selectionState.references.isEmpty
        model.switchPage(.images)
        checks["otherPageDensityAndScrollGeometryRestoreWithoutRetiredSelection"] = model.selectionState.references.isEmpty
            && !model.selectionState.isSelecting
            && model.queryState.preferredColumns == 6 && model.queryState.scrollOffset == 21 && model.queryState.scrollAtTop == false
        model.switchPage(.workshop)
        model.setSelection([steam], focused: steam)
        model.update(catalog: catalog, relationships: relations)
        checks["remoteSelectionNotErasedByAbsentLocalCatalog"] = model.selectionState.references == [steam]
        model.switchPage(.playlist(first))
        try await controller.perform(.deletePlaylist(first))
        model.update(catalog: catalog, relationships: controller.snapshot)
        checks["deletingCurrentPlaylistReturnsDirectoryNotAnotherSource"] = model.page == .playlists && model.directoryEntries.map(\.id) == [second]
        checks["deletedDirectoryAnchorAndItsOffsetAreRetired"] = model.directoryScrollAnchor == nil
            && model.directoryScrollOffset == nil && model.directoryScrollAtTop == nil
        let afterPlaylistDeletion = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)
        let stateAfterPlaylistDeletion = model.queryState
        model.setScrollAnchor(image, offset: -10, atTop: false, page: .playlist(first))
        let pagesAfterDeletedReceipt = try persistedQueryPages(defaults)
        checks["lateScrollForDeletedPlaylistCannotRecreateItsRetiredQuery"] = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == afterPlaylistDeletion
            && model.page == .playlists && model.queryState == stateAfterPlaylistDeletion
            && pagesAfterDeletedReceipt.contains(.playlist(first)) == false
        model.setDirectoryScrollAnchor(second, offset: 11.5, atTop: true)
        model.setQueryState(.init(search: "Alpha", sort: .name, preferredColumns: 4))
        let restored = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
        checks["settingsRestorePageQueryAndIndependentDirectoryAnchor"] = restored.page == .playlists && restored.queryState == model.queryState && restored.directoryScrollAnchor == second
            && restored.directoryScrollOffset == 11.5 && restored.directoryScrollAtTop == true
        model.switchPage(.playlist(second))
        model.setQueryState(.init(search: "preserve on recovery", preferredColumns: 4))
        let recoverySettings = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)
        let recovering = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        recovering.update(catalog: catalog, relationships: initial, relationshipsKnown: false)
        checks["unreadableRelationshipsCannotEraseSavedPlaylistPageOrQuery"] = recovering.page == .playlist(second)
            && recovering.queryState.search == "preserve on recovery" && recovering.queryResult.items.isEmpty
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == recoverySettings
        recovering.update(catalog: catalog, relationships: controller.snapshot)
        checks["laterKnownRelationshipsRestoreSavedPlaylistWithoutFalseDeletion"] = recovering.page == .playlist(second)
            && recovering.queryState.search == "preserve on recovery"
        model.switchPage(.playlists)
        let raw = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!
        for retired in [WallpaperLibraryStatusFilter.transferring, .failed] {
            let downloadsPage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WallpaperLibraryPage.downloads))
            let favoritesPage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WallpaperLibraryPage.favorites))
            var oldQuery = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WallpaperLibraryQueryState(
                search: "retained text", preferredColumns: 4))) as! [String: Any]
            for key in ["providers", "kinds", "statuses"] { oldQuery.removeValue(forKey: key) }
            oldQuery["status"] = retired.rawValue
            oldQuery.removeValue(forKey: "showsAdultContent")
            let oldState: [String: Any] = ["version": 2, "page": downloadsPage,
                "queries": [["page": downloadsPage, "query": oldQuery], ["page": favoritesPage, "query": oldQuery]]]
            defaults.set(try JSONSerialization.data(withJSONObject: oldState), forKey: WallpaperLibraryPresentation.settingsKey)
            let migrated = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
            migrated.update(catalog: catalog, relationships: controller.snapshot)
            checks["old-downloads-\(retired.rawValue)-migrates-to-all-with-query-and-geometry-intact"] = migrated.page == .downloads
                && migrated.queryState.statuses.isEmpty && migrated.queryState.search == "retained text"
                && migrated.queryState.preferredColumns == 4 && migrated.queryState.showsAdultContent && migrated.lastError == nil
            migrated.switchPage(.favorites)
            checks["retired-task-filter-migration-does-not-rewrite-another-page-\(retired.rawValue)"] = migrated.queryState.statuses == [retired]
            migrated.switchPage(.downloads)
            migrated.setQueryState(.init(showsAdultContent: false))
            let reopened = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
            reopened.update(catalog: catalog, relationships: controller.snapshot)
            checks["adult-filter-persists-through-the-original-page-settings-owner-\(retired.rawValue)"] = reopened.page == .downloads
                && !reopened.queryState.showsAdultContent && reopened.queryState.statuses.isEmpty
        }
        let mixedFilter = WallpaperLibraryQueryState(search: "mixed filters", providers: [.steamWorkshop, .pixabay], kinds: [.video, .scene],
            statuses: [.playable, .transferring, .failed], sort: .name, preferredColumns: 4, scrollOffset: -7, scrollAtTop: false,
            showsAdultContent: false)
        let mixedDownloadsPage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WallpaperLibraryPage.downloads))
        let mixedFavoritesPage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WallpaperLibraryPage.favorites))
        let mixedQueryObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mixedFilter))
        let mixedState: [String: Any] = ["version": 2, "page": mixedDownloadsPage,
            "queries": [["page": mixedDownloadsPage, "query": mixedQueryObject], ["page": mixedFavoritesPage, "query": mixedQueryObject]]]
        defaults.set(try JSONSerialization.data(withJSONObject: mixedState), forKey: WallpaperLibraryPresentation.settingsKey)
        let migratedMixed = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
        migratedMixed.update(catalog: catalog, relationships: controller.snapshot)
        var expectedDownloads = mixedFilter; expectedDownloads.statuses = [.playable]
        checks["downloads-removes-only-retired-statuses-and-preserves-composed-filters-and-geometry"] =
            migratedMixed.queryState == expectedDownloads && migratedMixed.lastError == nil
        migratedMixed.switchPage(.favorites)
        checks["downloads-status-migration-never-truncates-another-pages-multiselect-filters"] = migratedMixed.queryState == mixedFilter
        let reopenedMixed = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
        checks["multiselect-page-settings-retain-all-facets-and-per-page-migration-after-reopening"] =
            reopenedMixed.page == .favorites && reopenedMixed.queryState == mixedFilter
            && reopenedMixed.switchPage(.downloads) && reopenedMixed.queryState == expectedDownloads
        defaults.set(raw, forKey: WallpaperLibraryPresentation.settingsKey)
        var saved = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        checks["settingsPersistNoMediaOrRelationshipSnapshot"] = Set(saved.keys).isSubset(of: ["version", "page", "queries", "directoryScrollAnchor", "directoryScrollOffset", "directoryScrollAtTop"]) && saved["relationships"] == nil
        saved["version"] = 99
        let future = try JSONSerialization.data(withJSONObject: saved)
        defaults.set(future, forKey: WallpaperLibraryPresentation.settingsKey)
        let unsupported = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        unsupported.switchPage(.images)
        unsupported.setQueryState(.init(search: "local browsing"))
        unsupported.update(catalog: catalog, relationships: controller.snapshot)
        checks["futureSettingsRemainByteIdenticalDuringReadOnlyRecovery"] = !unsupported.canEditCollections && unsupported.page == .images && unsupported.lastError != nil && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == future
        let corrupt = Data([0xFF, 0x00, 0x2A])
        defaults.set(corrupt, forKey: WallpaperLibraryPresentation.settingsKey)
        let brokenJSON = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        brokenJSON.switchPage(.downloads)
        checks["corruptSettingsDataNotReplacedByFreshPage"] = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == corrupt && brokenJSON.lastError != nil
        defaults.set("bad original raw", forKey: WallpaperLibraryPresentation.settingsKey)
        let damaged = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        damaged.switchPage(.favorites)
        checks["damagedSettingsTypeNotOverwrittenWithEmptyDefaults"] = defaults.string(forKey: WallpaperLibraryPresentation.settingsKey) == "bad original raw" && damaged.lastError != nil
        checks["viewOperationsNeverChangeStoreOrPlaybackMetadata"] = try await store.snapshot() == controller.snapshot && controller.snapshot.recent.isEmpty
        let resetSuite = "mwx.presentation.reset." + UUID().uuidString
        let resetDefaults = UserDefaults(suiteName: resetSuite)!
        defer { resetDefaults.removePersistentDomain(forName: resetSuite) }
        let resetModel = WallpaperLibraryPresentation(collections: controller, defaults: resetDefaults)
        resetModel.update(catalog: catalog, relationships: controller.snapshot)
        resetModel.switchPage(.playlist(second))
        resetModel.setQueryState(.init(search: "must not revive after reset", preferredColumns: 3,
            scrollAnchor: image, scrollOffset: -31, scrollAtTop: false))
        resetModel.switchPage(.videos)
        resetModel.setSelection([nfc], focused: nfc, isSelecting: true)
        resetModel.setScrollAnchor(nfc, offset: -15, atTop: false)
        resetModel.setDirectoryScrollAnchor(second, offset: 23, atTop: false)
        let oldVideoSession = resetModel.selectionState.sessionID
        resetModel.switchPage(.workshop)
        resetModel.setSelection([steam], focused: steam, isSelecting: true)
        resetModel.setScrollAnchor(steam, offset: 8, atTop: true)
        let oldRemoteSession = resetModel.selectionState.sessionID
        try await controller.reset()
        // A source may publish its old catalog after relationship reset. Those
        // unchanged IDs cannot restore a selection receipt from the old epoch.
        resetModel.update(catalog: catalog, relationships: controller.snapshot)
        checks["realStoreResetClearsRemoteSelectionAndRevokesReceipt"] = resetModel.selectionState.references.isEmpty
            && !resetModel.selectionState.isSelecting && resetModel.selectionState.sessionID != oldRemoteSession
            && resetModel.queryState.scrollAnchor == nil && resetModel.queryState.scrollOffset == nil && resetModel.queryState.scrollAtTop == nil
            && resetModel.directoryScrollAnchor == nil && resetModel.directoryScrollOffset == nil && resetModel.directoryScrollAtTop == nil
        let afterResetSettings = resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey)
        let afterResetQuery = resetModel.queryState
        resetModel.setScrollAnchor(image, offset: -31, atTop: false, page: .playlist(second))
        let pagesAfterResetReceipt = try persistedQueryPages(resetDefaults)
        checks["lateScrollForResetDeletedPlaylistCannotRecreateItsPreviousQueryOrGeometry"] = resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == afterResetSettings
            && resetModel.queryState == afterResetQuery && pagesAfterResetReceipt.contains(.playlist(second)) == false
        resetModel.setSelection([steam], focused: steam)
        checks["oldRemoteCompletionCannotClearNewEpochSelection"] = !resetModel.setSelection([], expectedSessionID: oldRemoteSession)
            && resetModel.selectionState.references == [steam]
        resetModel.switchPage(.videos)
        checks["resetRevokesInactivePageSelectionDespiteLateCatalog"] = resetModel.selectionState.references.isEmpty
            && resetModel.selectionState.sessionID != oldVideoSession
            && resetModel.queryState.scrollAnchor == nil && resetModel.queryState.scrollOffset == nil && resetModel.queryState.scrollAtTop == nil
        resetModel.setSelection([nfc], focused: nfc)
        let newVideoSession = resetModel.selectionState.sessionID
        resetModel.update(catalog: catalog, relationships: controller.snapshot)
        checks["oldVideoCompletionCannotClearStableNewEpochSelection"] = !resetModel.setSelection([], expectedSessionID: oldVideoSession)
            && resetModel.selectionState.references == [nfc] && resetModel.selectionState.sessionID == newVideoSession
        resetModel.setScrollAnchor(nfc, offset: -12, atTop: false)
        let stableAnchorData = resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey)
        var anchorPublications = 0
        let anchorSubscription = resetModel.$state.dropFirst().sink { _ in anchorPublications += 1 }
        for _ in 0..<20 { resetModel.setScrollAnchor(nfc, offset: -12, atTop: false) }
        checks["identicalScrollGeometryDoesNotRepublishPageOrPersist"] = anchorPublications == 0
            && resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == stableAnchorData
        resetModel.setScrollAnchor(nfc, offset: -13, atTop: false)
        checks["withinRowOffsetChangeIsRetainedWithoutChangingSelection"] = anchorPublications == 1
            && resetModel.queryState.scrollOffset == -13 && resetModel.selectionState.references == [nfc]
        resetModel.setScrollAnchor(nfc, offset: -13, atTop: true)
        checks["trueTopIsDistinctFromFirstReferenceWithSameOffset"] = anchorPublications == 2 && resetModel.queryState.scrollAtTop == true
        resetModel.setScrollAnchor(steam, offset: 0, atTop: false)
        checks["crossingToAnotherFirstVisibleRowPublishesOneNewAnchor"] = anchorPublications == 3
            && resetModel.queryState.scrollAnchor == steam && resetModel.queryState.scrollOffset == 0 && resetModel.queryState.scrollAtTop == false
        anchorSubscription.cancel()
        let validGeometry = resetModel.queryState
        let validGeometryData = resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey)
        resetModel.setScrollAnchor(steam, offset: .nan, atTop: false)
        resetModel.setDirectoryScrollAnchor(second, offset: .infinity, atTop: false)
        checks["nonFiniteScrollUpdatesCannotPoisonPersistedViewState"] = resetModel.queryState == validGeometry
            && resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == validGeometryData
            && resetModel.directoryScrollOffset == nil && resetModel.lastError != nil
        var invalidDensity = validGeometry; invalidDensity.preferredColumns = 2
        checks["outOfRangeDensityCannotReplaceValidPageState"] = !resetModel.setQueryState(invalidDensity)
            && resetModel.queryState == validGeometry && resetDefaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == validGeometryData
        resetModel.switchPage(.images)
        resetModel.setQueryState(.init(search: "no result", preferredColumns: 3))
        resetModel.setEditingAllowed(false)
        resetModel.resetViewState()
        checks["explicitViewResetReprojectsLastAcceptedCatalogWithoutWaitingForPublisher"] = resetModel.page == .videos
            && resetModel.queryState == .init() && resetModel.queryResult.items.map(\.reference) == [backing, nfc, nfd]
            && resetModel.selectionState.references.isEmpty && !resetModel.selectionState.isSelecting
        let resetBadInput = UserCollectionsSnapshot(revision: controller.snapshot.revision, resetEpoch: controller.snapshot.resetEpoch,
            migrationManifestID: nil, playlists: [], members: [], favorites: [], recent: [],
            aliases: [.init(alias: nfc, canonical: nfd, proof: .explicitUserRelocation),
                      .init(alias: nfc, canonical: image, proof: .explicitUserRelocation)], locators: [])
        _ = resetModel.update(catalog: .init(), relationships: resetBadInput)
        resetModel.resetViewState()
        checks["explicitViewResetNeverPromotesLastRejectedQueryInput"] = resetModel.queryResult.items.map(\.reference) == [backing, nfc, nfd]
        let one = ref(.steamWorkshop, "one"), two = ref(.pixabay, "two"), three = ref(.steamWorkshop, "three")
        func removalCatalog(_ revision: UInt64, _ references: [WallpaperReference]) -> WallpaperLibraryCatalog {
            let names = [one: "A", two: "B", three: "C"]
            return .init(videos: [item(nfc)], downloads: references.map { item($0, title: names[$0]) }, revision: revision)
        }
        func deletionModel(_ catalog: WallpaperLibraryCatalog) -> WallpaperLibraryPresentation {
            defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
            let view = WallpaperLibraryPresentation(collections: controller, defaults: defaults)
            view.update(catalog: catalog, relationships: controller.snapshot)
            view.switchPage(.downloads)
            view.setQueryState(.init(sort: .name))
            return view
        }
        do {
            let old = removalCatalog(10, [one, two, three]), view = deletionModel(old)
            view.setSelection([one, two], focused: one, isSelecting: true)
            let receipt = view.beginRemoval([one, two], from: .downloads)
            let original = view.selectionState
            view.completeRemoval(receipt, succeeded: [one])
            checks["deletionReceiptDoesNotInventCatalogOrPruneBeforeSourcePublication"] = view.queryResult.items.map(\.reference) == [one, two, three]
                && view.selectionState == original
            view.update(catalog: removalCatalog(11, [two, three]), relationships: controller.snapshot)
            checks["mixedPartialRemovalRetainsFailedSelectionFocusAndMultiselect"] = view.queryResult.items.map(\.reference) == [two, three]
                && view.selectionState.references == [two] && view.selectionState.focusedReference == two && view.selectionState.isSelecting
            checks["lateOldCatalogCannotResurrectRemovedCardOrClearFailedSelection"] = !view.update(catalog: old, relationships: controller.snapshot)
                && view.queryResult.items.map(\.reference) == [two, three] && view.selectionState.references == [two]
            let failed = view.beginRemoval([two], from: .downloads), before = view.selectionState
            view.completeRemoval(failed, succeeded: [])
            checks["allRemovalFailuresPreserveSelectionSessionFocusAndMode"] = view.selectionState == before
            view.setSelection([two], focused: two)
            let single = view.beginRemoval([two], from: .downloads)
            view.completeRemoval(single, succeeded: [two])
            view.update(catalog: removalCatalog(12, [three]), relationships: controller.snapshot)
            checks["successfulSingleDeleteRestoresAdjacentCardInUnifiedOwner"] = view.queryResult.items.map(\.reference) == [three]
                && view.selectionState.references == [three] && view.selectionState.focusedReference == three && !view.selectionState.isSelecting
        }
        do {
            let view = deletionModel(removalCatalog(20, [one, two, three]))
            view.setSelection([three], focused: three)
            let receipt = view.beginRemoval([three], from: .downloads)
            view.update(catalog: removalCatalog(21, [one, two]), relationships: controller.snapshot)
            checks["sourceCanPruneBeforeAsynchronousRemovalCallback"] = view.selectionState.references.isEmpty
            view.completeRemoval(receipt, succeeded: [three])
            checks["lateSuccessUsesOriginalPredecessorAfterAutomaticPruning"] = view.selectionState.references == [two]
                && view.selectionState.focusedReference == two
        }
        do {
            let view = deletionModel(removalCatalog(30, [one, two, three]))
            view.setSelection([one], focused: one)
            let receipt = view.beginRemoval([one], from: .downloads)
            view.setQueryState(.init(sort: .name, ascending: false))
            view.completeRemoval(receipt, succeeded: [one])
            view.update(catalog: removalCatalog(31, [two, three]), relationships: controller.snapshot)
            checks["deletionNeighborUsesCapturedDisplayOrderInsteadOfLaterSortIndex"] = view.queryResult.items.map(\.reference) == [three, two]
                && view.selectionState.references == [two]
        }
        do {
            let view = deletionModel(removalCatalog(40, [one, two, three]))
            view.setSelection([one], focused: one)
            let receipt = view.beginRemoval([one], from: .downloads)
            view.completeRemoval(receipt, succeeded: [one])
            view.setQueryState(.init(search: "B", sort: .name))
            checks["searchHidingADeletedTargetIsNotSourceDeletionEvidence"] = view.selectionState.references.isEmpty
                && view.queryResult.items.map(\.reference) == [two]
            view.setQueryState(.init(sort: .name))
            view.update(catalog: removalCatalog(41, [two, three]), relationships: controller.snapshot)
            checks["receiptSurvivesOnlyAutomaticFilterPruningUntilRealAbsence"] = view.selectionState.references == [two]
        }
        do {
            let view = deletionModel(removalCatalog(50, [one, two, three]))
            view.setSelection([three], focused: three)
            let receipt = view.beginRemoval([two], from: .downloads)
            view.completeRemoval(receipt, succeeded: [two])
            view.update(catalog: removalCatalog(51, [one, three]), relationships: controller.snapshot)
            checks["contextDeleteOfUnselectedCardDoesNotStealExistingSelection"] = view.selectionState.references == [three]
                && view.selectionState.focusedReference == three
            view.setSelection([])
            let noSelection = view.beginRemoval([one], from: .downloads)
            view.completeRemoval(noSelection, succeeded: [one])
            view.update(catalog: removalCatalog(52, [three]), relationships: controller.snapshot)
            checks["contextDeleteWithoutSelectionDoesNotInventAdjacentSelection"] = view.selectionState.references.isEmpty
        }
        do {
            let view = deletionModel(removalCatalog(60, [one, two, three]))
            view.setSelection([one], focused: one)
            let receipt = view.beginRemoval([one], from: .downloads)
            view.update(catalog: removalCatalog(61, [two, three]), relationships: controller.snapshot)
            view.setSelection([three], focused: three)
            view.completeRemoval(receipt, succeeded: [one])
            checks["newUserSelectionRevokesOldDeletionAfterAutomaticPruning"] = view.selectionState.references == [three]
            let later = view.beginRemoval([three], from: .downloads)
            view.switchPage(.videos)
            view.setSelection([nfc], focused: nfc)
            view.completeRemoval(later, succeeded: [three])
            checks["oldPageDeletionCompletionCannotChangeNewPageSelection"] = view.page == .videos && view.selectionState.references == [nfc]
            view.switchPage(.downloads)
            view.update(catalog: removalCatalog(62, [two]), relationships: controller.snapshot)
            checks["returnVisitDoesNotReactivateOldDeletionReceipt"] = view.selectionState.references.isEmpty
        }
        do {
            let view = deletionModel(removalCatalog(70, [one, two, three]))
            view.setSelection([one], focused: one)
            let receipt = view.beginRemoval([one], from: .downloads)
            view.completeRemoval(receipt, succeeded: [one])
            var reimported = removalCatalog(71, [one, two, three])
            reimported.downloads[0] = item(one, title: "A reimported")
            view.update(catalog: reimported, relationships: controller.snapshot)
            checks["sameIDReimportWithoutObservedAbsenceDoesNotForceNeighborOrHideSource"] = view.selectionState.references == [one]
                && view.queryResult.items.contains { $0.reference == one && $0.title == "A reimported" }
            view.setSelection([three], focused: three)
            view.update(catalog: removalCatalog(72, [two, three]), relationships: controller.snapshot)
            checks["explicitSelectionEndsWaitingReceiptAfterSameIDReimport"] = view.selectionState.references == [three]
        }
        do {
            let view = deletionModel(removalCatalog(80, [one, two, three]))
            view.setSelection([one], focused: one)
            let receipt = view.beginRemoval([one], from: .downloads)
            view.completeRemoval(receipt, succeeded: [one])
            let oldRelationships = controller.snapshot
            try await controller.reset()
            view.update(catalog: removalCatalog(81, [one, two, three]), relationships: controller.snapshot)
            view.setSelection([three], focused: three)
            view.completeRemoval(receipt, succeeded: [one])
            view.update(catalog: removalCatalog(82, [two, three]), relationships: controller.snapshot)
            checks["resetRevokesDeletionReceiptBeforeLaterSourceAbsence"] = view.selectionState.references == [three]
            checks["lateRelationshipSnapshotCannotRestorePreResetSelectionAuthority"] = !view.update(catalog: removalCatalog(83, [one, two, three]), relationships: oldRelationships)
                && view.selectionState.references == [three] && view.queryResult.items.map(\.reference) == [two, three]
        }
        do {
            let view = deletionModel(removalCatalog(90, [one, two, three]))
            view.setSelection([one], focused: one)
            let old = view.beginRemoval([one], from: .downloads)
            let latest = view.beginRemoval([two], from: .downloads)
            view.completeRemoval(old, succeeded: [one])
            view.update(catalog: removalCatalog(91, [two, three]), relationships: controller.snapshot)
            view.completeRemoval(latest, succeeded: [])
            checks["newExplicitRemovalRetiresOlderWaitingSelectionAdjustment"] = view.selectionState.references.isEmpty
                && view.queryResult.items.map(\.reference) == [two, three]
        }
        let priorErrorEvent = model.state.lastErrorEvent
        let repeated = NSError(domain: "notice-test", code: 1, userInfo: [NSLocalizedDescriptionKey: "重复错误"])
        model.report(repeated)
        let firstErrorEvent = model.state.lastErrorEvent
        model.report(repeated)
        checks["eachExplicitReportCreatesANewErrorEventWithoutDuplicatingMessageState"] = model.lastError == "重复错误"
            && firstErrorEvent == priorErrorEvent &+ 1 && model.state.lastErrorEvent == firstErrorEvent &+ 1
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
