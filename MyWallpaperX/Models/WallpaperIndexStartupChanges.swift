import Foundation

/// Recovery for an index whose complete SQLite baseline has not been read yet.
/// Batches coalesce derived updates by path; user-wide operations retain order.
nonisolated struct WallpaperIndexStartupChanges: Codable {
    enum Field: String, Codable, Hashable {
        case title, favorite, lastUsed, thumbnail, staticFrame, fileSize, duration, resolution, firstIndexedAt
    }
    struct Change: Codable {
        var wallpaper: VideoWallpaper?
        var fields: Set<Field> = []
        var tags: [String: Bool] = [:]
        var insertsIfMissing = false
        var replacesExisting = false
    }
    struct Batch: Codable {
        var order: [String] = []
        var changes: [String: Change] = [:]
    }
    enum Step: Codable {
        case changes(Batch)
        case renameTag(String, String)
        case removeTag(String)
        case clearPreviews
    }
    var version = 1
    var seeds: [VideoWallpaper] = []
    var steps: [Step] = []
    var isEmpty: Bool { steps.isEmpty && seeds.isEmpty }

    func isValid(normalize: (String) -> String) -> Bool {
        guard version == 1 else { return false }
        for step in steps {
            if case .changes(let batch) = step {
                guard Set(batch.order).count == batch.order.count,
                      Set(batch.order) == Set(batch.changes.keys) else { return false }
                for (path, change) in batch.changes {
                    guard !path.isEmpty, normalize(path) == path else { return false }
                    if let wallpaper = change.wallpaper, normalize(wallpaper.path) != path { return false }
                }
            }
        }
        return true
    }

    func contains(_ path: String) -> Bool {
        steps.contains { if case .changes(let batch) = $0 { return batch.changes[path] != nil }; return false }
    }

    var removedPaths: Set<String> {
        var paths = Set<String>()
        for step in steps {
            if case .changes(let batch) = step {
                for (path, change) in batch.changes {
                    if change.wallpaper == nil { paths.insert(path) } else { paths.remove(path) }
                }
            }
        }
        return paths
    }

    mutating func record(path: String, old: VideoWallpaper?, new: VideoWallpaper?,
                         fields explicit: Set<Field> = [], tags explicitTags: [String: Bool] = [:]) {
        var batch = Batch()
        if let last = steps.last, case .changes(let existing) = last {
            batch = existing
            steps.removeLast()
        }
        let previous = batch.changes[path]
        if previous == nil { batch.order.append(path) }
        else if previous?.wallpaper == nil, new != nil {
            batch.order.removeAll { $0 == path }
            batch.order.append(path)
        }
        guard let new else {
            batch.changes[path] = Change(wallpaper: nil)
            steps.append(.changes(batch))
            return
        }
        var change = previous ?? Change(wallpaper: new)
        if change.wallpaper == nil { change = Change(wallpaper: new, replacesExisting: true) }
        change.wallpaper = new
        change.fields.formUnion(explicit)
        change.tags.merge(explicitTags) { _, latest in latest }
        if let old {
            if old.title != new.title { change.fields.insert(.title) }
            if old.isFavorite != new.isFavorite { change.fields.insert(.favorite) }
            if old.lastUsed != new.lastUsed { change.fields.insert(.lastUsed) }
            if old.firstIndexedAt != new.firstIndexedAt { change.fields.insert(.firstIndexedAt) }
            if old.thumbnailPath != new.thumbnailPath { change.fields.insert(.thumbnail) }
            if old.staticFramePath != new.staticFramePath { change.fields.insert(.staticFrame) }
            if old.fileSize != new.fileSize { change.fields.insert(.fileSize) }
            if old.duration != new.duration { change.fields.insert(.duration) }
            if old.resolution != new.resolution { change.fields.insert(.resolution) }
            for tag in old.tags where !new.tags.contains(tag) { change.tags[tag] = false }
            for tag in new.tags where !old.tags.contains(tag) { change.tags[tag] = true }
        }
        change.insertsIfMissing = change.insertsIfMissing || old == nil
            || !change.fields.isDisjoint(with: [.title, .favorite, .lastUsed]) || !change.tags.isEmpty
        batch.changes[path] = change
        steps.append(.changes(batch))
    }

    func merged(with baseline: [VideoWallpaper], materializePatches: Bool = false,
                normalize: (String) -> String) -> [VideoWallpaper] {
        var values: [String: VideoWallpaper] = [:]
        var order: [String] = []
        for wallpaper in baseline {
            let path = normalize(wallpaper.path)
            if values[path] == nil { values[path] = wallpaper; order.append(path) }
        }
        for step in steps {
            switch step {
            case .changes(let batch):
                for path in batch.order {
                    guard let change = batch.changes[path] else { continue }
                    guard let incoming = change.wallpaper else {
                        values.removeValue(forKey: path)
                        order.removeAll { $0 == path }
                        continue
                    }
                    guard let existing = values[path] else {
                        if change.insertsIfMissing || materializePatches {
                            values[path] = incoming
                            order.append(path)
                        }
                        continue
                    }
                    if change.replacesExisting {
                        values[path] = incoming
                        order.removeAll { $0 == path }
                        order.append(path)
                        continue
                    }
                    var tags = existing.tags.filter { change.tags[$0] != false }
                    for tag in incoming.tags where change.tags[tag] == true && !tags.contains(tag) { tags.append(tag) }
                    values[path] = VideoWallpaper(
                        id: existing.id, title: change.fields.contains(.title) ? incoming.title : existing.title,
                        path: existing.path,
                        thumbnailPath: change.fields.contains(.thumbnail) ? incoming.thumbnailPath ?? existing.thumbnailPath : existing.thumbnailPath,
                        staticFramePath: change.fields.contains(.staticFrame) ? incoming.staticFramePath ?? existing.staticFramePath : existing.staticFramePath,
                        isFavorite: change.fields.contains(.favorite) ? incoming.isFavorite : existing.isFavorite,
                        lastUsed: change.fields.contains(.lastUsed) ? incoming.lastUsed : existing.lastUsed,
                        tags: tags,
                        fileSize: change.fields.contains(.fileSize) ? incoming.fileSize ?? existing.fileSize : existing.fileSize,
                        duration: change.fields.contains(.duration) ? incoming.duration ?? existing.duration : existing.duration,
                        resolution: change.fields.contains(.resolution) ? incoming.resolution ?? existing.resolution : existing.resolution,
                        // An early import can discover a path before the SQL
                        // baseline. Its new admission clock must not turn an
                        // already indexed legacy record into a new import.
                        firstIndexedAt: existing.firstIndexedAt ?? (change.fields.contains(.firstIndexedAt) ? incoming.firstIndexedAt : nil)
                    )
                }
            case .renameTag(let old, let new):
                for path in order where values[path]?.tags.contains(old) == true {
                    values[path]?.tags.removeAll { $0 == old }
                    if values[path]?.tags.contains(new) == false { values[path]?.tags.append(new) }
                }
            case .removeTag(let tag):
                for path in order { values[path]?.tags.removeAll { $0 == tag } }
            case .clearPreviews:
                for path in order { values[path]?.thumbnailPath = nil; values[path]?.staticFramePath = nil }
            }
        }
        return order.compactMap { values[$0] }
    }
}
