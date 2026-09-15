import Foundation

extension SteamWorkshopService {
    func reloadInstalledItems() {
        let managed = managedDownloadSnapshots()
        reconcileDownloadCommits(managed)
        let videoFiles = directVideoFiles(in: videoLibraryRootURL)
        let webDirectories = directChildDirectories(in: webLibraryRootURL)
        let sceneDirectories = directChildDirectories(in: sceneLibraryRootURL)

        var records: [SteamWorkshopDownloadRecord] = managed.values.compactMap { snapshot in
            guard let commit = snapshot.commit,
                  SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: steamDownloadLibraryRootURL) else { return nil }
            return buildInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                fallbackProject: nil, fallbackIdentifier: snapshot.item.id, managedSnapshots: managed)
        }
        // Tombstones also suppress old legacy files; updates never delete files a player may still use.
        var seenIDs = Set(managed.keys)
        for videoURL in videoFiles {
            let metadata = loadVideoDownloadMetadataSnapshot(for: videoURL)
            guard let record = buildInstalledVideoRecord(videoURL: videoURL, metadata: metadata),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }
        for directory in webDirectories + sceneDirectories {
            guard let record = buildInstalledRecord(at: directory, managedSnapshots: managed),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }

        var transient = downloads.filter { record in
            switch record.status {
            case .queued, .downloading, .failed:
                return !records.contains(where: { $0.id == record.id })
            case .ready:
                return false
            }
        }
        var projectedIDs = Set(records.map(\.id)).union(transient.map(\.id))
        if let account = steamAuth.steamId {
            for job in downloadJobStore.jobs.sorted(by: { $0.updatedAt > $1.updatedAt })
            where job.accountSteamId == account && !projectedIDs.contains(job.workshopItemId) {
                guard let record = transientDownloadRecord(for: job) else { continue }
                transient.append(record)
                projectedIDs.insert(record.id)
            }
        }

        downloads = (records + transient).sorted { $0.updatedAt > $1.updatedAt }
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

    /// Rebuild the user-visible projection from durable intent after relaunch. A
    /// published ready record wins for the same item so a failed update never
    /// hides or disables the previous-current content.
    private func transientDownloadRecord(for job: SteamDownloadJob) -> SteamWorkshopDownloadRecord? {
        let status: SteamWorkshopDownloadRecord.Status
        switch job.state {
        case .queued:
            status = .queued
        case .running, .staged, .committing:
            status = .downloading
        case .failed:
            status = .failed(job.failureMessage ?? "下载失败，请重试。")
        case .cancelled, .completed:
            return nil
        }
        let item = browserItemForDownload(id: job.workshopItemId)
        return SteamWorkshopDownloadRecord(
            id: job.workshopItemId,
            title: item?.title ?? job.title,
            description: item?.descriptionText ?? "",
            tags: item?.tags ?? [],
            folderURL: libraryRootURL,
            projectFileURL: nil,
            ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil,
            entryHTMLURL: nil,
            resolvedWebRootURL: nil,
            previewURL: item?.previewImageURL,
            sourceVideoURL: nil,
            exportedVideoURL: nil,
            updatedAt: job.updatedAt,
            sizeText: item?.fileSizeText ?? "未知大小",
            status: status,
            browserItem: item,
            contentType: .unknown,
            dependencyItemID: nil,
            dependencyStatus: .none
        )
    }

    private func directChildDirectories(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter(\.hasDirectoryPath)
    }

    private func directVideoFiles(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { url in
            !url.hasDirectoryPath && isSupportedWorkshopVideoFile(url)
        }
    }

    func publishDownloadedVersion(_ request: SteamWorkshopPendingDownloadRequest,
                                  commit: SteamWorkshopLibraryCommit, libraryRoot: URL) throws {
        let content = try SteamWorkshopLibraryTransaction.contentURL(for: commit, libraryRoot: libraryRoot)
        let item = request.item ?? browserItemForDownload(id: request.id)
            ?? Self.itemByMergingAuthorMetadata(into: nil, id: request.id, title: request.pageTitle,
                author: "未知作者", authorProfileURL: nil, authorWorkshopURL: nil)
        var snapshot = SteamWorkshopDownloadMetadataSnapshot(fetchedAt: commit.committedAt, item: item,
            sourceVideoRelativePath: commit.contentType == "video" ? commit.entryPath : nil,
            previewRelativePath: nil,
            exportedVideoURL: commit.contentType == "video" ? commit.entryPath.map { content.appendingPathComponent($0) } : nil,
            legacyFolderURL: content)
        snapshot.commit = commit
        try SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(snapshot),
            itemID: request.id, libraryRoot: libraryRoot)
    }

    /// Single current pointer lives in the existing metadata index. Hidden versions are never scanned as ready.
    func managedDownloadSnapshots() -> [String: SteamWorkshopDownloadMetadataSnapshot] {
        let entries = (try? SteamWorkshopLibraryTransaction.publishedMetadata(
            libraryRoot: steamDownloadLibraryRootURL
        )) ?? [:]
        var result: [String: SteamWorkshopDownloadMetadataSnapshot] = [:]
        for (itemID, data) in entries {
            guard let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
                  let commit = snapshot.commit, commit.workshopId == snapshot.item.id,
                  itemID == commit.workshopId,
                  let content = try? SteamWorkshopLibraryTransaction.contentURL(for: commit, libraryRoot: steamDownloadLibraryRootURL),
                  snapshot.legacyFolderURL == content else { continue }
            result[commit.workshopId] = snapshot
        }
        return result
    }

    /// A crash before metadata publication leaves the old ready pointer; after publication the job
    /// can be completed from that exact commit. Never infer completion from a nonempty directory.
    private func reconcileDownloadCommits(_ snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]) {
        guard activeDownloadTask == nil else { return }
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
        let sourceVideoURL = resolveVideoURL(in: targetURL, preferredFileName: project?.file)
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

    func metadataItemForCompletedDownload(_ request: SteamWorkshopPendingDownloadRequest) async -> SteamWorkshopBrowserItem? {
        if let item = request.item ?? browserItemForDownload(id: request.id),
           !SteamWorkshopDetailRefreshSupport.needsListRefresh(item) {
            return item
        }

        let fallback = request.item ?? browserItemForDownload(id: request.id)
        return await resolveCachedDownloadAuthorMetadata(
            itemID: request.id,
            fallback: fallback,
            title: request.pageTitle
        )
    }

    func loadDownloadMetadataEntry(forItemID itemID: String) -> (url: URL, snapshot: SteamWorkshopDownloadMetadataSnapshot)? {
        let directURL = downloadMetadataFileURL(for: itemID)
        if let data = try? Data(contentsOf: directURL),
           let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
           snapshot.item.id == itemID {
            return (directURL, snapshot)
        }

        let metadataFiles = (try? FileManager.default.contentsOfDirectory(
            at: downloadMetadataIndexDirectoryURL(),
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

    private func loadVideoDownloadMetadataSnapshot(for videoURL: URL) -> SteamWorkshopDownloadMetadataSnapshot? {
        let metadataURL = downloadMetadataFileURL(forVideoURL: videoURL)
        guard let data = try? Data(contentsOf: metadataURL),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private func buildInstalledVideoRecord(
        videoURL: URL,
        metadata: SteamWorkshopDownloadMetadataSnapshot?
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

    private func fileSizeTextForURL(_ url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        return Self.fileSizeText(forBytes: size)
    }

    private func isSupportedWorkshopVideoFile(_ url: URL) -> Bool {
        Set(["mp4", "webm", "mov", "m4v"]).contains(url.pathExtension.localizedLowercase)
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
