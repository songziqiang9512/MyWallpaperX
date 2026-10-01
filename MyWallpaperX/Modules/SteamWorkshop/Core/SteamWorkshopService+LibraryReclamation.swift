import Foundation

extension SteamWorkshopService {
    func libraryVersionLifetime(for record: SteamWorkshopDownloadRecord) throws -> PlaybackResourceLifetime? {
        guard !removingDownloadIDs.contains(record.id) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "此壁纸正在删除，无法开始播放。")
        }
        // Lease the concrete model paths rather than re-reading the latest ready
        // pointer. A card may still carry the previous version while an update is
        // publishing, and dependency-backed Web consumes both version trees.
        let consumedRoots = [record.folderURL, record.dependencyHostFolderURL].compactMap { $0 }
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
                    NSLog("MWX Steam library: reclaimed %d inactive version(s)", result.removedStorageIdentities.count)
                }
            } catch is CancellationError {
            } catch {
                NSLog("MWX Steam library: version reclamation deferred: %@", error.localizedDescription)
            }
            // 索引 GC：元数据索引只增不减（墓碑与孤儿 legacy 条目永久累
            // 积），与版本回收同节奏清理内容已不存在的超龄条目；v1 兼容
            // 根同步退役（内容与超龄杂项清空后撤掉空目录）。删除阶段回
            // 到主 actor 无悬挂点执行：全部发布路径（publishCanonical/
            // publish/恢复/元数据更新）都在主 actor 同步 rename，与删除
            // 天然串行；事务层身份复核再挡住 actor 序列化之外的替换。
            if let self {
                let candidates = await Task.detached(priority: .utility) {
                    Self.scanOrphanedMetadataEntries(libraryRoot: library, minimumAge: 24 * 60 * 60)
                }.value
                var reclaimed = self.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
                reclaimed += await Task.detached(priority: .utility) {
                    Self.retireLegacyVersionsRoot(libraryRoot: library, minimumAge: 24 * 60 * 60)
                }.value
                if reclaimed > 0 {
                    NSLog("MWX Steam library: reclaimed %d orphaned metadata entr(ies)", reclaimed)
                }
            }
            self?.libraryVersionReclamationTask = nil
        }
    }

    /// v1 兼容根（只读遗留）退役：UUID 内容目录由 reclaimVersions 的常规
    /// 路径处理，这里只清掉应用私有根内的超龄杂项文件（Finder 残留），
    /// 根完全清空后整体撤掉。所有读点容忍目录缺席；非空（仍有未到期内
    /// 容或杂项）时不做任何删除。
    nonisolated static func retireLegacyVersionsRoot(libraryRoot: URL, minimumAge: TimeInterval) -> Int {
        guard let configured = try? SteamWorkshopLibraryTransaction.configuredRoot(libraryRoot) else { return 0 }
        let versions = configured.appendingPathComponent(
            SteamWorkshopLibraryTransaction.versionsName, isDirectory: true
        )
        let children = (try? FileManager.default.contentsOfDirectory(
            at: versions, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: []
        )) ?? []
        guard !children.isEmpty else { return 0 }
        let cutoff = Date().timeIntervalSince1970 - minimumAge
        var removed = 0
        for url in children where !(url.lastPathComponent.utf8.count == 36
            && UUID(uuidString: url.lastPathComponent) != nil) {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if values?.isRegularFile == true,
               (values?.contentModificationDate?.timeIntervalSince1970 ?? 0) < cutoff,
               (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        // 只有确认已完全清空才移除目录本身：removeItem 对非空目录是递归
        // 删除，绝不能在还有内容时调用。
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: versions)
        }
        return removed
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
            + wallpaperManager.recentlyUsedWallpapers.map(\.path)
            + [wallpaperManager.currentWallpaper?.path].compactMap { $0 }
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
