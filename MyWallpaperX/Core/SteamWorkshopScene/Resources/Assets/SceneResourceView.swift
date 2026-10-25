import Foundation
import Darwin

/// Read-only Scene resource namespace. Earlier roots win when the same authored
/// relative path exists in more than one source.
nonisolated struct SceneResourceView: Sendable {
    enum Source: String, Hashable, Sendable {
        case package
        case loose
        case stock
    }

    enum ReadError: Error, Equatable {
        case invalidHandle
        case invalidPath
        case missing
        case symlinkEscape
        case unreadable
        case fileTooLarge
        case sourceChanged
    }

    /// A physical file revision for directory backing or an explicitly external
    /// user file. This is not a trusted package receipt or a content digest.
    struct FileIdentity: Hashable, Sendable {
        let path: String
        let size: UInt64
        let modifiedAtBits: UInt64
        let fileSystemID: UInt64
        let fileID: UInt64
        let statusChangedAtSeconds: Int64
        let statusChangedAtNanoseconds: Int64

        init(path: String, size: UInt64, modifiedAtBits: UInt64,
             fileSystemID: UInt64, fileID: UInt64,
             statusChangedAtSeconds: Int64, statusChangedAtNanoseconds: Int64) {
            self.path = path
            self.size = size
            self.modifiedAtBits = modifiedAtBits
            self.fileSystemID = fileSystemID
            self.fileID = fileID
            self.statusChangedAtSeconds = statusChangedAtSeconds
            self.statusChangedAtNanoseconds = statusChangedAtNanoseconds
        }

        fileprivate init(path: String, value: stat) throws {
            guard value.st_mode & S_IFMT == S_IFREG, value.st_size >= 0 else {
                throw ReadError.unreadable
            }
            self.path = path
            size = UInt64(value.st_size)
            let modified = Double(value.st_mtimespec.tv_sec)
                + Double(value.st_mtimespec.tv_nsec) / 1_000_000_000
            modifiedAtBits = modified.bitPattern
            fileSystemID = UInt64(bitPattern: Int64(value.st_dev))
            fileID = UInt64(value.st_ino)
            statusChangedAtSeconds = Int64(value.st_ctimespec.tv_sec)
            statusChangedAtNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        }

        fileprivate static func statFileIdentity(_ url: URL) throws -> FileIdentity {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            var value = stat()
            guard lstat(path, &value) == 0 else { throw ReadError.unreadable }
            return try FileIdentity(path: path, value: value)
        }
    }

    /// A directory file revision and an opened-package range are distinct
    /// source values. Neither depends on a historical import digest.
    typealias PackageIdentity = ScenePackageContentIdentity

    enum ContentIdentity: Hashable, Sendable {
        case file(FileIdentity)
        case package(PackageIdentity)

        var size: UInt64 {
            switch self {
            case let .file(file): file.size
            case let .package(entry): UInt64(entry.byteCount)
            }
        }
    }

    struct ReadSnapshot: Sendable {
        let data: Data
        let identity: ContentIdentity
    }

    /// The selected authored resource and an independently authorized user file
    /// are explicit inputs. An external URL never guesses an authored Root.
    enum FileInput: Hashable, Sendable {
        case resource(Handle)
        case externalFile(URL)

        static func == (lhs: FileInput, rhs: FileInput) -> Bool {
            switch (lhs, rhs) {
            case let (.resource(a), .resource(b)):
                a.owner === b.owner && a.relativePath == b.relativePath
                    && a.isLiteralEntry == b.isLiteralEntry
                    && a.wasSelectedEntry == b.wasSelectedEntry
            case let (.externalFile(a), .externalFile(b)): a == b
            default: false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case let .resource(handle):
                hasher.combine(0)
                hasher.combine(ObjectIdentifier(handle.owner))
                hasher.combine(handle.relativePath)
                hasher.combine(handle.isLiteralEntry)
                hasher.combine(handle.wasSelectedEntry)
            case let .externalFile(url):
                hasher.combine(1)
                hasher.combine(url)
            }
        }

        var diagnosticPath: String {
            switch self {
            case let .resource(handle): handle.diagnosticPath
            case let .externalFile(url): url.path
            }
        }
        var pathExtension: String { (diagnosticPath as NSString).pathExtension }
        var lastPathComponent: String { (diagnosticPath as NSString).lastPathComponent }

        func currentIdentity(checkCancellation: (() throws -> Void)? = nil) throws -> ContentIdentity {
            try checkCancellation?()
            switch self {
            case let .resource(handle): return try handle.currentIdentity(checkCancellation: checkCancellation)
            case let .externalFile(url): return .file(try FileIdentity.statFileIdentity(url))
            }
        }

        func readSnapshot(
            expectedIdentity: ContentIdentity? = nil,
            maximumBytes: Int? = nil,
            checkCancellation: (() throws -> Void)? = nil
        ) throws -> ReadSnapshot {
            switch self {
            case let .resource(handle):
                return try handle.readSnapshot(expectedIdentity: expectedIdentity,
                    maximumBytes: maximumBytes, checkCancellation: checkCancellation)
            case let .externalFile(url):
                // Preserve the separate external-file adapter and its mapped
                // bytes. Security scope/freeze/revision remain with its caller.
                try checkCancellation?()
                let before = try FileIdentity.statFileIdentity(url)
                guard expectedIdentity.map({ $0 == .file(before) }) ?? true else { throw ReadError.sourceChanged }
                guard maximumBytes.map({ $0 >= 0 && before.size <= UInt64($0) }) ?? true else {
                    throw ReadError.fileTooLarge
                }
                let data: Data
                do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
                catch { throw ReadError.unreadable }
                try checkCancellation?()
                guard try FileIdentity.statFileIdentity(url) == before else { throw ReadError.sourceChanged }
                return ReadSnapshot(data: data, identity: .file(before))
            }
        }

        func sibling(appendingSuffix suffix: String) throws -> FileInput {
            switch self {
            case let .resource(handle): return .resource(try handle.sibling(appendingSuffix: suffix))
            case let .externalFile(url): return .externalFile(URL(fileURLWithPath: url.path + suffix))
            }
        }
    }

    /// A selected namespace reference, not a file URL. Keeping its Root alive
    /// retains the directory boundary or the opened package descriptor.
    struct Handle: Sendable {
        let owner: Root
        let indexedResource: SceneResourceIndex.Resource?
        let isLiteralEntry: Bool
        /// Lookup observation only. Source resolution and reads belong to Root.
        let wasSelectedEntry: Bool
        let relativePath: String

        init(owner: Root, indexedResource: SceneResourceIndex.Resource?, isLiteralEntry: Bool,
             relativePath: String, wasSelectedEntry: Bool = false) {
            self.owner = owner; self.indexedResource = indexedResource; self.isLiteralEntry = isLiteralEntry
            self.relativePath = relativePath; self.wasSelectedEntry = wasSelectedEntry
        }

        var source: Source { owner.source }
        var kind: SceneResourceIndex.ResourceKind? { indexedResource?.kind }
        /// Diagnostic location for the current directory backing, never a URL
        /// that a consumer may reopen instead of reading through this handle.
        var diagnosticPath: String { owner.diagnosticPath(relativePath) }
        var displayPath: String { source == .package ? relativePath : "\(source.rawValue):\(relativePath)" }

        nonisolated func currentIdentity(checkCancellation: (() throws -> Void)? = nil) throws -> ContentIdentity {
            try owner.currentIdentity(self, checkCancellation: checkCancellation)
        }

        nonisolated func sibling(appendingSuffix suffix: String) throws -> Handle {
            try owner.sibling(of: self, appendingSuffix: suffix)
        }

        nonisolated func readSnapshot(
            expectedIdentity: ContentIdentity? = nil,
            maximumBytes: Int? = nil,
            within directory: String? = nil,
            checkCancellation: (() throws -> Void)? = nil
        ) throws -> ReadSnapshot {
            try owner.readSnapshot(self, expectedIdentity: expectedIdentity,
                maximumBytes: maximumBytes, within: directory, checkCancellation: checkCancellation)
        }

        nonisolated func readBytes(
            maximumBytes: Int? = nil,
            within directory: String? = nil,
            checkCancellation: (() throws -> Void)? = nil
        ) throws -> Data {
            try owner.readBytes(self, maximumBytes: maximumBytes, within: directory,
                                checkCancellation: checkCancellation)
        }

        /// Streams the selected file through the same opened-source checks as
        /// snapshots. A sink must not publish partial bytes before this returns.
        @discardableResult
        nonisolated func readChunks(
            maximumBytes: Int? = nil,
            within directory: String? = nil,
            checkCancellation: (() throws -> Void)? = nil,
            prepare: (ContentIdentity) throws -> Void = { _ in },
            consume: (Data) throws -> Void
        ) throws -> ContentIdentity {
            try owner.readFile(self, maximumBytes: maximumBytes, within: directory,
                checkCancellation: checkCancellation, prepare: prepare, consume: consume)
        }
    }

    nonisolated final class Root: Sendable {
        let source: Source
        let directoryURL: URL?
        let index: SceneResourceIndex
        let canonicalRootURL: URL?
        let packageBacking: PackageBacking?
        private let resourcesByIdentity: [String: SceneResourceIndex.Resource]
        private let resourcesByInvariantIdentity: [String: SceneResourceIndex.Resource]
        private let packageDirectoriesByIdentity: [String: String]
        private let literalPackagePathsByIdentity: [String: String]

        nonisolated convenience init(source: Source, url: URL, index: SceneResourceIndex? = nil,
                                     canonicalRootURL: URL? = nil) {
            let canonical = canonicalRootURL ?? (index?.directoryURL ?? url)
                .resolvingSymlinksInPath().standardizedFileURL
            self.init(source: source, directoryURL: url, index: index ?? SceneResourceIndexBuilder().build(rootURL: url),
                canonicalRootURL: canonical, packageBacking: nil)
        }

        nonisolated init(source: Source, directoryURL: URL?, index: SceneResourceIndex,
                         canonicalRootURL: URL?, packageBacking: PackageBacking?) {
            self.source = source; self.directoryURL = directoryURL; self.index = index
            self.canonicalRootURL = canonicalRootURL; self.packageBacking = packageBacking
            var resourcesByIdentity: [String: SceneResourceIndex.Resource] = [:]
            var resourcesByInvariantIdentity: [String: SceneResourceIndex.Resource] = [:]
            var packageDirectoriesByIdentity: [String: String] = [:]
            var literalPackagePathsByIdentity: [String: String] = [:]
            for resource in index.resources {
                let identity = SceneResourceView.identity(resource.relativePath)
                if resourcesByIdentity[identity] == nil { resourcesByIdentity[identity] = resource }
                let invariantIdentity = Self.invariantPathIdentity(resource.relativePath)
                if resourcesByInvariantIdentity[invariantIdentity] == nil {
                    resourcesByInvariantIdentity[invariantIdentity] = resource
                }
            }
            if let packageBacking {
                for path in packageBacking.orderedPaths {
                    let key = SceneResourceView.identity(path)
                    if literalPackagePathsByIdentity[key] == nil { literalPackagePathsByIdentity[key] = path }
                    var components = path.split(separator: "/").map(String.init)
                    components.removeLast()
                    while !components.isEmpty {
                        let path = components.joined(separator: "/")
                        let key = SceneResourceView.identity(path)
                        if packageDirectoriesByIdentity[key] == nil { packageDirectoriesByIdentity[key] = path }
                        components.removeLast()
                    }
                }
            }
            self.resourcesByIdentity = resourcesByIdentity
            self.resourcesByInvariantIdentity = resourcesByInvariantIdentity
            self.packageDirectoriesByIdentity = packageDirectoriesByIdentity
            self.literalPackagePathsByIdentity = literalPackagePathsByIdentity
        }

        func diagnosticPath(_ relativePath: String) -> String {
            if let directoryURL { return directoryURL.appendingPathComponent(relativePath).path }
            return "package[\(packageBacking?.opened.packagePath ?? "unbound")]:\(relativePath)"
        }

        nonisolated func resource(relativePath: String) -> SceneResourceIndex.Resource? {
            resourcesByIdentity[SceneResourceView.identity(relativePath)]
        }

        /// Particle definitions and primary texture candidates historically
        /// used locale-independent keys. Keep that projection in the same Root,
        /// preserving the first indexed resource without another enumeration.
        nonisolated func invariantResource(relativePath: String) -> SceneResourceIndex.Resource? {
            resourcesByInvariantIdentity[Self.invariantPathIdentity(relativePath)]
        }

        /// Read the exact indexed leaf selected by the invariant projection.
        /// Its POSIX filename may itself contain a backslash; the normal path
        /// adapter must not reinterpret that selected name as a separator.
        nonisolated func invariantHandle(relativePath: String) -> Handle? {
            guard let resource = invariantResource(relativePath: relativePath) else { return nil }
            return Handle(owner: self, indexedResource: resource, isLiteralEntry: true,
                relativePath: resource.relativePath, wasSelectedEntry: true)
        }

        /// Preserve the complete legacy particle key normalization, including
        /// authored separator variants and outer whitespace in indexed names.
        nonisolated static func invariantPathIdentity(_ rawPath: String) -> String {
            var value = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
            while value.hasPrefix("./") { value.removeFirst(2) }
            return value.lowercased()
        }

        /// Exact probes preserve shader graph access to paths omitted by the
        /// best-effort directory index, including hidden authored directories.
        nonisolated func handle(relativePath: String, exact: Bool = false) -> Handle? {
            guard let path = SceneResourceView.normalizedRelativePath(relativePath) else { return nil }
            if exact, let packageBacking {
                guard case let .success(selected) = selectedPackagePath(path) else { return nil }
                return Handle(owner: self, indexedResource: packageResource(selected), isLiteralEntry: true,
                    relativePath: selected, wasSelectedEntry: packageBacking.entries[selected] != nil
                        || packageBacking.directories.contains(selected))
            }
            let indexed = resource(relativePath: path)
            return Handle(owner: self, indexedResource: indexed, isLiteralEntry: !exact && indexed != nil,
                relativePath: exact ? path : indexed?.relativePath ?? path,
                wasSelectedEntry: indexed != nil && (!exact || indexed?.relativePath == path))
        }

        /// Literal entry selection preserves hidden files and in-root dot
        /// components accepted by the filesystem entry loader. It does not use
        /// the index's case folding or guess alternate names/extensions.
        nonisolated func existingLiteralHandle(relativePath rawPath: String) throws -> Handle? {
            if let packageBacking {
                do { try packageBacking.opened.validateCurrentSource() }
                catch { throw ReadError.sourceChanged }
                let path: String
                do { path = try selectedPackagePath(rawPath).get() }
                catch ReadError.missing { return nil }
                let directoryPath = path.hasSuffix("/") ? String(path.dropLast()) : path
                guard packageBacking.entries[path] != nil || packageBacking.directories.contains(directoryPath) else { return nil }
                return Handle(owner: self, indexedResource: packageResource(path), isLiteralEntry: true,
                    relativePath: path, wasSelectedEntry: true)
            }
            guard let url = directoryURL else { throw ReadError.invalidHandle }
            try validatePath(rawPath, literal: true)
            let candidate = url.appendingPathComponent(rawPath)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                return nil
            }
            return Handle(owner: self, indexedResource: nil, isLiteralEntry: true,
                relativePath: rawPath, wasSelectedEntry: true)
        }

        nonisolated func owns(_ handle: Handle) -> Bool { handle.owner === self }

        nonisolated func sibling(of handle: Handle, appendingSuffix suffix: String) throws -> Handle {
            guard handle.owner === self else { throw ReadError.invalidHandle }
            guard SceneResourceView.normalizedRelativePath("sibling" + suffix) != nil else {
                throw ReadError.invalidPath
            }
            if packageBacking != nil {
                let path = try selectedPackagePath(handle.relativePath + suffix).get()
                return Handle(owner: self, indexedResource: packageResource(path), isLiteralEntry: true, relativePath: path)
            }
            return Handle(owner: self, indexedResource: nil, isLiteralEntry: true,
                relativePath: handle.relativePath + suffix)
        }

        private func packageResource(_ path: String) -> SceneResourceIndex.Resource? {
            guard let entry = packageBacking?.entries[path] else { return nil }
            return .init(relativePath: path, directoryURL: nil,
                kind: SceneResourceIndexBuilder.kind(for: path), fileSize: Int64(entry.size))
        }

        /// Package literal names have no filesystem to answer case-insensitive
        /// probes. Exact leaves/directories win; a miss uses this Root's sorted
        /// first-wins projection. Check each directory before consuming `..`.
        private func selectedPackagePath(_ rawPath: String) -> Result<String, ReadError> {
            guard let packageBacking, !rawPath.isEmpty, !rawPath.hasPrefix("/"), !rawPath.utf8.contains(0) else {
                return .failure(.invalidPath)
            }
            let components = rawPath.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: false)
            var current: [String] = []
            for (i, component) in components.enumerated() {
                if component.isEmpty || component == "." { continue }
                if component == ".." {
                    guard !current.isEmpty else { return .failure(.symlinkEscape) }
                    current.removeLast()
                    continue
                }
                let candidate = (current + [String(component)]).joined(separator: "/")
                if i == components.count - 1 {
                    if packageBacking.entries[candidate] != nil || packageBacking.directories.contains(candidate) { return .success(candidate) }
                    return .success(literalPackagePathsByIdentity[SceneResourceView.identity(candidate)]
                        ?? packageDirectoriesByIdentity[SceneResourceView.identity(candidate)] ?? candidate)
                }
                if packageBacking.directories.contains(candidate) { current.append(String(component)) }
                else if let path = packageDirectoriesByIdentity[SceneResourceView.identity(candidate)] {
                    current = path.split(separator: "/").map(String.init)
                } else { return .failure(.missing) }
            }
            guard !current.isEmpty else { return .failure(.invalidPath) }
            // Reaching the loop's end means the spelling ended in a separator
            // or dot component. Keep its directory intent even beside a file.
            return .success(current.joined(separator: "/") + "/")
        }

        /// Path-only validation is also used by the loss-preserving raw shader
        /// include projection, which intentionally does not load included files.
        nonisolated func validatePath(_ relativePath: String, within directory: String? = nil) throws {
            if let packageBacking {
                try packageBacking.validatePath(relativePath, within: directory)
            } else { try validatePath(relativePath, within: directory, literal: false) }
        }

        @discardableResult
        nonisolated func validatePath(
            _ relativePath: String, within directory: String? = nil, literal: Bool
        ) throws -> URL {
            guard let url = directoryURL, let canonicalRootURL else { throw ReadError.invalidHandle }
            let resolvedRoot = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedRoot == canonicalRootURL else {
                throw ReadError.sourceChanged
            }
            let path: String
            if literal {
                guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.utf8.contains(0) else {
                    throw ReadError.invalidPath
                }
                path = relativePath
            } else {
                guard let normalized = SceneResourceView.normalizedRelativePath(relativePath) else {
                    throw ReadError.invalidPath
                }
                path = normalized
            }
            let root = url.standardizedFileURL
            let boundary: URL
            if let directory {
                guard let normalized = SceneResourceView.normalizedRelativePath(directory) else {
                    throw ReadError.invalidPath
                }
                boundary = root.appendingPathComponent(normalized).standardizedFileURL
            } else { boundary = root }
            let candidate = literal ? url.appendingPathComponent(path) : root.appendingPathComponent(path).standardizedFileURL
            let resolvedBoundary = directory == nil
                ? resolvedRoot : boundary.resolvingSymlinksInPath().standardizedFileURL
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard Self.contains(candidate.standardizedFileURL, in: boundary),
                  Self.contains(resolvedBoundary, in: resolvedRoot),
                  Self.contains(resolvedCandidate, in: resolvedBoundary) else {
                throw ReadError.symlinkEscape
            }
            return resolvedCandidate
        }

        /// Literal `symlink/../entry` follows filesystem resolution. Validate
        /// the opened vnode before payload reads, beside the path/race checks.
        nonisolated func validateOpenedLiteralFile(_ descriptor: Int32, within directory: String?) throws {
            guard let url = directoryURL, let canonicalRootURL else { throw ReadError.invalidHandle }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &path) == 0 else { throw ReadError.unreadable }
            let openedURL = URL(fileURLWithPath: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
                .resolvingSymlinksInPath().standardizedFileURL
            let boundary = directory.map { url.appendingPathComponent($0) } ?? canonicalRootURL
            guard Self.contains(openedURL, in: boundary.resolvingSymlinksInPath().standardizedFileURL) else {
                throw ReadError.symlinkEscape
            }
        }

        nonisolated func currentIdentity(_ handle: Handle,
                                        checkCancellation: (() throws -> Void)? = nil) throws -> ContentIdentity {
            try checkCancellation?()
            guard handle.owner === self else { throw ReadError.invalidHandle }
            if let packageBacking { return .package(try packageBacking.identity(handle.relativePath)) }
            let candidate = try validatePath(handle.relativePath, literal: handle.isLiteralEntry)
            var value = stat()
            guard lstat(candidate.path, &value) == 0 else {
                throw ReadError.unreadable
            }
            let identity = try FileIdentity(path: candidate.path, value: value)
            guard try validatePath(handle.relativePath, literal: handle.isLiteralEntry) == candidate else {
                throw ReadError.sourceChanged
            }
            return .file(identity)
        }

        /// Reads the current selected source and checks its opened-file revision.
        nonisolated func readBytes(
            _ handle: Handle,
            maximumBytes: Int? = nil,
            within directory: String? = nil,
            checkCancellation: (() throws -> Void)? = nil
        ) throws -> Data {
            try readSnapshot(handle, maximumBytes: maximumBytes, within: directory,
                checkCancellation: checkCancellation).data
        }

        /// The identity and bytes describe the same opened file. Callers may
        /// compare it to a cache key without reopening payloads on a cache hit.
        nonisolated func readSnapshot(
            _ handle: Handle,
            expectedIdentity: ContentIdentity? = nil,
            maximumBytes: Int? = nil,
            within directory: String? = nil,
            checkCancellation: (() throws -> Void)? = nil
        ) throws -> ReadSnapshot {
            var data = Data()
            let identity = try readFile(handle, expectedIdentity: expectedIdentity,
                maximumBytes: maximumBytes, within: directory,
                checkCancellation: checkCancellation,
                prepare: { data.reserveCapacity(Int($0.size)) },
                consume: { data.append($0) })
            return ReadSnapshot(data: data, identity: identity)
        }

        /// The only directory payload read loop. Whole-data and streaming
        /// consumers share path, descriptor, revision and cancellation rules.
        fileprivate nonisolated func readFile(
            _ handle: Handle,
            expectedIdentity: ContentIdentity? = nil,
            maximumBytes: Int? = nil,
            within directory: String? = nil,
            checkCancellation: (() throws -> Void)? = nil,
            prepare: (ContentIdentity) throws -> Void,
            consume: (Data) throws -> Void
        ) throws -> ContentIdentity {
            try checkCancellation?()
            guard handle.owner === self else { throw ReadError.invalidHandle }
            if let packageBacking {
                return try packageBacking.readFile(handle.relativePath, expectedIdentity: expectedIdentity,
                    maximumBytes: maximumBytes, within: directory, checkCancellation: checkCancellation,
                    prepare: prepare, consume: consume)
            }
            guard let url = directoryURL else { throw ReadError.invalidHandle }
            try validatePath(handle.relativePath, within: directory, literal: handle.isLiteralEntry)
            let rawCandidate = url.appendingPathComponent(handle.relativePath)
            let candidate = handle.isLiteralEntry ? rawCandidate : rawCandidate.standardizedFileURL
            let descriptor = Darwin.open(candidate.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else {
                if errno == ENOENT || errno == ENOTDIR {
                    throw ReadError.missing
                }
                throw ReadError.unreadable
            }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? file.close() }
            if handle.isLiteralEntry { try validateOpenedLiteralFile(file.fileDescriptor, within: directory) }
            let before = try FileStamp(descriptor: file.fileDescriptor)
            let identity = before.identity(path: candidate.resolvingSymlinksInPath().standardizedFileURL.path)
            guard expectedIdentity.map({ $0 == .file(identity) }) ?? true else { throw ReadError.sourceChanged }
            guard maximumBytes.map({ $0 >= 0 && before.size <= $0 }) ?? true else {
                throw ReadError.fileTooLarge
            }
            try prepare(.file(identity))
            var consumed = 0
            while consumed < before.size {
                try checkCancellation?()
                let chunk: Data
                do { chunk = try file.read(upToCount: min(64 * 1_024, before.size - consumed)) ?? Data() }
                catch { throw ReadError.unreadable }
                guard !chunk.isEmpty else { throw ReadError.sourceChanged }
                try consume(chunk)
                consumed += chunk.count
            }
            try checkCancellation?()
            guard try FileStamp(descriptor: file.fileDescriptor) == before else {
                throw ReadError.sourceChanged
            }
            // A URL alias may move while the FD remains readable. Recheck the
            // selected directory path against the opened file, without reopening.
            do {
                try validatePath(handle.relativePath, within: directory, literal: handle.isLiteralEntry)
                guard try FileStamp(path: candidate.path) == before else { throw ReadError.sourceChanged }
            } catch { throw ReadError.sourceChanged }
            return .file(identity)
        }

        struct FileStamp: Equatable {
            let device: dev_t
            let inode: ino_t
            let size: Int
            let modifiedSeconds: Int
            let modifiedNanoseconds: Int
            let changedSeconds: Int
            let changedNanoseconds: Int

            init(descriptor: Int32) throws {
                var value = stat()
                guard fstat(descriptor, &value) == 0 else { throw ReadError.unreadable }
                try self.init(value)
            }

            init(path: String) throws {
                var value = stat()
                guard fstatat(AT_FDCWD, path, &value, 0) == 0 else { throw ReadError.sourceChanged }
                try self.init(value)
            }

            func identity(path: String) -> FileIdentity {
                let modified = Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000
                return FileIdentity(path: path, size: UInt64(size), modifiedAtBits: modified.bitPattern,
                    fileSystemID: UInt64(bitPattern: Int64(device)), fileID: UInt64(inode),
                    statusChangedAtSeconds: Int64(changedSeconds),
                    statusChangedAtNanoseconds: Int64(changedNanoseconds))
            }

            private init(_ value: stat) throws {
                guard value.st_mode & S_IFMT == S_IFREG, value.st_size >= 0,
                      UInt64(value.st_size) <= UInt64(Int.max) else { throw ReadError.unreadable }
                device = value.st_dev; inode = value.st_ino; size = Int(value.st_size)
                modifiedSeconds = value.st_mtimespec.tv_sec
                modifiedNanoseconds = value.st_mtimespec.tv_nsec
                changedSeconds = value.st_ctimespec.tv_sec
                changedNanoseconds = value.st_ctimespec.tv_nsec
            }
        }

        static func contains(_ candidate: URL, in root: URL) -> Bool {
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            return candidate.path == root.path || candidate.path.hasPrefix(prefix)
        }
    }

    let roots: [Root]

    // The running App's bundled namespace is immutable. Keep only its last
    // successful complete Root, including the locale-dependent lookup table.
    private nonisolated final class BundledStockRoot: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: (locale: Locale, root: Root)?

        func value() -> Root? {
            lock.lock()
            defer { lock.unlock() }
            let locale = Locale.current
            if let cached, cached.locale == locale { return cached.root }
            guard let url = SceneResourceView.defaultStockAssetsRootURL() else { return nil }
            let canonicalRoot = url.resolvingSymlinksInPath().standardizedFileURL
            let bundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
            let stockBundle = url.deletingLastPathComponent().standardizedFileURL
            let canonicalStockBundle = stockBundle.resolvingSymlinksInPath().standardizedFileURL
            let manifestURL = stockBundle.appendingPathComponent(SceneResourceIndexBuilder.bundledManifestFilename)
            let builder = SceneResourceIndexBuilder()
            // Only our immutable in-App stock can consume packaged metadata.
            // A redirected assets root or sidecar retains the old fresh index.
            let manifestIndex = canonicalRoot.path.hasPrefix(bundlePath + "/")
                && canonicalRoot == canonicalStockBundle.appendingPathComponent("assets", isDirectory: true)
                && manifestURL.resolvingSymlinksInPath().standardizedFileURL
                    == canonicalStockBundle.appendingPathComponent(SceneResourceIndexBuilder.bundledManifestFilename)
                ? builder.loadBundledManifest(rootURL: url, manifestURL: manifestURL) : nil
            let built = manifestIndex.map {
                SceneResourceIndexBuilder.BuildResult(index: $0, isComplete: true)
            } ?? builder.buildWithCompleteness(rootURL: url)
            let root = Root(source: .stock, url: url.standardizedFileURL, index: built.index,
                            canonicalRootURL: canonicalRoot)
            let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            // A default bundle resource redirected outside the App remains a
            // fresh best-effort root; it cannot establish an immutable snapshot.
            if built.isComplete, resolvedPath.hasPrefix(bundlePath + "/"),
               locale == Locale.current, url.resolvingSymlinksInPath().standardizedFileURL == canonicalRoot {
                cached = (locale, root)
            }
            return root
        }
    }

    private nonisolated static let bundledStockRoot = BundledStockRoot()

    nonisolated init(projectRootURL: URL, packageRootURL: URL?) {
        self.init(projectRoot: Root(source: .loose, url: projectRootURL.standardizedFileURL),
                  packageRootURL: packageRootURL,
                  stockRoot: Self.bundledStockRoot.value())
    }

    /// Playback reuses the loose namespace captured before project parsing.
    nonisolated init(projectRoot: Root, packageRootURL: URL?) {
        self.init(projectRoot: projectRoot, packageRootURL: packageRootURL,
                  stockRoot: Self.bundledStockRoot.value())
    }

    /// Explicit roots may be mutable, even when their path matches the bundle.
    nonisolated init(
        projectRootURL: URL,
        packageRootURL: URL?,
        stockAssetsRootURL: URL?
    ) {
        let stockRoot = stockAssetsRootURL.map { url in
            Root(source: .stock, url: url.standardizedFileURL)
        }
        self.init(projectRoot: Root(source: .loose, url: projectRootURL.standardizedFileURL),
                  packageRootURL: packageRootURL,
                  stockRoot: stockRoot)
    }

    nonisolated init(projectRoot: Root, packageRoot: Root?) {
        self.init(projectRoot: projectRoot, packageRoot: packageRoot, stockRoot: Self.bundledStockRoot.value())
    }

    nonisolated init(projectRoot: Root, packageRoot: Root?, stockRoot: Root?) {
        var seenDirectories: Set<String> = []
        roots = ([packageRoot, projectRoot, stockRoot].compactMap { $0 }).filter { root in
            guard let url = root.directoryURL else { return true }
            return seenDirectories.insert(url.standardizedFileURL.path).inserted
                && FileManager.default.fileExists(atPath: url.path)
        }
    }

    nonisolated private init(projectRoot: Root, packageRootURL: URL?, stockRoot: Root?) {
        self.init(projectRoot: projectRoot,
            packageRoot: packageRootURL.map { Root(source: .package, url: $0.standardizedFileURL) }, stockRoot: stockRoot)
    }

    /// Authored files have literal package -> loose precedence, with no stock
    /// fallback. Bare package directories are not file candidates; explicit
    /// directory spellings stay selected. Selected file failures never retry.
    nonisolated func literalEntry(relativePath: String) throws -> Handle? {
        for root in roots where root.source != .stock {
            guard let handle = try root.existingLiteralHandle(relativePath: relativePath) else { continue }
            if root.packageBacking != nil, handle.indexedResource == nil,
               !handle.relativePath.hasSuffix("/") { continue }
            return handle
        }
        return nil
    }

    nonisolated var authorResources: [SceneResourceIndex.Resource] {
        authorHandles.compactMap(\.indexedResource)
    }

    nonisolated var authorHandles: [Handle] {
        mergedHandles(from: roots.filter { $0.source != .stock })
    }

    nonisolated var availableRelativePaths: [String] {
        let virtualPaths = mergedHandles(from: roots).map(\.relativePath)
        let explicitStockPaths = roots
            .filter { $0.source == .stock }
            .flatMap(\.index.resources)
            .map { "assets/" + $0.relativePath }
        return virtualPaths + explicitStockPaths
    }

    nonisolated func resource(relativePath rawPath: String) -> SceneResourceIndex.Resource? {
        resolvedResource(relativePath: rawPath)?.indexedResource
    }

    nonisolated func resolvedResource(relativePath rawPath: String) -> Handle? {
        guard let normalized = Self.normalizedRelativePath(rawPath) else { return nil }
        for root in roots {
            if let resource = root.resource(relativePath: normalized) {
                return Handle(owner: root, indexedResource: resource, isLiteralEntry: true,
                    relativePath: resource.relativePath, wasSelectedEntry: true)
            }
            if root.source == .stock,
               normalized.localizedLowercase.hasPrefix("assets/"),
               let resource = root.resource(
                   relativePath: String(normalized.dropFirst("assets/".count))
               ) {
                return Handle(owner: root, indexedResource: resource, isLiteralEntry: true,
                    relativePath: resource.relativePath, wasSelectedEntry: true)
            }
        }
        return nil
    }

    nonisolated func resource(forReference rawReference: String) -> SceneResourceIndex.Resource? {
        resolvedResource(forReference: rawReference)?.indexedResource
    }

    nonisolated func resolvedResource(forReference rawReference: String) -> Handle? {
        guard let reference = Self.normalizedRelativePath(rawReference) else { return nil }
        for candidate in Self.referenceCandidates(reference) {
            if let resource = resolvedResource(relativePath: candidate) {
                return resource
            }
        }
        return nil
    }

    nonisolated static func defaultStockAssetsRootURL(in bundle: Bundle = .main) -> URL? {
        let bundleRoot: URL?
        if let bundled = bundle.url(forResource: "SceneStockAssets", withExtension: "bundle") {
            bundleRoot = bundled
        } else if let resourceURL = bundle.resourceURL {
            let candidate = resourceURL.appendingPathComponent(
                "SceneStockAssets.bundle",
                isDirectory: true
            )
            bundleRoot = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        } else {
            bundleRoot = nil
        }
        guard let bundleRoot else { return nil }
        let assets = bundleRoot.appendingPathComponent("assets", isDirectory: true)
        return FileManager.default.fileExists(atPath: assets.path) ? assets : nil
    }

    nonisolated private func mergedHandles(
        from selectedRoots: [Root]
    ) -> [Handle] {
        var identities: Set<String> = []
        return selectedRoots.flatMap { root in
            root.index.resources.compactMap { resource in
                guard identities.insert(Self.identity(resource.relativePath)).inserted else { return nil }
                return Handle(owner: root, indexedResource: resource, isLiteralEntry: true,
                    relativePath: resource.relativePath, wasSelectedEntry: true)
            }
        }
    }

    nonisolated private static func referenceCandidates(_ reference: String) -> [String] {
        var candidates = [reference]
        if URL(fileURLWithPath: reference).pathExtension.isEmpty {
            candidates += [
                reference + ".json",
                "materials/" + reference + ".json",
                "materials/" + reference + ".tex",
                reference + ".tex",
            ]
        }
        return candidates
    }

    nonisolated private static func normalizedRelativePath(_ rawPath: String) -> String? {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.utf8.contains(0) else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return path
    }

    nonisolated static func identity(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }
}
