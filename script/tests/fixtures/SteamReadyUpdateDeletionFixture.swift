import Foundation

enum SteamWorkshopDownloadContentType { case video, web, scene, unknown }

enum SteamReadyUpdateDeletionFixtureState {
    static var legacyFolderURL = URL(fileURLWithPath: "/private/tmp/unmanaged")
    static var contentType = SteamWorkshopDownloadContentType.web
    static var videoURL: URL?
    static var videoURLs: [Data: URL] = [:]
}

extension SteamWorkshopDownloadRecord {
    var contentType: SteamWorkshopDownloadContentType { SteamReadyUpdateDeletionFixtureState.contentType }
    var exportedVideoURL: URL? { SteamReadyUpdateDeletionFixtureState.videoURLs[Data(id.utf8)] ?? SteamReadyUpdateDeletionFixtureState.videoURL }
    var sourceVideoURL: URL? { exportedVideoURL }
    var folderURL: URL { SteamReadyUpdateDeletionFixtureState.legacyFolderURL }
}

extension SteamWorkshopService {
    func runReadyUpdateDeletionFixtureIfNeeded(mode: String, transport: Transport) async throws -> Bool {
        guard mode.hasPrefix("ready-update-delete") else { return false }
        try await runReadyUpdateDeletionFixture(mode: mode, transport: transport)
        return true
    }

    func runReadyUpdateDeletionFixture(mode: String, transport: Transport) async throws {
        let legacyVideo = mode.contains("legacy-video")
        let numericAlias = mode.hasSuffix("numeric-alias")
        let commitBearingAlias = mode.hasSuffix("commit-bearing-alias")
        let publishFailure = mode.hasSuffix("publish-failure")
        let localOnly = mode.hasSuffix("local-only")
        let legacy = mode.hasSuffix("legacy") || legacyVideo || localOnly
        let versionName = "11111111-1111-4111-8111-111111111111"
        let content = legacyVideo
            ? steamDownloadLibraryRootURL.appendingPathComponent(
                numericAlias ? "Video/2026.mp4" : "Video/renamed-wallpaper.mp4"
            )
            : legacy
                ? steamDownloadLibraryRootURL.appendingPathComponent("Web/123456", isDirectory: true)
                : steamDownloadLibraryRootURL
                .appendingPathComponent(SteamWorkshopLibraryTransaction.versionsName, isDirectory: true)
                .appendingPathComponent(versionName, isDirectory: true)
                .appendingPathComponent("content", isDirectory: true)
        SteamReadyUpdateDeletionFixtureState.legacyFolderURL = content
        SteamReadyUpdateDeletionFixtureState.contentType = legacyVideo ? .video : .web
        SteamReadyUpdateDeletionFixtureState.videoURL = legacyVideo ? content : nil
        try FileManager.default.createDirectory(
            at: legacyVideo ? content.deletingLastPathComponent() : content,
            withIntermediateDirectories: true
        )
        try Data("old-ready".utf8).write(to: legacyVideo ? content : content.appendingPathComponent("index.html"))
        let commit = SteamWorkshopLibraryCommit(
            version: 1,
            workshopId: "123456",
            jobId: "old-ready-job",
            attempt: 1,
            directoryName: versionName,
            manifestId: "123",
            contentDigest: String(repeating: "a", count: 64),
            contentType: "web",
            entryPath: "index.html",
            committedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: commit.committedAt,
            item: SteamWorkshopBrowserItem(id: "123456", title: "old ready"),
            sourceVideoRelativePath: nil,
            previewRelativePath: nil,
            exportedVideoURL: legacyVideo ? content : nil,
            legacyFolderURL: legacyVideo ? nil : content
        )
        if !legacy || commitBearingAlias { snapshot.commit = commit }
        if legacyVideo {
            let canonical = downloadMetadataIndexDirectoryURL().appendingPathComponent("\(commit.workshopId).json")
            try? FileManager.default.removeItem(at: canonical)
            try JSONEncoder().encode(snapshot).write(
                to: downloadMetadataFileURL(forVideoURL: content), options: .atomic
            )
        } else {
            try SteamWorkshopLibraryTransaction.publish(
                metadata: JSONEncoder().encode(snapshot),
                itemID: commit.workshopId,
                libraryRoot: steamDownloadLibraryRootURL
            )
        }
        if publishFailure {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: downloadMetadataIndexDirectoryURL().path
            )
        }
        if numericAlias {
            let managed = try loadManagedDownloadSnapshots(requireComplete: true)
            precondition(managed.isEmpty,
                "a numeric legacy video alias must not become a managed item identity")
        }
        let ready = SteamWorkshopDownloadRecord(
            id: "123456", title: "old ready", sizeText: "1 KB", status: .ready
        )
        let detail = Self.detailCacheFileURL(id: ready.id)
        let otherDetail = Self.detailCacheFileURL(id: "654321")
        try Data("this detail".utf8).write(to: detail)
        try Data("unrelated detail".utf8).write(to: otherDetail)
        defer {
            let keptContent = FileManager.default.fileExists(atPath: content.path)
            precondition(FileManager.default.fileExists(atPath: detail.path) == keptContent,
                "only a successful source deletion retires its detail cache")
            precondition(FileManager.default.fileExists(atPath: otherDetail.path),
                "deleting one source cannot remove another item's cached details")
            precondition(retiredWebCacheIDs.contains(ready.id) == !keptContent,
                "web analysis cache retirement follows successful file deletion")
        }
        if mode.hasSuffix("inspector-current") {
            selectedDownloadInspectorItem = .init(id: ready.id, title: ready.title)
            selectedDownloadDetailItem = selectedDownloadInspectorItem
            isRefreshingSelectedDownloadDetailItem = true
        }
        downloads = [ready]
        if mode.hasSuffix("inspector-other") {
            let other = SteamWorkshopBrowserItem(id: "654321", title: "Inspector B")
            selectedDownloadInspectorItem = other
            selectedDownloadDetailItem = other
            selectedDownloadDetailError = "B metadata status"
            isRefreshingSelectedDownloadDetailItem = true
            var results: [[String: Bool]] = []
            deleteDownloads(itemIDs: [ready.id]) { results.append($0) }
            while removingDownloadIDs.contains(ready.id) { await Task.yield() }
            precondition(results.count == 1 && results[0][ready.id] == true && downloads.isEmpty)
            precondition(!FileManager.default.fileExists(atPath: content.path))
            precondition(selectedDownloadInspectorItem?.id == other.id && selectedDownloadDetailItem?.id == other.id
                && selectedDownloadDetailError == "B metadata status" && isRefreshingSelectedDownloadDetailItem
                && detailCancellations == 0, "deleting A must not dismiss the current unrelated B inspector")
            installedLibraryScanGeneration = 2
            finishInstalledLibraryScan(generation: 1, records: [ready])
            precondition(downloads.isEmpty,
                "a stale source scan must not revive the removed A")
            let current = SteamWorkshopDownloadRecord(id: other.id, title: other.title, sizeText: "2 KB", status: .ready)
            finishInstalledLibraryScan(generation: 2, records: [current])
            precondition(downloads.map(\.id) == [other.id] && hasCompletedInstalledLibraryLoad
                && reclamationRequests == 1,
                "a current source reload must keep its original publication/reclamation work")
            precondition(selectedDownloadInspectorItem?.id == other.id && selectedDownloadDetailItem?.id == other.id
                && selectedDownloadDetailError == "B metadata status" && isRefreshingSelectedDownloadDetailItem
                && detailCancellations == 0, "source reload cannot clear a new inspector using retired selection state")
            dismissDownloadInspector()
            precondition(selectedDownloadInspectorItem == nil && selectedDownloadDetailItem == nil
                && selectedDownloadDetailError == nil && !isRefreshingSelectedDownloadDetailItem
                && detailCancellations == 1, "explicit inspector close must still cancel the original detail owner")
            await steamServiceClient.stop(shutdownTimeout: 0)
            print("EXECUTION PASS: \(mode)")
            return
        }
        if localOnly {
            try FileManager.default.removeItem(at: downloadMetadataIndexDirectoryURL())
            // Missing index means no per-item pointer; it must still block whole-library GC.
            do { _ = try loadManagedDownloadSnapshots(requireComplete: true)
                fatalError("missing full index admitted reclamation") } catch {}
            deleteDownload(itemID: ready.id)
            while removingDownloadIDs.contains(ready.id) { await Task.yield() }
            precondition(!FileManager.default.fileExists(atPath: content.path), statusMessage)
            precondition(downloads.isEmpty)
            await steamServiceClient.stop(shutdownTimeout: 0)
            print("EXECUTION PASS: \(mode)")
            return
        }
        var playbackLease: PlaybackResourceLifetime?
        if mode.contains("-scene") {
            SteamReadyUpdateDeletionFixtureState.contentType = .scene
            SceneDaemonClient.shared.recordID = ready.id
            if mode.hasSuffix("scene-busy") {
                prepareSceneDownloadRemoval = { _, done in done(false) }
            } else {
                playbackLease = steamLibraryVersionLeaseRegistry.acquire(commit)
                Task { @MainActor in
                    while !SceneDaemonClient.shared.stopped { await Task.yield() }
                    precondition(FileManager.default.fileExists(atPath: content.path))
                    precondition(!self.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().isEmpty)
                    playbackLease = nil
                    SceneDaemonClient.shared.completion?()
                }
            }
        }
        downloadWorkshopItem(id: "123456", pageTitle: "update")
        while !transport.commands.contains(where: { $0["command"] as? String == "startDownload" }) {
            await Task.yield()
        }
        let key = transport.commands.first { $0["command"] as? String == "startDownload" }!["jobId"] as! String
        let jobID = key.split(separator: "-").dropLast().joined(separator: "-")
        downloads = [ready] // A normal reload projects previous-current while its update is active.

        while transport.requireStagingAcknowledgement && !transport.observedPersistedIdentityBeforeAcknowledgement { await Task.yield() }
        let jobStoreURL = transport.jobStoreURL!
        let savedJobStoreURL = jobStoreURL.appendingPathExtension("before-delete")
        if mode.hasSuffix("save-failure") {
            try FileManager.default.moveItem(at: jobStoreURL, to: savedJobStoreURL)
            try FileManager.default.createDirectory(at: jobStoreURL, withIntermediateDirectories: false)
            deleteDownload(itemID: "123456")
        while removingDownloadIDs.contains("123456") { await Task.yield() }
            let retained = try loadManagedDownloadSnapshots(requireComplete: true)["123456"]?.commit
            precondition(retained?.removed == false && retained?.jobId == commit.jobId,
                "failed durable cancellation must preserve the ready pointer")
            precondition(statusMessage.contains("取消状态无法保存"))
            precondition(!transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }), "physical cancellation cannot stand in for the durable deletion fence")
            try FileManager.default.removeItem(at: jobStoreURL)
            try FileManager.default.moveItem(at: savedJobStoreURL, to: jobStoreURL)
            try await finishReadyUpdateDeletionFixtureCancellation(key: key, transport: transport)
            print("EXECUTION PASS: \(mode)")
            return
        }

        if mode.hasSuffix("metadata-failure") {
            let metadata = steamDownloadLibraryRootURL
                .appendingPathComponent(SteamWorkshopLibraryTransaction.metadataName, isDirectory: true)
                .appendingPathComponent("123456.json")
            try Data("broken-json".utf8).write(to: metadata, options: .atomic)
            deleteDownload(itemID: "123456")
        while removingDownloadIDs.contains("123456") { await Task.yield() }
            precondition(statusMessage.contains("无法安全读取"))
            precondition(downloadJobStore.job(id: jobID)?.state == .running)
            precondition(!transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }), "unknown metadata must fail before logical or physical cancellation")
            precondition(FileManager.default.fileExists(atPath: content.path))
            try await finishReadyUpdateDeletionFixtureCancellation(key: key, transport: transport)
            print("EXECUTION PASS: \(mode)")
            return
        }

        if commitBearingAlias {
            deleteDownload(itemID: "123456")
        while removingDownloadIDs.contains("123456") { await Task.yield() }
            precondition(statusMessage.contains("无法安全读取"))
            precondition(downloadJobStore.job(id: jobID)?.state == .running,
                "invalid alias identity must fail before durable cancellation")
            precondition(!transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }), "invalid alias identity must fail before helper cancellation")
            precondition(FileManager.default.fileExists(atPath: content.path))
            let canonical = try loadManagedDownloadSnapshots(requireComplete: true)["123456"]
            precondition(canonical == nil, "invalid alias identity must fail before tombstone publication")
            try await finishReadyUpdateDeletionFixtureCancellation(key: key, transport: transport)
            print("EXECUTION PASS: \(mode)")
            return
        }

        deleteDownload(itemID: "123456")
        while removingDownloadIDs.contains("123456") { await Task.yield() }
        if mode.hasSuffix("scene-busy") {
            precondition(statusMessage.contains("仍在切换"), statusMessage)
            precondition(downloads.count == 1 && downloads[0].status == .ready)
            precondition(FileManager.default.fileExists(atPath: content.path))
            precondition(!SceneDaemonClient.shared.stopped, "busy cannot stop another Scene ticket")
            let preserved = try loadManagedDownloadSnapshots(requireComplete: true)["123456"]
            precondition(preserved?.commit == snapshot.commit, "busy must preserve ready publication without tombstone")
            try await finishReadyUpdateDeletionFixtureCancellation(key: key, transport: transport)
            print("EXECUTION PASS: \(mode)")
            return
        }
        if publishFailure {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: downloadMetadataIndexDirectoryURL().path
            )
            precondition(statusMessage.contains("删除失败"))
            precondition(downloadJobStore.job(id: jobID)?.state == .cancelled)
            for _ in 0..<100_000 where !transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }) { await Task.yield() }
            precondition(transport.commands.contains(where: {
                $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
            }), "publish failure must not undo the durable or physical cancellation fence")
            precondition(downloads.count == 1 && downloads[0].status == .ready)
            precondition(FileManager.default.fileExists(atPath: content.path))
            let alias = downloadMetadataFileURL(forVideoURL: content)
            precondition(FileManager.default.fileExists(atPath: alias.path),
                "failed canonical publication must preserve the legacy video pointer")
            transport.finishHeldCancellation(jobId: key)
            while activeDownloadTasks[key] != nil { await Task.yield() }
            await terminalDownloadCleanupTask?.value
            precondition(statusMessage.contains("删除失败"),
                "silent cancellation must preserve the publication failure feedback")
            await steamServiceClient.stop(shutdownTimeout: 0)
            print("EXECUTION PASS: \(mode)")
            return
        }
        precondition(statusMessage == "已删除 1 个壁纸及本地文件", statusMessage)
        let removed = try loadManagedDownloadSnapshots(requireComplete: true)["123456"]
        if legacy {
            precondition(removed?.commit == nil && removed?.legacyRemoved == true,
                "legacy direct ready must publish a scanner tombstone")
        } else {
            precondition(removed?.commit?.removed == true, "managed ready must publish one tombstone")
        }
        precondition(downloadJobStore.job(id: jobID)?.state == .cancelled,
            "delete must durably cancel the logical update before returning")
        for _ in 0..<100_000 where !transport.commands.contains(where: {
            $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
        }) { await Task.yield() }
        precondition(transport.commands.contains(where: {
            $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
        }), "delete must cancel the exact helper task")
        precondition(activeDownloadTasks[key] != nil, "local ownership must wait for helper terminal")

        var replacement: URL?
        if mode.hasSuffix("cleanup-failure") {
            let staging = URL(fileURLWithPath: transport.receipt["stagingPath"] as! String, isDirectory: true)
            let original = staging.deletingLastPathComponent().appendingPathComponent("owned-original")
            try FileManager.default.moveItem(at: staging, to: original)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try Data("replacement".utf8).write(to: staging.appendingPathComponent("sentinel"))
            replacement = staging
        }
        transport.finishHeldCancellation(jobId: key)
        while activeDownloadTasks[key] != nil { await Task.yield() }
        await terminalDownloadCleanupTask?.value

        let final = try loadManagedDownloadSnapshots(requireComplete: true)["123456"]
        precondition(final?.legacyRemoved == true || final?.commit?.removed == true,
            "a cancelled update must not republish over the tombstone")
        precondition(!FileManager.default.fileExists(atPath: content.path),
            "explicit deletion must remove the exact local content before completing")
        precondition(downloadJobStore.job(id: jobID)?.state == .cancelled)
        precondition(downloads.isEmpty, "durable cancellation must not project an orphan failed card")
        if mode.hasSuffix("inspector-current") {
            precondition(selectedDownloadInspectorItem == nil && selectedDownloadDetailItem == nil
                && !isRefreshingSelectedDownloadDetailItem && detailCancellations == 1,
                "successful deletion cancels this item's in-flight detail writer before clearing its cache")
        }
        precondition(statusMessage == "已删除 1 个壁纸及本地文件", "silent delete cancellation must preserve outer feedback")
        if let replacement {
            precondition(FileManager.default.fileExists(atPath: replacement.appendingPathComponent("sentinel").path))
            precondition(downloadError?.contains("清理") == true)
        } else {
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String),
                "helper terminal must retire the exact staging lease")
        }
        await steamServiceClient.stop(shutdownTimeout: 0)
        withExtendedLifetime(playbackLease) {}
        print("EXECUTION PASS: \(mode)")
    }

    private func finishReadyUpdateDeletionFixtureCancellation(
        key: String,
        transport: Transport
    ) async throws {
        cancelDownload(itemID: "123456")
        while !transport.commands.contains(where: {
            $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == key
        }) { await Task.yield() }
        transport.finishHeldCancellation(jobId: key)
        while activeDownloadTasks[key] != nil { await Task.yield() }
        await terminalDownloadCleanupTask?.value
        await steamServiceClient.stop(shutdownTimeout: 0)
    }
}
