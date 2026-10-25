import Foundation

nonisolated struct LibraryPersonalSettingsPlan: Codable, Sendable {
    let commandID: UUID
    let resetEpoch: UUID
    let expectedOrganization: LibraryCollectionsOrganizationState
    let sourcePatches: [PersonalSettingsSourcePatch]
    let beforePreferences: PersonalSettingsPreferences
    let targetPreferences: PersonalSettingsPreferences
    let collections: LibraryCollectionsPersonalSettingsImport
    let summary: PersonalSettingsImportSummary
}

/// One-shot profile mapping. Filesystem normalization/availability is supplied
/// by the explicit import action; this mapper performs no I/O or source edits.
nonisolated enum LibraryPersonalSettings {
    static func decode(_ data: Data) throws -> PersonalSettingsPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersonalSettingsPayload.self, from: data)
    }

    static func encode(_ payload: PersonalSettingsPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func export(sources: [PersonalSettingsLocalSource], preferences: PersonalSettingsPreferences,
                       state: UserCollectionsSnapshot, coverAssets: [WallpaperPlaylistCoverAsset] = [],
                       at date: Date = Date()) throws -> PersonalSettingsPayload {
        let canonical = try aliasMap(state.aliases)
        var references: [WallpaperReference] = []
        var seen = Set<WallpaperReference>()
        for reference in sources.map(\.reference) + state.members.map(\.reference)
            + state.favorites.map(\.reference) + state.locators.map(\.reference)
            + state.excludedLibraryReferences.map(\.reference) {
            let ref = canonical[reference] ?? reference
            if seen.insert(ref).inserted { references.append(ref) }
        }
        let favorites = Dictionary(uniqueKeysWithValues: state.favorites.map { ($0.reference, $0) })
        var collections = LibraryCollectionsPersonalSettingsImport()
        collections.playlists = state.playlists
        collections.members = state.members
        collections.favoriteStates = references.map {
            .init(reference: $0, isFavorite: favorites[$0] != nil, favoritedAt: favorites[$0]?.favoritedAt)
        }
        collections.locators = state.locators
        collections.aliases = state.aliases
        collections.playlistMetadataIsExplicit = true
        let covers = try checkedCoverAssets(coverAssets)
        let needed = Set(state.playlists.compactMap(\.customCoverAssetID))
        guard needed.isSubset(of: Set(covers.keys)) else { throw PersonalSettingsError.invalidPayload("列表封面副本缺失") }
        collections.coverAssets = needed.sorted { $0.uuidString < $1.uuidString }.compactMap { covers[$0] }
        let excluded = Set(state.excludedLibraryReferences.map { canonical[$0.reference] ?? $0.reference })
        collections.libraryExclusionStates = references.map { .init(reference: $0, isExcluded: excluded.contains($0)) }
        return PersonalSettingsPayload(exportedAt: date, preferences: preferences, sources: sources, collections: collections)
    }

    static func plan(_ payload: PersonalSettingsPayload, sources: [PersonalSettingsLocalSource],
                     beforePreferences: PersonalSettingsPreferences, targetPreferences: PersonalSettingsPreferences,
                     state: UserCollectionsSnapshot, normalizedPaths: [String: String], missingPathCount: Int,
                     commandID: UUID = UUID(), at date: Date = Date()) throws -> LibraryPersonalSettingsPlan {
        var sourceByRef: [WallpaperReference: PersonalSettingsLocalSource] = [:]
        var sourceByPath: [WallpaperProvider: [String: PersonalSettingsLocalSource]] = [:]
        for source in sources {
            try validate(source)
            guard sourceByRef.updateValue(source, forKey: source.reference) == nil else {
                throw PersonalSettingsError.invalidPayload("重复来源 ID")
            }
            sourceByPath[source.reference.provider, default: [:]][normalizedPaths[source.path] ?? source.path] = source
        }
        var remapping: [WallpaperReference: WallpaperReference] = [:]
        var patches: [WallpaperReference: PersonalSettingsSourcePatch] = [:]
        var patchOrder: [WallpaperReference] = []
        var merged = 0, created = 0

        func merge(_ source: PersonalSettingsLocalSource) throws -> WallpaperReference {
            try validate(source)
            let normalizedPath = normalizedPaths[source.path] ?? source.path
            let existing = sourceByRef[source.reference]
                ?? sourceByPath[source.reference.provider]?[normalizedPath]
            let reference = existing?.reference ?? source.reference
            let title = source.title.isEmpty ? (existing?.title ?? URL(fileURLWithPath: normalizedPath).lastPathComponent) : source.title
            let firstIndexedAt = reference.provider == .videoLibrary ? (existing?.firstIndexedAt ?? source.firstIndexedAt) : nil
            let target = PersonalSettingsLocalSource(reference: reference, path: existing?.path ?? normalizedPath,
                                                     title: title, firstIndexedAt: firstIndexedAt)
            if patches[reference] == nil {
                patchOrder.append(reference)
                if existing == nil { created += 1 } else { merged += 1 }
            }
            let before = patches[reference].map(\.before) ?? existing
            patches[reference] = PersonalSettingsSourcePatch(before: before, target: target)
            sourceByRef[reference] = target
            sourceByPath[reference.provider, default: [:]][normalizedPath] = target
            remapping[source.reference] = reference
            return reference
        }

        var collections: LibraryCollectionsPersonalSettingsImport
        if payload.schemaVersion >= 6 {
            guard let incoming = payload.collections else { throw PersonalSettingsError.invalidPayload("collections") }
            var declarations: [WallpaperReference: PersonalSettingsLocalSource] = [:]
            for source in payload.sources {
                if let previous = declarations[source.reference], previous != source {
                    throw PersonalSettingsError.invalidPayload("来源 ID 声明冲突")
                }
                declarations[source.reference] = source
                _ = try merge(source)
            }
            func mapped(_ reference: WallpaperReference) -> WallpaperReference { remapping[reference] ?? reference }
            collections = incoming
            collections.legacyOrigins = []
            collections.members = incoming.members.map {
                .init(playlistID: $0.playlistID, reference: mapped($0.reference), position: $0.position, addedAt: $0.addedAt)
            }
            collections.favoriteStates = incoming.favoriteStates.map {
                .init(reference: mapped($0.reference), isFavorite: $0.isFavorite, favoritedAt: $0.favoritedAt)
            }
            collections.locators = incoming.locators.map { .init(reference: mapped($0.reference), locator: $0.locator) }
            collections.aliases = incoming.aliases.compactMap {
                let alias = mapped($0.alias), canonical = mapped($0.canonical)
                return alias == canonical ? nil : .init(alias: alias, canonical: canonical, proof: .restoredSourceRecord)
            }
            if payload.schemaVersion == 7 {
                collections.playlistMetadataIsExplicit = true
                collections.libraryExclusionStates = incoming.libraryExclusionStates?.map {
                    .init(reference: mapped($0.reference), isExcluded: $0.isExcluded)
                }
                collections.expectedLibraryExclusions = state.excludedLibraryReferences
            } else {
                // Older profiles never declared these values. A missing field
                // cannot clear a cover, description or a later hide intent.
                collections.playlistMetadataIsExplicit = false
                collections.coverAssets = []
                collections.libraryExclusionStates = nil
                collections.expectedLibraryExclusions = nil
            }
        } else {
            collections = LibraryCollectionsPersonalSettingsImport()
            var names: [String] = [], playlistByName: [String: UUID] = [:]
            func addTag(_ raw: String) {
                let name = normalizedTag(raw)
                guard !name.isEmpty, playlistByName[name] == nil else { return }
                let id = UUID()
                playlistByName[name] = id; names.append(name)
            }
            payload.tags.forEach(addTag)
            payload.entries.flatMap { $0.tags ?? [] }.forEach(addTag)
            payload.silTags.forEach(addTag)
            payload.silEntries.flatMap { $0.tags ?? [] }.forEach(addTag)
            collections.playlists = names.enumerated().map {
                .init(id: playlistByName[$0.element]!, name: $0.element, createdAt: date, sidebarRank: state.playlists.count + $0.offset)
            }
            collections.legacyOrigins = names.map {
                .init(playlistID: playlistByName[$0]!, sourceKey: "personal-settings-v1-v5", tag: $0)
            }
            var memberSets: [UUID: Set<WallpaperReference>] = [:]
            var favoriteOrder: [WallpaperReference] = [], favorites: [WallpaperReference: Bool] = [:]
            for (provider, entries) in [(WallpaperProvider.videoLibrary, payload.entries), (.staticImageLibrary, payload.silEntries)] {
                for entry in entries {
                    let source = PersonalSettingsLocalSource(reference: .init(provider: provider, sourceID: UUID().uuidString),
                                                            path: entry.path, title: entry.title ?? "")
                    let reference = try merge(source)
                    for raw in entry.tags ?? [] {
                        guard let id = playlistByName[normalizedTag(raw)],
                              memberSets[id, default: []].insert(reference).inserted else { continue }
                        collections.members.append(.init(playlistID: id, reference: reference,
                            position: memberSets[id]!.count - 1, addedAt: date))
                    }
                    if provider == .videoLibrary, let favorite = entry.isFavorite {
                        if favorites[reference] == nil { favoriteOrder.append(reference) }
                        favorites[reference] = favorite
                    }
                }
            }
            collections.favoriteStates = favoriteOrder.map { .init(reference: $0, isFavorite: favorites[$0]!) }
        }
        var locatedReferences = Set(collections.locators.map(\.reference))
        for reference in patchOrder {
            guard let target = patches[reference]?.target else { continue }
            if locatedReferences.insert(reference).inserted {
                collections.locators.append(.init(reference: reference, locator: .init(path: target.path, titleHint: target.title,
                    mediaKind: reference.provider == .videoLibrary ? .video : .image, provenance: "personal-settings")))
            }
        }
        try validate(collections, state: state)
        return .init(commandID: commandID, resetEpoch: state.resetEpoch, expectedOrganization: state.organizationState,
                     sourcePatches: patchOrder.compactMap { patches[$0] }, beforePreferences: beforePreferences,
                     targetPreferences: targetPreferences, collections: collections,
                     summary: .init(mergedWallpaperCount: merged, createdWallpaperCount: created,
                                    missingPathCount: missingPathCount, tagCount: collections.playlists.count))
    }

    static func paths(in payload: PersonalSettingsPayload, sources: [PersonalSettingsLocalSource]) -> [String] {
        sources.map(\.path) + payload.sources.map(\.path) + payload.entries.map(\.path)
            + payload.silEntries.map(\.path) + (payload.collections?.locators.compactMap { $0.locator.path } ?? [])
    }

    private static func normalizedTag(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private static func validate(_ source: PersonalSettingsLocalSource) throws {
        guard [.videoLibrary, .staticImageLibrary].contains(source.reference.provider),
              !source.reference.sourceID.isEmpty, !source.path.isEmpty else {
            throw PersonalSettingsError.invalidPayload("本地来源引用")
        }
    }

    private static func validate(_ payload: LibraryCollectionsPersonalSettingsImport, state: UserCollectionsSnapshot) throws {
        let covers = try checkedCoverAssets(payload.coverAssets)
        var ids = Set<UUID>()
        for playlist in payload.playlists {
            guard ids.insert(playlist.id).inserted, !normalizedTag(playlist.name).isEmpty, playlist.sidebarRank >= 0,
                  playlist.createdAt.timeIntervalSince1970.isFinite, playlist.modifiedAt.timeIntervalSince1970.isFinite else {
                throw PersonalSettingsError.invalidPayload("播放列表")
            }
            if payload.playlistMetadataIsExplicit, let id = playlist.customCoverAssetID, covers[id] == nil {
                throw PersonalSettingsError.invalidPayload("列表封面副本缺失")
            }
        }
        for member in payload.members {
            guard ids.contains(member.playlistID), !member.reference.sourceID.isEmpty, member.position >= 0,
                  member.addedAt.timeIntervalSince1970.isFinite else { throw PersonalSettingsError.invalidPayload("列表成员") }
        }
        let previous = try aliasMap(state.aliases)
        var aliases = Dictionary(uniqueKeysWithValues: state.aliases.map { ($0.alias, $0) })
        var incoming = Set<WallpaperReference>()
        for alias in payload.aliases {
            guard incoming.insert(alias.alias).inserted else { throw PersonalSettingsError.invalidPayload("重复身份声明") }
            let existing = previous[alias.alias] ?? alias.alias
            let target = previous[alias.canonical] ?? alias.canonical
            guard existing == alias.alias || existing == target else { throw PersonalSettingsError.invalidPayload("身份声明冲突") }
            if let prior = aliases[alias.alias] {
                guard (previous[prior.canonical] ?? prior.canonical) == target else { throw PersonalSettingsError.invalidPayload("身份声明冲突") }
            } else { aliases[alias.alias] = alias }
        }
        let canonical = try aliasMap(Array(aliases.values))
        for alias in state.aliases {
            guard canonical[alias.alias] == previous[alias.alias] else { throw PersonalSettingsError.invalidPayload("身份声明重定向") }
        }
        var states: [WallpaperReference: Bool] = [:]
        for favorite in payload.favoriteStates {
            guard !favorite.reference.sourceID.isEmpty,
                  favorite.favoritedAt?.timeIntervalSince1970.isFinite != false else { throw PersonalSettingsError.invalidPayload("特别喜爱") }
            let reference = canonical[favorite.reference] ?? favorite.reference
            if let previous = states[reference], previous != favorite.isFavorite { throw PersonalSettingsError.invalidPayload("喜爱状态冲突") }
            states[reference] = favorite.isFavorite
        }
        guard payload.locators.allSatisfy({ !$0.reference.sourceID.isEmpty }) else { throw PersonalSettingsError.invalidPayload("来源提示") }
        var exclusions: [WallpaperReference: Bool] = [:]
        for item in payload.libraryExclusionStates ?? [] {
            guard !item.reference.sourceID.isEmpty else { throw PersonalSettingsError.invalidPayload("库隐藏引用") }
            let reference = canonical[item.reference] ?? item.reference
            if let previous = exclusions.updateValue(item.isExcluded, forKey: reference), previous != item.isExcluded {
                throw PersonalSettingsError.invalidPayload("库隐藏状态冲突")
            }
        }
    }

    private static func checkedCoverAssets(_ assets: [WallpaperPlaylistCoverAsset]) throws -> [UUID: WallpaperPlaylistCoverAsset] {
        var result: [UUID: WallpaperPlaylistCoverAsset] = [:]
        for asset in assets {
            guard asset.isValidControlledCopy else { throw PersonalSettingsError.invalidPayload("列表封面副本") }
            if let previous = result.updateValue(asset, forKey: asset.id), previous != asset {
                throw PersonalSettingsError.invalidPayload("列表封面副本 ID 冲突")
            }
        }
        return result
    }

    private static func aliasMap(_ aliases: [WallpaperReferenceAlias]) throws -> [WallpaperReference: WallpaperReference] {
        var edges: [WallpaperReference: WallpaperReference] = [:]
        for alias in aliases {
            guard !alias.alias.sourceID.isEmpty, !alias.canonical.sourceID.isEmpty,
                  alias.alias != alias.canonical else { throw PersonalSettingsError.invalidPayload("身份声明") }
            if let previous = edges[alias.alias], previous != alias.canonical { throw PersonalSettingsError.invalidPayload("身份声明冲突") }
            edges[alias.alias] = alias.canonical
        }
        var resolved: [WallpaperReference: WallpaperReference] = [:]
        for source in edges.keys {
            var cursor = source, seen = Set<WallpaperReference>()
            while let next = edges[cursor] {
                guard seen.insert(cursor).inserted else { throw PersonalSettingsError.invalidPayload("身份声明环") }
                cursor = next
            }
            resolved[source] = cursor
        }
        return resolved
    }
}
