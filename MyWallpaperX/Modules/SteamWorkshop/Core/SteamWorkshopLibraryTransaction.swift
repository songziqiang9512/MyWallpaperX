import Foundation
import CryptoKit
import Darwin

/// The existing metadata index publishes this pointer. Version directories alone are never ready.
///
/// Version 1 commits point into the retired hidden-version layout and remain readable only so the
/// service can migrate them without touching a playing path. Version 2 commits point at immutable
/// direct children of Video/Web/Scene. The metadata rename remains the only ready commit point.
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
}

/// Disk preparation is detached from UI. Publication is a small, synchronous operation performed
/// by the service after checking the live account and job attempt. No old content is deleted.
nonisolated enum SteamWorkshopLibraryTransaction {
    /// Read-only compatibility root for version 1 commits. New content is never prepared here.
    static let versionsName = ".mywallpaperx-steam-versions"
    static let incomingName = ".mywallpaperx-steam-incoming"
    static let metadataName = ".mywallpaperx-steam-metadata"
    static let ownershipMarkerName = ".mywallpaperx-steam-version.json"
    static let maxBytes = 8 * 1024 * 1024 * 1024
    static let maximumRetainedBytesBeforeAdmissions = 16 * 1024 * 1024 * 1024
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

    private static let publicTypeDirectories = [
        "video": "Video",
        "web": "Web",
        "scene": "Scene",
    ]
    private final class FD {
        let value: Int32
        init(_ value: Int32) throws {
            guard value >= 0 else { throw Failure(message: "文件操作失败：\(String(cString: strerror(errno)))") }
            self.value = value
        }
        deinit { close(value) }
    }
    private static func require(_ condition: Bool, _ message: String = "下载内容或文件路径校验失败。") throws {
        guard condition else { throw Failure(message: message) }
    }
    private static func parts(_ path: String) throws -> [String] {
        let values = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        try require(!values.isEmpty && values.count <= 64 && path.utf8.count <= 16384)
        try require(values.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") && !$0.utf8.contains(0) })
        return values
    }
    private static func directory(_ parent: FD, _ name: String, create: Bool = false, exclusive: Bool = false) throws -> FD {
        if create && mkdirat(parent.value, name, 0o700) != 0 {
            try require(!exclusive && errno == EEXIST, "无法创建下载版本目录。")
        }
        return try FD(openat(parent.value, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }
    private static func absoluteDirectory(_ url: URL, create: Bool = false) throws -> FD {
        try require(url.isFileURL && url.path.hasPrefix("/"))
        var fd = try FD(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC))
        for part in try parts(String(url.path.dropFirst())) {
            fd = try directory(fd, part, create: create)
        }
        return fd
    }
    private static func info(_ fd: FD, regular: Bool) throws -> stat {
        var value = stat()
        try require(fstat(fd.value, &value) == 0)
        try require((value.st_mode & S_IFMT) == (regular ? S_IFREG : S_IFDIR))
        if regular { try require(value.st_nlink == 1 && value.st_size >= 0, "拒绝链接或特殊下载文件。") }
        return value
    }
    private static func openFile(_ root: FD, _ path: String, create: Bool = false) throws -> FD {
        let components = try parts(path)
        var parent = root
        for part in components.dropLast() { parent = try directory(parent, part, create: create) }
        let flags = O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (create ? O_WRONLY | O_CREAT | O_EXCL : O_RDONLY)
        let fd = try FD(openat(parent.value, components.last!, flags, mode_t(0o600)))
        _ = try info(fd, regular: true)
        return fd
    }
    private struct FileEntry { let path: String; let size: Int64; let isDirectory: Bool }
    private static func files(_ root: FD, topLevelLimit: Int? = nil) throws -> [FileEntry] {
        var result: [FileEntry] = []
        var count = 0
        var topLevelCount = 0
        var pathBytes = 0
        func walk(_ fd: FD, prefix: String, depth: Int) throws {
            try Task.checkCancellation()
            try require(depth <= 64)
            let duplicate = dup(fd.value)
            guard duplicate >= 0 else { throw Failure(message: "无法枚举下载目录。") }
            guard let stream = fdopendir(duplicate) else { close(duplicate); throw Failure(message: "无法枚举下载目录。") }
            defer { closedir(stream) }
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    try require(errno == 0, "下载目录枚举失败。")
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                if depth == 0 {
                    topLevelCount += 1
                    if let topLevelLimit { try require(topLevelCount < topLevelLimit, "保留的下载/版本目录达到数量预算。") }
                }
                let path = prefix + name
                _ = try parts(path)
                count += 1; pathBytes += path.utf8.count
                try require(count <= 200_000 && pathBytes <= 8 * 1024 * 1024)
                var value = stat()
                try require(fstatat(fd.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0)
                switch value.st_mode & S_IFMT {
                case S_IFDIR:
                    result.append(FileEntry(path: path, size: 0, isDirectory: true))
                    try walk(directory(fd, name), prefix: path + "/", depth: depth + 1)
                case S_IFREG:
                    try require(value.st_nlink == 1 && value.st_size >= 0)
                    result.append(FileEntry(path: path, size: value.st_size, isDirectory: false))
                default: throw Failure(message: "下载目录包含链接或特殊文件。")
                }
            }
        }
        try walk(root, prefix: "", depth: 0)
        return result.sorted {
            $0.path.precomposedStringWithCanonicalMapping.utf8.lexicographicallyPrecedes($1.path.precomposedStringWithCanonicalMapping.utf8)
        }
    }
    private static func write(_ data: Data, to fd: FD) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd.value, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                try require(n > 0, "下载入库写入失败，可能没有足够磁盘空间。")
                offset += n
            }
        }
    }
    private static func readData(_ fd: FD, maximumBytes: Int) throws -> Data {
        let before = try info(fd, regular: true)
        try require(before.st_size >= 0 && before.st_size <= maximumBytes, "下载记录超出读取预算。")
        var data = Data(count: Int(before.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd.value, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                try require(count > 0, "下载记录读取不完整。")
                offset += count
            }
        }
        let after = try info(fd, regular: true)
        try require(samePinnedFileSnapshot(after, before),
            "下载记录在读取期间发生变化。")
        return data
    }
    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private static func publicTypeDirectoryName(for contentType: String) throws -> String {
        guard let name = publicTypeDirectories[contentType] else {
            throw Failure(message: "下载项目缺少有效的 scene/web/video 类型。")
        }
        return name
    }

    private static func managedPublicDirectoryWorkshopID(_ name: String) -> String? {
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
        switch version {
        case 1:
            guard directoryName.utf8.count == 36, UUID(uuidString: directoryName) != nil else { return nil }
            return "v1:" + directoryName.lowercased()
        case 2:
            guard publicTypeDirectories[contentType] != nil,
                  validID(workshopId), validPublicDirectoryName(directoryName, workshopId: workshopId) else { return nil }
            return "v2:\(contentType):\(directoryName.lowercased())"
        default:
            return nil
        }
    }

    static func storageIdentity(for commit: SteamWorkshopLibraryCommit) -> String? {
        storageIdentity(forVersion: commit.version, contentType: commit.contentType,
                        workshopId: commit.workshopId, directoryName: commit.directoryName)
    }

    static func isValidStorageIdentity(_ identity: String) -> Bool {
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, parts[0] == "v1" || parts[0] == "incoming" {
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
                    "文件系统未提供完整创建身份，拒绝写入或删除。")
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

    private static func markerCommit(in root: FD) throws -> SteamWorkshopLibraryCommit {
        let marker = try openFile(root, ownershipMarkerName)
        let data = try readData(marker, maximumBytes: 16 * 1024)
        let commit = try JSONDecoder().decode(SteamWorkshopLibraryCommit.self, from: data)
        try require(commit.version == 2 && storageIdentity(for: commit) != nil,
                    "受管下载版本标记无效。")
        return commit
    }

    private static func writeMarker(_ commit: SteamWorkshopLibraryCommit, to root: FD) throws {
        let file = try openFile(root, ownershipMarkerName, create: true)
        try write(try JSONEncoder().encode(commit), to: file)
        try require(fsync(file.value) == 0, "下载版本标记无法同步到磁盘。")
    }

    private static func childNames(_ root: FD, limit: Int = 1_024) throws -> [String] {
        let duplicate = dup(root.value)
        guard duplicate >= 0 else { throw Failure(message: "无法枚举下载目录。") }
        guard let stream = fdopendir(duplicate) else {
            close(duplicate)
            throw Failure(message: "无法枚举下载目录。")
        }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                try require(errno == 0, "下载目录枚举失败。")
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
            try require(names.count <= limit, "保留的下载/版本目录超过回收扫描预算。")
        }
        return names.sorted()
    }

    /// Descriptor-anchored deletion that never follows links and verifies that
    /// the directory name still identifies the opened inode before unlinking it.
    private struct OwnedDirectoryChanged: Error {}

    private static func removeOwnedTree(
        parent: FD,
        name: String,
        expectedIdentity: SteamWorkshopStagingLeaseIdentity? = nil,
        expectedMarker: SteamWorkshopLibraryCommit? = nil,
        honorTaskCancellation: Bool = true
    ) throws {
        var named = stat()
        try require(fstatat(parent.value, name, &named, AT_SYMLINK_NOFOLLOW) == 0)
        try require((named.st_mode & S_IFMT) == S_IFDIR, "仅回收受管版本目录。")
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
                try require(unlinkat(opened.value, child, 0) == 0, "版本文件回收失败。")
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
                try require(unlinkat(opened.value, child, 0) == 0, "版本文件回收失败。")
            }
        }

        var current = stat()
        try require(fstatat(parent.value, name, &current, AT_SYMLINK_NOFOLLOW) == 0)
        guard (current.st_mode & S_IFMT) == S_IFDIR
            && sameFilesystemObject(current, openedInfo) else {
            throw OwnedDirectoryChanged()
        }
        try require(unlinkat(parent.value, name, AT_REMOVEDIR) == 0, "版本目录回收失败。")
    }
    // Retention never silently consumes unlimited disk while lifecycle-aware garbage collection is pending.
    private static func admitRetainedBytes(in root: FD) throws {
        var total: Int64 = 0
        for entry in try files(root, topLevelLimit: 64) {
            try require(entry.size <= Int64(maximumRetainedBytesBeforeAdmissions) - total,
                "保留的下载/版本已达到磁盘预算；请先处理旧任务和版本。")
            total += entry.size
        }
    }

    /// The public layout is still a version store. Count v1 compatibility,
    /// crash-orphan incoming and every reserved v2 generation before admitting
    /// another full copy; unrelated user folders in the public roots are not owned.
    private static func admitLibraryRetainedBytes(in library: FD, adding bytes: Int64) throws {
        try require(bytes >= 0 && bytes <= Int64(maxBytes))
        var total: Int64 = 0
        func add(_ amount: Int64) throws {
            try require(amount >= 0
                && amount <= Int64(maximumRetainedBytesBeforeAdmissions) - total,
                "保留的下载/版本已达到磁盘预算；请先处理旧任务和版本。")
            total += amount
        }
        func addTree(_ root: FD, topLevelLimit: Int? = nil) throws {
            for entry in try files(root, topLevelLimit: topLevelLimit) {
                try add(entry.size)
            }
        }

        if let versions = try? directory(library, versionsName) {
            try addTree(versions, topLevelLimit: 64)
        }
        if let incoming = try? directory(library, incomingName) {
            try addTree(incoming, topLevelLimit: 64)
        }
        for typeDirectoryName in publicTypeDirectories.values.sorted() {
            guard let typeRoot = try? directory(library, typeDirectoryName) else { continue }
            for name in try childNames(typeRoot, limit: 100_000)
            where managedPublicDirectoryWorkshopID(name) != nil {
                let managed = try directory(typeRoot, name)
                try addTree(managed)
            }
        }
        try add(bytes)
    }

    static func availableDiskBytes(at root: URL) throws -> Int64 {
        _ = try absoluteDirectory(root, create: true)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        guard let value = attributes[.systemFreeSize] as? NSNumber else {
            throw Failure(message: "无法读取下载磁盘的剩余空间。")
        }
        return value.int64Value
    }

    static func areOnSameFileSystem(_ lhs: URL, _ rhs: URL) throws -> Bool {
        _ = try absoluteDirectory(lhs, create: true)
        _ = try absoluteDirectory(rhs, create: true)
        let left = try FileManager.default.attributesOfFileSystem(forPath: lhs.path)[.systemNumber] as? NSNumber
        let right = try FileManager.default.attributesOfFileSystem(forPath: rhs.path)[.systemNumber] as? NSNumber
        guard let left, let right else { throw Failure(message: "无法识别下载目录所在磁盘。") }
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
        if commit.version == 2 {
            guard (try? markerCommit(in: root)) == commit else { return false }
        }
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
            try require(errno == ENOENT, "配置的下载目录无法访问。")
        }
        throw Failure(message: "配置的下载目录无法解析。")
    }
    static func stagingBase(at url: URL) throws -> URL {
        let root = try absoluteDirectory(url, create: true)
        try admitRetainedBytes(in: root)
        return url
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
            throw Failure(message: "拒绝清理不属于当前下载任务的暂存目录。")
        }
        let root = try absoluteDirectory(configured)
        let name = validated.lastPathComponent
        var named = stat()
        try require(fstatat(root.value, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                    "无法检查下载暂存目录。")
        try require((named.st_mode & S_IFMT) == S_IFDIR, "下载暂存目录身份无效。")
        let opened = try directory(root, name)
        let openedInfo = try info(opened, regular: false)
        try require(sameFilesystemObject(named, openedInfo),
                    "下载暂存目录在验收期间发生变化。")
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
                    "下载暂存缺少完整创建身份，拒绝按路径清理。")
        let configured = try configuredRoot(stagingRoot)
        guard let validated = SteamWorkshopStagedReceipt.validatedStagingURL(
            path: stagingURL.path,
            stagingRoot: configured.path
        ), validated.path == stagingURL.path else {
            throw Failure(message: "拒绝清理不属于当前下载任务的暂存目录。")
        }
        let root = try absoluteDirectory(configured)
        let name = validated.lastPathComponent
        var value = stat()
        if fstatat(root.value, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw Failure(message: "无法检查下载暂存目录。")
        }
        do {
            try removeOwnedTree(parent: root, name: name, expectedIdentity: expectedIdentity)
        } catch is OwnedDirectoryChanged {
            throw Failure(message: "下载暂存目录已被同名替换，拒绝清理。")
        }
    }

    static func prepare(receipt: SteamWorkshopStagedReceipt, attempt: Int,
                        libraryRoot: URL) throws -> SteamWorkshopLibraryCommit {
        try require(receipt.version == 2 && receipt.stagingLeaseIdentity?.isComplete == true,
                    "下载凭证缺少稳定的暂存目录身份。")
        return try prepareSource(
            sourceURL: receipt.stagingURL,
            expectedSourceIdentity: receipt.stagingLeaseIdentity,
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

    /// Copy a retired hidden v1 commit into the public immutable layout. The caller publishes the
    /// returned v2 commit only after re-reading the current metadata pointer; the v1 tree remains
    /// available to an existing player until lifecycle-aware reclamation proves it is unused.
    static func migrationRequiredBytes(
        for commit: SteamWorkshopLibraryCommit,
        libraryRoot: URL
    ) throws -> Int64 {
        try require(commit.version == 1 && !commit.removed && storageIdentity(for: commit) != nil,
                    "旧下载版本身份无效，无法迁移。")
        let source = try absoluteDirectory(try contentURL(for: commit, libraryRoot: libraryRoot))
        let inventory = try files(source)
        try require(!inventory.contains { $0.path == ownershipMarkerName }, "旧下载版本包含保留标记名。")
        return try inventory.reduce(Int64(0)) { partial, entry in
            try require(entry.size <= Int64(maxBytes) - partial)
            return partial + entry.size
        }
    }

    static func migrateLegacyCommit(_ commit: SteamWorkshopLibraryCommit,
                                    libraryRoot: URL) throws -> SteamWorkshopLibraryCommit {
        let sourceURL = try contentURL(for: commit, libraryRoot: libraryRoot)
        let total = try migrationRequiredBytes(for: commit, libraryRoot: libraryRoot)
        return try prepareSource(
            sourceURL: sourceURL,
            expectedSourceIdentity: nil,
            verifiedBytes: total,
            expectedDigest: commit.contentDigest,
            workshopId: commit.workshopId,
            jobId: commit.jobId,
            attempt: commit.attempt,
            manifestId: commit.manifestId,
            committedAt: commit.committedAt,
            libraryRoot: libraryRoot
        )
    }

    private static func prepareSource(sourceURL: URL,
                                      expectedSourceIdentity: SteamWorkshopStagingLeaseIdentity?,
                                      verifiedBytes: Int64, expectedDigest: String,
                                      workshopId: String, jobId: String, attempt: Int,
                                      manifestId: String, committedAt: Date,
                                      libraryRoot: URL) throws -> SteamWorkshopLibraryCommit {
        try Task.checkCancellation()
        try require(validID(workshopId) && !jobId.isEmpty && attempt > 0
            && verifiedBytes > 0 && verifiedBytes <= Int64(maxBytes))
        let source = try absoluteDirectory(sourceURL)
        if let expectedSourceIdentity {
            let sourceInfo = try info(source, regular: false)
            try require(sameDirectory(sourceInfo, as: expectedSourceIdentity),
                        "下载暂存目录已被同名替换，拒绝入库。")
        }
        let inventory = try files(source)
        try require(!inventory.contains { $0.path == ownershipMarkerName }, "下载内容使用了保留标记名。")
        let library = try absoluteDirectory(libraryRoot, create: true)
        try admitLibraryRetainedBytes(in: library, adding: verifiedBytes)
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
                NSLog("MWX Steam library: owned incoming rollback failed: %@", error.localizedDescription)
            }
            _ = unlinkat(library.value, incomingName, AT_REMOVEDIR)
        }
        let destination = try directory(version, "content", create: true, exclusive: true)
        var total: Int64 = 0
        var tree = SHA256()
        for entry in inventory {
            try Task.checkCancellation()
            if entry.isDirectory {
                var parent = destination
                for part in try parts(entry.path) { parent = try directory(parent, part, create: true) }
                continue
            }
            try require(entry.size <= Int64(maxBytes) - total)
            let input = try openFile(source, entry.path)
            let before = try info(input, regular: true)
            try require(before.st_size == entry.size)
            let output = try openFile(destination, entry.path, create: true)
            var remaining = entry.size
            var hash = SHA256()
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            while remaining > 0 {
                try Task.checkCancellation()
                let n = read(input.value, &bytes, min(bytes.count, Int(remaining)))
                if n < 0 && errno == EINTR { continue }
                try require(n > 0, "下载源文件在入库时被截断。")
                let data = Data(bytes.prefix(n))
                hash.update(data: data)
                try write(data, to: output)
                remaining -= Int64(n)
            }
            let after = try info(input, regular: true)
            try require(after.st_size == before.st_size && after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec
                && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)
            try require(fsync(output.value) == 0, "下载文件无法同步到磁盘。")
            let path = Data(entry.path.precomposedStringWithCanonicalMapping.utf8)
            tree.update(data: littleEndian(UInt32(path.count))); tree.update(data: path)
            tree.update(data: littleEndian(UInt64(entry.size))); tree.update(data: Data(hash.finalize()))
            total += entry.size
        }
        let digest = tree.finalize().map { String(format: "%02x", $0) }.joined()
        try require(total == verifiedBytes && digest == expectedDigest, "下载内容在入库前发生变化。")
        // Bounded project parsing from the newly copied, descriptor-anchored version.
        let projectFD = try openFile(destination, "project.json")
        let projectSize = try info(projectFD, regular: true).st_size
        try require(projectSize > 0 && projectSize <= 1024 * 1024, "project.json 超出解析预算。")
        var projectData = Data(count: Int(projectSize))
        try projectData.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let n = read(projectFD.value, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                try require(n > 0, "project.json 读取不完整。")
                offset += n
            }
        }
        guard let project = try JSONSerialization.jsonObject(with: projectData) as? [String: Any],
              let rawType = project["type"] as? String else {
            throw Failure(message: "下载项目缺少有效的 scene/web/video 类型。")
        }
        let contentType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try require(["scene", "web", "video"].contains(contentType),
            "下载项目缺少有效的 scene/web/video 类型。")
        let entry = (project["file"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if let entry { _ = try parts(entry) }
        if let preview = (project["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty { _ = try parts(preview) }
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
            guard let entry else { throw Failure(message: "下载项目缺少入口文件。") }
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
        try require(fsync(destination.value) == 0, "下载版本目录无法同步到磁盘。")
        try require(renameatx_np(version.value, "content", typeDirectory.value, finalDirectoryName, UInt32(RENAME_EXCL)) == 0,
                    "下载版本发布失败；旧版本保持不变。")
        try require(fsync(typeDirectory.value) == 0, "下载类型目录无法同步到磁盘。")
        return commit
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && (UInt64(id) ?? 0) > 0
    }
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
              managedPublicDirectoryWorkshopID(url.lastPathComponent) != nil,
              let configuredLibrary = try? configuredRoot(libraryRoot),
              let physicalParent = try? configuredRoot(url.deletingLastPathComponent()) else { return false }
        return publicTypeDirectories.values.contains { typeDirectoryName in
            let expected = configuredLibrary.appendingPathComponent(typeDirectoryName, isDirectory: true)
            guard let physicalExpected = try? configuredRoot(expected) else { return false }
            return physicalExpected.standardizedFileURL.path
                == physicalParent.standardizedFileURL.path
        }
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

        if let versions = try? directory(library, versionsName) {
            for name in try childNames(versions) {
                try Task.checkCancellation()
                guard name.utf8.count == 36, UUID(uuidString: name) != nil else {
                    skippedEntries.append(versionsName + "/" + name)
                    continue
                }
                var value = stat()
                guard fstatat(versions.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      (value.st_mode & S_IFMT) == S_IFDIR else {
                    skippedEntries.append(versionsName + "/" + name)
                    continue
                }
                try await removeIfAdmitted(parent: versions, name: name,
                    identity: "v1:" + name.lowercased(), value: value,
                    entryLabel: versionsName + "/" + name)
            }
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
                      marker.directoryName == name,
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

    static func publishedMetadata(libraryRoot: URL, requireComplete: Bool = false,
                                  matchingItemID: String? = nil, matchingFilename: String? = nil) throws -> [String: Data] {
        if let matchingFilename { try require(matchingFilename.utf8.count <= 255
            && matchingFilename.hasSuffix(".json") && !matchingFilename.contains("/") && !matchingFilename.utf8.contains(0)) }
        let library: FD
        do {
            library = try absoluteDirectory(libraryRoot)
        } catch {
            if errno == ENOENT && !requireComplete { return [:] }
            throw error
        }
        let index: FD
        do {
            index = try directory(library, metadataName)
        } catch {
            if errno == ENOENT && !requireComplete { return [:] }
            throw error
        }
        var result: [String: Data] = [:]
        for name in try childNames(index, limit: 100_000) {
            try Task.checkCancellation()
            guard name.hasSuffix(".json"), matchingFilename == nil || matchingFilename == name else { continue }
            let itemID = String(name.dropLast(5))
            guard (matchingFilename != nil || validID(itemID)), matchingItemID == nil || matchingItemID == itemID else { continue }
            do {
                let file = try openFile(index, name)
                result[itemID] = try readData(file, maximumBytes: 4 * 1024 * 1024)
            } catch {
                if requireComplete { throw error }
            }
        }
        return result
    }

    /// The rename is the commit point. Nothing after it may report a pre-commit failure.
    static func publish(metadata: Data, itemID: String, libraryRoot: URL) throws {
        try require(validID(itemID) && metadata.count <= 4 * 1024 * 1024)
        let library = try absoluteDirectory(libraryRoot)
        let index = try directory(library, metadataName, create: true)
        let name = ".pending-" + UUID().uuidString
        let file = try openFile(index, name, create: true)
        defer { unlinkat(index.value, name, 0) }
        try write(metadata, to: file)
        try require(fsync(file.value) == 0, "下载记录无法同步到磁盘。")
        try require(renameat(index.value, name, index.value, itemID + ".json") == 0, "下载记录提交失败；旧版本保持不变。")
        _ = fsync(index.value)
    }
}
