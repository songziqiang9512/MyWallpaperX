import Foundation
import Darwin

/// Revision of the actual opened package. No import receipt or content digest
/// participates in playback identity; a new file revision gets a new cache key.
nonisolated struct ScenePackageFileRevision: Hashable, Sendable {
    let fileSystemID: UInt64
    let fileID: UInt64
    let byteCount: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

nonisolated struct ScenePkgIndex: Equatable, Sendable {
    let magic: String
    let entries: [Entry]
    let dataStartOffset: Int
    let fileSize: Int

    struct Entry: Identifiable, Hashable, Sendable {
        let path: String
        let offset: UInt32
        let size: UInt32

        var id: String { path }
    }
}

nonisolated struct ScenePkgReader {
    enum ReadError: LocalizedError {
        case fileTooSmall
        case invalidMagic(String)
        case truncatedTable
        case invalidPathData
        case limitExceeded(String)
        case invalidSource
        case sourceChanged

        var errorDescription: String? {
            switch self {
            case .fileTooSmall:
                return "Scene 资源包过小，无法读取 PKGV 头。"
            case let .invalidMagic(magic):
                return "Scene 资源包 magic 不匹配：\(magic)"
            case .truncatedTable:
                return "Scene 资源包文件表不完整。"
            case .invalidPathData:
                return "Scene 资源包文件表包含无法解析的路径。"
            case let .limitExceeded(name):
                return "Scene 资源包读取超过预算：\(name)"
            case .invalidSource:
                return "Scene 资源包来源不是可读取的普通文件。"
            case .sourceChanged:
                return "Scene 资源包在读取期间发生变化或被截断。"
            }
        }
    }

    /// A caller policy, not a claim about the PKGV format's maximum sizes.
    /// Mount callers select the index parsing budget. Root bounds selected
    /// entry ranges and consumer bytes before handing them to the reader.
    struct IndexLimits: Sendable {
        let maximumTableBytes: Int?
        let maximumEntries: Int?
        let maximumPathBytes: Int?
        let maximumMagicBytes: Int?

        static let bounded = IndexLimits(maximumTableBytes: 16 * 1_024 * 1_024,
            maximumEntries: 100_000, maximumPathBytes: 64 * 1_024, maximumMagicBytes: 64)
        static let compatibility = IndexLimits(maximumTableBytes: nil,
            maximumEntries: nil, maximumPathBytes: nil, maximumMagicBytes: nil)
    }

    /// Owns one opened file and its parsed index. pread keeps concurrent reads
    /// independent; a strong borrower keeps the FD open through every read.
    final class OpenPackage: Sendable {
        let index: ScenePkgIndex
        private let descriptor: Int32
        private let identity: FileIdentity
        let packagePath: String

        fileprivate convenience init(packageURL: URL, limits: IndexLimits,
                         checkCancellation: (() throws -> Void)?) throws {
            try checkCancellation?()
            let descriptor = Darwin.open(packageURL.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try self.init(ownedDescriptor: descriptor, limits: limits, checkCancellation: checkCancellation)
        }

        fileprivate init(ownedDescriptor descriptor: Int32, limits: IndexLimits,
                         checkCancellation: (() throws -> Void)?) throws {
            do {
                try checkCancellation?()
                let identity = try FileIdentity(descriptor)
                let index = try ScenePkgReader.parseIndex(fileSize: Int(identity.size), limits: limits,
                    checkCancellation: checkCancellation) { offset, count in
                        try ScenePkgReader.readRange(descriptor: descriptor, offset: offset,
                            count: count, checkCancellation: checkCancellation)
                    }
                guard try FileIdentity(descriptor) == identity else { throw ReadError.sourceChanged }
                self.packagePath = try ScenePkgReader.openedPath(descriptor)
                self.descriptor = descriptor
                self.identity = identity
                self.index = index
            } catch {
                close(descriptor)
                throw error
            }
        }

        deinit { close(descriptor) }

        var fileRevision: ScenePackageFileRevision {
            .init(fileSystemID: UInt64(bitPattern: Int64(identity.device)),
                fileID: UInt64(identity.inode), byteCount: UInt64(identity.size),
                modifiedSeconds: Int64(identity.modifiedSeconds), modifiedNanoseconds: Int64(identity.modifiedNanoseconds),
                changedSeconds: Int64(identity.changedSeconds), changedNanoseconds: Int64(identity.changedNanoseconds))
        }

        /// Root is the only product caller. It supplies a selected immutable
        /// entry from its range-bounded projection and owns the byte budget.
        /// The sink stages bytes until this same-FD read succeeds.
        func readEntryChunks(_ entry: ScenePkgIndex.Entry,
                             checkCancellation: (() throws -> Void)? = nil,
                             consume: (Data) throws -> Void) throws {
            try checkCancellation?()
            try checkStable()
            var consumed = 0
            while consumed < Int(entry.size) {
                try checkCancellation?()
                let chunk = try ScenePkgReader.readRange(descriptor: descriptor,
                    offset: index.dataStartOffset + Int(entry.offset) + consumed,
                    count: min(64 * 1_024, Int(entry.size) - consumed), checkCancellation: checkCancellation)
                try consume(chunk)
                consumed += chunk.count
            }
            try checkCancellation?()
            try checkStable()
        }

        func validateCurrentSource() throws { try checkStable() }

        private func checkStable() throws {
            guard try FileIdentity(descriptor) == identity else { throw ReadError.sourceChanged }
        }
    }

    private struct FileIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        let birthSeconds: Int
        let birthNanoseconds: Int

        init(_ descriptor: Int32) throws {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard value.st_mode & S_IFMT == S_IFREG, value.st_size >= 0,
                  UInt64(value.st_size) <= UInt64(Int.max) else { throw ReadError.invalidSource }
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec; changedNanoseconds = value.st_ctimespec.tv_nsec
            birthSeconds = value.st_birthtimespec.tv_sec; birthNanoseconds = value.st_birthtimespec.tv_nsec
        }
    }

    func openPackage(packageURL: URL, limits: IndexLimits = .bounded,
                     checkCancellation: (() throws -> Void)? = nil) throws -> OpenPackage {
        try OpenPackage(packageURL: packageURL, limits: limits, checkCancellation: checkCancellation)
    }

    func openPackage(duplicatingFileDescriptor descriptor: Int32, limits: IndexLimits = .bounded,
                     checkCancellation: (() throws -> Void)? = nil) throws -> OpenPackage {
        try checkCancellation?()
        let owned = fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        guard owned >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return try OpenPackage(ownedDescriptor: owned, limits: limits, checkCancellation: checkCancellation)
    }

    private static func openedPath(_ descriptor: Int32) throws -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func readRange(descriptor: Int32, offset: Int, count: Int,
                                  checkCancellation: (() throws -> Void)?) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        var bytes = [UInt8](repeating: 0, count: min(64 * 1_024, count))
        while result.count < count {
            try checkCancellation?()
            let amount = min(bytes.count, count - result.count)
            let n = pread(descriptor, &bytes, amount, off_t(offset + result.count))
            if n < 0 && errno == EINTR { continue }
            if n < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard n > 0 else { throw ReadError.sourceChanged }
            bytes.withUnsafeBufferPointer { result.append($0.baseAddress!, count: n) }
        }
        return result
    }

    private static func parseIndex(fileSize: Int, limits: IndexLimits, checkCancellation: (() throws -> Void)?,
                                    read: (Int, Int) throws -> Data) throws -> ScenePkgIndex {
        var cursor = 0

        func readBytes(_ count: Int) throws -> Data {
            try checkCancellation?()
            guard count >= 0, cursor <= fileSize, count <= fileSize - cursor else {
                throw ReadError.truncatedTable
            }
            if let maximum = limits.maximumTableBytes {
                guard cursor <= maximum, count <= maximum - cursor else {
                    throw ReadError.limitExceeded("table-bytes")
                }
            }
            let value = try read(cursor, count)
            cursor += count
            return value
        }

        func readUInt32() throws -> UInt32 {
            try readBytes(4).withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self).littleEndian
            }
        }

        guard fileSize >= 16 else { throw ReadError.fileTooSmall }
        let magicLength = Int(try readUInt32())
        guard magicLength > 0 else { throw ReadError.truncatedTable }
        if let maximum = limits.maximumMagicBytes, magicLength > maximum {
            throw ReadError.limitExceeded("magic-bytes")
        }

        guard let magic = String(data: try readBytes(magicLength), encoding: .utf8) else {
            throw ReadError.invalidPathData
        }
        guard magic.hasPrefix("PKGV") else {
            throw ReadError.invalidMagic(magic)
        }

        let entryCount = Int(try readUInt32())
        // Every entry needs at least a path-length word, one path byte and
        // offset/size words. Reject impossible counts before reserving memory.
        guard entryCount <= (fileSize - cursor) / 13 else { throw ReadError.truncatedTable }
        if let maximum = limits.maximumEntries, entryCount > maximum {
            throw ReadError.limitExceeded("entry-count")
        }
        var entries: [ScenePkgIndex.Entry] = []

        for _ in 0..<entryCount {
            let pathLength = Int(try readUInt32())
            guard pathLength > 0 else { throw ReadError.truncatedTable }
            if let maximum = limits.maximumPathBytes, pathLength > maximum {
                throw ReadError.limitExceeded("path-bytes")
            }
            let record = try readBytes(pathLength + 8)
            guard let path = String(data: record.prefix(pathLength), encoding: .utf8) else {
                throw ReadError.invalidPathData
            }
            let offset = record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pathLength, as: UInt32.self).littleEndian }
            let size = record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pathLength + 4, as: UInt32.self).littleEndian }
            entries.append(ScenePkgIndex.Entry(path: path, offset: offset, size: size))
        }

        let dataStartOffset = cursor
        return ScenePkgIndex(
            magic: magic,
            entries: entries,
            dataStartOffset: dataStartOffset,
            fileSize: fileSize
        )
    }
}
