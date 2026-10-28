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
                  tags: [String] = [], rating: WallpaperContentRating? = nil) -> WallpaperContentItem {
            WallpaperContentItem(reference: reference, providerReference: reference,
                                 locator: WallpaperLocator(path: path, titleHint: title, mediaKind: kind), title: title, kind: kind,
                                 publishedAvailability: .available, capabilities: [.inspect, .play, .organize],
                                 metadata: WallpaperContentMetadata(author: author, summary: summary, descriptionText: description,
                                    sourceTags: tags, contentRating: rating, fileSizeBytes: size, createdAt: date, lastUsedAt: legacyUse),
                                 acquisition: .idle, update: update, aliases: [])
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
            UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: "test",
                playlists: [playlist], members: [
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
                state: .init(provider: .pixiv, showsAdultContent: false), catalog: rated, relationships: relations)
            checks["provider-filter-still-composes-with-the-shared-adult-filter"] = oneSource.items.map(\.reference) == [unknown]
        }
        func project(_ page: WallpaperLibraryPage, _ state: WallpaperLibraryQueryState = .init()) throws -> WallpaperLibraryPageResult {
            try WallpaperLibraryQuery.project(page: page, state: state, catalog: catalog, relationships: relations)
        }
        checks["pageKeyUsesUUIDNotRenamedTitle"] = WallpaperLibraryPage.playlist(playlist.id).persistenceKey == "playlist." + playlist.id.uuidString
        checks["pageStateRoundTripsWithoutSourceSingletons"] = try JSONDecoder().decode(WallpaperLibraryQueryState.self, from: JSONEncoder().encode(WallpaperLibraryQueryState(search: "夏天", preferredColumns: 3, scrollOffset: -5.25, scrollAtTop: false))) == WallpaperLibraryQueryState(search: "夏天", preferredColumns: 3, scrollOffset: -5.25, scrollAtTop: false)
        checks["myVideosExcludesProvenDownloadBacking"] = try project(.videos).items.map(\.reference) == [v]
        checks["sameNumberAcrossProvidersDoesNotCollapse"] = try project(.downloads).items.map(\.reference) == [steam, pixabay]
        let members = try project(.playlist(playlist.id))
        checks["playlistRetainsManualOrderAndOfflineMember"] = members.items.map(\.reference) == [image, steam, offline]
        checks["missingItemUsesStoredLocatorWithoutLosingRelation"] = members.items.last?.title == "Offline" && members.items.last?.kind == .web
        checks["missingItemCannotPlayOrOrganize"] = members.items.last?.publishedAvailability == .unavailable && members.items.last?.capabilities == [.inspect]
        checks["healthyMixedPlaylistKeepsLocalOrganizationCapabilities"] = members.items.prefix(2).allSatisfy { $0.capabilities.contains(.organize) }
        checks["queryDoesNotMutateSourceCollections"] = catalog.videos.count == 2 && catalog.downloads.count == 2 && relations.members.count == 3
        catalog.excludedDownloadReferences = [steam]
        checks["sourceTaskAndAccountExclusionsFilterOnlyMyDownloads"] = try project(.downloads).items.map(\.reference) == [pixabay]
            && project(.playlist(playlist.id)).items.map(\.reference) == [image, steam, offline]
            && project(.favorites).items.contains { $0.reference == steam }
            && WallpaperLibraryQuery.resolve([steam], catalog: catalog, relationships: relations)[0].capabilities.contains(.play)
        catalog.excludedDownloadReferences = []
        let hiddenBacking = snapshot(excluded: [.init(reference: backing, revision: 7)])
        checks["library-exclusion-follows-only-proven-alias-not-same-number-or-path"] = try WallpaperLibraryQuery.project(page: .downloads,
            state: .init(), catalog: catalog, relationships: hiddenBacking).items.map(\.reference) == [pixabay]
            && WallpaperLibraryQuery.project(page: .videos, state: .init(), catalog: catalog, relationships: hiddenBacking).items.map(\.reference) == [v]
            && WallpaperLibraryQuery.project(page: .images, state: .init(), catalog: catalog, relationships: hiddenBacking).items.map(\.reference) == [image]
        let hidden = snapshot(recent: [.init(reference: steam, lastSuccessfulUseAt: nil, commitSequence: 1, migrationOrder: nil)],
            excluded: [backing, v, image, pixabay].enumerated().map { .init(reference: $0.element, revision: Int64(7 + $0.offset)) })
        checks["durable-exclusion-filters-only-three-source-pages"] = try [WallpaperLibraryPage.videos, .images, .downloads].allSatisfy {
            let page = try WallpaperLibraryQuery.project(page: $0, state: .init(), catalog: catalog, relationships: hidden)
            return page.items.isEmpty && page.unfilteredCount == 0
        }
        checks["excluded-library-items-retain-all-existing-relationships-and-explicit-playback"] = try WallpaperLibraryQuery.project(page: .favorites,
            state: .init(), catalog: catalog, relationships: hidden).items.count == 3
            && WallpaperLibraryQuery.project(page: .recent, state: .init(), catalog: catalog, relationships: hidden).items.map(\.reference) == [steam]
            && WallpaperLibraryQuery.project(page: .playlist(playlist.id), state: .init(), catalog: catalog, relationships: hidden).items.map(\.reference) == [image, steam, offline]
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
        state = WallpaperLibraryQueryState(kind: .scene)
        checks["typeFilterIsMetadataNotSourceIdentity"] = try project(.downloads, state).items.map(\.reference) == [steam]
        state = WallpaperLibraryQueryState(provider: .pixabay)
        checks["providerFilterKeepsOnlyTargetSource"] = try project(.downloads, state).items.map(\.reference) == [pixabay]
        state = WallpaperLibraryQueryState(status: .failed)
        let failed = try project(.downloads, state)
        checks["failedUpdateKeepsPublishedPlayableItem"] = failed.items.map(\.reference) == [steam] && failed.items[0].capabilities.contains(.play)
        for ascending in [true, false] {
            state = WallpaperLibraryQueryState(sort: .fileSize, ascending: ascending)
            checks["unknownSizeAlwaysLast-\(ascending)"] = try project(.downloads, state).items.last?.reference == pixabay
            state.sort = .createdAt
            checks["unknownDateAlwaysLast-\(ascending)"] = try project(.downloads, state).items.last?.reference == pixabay
        }
        // The original source command and title win over its video backing.
        checks["canonicalSourceRetainsOwnerTargetAndMetadata"] = members.items[1].providerReference == steam && members.items[1].title == "Workshop"
        catalog.downloads.removeAll { $0.reference == steam }
        let fallback = try project(.playlist(playlist.id)).items[1]
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
        let searchRelations = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [searchList], members: searchRefs.enumerated().map {
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
        let downloadedImages = try WallpaperLibraryQuery.project(page: .downloads, state: .init(kind: .image),
            catalog: onlineImages, relationships: relations)
        checks["new-online-image-sources-retain-distinct-opaque-identity-in-downloads"] = Set(downloadedImages.items.map(\.reference)) == [wallhaven, pixivPage]
            && WallpaperReference(storageKey: wallhaven.storageKey) == wallhaven
            && WallpaperReference(storageKey: pixivPage.storageKey) == pixivPage
            && wallhaven != ref(.wallhaven, "ab001") && pixivPage != ref(.pixiv, "1234:p2")
            && pixivPage != ref(.pixiv, "001234:p0")
        checks["downloads-provider-filters-and-source-name-search-include-online-images"] = try WallpaperLibraryQuery.project(
            page: .downloads, state: .init(search: "wallhaven", provider: .wallhaven), catalog: onlineImages,
            relationships: relations).items.map(\.reference) == [wallhaven]
            && WallpaperLibraryQuery.project(page: .downloads, state: .init(search: "pixiv", provider: .pixiv),
                catalog: onlineImages, relationships: relations).items.map(\.reference) == [pixivPage]
        checks["download-readiness-includes-local-online-publications-and-respects-provider-filter"] = try WallpaperLibraryQuery.requiredProviders(
            page: .downloads, state: .init(), relationships: relations) == [.steamWorkshop, .pixabay, .wallhaven, .pixiv]
            && WallpaperLibraryQuery.requiredProviders(page: .downloads, state: .init(provider: .pixiv), relationships: relations) == [.pixiv]
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
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
