//
//  SteamWorkshopService+LibraryRecords.swift
//  MyWallpaperX
//

import Foundation

/// Value snapshot of everything the installed-library record builders need
/// from service state. The scan runs off the main actor; instead of reading
/// service properties mid-scan it captures this once on the main actor.
nonisolated struct SteamWorkshopInstalledLibraryScanContext: Sendable {
    let libraryRoot: URL
    let fallbackLibraryRoot: URL
    let videoRoot: URL
    let webRoot: URL
    let sceneRoot: URL
    let metadataIndexDirectory: URL
    /// `selectedBrowserItem` first, then `browserItems` — the exact fallback
    /// order of the removed `browserItemForDownload` reads.
    let fallbackItemsByID: [String: SteamWorkshopBrowserItem]
}

/// Current source/admission facts shared by published rows and dependency edges.
/// Recursive edges never compute the display-only preview, dates or folder size.
private nonisolated struct SteamWorkshopInstalledRecordPreparation {
    let identifier: String
    let metadata: SteamWorkshopDownloadMetadataSnapshot?
    let directory: URL?
    let projectFileURL: URL?
    let project: SteamWorkshopProject?
    let folderURL: URL
    let sourceVideoURL: URL?
    let exportedVideoURL: URL?
    let ownEntryHTMLURL: URL?
    let dependencyHostEntryHTMLURL: URL?
    let dependencyHostFolderURL: URL?
    let entryHTMLURL: URL?
    let resolvedWebRootURL: URL?
    let browserItem: SteamWorkshopBrowserItem?
    let contentType: SteamWorkshopDownloadContentType
    let dependencyItemID: String?
    let dependencyStatus: SteamWorkshopWebDependencyStatus
}

extension SteamWorkshopService {
    nonisolated static func loadWorkshopProject(from projectFileURL: URL?) -> SteamWorkshopProject? {
        guard let projectFileURL,
              let data = try? Data(contentsOf: projectFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(SteamWorkshopProject.self, from: data)
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
        fallbackPath: String? = nil
    ) -> String? {
        let fileManager = FileManager.default
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path

        func normalizedRelativePath(_ rawPath: String?) -> String? {
            guard let rawPath else { return nil }
            let normalized = rawPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
            return normalized.isEmpty ? nil : normalized
        }

        func existingRelativePath(_ rawPath: String?) -> String? {
            guard let relativePath = normalizedRelativePath(rawPath) else { return nil }
            let candidate = directory.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
            guard candidate.path.hasPrefix(root + "/") else { return nil }
            return fileManager.fileExists(atPath: candidate.path) ? relativePath : nil
        }

        func firstStaticPresetImagePath() -> String? {
            for path in project?.presetImagePaths ?? [] {
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

        return existingRelativePath(fallbackPath)
    }

    func downloadMetadataIndexDirectoryURL() -> URL {
        libraryRootURL.appendingPathComponent(".mywallpaperx-steam-metadata", isDirectory: true)
    }

    func downloadMetadataFileURL(for itemID: String) -> URL {
        downloadMetadataIndexDirectoryURL().appendingPathComponent("\(itemID).json")
    }

    nonisolated static func loadDetailCache(id: String) -> SteamWorkshopBrowserItem? {
        loadDetailCacheSnapshot(id: id)?.item
    }

    nonisolated static func loadDetailCacheSnapshot(id: String) -> SteamWorkshopDetailCacheSnapshot? {
        let url = detailCacheFileURL(id: id)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDetailCacheSnapshot.self, from: data),
              snapshot.item.id == id,
              Date().timeIntervalSince(snapshot.fetchedAt) < Constants.detailCacheTTL else {
            return nil
        }
        return snapshot
    }

    nonisolated static func saveDetailCache(item: SteamWorkshopBrowserItem) {
        let snapshot = SteamWorkshopDetailCacheSnapshot(fetchedAt: Date(), item: item)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = detailCacheDirectoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: detailCacheFileURL(id: item.id), options: [.atomic])
        DispatchQueue.global(qos: .utility).async {
            Self.sweepExpiredDetailCaches()
        }
    }

    // Guarded by detailCacheSweepLock; sweepExpiredDetailCaches runs off the
    // main actor from a utility queue, so the lock is the sole synchronizer.
    private nonisolated static let detailCacheSweepLock = NSLock()
    private nonisolated(unsafe) static var lastDetailCacheSweepAt: Date?

    /// Expired detail-cache files were previously never deleted (the TTL was
    /// judged only at read time), so ItemDetails only grew until the user
    /// cleared caches manually. Writes now trigger a rate-limited sweep, the
    /// same pattern as ThumbnailCache's disk trim.
    nonisolated static func sweepExpiredDetailCaches(now: Date = Date()) {
        detailCacheSweepLock.lock()
        if let last = lastDetailCacheSweepAt, now.timeIntervalSince(last) < 60 {
            detailCacheSweepLock.unlock()
            return
        }
        lastDetailCacheSweepAt = now
        detailCacheSweepLock.unlock()
        let cutoff = now.timeIntervalSince1970 - Constants.detailCacheTTL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: detailCacheDirectoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where file.pathExtension.localizedLowercase == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Main-actor wrapper for the cold single-record paths (installedRecord
    /// lookups, dependency resolution outside the bulk scan). The bulk scan
    /// calls the static variant directly with its captured context.
    func buildInstalledRecord(at directory: URL, resolvingIDs: Set<String> = [],
                              managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot]? = nil) -> SteamWorkshopDownloadRecord? {
        Self.scanBuildInstalledRecord(
            at: directory,
            resolvingIDs: resolvingIDs,
            managedSnapshots: managedSnapshots ?? managedDownloadSnapshots(),
            context: installedLibraryScanContext()
        )
    }

    func buildInstalledRecord(from metadata: SteamWorkshopDownloadMetadataSnapshot?, legacyDirectory: URL?,
                              fallbackProject: SteamWorkshopProject?, fallbackIdentifier: String,
                              resolvingIDs: Set<String> = [],
                              managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot]? = nil) -> SteamWorkshopDownloadRecord? {
        Self.scanBuildInstalledRecord(
            from: metadata, legacyDirectory: legacyDirectory,
            fallbackProject: fallbackProject, fallbackIdentifier: fallbackIdentifier,
            resolvingIDs: resolvingIDs,
            managedSnapshots: managedSnapshots ?? managedDownloadSnapshots(),
            context: installedLibraryScanContext()
        )
    }

    func installedLibraryScanContext() -> SteamWorkshopInstalledLibraryScanContext {
        var fallbackItemsByID: [String: SteamWorkshopBrowserItem] = [:]
        for item in browserItems {
            fallbackItemsByID[item.id] = item
        }
        if let selectedBrowserItem {
            fallbackItemsByID[selectedBrowserItem.id] = selectedBrowserItem
        }
        return SteamWorkshopInstalledLibraryScanContext(
            libraryRoot: steamDownloadLibraryRootURL,
            fallbackLibraryRoot: libraryRootURL,
            videoRoot: videoLibraryRootURL,
            webRoot: webLibraryRootURL,
            sceneRoot: sceneLibraryRootURL,
            metadataIndexDirectory: downloadMetadataIndexDirectoryURL(),
            fallbackItemsByID: fallbackItemsByID
        )
    }

    nonisolated static func scanBuildInstalledRecord(at directory: URL, resolvingIDs: Set<String>,
                              managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot],
                              context: SteamWorkshopInstalledLibraryScanContext) -> SteamWorkshopDownloadRecord? {
        scanPrepareInstalledRecord(at: directory, resolvingIDs: resolvingIDs,
            managedSnapshots: managedSnapshots, context: context).map { scanProjectInstalledRecord($0) }
    }

    private nonisolated static func scanPrepareInstalledRecord(at directory: URL, resolvingIDs: Set<String>,
                              managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot],
                              context: SteamWorkshopInstalledLibraryScanContext) -> SteamWorkshopInstalledRecordPreparation? {
        let managed = managedSnapshots
        if let snapshot = managed[directory.lastPathComponent] {
            guard let commit = snapshot.commit,
                  SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: context.libraryRoot) else { return nil }
            return scanPrepareInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                fallbackProject: nil, fallbackIdentifier: snapshot.item.id, resolvingIDs: resolvingIDs, managedSnapshots: managed, context: context)
        }
        let projectURL = directory.appendingPathComponent("project.json")
        let metadataURL = Self.legacyDownloadMetadataFileURL(for: directory)
        guard FileManager.default.fileExists(atPath: projectURL.path)
            || FileManager.default.fileExists(atPath: metadataURL.path)
            || FileManager.default.fileExists(atPath: directory.appendingPathComponent("scene.pkg").path)
            || resolveHTMLURL(in: directory, preferredFileName: nil) != nil
            || resolveVideoURL(in: directory, preferredFileName: nil) != nil else {
            return nil
        }
        let project = Self.loadWorkshopProject(from: projectURL)
        let identifier = directory.lastPathComponent
        let metadata = scanLoadDownloadMetadataSnapshot(legacyDirectory: directory, id: identifier, context: context)
        return scanPrepareInstalledRecord(
            from: metadata,
            legacyDirectory: directory,
            fallbackProject: project,
            fallbackIdentifier: identifier,
            resolvingIDs: resolvingIDs, managedSnapshots: managed, context: context
        )
    }

    nonisolated static func resolveVideoURL(in directory: URL, preferredFileName: String?) -> URL? {
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

    nonisolated static func resolveHTMLURL(in directory: URL, preferredFileName: String?) -> URL? {
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

        return candidateURLs.min(by: { lhs, rhs in
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
        })
    }

    nonisolated static func resolveContentType(
        project: SteamWorkshopProject?,
        directory: URL?,
        videoURL: URL?,
        htmlURL: URL?,
        dependencyItemID: String?,
        browserItem: SteamWorkshopBrowserItem?
    ) -> SteamWorkshopDownloadContentType {
        if let sceneContentType = Self.resolveSceneContentType(
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
        accountSteamID: String,
        sizeText: String? = nil
    ) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let previous = downloads[index]
            guard previous.status != .ready else { return }
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
                dependencyStatus: previous.dependencyStatus,
                createdAt: previous.createdAt,
                sizeBytes: previous.sizeBytes,
                intentAccountSteamID: accountSteamID
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
                dependencyStatus: .none,
                intentAccountSteamID: accountSteamID
            ),
            at: 0
        )
    }

    nonisolated static func scanBuildInstalledRecord(
        from metadata: SteamWorkshopDownloadMetadataSnapshot?,
        legacyDirectory: URL?, fallbackProject: SteamWorkshopProject?, fallbackIdentifier: String,
        resolvingIDs: Set<String> = [],
        managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot],
        context: SteamWorkshopInstalledLibraryScanContext
    ) -> SteamWorkshopDownloadRecord? {
        scanPrepareInstalledRecord(from: metadata, legacyDirectory: legacyDirectory,
            fallbackProject: fallbackProject, fallbackIdentifier: fallbackIdentifier,
            resolvingIDs: resolvingIDs, managedSnapshots: managedSnapshots, context: context)
            .map { scanProjectInstalledRecord($0) }
    }

    private nonisolated static func scanPrepareInstalledRecord(
        from metadata: SteamWorkshopDownloadMetadataSnapshot?,
        legacyDirectory: URL?,
        fallbackProject: SteamWorkshopProject?,
        fallbackIdentifier: String,
        resolvingIDs: Set<String> = [],
        managedSnapshots: [String: SteamWorkshopDownloadMetadataSnapshot],
        context: SteamWorkshopInstalledLibraryScanContext
    ) -> SteamWorkshopInstalledRecordPreparation? {
        let identifier = metadata?.item.id ?? fallbackIdentifier
        guard !resolvingIDs.contains(identifier) else { return nil }
        let resolving = resolvingIDs.union([identifier])
        let managed = managedSnapshots
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

        let dependency: SteamWorkshopInstalledRecordPreparation? = {
            guard let dependencyItemID,
                  dependencyItemID != identifier else { return nil }
            if let snapshot = managed[dependencyItemID] {
                guard let commit = snapshot.commit,
                      SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: context.libraryRoot) else { return nil }
                return scanPrepareInstalledRecord(from: snapshot, legacyDirectory: snapshot.legacyFolderURL,
                    fallbackProject: nil, fallbackIdentifier: dependencyItemID, resolvingIDs: resolving, managedSnapshots: managed, context: context)
            }
            return scanPrepareInstalledRecord(at: context.webRoot.appendingPathComponent(dependencyItemID, isDirectory: true),
                resolvingIDs: resolving, managedSnapshots: managed, context: context)
                ?? scanPrepareInstalledRecord(at: context.sceneRoot.appendingPathComponent(dependencyItemID, isDirectory: true),
                    resolvingIDs: resolving, managedSnapshots: managed, context: context)
        }()

        let dependencyEntryHTMLURL = dependency?.entryHTMLURL.flatMap { entry in
            FileManager.default.fileExists(atPath: entry.path) ? entry : nil
        }
        let dependencyHostFolderURL = dependency?.folderURL.resolvingSymlinksInPath().standardizedFileURL
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
        let browserItem = metadata?.item ?? context.fallbackItemsByID[identifier] ?? Self.loadDetailCache(id: identifier)
        let contentType = resolveContentType(
            project: resolvedProject,
            directory: resolvedLegacyDirectory,
            videoURL: effectiveVideoURL,
            htmlURL: entryHTMLURL,
            dependencyItemID: dependencyItemID,
            browserItem: browserItem
        )
        guard Self.hasLocalWorkshopContent(directory: resolvedLegacyDirectory,
            sceneEntry: contentType == .scene ? resolvedProject?.file : nil,
            videoURL: effectiveVideoURL, htmlURL: entryHTMLURL,
            hasDependency: dependencyItemID != nil && resolvedProject != nil) else {
            return nil
        }

        return SteamWorkshopInstalledRecordPreparation(
            identifier: identifier, metadata: metadata, directory: resolvedLegacyDirectory,
            projectFileURL: projectFileURL, project: resolvedProject,
            folderURL: resolvedLegacyDirectory ?? effectiveVideoURL?.deletingLastPathComponent() ?? context.fallbackLibraryRoot,
            sourceVideoURL: sourceVideoURL, exportedVideoURL: exportedVideoURL,
            ownEntryHTMLURL: directEntryHTMLURL, dependencyHostEntryHTMLURL: dependencyEntryHTMLURL,
            dependencyHostFolderURL: dependencyHostFolderURL, entryHTMLURL: entryHTMLURL,
            resolvedWebRootURL: resolvedWebRootURL, browserItem: browserItem, contentType: contentType,
            dependencyItemID: dependencyItemID, dependencyStatus: dependencyStatus
        )
    }

    private nonisolated static func scanProjectInstalledRecord(
        _ source: SteamWorkshopInstalledRecordPreparation
    ) -> SteamWorkshopDownloadRecord {
        let identifier = source.identifier
        let metadata = source.metadata
        let resolvedLegacyDirectory = source.directory
        let resolvedProject = source.project
        let browserItem = source.browserItem
        let effectiveVideoURL = source.exportedVideoURL ?? source.sourceVideoURL
        let preferredPreviewRelativePath: String? = {
            guard let resolvedLegacyDirectory else { return nil }
            return Self.preferredPreviewRelativePath(
                in: resolvedLegacyDirectory,
                project: resolvedProject,
                fallbackPath: metadata?.previewRelativePath
            )
        }()

        let previewURL: URL? = {
            if let preferredPreviewRelativePath,
               let resolvedLegacyDirectory {
                let candidate = resolvedLegacyDirectory.appendingPathComponent(preferredPreviewRelativePath)
                return candidate
            }
            return nil
        }()

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
        let statistics = Self.localDownloadStatistics(metadata: metadata,
            sampleDirectory: resolvedLegacyDirectory, standaloneFile: effectiveVideoURL ?? source.entryHTMLURL)

        let browserTitle = browserItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : (browserTitle.isEmpty ? "Workshop #\(identifier)" : browserTitle),
            description: description.isEmpty ? (browserItem?.descriptionText ?? "") : description,
            tags: tags.isEmpty ? (browserItem?.tags ?? []) : tags,
            folderURL: source.folderURL,
            projectFileURL: source.projectFileURL,
            ownEntryHTMLURL: source.ownEntryHTMLURL,
            dependencyHostEntryHTMLURL: source.dependencyHostEntryHTMLURL,
            dependencyHostFolderURL: source.dependencyHostFolderURL,
            entryHTMLURL: source.entryHTMLURL,
            resolvedWebRootURL: source.resolvedWebRootURL,
            previewURL: previewURL,
            sourceVideoURL: source.sourceVideoURL,
            exportedVideoURL: source.exportedVideoURL,
            updatedAt: updatedAt,
            sizeText: statistics.sizeText,
            status: .ready,
            browserItem: browserItem,
            contentType: source.contentType,
            dependencyItemID: source.dependencyItemID,
            dependencyStatus: source.dependencyStatus,
            createdAt: statistics.createdAt,
            sizeBytes: statistics.bytes
        )
    }

    nonisolated static func hasLocalWorkshopContent(directory: URL?, sceneEntry: String?,
        videoURL: URL?, htmlURL: URL?, hasDependency: Bool) -> Bool {
        func isFile(_ url: URL?) -> Bool {
            guard let url else { return false }
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
        }
        if isFile(videoURL) || isFile(htmlURL) { return true }
        guard let directory else { return false }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        if isFile(root.appendingPathComponent("scene.pkg")) { return true }
        if hasDependency && isFile(root.appendingPathComponent("project.json")) { return true }
        guard let sceneEntry else { return false }
        let entry = root.appendingPathComponent(sceneEntry).resolvingSymlinksInPath().standardizedFileURL
        return entry.path.hasPrefix(root.path + "/") && isFile(entry)
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

    nonisolated static private func videoFileCandidates(in directory: URL) -> [URL] {
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

    nonisolated static private func relativePath(for fileURL: URL, under directory: URL) -> String {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(directoryPath) else {
            return fileURL.lastPathComponent
        }
        let suffix = filePath.dropFirst(directoryPath.count)
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Prepared once by the background scan; both the detail text and sort keys
    /// consume this same local sample total and first-download date.
    nonisolated static func localDownloadStatistics(
        metadata: SteamWorkshopDownloadMetadataSnapshot?, sampleDirectory: URL?, standaloneFile: URL?
    ) -> (createdAt: Date?, bytes: Int64?, sizeText: String) {
        let bytes: Int64?
        if let sampleDirectory {
            bytes = Self.directoryTotalBytes(at: sampleDirectory)
        } else {
            bytes = standaloneFile.flatMap(Self.localFileSizeBytes(at:))
        }
        let creationDate = Self.localCreationDate(at: sampleDirectory ?? standaloneFile)
        return (metadata?.resolvedFirstDownloadDate(fallbackCreationDate: creationDate) ?? creationDate,
                bytes, bytes.map(Self.fileSizeText(forBytes:)) ?? "未知大小")
    }

    nonisolated static func localCreationDate(at url: URL?) -> Date? {
        guard let url else { return nil }
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    nonisolated static func localFileSizeBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    /// Include hidden/package resources, but never follow symbolic links outside
    /// the sample. Publish a total only after every entry was read successfully.
    nonisolated static func directoryTotalBytes(at directory: URL) -> Int64? {
        var failed = false
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in failed = true; return false }
        ) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
                return nil
            }
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            guard let size = values.fileSize, size >= 0 else { return nil }
            let sum = total.addingReportingOverflow(Int64(size))
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return failed ? nil : total
    }

    nonisolated static private func scanLoadDownloadMetadataSnapshot(legacyDirectory: URL?, id: String, context: SteamWorkshopInstalledLibraryScanContext) -> SteamWorkshopDownloadMetadataSnapshot? {
        if let entry = Self.scanLoadDownloadMetadataEntry(forItemID: id, metadataIndexDirectory: context.metadataIndexDirectory) {
            return entry.snapshot
        }

        if let legacyDirectory {
            let metadataURL = Self.legacyDownloadMetadataFileURL(for: legacyDirectory)
            if let data = try? Data(contentsOf: metadataURL),
               let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) {
                return snapshot
            }
        }

        guard let item = context.fallbackItemsByID[id] ?? Self.loadDetailCache(id: id) else { return nil }
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
