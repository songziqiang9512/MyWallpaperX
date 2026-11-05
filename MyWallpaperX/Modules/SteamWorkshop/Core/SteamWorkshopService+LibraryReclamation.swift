import Foundation

extension SteamWorkshopService {
    func libraryVersionLifetime(for record: SteamWorkshopDownloadRecord) throws -> PlaybackResourceLifetime? {
        try libraryVersionLifetime(recordID: record.id,
            consumedRoots: [record.folderURL, record.dependencyHostFolderURL].compactMap { $0 })
    }

    func libraryVersionLifetime(recordID: String, consumedRoots: [URL]) throws -> PlaybackResourceLifetime? {
        guard !removingDownloadIDs.contains(recordID) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "此壁纸正在删除，无法开始播放。")
        }
        let storageIdentities = Set(consumedRoots.compactMap {
            SteamWorkshopLibraryTransaction.storageIdentity(
                containing: $0,
                libraryRoot: steamDownloadLibraryRootURL
            )
        })
        guard !storageIdentities.isEmpty else {
            return nil
        }
        guard let lease = steamLibraryVersionLeaseRegistry.acquire(storageIdentities: storageIdentities) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "此版本已开始回收，请刷新列表后选择当前版本。")
        }
        return lease
    }

    /// Captured on the service actor with no suspension between the authoritative
    /// metadata/marker comparison and the original version-registry admission.
    /// The opaque lifetime never crosses into a worker or the wire DTO.
    struct SceneSourceAdmission {
        let source: ScenePlaybackSource
        let resourceLifetime: PlaybackResourceLifetime?
    }

    /// Captures the current managed pointer and obtains its lease in one
    /// unsuspended service-actor segment. No migration or content scan runs here.
    func sceneSourceAdmission(for record: SteamWorkshopDownloadRecord) throws -> SceneSourceAdmission {
        typealias Transaction = SteamWorkshopLibraryTransaction
        let rejected = Transaction.Failure(message: "Scene 来源版本已变化或正在删除，请刷新后重试。")
        guard !removingDownloadIDs.contains(record.id),
              record.dependencyItemID.map({ !removingDownloadIDs.contains($0) }) ?? true else { throw rejected }
        // Foundation may abbreviate /private/tmp to its /tmp symlink for an
        // existing URL. Keep the original FD owner's physical spelling.
        let root = try Transaction.configuredRoot(record.folderURL)
        let library = steamDownloadLibraryRootURL
        let snapshot: SteamWorkshopDownloadMetadataSnapshot?
        if FileManager.default.fileExists(atPath: library.path) {
            snapshot = try loadManagedDownloadSnapshots(requireComplete: true,
                matchingItemID: record.id, includeLegacy: true)[record.id]
        } else { snapshot = nil }
        if let commit = snapshot?.commit {
            let expectedRoot = try Transaction.contentURL(for: commit, libraryRoot: library)
            guard !commit.removed, commit.workshopId == record.id, commit.contentType == "scene",
                  let storageIdentity = Transaction.storageIdentity(for: commit),
                  expectedRoot.resolvingSymlinksInPath().standardizedFileURL.path ==
                    root.resolvingSymlinksInPath().standardizedFileURL.path,
                  snapshot?.legacyFolderURL?.standardizedFileURL == expectedRoot.standardizedFileURL else { throw rejected }
            let directory = try Transaction.absoluteDirectory(root)
            guard try Transaction.markerCommit(in: directory) == commit,
                  let generation = commit.generation else { throw rejected }
            let source = ScenePlaybackSource(rootURL: root, managed: .init(
                storageIdentity: storageIdentity, generation: generation.lowercased()))
            guard source.isValid else { throw rejected }
            guard let lifetime = steamLibraryVersionLeaseRegistry.acquire(storageIdentities: [storageIdentity]) else {
                throw Transaction.Failure(message: "Scene 来源版本已开始回收，请刷新后重试。")
            }
            return SceneSourceAdmission(source: source, resourceLifetime: lifetime)
        }
        // A missing/corrupt managed pointer or marker is not permission to turn a
        // previously managed generation into an unmanaged directory launch.
        guard snapshot?.legacyRemoved != true,
              Transaction.storageIdentity(containing: root, libraryRoot: library) == nil,
              !Transaction.isReservedManagedPublicDirectory(root, libraryRoot: library) else { throw rejected }
        let source = ScenePlaybackSource(rootURL: root)
        guard source.isValid else { throw rejected }
        return SceneSourceAdmission(source: source, resourceLifetime: nil)
    }

    func scheduleLibraryVersionReclamation() {
        guard libraryVersionReclamationTask == nil else { return }
        let library = steamDownloadLibraryRootURL
        let snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]
        do {
            // Publication still owns its generation when the player no longer admits that format.
            snapshots = try SteamWorkshopLibraryTransaction.publishedMetadata(libraryRoot: library,
                requireComplete: true).mapValues {
                    try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: $0)
                }
            for (itemID, snapshot) in snapshots {
                if let commit = snapshot.commit {
                    guard snapshot.item.id == itemID, commit.workshopId == itemID else {
                        throw SteamWorkshopLibraryTransaction.Failure(message: "下载索引身份无效，已暂停版本回收。")
                    }
                }
            }
        } catch {
#if DEBUG
            NSLog("MWX Steam library: incomplete index; reclamation deferred: %@", error.localizedDescription)
#endif
            return
        }
        let leases = steamLibraryVersionLeaseRegistry
        var retained = Set(snapshots.values.compactMap { snapshot -> String? in
            guard let commit = snapshot.commit, !commit.removed else { return nil }
            return SteamWorkshopLibraryTransaction.storageIdentity(for: commit)
        })
        retained.formUnion(downloadJobStore.jobs.compactMap {
            $0.preparedCommit.flatMap(SteamWorkshopLibraryTransaction.storageIdentity(for:))
        })
        retained.formUnion(referencedLibraryStorageIdentities())

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
                if !result.removedStorageIdentities.isEmpty {
#if DEBUG
                    NSLog("MWX Steam library: reclaimed %d inactive version(s)", result.removedStorageIdentities.count)
#endif
                }
            } catch is CancellationError {
            } catch {
#if DEBUG
                NSLog("MWX Steam library: version reclamation deferred: %@", error.localizedDescription)
#endif
            }
            // 索引 GC：元数据索引只增不减（墓碑与孤儿 legacy 条目永久累
            // 积），与版本回收同节奏清理内容已不存在的超龄条目。删除阶段回
            // 到主 actor 无悬挂点执行：全部发布路径（publishCanonical/
            // publish/恢复/元数据更新）都在主 actor 同步 rename，与删除
            // 天然串行；事务层身份复核再挡住 actor 序列化之外的替换。
            if let self {
                let candidates = await Task.detached(priority: .utility) {
                    Self.scanOrphanedMetadataEntries(libraryRoot: library, minimumAge: 24 * 60 * 60)
                }.value
                let reclaimed = self.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
                if reclaimed > 0 {
#if DEBUG
                    NSLog("MWX Steam library: reclaimed %d orphaned metadata entr(ies)", reclaimed)
#endif
                }
            }
            self?.libraryVersionReclamationTask = nil
        }
    }

    /// 索引孤儿候选：扫描阶段判定的全部身份——索引文件名、条目 itemID、
    /// 该目录项出生限定的文件系统身份（删除原语的复核凭据），以及让条
    /// 目成为孤儿的内容路径（删除前逐一再查）。
    struct OrphanedMetadataEntryCandidate: Sendable {
        let name: String
        let itemID: String
        let identity: SteamWorkshopStagingLeaseIdentity
        let contentURLs: [URL]
    }

    /// Index GC phase 1 (detached): decide orphan candidates only, never
    /// delete. Entries whose referenced content — commit directory, legacy
    /// folder or exported video — no longer exists and whose mtime passed the
    /// minimum age become candidates; the age guards entries racing a
    /// just-finished delete/recovery (the tombstone of a crash-interrupted
    /// removal keeps its directory check meaningful). Snapshot decode stays
    /// on the service side, like every other snapshot decode; the transaction
    /// layer's narrow harness subsets do not compile the snapshot model.
    nonisolated static func scanOrphanedMetadataEntries(
        libraryRoot: URL,
        minimumAge: TimeInterval
    ) -> [OrphanedMetadataEntryCandidate] {
        guard let entries = try? SteamWorkshopLibraryTransaction.scanPublishedMetadataEntries(
            libraryRoot: libraryRoot
        ) else { return [] }
        let cutoff = Date().timeIntervalSince1970 - minimumAge
        var candidates: [OrphanedMetadataEntryCandidate] = []
        for entry in entries where entry.modified < cutoff {
            guard let snapshot = try? JSONDecoder().decode(
                SteamWorkshopDownloadMetadataSnapshot.self, from: entry.data
            ) else { continue }
            var contentURLs: [URL] = []
            if let commit = snapshot.commit,
               let content = try? SteamWorkshopLibraryTransaction.contentURL(
                for: commit, libraryRoot: libraryRoot) {
                contentURLs.append(content)
            }
            if let legacy = snapshot.legacyFolderURL { contentURLs.append(legacy) }
            if let video = snapshot.exportedVideoURL { contentURLs.append(video) }
            guard contentURLs.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) else {
                continue
            }
            candidates.append(OrphanedMetadataEntryCandidate(
                name: entry.name,
                itemID: snapshot.item.id,
                identity: entry.identity,
                contentURLs: contentURLs
            ))
        }
        return candidates
    }

    /// Index GC phase 2 (main actor, no suspension points): every publish
    /// path runs its rename synchronously on the main actor, so a deletion
    /// pass on this actor cannot interleave with one. Each candidate is
    /// re-verified against state the detached scan could not see — items
    /// whose download/removal started after the scan are kept, content that
    /// reappeared is kept — and the unlink itself is the transaction layer's
    /// identity-checked primitive, so an entry replaced after the scan (new
    /// inode via renameat) survives even outside the actor serialization.
    func removeOrphanedMetadataEntries(
        _ candidates: [OrphanedMetadataEntryCandidate],
        libraryRoot: URL
    ) -> Int {
        let activeIDs = Set(downloadJobStore.jobs.map(\.workshopItemId))
            .union(removingDownloadIDs)
        var removed = 0
        for candidate in candidates where !activeIDs.contains(candidate.itemID) {
            guard candidate.contentURLs.allSatisfy({
                !FileManager.default.fileExists(atPath: $0.path)
            }) else { continue }
            if (try? SteamWorkshopLibraryTransaction.removeMetadataEntryIfUnchanged(
                name: candidate.name,
                expected: candidate.identity,
                libraryRoot: libraryRoot
            )) == true {
                removed += 1
            }
        }
        return removed
    }

    func referencedLibraryStorageIdentities() -> Set<String> {
        var retained = steamLibraryVersionLeaseRegistry.protectedStorageIdentities()
        let library = steamDownloadLibraryRootURL

        let wallpaperManager = WallpaperManager.shared
        let referencedVideoPaths = wallpaperManager.wallpapers.map(\.path)
            + [wallpaperManager.currentWallpaper?.path, wallpaperManager.pendingWallpaper?.path].compactMap { $0 }
        for path in referencedVideoPaths {
            if let identity = SteamWorkshopLibraryTransaction.storageIdentity(
                containing: URL(fileURLWithPath: path),
                libraryRoot: library
            ) {
                retained.insert(identity)
            }
        }
        if let currentPath = WallpaperEngine.shared.currentContentPath,
           let identity = SteamWorkshopLibraryTransaction.storageIdentity(
                containing: URL(fileURLWithPath: currentPath),
                libraryRoot: library
           ) {
            retained.insert(identity)
        }
        for request in [SceneDaemonClient.shared.activeIntent, SceneDaemonClient.shared.pendingIntent].compactMap({ $0 }) {
            if let identity = SteamWorkshopLibraryTransaction.storageIdentity(
                containing: request.rootURL,
                libraryRoot: library
            ) {
                retained.insert(identity)
            }
        }

        return retained
    }
}
