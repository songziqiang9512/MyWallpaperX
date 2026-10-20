import AppKit
import Foundation

/// Recovery for an index whose complete SQLite baseline has not been read yet.
/// Batches coalesce derived updates by path; user-wide operations retain order.
nonisolated struct WallpaperIndexStartupChanges: Codable {
    enum Field: String, Codable, Hashable {
        case title, favorite, lastUsed, thumbnail, staticFrame, fileSize, duration, resolution
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

    @MainActor func isValid(normalize: (String) -> String) -> Bool {
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

    @MainActor func contains(_ path: String) -> Bool {
        steps.contains { if case .changes(let batch) = $0 { return batch.changes[path] != nil }; return false }
    }

    @MainActor var removedPaths: Set<String> {
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

    @MainActor mutating func record(path: String, old: VideoWallpaper?, new: VideoWallpaper?,
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

    @MainActor func merged(with baseline: [VideoWallpaper], materializePatches: Bool = false,
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
                        resolution: change.fields.contains(.resolution) ? incoming.resolution ?? existing.resolution : existing.resolution
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

extension WallpaperManager {
    var initialIndexChangesKey: String { "WallpaperIndexStartupChangesV1" }
    var unreadableInitialIndexChangesKey: String { "WallpaperIndexStartupChangesUnreadable" }

    func beginInitialIndexLoad() {
        initialIndexLoadGeneration &+= 1
        initialIndexLoadInFlight = false
        initialIndexBootstrapInProgress = true
        initialIndexSeedWallpapers = []
        initialIndexChanges = WallpaperIndexStartupChanges()
        if let data = defaults.data(forKey: initialIndexChangesKey) {
            do {
                let decoded = try JSONDecoder().decode(WallpaperIndexStartupChanges.self, from: data)
                guard decoded.isValid(normalize: normalizedPath) else { throw CocoaError(.coderReadCorrupt) }
                initialIndexChanges = decoded
                initialIndexSeedWallpapers = decoded.seeds
            } catch {
                // Keep one exact, bounded recovery copy; never reinterpret it as
                // an empty complete library or overwrite the existing SQLite DB.
                defaults.set(data, forKey: unreadableInitialIndexChangesKey)
                defaults.removeObject(forKey: initialIndexChangesKey)
                reportUnreadableInitialIndexChanges()
            }
        }
    }

    func finishInitialIndexBootstrap() {
        guard initialIndexBootstrapInProgress else { return }
        initialIndexBootstrapInProgress = false
        guard !didFinishInitialIndexLoad else { saveWallpapers(); return }
        initialIndexChanges.seeds = initialIndexSeedWallpapers
        let removed = initialIndexChanges.removedPaths
        if !removed.isEmpty {
            initialIndexInternalPublication = true
            wallpapers.removeAll { removed.contains(normalizedPath($0.path)) }
            recentlyUsedWallpapers.removeAll { removed.contains(normalizedPath($0.path)) }
            if let current = currentWallpaper, removed.contains(normalizedPath(current.path)) { currentWallpaper = nil }
            if let pending = pendingWallpaper, removed.contains(normalizedPath(pending.path)) { pendingWallpaper = nil }
            initialIndexInternalPublication = false
        }
        let seedPaths = Set(initialIndexSeedWallpapers.map { normalizedPath($0.path) })
        for wallpaper in wallpapers {
            let path = normalizedPath(wallpaper.path)
            if !seedPaths.contains(path), !initialIndexChanges.contains(path) {
                initialIndexChanges.record(path: path, old: nil, new: wallpaper)
            }
        }
        persistInitialIndexChanges()
    }

    func recordInitialIndexUserSelection(_ wallpaper: VideoWallpaper) {
        guard !didFinishInitialIndexLoad else { return }
        initialIndexChanges.record(path: normalizedPath(wallpaper.path), old: nil, new: wallpaper)
    }

    func recordInitialIndexChanges(from old: [VideoWallpaper], to new: [VideoWallpaper]) {
        guard !didFinishInitialIndexLoad, !initialIndexBootstrapInProgress,
              !initialIndexInternalPublication, initialIndexGlobalMutationDepth == 0 else { return }
        let oldByPath = firstWallpapersByPath(old), newByPath = firstWallpapersByPath(new)
        for wallpaper in old {
            let path = normalizedPath(wallpaper.path)
            if newByPath[path] == nil { initialIndexChanges.record(path: path, old: wallpaper, new: nil) }
        }
        for wallpaper in new {
            let path = normalizedPath(wallpaper.path)
            if oldByPath[path] != wallpaper {
                initialIndexChanges.record(path: path, old: oldByPath[path], new: wallpaper)
            }
        }
    }

    private func firstWallpapersByPath(_ source: [VideoWallpaper]) -> [String: VideoWallpaper] {
        source.reduce(into: [:]) { values, wallpaper in
            let path = normalizedPath(wallpaper.path)
            if values[path] == nil { values[path] = wallpaper }
        }
    }

    func recordInitialIndexExplicitEdit(_ wallpaper: VideoWallpaper,
                                       fields: Set<WallpaperIndexStartupChanges.Field>, addedTags: [String] = []) {
        guard !didFinishInitialIndexLoad else { return }
        let tags = addedTags.reduce(into: [String: Bool]()) { $0[$1] = true }
        initialIndexChanges.record(path: normalizedPath(wallpaper.path), old: wallpaper, new: wallpaper,
                                   fields: fields, tags: tags)
    }

    func withInitialIndexGlobalMutation(_ step: WallpaperIndexStartupChanges.Step, _ body: () -> Void) {
        guard !didFinishInitialIndexLoad else { body(); return }
        initialIndexGlobalMutationDepth += 1
        body()
        initialIndexGlobalMutationDepth -= 1
        initialIndexChanges.steps.append(step)
        persistInitialIndexChanges()
    }

    func persistInitialIndexChanges() {
        guard !initialIndexChanges.isEmpty else { return }
        saveCodableValue(initialIndexChanges, forKey: initialIndexChangesKey)
    }

    func retryInitialIndexLoadIfNeeded() {
        guard !didFinishInitialIndexLoad, !initialIndexLoadInFlight else { return }
        initialIndexLoadInFlight = true
        initialIndexLoadGeneration &+= 1
        let generation = initialIndexLoadGeneration, epoch = wallpaperIndexSaveEpoch
        WallpaperIndexStore.shared.loadInitialIndexAsync { [weak self] result in
            guard let self, self.wallpaperIndexSaveEpoch == epoch,
                  self.initialIndexLoadGeneration == generation else { return }
            self.initialIndexLoadInFlight = false
            switch result {
            case .success(let index):
                self.settleInitialIndex(index)
                self.saveWallpapers()
            case .failure:
                self.persistInitialIndexChanges()
            }
        }
    }

    @discardableResult
    func settleInitialIndexForFlush() -> Bool {
        guard !didFinishInitialIndexLoad else { return true }
        initialIndexLoadGeneration &+= 1
        initialIndexLoadInFlight = false
        do {
            settleInitialIndex(try WallpaperIndexStore.shared.loadInitialIndex())
            return true
        } catch {
            persistInitialIndexChanges()
            return false
        }
    }

    func settleInitialIndex(_ index: WallpaperIndexStore.LoadedIndex) {
        initialIndexLoadGeneration &+= 1
        initialIndexLoadInFlight = false
        initialIndexInternalPublication = true
        defer { initialIndexInternalPublication = false }
        let oldByPath = firstWallpapersByPath(wallpapers)
        let selectedID = selectedWallpaperId, inspectedID = inspectedWallpaperID
        let selectedIDs = selectedWallpaperIds
        let baseline = index.initialized ? migratedBundledVideoIndex(index.wallpapers) : initialIndexSeedWallpapers
        let merged = initialIndexChanges.merged(with: baseline, normalize: normalizedPath)
        let removed = initialIndexChanges.removedPaths
        didFinishInitialIndexLoad = true
        wallpapers = merged
        let byPath = firstWallpapersByPath(merged)
        if let current = currentWallpaper, let canonical = byPath[normalizedPath(current.path)] { currentWallpaper = canonical }
        else if let current = currentWallpaper, removed.contains(normalizedPath(current.path)) { currentWallpaper = nil }
        if let pending = pendingWallpaper, let canonical = byPath[normalizedPath(pending.path)] { pendingWallpaper = canonical }
        else if let pending = pendingWallpaper, removed.contains(normalizedPath(pending.path)) { pendingWallpaper = nil }
        for id in Array(switchSelections.keys) {
            if case .video(let wallpaper) = switchSelections[id],
               let canonical = byPath[normalizedPath(wallpaper.path)] {
                switchSelections[id] = .video(canonical)
            }
        }
        let pathsByOldID = oldByPath.reduce(into: [String: String]()) { $0[$1.value.id] = $1.key }
        if let selected = selectedID, let path = pathsByOldID[selected] { selectedWallpaperId = byPath[path]?.id }
        if let inspected = inspectedID, let path = pathsByOldID[inspected] { inspectedWallpaperID = byPath[path]?.id }
        selectedWallpaperIds = Set(selectedIDs.compactMap { id in
            pathsByOldID[id].flatMap { byPath[$0]?.id } ?? (merged.contains { $0.id == id } ? id : nil)
        })
        if let current = currentWallpaper, let index = merged.firstIndex(where: { $0.id == current.id }) { currentIndex = index }
        normalizeRecentWallpapers(requireExistingFiles: true)
        saveRecentWallpapers()
        initialIndexSeedWallpapers = []
        scanForMissingMetadata()
        scheduleInitialIndexFileSizes(merged)
        scheduleMissingIndexedSourceFilesScan()
        refreshAutoSwitchTimerIfNeeded()
    }

    private func scheduleInitialIndexFileSizes(_ snapshot: [VideoWallpaper]) {
        let missing = snapshot.filter { $0.fileSize == nil }.map { (id: $0.id, path: $0.path) }
        guard !missing.isEmpty else { return }
        let epoch = wallpaperIndexSaveEpoch
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let updates = missing.compactMap { item -> (id: String, path: String, size: Int64)? in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: item.path),
                      let size = attributes[.size] as? Int64 else { return nil }
                return (item.id, item.path, size)
            }
            guard !updates.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wallpaperIndexSaveEpoch == epoch else { return }
                for update in updates {
                    if let index = self.wallpapers.firstIndex(where: { $0.id == update.id && $0.path == update.path }),
                       self.wallpapers[index].fileSize == nil {
                        self.wallpapers[index].fileSize = update.size
                    }
                }
            }
        }
    }

    func clearInitialIndexRecoveryAfterSave() {
        defaults.removeObject(forKey: initialIndexChangesKey)
        initialIndexChanges = WallpaperIndexStartupChanges()
    }

    func invalidateInitialIndexLoad() {
        initialIndexLoadGeneration &+= 1
        initialIndexLoadInFlight = false
        initialIndexBootstrapInProgress = false
        initialIndexSeedWallpapers = []
        clearInitialIndexRecoveryAfterSave()
        defaults.removeObject(forKey: unreadableInitialIndexChangesKey)
    }

    func reportUnreadableInitialIndexChanges() {
        DispatchQueue.main.async {
            let alert = makeAppAlert(title: "部分视频库变更无法恢复",
                                     message: "启动恢复记录已损坏或来自不支持的版本。原始记录已保留，现有视频库不会被清空；这些记录中的变更可能需要重新操作。",
                                     style: .warning, buttons: ["知道了"])
            presentAppAlert(alert, in: nil)
        }
    }
}
