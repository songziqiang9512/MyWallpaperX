import Foundation

enum SteamWorkshopDownloadContentType { case video, web, scene, unknown }

enum SteamReadyUpdateDeletionFixtureState {
    static var legacyFolderURL = URL(fileURLWithPath: "/private/tmp/unmanaged")
    static var contentType = SteamWorkshopDownloadContentType.web
    static var videoURL: URL?
}

extension SteamWorkshopDownloadRecord {
    var contentType: SteamWorkshopDownloadContentType { SteamReadyUpdateDeletionFixtureState.contentType }
    var exportedVideoURL: URL? { SteamReadyUpdateDeletionFixtureState.videoURL }
    var sourceVideoURL: URL? { SteamReadyUpdateDeletionFixtureState.videoURL }
    var folderURL: URL { SteamReadyUpdateDeletionFixtureState.legacyFolderURL }
}

extension SteamWorkshopService {
    func syncDownloadsInspectorSelectionIfNeeded() {}

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
        let legacy = mode.hasSuffix("legacy") || legacyVideo
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
        downloads = [ready]
        downloadWorkshopItem(id: "123456", pageTitle: "update")
        while !transport.commands.contains(where: { $0["command"] as? String == "startDownload" }) {
            await Task.yield()
        }
        let key = transport.commands.first { $0["command"] as? String == "startDownload" }!["jobId"] as! String
        let jobID = key.split(separator: "-").dropLast().joined(separator: "-")
        downloads = [ready] // A normal reload projects previous-current while its update is active.

        let jobStoreURL = transport.jobStoreURL!
        let savedJobStoreURL = jobStoreURL.appendingPathExtension("before-delete")
        if mode.hasSuffix("save-failure") {
            try FileManager.default.moveItem(at: jobStoreURL, to: savedJobStoreURL)
            try FileManager.default.createDirectory(at: jobStoreURL, withIntermediateDirectories: false)
            deleteDownload(itemID: "123456")
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
        if publishFailure {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: downloadMetadataIndexDirectoryURL().path
            )
            precondition(statusMessage.contains("移除失败"))
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
            precondition(statusMessage.contains("移除失败"),
                "silent cancellation must preserve the publication failure feedback")
            await steamServiceClient.stop(shutdownTimeout: 0)
            print("EXECUTION PASS: \(mode)")
            return
        }
        precondition(statusMessage == "已移除 old ready")
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
        precondition(FileManager.default.fileExists(atPath: content.path),
            "delete keeps previous-current content for playback-aware reclamation")
        precondition(downloadJobStore.job(id: jobID)?.state == .cancelled)
        precondition(downloads.isEmpty, "durable cancellation must not project an orphan failed card")
        precondition(statusMessage == "已移除 old ready", "silent delete cancellation must preserve outer feedback")
        if let replacement {
            precondition(FileManager.default.fileExists(atPath: replacement.appendingPathComponent("sentinel").path))
            precondition(downloadError?.contains("清理") == true)
        } else {
            precondition(!FileManager.default.fileExists(atPath: transport.receipt["stagingPath"] as! String),
                "helper terminal must retire the exact staging lease")
        }
        await steamServiceClient.stop(shutdownTimeout: 0)
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
