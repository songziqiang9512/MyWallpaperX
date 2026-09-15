//
//  SteamWorkshopService+LibraryRecords.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    nonisolated static func loadWorkshopProject(from projectFileURL: URL?) -> SteamWorkshopProject? {
        guard let projectFileURL,
              FileManager.default.fileExists(atPath: projectFileURL.path),
              let data = try? Data(contentsOf: projectFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(SteamWorkshopProject.self, from: data)
    }

    nonisolated static func loadWorkshopProjectRoot(from projectFileURL: URL?) -> [String: Any]? {
        guard let projectFileURL,
              FileManager.default.fileExists(atPath: projectFileURL.path),
              let data = try? Data(contentsOf: projectFileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return nil
        }
        return root
    }

    nonisolated static func detailCacheDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("ItemDetails", isDirectory: true)
    }

    nonisolated static func detailCacheFileURL(id: String) -> URL {
        detailCacheDirectoryURL().appendingPathComponent("\(id).json")
    }

    nonisolated static func legacyDownloadMetadataFileURL(for directory: URL) -> URL {
        directory.appendingPathComponent(".mywallpaperx-steam-metadata.json")
    }

    nonisolated static func preferredPreviewRelativePath(
        in directory: URL,
        project: SteamWorkshopProject?,
        projectRoot: [String: Any]?
    ) -> String? {
        let fileManager = FileManager.default

        func normalizedRelativePath(_ rawPath: String?) -> String? {
            guard let rawPath else { return nil }
            let normalized = rawPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
            return normalized.isEmpty ? nil : normalized
        }

        func existingRelativePath(_ rawPath: String?) -> String? {
            guard let relativePath = normalizedRelativePath(rawPath) else { return nil }
            let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
            let candidate = directory.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
            guard candidate.path.hasPrefix(root + "/") else { return nil }
            return fileManager.fileExists(atPath: candidate.path) ? relativePath : nil
        }

        func staticSiblingPath(for relativePath: String) -> String? {
            let baseURL = URL(fileURLWithPath: relativePath)
            let directoryPath = baseURL.deletingLastPathComponent().path == "."
                ? ""
                : baseURL.deletingLastPathComponent().path
            let baseName = baseURL.deletingPathExtension().lastPathComponent
            let extensions = ["png", "jpg", "jpeg", "webp"]
            for pathExtension in extensions {
                let fileName = "\(baseName).\(pathExtension)"
                let sibling = directoryPath.isEmpty ? fileName : "\(directoryPath)/\(fileName)"
                if let existing = existingRelativePath(sibling) {
                    return existing
                }
            }
            return nil
        }

        func firstStaticPresetImagePath() -> String? {
            guard let preset = projectRoot?["preset"] as? [String: Any] else { return nil }
            let preferredKeys = [
                "backgroundimageb",
                "backgroundimage",
                "background_image",
                "foreground_image",
                "image",
                "bgimage"
            ]
            for key in preferredKeys {
                guard let rawValue = preset[key] else { continue }
                let path: String?
                if let stringValue = rawValue as? String {
                    path = stringValue
                } else {
                    path = nil
                }
                guard let relativePath = existingRelativePath(path) else { continue }
                let pathExtension = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
                if pathExtension != "gif" {
                    return relativePath
                }
            }
            return nil
        }

        if let declaredPreview = existingRelativePath(project?.preview) {
            return declaredPreview
        }

        let stillCandidates = ["preview.png", "preview.jpg", "preview.jpeg", "preview.webp"]
        for candidate in stillCandidates {
            if let existing = existingRelativePath(candidate) {
                return existing
            }
        }

        if let presetImage = firstStaticPresetImagePath() {
            return presetImage
        }

        if let animatedFallback = existingRelativePath("preview.gif") {
            return animatedFallback
        }

        return nil
    }

    func downloadMetadataIndexDirectoryURL() -> URL {
        libraryRootURL.appendingPathComponent(".mywallpaperx-steam-metadata", isDirectory: true)
    }

    func downloadMetadataFileURL(for itemID: String) -> URL {
        downloadMetadataIndexDirectoryURL().appendingPathComponent("\(itemID).json")
    }

    nonisolated static func loadDetailCache(id: String) -> SteamWorkshopBrowserItem? {
        let url = detailCacheFileURL(id: id)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDetailCacheSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.fetchedAt) < Constants.detailCacheTTL else {
            return nil
        }
        return snapshot.item
    }

    nonisolated static func saveDetailCache(item: SteamWorkshopBrowserItem) {
        let snapshot = SteamWorkshopDetailCacheSnapshot(fetchedAt: Date(), item: item)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = detailCacheDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: detailCacheFileURL(id: item.id), options: [.atomic])
    }

    func buildInstalledRecord(at directory: URL, resolvingIDs: Set<String> = [],
                              managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot]? = nil) -> SteamWorkshopDownloadRecord? {
        let managed = managedSnapshots ?? managedDownloadSnapshots()
        if let snapshot = managed[directory.lastPathComponent] {
            guard let commit = snapshot.commit,
                  SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: steamDownloadLibraryRootURL) else { return nil }
            return buildInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                fallbackProject: nil, fallbackIdentifier: snapshot.item.id, resolvingIDs: resolvingIDs, managedSnapshots: managed)
        }
        let projectURL = directory.appendingPathComponent("project.json")
        let metadataURL = Self.legacyDownloadMetadataFileURL(for: directory)
        let hasProject = FileManager.default.fileExists(atPath: projectURL.path)
        let hasMetadata = FileManager.default.fileExists(atPath: metadataURL.path)
        let hasScenePackage = FileManager.default.fileExists(atPath: directory.appendingPathComponent("scene.pkg").path)
        let hasHTML = resolveHTMLURL(in: directory, preferredFileName: nil) != nil
        let hasVideo = resolveVideoURL(in: directory, preferredFileName: nil) != nil
        guard hasProject || hasMetadata || hasScenePackage || hasHTML || hasVideo else {
            return nil
        }
        let project = Self.loadWorkshopProject(from: projectURL)
        let identifier = directory.lastPathComponent
        let metadata = loadDownloadMetadataSnapshot(legacyDirectory: directory, id: identifier)
        return buildInstalledRecord(
            from: metadata,
            legacyDirectory: directory,
            fallbackProject: project,
            fallbackIdentifier: identifier,
            resolvingIDs: resolvingIDs, managedSnapshots: managed
        )
    }

    func resolveVideoURL(in directory: URL, preferredFileName: String?) -> URL? {
        let candidates = videoFileCandidates(in: directory)
        guard !candidates.isEmpty else { return nil }

        if let preferredFileName {
            let normalizedPreferredPath = preferredFileName
                .replacingOccurrences(of: "\\", with: "/")
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedPreferredPath.isEmpty {
                if let exactMatch = candidates.first(where: {
                    relativePath(for: $0, under: directory).lowercased() == normalizedPreferredPath
                }) {
                    return exactMatch
                }

                let preferredBaseName = URL(fileURLWithPath: normalizedPreferredPath).lastPathComponent
                if let namedMatch = candidates.first(where: {
                    $0.lastPathComponent.caseInsensitiveCompare(preferredBaseName) == .orderedSame
                }) {
                    return namedMatch
                }
            }
        }

        return candidates.max { lhs, rhs in
            let lhsSize = ((try? lhs.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            let rhsSize = ((try? rhs.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            if lhsSize != rhsSize {
                return lhsSize < rhsSize
            }

            let lhsRelativePath = relativePath(for: lhs, under: directory)
            let rhsRelativePath = relativePath(for: rhs, under: directory)
            let lhsDepth = lhsRelativePath.split(separator: "/").count
            let rhsDepth = rhsRelativePath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth > rhsDepth
            }
            return lhsRelativePath.localizedStandardCompare(rhsRelativePath) == .orderedDescending
        }
    }

    func resolveHTMLURL(in directory: URL, preferredFileName: String?) -> URL? {
        let supportedExtensions = Set(["html", "htm"])
        let normalizedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL

        func resolvedContainedHTMLURL(_ candidate: URL) -> URL? {
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            let rootPath = normalizedDirectory.path
            guard resolvedCandidate.path.hasPrefix(rootPath + "/"),
                  supportedExtensions.contains(resolvedCandidate.pathExtension.localizedLowercase),
                  FileManager.default.fileExists(atPath: resolvedCandidate.path) else {
                return nil
            }
            let isRegularFile = (try? resolvedCandidate.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? true
            return isRegularFile ? resolvedCandidate : nil
        }

        let candidateURLs: [URL]

        if let preferredFileName {
            let normalizedPreferredPath = preferredFileName
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedPreferredPath.isEmpty {
                let directCandidate = normalizedDirectory.appendingPathComponent(normalizedPreferredPath)
                if let directCandidate = resolvedContainedHTMLURL(directCandidate) {
                    return directCandidate
                }
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: normalizedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        candidateURLs = enumerator.compactMap { element in
            guard let url = element as? URL else { return nil }
            return resolvedContainedHTMLURL(url)
        }

        return candidateURLs.sorted { lhs, rhs in
            let lhsRelativePath = relativePath(for: lhs, under: normalizedDirectory)
            let rhsRelativePath = relativePath(for: rhs, under: normalizedDirectory)
            let lhsLower = lhsRelativePath.localizedLowercase
            let rhsLower = rhsRelativePath.localizedLowercase

            func entryPriority(for relativePath: String) -> Int {
                let normalized = relativePath.localizedLowercase
                if normalized == "index.html" || normalized == "index.htm" { return 0 }
                if normalized.hasSuffix("/index.html") || normalized.hasSuffix("/index.htm") { return 1 }
                if normalized == "default.html" || normalized == "default.htm" { return 2 }
                if normalized.contains("/ui/") || normalized.contains("/assets/") || normalized.contains("/preview") { return 5 }
                return 3
            }

            let lhsPriority = entryPriority(for: lhsRelativePath)
            let rhsPriority = entryPriority(for: rhsRelativePath)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            let lhsDepth = lhsRelativePath.split(separator: "/").count
            let rhsDepth = rhsRelativePath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }

            return lhsLower.localizedStandardCompare(rhsLower) == .orderedAscending
        }.first
    }

    func resolveContentType(
        project: SteamWorkshopProject?,
        directory: URL?,
        videoURL: URL?,
        htmlURL: URL?,
        dependencyItemID: String?,
        browserItem: SteamWorkshopBrowserItem?
    ) -> SteamWorkshopDownloadContentType {
        if let sceneContentType = resolveSceneContentType(
            project: project,
            directory: directory,
            browserItem: browserItem
        ) {
            return sceneContentType
        }

        let normalizedProjectType = project?.type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        let declaredEntryPath = project?.file?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let declaredEntryExtension = declaredEntryPath?
            .components(separatedBy: "/")
            .last?
            .components(separatedBy: ".")
            .last?
            .localizedLowercase
        let hasWebProperties = project?.general?.hasProperties == true
        let hasDependency = dependencyItemID != nil
        let htmlExists = htmlURL != nil
        let videoExists = videoURL != nil
        let declaredEntryLooksLikeWeb = declaredEntryExtension == "html" || declaredEntryExtension == "htm"
        let browserDeclaresWeb = browserItem?.workshopTypeText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Web") == .orderedSame
            || (browserItem?.tags.contains(where: { $0.localizedCaseInsensitiveCompare("Web") == .orderedSame }) ?? false)
        if normalizedProjectType == "web" {
            return .web
        }
        if declaredEntryLooksLikeWeb {
            return .web
        }
        if browserDeclaresWeb, hasDependency {
            return .web
        }
        if htmlExists, hasWebProperties {
            return .web
        }
        if hasDependency,
           hasWebProperties {
            return .web
        }
        if htmlExists,
           videoExists,
           hasWebProperties {
            return .web
        }
        if htmlExists,
           normalizedProjectType == nil || normalizedProjectType?.isEmpty == true,
           videoExists == false {
            return .web
        }
        if videoExists {
            return .video
        }
        if htmlExists {
            return .web
        }
        return .unknown
    }

    func upsertTransientRecord(
        id: String,
        title: String,
        status: SteamWorkshopDownloadRecord.Status,
        sizeText: String? = nil
    ) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let previous = downloads[index]
            downloads[index] = SteamWorkshopDownloadRecord(
                id: id,
                title: previous.title,
                description: previous.description,
                tags: previous.tags,
                folderURL: previous.folderURL,
                projectFileURL: previous.projectFileURL,
                ownEntryHTMLURL: previous.ownEntryHTMLURL,
                dependencyHostEntryHTMLURL: previous.dependencyHostEntryHTMLURL,
                dependencyHostFolderURL: previous.dependencyHostFolderURL,
                entryHTMLURL: previous.entryHTMLURL,
                resolvedWebRootURL: previous.resolvedWebRootURL,
                previewURL: previous.previewURL,
                sourceVideoURL: previous.sourceVideoURL,
                exportedVideoURL: previous.exportedVideoURL,
                updatedAt: Date(),
                sizeText: sizeText ?? previous.sizeText,
                status: status,
                browserItem: previous.browserItem,
                contentType: previous.contentType,
                dependencyItemID: previous.dependencyItemID,
                dependencyStatus: previous.dependencyStatus
            )
            return
        }

        downloads.insert(
            SteamWorkshopDownloadRecord(
                id: id,
                title: title,
                description: "",
                tags: [],
                folderURL: libraryRootURL,
                projectFileURL: nil,
                ownEntryHTMLURL: nil,
                dependencyHostEntryHTMLURL: nil,
                dependencyHostFolderURL: nil,
                entryHTMLURL: nil,
                resolvedWebRootURL: nil,
                previewURL: nil,
                sourceVideoURL: nil,
                exportedVideoURL: nil,
                updatedAt: Date(),
                sizeText: sizeText ?? "等待下载",
                status: status,
                browserItem: browserItemForDownload(id: id),
                contentType: .unknown,
                dependencyItemID: nil,
                dependencyStatus: .none
            ),
            at: 0
        )
    }

    func buildInstalledRecord(
        from metadata: SteamWorkshopDownloadMetadataSnapshot?,
        legacyDirectory: URL?,
        fallbackProject: SteamWorkshopProject?,
        fallbackIdentifier: String,
        resolvingIDs: Set<String> = [],
        managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot]? = nil
    ) -> SteamWorkshopDownloadRecord? {
        let identifier = metadata?.item.id ?? fallbackIdentifier
        guard !resolvingIDs.contains(identifier) else { return nil }
        let resolving = resolvingIDs.union([identifier])
        let managed = managedSnapshots ?? managedDownloadSnapshots()
        let resolvedLegacyDirectory: URL? = {
            if let legacyFolderURL = metadata?.legacyFolderURL,
               FileManager.default.fileExists(atPath: legacyFolderURL.path) {
                return legacyFolderURL
            }
            if let legacyDirectory,
               FileManager.default.fileExists(atPath: legacyDirectory.path) {
                return legacyDirectory
            }
            return nil
        }()

        let projectFileURL = resolvedLegacyDirectory?.appendingPathComponent("project.json")
        let resolvedProject: SteamWorkshopProject? = {
            if let fallbackProject {
                return fallbackProject
            }
            return Self.loadWorkshopProject(from: projectFileURL)
        }()
        let projectRoot = Self.loadWorkshopProjectRoot(from: projectFileURL)
        let preferredPreviewRelativePath: String? = {
            guard let resolvedLegacyDirectory else { return nil }
            return Self.preferredPreviewRelativePath(
                in: resolvedLegacyDirectory,
                project: resolvedProject,
                projectRoot: projectRoot
            )
        }()

        let previewURL: URL? = {
            if let preferredPreviewRelativePath,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(preferredPreviewRelativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let previewRelativePath = metadata?.previewRelativePath,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(previewRelativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let preview = resolvedProject?.preview,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(preview)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }()

        let sourceVideoURL: URL? = {
            if let sourceVideoRelativePath = metadata?.sourceVideoRelativePath,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(sourceVideoRelativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let resolvedLegacyDirectory {
                return resolveVideoURL(in: resolvedLegacyDirectory, preferredFileName: resolvedProject?.file)
            }
            return nil
        }()

        let directEntryHTMLURL: URL? = {
            guard let resolvedLegacyDirectory else { return nil }
            return resolveHTMLURL(in: resolvedLegacyDirectory, preferredFileName: resolvedProject?.file)
        }()

        let dependencyItemID: String? = {
            guard let raw = resolvedProject?.dependency?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return nil
            }
            return raw
        }()

        let dependencyRecord: SteamWorkshopDownloadRecord? = {
            guard let dependencyItemID,
                  dependencyItemID != identifier else { return nil }
            if let snapshot = managed[dependencyItemID] {
                guard let commit = snapshot.commit,
                      SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: steamDownloadLibraryRootURL) else { return nil }
                return buildInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                    fallbackProject: nil, fallbackIdentifier: dependencyItemID, resolvingIDs: resolving, managedSnapshots: managed)
            }
            if let cachedRecord = latestDownloadRecord(for: dependencyItemID), cachedRecord.webEntryURL != nil {
                return cachedRecord
            }
            return buildInstalledRecord(at: webLibraryRootURL.appendingPathComponent(dependencyItemID, isDirectory: true),
                resolvingIDs: resolving, managedSnapshots: managed)
                ?? buildInstalledRecord(at: sceneLibraryRootURL.appendingPathComponent(dependencyItemID, isDirectory: true),
                    resolvingIDs: resolving, managedSnapshots: managed)
        }()

        let dependencyEntryHTMLURL = dependencyRecord?.webEntryURL
        let dependencyHostFolderURL = dependencyRecord?.folderURL.resolvingSymlinksInPath().standardizedFileURL
        let dependencyStatus: SteamWorkshopWebDependencyStatus = {
            guard let dependencyItemID else { return .none }
            if dependencyEntryHTMLURL != nil {
                return .available(itemID: dependencyItemID)
            }
            return .missing(itemID: dependencyItemID)
        }()

        let entryHTMLURL = directEntryHTMLURL ?? dependencyEntryHTMLURL
        let resolvedWebRootURL: URL? = {
            if directEntryHTMLURL != nil,
               let resolvedLegacyDirectory {
                return resolvedLegacyDirectory.resolvingSymlinksInPath().standardizedFileURL
            }
            if dependencyEntryHTMLURL != nil,
               let dependencyHostFolderURL {
                return dependencyHostFolderURL.resolvingSymlinksInPath().standardizedFileURL
            }
            guard let entryHTMLURL else { return nil }
            return entryHTMLURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .deletingLastPathComponent()
        }()

        let exportedVideoURL = metadata?.exportedVideoURL.flatMap { url in
            FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let effectiveVideoURL = exportedVideoURL ?? sourceVideoURL
        let browserItem = metadata?.item ?? browserItemForDownload(id: identifier)
        let contentType = resolveContentType(
            project: resolvedProject,
            directory: resolvedLegacyDirectory,
            videoURL: effectiveVideoURL,
            htmlURL: entryHTMLURL,
            dependencyItemID: dependencyItemID,
            browserItem: browserItem
        )
        let scenePkgURL: URL? = {
            guard let resolvedLegacyDirectory else { return nil }
            let candidate = resolvedLegacyDirectory.appendingPathComponent("scene.pkg")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }()
        guard metadata != nil || effectiveVideoURL != nil || entryHTMLURL != nil || dependencyItemID != nil || scenePkgURL != nil else {
            return nil
        }

        let updatedAt: Date = {
            if let effectiveVideoURL,
               let values = try? effectiveVideoURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate {
                return date
            }
            if let resolvedLegacyDirectory,
               let values = try? resolvedLegacyDirectory.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate {
                return date
            }
            return Date()
        }()

        let title = resolvedProject?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = resolvedProject?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = resolvedProject?.tags ?? []
        let sizeText = effectiveVideoURL.flatMap { fileSizeText(for: $0) }
            ?? entryHTMLURL.flatMap { fileSizeText(for: $0) }
            ?? "未知大小"

        let browserTitle = browserItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : (browserTitle.isEmpty ? "Workshop #\(identifier)" : browserTitle),
            description: description.isEmpty ? (browserItem?.descriptionText ?? "") : description,
            tags: tags.isEmpty ? (browserItem?.tags ?? []) : tags,
            folderURL: resolvedLegacyDirectory ?? effectiveVideoURL?.deletingLastPathComponent() ?? libraryRootURL,
            projectFileURL: projectFileURL,
            ownEntryHTMLURL: directEntryHTMLURL,
            dependencyHostEntryHTMLURL: dependencyEntryHTMLURL,
            dependencyHostFolderURL: dependencyHostFolderURL,
            entryHTMLURL: entryHTMLURL,
            resolvedWebRootURL: resolvedWebRootURL,
            previewURL: previewURL,
            sourceVideoURL: sourceVideoURL,
            exportedVideoURL: exportedVideoURL,
            updatedAt: updatedAt,
            sizeText: sizeText,
            status: .ready,
            browserItem: browserItem,
            contentType: contentType,
            dependencyItemID: dependencyItemID,
            dependencyStatus: dependencyStatus
        )
    }

    func browserItemForDownload(id: String) -> SteamWorkshopBrowserItem? {
        if let selectedBrowserItem, selectedBrowserItem.id == id {
            return selectedBrowserItem
        }
        if let browserItem = browserItems.first(where: { $0.id == id }) {
            return browserItem
        }
        return Self.loadDetailCache(id: id)
    }

    nonisolated static func creatorID(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.absoluteURL.pathComponents
        guard let profilesIndex = components.firstIndex(of: "profiles"),
              components.indices.contains(profilesIndex + 1) else {
            return nil
        }
        let candidate = components[profilesIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let value = UInt64(candidate), value != 0 else {
            return nil
        }
        return candidate
    }

    private func videoFileCandidates(in directory: URL) -> [URL] {
        let supportedExtensions = Set(["mp4", "webm", "mov", "m4v"])
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [URL] = []
        for case let candidate as URL in enumerator {
            guard supportedExtensions.contains(candidate.pathExtension.localizedLowercase) else { continue }
            let isRegularFile = (try? candidate.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? true
            guard isRegularFile else { continue }
            candidates.append(candidate)
        }

        return candidates.sorted {
            relativePath(for: $0, under: directory).localizedStandardCompare(relativePath(for: $1, under: directory)) == .orderedAscending
        }
    }

    private func relativePath(for fileURL: URL, under directory: URL) -> String {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(directoryPath) else {
            return fileURL.lastPathComponent
        }
        let suffix = filePath.dropFirst(directoryPath.count)
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func fileSizeText(for url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        return Self.fileSizeText(forBytes: size)
    }

    private func loadDownloadMetadataSnapshot(legacyDirectory: URL?, id: String) -> SteamWorkshopDownloadMetadataSnapshot? {
        if let entry = loadDownloadMetadataEntry(forItemID: id) {
            return entry.snapshot
        }

        if let legacyDirectory {
            let metadataURL = Self.legacyDownloadMetadataFileURL(for: legacyDirectory)
            if let data = try? Data(contentsOf: metadataURL),
               let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) {
                return snapshot
            }
        }

        guard let item = browserItemForDownload(id: id) else { return nil }
        return SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: .distantPast,
            item: item,
            sourceVideoRelativePath: nil,
            previewRelativePath: nil,
            exportedVideoURL: nil,
            legacyFolderURL: legacyDirectory
        )
    }
}
