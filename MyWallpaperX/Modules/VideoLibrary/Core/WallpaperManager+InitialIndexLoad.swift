import AppKit
import Foundation

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
                if !preservesLegacyMigrationInputs {
                    defaults.set(data, forKey: unreadableInitialIndexChangesKey)
                    defaults.removeObject(forKey: initialIndexChangesKey)
                }
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


    func withInitialIndexGlobalMutation(_ step: WallpaperIndexStartupChanges.Step, _ body: () -> Void) {
        guard !didFinishInitialIndexLoad else { body(); return }
        initialIndexGlobalMutationDepth += 1
        body()
        initialIndexGlobalMutationDepth -= 1
        initialIndexChanges.steps.append(step)
        persistInitialIndexChanges()
    }

    func persistInitialIndexChanges() {
        guard !preservesLegacyMigrationInputs, !initialIndexChanges.isEmpty else { return }
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
        if let current = currentWallpaper, let index = merged.firstIndex(where: { $0.id == current.id }) { currentIndex = index }
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
        guard !preservesLegacyMigrationInputs else { return }
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
                                     message: "无法读取启动恢复记录。原始记录和视频库均已保留，未恢复的操作需重试。",
                                     style: .warning, buttons: ["知道了"])
            presentAppAlert(alert, in: nil)
        }
    }
}
