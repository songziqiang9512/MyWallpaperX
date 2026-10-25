import CoreFoundation
import Foundation

/// A one-time value adapter over the already frozen migration input. It never
/// reads live defaults, source services, media or mutable playlist membership.
nonisolated enum WallpaperLibraryViewPreferencesMigration {
    struct Result: Sendable {
        var queries: [WallpaperLibraryPage: WallpaperLibraryQueryState] = [:]
        var warnings: [String] = []
    }
    private struct LegacySort: Decodable {
        let mode: String
        let ascending: Bool
    }

    static func map(_ seed: LibraryCollectionsViewPreferencesSeed, relationships: UserCollectionsSnapshot? = nil) -> Result {
        var result = Result()
        var canonical: [WallpaperReference: WallpaperReference] = [:]
        var memberScopes: [WallpaperLibraryPage: Set<WallpaperReference>] = [:]
        if let relationships {
            // One transient batch resolution; keeping a full library rank in
            // every playlist would multiply the saved preference size by P×N.
            let references = Set(seed.preferences.videoTimeOrder + seed.preferences.imageTimeOrder
                + relationships.members.map(\.reference) + relationships.favorites.map(\.reference))
            do {
                canonical = try WallpaperLibraryQuery.canonicalReferences(references, relationships: relationships)
                memberScopes[.favorites] = Set(relationships.favorites.map { canonical[$0.reference] ?? $0.reference })
                for mapping in seed.manifest.tagMappings { memberScopes[.playlist(mapping.playlistID)] = [] }
                for member in relationships.members {
                    memberScopes[.playlist(member.playlistID), default: []].insert(canonical[member.reference] ?? member.reference)
                }
            } catch {
                // Keep the frozen preference intact when its optional scope
                // cannot be interpreted; the relationship reader reports its
                // own invalid snapshot rather than guessing a member order.
                result.warnings.append("旧界面偏好成员范围无法恢复")
            }
        }
        let values: [String: Any]
        do {
            if let data = seed.preferences.auxiliaryPreferences {
                guard let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                    result.warnings.append("旧界面偏好类型无效")
                    return result
                }
                values = decoded
            } else { values = [:] }
        } catch {
            result.warnings.append("旧界面偏好无法读取")
            return result
        }
        func json(_ key: String) -> [String: Any]? {
            guard let raw = values[key] else { return nil }
            guard let data = raw as? Data,
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result.warnings.append(key)
                return nil
            }
            return value
        }
        func boolean(_ raw: Any?) -> Bool? {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        let videoModes: Set<String> = ["none", "name", "size", "dateAdded"]
        let imageModes: Set<String> = ["none", "name", "fileSize", "addedAt", "lastUsed"]
        func sort(_ object: [String: Any]?, modeKey: String = "mode", ascendingKey: String = "ascending",
                  allowedModes: Set<String>, missingMode: String? = nil, missingAscending: Bool? = nil, key: String) -> LegacySort? {
            guard let object else { return nil }
            let rawMode = object[modeKey], rawAscending = object[ascendingKey]
            let mode = rawMode == nil || rawMode is NSNull ? missingMode : rawMode as? String
            let ascending = rawAscending == nil || rawAscending is NSNull ? missingAscending : boolean(rawAscending)
            guard let mode, allowedModes.contains(mode), let ascending else {
                result.warnings.append(key)
                return nil
            }
            return LegacySort(mode: mode, ascending: ascending)
        }
        let globalObject = json("WallpaperSettings")
        // WallpaperSettings' original per-field decoder defaults absent/null
        // sort keys. SortState/SILSortState used synthesized strict decoders.
        let global = sort(globalObject, modeKey: "sortMode", ascendingKey: "sortAscending", allowedModes: videoModes,
                          missingMode: "none", missingAscending: true, key: "WallpaperSettings")
        let perSelection = json("PerSelectionSortStates") ?? [:]
        let imageSort = sort(json("SILSortState"), allowedModes: imageModes, key: "SILSortState")
        func videoSort(_ key: String) -> LegacySort? {
            guard let raw = perSelection[key] else { return global }
            guard let object = raw as? [String: Any] else {
                result.warnings.append("PerSelectionSortStates." + key)
                return global
            }
            return sort(object, allowedModes: videoModes, key: "PerSelectionSortStates." + key) ?? global
        }
        func query(_ old: LegacySort?, provider: WallpaperProvider, page: WallpaperLibraryPage) -> WallpaperLibraryQueryState {
            // Old offsets required an unsaved viewport width and used a
            // different layout rule. Preserve their raw backup, not an invented
            // column count; every newly migrated page starts at five columns.
            var value = WallpaperLibraryQueryState()
            guard let old else { return value }
            value.ascending = old.ascending
            switch old.mode {
            case "none": value.sort = .sourceOrder
            case "name": value.sort = .name
            case "size", "fileSize": value.sort = .fileSize
            case "addedAt" where provider == .staticImageLibrary: value.sort = .createdAt
            case "dateAdded" where provider == .videoLibrary,
                 "lastUsed" where provider == .staticImageLibrary:
                value.sort = .legacyTime
                let rank = provider == .videoLibrary ? seed.preferences.videoTimeOrder : seed.preferences.imageTimeOrder
                // Retain the original raw identity for a later alias change;
                // membership is tested through today's canonical relation only.
                value.legacyTimeOrder = memberScopes[page].map { scope in
                    rank.filter { scope.contains(canonical[$0] ?? $0) }
                } ?? rank
            default: result.warnings.append("排序：" + old.mode)
            }
            return value
        }
        result.queries[.videos] = query(videoSort("category.myWallpapers"), provider: .videoLibrary, page: .videos)
        result.queries[.favorites] = query(videoSort("category.favorites"), provider: .videoLibrary, page: .favorites)
        result.queries[.images] = query(imageSort, provider: .staticImageLibrary, page: .images)
        // Recent has a new explicit success-order contract; old raw preferences
        // remain in the backup, without silently reordering its history.
        result.queries[.recent] = .init()
        result.queries[.playlists] = .init()
        for mapping in seed.manifest.tagMappings {
            if let video = mapping.origins.first(where: { $0.provider == .videoLibrary }) {
                result.queries[.playlist(mapping.playlistID)] = query(videoSort("tag." + video.originalName), provider: .videoLibrary, page: .playlist(mapping.playlistID))
            } else if mapping.origins.contains(where: { $0.provider == .staticImageLibrary }) {
                result.queries[.playlist(mapping.playlistID)] = query(imageSort, provider: .staticImageLibrary, page: .playlist(mapping.playlistID))
            }
        }
        result.warnings = Array(Set(result.warnings)).sorted()
        return result
    }
}
