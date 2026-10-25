import Foundation

/// Frozen, metadata-only input supplied by the legacy owners before cleanup.
/// Array order is the original library order, never a current UI sort.
nonisolated struct LibraryCollectionsMigrationItem: Codable, Equatable, Sendable {
    let reference: WallpaperReference
    let locator: WallpaperLocator
    let tags: [String]
    let isFavorite: Bool

    init(reference: WallpaperReference, locator: WallpaperLocator = WallpaperLocator(),
         tags: [String] = [], isFavorite: Bool = false) {
        self.reference = reference
        self.locator = locator
        self.tags = tags
        self.isFavorite = isFavorite
    }
}

nonisolated struct LibraryCollectionsMigrationInput: Codable, Equatable, Sendable {
    let manifestID: String
    let capturedAt: Date
    let videos: [LibraryCollectionsMigrationItem]
    let videoTags: [String]
    let staticImages: [LibraryCollectionsMigrationItem]
    let staticImageTags: [String]
    let recent: [LibraryCollectionsMigrationItem]
    let aliases: [WallpaperReferenceAlias]
    let viewPreferences: LibraryCollectionsLegacyViewPreferences?

    init(manifestID: String, capturedAt: Date, videos: [LibraryCollectionsMigrationItem] = [],
         videoTags: [String] = [], staticImages: [LibraryCollectionsMigrationItem] = [],
         staticImageTags: [String] = [], recent: [LibraryCollectionsMigrationItem] = [],
         aliases: [WallpaperReferenceAlias] = [], viewPreferences: LibraryCollectionsLegacyViewPreferences? = nil) {
        self.manifestID = manifestID
        self.capturedAt = capturedAt
        self.videos = videos
        self.videoTags = videoTags
        self.staticImages = staticImages
        self.staticImageTags = staticImageTags
        self.recent = recent
        self.aliases = aliases
        self.viewPreferences = viewPreferences
    }
}

/// Frozen display preferences and legacy time ranks, never playback-success
/// dates or a second persistent member order. The App maps these once.
nonisolated struct LibraryCollectionsLegacyViewPreferences: Codable, Equatable, Sendable {
    var auxiliaryPreferences: Data? = nil
    var videoTimeOrder: [WallpaperReference] = []
    var imageTimeOrder: [WallpaperReference] = []
}

nonisolated struct LibraryCollectionsViewPreferencesSeed: Codable, Equatable, Sendable {
    let preferences: LibraryCollectionsLegacyViewPreferences
    let manifest: LibraryCollectionsMigrationManifest
}

nonisolated struct LibraryCollectionsMigrationTagOrigin: Codable, Equatable, Sendable {
    let provider: WallpaperProvider
    let originalName: String
    let isDeclared: Bool
}

nonisolated struct LibraryCollectionsMigrationTagMapping: Codable, Equatable, Sendable {
    let normalizedName: String
    let playlistID: UUID
    let displayName: String
    var origins: [LibraryCollectionsMigrationTagOrigin]
}

/// Persist alongside the frozen snapshot before attempting database publication.
/// A retry reuses these UUIDs; a tag's name is never its persistent primary key.
nonisolated struct LibraryCollectionsMigrationManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceManifestID: String
    let capturedAt: Date
    let tagMappings: [LibraryCollectionsMigrationTagMapping]
}

nonisolated struct LibraryCollectionsMigrationCounts: Codable, Equatable, Sendable {
    let videos: Int
    let staticImages: Int
    let declaredTags: Int
    let orphanTags: Int
    let playlists: Int
    let members: Int
    let favorites: Int
    let recent: Int
    let aliases: Int
}

nonisolated struct LibraryCollectionsMigrationResult: Codable, Equatable, Sendable {
    let payload: LibraryCollectionsImport
    let manifest: LibraryCollectionsMigrationManifest
    let counts: LibraryCollectionsMigrationCounts
}

nonisolated enum LibraryCollectionsMigrationError: Error, Equatable {
    case invalidReference
    case invalidTagName
    case conflictingAlias
    case aliasCycle
    case manifestMismatch
}

/// Pure mapping only: no filesystem probes, UserDefaults, media imports,
/// playback, or writes to either old or new storage.
nonisolated enum LibraryCollectionsMigration {
    static func prepareManifest(
        for input: LibraryCollectionsMigrationInput,
        reusing previous: LibraryCollectionsMigrationManifest? = nil
    ) throws -> LibraryCollectionsMigrationManifest {
        guard !input.manifestID.isEmpty else { throw LibraryCollectionsMigrationError.manifestMismatch }
        let tags = try orderedTags(in: input)
        if let previous {
            try validate(previous, input: input, tags: tags)
            return previous
        }
        return LibraryCollectionsMigrationManifest(
            schemaVersion: 1, sourceManifestID: input.manifestID, capturedAt: input.capturedAt,
            tagMappings: tags.map {
                LibraryCollectionsMigrationTagMapping(
                    normalizedName: $0.name, playlistID: UUID(), displayName: $0.name, origins: $0.origins
                )
            }
        )
    }

    static func build(
        _ input: LibraryCollectionsMigrationInput,
        manifest: LibraryCollectionsMigrationManifest
    ) throws -> LibraryCollectionsMigrationResult {
        let tags = try orderedTags(in: input)
        try validate(manifest, input: input, tags: tags)
        let aliasGraph = try resolvedAliases(input.aliases)
        func canonical(_ reference: WallpaperReference) throws -> WallpaperReference {
            guard !reference.sourceID.isEmpty else { throw LibraryCollectionsMigrationError.invalidReference }
            return aliasGraph.canonical[reference] ?? reference
        }

        let playlists = manifest.tagMappings.enumerated().map { rank, mapping in
            WallpaperPlaylist(id: mapping.playlistID, name: mapping.displayName,
                              createdAt: manifest.capturedAt, sidebarRank: rank)
        }
        let playlistByName = Dictionary(uniqueKeysWithValues: manifest.tagMappings.map {
            ($0.normalizedName, $0.playlistID)
        })
        var members: [WallpaperPlaylistMember] = []
        var membersByPlaylist: [UUID: Set<WallpaperReference>] = [:]
        var nextPosition: [UUID: Int] = [:]
        for item in input.videos + input.staticImages {
            let reference = try canonical(item.reference)
            for tag in item.tags {
                let name = try normalizedTag(tag)
                guard let playlistID = playlistByName[name] else {
                    throw LibraryCollectionsMigrationError.manifestMismatch
                }
                if membersByPlaylist[playlistID, default: []].insert(reference).inserted {
                    let position = nextPosition[playlistID, default: 0]
                    members.append(WallpaperPlaylistMember(playlistID: playlistID, reference: reference,
                                                           position: position, addedAt: manifest.capturedAt))
                    nextPosition[playlistID] = position + 1
                }
            }
        }
        var favorites: [WallpaperFavorite] = []
        var favoriteReferences: Set<WallpaperReference> = []
        for (index, item) in input.videos.enumerated() where item.isFavorite {
            let reference = try canonical(item.reference)
            if favoriteReferences.insert(reference).inserted {
                favorites.append(WallpaperFavorite(reference: reference, favoritedAt: nil, migrationOrder: index))
            }
        }
        var recentReferences: [WallpaperReference] = []
        var recentSeen: Set<WallpaperReference> = []
        for item in input.recent {
            let reference = try canonical(item.reference)
            if recentSeen.insert(reference).inserted, recentReferences.count < 50 {
                recentReferences.append(reference)
            }
        }
        let recent = recentReferences.enumerated().map { index, reference in
            WallpaperRecentUse(reference: reference, lastSuccessfulUseAt: nil,
                               commitSequence: Int64(recentReferences.count - index), migrationOrder: index)
        }

        var locators: [WallpaperReferenceLocator] = []
        var locatorIndices: [WallpaperReference: Int] = [:]
        func remember(_ reference: WallpaperReference, _ locator: WallpaperLocator) {
            if let index = locatorIndices[reference] {
                // First source owns conflicts. Later records can only fill missing hints.
                let old = locators[index].locator
                locators[index].locator = WallpaperLocator(
                    path: old.path ?? locator.path, titleHint: old.titleHint ?? locator.titleHint,
                    mediaKind: old.mediaKind == .unknown ? locator.mediaKind : old.mediaKind,
                    provenance: old.provenance ?? locator.provenance
                )
            } else {
                locatorIndices[reference] = locators.count
                locators.append(WallpaperReferenceLocator(reference: reference, locator: locator))
            }
        }
        for item in input.videos + input.staticImages + input.recent {
            let reference = try canonical(item.reference)
            // Retain the old UUID's recovery hint as well as the canonical one.
            remember(item.reference, item.locator)
            if reference != item.reference { remember(reference, item.locator) }
        }
        let payload = LibraryCollectionsImport(playlists: playlists, members: members, favorites: favorites,
                                               recent: recent, aliases: aliasGraph.aliases, locators: locators)
        return LibraryCollectionsMigrationResult(
            payload: payload, manifest: manifest,
            counts: LibraryCollectionsMigrationCounts(
                videos: input.videos.count, staticImages: input.staticImages.count,
                declaredTags: input.videoTags.count + input.staticImageTags.count,
                orphanTags: tags.filter { !$0.origins.contains(where: \.isDeclared) }.count,
                playlists: playlists.count, members: members.count, favorites: favorites.count,
                recent: recent.count, aliases: aliasGraph.aliases.count
            )
        )
    }

    private struct OrderedTag {
        let name: String
        var origins: [LibraryCollectionsMigrationTagOrigin]
    }

    private static func normalizedTag(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw LibraryCollectionsMigrationError.invalidTagName }
        return name
    }

    private static func orderedTags(in input: LibraryCollectionsMigrationInput) throws -> [OrderedTag] {
        var tags: [OrderedTag] = []
        var indices: [String: Int] = [:]
        func append(_ raw: String, provider: WallpaperProvider, declared: Bool) throws {
            let name = try normalizedTag(raw)
            let origin = LibraryCollectionsMigrationTagOrigin(provider: provider, originalName: raw,
                                                               isDeclared: declared)
            if let index = indices[name] {
                if !tags[index].origins.contains(origin) { tags[index].origins.append(origin) }
            } else {
                indices[name] = tags.count
                tags.append(OrderedTag(name: name, origins: [origin]))
            }
        }
        for tag in input.videoTags { try append(tag, provider: .videoLibrary, declared: true) }
        for tag in input.staticImageTags { try append(tag, provider: .staticImageLibrary, declared: true) }
        for item in input.videos {
            for tag in item.tags { try append(tag, provider: .videoLibrary, declared: false) }
        }
        for item in input.staticImages {
            for tag in item.tags { try append(tag, provider: .staticImageLibrary, declared: false) }
        }
        return tags
    }

    private static func validate(_ manifest: LibraryCollectionsMigrationManifest,
                                 input: LibraryCollectionsMigrationInput, tags: [OrderedTag]) throws {
        guard manifest.schemaVersion == 1, !input.manifestID.isEmpty,
              manifest.sourceManifestID == input.manifestID,
              manifest.tagMappings.count == tags.count,
              Set(manifest.tagMappings.map(\.playlistID)).count == tags.count else {
            throw LibraryCollectionsMigrationError.manifestMismatch
        }
        for (mapping, tag) in zip(manifest.tagMappings, tags) {
            guard mapping.normalizedName == tag.name, mapping.displayName == tag.name,
                  mapping.origins == tag.origins else { throw LibraryCollectionsMigrationError.manifestMismatch }
        }
    }

    private static func resolvedAliases(_ input: [WallpaperReferenceAlias]) throws -> (
        canonical: [WallpaperReference: WallpaperReference], aliases: [WallpaperReferenceAlias]
    ) {
        var targets: [WallpaperReference: WallpaperReference] = [:]
        var ordered: [WallpaperReferenceAlias] = []
        for alias in input {
            guard !alias.alias.sourceID.isEmpty, !alias.canonical.sourceID.isEmpty else {
                throw LibraryCollectionsMigrationError.invalidReference
            }
            if let existing = targets[alias.alias] {
                guard existing == alias.canonical else { throw LibraryCollectionsMigrationError.conflictingAlias }
            } else {
                targets[alias.alias] = alias.canonical
                ordered.append(alias)
            }
        }
        var canonical: [WallpaperReference: WallpaperReference] = [:]
        for alias in ordered {
            var reference = alias.alias
            var visited: Set<WallpaperReference> = []
            var path: [WallpaperReference] = []
            while let next = targets[reference] {
                guard visited.insert(reference).inserted else { throw LibraryCollectionsMigrationError.aliasCycle }
                path.append(reference)
                if let resolved = canonical[next] { reference = resolved; break }
                reference = next
            }
            for component in path { canonical[component] = reference }
        }
        return (canonical, ordered.map {
            WallpaperReferenceAlias(alias: $0.alias, canonical: canonical[$0.alias] ?? $0.canonical, proof: $0.proof)
        })
    }
}
