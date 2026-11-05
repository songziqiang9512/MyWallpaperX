import Foundation

@main struct WallpaperLibraryViewPreferencesHarness {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        func ref(_ id: String) -> WallpaperReference { .init(provider: .videoLibrary, sourceID: id) }
        let a = ref("a"), b = ref("b"), new = ref("new")
        let shared = UUID(), imageOnly = UUID()
        let mixed = WallpaperPlaylist(id: shared, name: "Mixed", sidebarRank: 0)
        func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        func item(_ reference: WallpaperReference, date: TimeInterval) -> WallpaperContentItem {
            .init(reference: reference, providerReference: reference, locator: .init(), title: reference.sourceID, kind: .video,
                publishedAvailability: .available, capabilities: [.play, .organize], metadata: .init(createdAt: Date(timeIntervalSince1970: date)),
                acquisition: .idle, update: .idle, aliases: [])
        }
        let catalog = WallpaperLibraryCatalog(videos: [item(a, date: 500), item(b, date: 1000), item(new, date: 1)])
        let suite = "mwx.view-preferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        _ = model.update(catalog: catalog, relationships: relationships)
        let videoQuery = WallpaperLibraryQueryState(search: "video", sort: .name, ascending: false, preferredColumns: 3)
        _ = model.setQueryState(videoQuery)
        _ = model.switchPage(.downloads)
        let downloadQuery = WallpaperLibraryQueryState(providers: [.pixabay], kinds: [.video], statuses: [.playable], sort: .createdAt, preferredColumns: 6)
        _ = model.setQueryState(downloadQuery)
        _ = model.switchPage(.videos)
        checks["current-page-sessions-retain-independent-query-sort-and-density"] = model.queryState == videoQuery
        let reopened = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["current-cache-reopens-the-selected-page-and-its-query"] = reopened.page == .videos && reopened.queryState == videoQuery
        _ = reopened.switchPage(.downloads)
        checks["current-cache-retains-the-other-pages-query"] = reopened.queryState == downloadQuery
        model.resetViewState()
        checks["reset-persists-current-empty-page-preferences"] = WallpaperLibraryPresentation(collections: nil, defaults: defaults).queryState == .init()
        for version in 0..<4 {
            let old = try data(["version": version, "page": "old page", "queries": "old shape"] as [String: Any])
            defaults.set(old, forKey: WallpaperLibraryPresentation.settingsKey)
            let ignored = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
            checks["old-cache-version-is-ignored-before-current-payload-decode-\(version)"] = ignored.page == .videos
                && ignored.queryState == .init() && ignored.lastError == nil && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == old
            _ = ignored.setQueryState(.init(preferredColumns: 6))
            let written = try JSONSerialization.jsonObject(with: defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!) as! [String: Any]
            checks["explicit-current-preference-replaces-ignored-cache-with-v4-\(version)"] = written["version"] as? Int == 4
                && WallpaperLibraryPresentation(collections: nil, defaults: defaults).queryState.preferredColumns == 6
        }
        let invalid = Data("unsupported bytes".utf8)
        defaults.set(invalid, forKey: WallpaperLibraryPresentation.settingsKey)
        let recovery = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        _ = recovery.setQueryState(.init(preferredColumns: 3))
        checks["corrupt-current-cache-is-preserved-with-warning"] = recovery.lastError != nil
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == invalid

        func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
        let geometryQuery = WallpaperLibraryQueryState(search: "preserve all fields", providers: [.steamWorkshop, .pixabay], kinds: [.scene, .video],
            statuses: [.failed, .playable], sort: .name, ascending: false, preferredColumns: 3,
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
        checks["current-query-persists-all-filter-sets-without-retired-single-value-fields"] =
            Set(queryObject["providers"] as! [String]) == Set([WallpaperProvider.steamWorkshop.rawValue, WallpaperProvider.pixabay.rawValue])
            && Set(queryObject["kinds"] as! [String]) == Set([WallpaperMediaKind.scene.rawValue, WallpaperMediaKind.video.rawValue])
            && Set(queryObject["statuses"] as! [String]) == Set([WallpaperLibraryStatusFilter.failed.rawValue, WallpaperLibraryStatusFilter.playable.rawValue])
            && queryObject["provider"] == nil && queryObject["kind"] == nil && queryObject["status"] == nil
        let pageObject = try object(WallpaperLibraryPage.videos)
        defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
        let geometryModel = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        _ = geometryModel.setQueryState(geometryQuery)
        geometryModel.setDirectoryScrollAnchor(imageOnly, offset: -19.25, atTop: false)
        let preciseBytes = defaults.data(forKey: WallpaperLibraryPresentation.settingsKey)!
        let precise = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["current-v4-restores-finite-negative-query-and-directory-offsets-exactly"] = precise.queryState == geometryQuery
            && precise.directoryScrollAnchor == imageOnly && precise.directoryScrollOffset == -19.25 && precise.directoryScrollAtTop == false
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == preciseBytes
        precise.setDirectoryScrollAnchor(imageOnly, offset: -19.25, atTop: true)
        let atTop = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["directory-explicit-top-is-not-confused-with-same-first-card-and-offset"] = atTop.directoryScrollAnchor == imageOnly
            && atTop.directoryScrollOffset == -19.25 && atTop.directoryScrollAtTop == true
        let anchoredRelations = UserCollectionsSnapshot(revision: 10, resetEpoch: relationships.resetEpoch, playlists: [.init(id: imageOnly, name: "Images", sidebarRank: 0)], members: [], favorites: [], recent: [], aliases: [], locators: [])
        _ = atTop.update(catalog: catalog, relationships: anchoredRelations)
        let removedRelations = UserCollectionsSnapshot(revision: 11, resetEpoch: relationships.resetEpoch, playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        _ = atTop.update(catalog: catalog, relationships: removedRelations)
        checks["deleted-directory-reference-retires-its-offset-but-preserves-explicit-true-top"] = atTop.directoryScrollAnchor == nil
            && atTop.directoryScrollOffset == nil && atTop.directoryScrollAtTop == true
        let currentEnvelope = try JSONSerialization.jsonObject(with: preciseBytes) as! [String: Any]
        func invalidEnvelope(_ query: [String: Any], version: Int = 4) throws -> Data {
            var envelope = currentEnvelope; envelope["version"] = version
            envelope["queries"] = [["page": pageObject, "query": query]]
            return try data(envelope)
        }
        var pagePayloadsRejected = true
        for payload in [42, NSNull(), []] as [Any] {
            let bytes = try data(["workshop": payload])
            pagePayloadsRejected = pagePayloadsRejected && (try? JSONDecoder().decode(WallpaperLibraryPage.self, from: bytes)) == nil
        }
        checks["current-page-codec-rejects-nonobject-enum-payloads"] = pagePayloadsRejected
        checks["retired-workshop-page-alias-is-not-accepted"] = (try? JSONDecoder().decode(WallpaperLibraryPage.self,
            from: data(["workshopSubscriptions": [:] as [String: Any]]))) == nil
        var currentPagesRoundTrip = true
        for page in [WallpaperLibraryPage.videos, .images, .downloads, .recent, .workshop, .pixabay, .wallhaven, .pixiv, .playlists, .favorites, .playlist(shared)] {
            let decoded = try JSONDecoder().decode(WallpaperLibraryPage.self, from: JSONEncoder().encode(page))
            currentPagesRoundTrip = currentPagesRoundTrip && decoded == page
        }
        checks["all-current-page-cases-keep-the-original-associated-value-codec"] = currentPagesRoundTrip
        let currentEntry: [String: Any] = ["page": pageObject, "query": queryObject]
        let duplicateBytes = try data(["version": 4, "page": pageObject, "queries": [currentEntry, currentEntry]])
        defaults.set(duplicateBytes, forKey: WallpaperLibraryPresentation.settingsKey)
        let duplicate = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["current-ui-cache-rejects-duplicate-page-records"] = duplicate.lastError != nil
            && defaults.data(forKey: WallpaperLibraryPresentation.settingsKey) == duplicateBytes
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
        var missingColumns = queryObject; missingColumns.removeValue(forKey: "preferredColumns")
        checks["missing-column-key-decodes-new-five-column-default-without-other-loss"] = try JSONDecoder().decode(
            WallpaperLibraryQueryState.self, from: data(missingColumns)).preferredColumns == 5
        var nonFiniteObject = queryObject; nonFiniteObject["scrollOffset"] = "NaN"
        let nonFiniteDecoder = JSONDecoder()
        nonFiniteDecoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        checks["query-codec-refuses-nonfinite-offset-even-with-custom-float-decoding"] = (try? nonFiniteDecoder.decode(
            WallpaperLibraryQueryState.self, from: data(nonFiniteObject))) == nil
        let futureGeometryBytes = try invalidEnvelope(queryObject, version: 5)
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
        let facetQuery = WallpaperLibraryQueryState(search: "needle", providers: [.steamWorkshop], kinds: [.scene],
            statuses: [.playable], sort: .name, ascending: false)
        _ = facets.setQueryState(facetQuery)
        checks["type-counts-remove-only-kind-filter-and-preserve-search-provider-status"] = facets.mediaKindCounts == [.video: 1]
            && facets.queryResult.items.isEmpty && facets.queryState == facetQuery
        var mixedFacetQuery = facetQuery
        mixedFacetQuery.providers.insert(.pixabay)
        mixedFacetQuery.kinds = [.scene, .web]
        mixedFacetQuery.statuses = [.playable, .unavailable]
        _ = facets.setQueryState(mixedFacetQuery)
        checks["type-facet-counts-ignore-all-selected-kinds-without-clearing-composed-provider-status-or-search"] =
            facets.mediaKindCounts == [.video: 2, .scene: 1] && facets.queryState == mixedFacetQuery
            && facets.queryResult.items.map(\.reference.sourceID) == ["scene"]
        func facetCounts(_ view: WallpaperLibraryPresentation, _ label: String, ceiling: Int = 0) -> [WallpaperMediaKind: Int] {
            let before = WallpaperLibraryQuery.fullResolverInitializations
            let counts = view.mediaKindCounts
            FileHandle.standardError.write(Data("FACET PREPARATIONS \(label) \(ceiling) \(WallpaperLibraryQuery.fullResolverInitializations - before)\n".utf8))
            return counts
        }
        _ = facetCounts(facets, "active-kinds", ceiling: 1)
        for (index, original) in [facetQuery, mixedFacetQuery].enumerated() {
            var query = original
            query.kinds = []; query.sort = index == 0 ? .fileSize : .name; query.ascending = index == 0
            let expected: [WallpaperMediaKind: Int] = index == 0 ? [.video: 1] : [.video: 2, .scene: 1]
            let accepted = facets.setQueryState(query), items = facets.queryResult.items
            checks["unselected-kinds-count-accepted-sort-search-provider-status-\(index)"] = accepted
                && facetCounts(facets, "known-\(index)") == expected && facets.queryState == query
                && facets.queryResult.items == items && items.count == expected.values.reduce(0, +)
        }
        var updated = facetCatalog
        updated.revision = 1
        updated.downloads.append(facet("new-image", provider: .pixabay, kind: .image, title: "needle", available: true))
        let acceptedQuery = facets.queryState
        checks["type-counts-follow-the-next-accepted-catalog-without-reusing-old-members"] = facets.update(catalog: updated, relationships: relationships)
            && facetCounts(facets, "updated-catalog") == [.image: 1, .video: 2, .scene: 1]
            && facets.queryState == acceptedQuery && facets.queryResult.items.count == 4
        let beforeFailure = facets.queryResult.items
        let badRelationships = UserCollectionsSnapshot(revision: 2, resetEpoch: relationships.resetEpoch, playlists: [], members: [], favorites: [], recent: [], aliases: [
                .init(alias: facetCatalog.downloads[0].reference, canonical: facetCatalog.downloads[1].reference, proof: .publishedDownload),
                .init(alias: facetCatalog.downloads[1].reference, canonical: facetCatalog.downloads[0].reference, proof: .publishedDownload)], locators: [])
        checks["failed-projection-keeps-visible-error-query-items-and-accepted-type-counts"] = !facets.update(catalog: updated, relationships: badRelationships)
            && facets.lastError == UserCollectionsError.corruptData("alias cycle").localizedDescription
            && facets.queryState == acceptedQuery && facets.queryResult.items == beforeFailure
            && facetCounts(facets, "failed-update") == [.image: 1, .video: 2, .scene: 1]
        defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
        let unknown = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        let unknownRelationships = UserCollectionsSnapshot(revision: 1, resetEpoch: relationships.resetEpoch, playlists: [mixed], members: Array(facetCatalog.downloads.prefix(2)).enumerated().map {
                .init(playlistID: shared, reference: $0.element.reference, position: $0.offset, addedAt: Date())
            }, favorites: [], recent: [], aliases: [], locators: [])
        checks["unknown-relationships-keep-main-playlist-empty-but-preserve-original-facet-query"] = unknown.update(
            catalog: facetCatalog, relationships: unknownRelationships, relationshipsKnown: false)
            && unknown.switchPage(.playlist(shared)) && unknown.queryResult.items.isEmpty
            && facetCounts(unknown, "unknown-playlist", ceiling: 1) == [.video: 1, .scene: 1]
            && unknown.page == .playlist(shared) && unknown.queryState == .init() && unknown.lastError == nil
        let missing = WallpaperLibraryPage.playlist(UUID())
        checks["unknown-missing-playlist-facet-failure-stays-empty-without-changing-main-state"] = unknown.switchPage(missing)
            && facetCounts(unknown, "unknown-missing", ceiling: 1).isEmpty && unknown.page == missing
            && unknown.queryState == .init() && unknown.queryResult.items.isEmpty && unknown.lastError == nil
        for (index, page) in [WallpaperLibraryPage.playlists, .workshop, .pixabay, .wallhaven, .pixiv].enumerated() {
            checks["directory-or-remote-type-counts-stay-empty-\(index)"] = unknown.switchPage(page)
                && facetCounts(unknown, "empty-\(index)").isEmpty && unknown.page == page && unknown.queryResult.items.isEmpty
        }
        defaults.removeObject(forKey: WallpaperLibraryPresentation.settingsKey)
        let uninitialized = WallpaperLibraryPresentation(collections: nil, defaults: defaults)
        checks["type-counts-without-accepted-inputs-stay-empty"] = facetCounts(uninitialized, "uninitialized").isEmpty
            && uninitialized.queryResult.items.isEmpty && uninitialized.queryState == .init()
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
