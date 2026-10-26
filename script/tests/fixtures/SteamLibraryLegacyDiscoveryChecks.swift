import Foundation

// Observations live only at real resolver/projection entries in copied source.
nonisolated final class LegacyDiscoveryObservation: @unchecked Sendable {
    static let shared = LegacyDiscoveryObservation()
    private let lock = NSLock()
    private var calls: [[String: String]] = []
    func entered(_ kind: String, directory: URL?, preferred: String?) {
        lock.lock(); defer { lock.unlock() }
        calls.append(["kind": kind, "directory": directory?.path ?? "<nil>", "preferred": preferred ?? "<nil>"])
    }
    func exists(_ kind: String, directory: URL, path: String) -> Bool {
        entered("exists-" + kind, directory: directory, preferred: nil)
        return FileManager.default.fileExists(atPath: path)
    }
    func take() -> [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        let value = calls; calls.removeAll(); return value
    }
}

@main enum SteamLibraryLegacyDiscoveryChecks {
    static let packageID = "99001"
    static let hostID = "49011"
    static let managedID = "99101"
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        let expectedHome = root.deletingLastPathComponent().appendingPathComponent("home", isDirectory: true)
        precondition(fm.homeDirectoryForCurrentUser.standardizedFileURL.path == expectedHome.standardizedFileURL.path,
                     "real detail-cache fallback must use this fixture's isolated HOME")
        let library = root.appendingPathComponent("library", isDirectory: true)
        let web = library.appendingPathComponent("Web", isDirectory: true)
        let scene = library.appendingPathComponent("Scene", isDirectory: true)
        let metadataIndex = library.appendingPathComponent(".mywallpaperx-steam-metadata", isDirectory: true)
        func directory(_ name: String) -> URL { web.appendingPathComponent(name, isDirectory: true) }
        func put(_ relative: String, _ bytes: Data) throws {
            let url = root.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
            try fm.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        }
        func text(_ relative: String, _ value: String) throws { try put(relative, Data(value.utf8)) }
        func json(_ relative: String, _ value: [String: Any]) throws {
            try put(relative, JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
        }
        func item(_ id: String, workshopType: String? = nil) -> SteamWorkshopBrowserItem {
            SteamWorkshopBrowserItem(id: id, title: "Browser \(id)", author: "fixture author",
                authorProfileURL: nil, authorWorkshopURL: nil, hasAdultContent: false,
                summary: "summary", descriptionText: "browser description", tags: ["fixture"],
                workshopTypeText: workshopType, ageRatingText: nil, genreText: nil, categoryText: "Wallpaper",
                dependencyIDs: [], previewImageURL: nil, previewVideoURL: nil, previewAssetKind: .stillImage,
                fileSizeText: nil, resolutionText: nil, postedText: nil, updatedText: nil,
                favoritesText: nil, subscriptionsText: nil, scoreText: nil, lifetimeFavoritesText: nil,
                lifetimeSubscriptionsText: nil, visibilityText: nil, moderationText: nil, detailFields: [],
                detailURL: URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")!)
        }
        let compatibilityName = "11111111-2222-4333-8444-555555555555"
        let managedRoot = library.appendingPathComponent(".mywallpaperx-steam-versions/\(compatibilityName)/content", isDirectory: true)
        let managedCommit = SteamWorkshopLibraryCommit(version: 1, workshopId: managedID, jobId: "owned-job",
            attempt: 1, directoryName: compatibilityName, manifestId: "77", contentDigest: String(repeating: "a", count: 64),
            contentType: "web", entryPath: "index.html", committedAt: fixedDate)
        func snapshot(_ id: String, folder: URL, source: String? = nil, exported: URL? = nil,
                      commit: SteamWorkshopLibraryCommit? = nil) -> SteamWorkshopDownloadMetadataSnapshot {
            SteamWorkshopDownloadMetadataSnapshot(fetchedAt: fixedDate, item: item(id), sourceVideoRelativePath: source,
                previewRelativePath: nil, exportedVideoURL: exported, legacyFolderURL: folder,
                commit: commit, firstDownloadedAt: fixedDate)
        }
        if mode == "setup" {
            for path in [web, scene, library.appendingPathComponent("Video"), metadataIndex] {
                try fm.createDirectory(at: path, withIntermediateDirectories: true)
            }
            try json("library/Web/project-web/project.json", ["type": "web", "file": "nested/preferred.htm",
                "title": "Authored title", "description": "Authored description", "tags": ["authored"], "preview": "preview.png"])
            try text("library/Web/project-web/nested/preferred.htm", "<html>preferred</html>")
            try text("library/Web/project-web/index.html", "<html>index fallback</html>")
            try text("library/Web/project-web/preview.png", "owned preview path; no image-decode claim")
            try json("library/Web/project-scene/project.json", ["type": "scene", "file": "scene.json"])
            try text("library/Web/project-scene/scene.json", "{}")
            try text("library/Web/metadata-video/clips/picked.mov", "small owned movie path")
            try text("library/Web/metadata-video/big.mp4", String(repeating: "v", count: 100))
            let local = snapshot("metadata-video", folder: directory("metadata-video"), source: "clips/picked.mov")
            try put("library/Web/metadata-video/.mywallpaperx-steam-metadata.json", JSONEncoder().encode(local))
            try text("library/Web/\(packageID)/scene.pkg", "owned package presence, not a Scene decoder fixture")
            try text("library/Web/html-only/index.html", "<html>root</html>")
            try text("library/Web/html-only/nested/default.html", "<html>secondary</html>")
            try text("library/Web/video-only/clip.mp4", "owned video path")
            try fm.createDirectory(at: directory("empty"), withIntermediateDirectories: true)
            try json("library/Web/project-ghost/project.json", ["type": "web", "file": "missing.html"])
            try put("library/Web/metadata-ghost/.mywallpaperx-steam-metadata.json",
                    JSONEncoder().encode(snapshot("metadata-ghost", folder: directory("metadata-ghost"))))
            try fm.createDirectory(at: directory("package-ghost").appendingPathComponent("scene.pkg"), withIntermediateDirectories: true)
            try text("library/Web/malformed-project/project.json", "not JSON")
            try text("library/Web/malformed-project/index.html", "<html>valid despite bad optional metadata</html>")
            try json("library/Web/preferred-video/project.json", ["type": "video", "file": "clips/wanted.mov"])
            try text("library/Web/preferred-video/clips/wanted.mov", "picked")
            try text("library/Web/preferred-video/big.mp4", String(repeating: "b", count: 100))
            try json("library/Web/missing-preferred/project.json", ["type": "web", "file": "missing.htm"])
            try text("library/Web/missing-preferred/index.html", "<html>current fallback</html>")
            try json("library/Web/\(hostID)/project.json", ["type": "web", "file": "index.html"])
            try text("library/Web/\(hostID)/index.html", "<html>dependency host</html>")
            try json("library/Web/shell/project.json", ["type": "web", "dependency": hostID])
            try json("library/Web/missing-shell/project.json", ["type": "web", "dependency": "49999"])
            try json("library/Web/49021/project.json", ["type": "web", "dependency": "49022"])
            try json("library/Web/49022/project.json", ["type": "web", "dependency": "49021"])
            for name in ["shared-shell-a", "shared-shell-b"] {
                try json("library/Web/\(name)/project.json", ["type": "web", "dependency": hostID])
            }
            try text("library/Web/\(hostID)/preview.png", "host preview survives row projection")
            try json("library/Web/transitive-shell/project.json", ["type": "web", "dependency": "49042"])
            try json("library/Web/49042/project.json", ["type": "web", "dependency": hostID])
            for (shell, host) in [("package-shell", packageID), ("video-shell", "49051"),
                                  ("loose-scene-shell", "49052"), ("scene-html-shell", "49061"),
                                  ("video-html-shell", "49062"), ("priority-shell", "49063"),
                                  ("fallback-shell", "49064"), ("relocated-shell", "49065"),
                                  ("browser-scene-shell", "49066"), ("ghost-host-shell", "49067"),
                                  ("managed-shell", managedID)] {
                try json("library/Web/\(shell)/project.json", ["type": "web", "dependency": host])
            }
            try text("library/Web/49051/clip.mp4", "admitted video without HTML")
            try json("library/Scene/49052/project.json", ["type": "scene", "file": "scene.json"])
            try text("library/Scene/49052/scene.json", "{}")
            try json("library/Web/49061/project.json", ["type": "scene", "file": "scene.json"])
            try text("library/Web/49061/scene.json", "{}")
            try text("library/Web/49061/index.html", "Scene-labelled host with HTML")
            try json("library/Web/49062/project.json", ["type": "video", "file": "clip.mp4"])
            try text("library/Web/49062/clip.mp4", "video-labelled host")
            try text("library/Web/49062/index.html", "Video-labelled host with HTML")
            try text("library/Web/49063/clip.mp4", "admitted Web-root host without HTML")
            try text("library/Scene/49063/index.html", "must not replace admitted Web-root host")
            try json("library/Web/49064/project.json", ["type": "web", "file": "missing.html"])
            try text("library/Scene/49064/index.html", "actual Scene-root fallback")
            try text("library/Web/49065/index.html", "unselected root alias")
            try json("library/Web/relocated-host/project.json", ["type": "web", "file": "index.html"])
            try text("library/Web/relocated-host/index.html", "metadata-selected actual host")
            try put("library/Web/49065/.mywallpaperx-steam-metadata.json",
                    JSONEncoder().encode(snapshot("49065", folder: directory("relocated-host"))))
            try json("library/Web/49066/project.json", ["file": "authored.json"])
            try text("library/Web/49066/authored.json", "browser Scene classification admits actual loose entry")
            try json("library/Web/49067/project.json", ["type": "web", "file": "missing.html"])
            try json("library/Web/self-shell/project.json", ["type": "web", "dependency": "self-shell"])
            try json("library/Web/\(managedID)/project.json", ["type": "web", "file": "alias.html"])
            try text("library/Web/\(managedID)/alias.html", "<html>unselected legacy alias</html>")
            try put("library/.mywallpaperx-steam-versions/\(compatibilityName)/content/project.json",
                    JSONSerialization.data(withJSONObject: ["type": "web", "file": "index.html"]))
            try text("library/.mywallpaperx-steam-versions/\(compatibilityName)/content/index.html", "<html>managed source</html>")
            try json("library/Web/escape-web/project.json", ["type": "web", "file": "escape.html"])
            try text("outside.html", "owned out-of-root HTML must not be selected")
            try fm.createSymbolicLink(at: directory("escape-web").appendingPathComponent("escape.html"),
                                      withDestinationURL: root.appendingPathComponent("outside.html"))
            try text("library/Web/exported-video/source.mov", "owned original video path")
            try text("library/Exports/exported.mov", "owned current exported video path")
            let exported = snapshot("exported-video", folder: directory("exported-video"), source: "source.mov",
                                    exported: library.appendingPathComponent("Exports/exported.mov"))
            try put("library/Web/exported-video/.mywallpaperx-steam-metadata.json", JSONEncoder().encode(exported))
            print("{\"setup\":true}")
            return
        }
        if mode == "mutate" {
            for path in ["library/Web/project-web/nested/preferred.htm", "library/Web/metadata-video/clips/picked.mov",
                         "library/Web/\(hostID)/index.html", "library/Exports/exported.mov"] {
                try fm.removeItem(at: root.appendingPathComponent(path))
            }
            print("{\"mutation\":true}")
            return
        }
        precondition(mode == "initial" || mode == "changed")
        let changed = mode == "changed"
        let context = SteamWorkshopInstalledLibraryScanContext(libraryRoot: library, fallbackLibraryRoot: library,
            videoRoot: library.appendingPathComponent("Video"), webRoot: web, sceneRoot: scene,
            metadataIndexDirectory: metadataIndex, fallbackItemsByID: ["49066": item("49066", workshopType: "Scene")])
        var checks: [String: Bool] = [:], workChecks: [String: Bool] = [:]
        var records: [String: Any] = [:], observations: [String: [[String: String]]] = [:]
        func recordValue(_ record: SteamWorkshopDownloadRecord?) throws -> Any {
            guard let record else { return NSNull() }
            func path(_ value: URL?) -> Any { value.map { $0.absoluteString as Any } ?? NSNull() }
            func date(_ value: Date?) -> Any { value.map { $0.timeIntervalSince1970 as Any } ?? NSNull() }
            let browser: Any = try record.browserItem.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
            let dependency: [String: String]
            switch record.dependencyStatus {
            case .none: dependency = ["status": "none"]
            case .available(let id): dependency = ["status": "available", "itemID": id]
            case .missing(let id): dependency = ["status": "missing", "itemID": id]
            }
            let status: String
            switch record.status {
            case .queued: status = "queued"
            case .downloading: status = "downloading"
            case .ready: status = "ready"
            case .failed(let message): status = "failed:" + message
            }
            return ["id": record.id, "title": record.title, "description": record.description, "tags": record.tags,
                "folderURL": path(record.folderURL), "projectFileURL": path(record.projectFileURL),
                "ownEntryHTMLURL": path(record.ownEntryHTMLURL), "dependencyHostEntryHTMLURL": path(record.dependencyHostEntryHTMLURL),
                "dependencyHostFolderURL": path(record.dependencyHostFolderURL), "entryHTMLURL": path(record.entryHTMLURL),
                "resolvedWebRootURL": path(record.resolvedWebRootURL), "previewURL": path(record.previewURL),
                "sourceVideoURL": path(record.sourceVideoURL), "exportedVideoURL": path(record.exportedVideoURL),
                "updatedAt": record.updatedAt.timeIntervalSince1970, "sizeText": record.sizeText, "status": status,
                "browserItem": browser, "contentType": record.contentType.rawValue,
                "dependencyItemID": record.dependencyItemID.map { $0 as Any } ?? NSNull(),
                "dependencyStatus": dependency, "createdAt": date(record.createdAt),
                "sizeBytes": record.sizeBytes.map { $0 as Any } ?? NSNull(),
                "intentAccountSteamID": record.intentAccountSteamID.map { $0 as Any } ?? NSNull()] as [String: Any]
        }
        func build(_ name: String, folder: String? = nil,
                   managed: [String: SteamWorkshopDownloadMetadataSnapshot] = [:],
                   from metadata: SteamWorkshopDownloadMetadataSnapshot? = nil) throws -> SteamWorkshopDownloadRecord? {
            _ = LegacyDiscoveryObservation.shared.take()
            let record: SteamWorkshopDownloadRecord?
            if let metadata {
                record = SteamWorkshopService.scanBuildInstalledRecord(from: metadata,
                    legacyDirectory: directory(folder ?? name), fallbackProject: nil,
                    fallbackIdentifier: name, resolvingIDs: [], managedSnapshots: managed, context: context)
            } else {
                record = SteamWorkshopService.scanBuildInstalledRecord(at: directory(folder ?? name),
                    resolvingIDs: [], managedSnapshots: managed, context: context)
            }
            records[name] = try recordValue(record)
            observations[name] = LegacyDiscoveryObservation.shared.take()
            return record
        }
        func samePath(_ lhs: URL?, _ rhs: URL) -> Bool {
            lhs?.resolvingSymlinksInPath().standardizedFileURL.path == rhs.resolvingSymlinksInPath().standardizedFileURL.path
        }
        func count(_ name: String, _ kind: String, at directory: URL? = nil) -> Int {
            (observations[name] ?? []).filter { $0["kind"] == kind && (directory == nil || $0["directory"] == directory!.path) }.count
        }
        let authored = try build("project-web")
        checks["projectPreferredHTMLAndPreviewSurvive"] = authored?.title == "Authored title"
            && authored?.description == "Authored description" && authored?.tags == ["authored"]
            && samePath(authored?.entryHTMLURL, directory("project-web").appendingPathComponent(changed ? "index.html" : "nested/preferred.htm"))
            && samePath(authored?.previewURL, directory("project-web").appendingPathComponent("preview.png"))
            && authored?.contentType == .web
        let loose = try build("project-scene")
        checks["projectSceneKeepsLooseEntry"] = loose?.contentType == .scene && loose?.status == .ready
        let metadata = try build("metadata-video")
        checks["metadataKeepsSourceAndBrowserFields"] = metadata?.title == "Browser metadata-video"
            && metadata?.browserItem == item("metadata-video") && metadata?.createdAt == fixedDate
            && samePath(metadata?.sourceVideoURL, directory("metadata-video").appendingPathComponent(changed ? "big.mp4" : "clips/picked.mov"))
        checks["packageOnlyRemainsScene"] = try build(packageID)?.contentType == .scene
        let htmlOnly = try build("html-only")
        checks["HTMLOnlyDirectoryStillDiscovered"] = htmlOnly?.contentType == .web
            && samePath(htmlOnly?.entryHTMLURL, directory("html-only").appendingPathComponent("index.html"))
        let videoOnly = try build("video-only")
        checks["videoOnlyDirectoryStillDiscovered"] = videoOnly?.contentType == .video
            && samePath(videoOnly?.sourceVideoURL, directory("video-only").appendingPathComponent("clip.mp4"))
        checks["emptyDirectoryStaysAbsent"] = try build("empty") == nil
        checks["projectGhostStaysAbsent"] = try build("project-ghost") == nil
        checks["metadataGhostStaysAbsent"] = try build("metadata-ghost") == nil
        checks["directoryNamedPackageStaysAbsent"] = try build("package-ghost") == nil
        checks["malformedProjectStillFindsActualHTML"] = try build("malformed-project")?.contentType == .web
        let video = try build("preferred-video")
        checks["preferredVideoOutranksLargerAlternative"] = samePath(video?.sourceVideoURL, directory("preferred-video").appendingPathComponent("clips/wanted.mov"))
        let missingPreferred = try build("missing-preferred")
        checks["missingPreferredFallsBackToCurrentIndex"] = samePath(missingPreferred?.entryHTMLURL, directory("missing-preferred").appendingPathComponent("index.html"))
        let shell = try build("shell")
        checks["dependencyShellKeepsHostAndStatus"] = shell?.dependencyItemID == hostID && shell?.ownEntryHTMLURL == nil
            && (changed ? shell?.dependencyStatus == .missing(itemID: hostID) && shell?.entryHTMLURL == nil
                : shell?.dependencyStatus == .available(itemID: hostID)
                    && samePath(shell?.entryHTMLURL, directory(hostID).appendingPathComponent("index.html"))
                    && samePath(shell?.resolvedWebRootURL, directory(hostID)))
        let missingShell = try build("missing-shell")
        checks["missingDependencyKeepsLocalShell"] = missingShell?.status == .ready
            && missingShell?.dependencyStatus == .missing(itemID: "49999") && missingShell?.entryHTMLURL == nil
        let cycle = try build("49021")
        checks["dependencyCycleStopsWithoutInventingEntry"] = cycle?.status == .ready
            && cycle?.dependencyStatus == .missing(itemID: "49022") && cycle?.entryHTMLURL == nil
        let managed = snapshot(managedID, folder: managedRoot, commit: managedCommit)
        let selected = try build("managed", folder: managedID, managed: [managedID: managed])
        checks["managedSnapshotReturnsBeforeLegacyProbe"] = SteamWorkshopLibraryTransaction.isAvailable(managedCommit, libraryRoot: library)
            && samePath(selected?.folderURL, managedRoot) && samePath(selected?.entryHTMLURL, managedRoot.appendingPathComponent("index.html"))
        var removedCommit = managedCommit; removedCommit.removed = true
        checks["removedManagedSnapshotDoesNotReviveAlias"] = try build("removed-managed", folder: managedID,
            managed: [managedID: snapshot(managedID, folder: managedRoot, commit: removedCommit)]) == nil
        checks["managedWithoutCommitDoesNotReviveAlias"] = try build("uncommitted-managed", folder: managedID,
            managed: [managedID: snapshot(managedID, folder: managedRoot)]) == nil
        checks["outsideHTMLSymlinkRemainsUnavailable"] = try build("escape-web") == nil
        let exported = try build("exported-video")
        checks["exportedVideoUsesCurrentExistingFile"] = changed
            ? exported?.exportedVideoURL == nil && samePath(exported?.sourceVideoURL, directory("exported-video").appendingPathComponent("source.mov"))
            : samePath(exported?.exportedVideoURL, library.appendingPathComponent("Exports/exported.mov"))
        let sharedA = try build("shared-shell-a"), sharedB = try build("shared-shell-b")
        let transitive = try build("transitive-shell")
        let publishedHost = try build("published-host", folder: hostID)
        checks["sharedHostRowsAndTransitiveEntryStayIdentical"] = [sharedA, sharedB, transitive].allSatisfy { row in
            guard let row, let dependencyID = row.dependencyItemID else { return false }
            return row.dependencyStatus == (changed ? .missing(itemID: dependencyID) : .available(itemID: dependencyID))
                && (changed ? row.entryHTMLURL == nil
                    : samePath(row.entryHTMLURL, directory(hostID).appendingPathComponent("index.html")))
        } && samePath(transitive?.dependencyHostFolderURL, directory("49042"))
        var admittedNoHTML = true
        for (name, expectedRoot) in [("package-shell", directory(packageID)),
                                     ("video-shell", directory("49051")),
                                     ("loose-scene-shell", scene.appendingPathComponent("49052"))] {
            let row = try build(name)
            admittedNoHTML = admittedNoHTML
                && row?.dependencyStatus == .missing(itemID: row?.dependencyItemID ?? "")
                && row?.entryHTMLURL == nil && samePath(row?.dependencyHostFolderURL, expectedRoot)
        }
        checks["admittedHostsWithoutHTMLKeepTheirFolders"] = admittedNoHTML
        let sceneHTML = try build("scene-html-shell"), videoHTML = try build("video-html-shell")
        let actualSceneHost = try build("scene-html-host", folder: "49061")
        let actualVideoHost = try build("video-html-host", folder: "49062")
        checks["declaredSceneAndVideoCanStillHostHTML"] = actualSceneHost?.contentType == .scene
            && actualVideoHost?.contentType == .video
            && samePath(sceneHTML?.entryHTMLURL, directory("49061").appendingPathComponent("index.html"))
            && samePath(videoHTML?.entryHTMLURL, directory("49062").appendingPathComponent("index.html"))
        let priority = try build("priority-shell"), fallback = try build("fallback-shell")
        checks["admittedWebRootOutranksSceneAndGhostFallsThrough"] = priority?.entryHTMLURL == nil
            && samePath(priority?.dependencyHostFolderURL, directory("49063"))
            && samePath(fallback?.entryHTMLURL, scene.appendingPathComponent("49064/index.html"))
            && samePath(fallback?.dependencyHostFolderURL, scene.appendingPathComponent("49064"))
        let relocated = try build("relocated-shell")
        checks["metadataSelectedHostRootOutranksAlias"] = samePath(relocated?.dependencyHostFolderURL, directory("relocated-host"))
            && samePath(relocated?.entryHTMLURL, directory("relocated-host").appendingPathComponent("index.html"))
        let browserScene = try build("browser-scene-shell")
        checks["browserClassificationStillAdmitsLooseSceneHost"] = browserScene?.entryHTMLURL == nil
            && samePath(browserScene?.dependencyHostFolderURL, directory("49066"))
        let managedShell = try build("managed-shell", managed: [managedID: managed])
        let removedShell = try build("removed-managed-shell", folder: "managed-shell",
            managed: [managedID: snapshot(managedID, folder: managedRoot, commit: removedCommit)])
        let uncommittedShell = try build("uncommitted-managed-shell", folder: "managed-shell",
            managed: [managedID: snapshot(managedID, folder: managedRoot)])
        checks["managedDependencyKeepsCommitAndNoAliasRules"] = samePath(managedShell?.dependencyHostFolderURL, managedRoot)
            && samePath(managedShell?.entryHTMLURL, managedRoot.appendingPathComponent("index.html"))
            && [removedShell, uncommittedShell].allSatisfy { $0?.entryHTMLURL == nil && $0?.dependencyHostFolderURL == nil }
        let ghostHost = try build("ghost-host-shell"), selfHost = try build("self-shell")
        checks["ghostAndSelfDependencyDoNotInventHosts"] = [ghostHost, selfHost].allSatisfy {
            $0?.status == .ready && $0?.entryHTMLURL == nil && $0?.dependencyHostFolderURL == nil
        }
        let directMetadata = try build("direct-metadata", folder: "empty",
            from: snapshot("metadata-video", folder: directory("metadata-video"), source: "clips/picked.mov"))
        checks["directMetadataBuilderKeepsSelectedRootAndFields"] = directMetadata?.id == "metadata-video"
            && directMetadata?.browserItem == item("metadata-video") && directMetadata?.createdAt == fixedDate
            && samePath(directMetadata?.folderURL, directory("metadata-video"))
            && samePath(directMetadata?.sourceVideoURL,
                        directory("metadata-video").appendingPathComponent(changed ? "big.mp4" : "clips/picked.mov"))
        let expectedBytes = try fm.contentsOfDirectory(at: directory("project-web"), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "nested" }.reduce(Int64(0)) { partial, url in
                partial + Int64((try fm.attributesOfItem(atPath: url.path)[.size] as! NSNumber).int64Value)
            } + (changed ? 0 : Int64(Data("<html>preferred</html>".utf8).count))
        checks["recordBytesAndDatesArePreparedFromRealInputs"] = authored?.sizeBytes == expectedBytes
            && authored?.createdAt != nil && (authored?.updatedAt.timeIntervalSince1970 ?? 0) > 0
        let marked = ["project-web", "project-scene", packageID, "project-ghost", "metadata-ghost", "package-ghost",
                      "malformed-project", "preferred-video", "missing-preferred", "escape-web"]
        workChecks["markedDirectoriesHaveOnlyActualResolverCalls"] = marked.allSatisfy { count($0, "HTML") == 1 && count($0, "Video") == 1 }
        workChecks["HTMLOnlySkipsUnusedVideoPreflight"] = count("html-only", "HTML") == 2 && count("html-only", "Video") == 1
        workChecks["videoOnlyRetainsNecessaryDiscovery"] = count("video-only", "HTML") == 2 && count("video-only", "Video") == 2
        workChecks["emptyRetainsNecessaryDiscovery"] = count("empty", "HTML") == 1 && count("empty", "Video") == 1
        workChecks["metadataSourceAvoidsVideoDiscoveryUntilMissing"] = count("metadata-video", "HTML") == 1
            && count("metadata-video", "Video") == (changed ? 1 : 0)
        workChecks["managedAliasNeverProbesLegacyDirectory"] = count("managed", "HTML", at: directory(managedID)) == 0
            && count("managed", "Video", at: directory(managedID)) == 0
            && observations["removed-managed"]?.isEmpty == true && observations["uncommitted-managed"]?.isEmpty == true
        let preferredCalls = (observations["project-web"] ?? []).filter { $0["kind"] == "HTML" || $0["kind"] == "Video" }
        workChecks["preferredNameReachesActualResolvers"] = preferredCalls.count == 2
            && preferredCalls.allSatisfy { $0["preferred"] == "nested/preferred.htm" }
        workChecks["dependencyHostStillResolvesOnce"] = count("shell", "HTML", at: directory(hostID)) == 1
            && count("shell", "Video", at: directory(hostID)) == 1
        workChecks["markerExistsShortCircuitsInOrder"] = ["project-web", "project-ghost", "malformed-project"].allSatisfy {
            count($0, "exists-project") == 1 && count($0, "exists-metadata") == 0 && count($0, "exists-package") == 0
        } && ["metadata-video", "metadata-ghost"].allSatisfy {
            count($0, "exists-project") == 1 && count($0, "exists-metadata") == 1 && count($0, "exists-package") == 0
        } && [packageID, "html-only", "video-only", "empty"].allSatisfy {
            count($0, "exists-project") == 1 && count($0, "exists-metadata") == 1 && count($0, "exists-package") == 1
        }
        workChecks["dependencyEdgesDoNotProjectHostRows"] = ["shell", "shared-shell-a", "shared-shell-b"].allSatisfy {
            count($0, "Preview", at: directory(hostID)) == 0 && count($0, "Statistics", at: directory(hostID)) == 0
                && count($0, "Statistics") == 1
        }
        workChecks["publishedHostStillProjectsAllDisplayFields"] = changed
            ? publishedHost == nil && count("published-host", "Preview") == 0 && count("published-host", "Statistics") == 0
            : samePath(publishedHost?.previewURL, directory(hostID).appendingPathComponent("preview.png"))
                && publishedHost?.sizeBytes != nil && publishedHost?.createdAt != nil
                && count("published-host", "Preview") == 1 && count("published-host", "Statistics") == 1
        workChecks["transitiveEdgesDoNotProjectIntermediateRows"] = [directory("49042"), directory(hostID)].allSatisfy {
            count("transitive-shell", "Preview", at: $0) == 0 && count("transitive-shell", "Statistics", at: $0) == 0
        } && count("transitive-shell", "Statistics") == 1
        print(String(data: try JSONSerialization.data(withJSONObject: ["phase": mode, "checks": checks,
            "workChecks": workChecks, "records": records, "resolverCalls": observations], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
