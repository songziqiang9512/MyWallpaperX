import Foundation

/// Single-flight state for the installed-library scan. The generation counter
/// alone only discarded stale results; every overlapping reload still ran a
/// full detached scan (three root enumerations plus per-record stats/decodes).
/// Instances are keyed by `ObjectIdentifier` because the service's stored
/// properties belong to the primary declaration file; the registry is
/// main-actor confined together with every accessor below.
@MainActor private final class SteamWorkshopInstalledLibraryScanFlight {
    static var registry: [ObjectIdentifier: SteamWorkshopInstalledLibraryScanFlight] = [:]
    var isInFlight = false
    var rescanRequested = false
}

extension SteamWorkshopService {
    /// Rebuilds the installed-library index. The filesystem transaction and
    /// the stateful schedulers stay on the main actor; the expensive pure
    /// part (directory enumeration plus per-record construction — several
    /// file stats and JSON decodes per record) runs detached and publishes
    /// back through `applyInstalledLibraryRecords`. Only one scan is in
    /// flight at any time: reloads arriving mid-scan are coalesced into a
    /// single catch-up scan launched from the newest state once the current
    /// scan finishes, and only the newest generation is ever applied.
    func reloadInstalledItems() {
        do { try SteamWorkshopLibraryTransaction.recoverPublications(libraryRoot: steamDownloadLibraryRootURL,
            retaining: referencedLibraryStorageIdentities()) }
        catch { statusMessage = "入库恢复失败：\(error.localizedDescription)" }
        let managed = managedDownloadSnapshots()
        scheduleLegacyLibraryPublicationMigration(from: managed)
        reconcileDownloadCommits(managed)
        scheduleTerminalDownloadCleanup()
        installedLibraryScanGeneration += 1
        guard !installedLibraryScanFlight.isInFlight else {
            installedLibraryScanFlight.rescanRequested = true
            return
        }
        startInstalledLibraryScan(managed: managed)
    }

    /// Per-service single-flight holder (see `SteamWorkshopInstalledLibraryScanFlight`).
    private var installedLibraryScanFlight: SteamWorkshopInstalledLibraryScanFlight {
        let key = ObjectIdentifier(self)
        if let flight = SteamWorkshopInstalledLibraryScanFlight.registry[key] { return flight }
        let flight = SteamWorkshopInstalledLibraryScanFlight()
        SteamWorkshopInstalledLibraryScanFlight.registry[key] = flight
        return flight
    }

    private func startInstalledLibraryScan(managed: [String: SteamWorkshopDownloadMetadataSnapshot]) {
        installedLibraryScanFlight.isInFlight = true
        let generation = installedLibraryScanGeneration
        let context = installedLibraryScanContext()
        Task.detached(priority: .utility) { [weak self] in
            let records = SteamWorkshopService.scanInstalledLibraryRecords(
                managed: managed, context: context
            )
            await MainActor.run { [weak self] in
                self?.finishInstalledLibraryScan(generation: generation, records: records)
            }
        }
    }

    /// Scan completion back on the main actor. A stale generation is never
    /// applied; the flight slot is released unconditionally, and one merged
    /// catch-up scan — reading the index anew so it reflects every coalesced
    /// request — carries the current (newest) generation. No requested reload
    /// can be lost and no stale result can overwrite a newer projection.
    private func finishInstalledLibraryScan(generation: Int, records: [SteamWorkshopDownloadRecord]) {
        if installedLibraryScanGeneration == generation {
            applyInstalledLibraryRecords(records)
        }
        installedLibraryScanFlight.isInFlight = false
        guard installedLibraryScanFlight.rescanRequested else { return }
        installedLibraryScanFlight.rescanRequested = false
        startInstalledLibraryScan(managed: managedDownloadSnapshots())
    }

    private func applyInstalledLibraryRecords(_ records: [SteamWorkshopDownloadRecord]) {
        downloads = records
#if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--mwx-debug-run-web-workshop-id") {
            preloadWebRuntimeCaches(for: records)
        }
#else
        preloadWebRuntimeCaches(for: records)
#endif
        let nextPrimaryID: String? = {
            if let selectedDownloadID,
               downloads.contains(where: { $0.id == selectedDownloadID }) {
                return selectedDownloadID
            }
            return nil
        }()
        let nextSelectedIDs = selectedDownloadIDs.filter { id in
            downloads.contains(where: { $0.id == id })
        }
        publishDownloadSelectionState(
            primaryID: nextPrimaryID,
            selectedIDs: nextSelectedIDs,
            deferPublishing: true
        )
        scheduleLibraryVersionReclamation()
    }

    nonisolated static func scanInstalledLibraryRecords(
        managed: [String: SteamWorkshopDownloadMetadataSnapshot],
        context: SteamWorkshopInstalledLibraryScanContext
    ) -> [SteamWorkshopDownloadRecord] {
        let videoFiles = scanDirectVideoFiles(in: context.videoRoot)
        let webDirectories = scanDirectChildDirectories(in: context.webRoot).filter {
            !SteamWorkshopLibraryTransaction.isReservedManagedPublicDirectory(
                $0, libraryRoot: context.libraryRoot
            )
        }
        let sceneDirectories = scanDirectChildDirectories(in: context.sceneRoot).filter {
            !SteamWorkshopLibraryTransaction.isReservedManagedPublicDirectory(
                $0, libraryRoot: context.libraryRoot
            )
        }

        var records: [SteamWorkshopDownloadRecord] = managed.values.compactMap { snapshot in
            guard let commit = snapshot.commit,
                  SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: context.libraryRoot) else { return nil }
            return scanBuildInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                fallbackProject: nil, fallbackIdentifier: snapshot.item.id, managedSnapshots: managed, context: context)
        }
        // Tombstones suppress stale legacy aliases; task history never creates a local wallpaper.
        var seenIDs = Set(managed.keys)
        for videoURL in videoFiles {
            let metadata = scanLoadVideoDownloadMetadataSnapshot(for: videoURL, context: context)
            guard let record = scanBuildInstalledVideoRecord(videoURL: videoURL, metadata: metadata, context: context),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }
        for directory in webDirectories + sceneDirectories {
            guard let record = scanBuildInstalledRecord(at: directory, resolvingIDs: [], managedSnapshots: managed, context: context),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }
        return records.sorted { $0.updatedAt > $1.updatedAt }
    }

    nonisolated static private func scanDirectChildDirectories(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter(\.hasDirectoryPath)
    }

    nonisolated static private func scanDirectVideoFiles(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { url in
            !url.hasDirectoryPath && isSupportedWorkshopVideoFile(url)
        }
    }

    nonisolated static private func isSupportedWorkshopVideoFile(_ url: URL) -> Bool {
        Set(["mp4", "webm", "mov", "m4v"]).contains(url.pathExtension.localizedLowercase)
    }

    nonisolated static private func scanLoadVideoDownloadMetadataSnapshot(
        for videoURL: URL,
        context: SteamWorkshopInstalledLibraryScanContext
    ) -> SteamWorkshopDownloadMetadataSnapshot? {
        let metadataURL = context.metadataIndexDirectory
            .appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("json")
        guard let data = try? Data(contentsOf: metadataURL),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    nonisolated static private func scanBuildInstalledVideoRecord(
        videoURL: URL,
        metadata: SteamWorkshopDownloadMetadataSnapshot?,
        context: SteamWorkshopInstalledLibraryScanContext
    ) -> SteamWorkshopDownloadRecord? {
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }
        let identifier = metadata?.item.id ?? "video:\(videoURL.deletingPathExtension().lastPathComponent)"
        let browserItem = metadata?.item
        let title = browserItem?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = videoURL.deletingPathExtension().lastPathComponent
        let updatedAt = (try? videoURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : fallbackTitle,
            description: browserItem?.descriptionText ?? "",
            tags: browserItem?.tags ?? [],
            folderURL: videoURL.deletingLastPathComponent(),
            projectFileURL: nil,
            ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil,
            entryHTMLURL: nil,
            resolvedWebRootURL: nil,
            previewURL: browserItem?.previewImageURL,
            sourceVideoURL: nil,
            exportedVideoURL: videoURL,
            updatedAt: updatedAt,
            sizeText: fileSizeTextForURL(videoURL) ?? "未知大小",
            status: .ready,
            browserItem: browserItem,
            contentType: .video,
            dependencyItemID: nil,
            dependencyStatus: .none
        )
    }

    nonisolated static private func fileSizeTextForURL(_ url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        return Self.fileSizeText(forBytes: size)
    }

    func publishDownloadedVersion(_ request: SteamWorkshopPendingDownloadRequest,
        commit prepared: SteamWorkshopLibraryCommit, libraryRoot: URL) throws {
        guard !removingDownloadIDs.contains(request.id) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "此壁纸正在删除，已停止入库。")
        }
        let commit = try SteamWorkshopLibraryTransaction.canonicalCommit(prepared)
        let content = try SteamWorkshopLibraryTransaction.contentURL(for: commit, libraryRoot: libraryRoot)
        let previousIdentity = SteamWorkshopLibraryTransaction.storageIdentity(containing: content, libraryRoot: libraryRoot)
        if let previousIdentity {
            guard !referencedLibraryStorageIdentities().contains(previousIdentity),
                  steamLibraryVersionLeaseRegistry.beginReclamation(previousIdentity) else {
                throw SteamWorkshopLibraryTransaction.Failure(message: "此壁纸仍被播放器或视频库引用，请解除引用后重试更新。")
            }
        }
        defer {
            // Publication only relocates the previous version; GC must be able to
            // acquire its own removal reservation after this synchronous handoff.
            if let previousIdentity { steamLibraryVersionLeaseRegistry.reclamationFailed(previousIdentity) }
        }
        // 无所有权标记的旧版样本占据目标目录时按需收编。事务层对无标记
        // 占用保持失败关闭（未知内容不得被静默覆盖），收编在服务层显式
        // 完成：正在播放的旧样本拒绝更新，其余把旧目录移开，发布成功后
        // 删除旧内容，失败回移。
        var legacyAsideURL: URL?
        if previousIdentity == nil,
           let occupant = try? SteamWorkshopLibraryTransaction.absoluteDirectory(content),
           (try? SteamWorkshopLibraryTransaction.markerCommit(in: occupant)) == nil {
            if let record = latestDownloadRecord(for: request.id), isRecordCurrentlyPlaying(record) {
                throw SteamWorkshopLibraryTransaction.Failure(message: "旧版样本正在播放，请先停止播放再更新。")
            }
            let aside = content.deletingLastPathComponent()
                .appendingPathComponent(".retired-legacy-\(request.id)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.moveItem(at: content, to: aside)
            legacyAsideURL = aside
        }
        let item = request.item ?? browserItemForDownload(id: request.id)
            ?? Self.itemByMergingAuthorMetadata(into: nil, id: request.id, title: request.pageTitle,
                author: "未知作者", authorProfileURL: nil, authorWorkshopURL: nil)
        var snapshot = SteamWorkshopDownloadMetadataSnapshot(fetchedAt: commit.committedAt, item: item,
            sourceVideoRelativePath: commit.contentType == "video" ? commit.entryPath : nil,
            previewRelativePath: nil,
            exportedVideoURL: commit.contentType == "video" ? commit.entryPath.map { content.appendingPathComponent($0) } : nil,
            legacyFolderURL: content)
        snapshot.commit = commit
        do {
            try SteamWorkshopLibraryTransaction.publishCanonical(prepared,
                metadata: JSONEncoder().encode(snapshot), libraryRoot: libraryRoot)
            if let aside = legacyAsideURL {
                try? FileManager.default.removeItem(at: aside)
            }
        } catch {
            if let aside = legacyAsideURL {
                try? FileManager.default.moveItem(at: aside, to: content)
            }
            throw error
        }
    }

    /// Single current pointer lives in the existing metadata index. Managed version directories are
    /// never inferred as ready by the public legacy scanner.
    func managedDownloadSnapshots() -> [String: SteamWorkshopDownloadMetadataSnapshot] {
        (try? loadManagedDownloadSnapshots(requireComplete: false)) ?? [:]
    }

    /// One-item variant for open-time freshness decisions: reads a single
    /// metadata file instead of the whole index.
    func managedDownloadSnapshots(matchingItemID: String) -> [String: SteamWorkshopDownloadMetadataSnapshot] {
        (try? loadManagedDownloadSnapshots(requireComplete: false, matchingItemID: matchingItemID)) ?? [:]
    }

    func loadManagedDownloadSnapshots(
        requireComplete: Bool,
        matchingItemID: String? = nil,
        includeLegacy: Bool = false
    ) throws -> [String: SteamWorkshopDownloadMetadataSnapshot] {
        let entries = try SteamWorkshopLibraryTransaction.publishedMetadata(
            libraryRoot: steamDownloadLibraryRootURL,
            requireComplete: requireComplete,
            matchingItemID: matchingItemID
        )
        var result: [String: SteamWorkshopDownloadMetadataSnapshot] = [:]
        for (itemID, data) in entries {
            guard let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
                if requireComplete { throw SteamWorkshopLibraryTransaction.Failure(message: "下载索引不完整，已暂停版本回收。") }
                continue
            }
            guard let commit = snapshot.commit else {
                if includeLegacy || snapshot.legacyRemoved == true {
                    guard snapshot.item.id == itemID else {
                        if requireComplete { throw SteamWorkshopLibraryTransaction.Failure(message: "下载索引身份无效，已暂停版本回收。") }
                        continue
                    }
                    result[itemID] = snapshot
                }
                continue
            }
            guard commit.workshopId == snapshot.item.id,
                  itemID == commit.workshopId,
                  let content = try? SteamWorkshopLibraryTransaction.contentURL(for: commit, libraryRoot: steamDownloadLibraryRootURL),
                  snapshot.legacyFolderURL == content else {
                if requireComplete { throw SteamWorkshopLibraryTransaction.Failure(message: "下载索引身份无效，已暂停版本回收。") }
                continue
            }
            result[commit.workshopId] = snapshot
        }
        return result
    }

    func loadLegacyVideoDownloadSnapshot(
        matching record: SteamWorkshopDownloadRecord
    ) throws -> SteamWorkshopDownloadMetadataSnapshot? {
        guard record.contentType == .video,
              let videoURL = record.exportedVideoURL ?? record.sourceVideoURL else { return nil }
        let filename = downloadMetadataFileURL(forVideoURL: videoURL).lastPathComponent
        let entries = try SteamWorkshopLibraryTransaction.publishedMetadata(
            libraryRoot: steamDownloadLibraryRootURL,
            requireComplete: true,
            matchingFilename: filename
        )
        guard let data = entries[String(filename.dropLast(5))] else { return nil }
        guard let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "旧版视频下载索引不完整，拒绝移除。")
        }
        guard snapshot.commit == nil else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "旧版视频下载索引身份无效，拒绝移除。")
        }
        return snapshot
    }

    /// Upgrade the retired hidden v1 layout in the background. Copy and validation happen off the
    /// main actor; publication re-checks the exact old pointer before atomically replacing metadata.
    /// A playing v1 path is never moved or deleted here and remains protected by the normal lease /
    /// engine-reference reclamation set.
    private func scheduleLegacyLibraryPublicationMigration(
        from snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]
    ) {
        guard legacyLibraryPublicationMigrationTask == nil else { return }
        let candidates = snapshots.values.filter {
            ($0.commit?.version == 1 || $0.commit?.version == 2) && $0.commit?.removed == false
        }.sorted { $0.item.id < $1.item.id }
        guard !candidates.isEmpty else { return }
        let library = steamDownloadLibraryRootURL
        let staging = steamDownloadStagingRootURL
        legacyLibraryPublicationMigrationTask = Task { [weak self] in
            guard let self else { return }
            var migratedCount = 0
            var deferredCount = 0
        candidateLoop:
            for candidate in candidates {
                guard let legacyCommit = candidate.commit,
                      !self.removingDownloadIDs.contains(candidate.item.id),
                      self.downloadJobStore.activeJob(forWorkshopItemId: candidate.item.id) == nil else { continue }
                let capacityKey = "legacy-migration:" + (
                    SteamWorkshopLibraryTransaction.storageIdentity(for: legacyCommit)
                        ?? candidate.item.id
                )
                // Public v2 folders only need a rename. A live consumer keeps its
                // immutable path until the next scan after its lease is released.
                if legacyCommit.version == 2 {
                    guard let identity = SteamWorkshopLibraryTransaction.storageIdentity(for: legacyCommit),
                          !self.referencedLibraryStorageIdentities().contains(identity),
                          self.steamLibraryVersionLeaseRegistry.beginReclamation(identity) else { continue }
                    defer { self.steamLibraryVersionLeaseRegistry.reclamationFailed(identity) }
                    do {
                        guard try self.loadManagedDownloadSnapshots(requireComplete: true)[candidate.item.id]?.commit == legacyCommit else { continue }
                        try self.publishDownloadedVersion(SteamWorkshopPendingDownloadRequest(
                            id: candidate.item.id, pageTitle: candidate.item.title, item: candidate.item),
                            commit: legacyCommit, libraryRoot: library)
                        migratedCount += 1
                    } catch { deferredCount += 1 }
                    continue
                }
                var preparedMigration: SteamWorkshopLibraryCommit?
                for retry in 0..<3 {
                    if retry > 0 {
                        let delay = retry == 1 ? UInt64(250_000_000) : UInt64(1_000_000_000)
                        do { try await Task.sleep(nanoseconds: delay) }
                        catch { break candidateLoop }
                    }
                    do {
                        let before = try self.loadManagedDownloadSnapshots(requireComplete: true)[candidate.item.id]
                        guard before?.commit == legacyCommit else {
                            continue candidateLoop // A delete/update already won.
                        }
                        if let prepared = preparedMigration,
                           !SteamWorkshopLibraryTransaction.isAvailable(
                               prepared,
                               libraryRoot: library
                           ) {
                            self.reservedLibraryCopyBytesByJobKey[capacityKey] = nil
                            preparedMigration = nil
                        }
                        if preparedMigration == nil {
                            try await self.claimLibraryCopyCapacity(jobKey: capacityKey)
                            do {
                                defer { self.reservedLibraryCopyBytesByJobKey[capacityKey] = nil }
                                let capacity = try await Task.detached(priority: .utility) {
                                    (
                                        required: try SteamWorkshopLibraryTransaction.migrationRequiredBytes(
                                            for: legacyCommit,
                                            libraryRoot: library
                                        ),
                                        available: try SteamWorkshopLibraryTransaction.availableDiskBytes(at: library),
                                        sharesStagingVolume: try SteamWorkshopLibraryTransaction.areOnSameFileSystem(
                                            library,
                                            staging
                                        )
                                    )
                                }.value
                                try self.reserveLibraryCopyCapacity(
                                    required: capacity.required,
                                    available: capacity.available,
                                    sharesStagingVolume: capacity.sharesStagingVolume,
                                    jobKey: capacityKey
                                )
                                preparedMigration = try await Task.detached(priority: .utility) {
                                    try SteamWorkshopLibraryTransaction.migrateLegacyCommit(
                                        legacyCommit, libraryRoot: library
                                    )
                                }.value
                            }
                        }
                        guard let migratedCommit = preparedMigration else {
                            throw SteamWorkshopLibraryTransaction.Failure(
                                message: "旧下载版本尚未完成公开目录准备。"
                            )
                        }
                        let current = try self.loadManagedDownloadSnapshots(requireComplete: true)[candidate.item.id]
                        guard current?.commit == legacyCommit else {
                            continue candidateLoop // A delete/update won while the copy was in flight.
                        }
                        try self.publishDownloadedVersion(SteamWorkshopPendingDownloadRequest(
                            id: candidate.item.id, pageTitle: candidate.item.title, item: current?.item ?? candidate.item),
                            commit: migratedCommit, libraryRoot: library)
                        migratedCount += 1
                        continue candidateLoop
                    } catch is CancellationError {
                        break candidateLoop
                    } catch {
                        if retry == 2 {
                            deferredCount += 1
                            NSLog("MWX Steam library: v1 public migration deferred for %@: %@",
                                  candidate.item.id, error.localizedDescription)
                        }
                    }
                }
            }
            self.legacyLibraryPublicationMigrationTask = nil
            if migratedCount > 0 {
                NSLog("MWX Steam library: migrated %d hidden version(s) into public type folders", migratedCount)
                self.reloadInstalledItems()
            }
            if deferredCount > 0 {
                NSLog("MWX Steam library: %d hidden version migration(s) remain retryable", deferredCount)
            }
        }
    }

    /// A crash before metadata publication leaves the old ready pointer; after publication the job
    /// can be completed from that exact commit. Never infer completion from a nonempty directory.
    private func reconcileDownloadCommits(_ snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]) {
        guard activeDownloadTasks.isEmpty else { return }
        let published = snapshots.compactMapValues { snapshot -> SteamWorkshopLibraryCommit? in
            guard let commit = snapshot.commit,
                  SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: steamDownloadLibraryRootURL) else { return nil }
            return commit
        }
        downloadJobStore.reconcileInterruptedCommits(published: published)
    }

    func persistDownloadMetadata(item: SteamWorkshopBrowserItem, id: String, targetURL: URL) {
        if let current = managedDownloadSnapshots()[id], let commit = current.commit {
            var updated = SteamWorkshopDownloadMetadataSnapshot(fetchedAt: Date(), item: item,
                sourceVideoRelativePath: current.sourceVideoRelativePath, previewRelativePath: current.previewRelativePath,
                exportedVideoURL: current.exportedVideoURL, legacyFolderURL: current.legacyFolderURL)
            updated.commit = commit
            do {
                try SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(updated),
                    itemID: id, libraryRoot: steamDownloadLibraryRootURL)
            } catch { statusMessage = "下载元数据更新失败：\(error.localizedDescription)" }
            return
        }
        if let record = latestDownloadRecord(for: id),
           record.contentType == .video,
           let videoURL = record.exportedVideoURL ?? record.sourceVideoURL {
            persistVideoDownloadMetadata(item: item, videoURL: videoURL)
            return
        }
        persistProjectDownloadMetadata(item: item, id: id, targetURL: targetURL)
    }

    private func persistVideoDownloadMetadata(item: SteamWorkshopBrowserItem, videoURL: URL) {
        try? FileManager.default.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        let snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: Date(),
            item: item,
            sourceVideoRelativePath: nil,
            previewRelativePath: nil,
            exportedVideoURL: videoURL,
            legacyFolderURL: nil
        )
        writeDownloadMetadataSnapshot(snapshot, to: downloadMetadataFileURL(forVideoURL: videoURL))
    }

    private func persistProjectDownloadMetadata(item: SteamWorkshopBrowserItem?, id: String, targetURL: URL) {
        guard let item = item ?? browserItemForDownload(id: id) else { return }
        let project = Self.loadWorkshopProject(from: targetURL.appendingPathComponent("project.json"))
        try? FileManager.default.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        let sourceVideoURL = Self.resolveVideoURL(in: targetURL, preferredFileName: project?.file)
        let previewRelativePath = resolvePreviewRelativePath(in: targetURL)
        let sourceVideoRelativePath = sourceVideoURL.map { url in
            let basePath = targetURL.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path
            if filePath.hasPrefix(basePath + "/") {
                return String(filePath.dropFirst(basePath.count + 1))
            }
            return url.lastPathComponent
        }
        let snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: Date(),
            item: item,
            sourceVideoRelativePath: sourceVideoRelativePath,
            previewRelativePath: previewRelativePath,
            exportedVideoURL: nil,
            legacyFolderURL: targetURL
        )
        writeDownloadMetadataSnapshot(snapshot, to: downloadMetadataFileURL(for: id))
    }

    private func writeDownloadMetadataSnapshot(_ snapshot: SteamWorkshopDownloadMetadataSnapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: Data.WritingOptions.atomic)
    }

    func loadDownloadMetadataEntry(forItemID itemID: String) -> (url: URL, snapshot: SteamWorkshopDownloadMetadataSnapshot)? {
        Self.scanLoadDownloadMetadataEntry(
            forItemID: itemID,
            metadataIndexDirectory: downloadMetadataIndexDirectoryURL()
        )
    }

    nonisolated static func scanLoadDownloadMetadataEntry(
        forItemID itemID: String,
        metadataIndexDirectory: URL
    ) -> (url: URL, snapshot: SteamWorkshopDownloadMetadataSnapshot)? {
        let directURL = metadataIndexDirectory
            .appendingPathComponent("\(itemID).json")
        if let data = try? Data(contentsOf: directURL),
           let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
           snapshot.item.id == itemID {
            return (directURL, snapshot)
        }

        let metadataFiles = (try? FileManager.default.contentsOfDirectory(
            at: metadataIndexDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in metadataFiles where url.pathExtension == "json" && url != directURL {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
                  snapshot.item.id == itemID else { continue }
            return (url, snapshot)
        }
        return nil
    }

    func downloadMetadataFileURL(forVideoURL videoURL: URL) -> URL {
        downloadMetadataIndexDirectoryURL()
            .appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("json")
    }

    func downloadMetadataFileURL(for record: SteamWorkshopDownloadRecord) -> URL {
        if record.contentType == .video,
           let videoURL = record.exportedVideoURL ?? record.sourceVideoURL {
            return downloadMetadataFileURL(forVideoURL: videoURL)
        }
        return downloadMetadataFileURL(for: record.id)
    }

    private func resolvePreviewRelativePath(in directory: URL) -> String? {
        let projectURL = directory.appendingPathComponent("project.json")
        let project = Self.loadWorkshopProject(from: projectURL)
        let projectRoot = Self.loadWorkshopProjectRoot(from: projectURL)
        return Self.preferredPreviewRelativePath(
            in: directory,
            project: project,
            projectRoot: projectRoot
        )
    }

}
