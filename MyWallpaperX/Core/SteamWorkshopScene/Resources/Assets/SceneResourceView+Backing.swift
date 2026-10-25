import Foundation
import Darwin

nonisolated extension SceneResourceView.Root {
    nonisolated enum NamespaceIdentity: Hashable {
        case directory(path: String)
        case package(path: String, revision: ScenePackageFileRevision)
        case absent

        var sortComponents: [String] {
            switch self {
            case let .directory(path), let .package(path, _): [path]
            case .absent: []
            }
        }
    }

    var namespaceIdentity: NamespaceIdentity {
        if let packageBacking {
            return .package(path: packageBacking.opened.packagePath,
                revision: packageBacking.opened.fileRevision)
        }
        if let directoryURL { return .directory(path: directoryURL.standardizedFileURL.path) }
        return .absent
    }

    var sourceOrder: Int {
        switch source { case .package: 0; case .loose: 1; case .stock: 2 }
    }

    var usesPackageNamespaceOrder: Bool { packageBacking != nil }

    /// The parsed index, FD revision and namespace belong to this Root. A
    /// resource is selected by a projected name and read from its raw range.
    nonisolated final class PackageBacking: Sendable {
        let opened: ScenePkgReader.OpenPackage
        let entries: [String: ScenePkgIndex.Entry]
        let orderedEntries: [(path: String, entry: ScenePkgIndex.Entry)]
        var orderedPaths: [String] { orderedEntries.map(\.path) }
        let directories: Set<String>

        init(opened: ScenePkgReader.OpenPackage, checkCancellation: (() throws -> Void)?) throws {
            var entries: [String: ScenePkgIndex.Entry] = [:]
            var representatives: [(path: String, entry: ScenePkgIndex.Entry)] = []
            var directories: Set<String> = []
            let payloadSize = UInt64(opened.index.fileSize - opened.index.dataStartOffset)
            for entry in opened.index.entries {
                try checkCancellation?()
                let path = entry.path.replacingOccurrences(of: "\\", with: "/")
                let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                guard !path.hasPrefix("/"), !path.utf8.contains(0),
                      parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      UInt64(entry.offset) + UInt64(entry.size) <= payloadSize else { continue }
                // Swift String equality groups canonical Unicode equivalents;
                // case-only neighbors remain separate exact leaves.
                if entries[path] != nil { continue }
                entries[path] = entry
                representatives.append((path, entry))
                var components = parts.map(String.init)
                components.removeLast()
                while !components.isEmpty {
                    directories.insert(components.joined(separator: "/")); components.removeLast()
                }
            }
            self.opened = opened
            self.entries = entries; self.directories = directories
            orderedEntries = try representatives.sorted {
                try checkCancellation?()
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        }

        func literalPath(_ rawPath: String) throws -> String {
            guard !rawPath.isEmpty, !rawPath.hasPrefix("/"), !rawPath.utf8.contains(0) else {
                throw SceneResourceView.ReadError.invalidPath
            }
            let components = rawPath.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: false)
            var result: [String] = []
            for (i, component) in components.enumerated() {
                if component.isEmpty || component == "." { continue }
                if component == ".." {
                    guard !result.isEmpty else { throw SceneResourceView.ReadError.symlinkEscape }
                    result.removeLast()
                } else { result.append(String(component)) }
                if i < components.count - 1, !result.isEmpty,
                   !directories.contains(result.joined(separator: "/")) {
                    throw SceneResourceView.ReadError.missing
                }
            }
            guard !result.isEmpty else { throw SceneResourceView.ReadError.invalidPath }
            if let last = components.last, last.isEmpty || last == "." || last == ".." {
                throw SceneResourceView.ReadError.unreadable
            }
            let selected = result.joined(separator: "/")
            if entries[selected] == nil, directories.contains(selected) {
                throw SceneResourceView.ReadError.unreadable
            }
            return selected
        }

        func validatePath(_ path: String, within directory: String?) throws {
            func normalized(_ raw: String) throws -> String {
                let value = raw.replacingOccurrences(of: "\\", with: "/")
                guard !value.hasPrefix("/"), !value.utf8.contains(0),
                      value.split(separator: "/", omittingEmptySubsequences: false)
                        .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                    throw SceneResourceView.ReadError.invalidPath
                }
                return value
            }
            let selected = try normalized(path)
            if let directory {
                let boundary = try normalized(directory)
                // This is a logical package subtree, using the same folded
                // namespace as its Root. It never selects or reopens an entry.
                guard SceneResourceView.identity(selected).hasPrefix(SceneResourceView.identity(boundary) + "/") else {
                    throw SceneResourceView.ReadError.symlinkEscape
                }
            }
        }

        func identity(_ path: String) throws -> SceneResourceView.PackageIdentity {
            do { try opened.validateCurrentSource() }
            catch { throw SceneResourceView.ReadError.sourceChanged }
            let selected = try literalPath(path)
            guard let entry = entries[selected] else { throw SceneResourceView.ReadError.missing }
            return identity(for: entry)
        }

        private func identity(for entry: ScenePkgIndex.Entry) -> SceneResourceView.PackageIdentity {
            .init(packagePath: opened.packagePath, fileRevision: opened.fileRevision,
                rawEntryPath: entry.path, dataStartOffset: UInt64(opened.index.dataStartOffset),
                offset: entry.offset, byteCount: entry.size)
        }

        func readFile(_ path: String, expectedIdentity: SceneResourceView.ContentIdentity?,
                      maximumBytes: Int?, within directory: String?, checkCancellation: (() throws -> Void)?,
                      prepare: (SceneResourceView.ContentIdentity) throws -> Void,
                      consume: (Data) throws -> Void) throws -> SceneResourceView.ContentIdentity {
            try checkCancellation?()
            let selected = try literalPath(path)
            try validatePath(path, within: directory)
            guard let entry = entries[selected] else { throw SceneResourceView.ReadError.missing }
            let identity = SceneResourceView.ContentIdentity.package(identity(for: entry))
            guard expectedIdentity.map({ $0 == identity }) ?? true else { throw SceneResourceView.ReadError.sourceChanged }
            guard maximumBytes.map({ $0 >= 0 && Int(entry.size) <= $0 }) ?? true else {
                throw SceneResourceView.ReadError.fileTooLarge
            }
            try prepare(identity)
            // Preserve caller failures rather than turning cancellation or a
            // materializer failure into a changed source.
            struct CallbackFailure: Error { let underlying: any Error }
            let cancellation: (() throws -> Void)? = checkCancellation.map { callback in
                { do { try callback() } catch { throw CallbackFailure(underlying: error) } }
            }
            do {
                try opened.readEntryChunks(entry, checkCancellation: cancellation) { chunk in
                        do { try consume(chunk) } catch { throw CallbackFailure(underlying: error) }
                    }
            } catch let error as CallbackFailure {
                throw error.underlying
            } catch {
                throw SceneResourceView.ReadError.sourceChanged
            }
            return identity
        }
    }

    static func package(openedPackage: ScenePkgReader.OpenPackage,
                        checkCancellation: (() throws -> Void)? = nil) throws -> SceneResourceView.Root {
        let backing = try PackageBacking(opened: openedPackage, checkCancellation: checkCancellation)
        let resources = try backing.orderedEntries.filter { SceneResourceIndexBuilder.isOrdinaryPackagePath($0.path) }.map { path, entry in
            try checkCancellation?()
            return SceneResourceIndex.Resource(relativePath: path, directoryURL: nil,
                kind: SceneResourceIndexBuilder.kind(for: path), fileSize: Int64(entry.size))
        }
        let root = SceneResourceView.Root(source: .package, directoryURL: nil, index: .init(resources: resources),
            canonicalRootURL: nil, packageBacking: backing)
        try checkCancellation?()
        return root
    }

    /// Parse the selected directory entry through a duplicate of the same FD.
    func openPackage(_ handle: SceneResourceView.Handle, limits: ScenePkgReader.IndexLimits = .bounded,
                     checkCancellation: (() throws -> Void)? = nil) throws -> ScenePkgReader.OpenPackage {
        try withDirectoryFile(handle, checkCancellation: checkCancellation) { descriptor in
            try ScenePkgReader().openPackage(duplicatingFileDescriptor: descriptor,
                limits: limits, checkCancellation: checkCancellation)
        }
    }

    private func withDirectoryFile<T>(_ handle: SceneResourceView.Handle,
                                      checkCancellation: (() throws -> Void)? = nil,
                                      body: (Int32) throws -> T) throws -> T {
        try checkCancellation?()
        guard owns(handle), let directoryURL else { throw SceneResourceView.ReadError.invalidHandle }
        try validatePath(handle.relativePath, literal: handle.isLiteralEntry)
        let raw = directoryURL.appendingPathComponent(handle.relativePath)
        let candidate = handle.isLiteralEntry ? raw : raw.standardizedFileURL
        let descriptor = Darwin.open(candidate.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ENOTDIR {
                throw SceneResourceView.ReadError.missing
            }
            throw SceneResourceView.ReadError.unreadable
        }
        defer { close(descriptor) }
        try validateOpenedLiteralFile(descriptor, within: nil)
        let before = try FileStamp(descriptor: descriptor)
        let result = try body(descriptor)
        try checkCancellation?()
        try validatePath(handle.relativePath, literal: handle.isLiteralEntry)
        guard try FileStamp(descriptor: descriptor) == before,
              try FileStamp(path: candidate.path) == before else { throw SceneResourceView.ReadError.sourceChanged }
        return result
    }

}
