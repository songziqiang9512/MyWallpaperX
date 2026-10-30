import Foundation

/// Existing source owners supply these published projections. Browser results
/// never enter the local catalog, and queries do not scan or mutate a service.
nonisolated struct WallpaperLibraryCatalog: Sendable {
    var videos: [WallpaperContentItem] = []
    var images: [WallpaperContentItem] = []
    var downloads: [WallpaperContentItem] = []
    /// Original source task/account exclusions affect only My Downloads.
    /// Keep full source facts for explicit playback and mixed playlists.
    var excludedDownloadReferences: Set<WallpaperReference> = []
    var revision: UInt64 = 0
    /// A successful empty source is different from its initial empty value.
    var loadedProviders: Set<WallpaperProvider> = []
    /// Source-owned scan facts reach feedback without another scanner/error owner.
    var sourceScanStatuses: [WallpaperProvider: WallpaperSourceScanStatus] = [:]
}

nonisolated struct WallpaperLibraryPageResult: Sendable {
    let items: [WallpaperContentItem]
    let unfilteredCount: Int
}

nonisolated enum WallpaperLibraryQuery {
    /// Readiness follows the page's real source dependencies, before search,
    /// status or media filters can hide an as-yet-unloaded member.
    static func requiredProviders(page: WallpaperLibraryPage, state: WallpaperLibraryQueryState,
                                  relationships: UserCollectionsSnapshot) throws -> Set<WallpaperProvider> {
        let providers: Set<WallpaperProvider>
        let references: [WallpaperReference]
        switch page {
        case .videos: providers = [.videoLibrary]; references = []
        case .images: providers = [.staticImageLibrary]; references = []
        case .downloads: providers = [.steamWorkshop, .pixabay, .wallhaven, .pixiv]; references = []
        case .recent:
            // Use the same canonical deduplication-before-limit rule as the
            // visible history. Raw aliases must not consume the 50-item cap.
            references = []; providers = []
        case .favorites: references = relationships.favorites.map(\.reference); providers = []
        case .playlist(let id): references = relationships.members.filter { $0.playlistID == id }.map(\.reference); providers = []
        case .playlists, .workshop, .pixabay, .wallhaven, .pixiv: references = []; providers = []
        }
        var result = providers
        if page == .recent || !references.isEmpty {
            let resolver = try Resolver(aliases: relationships.aliases)
            let canonical: [WallpaperReference]
            if page == .recent { canonical = try recentReferences(relationships, resolver: resolver) }
            else { canonical = try references.map { try resolver.canonical($0) } }
            result.formUnion(canonical.map(\.provider))
        }
        return state.providers.isEmpty ? result : result.intersection(state.providers)
    }

    static func resolve(_ references: [WallpaperReference], catalog: WallpaperLibraryCatalog,
                        relationships: UserCollectionsSnapshot) throws -> [WallpaperContentItem] {
        let resolver = try Resolver(catalog: catalog, relationships: relationships)
        return try references.map { try resolver.resolve($0) }
    }

    static func canonicalReferences(_ references: Set<WallpaperReference>,
                                    relationships: UserCollectionsSnapshot) throws -> [WallpaperReference: WallpaperReference] {
        let resolver = try Resolver(aliases: relationships.aliases)
        var result: [WallpaperReference: WallpaperReference] = [:]
        for reference in references { result[reference] = try resolver.canonical(reference) }
        return result
    }

    /// A success receipt compares the exclusion seen at its explicit admission.
    /// Missing keys mean "not hidden then", never permission to clear a later hide.
    static func libraryExclusionRevisions(for references: Set<WallpaperReference>,
                                         relationships: UserCollectionsSnapshot) throws -> [WallpaperReference: Int64] {
        let resolver = try Resolver(aliases: relationships.aliases)
        var revisions: [WallpaperReference: Int64] = [:]
        for exclusion in relationships.excludedLibraryReferences {
            let key = try resolver.canonical(exclusion.reference)
            revisions[key] = max(revisions[key] ?? exclusion.revision, exclusion.revision)
        }
        var result: [WallpaperReference: Int64] = [:]
        for reference in references { result[reference] = revisions[try resolver.canonical(reference)] }
        return result
    }

    static func project(page: WallpaperLibraryPage, state: WallpaperLibraryQueryState,
                        catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot) throws -> WallpaperLibraryPageResult {
        if page == .playlists || page.isRemoteBrowse {
            return WallpaperLibraryPageResult(items: [], unfilteredCount: 0)
        }
        let resolver = try Resolver(catalog: catalog, relationships: relationships)
        func canonical(_ reference: WallpaperReference) throws -> WallpaperReference { try resolver.canonical(reference) }
        func resolve(_ reference: WallpaperReference) throws -> WallpaperContentItem { try resolver.resolve(reference) }
        let search = state.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = state.sort ?? defaultSort(page)
        let sortsItems = page != .recent && sort != .sourceOrder
        // This is a user-owned source-page exclusion, not an availability
        // fact. Retained relationships and explicit playback still resolve
        // against the complete catalog above.
        let excluded: Set<WallpaperReference>
        if page == .videos || page == .images || page == .downloads {
            excluded = Set(try relationships.excludedLibraryReferences.map { try canonical($0.reference) })
        } else { excluded = [] }
        func unique(_ items: [WallpaperContentItem]) -> [WallpaperContentItem] {
            var seen = Set<WallpaperReference>()
            return items.filter { seen.insert($0.reference).inserted }
        }
        var memberships: [WallpaperReference: [String]] = [:]
        if !search.isEmpty {
            let playlistNames = Dictionary(relationships.playlists.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            for member in relationships.members {
                if let name = playlistNames[member.playlistID] {
                    memberships[try canonical(member.reference), default: []].append(name)
                }
            }
        }
        var addedAt: [WallpaperReference: Date] = [:]
        var favoritedAt: [WallpaperReference: Date] = [:]
        if sortsItems, sort == .favoritedAt {
            for favorite in relationships.favorites {
                if let date = favorite.favoritedAt { favoritedAt[try canonical(favorite.reference)] = date }
            }
        }
        var recentAt: [WallpaperReference: Date] = [:]
        if sortsItems, sort == .lastUsed {
            for recent in relationships.recent {
                if let date = recent.lastSuccessfulUseAt { recentAt[try canonical(recent.reference)] = date }
            }
        }
        let candidates: [WallpaperContentItem]
        switch page {
        case .videos:
            candidates = try unique(catalog.videos.map { try resolve($0.reference) })
                .filter { $0.reference.provider == .videoLibrary && !excluded.contains($0.reference) }
        case .images:
            candidates = try unique(catalog.images.map { try resolve($0.reference) })
                .filter { !excluded.contains($0.reference) }
        case .downloads:
            candidates = try unique(catalog.downloads.filter {
                !catalog.excludedDownloadReferences.contains($0.providerReference)
                    && (state.showsAdultContent || $0.metadata.contentRating != .adult)
            }
                .map { try resolve($0.reference) }).filter { !excluded.contains($0.reference) }
        case .recent:
            // Filter/search only these 50; never refill from older history.
            candidates = try recentReferences(relationships, resolver: resolver).map(resolve)
        case .favorites: candidates = try unique(relationships.favorites.map { try resolve($0.reference) })
        case .playlist(let id):
            guard relationships.playlists.contains(where: { $0.id == id }) else { throw UserCollectionsError.missingPlaylist }
            let members = relationships.members.filter { $0.playlistID == id }.sorted { $0.position < $1.position }
            if sortsItems, sort == .addedAt {
                for member in members { addedAt[try canonical(member.reference)] = member.addedAt }
            }
            candidates = try unique(members.map { try resolve($0.reference) })
        case .playlists, .workshop, .pixabay, .wallhaven, .pixiv:
            // Directory and server-paginated browser pages use their own typed
            // projections, rather than silently sorting them as local items.
            candidates = []
        }
        let steamIDSearch = WallpaperProvider.workshopItemIDSearchID(from: search) ?? search
        var visible = candidates.filter { item in
            guard state.providers.isEmpty || state.providers.contains(item.reference.provider),
                  state.kinds.isEmpty || state.kinds.contains(item.kind) else { return false }
            if !state.statuses.isEmpty && !state.statuses.contains(where: { status in
                switch status {
                case .playable: return item.capabilities.contains(.play)
                case .unavailable: return item.publishedAvailability == .unavailable
                case .transferring:
                    return item.acquisition.phase != .idle && item.acquisition.phase != .failed
                        || item.update.phase != .idle && item.update.phase != .failed
                case .failed: return item.acquisition.phase == .failed || item.update.phase == .failed
                }
            }) {
                return false
            }
            guard !search.isEmpty else { return true }
            var terms = [item.title] + item.reference.provider.librarySearchTerms + (memberships[item.reference] ?? [])
            if item.providerReference.provider == .steamWorkshop {
                terms += [item.metadata.author, item.metadata.summary, item.metadata.descriptionText].compactMap { $0 }
                    + item.metadata.sourceTags
            }
            if item.providerReference.provider == .staticImageLibrary, let path = item.locator.path { terms.append(path) }
            if terms.contains(where: { $0.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) { return true }
            // A proven video backing retains its canonical Steam ID, but a
            // numeric URL never searches unrelated provider IDs or file paths.
            return [item.reference, item.providerReference].contains { reference in
                reference.provider == .steamWorkshop
                    && reference.sourceID.range(of: steamIDSearch, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        if sortsItems {
            let ascending = state.sort == nil && (page == .downloads || page == .favorites) ? false : state.ascending
            let originalPositions = sort == .legacyTime || sort == .favoritedAt
                ? Dictionary(candidates.enumerated().map { ($0.element.reference, $0.offset) }, uniquingKeysWith: { first, _ in first }) : [:]
            var legacyPositions: [WallpaperReference: Int] = [:]
            if sort == .legacyTime {
                for reference in state.legacyTimeOrder ?? [] {
                    let key = try canonical(reference)
                    if legacyPositions[key] == nil { legacyPositions[key] = legacyPositions.count }
                }
            }
            let locale = Locale(identifier: "en_US_POSIX")
            var foldedTitles: [String: String] = [:]
            func titleComparison(_ left: WallpaperContentItem, _ right: WallpaperContentItem) -> ComparisonResult {
                guard page == .downloads else { return left.title.localizedStandardCompare(right.title) }
                func folded(_ title: String) -> String {
                    if let cached = foldedTitles[title] { return cached }
                    let value = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                    foldedTitles[title] = value
                    return value
                }
                let comparison = folded(left.title).compare(folded(right.title), options: [.numeric], locale: locale)
                if comparison != .orderedSame { return comparison }
                let identity = left.reference.sourceID.compare(right.reference.sourceID, options: [.literal])
                return identity == .orderedSame ? stableKey(left).compare(stableKey(right), options: [.literal]) : identity
            }
            func tieBefore(_ left: WallpaperContentItem, _ right: WallpaperContentItem) -> Bool {
                guard page == .downloads else { return stableKey(left) < stableKey(right) }
                return titleComparison(left, right) == (ascending ? .orderedAscending : .orderedDescending)
            }
            visible.sort { left, right in
                let comparison: ComparisonResult
                switch sort {
                case .name: comparison = titleComparison(left, right)
                case .fileSize: return compareOptional(left.metadata.fileSizeBytes, right.metadata.fileSizeBytes, ascending: ascending, tieBefore: { tieBefore(left, right) })
                case .createdAt: return compareOptional(left.metadata.createdAt, right.metadata.createdAt, ascending: ascending, tieBefore: { tieBefore(left, right) })
                case .modifiedAt: return compareOptional(left.metadata.modifiedAt, right.metadata.modifiedAt, ascending: ascending, tieBefore: { tieBefore(left, right) })
                case .lastUsed: return compareOptional(recentAt[left.reference], recentAt[right.reference], ascending: ascending, tieBefore: { tieBefore(left, right) })
                case .addedAt: return compareOptional(addedAt[left.reference], addedAt[right.reference], ascending: ascending, tieBefore: { tieBefore(left, right) })
                case .legacyTime:
                    switch (legacyPositions[left.reference], legacyPositions[right.reference]) {
                    case let (a?, b?): return ascending ? a < b : a > b
                    case (.some, nil): return true
                    case (nil, .some): return false
                    case (nil, nil): return (originalPositions[left.reference] ?? 0) < (originalPositions[right.reference] ?? 0)
                    }
                case .favoritedAt:
                    if favoritedAt[left.reference] == nil, favoritedAt[right.reference] == nil {
                        return (originalPositions[left.reference] ?? 0) < (originalPositions[right.reference] ?? 0)
                    }
                    return compareOptional(favoritedAt[left.reference], favoritedAt[right.reference], ascending: ascending, tieBefore: { tieBefore(left, right) })
                case .sourceOrder: comparison = .orderedSame
                }
                if comparison == .orderedSame { return tieBefore(left, right) }
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
        return WallpaperLibraryPageResult(items: visible, unfilteredCount: candidates.count)
    }

    /// Directory order is the sidebar rank; retired saved sort values are ignored.
    /// Search only filters names. One resolver serves covers without per-list catalog scans.
    static func directory(state: WallpaperLibraryQueryState, catalog: WallpaperLibraryCatalog,
                          relationships: UserCollectionsSnapshot) throws -> [WallpaperPlaylistDirectoryEntry] {
        guard state.providers.isEmpty, state.kinds.isEmpty, state.statuses.isEmpty else {
            throw WallpaperLibraryQueryError.unsupportedDirectoryFilter
        }
        let resolver = try Resolver(catalog: catalog, relationships: relationships)
        let members = Dictionary(grouping: relationships.members, by: \.playlistID)
        var entries: [WallpaperPlaylistDirectoryEntry] = []
        for playlist in relationships.playlists {
            var seen = Set<WallpaperReference>()
            var coverReference: WallpaperReference?
            let ordered = (members[playlist.id] ?? []).enumerated().sorted {
                $0.element.position == $1.element.position ? $0.offset < $1.offset : $0.element.position < $1.element.position
            }
            for member in ordered {
                let item = try resolver.resolve(member.element.reference)
                guard seen.insert(item.reference).inserted else { continue }
                if seen.count == 1 { coverReference = item.providerReference }
            }
            entries.append(.init(id: playlist.id, name: playlist.name, count: seen.count, coverReference: coverReference,
                                 createdAt: playlist.createdAt, modifiedAt: playlist.modifiedAt))
        }
        let ranks = Dictionary(relationships.playlists.map { ($0.id, $0.sidebarRank) }, uniquingKeysWith: { first, _ in first })
        let search = state.search.trimmingCharacters(in: .whitespacesAndNewlines)
        entries = entries.filter { search.isEmpty || $0.name.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        entries.sort { left, right in
            let a = ranks[left.id] ?? 0, b = ranks[right.id] ?? 0
            return a == b ? left.id.uuidString < right.id.uuidString : a < b
        }
        return entries
    }

    private static func recentReferences(_ relationships: UserCollectionsSnapshot, resolver: Resolver) throws -> [WallpaperReference] {
        let ordered = relationships.recent.enumerated().sorted {
            if $0.element.commitSequence != $1.element.commitSequence { return $0.element.commitSequence > $1.element.commitSequence }
            return $0.offset < $1.offset
        }
        var seen = Set<WallpaperReference>()
        var references: [WallpaperReference] = []
        for recent in ordered {
            let reference = try resolver.canonical(recent.element.reference)
            if seen.insert(reference).inserted { references.append(reference) }
            if references.count == 50 { break }
        }
        return references
    }

    struct Resolver {
        private let aliases: [WallpaperReference: WallpaperReference]
        private var items: [WallpaperReference: WallpaperContentItem] = [:]
        private var locators: [WallpaperReference: WallpaperLocator] = [:]

        init(aliases: [WallpaperReferenceAlias]) throws {
            self.aliases = try WallpaperLibraryQuery.aliasMap(aliases)
        }

        init(catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot) throws {
            try self.init(aliases: relationships.aliases)
            for item in catalog.videos + catalog.images + catalog.downloads {
                let key = try canonical(item.reference)
                let normalized = WallpaperLibraryQuery.replacingReference(item, with: key)
                if items[key] == nil || normalized.providerReference == key { items[key] = normalized }
            }
            for item in relationships.locators { locators[try canonical(item.reference)] = item.locator }
        }

        func canonical(_ reference: WallpaperReference) throws -> WallpaperReference {
            var value = reference, visited = Set<WallpaperReference>()
            while let next = aliases[value] {
                guard visited.insert(value).inserted else { throw UserCollectionsError.corruptData("alias cycle") }
                value = next
            }
            return value
        }

        func resolve(_ reference: WallpaperReference) throws -> WallpaperContentItem {
            let key = try canonical(reference)
            return items[key] ?? WallpaperLibraryQuery.unavailable(key, locator: locators[key])
        }
    }

    static func defaultSort(_ page: WallpaperLibraryPage) -> WallpaperLibrarySort {
        switch page {
        case .downloads: return .createdAt
        case .favorites: return .favoritedAt
        default: return .sourceOrder
        }
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?, ascending: Bool,
                                                       tieBefore: () -> Bool) -> Bool {
        switch (lhs, rhs) {
        case (nil, .some): return false
        case (.some, nil): return true
        case (nil, nil): return tieBefore()
        case let (.some(a), .some(b)):
            return a == b ? tieBefore() : (ascending ? a < b : a > b)
        }
    }

    private static func stableKey(_ item: WallpaperContentItem) -> String { item.reference.storageKey }

    private static func aliasMap(_ values: [WallpaperReferenceAlias]) throws -> [WallpaperReference: WallpaperReference] {
        var result: [WallpaperReference: WallpaperReference] = [:]
        for value in values {
            if let old = result[value.alias], old != value.canonical { throw UserCollectionsError.corruptData("conflicting alias") }
            result[value.alias] = value.canonical
        }
        return result
    }

    private static func replacingReference(_ item: WallpaperContentItem, with reference: WallpaperReference) -> WallpaperContentItem {
        WallpaperContentItem(reference: reference, providerReference: item.providerReference, locator: item.locator,
                             title: item.title, kind: item.kind, publishedAvailability: item.publishedAvailability,
                             capabilities: item.capabilities, metadata: item.metadata, acquisition: item.acquisition,
                             update: item.update, aliases: item.aliases)
    }

    private static func unavailable(_ reference: WallpaperReference, locator: WallpaperLocator?) -> WallpaperContentItem {
        let locator = locator ?? WallpaperLocator(mediaKind: .unknown)
        return WallpaperContentItem(reference: reference, providerReference: reference, locator: locator,
                                    title: locator.titleHint ?? reference.sourceID, kind: locator.mediaKind,
                                    publishedAvailability: .unavailable, capabilities: [.inspect],
                                    metadata: WallpaperContentMetadata(), acquisition: .idle, update: .idle, aliases: [])
    }
}

nonisolated enum WallpaperLibraryQueryError: Error, LocalizedError {
    case unsupportedDirectoryFilter

    var errorDescription: String? {
        switch self {
        case .unsupportedDirectoryFilter: return "播放列表目录仅支持名称搜索。"
        }
    }
}
