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
    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
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
              let type = project["type"] as? String, ["scene", "web", "video"].contains(type.lowercased()) else {
            throw Failure(message: "下载项目缺少有效的 scene/web/video 类型。")
        }
        let contentType = type.lowercased()
        let entry = (project["file"] as? String)?.replacingOccurrences(of: "\\", with: "/")
        if let entry { _ = try parts(entry) }
        if let preview = project["preview"] as? String, !preview.isEmpty { _ = try parts(preview) }
        let dependency = project["dependency"] as? String
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
