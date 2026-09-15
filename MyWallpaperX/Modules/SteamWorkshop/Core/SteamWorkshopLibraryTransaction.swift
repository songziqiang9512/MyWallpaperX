import Foundation
import CryptoKit
import Darwin

/// The existing metadata index publishes this pointer. Version directories alone are never ready.
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
    static let versionsName = ".mywallpaperx-steam-versions"
    static let metadataName = ".mywallpaperx-steam-metadata"
    static let maxBytes = 8 * 1024 * 1024 * 1024

    struct ReclamationResult: Equatable, Sendable {
        let removedDirectoryNames: [String]
        let retainedDirectoryNames: [String]
        let skippedDirectoryNames: [String]
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
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
        try require(after.st_dev == before.st_dev && after.st_ino == before.st_ino
            && after.st_size == before.st_size
            && after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec
            && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
            "下载记录在读取期间发生变化。")
        return data
    }
    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
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
    private static func removeOwnedTree(parent: FD, name: String) throws {
        var named = stat()
        try require(fstatat(parent.value, name, &named, AT_SYMLINK_NOFOLLOW) == 0)
        try require((named.st_mode & S_IFMT) == S_IFDIR, "仅回收受管版本目录。")
        let opened = try directory(parent, name)
        let openedInfo = try info(opened, regular: false)
        try require(named.st_dev == openedInfo.st_dev && named.st_ino == openedInfo.st_ino,
            "版本目录在回收前发生变化。")

        for child in try childNames(opened) {
            try Task.checkCancellation()
            var value = stat()
            try require(fstatat(opened.value, child, &value, AT_SYMLINK_NOFOLLOW) == 0)
            if (value.st_mode & S_IFMT) == S_IFDIR {
                try removeOwnedTree(parent: opened, name: child)
            } else {
                try require(unlinkat(opened.value, child, 0) == 0, "版本文件回收失败。")
            }
        }

        var current = stat()
        try require(fstatat(parent.value, name, &current, AT_SYMLINK_NOFOLLOW) == 0)
        try require((current.st_mode & S_IFMT) == S_IFDIR
            && current.st_dev == openedInfo.st_dev && current.st_ino == openedInfo.st_ino,
            "版本目录在回收期间被替换。")
        try require(unlinkat(parent.value, name, AT_REMOVEDIR) == 0, "版本目录回收失败。")
    }
    // Retention never silently consumes unlimited disk while lifecycle-aware garbage collection is pending.
    private static func admitRetainedBytes(in root: FD) throws {
        var total: Int64 = 0
        for entry in try files(root, topLevelLimit: 64) {
            try require(entry.size <= Int64(24 * 1024 * 1024 * 1024) - total,
                "保留的下载/版本已达到磁盘预算；请先处理旧任务和版本。")
            total += entry.size
        }
    }
    static func isAvailable(_ commit: SteamWorkshopLibraryCommit, libraryRoot: URL) -> Bool {
        guard !commit.removed, let url = try? contentURL(for: commit, libraryRoot: libraryRoot),
              let root = try? absoluteDirectory(url), let project = try? openFile(root, "project.json"),
              let size = try? info(project, regular: true).st_size, size > 0, size <= 1024 * 1024 else { return false }
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

    /// Deletes only one exact helper-owned direct staging lease. Validation is
    /// lexical first and deletion remains descriptor-relative/no-follow, so an
    /// unknown sibling or a replaced/symlinked lease is never adopted.
    static func removeStagingLease(stagingURL: URL, stagingRoot: URL) throws {
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
        try removeOwnedTree(parent: root, name: name)
    }

    static func prepare(receipt: SteamWorkshopStagedReceipt, attempt: Int, libraryRoot: URL) throws -> SteamWorkshopLibraryCommit {
        try Task.checkCancellation()
        try require(receipt.version == 2 && attempt > 0 && receipt.verifiedBytes > 0 && receipt.verifiedBytes <= maxBytes)
        let source = try absoluteDirectory(receipt.stagingURL)
        let inventory = try files(source)
        let library = try absoluteDirectory(libraryRoot, create: true)
        let versions = try directory(library, versionsName, create: true)
        try admitRetainedBytes(in: versions)
        let name = UUID().uuidString.lowercased()
        let version = try directory(versions, name, create: true, exclusive: true)
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
        try require(total == receipt.verifiedBytes && digest == receipt.contentDigest, "下载内容在入库前发生变化。")
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
        return SteamWorkshopLibraryCommit(version: 1, workshopId: receipt.workshopId, jobId: receipt.jobId,
            attempt: attempt, directoryName: name, manifestId: receipt.manifestId, contentDigest: digest,
            contentType: contentType, entryPath: entry, committedAt: Date())
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && (UInt64(id) ?? 0) > 0
    }
    static func contentURL(for commit: SteamWorkshopLibraryCommit, libraryRoot: URL) throws -> URL {
        try require(commit.version == 1 && validID(commit.workshopId) && UUID(uuidString: commit.directoryName) != nil)
        try require(commit.directoryName.utf8.count == 36 && !commit.directoryName.contains("/"))
        return libraryRoot.appendingPathComponent(versionsName).appendingPathComponent(commit.directoryName).appendingPathComponent("content", isDirectory: true)
    }

    static func versionDirectoryName(containing url: URL, libraryRoot: URL) -> String? {
        guard url.isFileURL,
              let configuredLibrary = try? configuredRoot(libraryRoot) else { return nil }
        let versions = configuredLibrary.appendingPathComponent(versionsName, isDirectory: true)
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedVersions = versions.resolvingSymlinksInPath().standardizedFileURL
        let prefix = resolvedVersions.path + "/"
        guard resolvedURL.path.hasPrefix(prefix) else { return nil }
        let remainder = resolvedURL.path.dropFirst(prefix.count)
        guard let first = remainder.split(separator: "/", omittingEmptySubsequences: true).first else {
            return nil
        }
        let name = String(first)
        guard name.utf8.count == 36, UUID(uuidString: name) != nil else { return nil }
        return name.lowercased()
    }

    /// Reclaims only direct UUID version directories that are old enough and
    /// absent from the caller's complete live/reference set. Unknown entries are
    /// left untouched. The caller owns readiness, job and playback identities.
    static func reclaimVersions(
        libraryRoot: URL,
        retaining directoryNames: Set<String>,
        minimumAge: TimeInterval,
        now: Date = Date()
    ) throws -> ReclamationResult {
        try require(minimumAge >= 0 && minimumAge.isFinite)
        let library = try absoluteDirectory(libraryRoot, create: true)
        let versions: FD
        do {
            versions = try directory(library, versionsName)
        } catch {
            if errno == ENOENT {
                return ReclamationResult(removedDirectoryNames: [], retainedDirectoryNames: [], skippedDirectoryNames: [])
            }
            throw error
        }
        let retained = Set(directoryNames.map { $0.lowercased() })
        var removedNames: [String] = []
        var retainedNames: [String] = []
        var skippedNames: [String] = []
        for name in try childNames(versions) {
            try Task.checkCancellation()
            let normalized = name.lowercased()
            guard name.utf8.count == 36, UUID(uuidString: name) != nil else {
                skippedNames.append(name)
                continue
            }
            if retained.contains(normalized) {
                retainedNames.append(normalized)
                continue
            }
            var value = stat()
            guard fstatat(versions.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                  (value.st_mode & S_IFMT) == S_IFDIR else {
                skippedNames.append(name)
                continue
            }
            let modified = Date(timeIntervalSince1970:
                TimeInterval(value.st_mtimespec.tv_sec) + TimeInterval(value.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard now.timeIntervalSince(modified) >= minimumAge else {
                retainedNames.append(normalized)
                continue
            }
            try removeOwnedTree(parent: versions, name: name)
            removedNames.append(normalized)
        }
        return ReclamationResult(
            removedDirectoryNames: removedNames.sorted(),
            retainedDirectoryNames: retainedNames.sorted(),
            skippedDirectoryNames: skippedNames.sorted()
        )
    }

    /// Reads the single published ready index without following metadata links.
    /// Invalid/unrelated direct children are ignored; page/view lifecycle is not
    /// part of ready discovery.
    static func publishedMetadata(libraryRoot: URL) throws -> [String: Data] {
        let library: FD
        do {
            library = try absoluteDirectory(libraryRoot)
        } catch {
            if errno == ENOENT { return [:] }
            throw error
        }
        let index: FD
        do {
            index = try directory(library, metadataName)
        } catch {
            if errno == ENOENT { return [:] }
            throw error
        }
        var result: [String: Data] = [:]
        for name in try childNames(index, limit: 100_000) {
            try Task.checkCancellation()
            guard name.hasSuffix(".json") else { continue }
            let itemID = String(name.dropLast(5))
            guard validID(itemID),
                  let file = try? openFile(index, name),
                  let data = try? readData(file, maximumBytes: 4 * 1024 * 1024) else {
                continue
            }
            result[itemID] = data
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
