import Foundation

@main struct WallpaperLibraryQueryHarness {
    static func main() throws {
        var checks: [String: Bool] = [:]
        func ref(_ provider: WallpaperProvider, _ id: String) -> WallpaperReference {
            WallpaperReference(provider: provider, sourceID: id)
        }
        func item(_ reference: WallpaperReference, _ title: String, kind: WallpaperMediaKind = .video,
                  size: Int64? = nil, date: Date? = nil, legacyUse: Date? = nil,
                  update: WallpaperContentTransferState = .idle, path: String? = nil,
                  author: String? = nil, summary: String? = nil, description: String? = nil,
                  tags: [String] = [], rating: WallpaperContentRating? = nil,
                  acquisition: WallpaperContentTransferState = .idle,
                  availability: WallpaperPublishedAvailability = .available,
                  capabilities: WallpaperContentCapabilities = [.inspect, .play, .organize]) -> WallpaperContentItem {
            WallpaperContentItem(reference: reference, providerReference: reference,
                                 locator: WallpaperLocator(path: path, titleHint: title, mediaKind: kind), title: title, kind: kind,
                                 publishedAvailability: availability, capabilities: capabilities,
                                 metadata: WallpaperContentMetadata(author: author, summary: summary, descriptionText: description,
                                    sourceTags: tags, contentRating: rating, fileSizeBytes: size, createdAt: date, lastUsedAt: legacyUse),
                                 acquisition: acquisition, update: update, aliases: [])
        }
        let v = ref(.videoLibrary, "1"), image = ref(.staticImageLibrary, "1"), steam = ref(.steamWorkshop, "1")
        let backing = ref(.videoLibrary, "backing"), offline = ref(.steamWorkshop, "video:offline")
        let pixabay = ref(.pixabay, "1")
        let playlist = WallpaperPlaylist(name: "夏天 Café", createdAt: Date(timeIntervalSince1970: 10), sidebarRank: 0)
        var catalog = WallpaperLibraryCatalog(
            videos: [item(v, "Video", size: 3), item(backing, "Backing", size: 4)],
            images: [item(image, "Image", kind: .image, size: 1)],
            downloads: [item(steam, "Workshop", kind: .scene, size: 5, date: Date(timeIntervalSince1970: 100),
                             update: .init(phase: .failed, failureMessage: "update failed")),
                        item(pixabay, "Pixabay", size: nil)])
        func snapshot(recent: [WallpaperRecentUse] = [], aliases: [WallpaperReferenceAlias]? = nil,
                      excluded: [WallpaperLibraryExclusion] = []) -> UserCollectionsSnapshot {
            UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: [playlist], members: [
                    .init(playlistID: playlist.id, reference: steam, position: 1, addedAt: Date(timeIntervalSince1970: 20)),
                    .init(playlistID: playlist.id, reference: image, position: 0, addedAt: Date(timeIntervalSince1970: 10)),
                    .init(playlistID: playlist.id, reference: offline, position: 2, addedAt: Date(timeIntervalSince1970: 30))],
                favorites: [.init(reference: pixabay, favoritedAt: nil, migrationOrder: 0),
                            .init(reference: image, favoritedAt: nil, migrationOrder: 1),
                            .init(reference: steam, favoritedAt: Date(timeIntervalSince1970: 25), migrationOrder: nil)],
                recent: recent,
                aliases: aliases ?? [.init(alias: backing, canonical: steam, proof: .publishedDownload)],
                locators: [.init(reference: offline, locator: .init(path: "/offline/a", titleHint: "Offline", mediaKind: .web))],
                excludedLibraryReferences: excluded)
        }
        let relations = snapshot()
        do {
            let adultWH = ref(.wallhaven, "nsfw"), adultPX = ref(.pixiv, "18:p0")
            let sensitive = ref(.wallhaven, "sketchy"), safe = ref(.steamWorkshop, "everyone")
            let unknown = ref(.pixiv, "unrated:p0"), legacy = ref(.wallhaven, "legacy")
            let rated = WallpaperLibraryCatalog(downloads: [item(steam, "Mature", rating: .adult),
                item(adultWH, "NSFW", rating: .adult), item(adultPX, "R18", rating: .adult),
                item(sensitive, "Sketchy", rating: .sensitive), item(safe, "Everyone", rating: .safe),
                item(unknown, "Unknown", rating: .unknown), item(legacy, "Legacy without rating")])
            let hidden = WallpaperLibraryQueryState(showsAdultContent: false)
            let result = try WallpaperLibraryQuery.project(page: .downloads, state: hidden, catalog: rated, relationships: relations)
            checks["downloads-adult-filter-uses-one-cross-source-query-and-keeps-sensitive-unknown-and-legacy"] = Set(result.items.map(\.reference))
                == Set([sensitive, safe, unknown, legacy]) && result.unfilteredCount == 4
            checks["show-adult-restores-all-three-sources-without-changing-explicit-playback-or-favorites"] =
                try WallpaperLibraryQuery.project(page: .downloads, state: .init(), catalog: rated, relationships: relations).items.count == 7
                && WallpaperLibraryQuery.resolve([steam, adultWH, adultPX], catalog: rated, relationships: relations).allSatisfy { $0.capabilities.contains(.play) }
                && WallpaperLibraryQuery.project(page: .favorites, state: hidden, catalog: rated, relationships: relations).items.contains { $0.reference == steam }
            let oneSource = try WallpaperLibraryQuery.project(page: .downloads,
                state: .init(providers: [.pixiv], showsAdultContent: false), catalog: rated, relationships: relations)
            checks["provider-filter-still-composes-with-the-shared-adult-filter"] = oneSource.items.map(\.reference) == [unknown]
        }
        func project(_ page: WallpaperLibraryPage, _ state: WallpaperLibraryQueryState = .init()) throws -> WallpaperLibraryPageResult {
            try WallpaperLibraryQuery.project(page: page, state: state, catalog: catalog, relationships: relations)
        }
        checks["pageKeyUsesUUIDNotRenamedTitle"] = WallpaperLibraryPage.playlist(playlist.id).persistenceKey == "playlist." + playlist.id.uuidString
        checks["pageStateRoundTripsWithoutSourceSingletons"] = try JSONDecoder().decode(WallpaperLibraryQueryState.self, from: JSONEncoder().encode(WallpaperLibraryQueryState(search: "夏天", preferredColumns: 3, scrollOffset: -5.25, scrollAtTop: false))) == WallpaperLibraryQueryState(search: "夏天", preferredColumns: 3, scrollOffset: -5.25, scrollAtTop: false)
        do {
            let decoder = JSONDecoder(), encoder = JSONEncoder()
            let selected = WallpaperLibraryQueryState(search: "Café", providers: [.wallhaven, .steamWorkshop, .pixabay],
                kinds: [.video, .scene, .image], statuses: [.transferring, .playable, .failed], sort: .name,
                ascending: false, preferredColumns: 4, scrollAnchor: steam,
                scrollOffset: -15.5, scrollAtTop: false, showsAdultContent: false)
            let encoded = try encoder.encode(selected)
            let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            checks["new-filter-sets-round-trip-with-all-original-preferences"] = try decoder.decode(
                WallpaperLibraryQueryState.self, from: encoded) == selected
            checks["new-filter-encoding-is-stably-sorted-and-retires-single-value-keys"] =
                object["providers"] as? [String] == ["pixabay", "steamWorkshop", "wallhaven"]
                && object["kinds"] as? [String] == ["image", "scene", "video"]
                && object["statuses"] as? [String] == ["failed", "playable", "transferring"]
                && object["provider"] == nil && object["kind"] == nil && object["status"] == nil
            let newEmpty = Data(#"{"search":"","providers":[],"kinds":[],"statuses":[],"provider":"pixabay","kind":"video","status":"failed","ascending":true}"#.utf8)
            checks["explicit-new-empty-sets-take-precedence-over-retired-single-values"] = try decoder.decode(
                WallpaperLibraryQueryState.self, from: newEmpty) == WallpaperLibraryQueryState()
            let repeated = Data(#"{"search":"","providers":["pixabay","pixabay"],"kinds":["video","video"],"statuses":["failed","failed"],"ascending":true}"#.utf8)
            checks["new-filter-arrays-decode-to-one-selection-per-value"] = try decoder.decode(
                WallpaperLibraryQueryState.self, from: repeated)
                == WallpaperLibraryQueryState(providers: [.pixabay], kinds: [.video], statuses: [.failed])
            for (name, json) in [
                ("new-invalid", #"{"search":"","providers":[],"kinds":[],"statuses":["unknown"],"ascending":true}"#),
                ("new-retired-all", #"{"search":"","providers":[],"kinds":[],"statuses":["all"],"ascending":true}"#)
            ] {
                do {
                    _ = try decoder.decode(WallpaperLibraryQueryState.self, from: Data(json.utf8))
                    checks["invalid-status-still-rejected-\(name)"] = false
                } catch DecodingError.dataCorrupted {
                    checks["invalid-status-still-rejected-\(name)"] = true
                }
            }
        }
        checks["myVideosExcludesProvenDownloadBacking"] = try project(.videos).items.map(\.reference) == [v]
        checks["sameNumberAcrossProvidersDoesNotCollapse"] = try project(.downloads).items.map(\.reference) == [steam, pixabay]
        checks["playlist-default-is-actual-join-time-descending"] = try project(.playlist(playlist.id)).items.map(\.reference) == [offline, steam, image]
        checks["playlist-explicit-join-time-ascending-is-retained"] = try project(.playlist(playlist.id), .init(sort: .addedAt, ascending: true)).items.map(\.reference) == [image, steam, offline]
        let joinedTogether = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: [playlist], members: [steam, offline, image].enumerated().map {
                .init(playlistID: playlist.id, reference: $0.element, position: $0.offset, addedAt: Date(timeIntervalSince1970: 20))
            }, favorites: [], recent: [], aliases: relations.aliases, locators: relations.locators)
        checks["same-batch-join-time-uses-member-position-instead-of-source-id"] = try WallpaperLibraryQuery.project(
            page: .playlist(playlist.id), state: .init(), catalog: catalog, relationships: joinedTogether).items.map(\.reference) == [image, offline, steam]
        catalog.sessionHiddenDownloadReferences = [steam]
        checks["session-download-hide-is-canonical-and-keeps-playlist-and-explicit-playback"] = try project(.downloads).items.map(\.reference) == [pixabay]
            && project(.playlist(playlist.id), .init(sort: .sourceOrder)).items.map(\.reference) == [image, steam, offline]
            && WallpaperLibraryQuery.resolve([steam], catalog: catalog, relationships: relations)[0].capabilities.contains(.play)
        catalog.sessionHiddenDownloadReferences = [backing]
        checks["session-download-hide-follows-later-canonical-alias"] = try project(.downloads).items.allSatisfy { $0.reference != steam }
        catalog.sessionHiddenDownloadReferences = []
        let members = try project(.playlist(playlist.id), .init(sort: .sourceOrder))
        checks["playlistRetainsManualOrderAndOfflineMember"] = members.items.map(\.reference) == [image, steam, offline]
        checks["missingItemUsesStoredLocatorWithoutLosingRelation"] = members.items.last?.title == "Offline" && members.items.last?.kind == .web
        checks["missingItemCannotPlayOrOrganize"] = members.items.last?.publishedAvailability == .unavailable && members.items.last?.capabilities == [.inspect]
        checks["healthyMixedPlaylistKeepsLocalOrganizationCapabilities"] = members.items.prefix(2).allSatisfy { $0.capabilities.contains(.organize) }
        checks["queryDoesNotMutateSourceCollections"] = catalog.videos.count == 2 && catalog.downloads.count == 2 && relations.members.count == 3
        catalog.excludedDownloadReferences = [steam]
        checks["sourceTaskAndAccountExclusionsFilterOnlyMyDownloads"] = try project(.downloads).items.map(\.reference) == [pixabay]
            && project(.playlist(playlist.id), .init(sort: .sourceOrder)).items.map(\.reference) == [image, steam, offline]
            && project(.favorites).items.contains { $0.reference == steam }
            && WallpaperLibraryQuery.resolve([steam], catalog: catalog, relationships: relations)[0].capabilities.contains(.play)
        catalog.excludedDownloadReferences = []
        let hiddenBacking = snapshot(excluded: [.init(reference: backing, revision: 7)])
        checks["old-sql-download-exclusion-no-longer-hides-disk-content-or-other-sources"] = try WallpaperLibraryQuery.project(page: .downloads,
            state: .init(), catalog: catalog, relationships: hiddenBacking).items.map(\.reference) == [steam, pixabay]
            && WallpaperLibraryQuery.project(page: .videos, state: .init(), catalog: catalog, relationships: hiddenBacking).items.map(\.reference) == [v]
            && WallpaperLibraryQuery.project(page: .images, state: .init(), catalog: catalog, relationships: hiddenBacking).items.map(\.reference) == [image]
        let hidden = snapshot(recent: [.init(reference: steam, lastSuccessfulUseAt: nil, commitSequence: 1, migrationOrder: nil)],
            excluded: [backing, v, image, pixabay].enumerated().map { .init(reference: $0.element, revision: Int64(7 + $0.offset)) })
        checks["durable-exclusion-retains-local-video-and-image-page-semantics"] = try [WallpaperLibraryPage.videos, .images].allSatisfy {
            let page = try WallpaperLibraryQuery.project(page: $0, state: .init(), catalog: catalog, relationships: hidden)
            return page.items.isEmpty && page.unfilteredCount == 0
        }
        checks["excluded-library-items-retain-all-existing-relationships-and-explicit-playback"] = try WallpaperLibraryQuery.project(page: .favorites,
            state: .init(), catalog: catalog, relationships: hidden).items.count == 3
            && WallpaperLibraryQuery.project(page: .recent, state: .init(), catalog: catalog, relationships: hidden).items.map(\.reference) == [steam]
            && WallpaperLibraryQuery.project(page: .playlist(playlist.id), state: .init(sort: .sourceOrder), catalog: catalog, relationships: hidden).items.map(\.reference) == [image, steam, offline]
            && WallpaperLibraryQuery.resolve([steam, image, v, pixabay], catalog: catalog, relationships: hidden).allSatisfy { $0.capabilities.contains(.play) }
        let admitted = try WallpaperLibraryQuery.libraryExclusionRevisions(for: [backing, steam, v], relationships: hiddenBacking)
        checks["restore-receipt-uses-canonical-admission-revision-and-keeps-absent-as-nil"] = admitted[backing] == 7 && admitted[steam] == 7 && admitted[v] == nil
        checks["clearingSourceExclusionsRestoresDownloadsWithoutLosingRelations"] = try project(.downloads).items.map(\.reference) == [steam, pixabay]
            && relations.members.count == 3
        let favorites = try project(.favorites)
        checks["knownFavoritesFirstUnknownKeepMigrationOrder"] = favorites.items.map(\.reference) == [steam, pixabay, image]
        var state = WallpaperLibraryQueryState(search: "cafe")
        checks["searchIncludesPlaylistNamesAndDiacritics"] = try project(.favorites, state).items.map(\.reference) == [steam, image]
        let filteredMembers = try project(.playlist(playlist.id), .init(search: "Image"))
        checks["filteredPlaylistKeepsCanonicalLocalOrganizationTarget"] = filteredMembers.items.map(\.reference) == [image]
            && filteredMembers.items.first?.capabilities.contains(.organize) == true
        state.search = "创意工坊"
        checks["searchIncludesUserVisibleChineseSource"] = try project(.favorites, state).items.map(\.reference) == [steam]
        state.search = "本地图片"
        checks["searchIncludesUserVisibleImageSource"] = try project(.favorites, state).items.map(\.reference) == [image]
        state = WallpaperLibraryQueryState(kinds: [.scene])
        checks["typeFilterIsMetadataNotSourceIdentity"] = try project(.downloads, state).items.map(\.reference) == [steam]
        state = WallpaperLibraryQueryState(providers: [.pixabay])
        checks["providerFilterKeepsOnlyTargetSource"] = try project(.downloads, state).items.map(\.reference) == [pixabay]
        state = WallpaperLibraryQueryState(statuses: [.failed])
        let failed = try project(.downloads, state)
        checks["failedUpdateKeepsPublishedPlayableItem"] = failed.items.map(\.reference) == [steam] && failed.items[0].capabilities.contains(.play)
        do {
            let a = ref(.steamWorkshop, "filter-scene"), b = ref(.steamWorkshop, "filter-acquisition")
            let c = ref(.pixabay, "filter-image"), d = ref(.pixabay, "filter-failed")
            let e = ref(.wallhaven, "filter-update"), f = ref(.pixiv, "filter-unavailable")
            let g = ref(.steamWorkshop, "filter-idle")
            let mixed = WallpaperLibraryCatalog(downloads: [
                item(a, "A", kind: .scene, update: .init(phase: .failed), capabilities: [.inspect]),
                item(b, "B", acquisition: .init(phase: .queued), availability: .unavailable, capabilities: [.inspect]),
                item(c, "C", kind: .image),
                item(d, "D", acquisition: .init(phase: .failed), availability: .unavailable, capabilities: [.inspect]),
                item(e, "E", update: .init(phase: .publishing)),
                item(f, "F", kind: .web, availability: .unavailable, capabilities: [.inspect]),
                item(g, "G")])
            func filtered(_ selection: WallpaperLibraryQueryState) throws -> WallpaperLibraryPageResult {
                try WallpaperLibraryQuery.project(page: .downloads, state: selection, catalog: mixed, relationships: relations)
            }
            var selection = WallpaperLibraryQueryState(providers: [.steamWorkshop, .pixabay], kinds: [.scene, .video],
                statuses: [.failed, .transferring], sort: .sourceOrder)
            let selected = try filtered(selection)
            checks["three-filter-groups-use-or-within-and-between-without-changing-unfiltered-count"] =
                selected.items.map(\.reference) == [a, b, d] && selected.unfilteredCount == 7
            selection.statuses.remove(.failed)
            checks["removing-one-selected-status-keeps-the-other"] = try filtered(selection).items.map(\.reference) == [b]
            selection.statuses.remove(.transferring)
            checks["removing-final-status-restores-unrestricted-status-with-other-groups-intact"] =
                try filtered(selection).items.map(\.reference) == [a, b, d, g]
            selection.statuses = [.failed, .transferring]
            selection.kinds.remove(.scene)
            checks["removing-one-selected-kind-keeps-the-other"] = try filtered(selection).items.map(\.reference) == [b, d]
            selection.kinds.remove(.video)
            checks["removing-final-kind-restores-unrestricted-kinds-with-other-groups-intact"] =
                try filtered(selection).items.map(\.reference) == [a, b, d]
            selection.kinds = [.scene, .video]
            selection.providers.remove(.steamWorkshop)
            checks["removing-one-selected-provider-keeps-the-other"] = try filtered(selection).items.map(\.reference) == [d]
            selection.providers.remove(.pixabay)
            checks["removing-final-provider-restores-unrestricted-providers-with-other-groups-intact"] =
                try filtered(selection).items.map(\.reference) == [a, b, d, e]
            selection.kinds.removeAll(); selection.statuses.removeAll()
            checks["clearing-all-filter-groups-restores-original-source-order-and-count"] =
                try filtered(selection).items.map(\.reference) == [a, b, c, d, e, f, g]
            let statusCases: [(Set<WallpaperLibraryStatusFilter>, [WallpaperReference])] = [
                ([.playable], [c, e, g]), ([.unavailable], [b, d, f]),
                ([.transferring], [b, e]), ([.failed], [a, d]),
                ([.playable, .transferring], [b, c, e, g]), ([.unavailable, .failed], [a, b, d, f])]
            for (statuses, expected) in statusCases {
                let name = statuses.map(\.rawValue).sorted().joined(separator: "+")
                checks["status-set-retains-original-facts-and-never-duplicates-overlap-\(name)"] = try filtered(
                    .init(statuses: statuses, sort: .sourceOrder)).items.map(\.reference) == expected
            }
        }
        for ascending in [true, false] {
            state = WallpaperLibraryQueryState(sort: .fileSize, ascending: ascending)
            checks["unknownSizeAlwaysLast-\(ascending)"] = try project(.downloads, state).items.last?.reference == pixabay
            state.sort = .createdAt
            checks["unknownDateAlwaysLast-\(ascending)"] = try project(.downloads, state).items.last?.reference == pixabay
        }
        // The original source command and title win over its video backing.
        checks["canonicalSourceRetainsOwnerTargetAndMetadata"] = members.items[1].providerReference == steam && members.items[1].title == "Workshop"
        catalog.downloads.removeAll { $0.reference == steam }
        let fallback = try project(.playlist(playlist.id), .init(sort: .sourceOrder)).items[1]
        checks["backingFallbackUsesCanonicalRelationButOriginalOwnerCommand"] = fallback.reference == steam && fallback.providerReference == backing && fallback.title == "Backing"
        let oldID = ref(.videoLibrary, "old"), newID = ref(.videoLibrary, "new")
        catalog.downloads = [item(steam, "Used", size: 1),
                             item(pixabay, "Never played", legacyUse: Date(timeIntervalSince1970: 1000))]
        let knownUse = snapshot(recent: [.init(reference: steam, lastSuccessfulUseAt: Date(timeIntervalSince1970: 500), commitSequence: 1, migrationOrder: nil)])
        let byUse = try WallpaperLibraryQuery.project(page: .downloads, state: .init(sort: .lastUsed, ascending: false), catalog: catalog, relationships: knownUse)
        checks["lastUseSortDoesNotInventSuccessfulPlaybackFromLegacyImportTime"] = byUse.items.map(\.reference) == [steam, pixabay]
        let recents = (0..<52).map { i in
            WallpaperRecentUse(reference: ref(.videoLibrary, String(i)), lastSuccessfulUseAt: Date(timeIntervalSince1970: Double(100-i)), commitSequence: Int64(i), migrationOrder: nil)
        }
        let recentSnapshot = snapshot(recent: recents)
        let recent = try WallpaperLibraryQuery.project(page: .recent, state: .init(sort: .name), catalog: catalog, relationships: recentSnapshot)
        checks["recentUsesSuccessSequenceDespiteClockRollback"] = recent.items.first?.reference.sourceID == "51" && recent.items.last?.reference.sourceID == "2"
        checks["recentCapsBeforeFiltering"] = recent.items.count == 50
        let filtered = try WallpaperLibraryQuery.project(page: .recent, state: .init(search: "0"), catalog: catalog, relationships: recentSnapshot)
        checks["recentDoesNotRefillFromOlderHistory"] = filtered.items.allSatisfy { Int($0.reference.sourceID)! >= 2 } && filtered.items.count < 50
        let aliases = [WallpaperReferenceAlias(alias: oldID, canonical: newID, proof: .explicitUserRelocation)]
        let duplicated = snapshot(recent: [.init(reference: oldID, lastSuccessfulUseAt: nil, commitSequence: 2, migrationOrder: nil),
                                           .init(reference: newID, lastSuccessfulUseAt: nil, commitSequence: 1, migrationOrder: nil)], aliases: aliases)
        checks["recentCanonicalDedupRetainsFirstSuccess"] = try WallpaperLibraryQuery.project(page: .recent, state: .init(), catalog: catalog, relationships: duplicated).items.map(\.reference) == [newID]
        do { _ = try project(.playlist(UUID())); checks["deletedPlaylistIsNotSilentlyAnotherSource"] = false }
        catch UserCollectionsError.missingPlaylist { checks["deletedPlaylistIsNotSilentlyAnotherSource"] = true }
        let loop = snapshot(aliases: [.init(alias: backing, canonical: steam, proof: .publishedDownload),
                                    .init(alias: steam, canonical: backing, proof: .publishedDownload)])
        do {
            _ = try WallpaperLibraryQuery.project(page: .downloads, state: .init(), catalog: catalog, relationships: loop)
            checks["invalidAliasCycleRejectsSnapshotRatherThanHanging"] = false
        } catch UserCollectionsError.corruptData { checks["invalidAliasCycleRejectsSnapshotRatherThanHanging"] = true }

        let fallbackVideo = VideoLibraryContentProjection.project(
            VideoWallpaper(id: "fallback-title", title: "", path: "/not-visible-private-parent/Visible Filename.mp4"),
            facts: .init(isPublishedLocally: true, isAvailable: true, canPlay: true, canDelete: true))
        let fallbackCatalog = WallpaperLibraryCatalog(videos: [fallbackVideo])
        checks["visible-filename-fallback-title-is-searchable-through-real-source-projection"] = try fallbackVideo.title == "Visible Filename.mp4"
            && WallpaperLibraryQuery.project(page: .videos, state: .init(search: "Visible Filename"), catalog: fallbackCatalog, relationships: relations).items.map(\.reference) == [fallbackVideo.reference]
        checks["fallback-title-search-does-not-expose-hidden-parent-path"] = try WallpaperLibraryQuery.project(page: .videos,
            state: .init(search: "not-visible-private-parent"), catalog: fallbackCatalog, relationships: relations).items.isEmpty

        // Search preserves original source fields, without making private video
        // paths or retired source tags into a second playlist-membership owner.
        let searchSteam = ref(.steamWorkshop, "123456789"), searchImage = ref(.staticImageLibrary, "123456789")
        let searchVideo = ref(.videoLibrary, "123456789"), searchPixabay = ref(.pixabay, "123456789")
        let missingSteam = ref(.steamWorkshop, "987654321"), missingImage = ref(.staticImageLibrary, "missing")
        let searchBacking = ref(.videoLibrary, "download-backing")
        let searchRefs = [searchSteam, searchImage, searchVideo, searchPixabay, missingSteam, missingImage]
        let searchList = WallpaperPlaylist(name: "Current Mixed List", sidebarRank: 0)
        let searchCatalog = WallpaperLibraryCatalog(
            videos: [item(searchVideo, "Local Film", path: "/video-private-path/movie.mp4", tags: ["RetiredLocalTag"]),
                     item(searchBacking, "Backing", tags: ["RetiredLocalTag"])],
            images: [item(searchImage, "Still", kind: .image, path: "/image-path-only/still.heic", tags: ["RetiredLocalTag"])],
            downloads: [item(searchSteam, "Workshop Film", path: "/steam-private-path/movie.mp4", author: "Zoë Author",
                             summary: "Short Teaser", description: "Full River Delta Description", tags: ["Retrowave"]),
                        item(searchPixabay, "Stock Film", path: "/pixabay-private-path/movie.mp4", author: "Zoë Author",
                             summary: "Short Teaser", description: "Full River Delta Description", tags: ["Retrowave"])])
        let searchRelations = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: [searchList], members: searchRefs.enumerated().map {
                .init(playlistID: searchList.id, reference: $0.element, position: $0.offset, addedAt: Date())
            }, favorites: searchRefs.map { .init(reference: $0, favoritedAt: nil, migrationOrder: nil) },
            recent: searchRefs.enumerated().map {
                .init(reference: $0.element, lastSuccessfulUseAt: nil, commitSequence: Int64(100 - $0.offset), migrationOrder: nil)
            }, aliases: [.init(alias: searchBacking, canonical: searchSteam, proof: .publishedDownload)],
            locators: [.init(reference: missingImage, locator: .init(path: "/offline-image-only/still.png", titleHint: "Absent Still", mediaKind: .image)),
                       .init(reference: missingSteam, locator: .init(path: "/offline-steam-private/movie.mp4", titleHint: "Absent Workshop", mediaKind: .video))])
        func searched(_ page: WallpaperLibraryPage, _ text: String, catalog: WallpaperLibraryCatalog? = nil) throws -> [WallpaperReference] {
            try WallpaperLibraryQuery.project(page: page, state: .init(search: text), catalog: catalog ?? searchCatalog,
                                              relationships: searchRelations).items.map(\.reference)
        }
        let mixedPages: [WallpaperLibraryPage] = [.favorites, .recent, .playlist(searchList.id)]
        for (name, term) in [("author", "zoe"), ("summary", "teaser"), ("description", "river delta"),
                             ("tag", "retrowave"), ("ID", "456789"),
                             ("workshopURL", "https://steamcommunity.com/sharedfiles/filedetails/?ID=123456789")] {
            checks["Steam-\(name)-search-preserved-on-downloads-and-mixed-pages"] = try ([.downloads] + mixedPages).allSatisfy {
                try searched($0, term) == [searchSteam]
            }
        }
        checks["image-path-search-preserved-on-images-and-mixed-pages"] = try ([.images] + mixedPages).allSatisfy {
            try searched($0, "image-path-only") == [searchImage]
        }
        checks["offline-image-retains-path-search-without-source-or-IO"] = try mixedPages.allSatisfy {
            try searched($0, "offline-image-only") == [missingImage]
        }
        checks["offline-Steam-retains-canonical-ID-search-without-source-or-IO"] = try mixedPages.allSatisfy {
            try searched($0, "https://steamcommunity.com/sharedfiles/filedetails/?id=987654321") == [missingSteam]
        }
        checks["workshop-URL-ID-does-not-search-other-provider-numeric-identities"] = try searched(.videos, "id=123456789").isEmpty
            && searched(.images, "id=123456789").isEmpty
        checks["video-Pixabay-and-Steam-paths-are-not-new-search-fields"] = try ([.videos, .downloads] + mixedPages).allSatisfy { page in
            try ["video-private-path", "pixabay-private-path", "steam-private-path", "offline-steam-private"].allSatisfy {
                try searched(page, $0).isEmpty
            }
        }
        checks["retired-local-source-tags-never-resurrect-playlist-search"] = try ([.videos, .images] + mixedPages).allSatisfy {
            try searched($0, "RetiredLocalTag").isEmpty
        }
        checks["actual-playlist-membership-name-stays-searchable"] = try mixedPages.allSatisfy {
            try searched($0, "Current Mixed List").count == searchRefs.count
        }
        var backingCatalog = searchCatalog
        backingCatalog.downloads.removeAll { $0.reference == searchSteam }
        checks["proven-backing-fallback-remains-searchable-by-canonical-Steam-ID"] = try searched(.playlist(searchList.id), "id=123456789", catalog: backingCatalog) == [searchSteam]
        checks["proven-Steam-alias-does-not-import-backing-local-tags-as-Steam-metadata"] = try searched(.playlist(searchList.id), "RetiredLocalTag", catalog: backingCatalog).isEmpty
        let wallhaven = ref(.wallhaven, "Ab001"), pixivPage = ref(.pixiv, "001234:p2")
        let onlineImages = WallpaperLibraryCatalog(downloads: [
            item(wallhaven, "Still", kind: .image), item(pixivPage, "Still", kind: .image)])
        let downloadedImages = try WallpaperLibraryQuery.project(page: .downloads, state: .init(kinds: [.image]),
            catalog: onlineImages, relationships: relations)
        checks["new-online-image-sources-retain-distinct-opaque-identity-in-downloads"] = Set(downloadedImages.items.map(\.reference)) == [wallhaven, pixivPage]
            && WallpaperReference(storageKey: wallhaven.storageKey) == wallhaven
            && WallpaperReference(storageKey: pixivPage.storageKey) == pixivPage
            && wallhaven != ref(.wallhaven, "ab001") && pixivPage != ref(.pixiv, "1234:p2")
            && pixivPage != ref(.pixiv, "001234:p0")
        checks["downloads-provider-filters-and-source-name-search-include-online-images"] = try WallpaperLibraryQuery.project(
            page: .downloads, state: .init(search: "wallhaven", providers: [.wallhaven]), catalog: onlineImages,
            relationships: relations).items.map(\.reference) == [wallhaven]
            && WallpaperLibraryQuery.project(page: .downloads, state: .init(search: "pixiv", providers: [.pixiv]),
                catalog: onlineImages, relationships: relations).items.map(\.reference) == [pixivPage]
        checks["download-readiness-includes-local-online-publications-and-respects-provider-filter"] = try WallpaperLibraryQuery.requiredProviders(
            page: .downloads, state: .init(), relationships: relations) == [.steamWorkshop, .pixabay, .wallhaven, .pixiv]
            && WallpaperLibraryQuery.requiredProviders(page: .downloads, state: .init(providers: [.pixiv]), relationships: relations) == [.pixiv]
        checks["multi-provider-readiness-intersects-page-sources-and-ignores-media-and-status-visibility"] =
            try WallpaperLibraryQuery.requiredProviders(page: .downloads,
                state: .init(providers: [.steamWorkshop, .pixabay, .videoLibrary], kinds: [.image], statuses: [.failed]),
                relationships: relations) == [.steamWorkshop, .pixabay]
            && WallpaperLibraryQuery.requiredProviders(page: .images, state: .init(providers: [.pixabay]), relationships: relations).isEmpty
        checks["mixed-page-readiness-unions-canonical-members-then-intersects-selected-providers"] =
            try WallpaperLibraryQuery.requiredProviders(page: .playlist(playlist.id), state: .init(), relationships: relations)
                == [.staticImageLibrary, .steamWorkshop]
            && WallpaperLibraryQuery.requiredProviders(page: .favorites,
                state: .init(providers: [.steamWorkshop, .staticImageLibrary, .pixiv]), relationships: relations)
                == [.steamWorkshop, .staticImageLibrary]
        for (name, state) in [("provider", WallpaperLibraryQueryState(providers: [.steamWorkshop])),
                              ("kind", WallpaperLibraryQueryState(kinds: [.video])),
                              ("status", WallpaperLibraryQueryState(statuses: [.playable]))] {
            do {
                _ = try WallpaperLibraryQuery.directory(state: state, catalog: catalog, relationships: relations)
                checks["directory-still-rejects-unsupported-filter-group-\(name)"] = false
            } catch WallpaperLibraryQueryError.unsupportedDirectoryFilter {
                checks["directory-still-rejects-unsupported-filter-group-\(name)"] = true
            }
        }
        checks["new-browser-pages-have-independent-navigation-and-no-local-catalog-or-login-dependencies"] = try [WallpaperLibraryPage.wallhaven, .pixiv].allSatisfy {
            let result = try WallpaperLibraryQuery.project(page: $0, state: .init(), catalog: onlineImages, relationships: relations)
            let dependencies = try WallpaperLibraryQuery.requiredProviders(page: $0, state: .init(), relationships: relations)
            return $0.isRemoteBrowse && result.items.isEmpty && result.unfilteredCount == 0
                && dependencies.isEmpty
        } && WallpaperLibraryPage.wallhaven.persistenceKey == "browse.wallhaven" && WallpaperLibraryPage.pixiv.persistenceKey == "browse.pixiv"
        func auxiliaryReads() -> [Int] {
            [WallpaperLibraryQuery.membershipReads, WallpaperLibraryQuery.favoriteDateReads, WallpaperLibraryQuery.recentDateReads]
        }
        let idleReads = auxiliaryReads()
        let sourceOrder = try project(.videos)
        checks["source-order-without-search-builds-no-unused-relationship-tables"] = sourceOrder.items.map(\.reference) == [v]
            && auxiliaryReads() == idleReads
        let aliasInitializations = WallpaperLibraryQuery.resolverInitializations
        let locatorReads = WallpaperLibraryQuery.locatorReads
        let canonicalOnly = try WallpaperLibraryQuery.canonicalReferences([backing, steam], relationships: relations)
        checks["alias-only-resolution-uses-one-real-initialization-without-locators"] = canonicalOnly[backing] == steam
            && canonicalOnly[steam] == steam && WallpaperLibraryQuery.resolverInitializations == aliasInitializations + 1
            && WallpaperLibraryQuery.locatorReads == locatorReads
        _ = try WallpaperLibraryQuery.libraryExclusionRevisions(for: [backing], relationships: relations)
        checks["exclusion-admission-does-not-read-unrelated-locators"] = WallpaperLibraryQuery.locatorReads == locatorReads
        let searchedReads = WallpaperLibraryQuery.membershipReads
        let searchedMembers = try project(.favorites, .init(search: "cafe", sort: .sourceOrder))
        checks["real-membership-search-still-consumes-its-table"] = searchedMembers.items.map(\.reference) == [image, steam]
            && WallpaperLibraryQuery.membershipReads == searchedReads + relations.members.count
        let favoriteReads = WallpaperLibraryQuery.favoriteDateReads
        _ = try project(.favorites)
        checks["favorite-default-sort-still-consumes-real-favorite-dates"] = WallpaperLibraryQuery.favoriteDateReads == favoriteReads + relations.favorites.count
        let useReads = WallpaperLibraryQuery.recentDateReads
        _ = try WallpaperLibraryQuery.project(page: .downloads, state: .init(sort: .lastUsed), catalog: catalog, relationships: knownUse)
        checks["last-use-sort-still-consumes-success-dates"] = WallpaperLibraryQuery.recentDateReads == useReads + knownUse.recent.count
        let visibleRecent = try WallpaperLibraryQuery.project(page: .recent, state: .init(), catalog: catalog, relationships: recentSnapshot)
        let dependencyInit = WallpaperLibraryQuery.resolverInitializations
        let dependencyLocators = WallpaperLibraryQuery.locatorReads
        let dependencies = try WallpaperLibraryQuery.requiredProviders(page: .recent, state: .init(), relationships: recentSnapshot)
        checks["recent-readiness-shares-visible-canonical-limit-without-building-dtos"] = dependencies == Set(visibleRecent.items.map { $0.reference.provider })
            && WallpaperLibraryQuery.resolverInitializations == dependencyInit + 1 && WallpaperLibraryQuery.locatorReads == dependencyLocators
        let nonlocalInit = WallpaperLibraryQuery.resolverInitializations
        checks["directory-and-remote-pages-do-not-build-unused-local-projections"] = try [WallpaperLibraryPage.playlists, .workshop, .pixabay, .wallhaven, .pixiv].allSatisfy {
            try project($0).items.isEmpty
        } && WallpaperLibraryQuery.resolverInitializations == nonlocalInit
        do {
            _ = try WallpaperLibraryQuery.canonicalReferences([backing], relationships: loop)
            checks["light-alias-resolution-still-refuses-requested-cycles"] = false
        } catch UserCollectionsError.corruptData { checks["light-alias-resolution-still-refuses-requested-cycles"] = true }
        do {
            let date = Date(timeIntervalSince1970: 123)
            let list = WallpaperPlaylist(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Directory Café", createdAt: date, modifiedAt: date.addingTimeInterval(5), sidebarRank: 7)
            let empty = WallpaperPlaylist(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Empty", createdAt: date, sidebarRank: 7)
            let canonical = ref(.steamWorkshop, "directory-native"), backing = ref(.videoLibrary, "directory-backing")
            let relocated = ref(.videoLibrary, "directory-relocated"), healthy = ref(.staticImageLibrary, "directory-healthy")
            let missing = ref(.pixabay, "directory-missing")
            let aliases: [WallpaperReferenceAlias] = [
                .init(alias: relocated, canonical: backing, proof: .explicitUserRelocation),
                .init(alias: backing, canonical: canonical, proof: .publishedDownload)]
            let directoryCatalog = WallpaperLibraryCatalog(videos: [item(backing, "Backing")],
                images: [item(healthy, "Healthy", kind: .image)], downloads: [item(canonical, "Native")])
            func directorySnapshot(_ values: [(WallpaperReference, Int)], aliases: [WallpaperReferenceAlias] = [],
                                   locators: [WallpaperReferenceLocator] = []) -> UserCollectionsSnapshot {
                .init(revision: 9, resetEpoch: relations.resetEpoch, playlists: [list, empty],
                    members: values.map { .init(playlistID: list.id, reference: $0.0, position: $0.1, addedAt: date) },
                    favorites: [], recent: [], aliases: aliases, locators: locators)
            }
            func expectedEntry(count: Int, cover: WallpaperReference?) -> WallpaperPlaylistDirectoryEntry {
                .init(id: list.id, name: list.name, count: count, coverReference: cover,
                    createdAt: list.createdAt, modifiedAt: list.modifiedAt)
            }
            let emptyEntry = WallpaperPlaylistDirectoryEntry(id: empty.id, name: empty.name, count: 0,
                coverReference: nil, createdAt: empty.createdAt, modifiedAt: empty.modifiedAt)
            let tied = directorySnapshot([(canonical, Int.max), (missing, Int.min), (healthy, Int.min), (relocated, 5)],
                aliases: aliases)
            var before = WallpaperLibraryQuery.contentResolutions
            let tiedEntries = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog, relationships: tied)
            let tiedResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-position-ties-retain-input-first-missing-cover-and-canonical-count"] = tiedEntries
                == [emptyEntry, expectedEntry(count: 3, cover: missing)]
            before = WallpaperLibraryQuery.contentResolutions
            let reversedTies = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog,
                relationships: directorySnapshot([(canonical, Int.max), (healthy, Int.min), (missing, Int.min), (relocated, 5)],
                    aliases: aliases))
            let reversedTieResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-reversing-equal-position-members-reverses-only-cover-choice"] = reversedTies
                == [emptyEntry, expectedEntry(count: 3, cover: healthy)]
            before = WallpaperLibraryQuery.contentResolutions
            let maximum = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog,
                relationships: directorySnapshot([(healthy, Int.max)]))
            let maximumResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-int-max-first-position-still-supplies-cover"] = maximum
                == [emptyEntry, expectedEntry(count: 1, cover: healthy)] && maximumResolutions == 1

            let earlierAlias = directorySnapshot([(canonical, 100), (healthy, 0), (relocated, -1), (backing, 1000)],
                aliases: aliases)
            before = WallpaperLibraryQuery.contentResolutions
            let native = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog, relationships: earlierAlias)
            let nativeResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-earlier-duplicate-alias-can-replace-previously-seen-cover-candidate"] = native
                == [emptyEntry, expectedEntry(count: 2, cover: canonical)]
            var backingOnly = directoryCatalog
            backingOnly.downloads.removeAll()
            before = WallpaperLibraryQuery.contentResolutions
            let fallback = try WallpaperLibraryQuery.directory(state: .init(), catalog: backingOnly, relationships: earlierAlias)
            let backingResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-canonical-first-member-retains-real-backing-cover-owner"] = fallback
                == [emptyEntry, expectedEntry(count: 2, cover: backing)]
            checks["directory-name-search-keeps-rank-metadata-and-complete-member-count"] = try WallpaperLibraryQuery.directory(
                state: .init(search: "cafe"), catalog: directoryCatalog, relationships: earlierAlias)
                == [expectedEntry(count: 2, cover: canonical)]

            let longMembers: [(WallpaperReference, Int)] = [(canonical, 1000)] + (0..<512).reversed().map {
                (ref(.videoLibrary, "directory-reverse-\($0)"), $0)
            } + [(relocated, Int.max), (backing, 999)]
            before = WallpaperLibraryQuery.contentResolutions
            let longEntries = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog,
                relationships: directorySnapshot(longMembers, aliases: aliases))
            let longResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-reverse-long-members-keep-missing-manual-first-and-full-deduplicated-count"] = longEntries
                == [emptyEntry, expectedEntry(count: 513, cover: ref(.videoLibrary, "directory-reverse-0"))]
            before = WallpaperLibraryQuery.contentResolutions
            let emptyEntries = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog,
                relationships: directorySnapshot([], aliases: aliases))
            let emptyResolutions = WallpaperLibraryQuery.contentResolutions - before
            checks["directory-empty-lists-retain-rank-and-nil-cover"] = emptyEntries
                == [emptyEntry, expectedEntry(count: 0, cover: nil)]
            checks["directory-resolves-only-cover-for-tied-and-aliased-members"] =
                [tiedResolutions, reversedTieResolutions, nativeResolutions, backingResolutions].allSatisfy { $0 == 1 }
            checks["directory-reverse-long-members-resolve-only-cover"] = longResolutions == 1
            checks["directory-empty-members-do-not-resolve-content"] = emptyResolutions == 0
            FileHandle.standardError.write(Data(("directory resolve calls tied=\(tiedResolutions) reversed-ties=\(reversedTieResolutions) "
                + "max=\(maximumResolutions) native=\(nativeResolutions) backing=\(backingResolutions) "
                + "reverse-long=\(longResolutions) empty=\(emptyResolutions)\n").utf8))

            let cycleA = ref(.videoLibrary, "directory-cycle-a"), cycleB = ref(.videoLibrary, "directory-cycle-b")
            let cycleAliases: [WallpaperReferenceAlias] = [
                .init(alias: cycleA, canonical: cycleB, proof: .explicitUserRelocation),
                .init(alias: cycleB, canonical: cycleA, proof: .explicitUserRelocation)]
            for (name, values) in [("tail", [(healthy, 0), (cycleA, 100)]),
                                   ("unsorted", [(cycleA, 100), (healthy, 0)])] {
                do {
                    _ = try WallpaperLibraryQuery.directory(state: .init(search: "not-a-list-name"), catalog: directoryCatalog,
                        relationships: directorySnapshot(values, aliases: cycleAliases))
                    checks["directory-still-rejects-unmatched-list-member-cycle-\(name)"] = false
                } catch let error as UserCollectionsError {
                    checks["directory-still-rejects-unmatched-list-member-cycle-\(name)"] = error == .corruptData("alias cycle")
                }
            }
            let conflicting = directorySnapshot([(healthy, 0)], aliases: [
                .init(alias: relocated, canonical: canonical, proof: .explicitUserRelocation),
                .init(alias: relocated, canonical: healthy, proof: .explicitUserRelocation)])
            do {
                _ = try WallpaperLibraryQuery.directory(state: .init(), catalog: directoryCatalog, relationships: conflicting)
                checks["directory-retains-conflicting-alias-error"] = false
            } catch let error as UserCollectionsError {
                checks["directory-retains-conflicting-alias-error"] = error == .corruptData("conflicting alias")
            }
            let beforeInvalidFilter = WallpaperLibraryQuery.resolverInitializations
            do {
                _ = try WallpaperLibraryQuery.directory(state: .init(kinds: [.video]), catalog: directoryCatalog,
                    relationships: conflicting)
                checks["directory-unsupported-filter-still-precedes-resolver-errors"] = false
            } catch WallpaperLibraryQueryError.unsupportedDirectoryFilter {
                checks["directory-unsupported-filter-still-precedes-resolver-errors"] =
                    WallpaperLibraryQuery.resolverInitializations == beforeInvalidFilter
            }
            for (name, inputs, locators) in [
                ("catalog", WallpaperLibraryCatalog(videos: [item(cycleA, "Cycle")]), [WallpaperReferenceLocator]()),
                ("locator", WallpaperLibraryCatalog(), [.init(reference: cycleA, locator: .init())])
            ] {
                before = WallpaperLibraryQuery.contentResolutions
                do {
                    _ = try WallpaperLibraryQuery.directory(state: .init(), catalog: inputs,
                        relationships: directorySnapshot([(healthy, 0)], aliases: cycleAliases, locators: locators))
                    checks["directory-\(name)-cycle-still-precedes-member-resolution"] = false
                } catch let error as UserCollectionsError {
                    checks["directory-\(name)-cycle-still-precedes-member-resolution"] = error == .corruptData("alias cycle")
                        && WallpaperLibraryQuery.contentResolutions == before
                }
            }
        }
        do {
            let video = ref(.videoLibrary, "batch-video"), image = ref(.staticImageLibrary, "batch-image")
            let a = ref(.steamWorkshop, "batch-a"), b = ref(.steamWorkshop, "batch-b")
            let x = ref(.steamWorkshop, "batch-cycle-x"), y = ref(.steamWorkshop, "batch-cycle-y")
            func batchRelationships(aliases: [WallpaperReferenceAlias] = [],
                                    locators: [WallpaperReferenceLocator] = [], favorites: [WallpaperFavorite] = [],
                                    playlists: [WallpaperPlaylist] = [], members: [WallpaperPlaylistMember] = []) -> UserCollectionsSnapshot {
                UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: playlists, members: members, favorites: favorites, recent: [], aliases: aliases, locators: locators)
            }
            let sourceCatalog = WallpaperLibraryCatalog(videos: [item(video, "Batch Video"), item(backing, "Backing")],
                images: [item(image, "Batch Image", kind: .image)], downloads: [
                    item(b, "Batch B", date: Date(timeIntervalSince1970: 50)),
                    item(a, "Batch A", date: Date(timeIntervalSince1970: 50))])
            let sourceRelations = batchRelationships(aliases: [.init(alias: backing, canonical: a, proof: .publishedDownload)])
            let cases: [(String, [WallpaperLibraryPage], WallpaperLibraryQueryState)] = [
                ("default", [.videos, .images, .downloads], .init()),
                ("filtered", [.videos, .images, .downloads], .init(search: "batch", providers: [.videoLibrary, .steamWorkshop],
                    kinds: [.video], statuses: [.playable], sort: .name, ascending: false)),
                ("mixed-repeat", [.workshop, .downloads, .playlists, .videos, .images, .downloads, .pixiv], .init())]
            for (name, pages, state) in cases {
                let single = try pages.flatMap { try WallpaperLibraryQuery.project(page: $0, state: state,
                    catalog: sourceCatalog, relationships: sourceRelations).items }
                let before = WallpaperLibraryQuery.fullResolverInitializations
                let batch = try WallpaperLibraryQuery.project(pages: pages, state: state, catalog: sourceCatalog, relationships: sourceRelations)
                FileHandle.standardError.write(Data("CATALOG PREPARATIONS query \(pages.count) \(WallpaperLibraryQuery.fullResolverInitializations - before)\n".utf8))
                checks["batch-\(name)-matches-real-single-page-projections"] = batch == single
                let expected = name == "default" ? [video, image, b, a]
                    : name == "filtered" ? [video, b, a] : [b, a, video, image, b, a]
                checks["batch-\(name)-keeps-page-order-default-ties-and-duplicate-pages"] = batch.map(\.reference) == expected
            }
            checks["single-page-unfiltered-count-remains-local"] = try WallpaperLibraryQuery.project(page: .videos, state: .init(),
                catalog: sourceCatalog, relationships: sourceRelations).unfilteredCount == 1
                && WallpaperLibraryQuery.project(page: .downloads, state: .init(), catalog: sourceCatalog, relationships: sourceRelations).unfilteredCount == 2
            let cycle: [WallpaperReferenceAlias] = [.init(alias: x, canonical: y, proof: .publishedDownload),
                .init(alias: y, canonical: x, proof: .publishedDownload)]
            var brokenCatalog = sourceCatalog
            brokenCatalog.downloads.append(item(x, "Unselected broken download"))
            let cycleRelations = batchRelationships(aliases: cycle)
            let emptyCases: [[WallpaperLibraryPage]] = [[], [.playlists, .workshop, .pixabay, .wallhaven, .pixiv]]
            for pages in emptyCases {
                let before = WallpaperLibraryQuery.fullResolverInitializations
                checks["batch-empty-or-remote-\(pages.count)-ignores-unused-broken-catalog"] = try WallpaperLibraryQuery.project(
                    pages: pages, state: .init(), catalog: brokenCatalog, relationships: cycleRelations).isEmpty
                FileHandle.standardError.write(Data("CATALOG PREPARATIONS query-empty \(pages.count) \(WallpaperLibraryQuery.fullResolverInitializations - before)\n".utf8))
            }
            let missing = WallpaperLibraryPage.playlist(UUID())
            let locatorCycle = batchRelationships(aliases: cycle, locators: [.init(reference: x, locator: .init(titleHint: "Cycle"))])
            for (name, inputs, relations) in [("catalog", brokenCatalog, cycleRelations), ("locator", sourceCatalog, locatorCycle)] {
                do {
                    _ = try WallpaperLibraryQuery.project(pages: [.videos, missing], state: .init(), catalog: inputs, relationships: relations)
                    checks["batch-rejects-unselected-\(name)-cycle-before-page-errors"] = false
                } catch let error as UserCollectionsError {
                    checks["batch-rejects-unselected-\(name)-cycle-before-page-errors"] = error == .corruptData("alias cycle")
                }
            }
            let laterCycle = batchRelationships(aliases: cycle, favorites: [.init(reference: x, favoritedAt: nil)])
            let errorCases: [(String, [WallpaperLibraryPage], UserCollectionsError)] = [
                ("missing-first", [missing, .favorites], .missingPlaylist),
                ("cycle-first", [.favorites, missing], .corruptData("alias cycle"))]
            for (name, pages, expected) in errorCases {
                do {
                    _ = try WallpaperLibraryQuery.project(pages: pages, state: .init(), catalog: sourceCatalog, relationships: laterCycle)
                    checks["batch-retains-first-page-error-\(name)"] = false
                } catch let error as UserCollectionsError { checks["batch-retains-first-page-error-\(name)"] = error == expected }
            }
            let conflict = batchRelationships(aliases: [.init(alias: x, canonical: y, proof: .publishedDownload),
                .init(alias: x, canonical: video, proof: .publishedDownload)])
            do {
                _ = try WallpaperLibraryQuery.project(pages: [missing], state: .init(), catalog: sourceCatalog, relationships: conflict)
                checks["batch-retains-conflicting-alias-before-missing-playlist"] = false
            } catch let error as UserCollectionsError {
                checks["batch-retains-conflicting-alias-before-missing-playlist"] = error == .corruptData("conflicting alias")
            }
            let named = WallpaperPlaylist(name: "Batch Café", sidebarRank: 0)
            let duplicate = WallpaperPlaylist(id: named.id, name: "Retired Shadow", sidebarRank: 1)
            let secondary = WallpaperPlaylist(name: "Second Name", sidebarRank: 2)
            let namedMembers: [WallpaperPlaylistMember] = [
                .init(playlistID: named.id, reference: video, position: 0, addedAt: .distantPast),
                .init(playlistID: named.id, reference: image, position: 1, addedAt: .distantPast),
                .init(playlistID: named.id, reference: backing, position: 2, addedAt: .distantPast),
                .init(playlistID: secondary.id, reference: video, position: 0, addedAt: .distantPast),
                .init(playlistID: named.id, reference: backing, position: 3, addedAt: .distantPast),
                .init(playlistID: UUID(), reference: x, position: 0, addedAt: .distantPast)]
            let searchRelations = batchRelationships(aliases: sourceRelations.aliases + cycle,
                playlists: [named, duplicate, secondary], members: namedMembers)
            let three: [WallpaperLibraryPage] = [.videos, .images, .downloads]
            let searchCases: [(String, [WallpaperLibraryPage], String, [WallpaperReference], Int)] = [
                ("three", three, "  cafe\n", [video, image, a], namedMembers.count),
                ("repeated", [.downloads, .videos, .downloads, .images], "cafe", [a, video, a, image], namedMembers.count),
                ("second-name", three, "Second Name", [video], namedMembers.count),
                ("duplicate-name", three, "Retired Shadow", [], namedMembers.count),
                ("whitespace", three, " \n\t", [video, image, b, a], 0)]
            for (name, pages, search, expected, budget) in searchCases {
                let state = WallpaperLibraryQueryState(search: search)
                let single = try pages.flatMap { try WallpaperLibraryQuery.project(page: $0, state: state,
                    catalog: sourceCatalog, relationships: searchRelations).items }
                let before = WallpaperLibraryQuery.membershipReads
                let batch = try WallpaperLibraryQuery.project(pages: pages, state: state, catalog: sourceCatalog,
                    relationships: searchRelations)
                FileHandle.standardError.write(Data("MEMBERSHIP PREPARATIONS \(name) \(WallpaperLibraryQuery.membershipReads - before) \(budget)\n".utf8))
                checks["batch-member-search-\(name)-matches-single-pages-and-exact-order"] = batch == single && batch.map(\.reference) == expected
            }
            let filteredDownload = try WallpaperLibraryQuery.project(page: .downloads, state: .init(search: "cafe"),
                catalog: sourceCatalog, relationships: searchRelations)
            checks["single-member-search-retains-unfiltered-count-and-alias-owner"] = filteredDownload.unfilteredCount == 2
                && filteredDownload.items.map(\.reference) == [a] && filteredDownload.items.first?.providerReference == a
            for (name, pages) in [("empty", [WallpaperLibraryPage]()), ("remote", emptyCases[1])] {
                let before = WallpaperLibraryQuery.membershipReads
                let projected = try WallpaperLibraryQuery.project(pages: pages, state: .init(search: "cafe"),
                    catalog: brokenCatalog, relationships: searchRelations)
                checks["batch-member-search-\(name)-still-ignores-broken-unused-catalog"] = projected.isEmpty
                FileHandle.standardError.write(Data("MEMBERSHIP PREPARATIONS \(name) \(WallpaperLibraryQuery.membershipReads - before) 0\n".utf8))
            }
            let cyclicMembers = namedMembers + [.init(playlistID: named.id, reference: x, position: 4, addedAt: .distantPast)]
            let cyclicSearch = batchRelationships(aliases: searchRelations.aliases, playlists: [named], members: cyclicMembers)
            for (search, expected) in [("cafe", UserCollectionsError.corruptData("alias cycle")), (" \n", .missingPlaylist)] {
                do {
                    _ = try WallpaperLibraryQuery.project(pages: [missing, .videos], state: .init(search: search),
                        catalog: sourceCatalog, relationships: cyclicSearch)
                    checks["batch-member-search-retains-error-order-\(expected)"] = false
                } catch let error as UserCollectionsError {
                    checks["batch-member-search-retains-error-order-\(expected)"] = error == expected
                }
            }
            let conflictingSearch = batchRelationships(aliases: conflict.aliases, playlists: [named], members: cyclicMembers)
            do {
                _ = try WallpaperLibraryQuery.project(pages: [missing], state: .init(search: "cafe"),
                    catalog: sourceCatalog, relationships: conflictingSearch)
                checks["batch-member-search-retains-conflicting-alias-before-member-and-page-errors"] = false
            } catch let error as UserCollectionsError {
                checks["batch-member-search-retains-conflicting-alias-before-member-and-page-errors"] = error == .corruptData("conflicting alias")
            }
        }
        do {
            let local = ref(.videoLibrary, "pending-local"), warmBacking = ref(.videoLibrary, "pending-backing")
            let canonical = ref(.steamWorkshop, "pending-canonical"), absentVideo = ref(.steamWorkshop, "pending-absent")
            let absentImage = ref(.staticImageLibrary, "pending-image"), id = UUID()
            let requested = [absentVideo, local, warmBacking, absentImage]
            let expectedStrict = [absentVideo, local, canonical, absentImage]
            let pendingRelations = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: [.init(id: id, name: "Pending sources", createdAt: Date(), modifiedAt: Date(), sidebarRank: 0)],
                members: requested.enumerated().map { .init(playlistID: id, reference: $0.element, position: $0.offset, addedAt: Date()) },
                favorites: requested.enumerated().map { .init(reference: $0.element, favoritedAt: nil, migrationOrder: $0.offset) },
                recent: requested.enumerated().map { .init(reference: $0.element, lastSuccessfulUseAt: nil, commitSequence: Int64(4 - $0.offset), migrationOrder: nil) },
                aliases: [.init(alias: warmBacking, canonical: canonical, proof: .publishedDownload)],
                locators: [.init(reference: absentVideo, locator: .init(titleHint: "Absent video", mediaKind: .web)),
                           .init(reference: absentImage, locator: .init(titleHint: "Absent image", mediaKind: .image))])
            let pages: [(String, WallpaperLibraryPage)] = [("playlist", .playlist(id)), ("favorites", .favorites), ("recent", .recent)]
            let empty = WallpaperLibraryCatalog()
            var warm = empty
            warm.videos = [item(local, "Warm local"), item(warmBacking, "Warm backing")]
            var loadedVideo = warm; loadedVideo.loadedProviders = [.steamWorkshop]
            var loadedBoth = loadedVideo; loadedBoth.loadedProviders.insert(.staticImageLibrary)
            let stages: [(String, WallpaperLibraryCatalog, [WallpaperReference])] = [
                ("empty", empty, []), ("warm", warm, [local, canonical]),
                ("one-source", loadedVideo, [absentVideo, local, canonical]), ("loaded", loadedBoth, expectedStrict)]
            for (stage, source, expected) in stages {
                for (name, page) in pages {
                    let result = try WallpaperLibraryQuery.project(page: page, state: .init(sort: .sourceOrder),
                        catalog: source, relationships: pendingRelations, omitsPendingMembers: true)
                    checks["ui-pending-\(name)-\(stage)-uses-only-real-rows-or-completed-source-absence"] =
                        result.items.map(\.reference) == expected && result.unfilteredCount == expected.count
                }
            }
            checks["default-page-and-public-resolution-retain-pending-playback-members"] = try pages.allSatisfy {
                try WallpaperLibraryQuery.project(page: $0.1, state: .init(sort: .sourceOrder), catalog: empty,
                    relationships: pendingRelations).items.map(\.reference) == expectedStrict
            } && WallpaperLibraryQuery.resolve(requested, catalog: empty, relationships: pendingRelations).allSatisfy {
                $0.publishedAvailability == .unavailable && $0.capabilities == [.inspect]
            }
            checks["batch-default-still-retains-pending-members-for-each-page"] = try WallpaperLibraryQuery.project(
                pages: pages.map { $0.1 }, state: .init(sort: .sourceOrder), catalog: empty, relationships: pendingRelations).map(\.reference)
                == expectedStrict + expectedStrict + expectedStrict
            let warmItems = try WallpaperLibraryQuery.project(page: .playlist(id), state: .init(sort: .sourceOrder), catalog: warm,
                relationships: pendingRelations, omitsPendingMembers: true).items
            checks["unloaded-canonical-provider-does-not-hide-a-real-backing-owner"] = warmItems.last?.reference == canonical
                && warmItems.last?.providerReference == warmBacking && warm.loadedProviders.isEmpty
            checks["pending-members-do-not-become-unavailable-filter-matches"] = try WallpaperLibraryQuery.project(page: .playlist(id),
                state: .init(statuses: [.unavailable]), catalog: warm, relationships: pendingRelations, omitsPendingMembers: true).items.isEmpty
            var unavailableRow = warm
            unavailableRow.videos[0] = item(local, "Known unavailable", availability: .unavailable, capabilities: [.inspect])
            checks["actual-unavailable-row-remains-visible-before-provider-completion"] = try WallpaperLibraryQuery.project(page: .playlist(id),
                state: .init(statuses: [.unavailable]), catalog: unavailableRow, relationships: pendingRelations,
                omitsPendingMembers: true).items.map(\.reference) == [local]
            checks["readiness-still-includes-pending-canonical-provider-dependencies"] = try WallpaperLibraryQuery.requiredProviders(
                page: .playlist(id), state: .init(), relationships: pendingRelations) == [.videoLibrary, .steamWorkshop, .staticImageLibrary]
            let recentSubset = WallpaperLibraryCatalog(videos: [item(ref(.videoLibrary, "0"), "Older outside cap"), item(ref(.videoLibrary, "51"), "Newest")])
            checks["ui-pending-recent-omission-never-refills-outside-original-fifty"] = try WallpaperLibraryQuery.project(page: .recent,
                state: .init(), catalog: recentSubset, relationships: recentSnapshot, omitsPendingMembers: true).items.map(\.reference) == [ref(.videoLibrary, "51")]
            do {
                _ = try WallpaperLibraryQuery.project(page: .favorites, state: .init(), catalog: .init(videos: [item(backing, "Cyclic")]),
                    relationships: loop, omitsPendingMembers: true)
                checks["ui-pending-policy-does-not-bypass-original-alias-validation"] = false
            } catch UserCollectionsError.corruptData {
                checks["ui-pending-policy-does-not-bypass-original-alias-validation"] = true
            }
        }
        do {
            func resolutionRelationships(aliases: [WallpaperReferenceAlias] = [],
                                         locators: [WallpaperReferenceLocator] = []) -> UserCollectionsSnapshot {
                .init(revision: 1, resetEpoch: relations.resetEpoch, playlists: [], members: [], favorites: [], recent: [], aliases: aliases, locators: locators)
            }
            func resolveMeasured(_ name: String, _ references: [WallpaperReference], catalog: WallpaperLibraryCatalog,
                                 relationships: UserCollectionsSnapshot) throws -> (items: [WallpaperContentItem], work: [Int], locatorReads: Int) {
                func counts() -> [Int] {
                    [WallpaperLibraryQuery.normalizedDTOs, WallpaperLibraryQuery.unavailableDTOs,
                     WallpaperLibraryQuery.itemWrites, WallpaperLibraryQuery.locatorWrites]
                }
                let before = counts()
                let locatorReads = WallpaperLibraryQuery.locatorReads
                let items = try WallpaperLibraryQuery.resolve(references, catalog: catalog, relationships: relationships)
                let work = zip(counts(), before).map { $0.0 - $0.1 }
                let reads = WallpaperLibraryQuery.locatorReads - locatorReads
                FileHandle.standardError.write(Data(("RESOLUTION WORK \(name) \(references.count) "
                    + work.map(String.init).joined(separator: " ") + " \(reads)\n").utf8))
                return (items, work, reads)
            }
            let tailReference = ref(.staticImageLibrary, "single-4999")
            let tail = item(tailReference, "Full tail", kind: .image, size: 987654321,
                date: Date(timeIntervalSince1970: 123), update: .init(phase: .failed, failureMessage: "retained failure"),
                path: "/single/tail.jpg", author: "Author", summary: "Summary", description: "Description",
                tags: ["one", "two"], rating: .sensitive, acquisition: .init(phase: .queued),
                capabilities: [.inspect, .play, .organize, .reveal])
            var many = WallpaperLibraryCatalog(images: (0..<5000).map {
                item(ref(.staticImageLibrary, "single-\($0)"), "Image \($0)", kind: .image, size: Int64($0))
            })
            many.images[4999] = tail
            let manyLocators = many.images.map {
                WallpaperReferenceLocator(reference: $0.reference,
                    locator: .init(path: "/stored/\($0.reference.sourceID)", titleHint: "Stored", mediaKind: .web))
            }
            let ordinaryRelations = resolutionRelationships(locators: manyLocators)
            let tailResult = try resolveMeasured("tail", [tailReference], catalog: many, relationships: ordinaryRelations)
            checks["single-tail-preserves-complete-source-dto-including-current-locator"] = tailResult.items == [tail]
            checks["single-tail-only-normalizes-and-indexes-requested-row"] = tailResult.work == [1, 0, 1, 1]
            checks["single-tail-retains-all-locator-canonical-reads"] = tailResult.locatorReads == 5000

            let native = ref(.steamWorkshop, "single-native"), firstBacking = ref(.videoLibrary, "single-first-backing")
            let secondBacking = ref(.videoLibrary, "single-second-backing"), relocated = ref(.videoLibrary, "single-relocated")
            let aliases: [WallpaperReferenceAlias] = [
                .init(alias: relocated, canonical: firstBacking, proof: .explicitUserRelocation),
                .init(alias: firstBacking, canonical: native, proof: .publishedDownload),
                .init(alias: secondBacking, canonical: native, proof: .publishedDownload)]
            let first = item(firstBacking, "First backing", size: 42, path: "/single/first.mp4")
            let second = item(secondBacking, "Second backing", size: 99, path: "/single/second.mp4")
            let nativeFirst = item(native, "Earlier native", kind: .scene, size: 123)
            let nativeLast = item(native, "Last native", kind: .web, size: 456, author: "Native owner",
                acquisition: .init(phase: .waiting), capabilities: [.inspect, .play, .delete])
            var mixed = many
            mixed.videos = [first]
            mixed.downloads = [nativeFirst, nativeLast, second]
            let ownerRelations = resolutionRelationships(aliases: aliases, locators: manyLocators)
            let nativeResult = try resolveMeasured("native", [relocated], catalog: mixed, relationships: ownerRelations)
            checks["single-chain-alias-keeps-last-native-owner-over-earlier-and-later-backings"] = nativeResult.items == [nativeLast]
            checks["single-native-only-prepares-matching-owners-with-original-decision-order"] = nativeResult.work == [4, 0, 3, 0]
            var backingOnly = many
            backingOnly.videos = [first]
            backingOnly.downloads = [second]
            let backingResult = try resolveMeasured("backing", [native], catalog: backingOnly, relationships: ownerRelations)
            let expectedBacking = WallpaperContentItem(reference: native, providerReference: firstBacking,
                locator: .init(path: "/single/first.mp4", titleHint: "First backing", mediaKind: .video),
                title: "First backing", kind: .video, publishedAvailability: .available,
                capabilities: [.inspect, .play, .organize], metadata: .init(fileSizeBytes: 42),
                acquisition: .idle, update: .idle, aliases: [])
            checks["single-without-native-keeps-complete-first-backing-dto-and-owner"] = backingResult.items == [expectedBacking]
            checks["single-backing-does-not-index-unrelated-items-or-later-fallback"] = backingResult.work == [2, 0, 1, 0]

            let missing = ref(.steamWorkshop, "single-missing"), missingAlias = ref(.videoLibrary, "single-missing-alias")
            let finalLocator = WallpaperLocator(path: "/single/missing-final.jpg", titleHint: "Final missing", mediaKind: .image)
            let missingRelations = resolutionRelationships(aliases: aliases + [
                .init(alias: missingAlias, canonical: missing, proof: .publishedDownload)],
                locators: manyLocators + [
                    .init(reference: missing, locator: .init(titleHint: "Old canonical", mediaKind: .video)),
                    .init(reference: missingAlias, locator: .init(titleHint: "Later alias", mediaKind: .web)),
                    .init(reference: missing, locator: finalLocator)])
            let expectedMissing = WallpaperContentItem(reference: missing, providerReference: missing, locator: finalLocator,
                title: "Final missing", kind: .image, publishedAvailability: .unavailable, capabilities: [.inspect],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            let missingResult = try resolveMeasured("missing", [missingAlias], catalog: many, relationships: missingRelations)
            checks["single-missing-keeps-last-canonicalized-locator-and-inspect-only-dto"] = missingResult.items == [expectedMissing]
            checks["single-missing-creates-only-fallback-and-matching-locator-index"] = missingResult.work == [0, 1, 0, 3]
            checks["single-missing-still-canonicalizes-all-locators"] = missingResult.locatorReads == 5003
            let noLocator = ref(.pixiv, "single-no-locator")
            let noLocatorResult = try resolveMeasured("no-locator", [noLocator], catalog: many, relationships: ordinaryRelations)
            let expectedNoLocator = WallpaperContentItem(reference: noLocator, providerReference: noLocator,
                locator: .init(mediaKind: .unknown), title: "single-no-locator", kind: .unknown,
                publishedAvailability: .unavailable, capabilities: [.inspect], metadata: .init(),
                acquisition: .idle, update: .idle, aliases: [])
            checks["single-no-locator-retains-unknown-fallback"] = noLocatorResult.items == [expectedNoLocator]
            checks["single-no-locator-does-not-prepare-unrelated-dtos-or-indexes"] = noLocatorResult.work == [0, 1, 0, 0]

            let repeated = try resolveMeasured("repeated", [tailReference], catalog: many, relationships: ordinaryRelations)
            checks["repeated-single-request-keeps-complete-result"] = repeated.items == [tail]
            checks["repeated-single-request-keeps-bounded-preparation"] = repeated.work == [1, 0, 1, 1]
            let updatedTail = item(tailReference, "Updated source", kind: .image, size: 7,
                path: "/single/new.jpg", acquisition: .init(phase: .failed, failureMessage: "new fact"), capabilities: [.inspect])
            many.images[4999] = updatedTail
            let updated = try resolveMeasured("updated", [tailReference], catalog: many,
                relationships: resolutionRelationships(locators: [.init(reference: tailReference, locator: .init(titleHint: "Not source"))]))
            checks["next-single-request-uses-updated-source-without-retaining-old-dto-or-locator"] = updated.items == [updatedTail]
            checks["updated-single-keeps-request-local-work"] = updated.work == [1, 0, 1, 1]
            let duplicateResult = try resolveMeasured("duplicates", [tailReference, relocated, missingAlias, tailReference],
                catalog: mixed, relationships: missingRelations)
            checks["multi-resolve-keeps-input-order-repeated-request-and-original-owner"] = duplicateResult.items
                == [tail, nativeLast, expectedMissing, tail]
            checks["multi-resolve-retains-full-original-preparation-path"] = duplicateResult.work == [5004, 1, 5003, 5003]
            let emptyResult = try resolveMeasured("empty", [], catalog: many, relationships: ordinaryRelations)
            checks["empty-resolve-retains-empty-result-and-full-original-preparation-path"] = emptyResult.items.isEmpty
                && emptyResult.work == [5000, 0, 5000, 5000]

            let cycleA = ref(.videoLibrary, "single-cycle-a"), cycleB = ref(.steamWorkshop, "single-cycle-b")
            let cycle: [WallpaperReferenceAlias] = [
                .init(alias: cycleA, canonical: cycleB, proof: .publishedDownload),
                .init(alias: cycleB, canonical: cycleA, proof: .publishedDownload)]
            var brokenCatalog = many
            brokenCatalog.downloads = [item(cycleA, "Unrequested cycle")]
            let cycleRelations = resolutionRelationships(aliases: cycle)
            let locatorCycle = resolutionRelationships(aliases: cycle, locators: [.init(reference: cycleA, locator: .init())])
            let conflict = resolutionRelationships(aliases: cycle + [
                .init(alias: cycleA, canonical: tailReference, proof: .explicitUserRelocation)])
            let errorCases: [(String, WallpaperLibraryCatalog, UserCollectionsSnapshot, [WallpaperReference], UserCollectionsError)] = [
                ("unrequested-catalog-cycle", brokenCatalog, cycleRelations, [tailReference], .corruptData("alias cycle")),
                ("unrequested-locator-cycle", many, locatorCycle, [tailReference], .corruptData("alias cycle")),
                ("requested-cycle", many, cycleRelations, [cycleA], .corruptData("alias cycle")),
                ("conflict-before-catalog-cycle", brokenCatalog, conflict, [tailReference], .corruptData("conflicting alias")),
                ("empty-catalog-cycle", brokenCatalog, cycleRelations, [], .corruptData("alias cycle")),
                ("empty-locator-cycle", many, locatorCycle, [], .corruptData("alias cycle")),
                ("empty-conflict", many, conflict, [], .corruptData("conflicting alias"))]
            for (name, inputs, relationships, requested, expected) in errorCases {
                do {
                    _ = try WallpaperLibraryQuery.resolve(requested, catalog: inputs, relationships: relationships)
                    checks["single-resolution-retains-error-boundary-\(name)"] = false
                } catch let error as UserCollectionsError {
                    checks["single-resolution-retains-error-boundary-\(name)"] = error == expected
                }
            }
            checks["single-resolution-does-not-newly-reject-unused-alias-cycle"] = try WallpaperLibraryQuery.resolve(
                [tailReference], catalog: many, relationships: cycleRelations) == [updatedTail]
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
