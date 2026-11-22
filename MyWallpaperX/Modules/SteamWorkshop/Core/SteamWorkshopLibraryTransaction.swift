import Foundation
import Darwin

/// The existing metadata index publishes this pointer. Version directories alone are never ready.
///
/// Version 2 describes prepared and retired generations. Version 3 is the current ready pointer
/// in Video/Web/Scene; the metadata rename remains the only ready commit point.
nonisolated struct SteamWorkshopLibraryCommit: Codable, Equatable, Sendable {
    let version: Int
    let workshopId: String
    let jobId: String
    let attempt: Int
    let directoryName: String
    let manifestId: String
    let contentDigest: String
    let contentType: String
    let entryPath: String?
    let committedAt: Date
    var removed: Bool = false
    var generation: String? = nil
    var sceneReceipt: SceneSourceReceiptReference? = nil
}

/// Disk preparation is detached from UI. Publication is a small, synchronous operation performed
/// by the service after checking the live account and job attempt. No old content is deleted.
nonisolated enum SteamWorkshopLibraryTransaction {
    static let incomingName = ".mywallpaperx-steam-incoming"
    static let metadataName = ".mywallpaperx-steam-metadata"
    static let ownershipMarkerName = SteamWorkshopStorageTree.ownershipMarkerName
    static let retiredPrefix = ".retired-"
    static let maxBytes = 8 * 1024 * 1024 * 1024
    static let diskSafetyReserveBytes = 256 * 1024 * 1024

    struct ReclamationResult: Equatable, Sendable {
        let removedStorageIdentities: [String]
        let retainedStorageIdentities: [String]
        let skippedEntries: [String]
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let publicTypeDirectories = [
        "video": "Video",
        "web": "Web",
        "scene": "Scene",
    ]
    typealias FD = SteamWorkshopStorageTree.FD
    static func require(_ condition: Bool, _ message: String = String(localized: "Validation of the downloaded content or file path failed.")) throws {
        guard condition else { throw Failure(message: message) }
    }
    private static func parts(_ path: String) throws -> [String] {
        try SteamWorkshopStorageTree.parts(path)
    }
    static func directory(_ parent: FD, _ name: String, create: Bool = false, exclusive: Bool = false) throws -> FD {
        try SteamWorkshopStorageTree.directory(parent, name, create: create, exclusive: exclusive)
    }
    static func absoluteDirectory(_ url: URL, create: Bool = false) throws -> FD {
        try SteamWorkshopStorageTree.absoluteDirectory(url, create: create)
    }
    static func info(_ fd: FD, regular: Bool) throws -> stat {
        try SteamWorkshopStorageTree.info(fd, regular: regular)
    }
    static func openFile(_ root: FD, _ path: String, create: Bool = false, readableOutput: Bool = false) throws -> FD {
        try SteamWorkshopStorageTree.openFile(root, path, create: create, readableOutput: readableOutput)
    }
    static func write(_ data: Data, to fd: FD) throws {
        try SteamWorkshopStorageTree.write(data, to: fd)
    }
    static func readData(_ fd: FD, maximumBytes: Int) throws -> Data {
        try SteamWorkshopStorageTree.readData(fd, maximumBytes: maximumBytes)
    }

    static func publicTypeDirectoryName(for contentType: String) throws -> String {
        guard let name = publicTypeDirectories[contentType] else {
            throw Failure(message: String(localized: "The downloaded project doesn’t have a valid scene/web/video type."))
        }
        return name
    }

    static func managedPublicDirectoryWorkshopID(_ name: String) -> String? {
        guard let separator = name.firstIndex(of: "-") else { return nil }
        let workshopId = String(name[..<separator])
        let suffix = String(name[name.index(after: separator)...])
        guard validID(workshopId), suffix.utf8.count == 36,
              UUID(uuidString: suffix) != nil else { return nil }
        return workshopId
    }

    private static func validPublicDirectoryName(_ name: String, workshopId: String) -> Bool {
        let prefix = workshopId + "-"
        guard name.hasPrefix(prefix) else { return false }
        return managedPublicDirectoryWorkshopID(name) == workshopId
    }

    private static func storageIdentity(forVersion version: Int, contentType: String,
                                        workshopId: String, directoryName: String) -> String? {
        guard version == 2, publicTypeDirectories[contentType] != nil,
              validID(workshopId), validPublicDirectoryName(directoryName, workshopId: workshopId) else { return nil }
        return "v2:\(contentType):\(directoryName.lowercased())"
    }

    static func storageIdentity(for commit: SteamWorkshopLibraryCommit) -> String? {
        if commit.version == 3 {
            guard commit.directoryName == commit.workshopId, let generation = commit.generation else { return nil }
            return storageIdentity(forVersion: 2, contentType: commit.contentType,
                workshopId: commit.workshopId, directoryName: commit.workshopId + "-" + generation)
        }
        return storageIdentity(forVersion: commit.version, contentType: commit.contentType,
                        workshopId: commit.workshopId, directoryName: commit.directoryName)
    }

    static func isValidStorageIdentity(_ identity: String) -> Bool {
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, parts[0] == "incoming" {
            return parts[1].utf8.count == 36 && UUID(uuidString: parts[1]) != nil
        }
        guard parts.count == 3, parts[0] == "v2", publicTypeDirectories[parts[1]] != nil else { return false }
        guard let workshopId = managedPublicDirectoryWorkshopID(parts[2]) else { return false }
        return validPublicDirectoryName(parts[2], workshopId: workshopId)
    }

    /// Every pathname mutation uses the same birth-qualified filesystem identity.
    /// Filesystems that cannot supply a valid creation time fail closed instead of
    /// silently degrading the comparison to device + inode.
    static func validatedFilesystemIdentity(
        _ value: stat
    ) throws -> SteamWorkshopStagingLeaseIdentity {
        let identity = SteamWorkshopStagingLeaseIdentity(
            device: UInt64(value.st_dev),
            inode: UInt64(value.st_ino),
            birthSeconds: Int64(value.st_birthtimespec.tv_sec),
            birthNanoseconds: Int64(value.st_birthtimespec.tv_nsec)
        )
        try require(identity.isComplete,
                    String(localized: "The file system didn’t provide a complete creation identity; writing and deleting are refused."))
        return identity
    }

    /// A read held on one already-open descriptor does not adopt a pathname.
    /// Keep its snapshot check independent from mutation birth-time support so
    /// an older volume cannot hide an existing ready record during a pure read.
    static func samePinnedFileSnapshot(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
    }

    private static func sameFilesystemObject(_ lhs: stat, _ rhs: stat) -> Bool {
        guard let left = try? validatedFilesystemIdentity(lhs),
              let right = try? validatedFilesystemIdentity(rhs) else { return false }
        return left == right
    }

    private static func sameDirectory(_ value: stat, as expected: SteamWorkshopStagingLeaseIdentity) -> Bool {
        guard expected.isComplete,
              let identity = try? validatedFilesystemIdentity(value) else { return false }
        return identity == expected
    }

    static func markerCommit(in root: FD) throws -> SteamWorkshopLibraryCommit {
        let marker = try openFile(root, ownershipMarkerName)
        let data = try readData(marker, maximumBytes: 16 * 1024)
        let commit = try JSONDecoder().decode(SteamWorkshopLibraryCommit.self, from: data)
        try require((commit.version == 2 || commit.version == 3) && storageIdentity(for: commit) != nil,
                    String(localized: "The managed download version marker is invalid."))
        return commit
    }

    private static func writeMarker(_ commit: SteamWorkshopLibraryCommit, to root: FD) throws {
        let file = try openFile(root, ownershipMarkerName, create: true)
        let data = try JSONEncoder().encode(commit)
        try require(data.count <= 16 * 1024, String(localized: "The download version marker exceeds the budget."))
        try write(data, to: file)
        try require(fsync(file.value) == 0, String(localized: "The download version marker couldn’t be synced to disk."))
    }

    static func childNames(_ root: FD, limit: Int = 1_024) throws -> [String] {
        let duplicate = dup(root.value)
        guard duplicate >= 0 else { throw Failure(message: String(localized: "Couldn’t enumerate the Downloads folder.")) }
        guard let stream = fdopendir(duplicate) else {
            close(duplicate)
            throw Failure(message: String(localized: "Couldn’t enumerate the Downloads folder."))
        }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                try require(errno == 0, String(localized: "Failed to enumerate the Downloads folder."))
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            try require(!name.isEmpty && !name.contains("/") && !name.utf8.contains(0))
            names.append(name)
            try require(names.count <= limit, String(localized: "The retained download/version directory exceeds the cleanup scan budget."))
        }
        return names.sorted()
    }

    /// Descriptor-anchored deletion that never follows links and verifies that
    /// the directory name still identifies the opened inode before unlinking it.
    private struct OwnedDirectoryChanged: Error {}

    static func removeOwnedTree(
        parent: FD,
        name: String,
        expectedIdentity: SteamWorkshopStagingLeaseIdentity? = nil,
        expectedMarker: SteamWorkshopLibraryCommit? = nil,
        honorTaskCancellation: Bool = true
    ) throws {
        var named = stat()
        try require(fstatat(parent.value, name, &named, AT_SYMLINK_NOFOLLOW) == 0)
        try require((named.st_mode & S_IFMT) == S_IFDIR, String(localized: "Only managed version folders are reclaimed."))
        guard (try? validatedFilesystemIdentity(named)) != nil else {
            throw OwnedDirectoryChanged()
        }
        if let expectedIdentity, !sameDirectory(named, as: expectedIdentity) {
            throw OwnedDirectoryChanged()
        }
        let opened = try directory(parent, name)
        let openedInfo = try info(opened, regular: false)
        guard sameFilesystemObject(named, openedInfo) else {
            throw OwnedDirectoryChanged()
        }
        if let expectedIdentity, !sameDirectory(openedInfo, as: expectedIdentity) {
            throw OwnedDirectoryChanged()
        }
        if let expectedMarker {
            guard (try? markerCommit(in: opened)) == expectedMarker else {
                throw OwnedDirectoryChanged()
            }
        }

        for child in try childNames(opened) {
            if honorTaskCancellation { try Task.checkCancellation() }
            var value = stat()
            try require(fstatat(opened.value, child, &value, AT_SYMLINK_NOFOLLOW) == 0)
            if (value.st_mode & S_IFMT) == S_IFDIR {
                let childIdentity: SteamWorkshopStagingLeaseIdentity
                do {
                    childIdentity = try validatedFilesystemIdentity(value)
                } catch {
                    throw OwnedDirectoryChanged()
                }
                try removeOwnedTree(
                    parent: opened,
                    name: child,
                    expectedIdentity: childIdentity,
                    honorTaskCancellation: honorTaskCancellation
                )
            } else if (value.st_mode & S_IFMT) == S_IFREG {
                let file = try openFile(opened, child)
                let openedFileInfo = try info(file, regular: true)
                guard sameFilesystemObject(value, openedFileInfo) else {
                    throw OwnedDirectoryChanged()
                }
                var currentFileInfo = stat()
                guard fstatat(opened.value, child, &currentFileInfo, AT_SYMLINK_NOFOLLOW) == 0,
                      (currentFileInfo.st_mode & S_IFMT) == S_IFREG,
                      sameFilesystemObject(currentFileInfo, openedFileInfo) else {
                    throw OwnedDirectoryChanged()
                }
                try require(unlinkat(opened.value, child, 0) == 0, String(localized: "Version file cleanup failed."))
            } else {
                // Symlinks and other non-directory entries are never followed.
                // They still need a complete birth-qualified pathname identity
                // immediately before unlink so an owned cleanup cannot adopt a
                // same-name replacement.
                guard (try? validatedFilesystemIdentity(value)) != nil else {
                    throw OwnedDirectoryChanged()
                }
                var currentEntryInfo = stat()
                guard fstatat(opened.value, child, &currentEntryInfo, AT_SYMLINK_NOFOLLOW) == 0,
                      sameFilesystemObject(currentEntryInfo, value) else {
                    throw OwnedDirectoryChanged()
                }
                try require(unlinkat(opened.value, child, 0) == 0, String(localized: "Version file cleanup failed."))
            }
        }

        var current = stat()
        try require(fstatat(parent.value, name, &current, AT_SYMLINK_NOFOLLOW) == 0)
        guard (current.st_mode & S_IFMT) == S_IFDIR
            && sameFilesystemObject(current, openedInfo) else {
            throw OwnedDirectoryChanged()
        }
        try require(unlinkat(parent.value, name, AT_REMOVEDIR) == 0, String(localized: "Couldn't reclaim the version directory."))
    }
    static func availableDiskBytes(at root: URL) throws -> Int64 {
        _ = try absoluteDirectory(root, create: true)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        guard let value = attributes[.systemFreeSize] as? NSNumber else {
            throw Failure(message: String(localized: "Couldn’t read the free space on the download disk."))
        }
        return value.int64Value
    }

    static func areOnSameFileSystem(_ lhs: URL, _ rhs: URL) throws -> Bool {
        _ = try absoluteDirectory(lhs, create: true)
        _ = try absoluteDirectory(rhs, create: true)
        let left = try FileManager.default.attributesOfFileSystem(forPath: lhs.path)[.systemNumber] as? NSNumber
        let right = try FileManager.default.attributesOfFileSystem(forPath: rhs.path)[.systemNumber] as? NSNumber
        guard let left, let right else { throw Failure(message: String(localized: "Couldn’t identify the disk that contains the Downloads folder.")) }
        return left == right
    }

    static func canReserveDiskBytes(required: Int64, available: Int64, alreadyReserved: Int64) -> Bool {
        guard required >= 0, available >= 0, alreadyReserved >= 0,
              required <= Int64(maxBytes), alreadyReserved <= available else { return false }
        return required <= available - alreadyReserved
            && Int64(diskSafetyReserveBytes) <= available - alreadyReserved - required
    }
    static func isAvailable(_ commit: SteamWorkshopLibraryCommit, libraryRoot: URL) -> Bool {
        guard !commit.removed, let url = try? contentURL(for: commit, libraryRoot: libraryRoot),
              let root = try? absoluteDirectory(url), let project = try? openFile(root, "project.json"),
              let size = try? info(project, regular: true).st_size, size > 0, size <= 1024 * 1024 else { return false }
        guard (try? markerCommit(in: root)) == commit else { return false }
        if let entry = commit.entryPath, (try? openFile(root, entry)) != nil { return true }
        if commit.contentType == "scene" { return (try? openFile(root, "scene.pkg")) != nil }
        return commit.contentType == "web" && commit.entryPath == nil
    }
    /// Resolve only app-configured roots (never a receipt). Foundation canonicalization can
    /// abbreviate /private/tmp back to the /tmp symlink, so use the native physical spelling.
    static func configuredRoot(_ url: URL) throws -> URL {
        try require(url.isFileURL && url.path.hasPrefix("/"))
        let components = try parts(String(url.path.dropFirst()))
        for count in stride(from: components.count, through: 0, by: -1) {
            let prefix = "/" + components.prefix(count).joined(separator: "/")
            if let resolved = realpath(prefix, nil) {
                defer { free(resolved) }
                var result = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
                for part in components.dropFirst(count) { result.appendPathComponent(part, isDirectory: true) }
                return result
            }
            try require(errno == ENOENT, String(localized: "The configured downloads folder is inaccessible."))
        }
        throw Failure(message: String(localized: "The configured download folder can’t be resolved."))
    }
    /// Capture the exact helper lease identity when its allocated event is accepted.
    /// The persisted identity is later required by ack, preparation and cleanup.
    static func stagingLeaseIdentity(
        stagingURL: URL,
        stagingRoot: URL
    ) throws -> SteamWorkshopStagingLeaseIdentity {
        let configured = try configuredRoot(stagingRoot)
        guard let validated = SteamWorkshopStagedReceipt.validatedStagingURL(
            path: stagingURL.path,
            stagingRoot: configured.path
        ), validated.path == stagingURL.path else {
            throw Failure(message: String(localized: "Refusing to clean up a staging folder that doesn’t belong to the current download task."))
        }
        let root = try absoluteDirectory(configured)
        let name = validated.lastPathComponent
        var named = stat()
        try require(fstatat(root.value, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                    String(localized: "Couldn’t inspect the download staging folder."))
        try require((named.st_mode & S_IFMT) == S_IFDIR, String(localized: "The download staging folder has an invalid identity."))
        let opened = try directory(root, name)
        let openedInfo = try info(opened, regular: false)
        try require(sameFilesystemObject(named, openedInfo),
                    String(localized: "The download staging folder changed during validation."))
        return try validatedFilesystemIdentity(openedInfo)
    }

    /// Deletes only the exact receipt-bound helper staging inode. A missing old
    /// lease is already clean; a same-name replacement is never adopted.
    static func removeStagingLease(
        stagingURL: URL,
        stagingRoot: URL,
        expectedIdentity: SteamWorkshopStagingLeaseIdentity
    ) throws {
        try require(expectedIdentity.isComplete,
                    String(localized: "The download staging lacks a complete creation identity; cleanup by path refused."))
        let configured = try configuredRoot(stagingRoot)
        guard let validated = SteamWorkshopStagedReceipt.validatedStagingURL(
            path: stagingURL.path,
            stagingRoot: configured.path
        ), validated.path == stagingURL.path else {
            throw Failure(message: String(localized: "Refusing to clean up a staging folder that doesn’t belong to the current download task."))
        }
        let root = try absoluteDirectory(configured)
        let name = validated.lastPathComponent
        var value = stat()
        if fstatat(root.value, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw Failure(message: String(localized: "Couldn’t inspect the download staging folder."))
        }
        do {
            try removeOwnedTree(parent: root, name: name, expectedIdentity: expectedIdentity)
        } catch is OwnedDirectoryChanged {
            throw Failure(message: String(localized: "The download staging directory was replaced by an item with the same name, so cleanup was refused."))
        }
    }

    static func prepare(receipt: SteamWorkshopStagedReceipt, attempt: Int,
                        libraryRoot: URL) throws -> SteamWorkshopLibraryCommit {
        guard receipt.version == 2, let sourceIdentity = receipt.stagingLeaseIdentity, sourceIdentity.isComplete else {
            throw Failure(message: String(localized: "The download receipt is missing a stable staging directory identity."))
        }
        return try prepareSource(
            sourceURL: receipt.stagingURL,
            expectedSourceIdentity: sourceIdentity,
            verifiedBytes: Int64(receipt.verifiedBytes),
            expectedDigest: receipt.contentDigest,
            workshopId: receipt.workshopId,
            jobId: receipt.jobId,
            attempt: attempt,
            manifestId: receipt.manifestId,
            committedAt: Date(),
            libraryRoot: libraryRoot
        )
    }

    private static func prepareSource(sourceURL: URL,
                                      expectedSourceIdentity: SteamWorkshopStagingLeaseIdentity,
                                      verifiedBytes: Int64, expectedDigest: String,
                                      workshopId: String, jobId: String, attempt: Int,
                                      manifestId: String, committedAt: Date,
                                      libraryRoot: URL) throws -> SteamWorkshopLibraryCommit {
        try Task.checkCancellation()
        try require(validID(workshopId) && !jobId.isEmpty && attempt > 0
            && verifiedBytes > 0 && verifiedBytes <= Int64(maxBytes))
        let source = try absoluteDirectory(sourceURL)
        let sourceInfo = try info(source, regular: false)
        try require(sameDirectory(sourceInfo, as: expectedSourceIdentity),
                    String(localized: "The download staging folder was replaced by one with the same name; import refused."))
        let inventory = try SteamWorkshopStorageTree.files(source,
            checkCancellation: { try Task.checkCancellation() })
        try require(!inventory.contains { $0.path == ownershipMarkerName }, String(localized: "The downloaded content uses a reserved marker name."))
        let library = try absoluteDirectory(libraryRoot, create: true)
        let incoming = try directory(library, incomingName, create: true)
        // Reject volumes without stable birth identity before creating an
        // attempt-owned UUID. The child is still validated again after mkdir.
        _ = try validatedFilesystemIdentity(try info(incoming, regular: false))
        let name = UUID().uuidString.lowercased()
        let version = try directory(incoming, name, create: true, exclusive: true)
        let versionIdentity = try validatedFilesystemIdentity(try info(version, regular: false))
        defer {
            // Cancellation stops the copy, but it must not cancel removal of the
            // exact descriptor-bound partial generation that this invocation owns.
            do {
                try removeOwnedTree(
                    parent: incoming,
                    name: name,
                    expectedIdentity: versionIdentity,
                    honorTaskCancellation: false
                )
            } catch {
#if DEBUG
                NSLog("MWX Steam library: owned incoming rollback failed: %@", error.localizedDescription)
#endif
            }
            _ = unlinkat(library.value, incomingName, AT_REMOVEDIR)
        }
        let destination = try directory(version, "content", create: true, exclusive: true)
        var total: Int64 = 0
        var fileFacts: [SceneSourceManifest.FileFact] = []
        // Parse the small project first; the complete download digest below
        // still folds every copied author file in the original NFC/UTF8 order.
        guard let projectEntry = inventory.first(where: { $0.path == "project.json" && !$0.isDirectory }) else {
            throw Failure(message: String(localized: "The downloaded project is missing project.json."))
        }
        var project: [String: Any] = [:]
        var contentType = ""
        let copyOrder = [projectEntry] + inventory.filter { $0.path != "project.json" }
        for entry in copyOrder {
            try Task.checkCancellation()
            if entry.isDirectory {
                var parent = destination
                for part in try parts(entry.path) { parent = try directory(parent, part, create: true) }
                continue
            }
            try require(entry.size <= Int64(maxBytes) - total)
            let input = try openFile(source, entry.path)
            let output = try openFile(destination, entry.path, create: true, readableOutput: true)
            let fact = try SteamWorkshopStorageTree.streamFile(input, entry: entry, output: output,
                                                              checkCancellation: { try Task.checkCancellation() })
            try require(fsync(output.value) == 0, String(localized: "The downloaded file couldn’t be synced to disk."))
            fileFacts.append(fact)
            total += entry.size
            if entry.path == "project.json" {
                try require(entry.size > 0 && entry.size <= 1024 * 1024, String(localized: "project.json exceeds the parsing budget."))
                let data = try SteamWorkshopStorageTree.readData(output, maximumBytes: 1024 * 1024,
                                                                 checkCancellation: { try Task.checkCancellation() })
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawType = value["type"] as? String else {
                    throw Failure(message: String(localized: "The downloaded project doesn’t have a valid scene/web/video type."))
                }
                project = value
                contentType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                try require(["scene", "web", "video"].contains(contentType), String(localized: "The downloaded project doesn’t have a valid scene/web/video type."))
            }
        }
        let digest = try SteamWorkshopStorageTree.treeDigest(fileFacts)
        try require(total == verifiedBytes, String(localized: "The download changed before it was added to the library."))
        try require(digest == expectedDigest, String(localized: "The download changed before it was added to the library."))
        let entry = (project["file"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if let entry { _ = try parts(entry) }
        let dependency: String? = {
            if let value = project["dependency"] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = project["dependency"] as? NSNumber,
               !(project["dependency"] is Bool) {
                return value.stringValue
            }
            return nil
        }()
        if let dependency { try require(Self.validID(dependency)) }
        if contentType == "scene" {
            // Authored entry may live inside scene.pkg; the Scene loader owns package semantics.
            if let entry, (try? openFile(destination, entry)) != nil {} else { _ = try openFile(destination, "scene.pkg") }
        } else if contentType == "web", entry == nil, dependency != nil {
            // A dependency-only web project has no local HTML entry.
        } else {
            guard let entry else { throw Failure(message: String(localized: "The downloaded project is missing its entry file.")) }
            let ext = URL(fileURLWithPath: entry).pathExtension.lowercased()
            try require((contentType == "web" ? ["html", "htm"] : ["mp4", "webm", "mov", "m4v"]).contains(ext))
            _ = try openFile(destination, entry)
        }
        try Task.checkCancellation()
        let typeDirectoryName = try publicTypeDirectoryName(for: contentType)
        let typeDirectory = try directory(library, typeDirectoryName, create: true)
        let finalDirectoryName = workshopId + "-" + name
        let commit = SteamWorkshopLibraryCommit(
            version: 2,
            workshopId: workshopId,
            jobId: jobId,
            attempt: attempt,
            directoryName: finalDirectoryName,
            manifestId: manifestId,
            contentDigest: digest,
            contentType: contentType,
            entryPath: entry,
            committedAt: committedAt
        )
        try writeMarker(commit, to: destination)
        try require(fsync(destination.value) == 0, String(localized: "The download version folder couldn’t be synced to disk."))
        try require(renameatx_np(version.value, "content", typeDirectory.value, finalDirectoryName, UInt32(RENAME_EXCL)) == 0,
                    String(localized: "Publishing the downloaded version failed; the old version is unchanged."))
        try require(fsync(typeDirectory.value) == 0, String(localized: "The download type folder couldn’t be synced to disk."))
        return commit
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && (UInt64(id) ?? 0) > 0
    }
    /// Reclaims only descriptor-verified managed versions that are old enough and absent from the
    /// caller's complete ready/job/playback set. Public user content without our exact marker and
    /// unknown hidden entries are left untouched.
    static func reclaimVersions(
        libraryRoot: URL,
        retaining storageIdentities: Set<String>,
        minimumAge: TimeInterval,
        now: Date = Date(),
        admitRemoval: @Sendable (String) async -> Bool = { _ in true },
        removalFailed: @Sendable (String) async -> Void = { _ in }
    ) async throws -> ReclamationResult {
        try require(minimumAge >= 0 && minimumAge.isFinite)
        let library = try absoluteDirectory(libraryRoot, create: true)
        let retained = Set(storageIdentities.map { $0.lowercased() })
        var removedIdentities: [String] = []
        var retainedIdentities: [String] = []
        var skippedEntries: [String] = []

        func oldEnough(_ value: stat) -> Bool {
            let modified = Date(timeIntervalSince1970:
                TimeInterval(value.st_mtimespec.tv_sec) + TimeInterval(value.st_mtimespec.tv_nsec) / 1_000_000_000)
            return now.timeIntervalSince(modified) >= minimumAge
        }

        func removeIfAdmitted(
            parent: FD,
            name: String,
            identity: String,
            value: stat,
            expectedMarker: SteamWorkshopLibraryCommit? = nil,
            entryLabel: String
        ) async throws {
            if retained.contains(identity) || !oldEnough(value) {
                retainedIdentities.append(identity)
                return
            }
            let capturedIdentity: SteamWorkshopStagingLeaseIdentity
            do {
                capturedIdentity = try validatedFilesystemIdentity(value)
            } catch {
                await removalFailed(identity)
                skippedEntries.append(entryLabel)
                return
            }
            guard await admitRemoval(identity) else {
                retainedIdentities.append(identity)
                return
            }
            do {
                try Task.checkCancellation()
                try removeOwnedTree(
                    parent: parent,
                    name: name,
                    expectedIdentity: capturedIdentity,
                    expectedMarker: expectedMarker
                )
            } catch is OwnedDirectoryChanged {
                await removalFailed(identity)
                skippedEntries.append(entryLabel)
                return
            } catch {
                await removalFailed(identity)
                throw error
            }
            removedIdentities.append(identity)
        }

        if let incoming = try? directory(library, incomingName) {
            for name in try childNames(incoming) {
                try Task.checkCancellation()
                guard name.utf8.count == 36, UUID(uuidString: name) != nil else {
                    skippedEntries.append(incomingName + "/" + name)
                    continue
                }
                var value = stat()
                guard fstatat(incoming.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      (value.st_mode & S_IFMT) == S_IFDIR else {
                    skippedEntries.append(incomingName + "/" + name)
                    continue
                }
                try await removeIfAdmitted(parent: incoming, name: name,
                    identity: "incoming:" + name.lowercased(), value: value,
                    entryLabel: incomingName + "/" + name)
            }
            _ = unlinkat(library.value, incomingName, AT_REMOVEDIR)
        }

        for (contentType, typeDirectoryName) in publicTypeDirectories.sorted(by: { $0.key < $1.key }) {
            guard let typeRoot = try? directory(library, typeDirectoryName) else { continue }
            for name in try childNames(typeRoot, limit: 100_000) {
                try Task.checkCancellation()
                var value = stat()
                guard fstatat(typeRoot.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      (value.st_mode & S_IFMT) == S_IFDIR,
                      let root = try? directory(typeRoot, name),
                      let openedInfo = try? info(root, regular: false),
                      sameFilesystemObject(openedInfo, value),
                      let marker = try? markerCommit(in: root),
                      marker.contentType == contentType,
                      (marker.directoryName == name
                        || (marker.version == 2 && retiredPrefix + marker.directoryName == name)),
                      let identity = storageIdentity(for: marker) else {
                    continue // Public user content is not an error and is never adopted.
                }
                try await removeIfAdmitted(
                    parent: typeRoot,
                    name: name,
                    identity: identity,
                    value: value,
                    expectedMarker: marker,
                    entryLabel: typeDirectoryName + "/" + name
                )
            }
        }

        return ReclamationResult(
            removedStorageIdentities: removedIdentities.sorted(),
            retainedStorageIdentities: retainedIdentities.sorted(),
            skippedEntries: skippedEntries.sorted()
        )
    }
}
