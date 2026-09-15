import Foundation

extension SteamWorkshopService {
    func libraryVersionLifetime(for record: SteamWorkshopDownloadRecord) -> PlaybackResourceLifetime? {
        guard let commit = managedDownloadSnapshots()[record.id]?.commit,
              !commit.removed,
              let content = try? SteamWorkshopLibraryTransaction.contentURL(
                for: commit,
                libraryRoot: steamDownloadLibraryRootURL
              ),
              content.resolvingSymlinksInPath().standardizedFileURL
                == record.folderURL.resolvingSymlinksInPath().standardizedFileURL else {
            return nil
        }
        return steamLibraryVersionLeaseRegistry.acquire(commit)
    }

    func scheduleLibraryVersionReclamation() {
        guard libraryVersionReclamationTask == nil else { return }
        let library = steamDownloadLibraryRootURL
        let snapshots = managedDownloadSnapshots()
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
                try SteamWorkshopLibraryTransaction.reclaimVersions(
                    libraryRoot: library,
                    retaining: retained,
                    minimumAge: 24 * 60 * 60
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
