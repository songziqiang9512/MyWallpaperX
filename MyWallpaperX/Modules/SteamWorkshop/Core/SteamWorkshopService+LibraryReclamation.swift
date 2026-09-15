import Foundation

extension SteamWorkshopService {
    func libraryVersionLifetime(for record: SteamWorkshopDownloadRecord) throws -> PlaybackResourceLifetime? {
        // Lease the concrete model paths rather than re-reading the latest ready
        // pointer. A card may still carry the previous version while an update is
        // publishing, and dependency-backed Web consumes both version trees.
        let consumedRoots = [record.folderURL, record.dependencyHostFolderURL].compactMap { $0 }
        let directoryNames = Set(consumedRoots.compactMap {
            SteamWorkshopLibraryTransaction.versionDirectoryName(
                containing: $0,
                libraryRoot: steamDownloadLibraryRootURL
            )
        })
        guard !directoryNames.isEmpty else {
            return nil
        }
        guard let lease = steamLibraryVersionLeaseRegistry.acquire(directoryNames: directoryNames) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "此版本已开始回收，请刷新列表后选择当前版本。")
        }
        return lease
    }

    func scheduleLibraryVersionReclamation() {
        guard libraryVersionReclamationTask == nil else { return }
        let library = steamDownloadLibraryRootURL
        let snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]
        do {
            snapshots = try loadManagedDownloadSnapshots(requireComplete: true)
        } catch {
            NSLog("MWX Steam library: incomplete index; reclamation deferred: %@", error.localizedDescription)
            return
        }
        let leases = steamLibraryVersionLeaseRegistry
        var retained = Set(snapshots.values.compactMap { snapshot -> String? in
            guard let commit = snapshot.commit, !commit.removed else { return nil }
            return commit.directoryName.lowercased()
        })
        retained.formUnion(downloadJobStore.jobs.compactMap {
            $0.preparedCommit?.directoryName.lowercased()
        })
        retained.formUnion(steamLibraryVersionLeaseRegistry.protectedDirectoryNames())

        let wallpaperManager = WallpaperManager.shared
        let referencedVideoPaths = wallpaperManager.wallpapers.map(\.path)
            + wallpaperManager.recentlyUsedWallpapers.map(\.path)
            + [wallpaperManager.currentWallpaper?.path].compactMap { $0 }
        for path in referencedVideoPaths {
            if let name = SteamWorkshopLibraryTransaction.versionDirectoryName(
                containing: URL(fileURLWithPath: path),
                libraryRoot: library
            ) {
                retained.insert(name)
            }
        }
        if let currentPath = WallpaperEngine.shared.currentContentPath,
           let name = SteamWorkshopLibraryTransaction.versionDirectoryName(
            containing: URL(fileURLWithPath: currentPath),
            libraryRoot: library
           ) {
            retained.insert(name)
        }
        for request in [SceneDaemonClient.shared.activeIntent, SceneDaemonClient.shared.pendingIntent].compactMap({ $0 }) {
            if let name = SteamWorkshopLibraryTransaction.versionDirectoryName(
                containing: request.rootURL,
                libraryRoot: library
            ) {
                retained.insert(name)
            }
        }

        libraryVersionReclamationTask = Task { [weak self] in
            let work = Task.detached(priority: .utility) {
                try await SteamWorkshopLibraryTransaction.reclaimVersions(
                    libraryRoot: library,
                    retaining: retained,
                    minimumAge: 24 * 60 * 60,
                    admitRemoval: { await leases.beginReclamation($0) },
                    removalFailed: { await leases.reclamationFailed($0) }
                )
            }
            do {
                let result = try await work.value
                if !result.removedDirectoryNames.isEmpty {
                    NSLog("MWX Steam library: reclaimed %d inactive version(s)", result.removedDirectoryNames.count)
                }
            } catch is CancellationError {
            } catch {
                NSLog("MWX Steam library: version reclamation deferred: %@", error.localizedDescription)
            }
            self?.libraryVersionReclamationTask = nil
        }
    }
}
