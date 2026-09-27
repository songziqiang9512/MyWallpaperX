import Foundation
import Darwin

extension SteamWorkshopLibraryTransaction {
    static func contentURL(for commit: SteamWorkshopLibraryCommit, libraryRoot: URL) throws -> URL {
        try require(storageIdentity(for: commit) != nil)
        if commit.version == 1 {
            return libraryRoot.appendingPathComponent(versionsName)
                .appendingPathComponent(commit.directoryName)
                .appendingPathComponent("content", isDirectory: true)
        }
        return libraryRoot.appendingPathComponent(try publicTypeDirectoryName(for: commit.contentType), isDirectory: true)
            .appendingPathComponent(commit.directoryName, isDirectory: true)
    }

    static func storageIdentity(containing url: URL, libraryRoot: URL) -> String? {
        guard url.isFileURL,
              let configuredLibrary = try? configuredRoot(libraryRoot) else { return nil }
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL

        // Version 1 compatibility: hidden UUID/content trees are read only and
        // remain leaseable until migration plus reclamation have both finished.
        let versions = configuredLibrary.appendingPathComponent(versionsName, isDirectory: true)
        let resolvedVersions = versions.resolvingSymlinksInPath().standardizedFileURL
        let prefix = resolvedVersions.path + "/"
        if resolvedURL.path.hasPrefix(prefix) {
            let remainder = resolvedURL.path.dropFirst(prefix.count)
            if let first = remainder.split(separator: "/", omittingEmptySubsequences: true).first {
                let name = String(first)
                if name.utf8.count == 36, UUID(uuidString: name) != nil {
                    return "v1:" + name.lowercased()
                }
            }
        }

        for (contentType, typeDirectoryName) in publicTypeDirectories {
            let configuredTypeRoot = configuredLibrary.appendingPathComponent(typeDirectoryName, isDirectory: true)
            let typeRoot = configuredTypeRoot.resolvingSymlinksInPath().standardizedFileURL
            let typePrefix = typeRoot.path + "/"
            guard resolvedURL.path.hasPrefix(typePrefix) else { continue }
            let remainder = resolvedURL.path.dropFirst(typePrefix.count)
            guard let first = remainder.split(separator: "/", omittingEmptySubsequences: true).first else { continue }
            let name = String(first)
            // Open through the physical configured spelling. Foundation may abbreviate
            // /private/tmp to the /tmp symlink while resolving the comparison path.
            let directoryURL = configuredTypeRoot.appendingPathComponent(name, isDirectory: true)
            guard let root = try? absoluteDirectory(directoryURL),
                  let marker = try? markerCommit(in: root),
                  marker.contentType == contentType,
                  marker.directoryName == name,
                  let identity = storageIdentity(for: marker) else { continue }
            return identity
        }
        return nil
    }

    static func isManagedPublicDirectory(_ url: URL, libraryRoot: URL) -> Bool {
        storageIdentity(containing: url, libraryRoot: libraryRoot)?.hasPrefix("v2:") == true
    }

    /// Public legacy discovery must fail closed for the entire managed naming
    /// namespace, even when a v2 marker is missing or corrupt. Otherwise a bare
    /// project file could become a second ready owner after metadata publication.
    static func isReservedManagedPublicDirectory(_ url: URL, libraryRoot: URL) -> Bool {
        guard url.isFileURL,
              (managedPublicDirectoryWorkshopID(url.lastPathComponent) != nil
                || FileManager.default.fileExists(atPath: url.appendingPathComponent(ownershipMarkerName).path)),
              let configuredLibrary = try? configuredRoot(libraryRoot),
              let physicalParent = try? configuredRoot(url.deletingLastPathComponent()) else { return false }
        return publicTypeDirectories.values.contains { typeDirectoryName in
            let expected = configuredLibrary.appendingPathComponent(typeDirectoryName, isDirectory: true)
            guard let physicalExpected = try? configuredRoot(expected) else { return false }
            return physicalExpected.standardizedFileURL.path
                == physicalParent.standardizedFileURL.path
        }
    }

    private static let publicationsName = ".mywallpaperx-steam-publications"
    private struct Publication: Codable {
        let prepared: SteamWorkshopLibraryCommit
        let current: SteamWorkshopLibraryCommit
        let metadata: Data
        let previousMetadata: Data?
        let previous: SteamWorkshopLibraryCommit?
    }
    private struct MetadataPointer: Decodable { let commit: SteamWorkshopLibraryCommit }

    static func canonicalCommit(_ prepared: SteamWorkshopLibraryCommit) throws -> SteamWorkshopLibraryCommit {
        try require(prepared.version == 2 && storageIdentity(for: prepared) != nil && !prepared.removed)
        return SteamWorkshopLibraryCommit(version: 3, workshopId: prepared.workshopId,
            jobId: prepared.jobId, attempt: prepared.attempt, directoryName: prepared.workshopId,
            manifestId: prepared.manifestId, contentDigest: prepared.contentDigest,
            contentType: prepared.contentType, entryPath: prepared.entryPath, committedAt: prepared.committedAt,
            generation: String(prepared.directoryName.dropFirst(prepared.workshopId.count + 1)))
    }

    private static func atomicWrite(_ data: Data, name: String, in root: FD) throws {
        let temporary = ".pending-" + UUID().uuidString
        let file = try openFile(root, temporary, create: true)
        defer { unlinkat(root.value, temporary, 0) }
        try write(data, to: file)
        try require(fsync(file.value) == 0)
        try require(renameat(root.value, temporary, root.value, name) == 0)
        try require(fsync(root.value) == 0)
    }

    /// Called with playback admission fenced by the service. Preparation stays immutable;
    /// only this durable publication intent may install or replace the clean ID directory.
    static func publishCanonical(_ prepared: SteamWorkshopLibraryCommit, metadata: Data, libraryRoot: URL) throws {
        let current = try canonicalCommit(prepared)
        let library = try absoluteDirectory(libraryRoot)
        let type = try directory(library, publicTypeDirectoryName(for: current.contentType))
        let candidate = try directory(type, prepared.directoryName)
        try require(try markerCommit(in: candidate) == prepared)
        var value = stat()
        let exists = fstatat(type.value, current.directoryName, &value, AT_SYMLINK_NOFOLLOW) == 0
        if !exists { try require(errno == ENOENT) }
        let previous = exists ? try markerCommit(in: directory(type, current.directoryName)) : nil
        if let previous { try require(previous.workshopId == current.workshopId
            && previous.contentType == current.contentType && previous.directoryName == current.directoryName) }
        _ = try directory(library, metadataName, create: true)
        let previousMetadata = try publishedMetadata(libraryRoot: libraryRoot, requireComplete: true,
            matchingItemID: current.workshopId)[current.workshopId]
        let intent = Publication(prepared: prepared, current: current, metadata: metadata,
            previousMetadata: previousMetadata, previous: previous)
        let journal = try directory(library, publicationsName, create: true)
        let journalName = current.workshopId + ".json"
        try require(fstatat(journal.value, journalName, &value, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT,
                    "此项目有待恢复的入库事务，请重新扫描后重试。")
        try atomicWrite(try JSONEncoder().encode(intent), name: journalName, in: journal)
        try finishPublication(intent, libraryRoot: libraryRoot)
    }

    private static func finishPublication(_ intent: Publication, libraryRoot: URL) throws {
        let current = try canonicalCommit(intent.prepared)
        try require(current == intent.current && intent.metadata.count <= 4 * 1024 * 1024)
        let library = try absoluteDirectory(libraryRoot)
        let type = try directory(library, publicTypeDirectoryName(for: current.contentType))
        let indexed = try publishedMetadata(libraryRoot: libraryRoot, requireComplete: true,
            matchingItemID: current.workshopId)[current.workshopId]
        let indexedCommit = indexed.flatMap { try? JSONDecoder().decode(MetadataPointer.self, from: $0).commit }
        let committed = indexed == intent.metadata || indexedCommit == current
        try require(indexed == intent.previousMetadata || committed,
                    "下载索引已变化，拒绝覆盖其他入库事务。")
        let installed = try? markerCommit(in: directory(type, current.directoryName))
        try require(!committed || installed == current)
        if installed != current {
            try require(installed == intent.previous, "目标 ID 目录已变化，拒绝覆盖本地内容。")
            let candidate = try directory(type, intent.prepared.directoryName)
            let marker = try markerCommit(in: candidate)
            try require(marker == intent.prepared || marker == current)
            try atomicWrite(try JSONEncoder().encode(current), name: ownershipMarkerName, in: candidate)
            let flags = intent.previous == nil ? RENAME_EXCL : RENAME_SWAP
            try require(renameatx_np(type.value, intent.prepared.directoryName, type.value,
                current.directoryName, UInt32(flags)) == 0, "下载目录发布失败，入库事务保留以供恢复。")
            try require(fsync(type.value) == 0)
        }
        // A crash between directory exchange and metadata publication is replayed from
        // this exact intent before the next local scan; no directory alone becomes ready.
        do {
            if !committed {
                try publish(metadata: intent.metadata, itemID: current.workshopId, libraryRoot: libraryRoot)
            }
        } catch {
            // Ordinary write failure restores the old path synchronously. If rollback
            // itself fails, retain the durable intent for recovery instead of guessing.
            let flags = intent.previous == nil ? RENAME_EXCL : RENAME_SWAP
            if renameatx_np(type.value, current.directoryName, type.value,
                intent.prepared.directoryName, UInt32(flags)) == 0 {
                let candidate = try directory(type, intent.prepared.directoryName)
                try atomicWrite(try JSONEncoder().encode(intent.prepared), name: ownershipMarkerName, in: candidate)
                let journal = try directory(library, publicationsName)
                _ = unlinkat(journal.value, current.workshopId + ".json", 0)
                _ = fsync(type.value)
            }
            throw error
        }
        if let previous = intent.previous,
           let backup = try? directory(type, intent.prepared.directoryName),
           (try? markerCommit(in: backup)) == previous {
            do { try removeOwnedTree(parent: type, name: intent.prepared.directoryName, expectedMarker: previous) }
            catch { return } // Published; keep the journal so cleanup can be retried.
        }
        if let journal = try? directory(library, publicationsName) {
            _ = unlinkat(journal.value, current.workshopId + ".json", 0)
            _ = fsync(journal.value)
        }
    }

    static func recoverPublications(libraryRoot: URL, retaining identities: Set<String> = []) throws {
        guard let library = try? absoluteDirectory(libraryRoot),
              let journal = try? directory(library, publicationsName) else { return }
        for name in try childNames(journal) where name.hasSuffix(".json") {
            let data = try readData(openFile(journal, name), maximumBytes: 12 * 1024 * 1024)
            let intent = try JSONDecoder().decode(Publication.self, from: data)
            try require(name == intent.current.workshopId + ".json")
            let affected = [intent.prepared, intent.current, intent.previous].compactMap { $0 }
                .compactMap(storageIdentity(for:))
            guard identities.isDisjoint(with: affected) else { continue }
            try finishPublication(intent, libraryRoot: libraryRoot)
        }
    }

    /// Explicit user deletion is immediate, independent of background version retention.
    /// Only a direct content child of a configured type root can be removed.
    static func removeContent(at url: URL, itemID: String, libraryRoot: URL,
                              expectedCommit: SteamWorkshopLibraryCommit?) throws {
        let library = try configuredRoot(libraryRoot)
        if let commit = expectedCommit, commit.version == 1 {
            try require(try contentURL(for: commit, libraryRoot: library) == url)
            let parent = try directory(absoluteDirectory(library), versionsName)
            let target = try directory(parent, commit.directoryName)
            try removeOwnedTree(parent: parent, name: commit.directoryName,
                expectedIdentity: validatedFilesystemIdentity(info(target, regular: false)))
            return
        }
        let parentURL = url.deletingLastPathComponent().standardizedFileURL
        try require(["Scene", "Web", "Video"].contains(parentURL.lastPathComponent)
            && (try configuredRoot(parentURL.deletingLastPathComponent())) == library)
        let parent = try directory(absoluteDirectory(library), parentURL.lastPathComponent)
        let name = url.lastPathComponent
        var value = stat()
        guard fstatat(parent.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            try require(errno == ENOENT); return
        }
        if (value.st_mode & S_IFMT) == S_IFDIR {
            try require(name == itemID || name.hasPrefix(itemID + "-"))
            let identity = try validatedFilesystemIdentity(value)
            try removeOwnedTree(parent: parent, name: name, expectedIdentity: identity, expectedMarker: expectedCommit)
        } else {
            try require(expectedCommit == nil && parentURL.lastPathComponent == "Video")
            let file = try openFile(parent, name)
            try require(samePinnedFileSnapshot(try info(file, regular: true), value))
            try require(unlinkat(parent.value, name, 0) == 0)
        }
        _ = fsync(parent.value)
    }
}
