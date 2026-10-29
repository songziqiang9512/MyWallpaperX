import Foundation
import CryptoKit
import Darwin

/// Descriptor-bound filesystem and content-digest mechanics for download
/// publication. Playback never scans or hashes an author tree here.
nonisolated enum SteamWorkshopStorageTree {
    static let ownershipMarkerName = ".mywallpaperx-steam-version.json"
    static let maximumEntries = 200_000
    static let maximumPathBytes = 8 * 1_024 * 1_024

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    enum IntegrityError: LocalizedError {
        case sourceChanged
        var errorDescription: String? {
            switch self {
            case .sourceChanged: return "受管来源在读取期间发生变化。"
            }
        }
    }
    final class FD {
        let value: Int32
        init(_ value: Int32) throws {
            guard value >= 0 else { throw Failure(message: "文件操作失败：\(String(cString: strerror(errno)))") }
            self.value = value
        }
        deinit { close(value) }
    }
    struct FileEntry: Equatable {
        let path: String
        let size: Int64
        let isDirectory: Bool
    }
    static func require(_ condition: Bool, _ message: String = "下载内容或文件路径校验失败。") throws {
        guard condition else { throw Failure(message: message) }
    }
    static func parts(_ path: String) throws -> [String] {
        let values = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        try require(!values.isEmpty && values.count <= 64 && path.utf8.count <= 16_384)
        try require(values.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".."
            && !$0.contains(":") && !$0.utf8.contains(0) })
        return values
    }
    static func directory(_ parent: FD, _ name: String, create: Bool = false, exclusive: Bool = false) throws -> FD {
        if create && mkdirat(parent.value, name, 0o700) != 0 {
            try require(!exclusive && errno == EEXIST, "无法创建下载版本目录。")
        }
        return try FD(openat(parent.value, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }
    static func absoluteDirectory(_ url: URL, create: Bool = false) throws -> FD {
        try require(url.isFileURL && url.path.hasPrefix("/"))
        var fd = try FD(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC))
        for part in try parts(String(url.path.dropFirst())) { fd = try directory(fd, part, create: create) }
        return fd
    }
    static func info(_ fd: FD, regular: Bool) throws -> stat {
        var value = stat()
        try require(fstat(fd.value, &value) == 0)
        try require((value.st_mode & S_IFMT) == (regular ? S_IFREG : S_IFDIR))
        if regular { try require(value.st_nlink == 1 && value.st_size >= 0, "拒绝链接或特殊下载文件。") }
        return value
    }
    static func openFile(_ root: FD, _ path: String, create: Bool = false, readableOutput: Bool = false) throws -> FD {
        let components = try parts(path)
        var parent = root
        for part in components.dropLast() { parent = try directory(parent, part, create: create) }
        let access = create ? (readableOutput ? O_RDWR : O_WRONLY) | O_CREAT | O_EXCL : O_RDONLY
        let fd = try FD(openat(parent.value, components.last!, O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | access, mode_t(0o600)))
        _ = try info(fd, regular: true)
        return fd
    }
    static func pathPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.precomposedStringWithCanonicalMapping.utf8
            .lexicographicallyPrecedes(rhs.precomposedStringWithCanonicalMapping.utf8)
    }
    static func files(_ root: FD, checkCancellation: (() throws -> Void)? = nil) throws -> [FileEntry] {
        var result: [FileEntry] = []
        var count = 0, pathBytes = 0
        func walk(_ fd: FD, prefix: String, depth: Int) throws {
            try checkCancellation?()
            try require(depth <= 64)
            // A fresh open description prevents readdir from changing the root
            // descriptor's shared directory offset across repeated inventories.
            let duplicate = openat(fd.value, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
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
                var value = stat()
                try require(fstatat(fd.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0)
                let path = prefix + name
                _ = try parts(path)
                count += 1; pathBytes += path.utf8.count
                try require(count <= maximumEntries && pathBytes <= maximumPathBytes)
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
        return result.sorted { pathPrecedes($0.path, $1.path) }
    }
    static func sameSnapshot(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
            && lhs.st_birthtimespec.tv_sec == rhs.st_birthtimespec.tv_sec
            && lhs.st_birthtimespec.tv_nsec == rhs.st_birthtimespec.tv_nsec
    }
    static func write(_ data: Data, to fd: FD) throws {
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
    static func readData(_ fd: FD, maximumBytes: Int,
                         checkCancellation: (() throws -> Void)? = nil) throws -> Data {
        let before = try info(fd, regular: true)
        try require(maximumBytes >= 0 && before.st_size <= maximumBytes, "下载记录超出读取预算。")
        var data = Data(count: Int(before.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try checkCancellation?()
                let n = pread(fd.value, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, off_t(offset))
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw IntegrityError.sourceChanged }
                offset += n
            }
        }
        guard sameSnapshot(try info(fd, regular: true), before) else { throw IntegrityError.sourceChanged }
        return data
    }
    /// Hash and copy the staged file in one bounded stream.
    static func streamFile(_ input: FD, entry: FileEntry, output: FD? = nil,
                           checkCancellation: (() throws -> Void)? = nil) throws -> SceneSourceManifest.FileFact {
        let before = try info(input, regular: true)
        guard before.st_size == entry.size else { throw IntegrityError.sourceChanged }
        var offset: Int64 = 0
        var hash = SHA256()
        var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
        while offset < entry.size {
            try checkCancellation?()
            let n = pread(input.value, &bytes, min(bytes.count, Int(entry.size - offset)), off_t(offset))
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw IntegrityError.sourceChanged }
            let data = Data(bytes.prefix(n))
            hash.update(data: data)
            if let output { try write(data, to: output) }
            offset += Int64(n)
        }
        try checkCancellation?()
        guard sameSnapshot(try info(input, regular: true), before) else { throw IntegrityError.sourceChanged }
        return SceneSourceManifest.FileFact(path: entry.path, size: entry.size,
            sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    static func treeDigest(_ facts: [SceneSourceManifest.FileFact]) throws -> String {
        var tree = SHA256()
        for fact in facts.sorted(by: { pathPrecedes($0.path, $1.path) }) {
            _ = try parts(fact.path)
            try require(fact.size >= 0 && SceneSourceManifest.isSHA256(fact.sha256))
            let path = Data(fact.path.precomposedStringWithCanonicalMapping.utf8)
            var length = UInt32(path.count).littleEndian
            var size = UInt64(fact.size).littleEndian
            withUnsafeBytes(of: &length) { tree.update(data: Data($0)) }
            tree.update(data: path)
            withUnsafeBytes(of: &size) { tree.update(data: Data($0)) }
            let bytes = Array(fact.sha256.utf8)
            let digest = stride(from: 0, to: bytes.count, by: 2).map { index -> UInt8 in
                func nibble(_ x: UInt8) -> UInt8 { x <= 57 ? x - 48 : x - 87 }
                return nibble(bytes[index]) * 16 + nibble(bytes[index + 1])
            }
            tree.update(data: Data(digest))
        }
        return tree.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
