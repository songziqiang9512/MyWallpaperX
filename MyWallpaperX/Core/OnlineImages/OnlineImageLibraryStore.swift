import Foundation

/// The online-image publisher's disk boundary. Only this manifest declares
/// local assets; directory contents never manufacture a publication.
actor OnlineImageLibraryStore {
    nonisolated enum StoreError: Error, LocalizedError {
        case unsupportedSchema(Int)
        case invalidManifest
        case invalidPath
        case changedRecord

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version): return "在线图片记录版本 \(version) 暂不支持，原文件已保留。"
            case .invalidManifest: return "在线图片记录无法读取，原文件已保留。"
            case .invalidPath: return "在线图片记录包含无效文件位置。"
            case .changedRecord: return "在线图片记录已变化，请刷新后重试。"
            }
        }
    }

    nonisolated private struct Manifest: Codable {
        var schemaVersion = 1
        var records: [OnlineImageLocalRecord] = []
        var retiredPaths: [String] = []

        private enum CodingKeys: String, CodingKey { case schemaVersion, records, retiredPaths }

        init() {}

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == 1 else { throw StoreError.unsupportedSchema(schemaVersion) }
            records = try values.decode([OnlineImageLocalRecord].self, forKey: .records)
            retiredPaths = try values.decode([String].self, forKey: .retiredPaths)
        }
    }

    nonisolated private let root: URL
    private var manifest: Manifest?
    private var unavailable = Set<OnlineImageAssetID>()
    private var snapshotRevision: UInt64 = 0

    init(root: URL) {
        self.root = Self.resolvingExistingAncestor(of: root).url
    }

    /// A missing manifest is a successful empty library. Invalid input never
    /// becomes an empty success or grants permission to replace that input.
    func load() throws -> OnlineImageLocalSnapshot {
        manifest = nil
        let manifestURL = try containedURL(relativePath: "manifest.json").url
        let decoded: Manifest
        do {
            let bytes = try Data(contentsOf: manifestURL)
            do { decoded = try JSONDecoder().decode(Manifest.self, from: bytes) }
            catch let error as StoreError { throw error }
            catch { throw StoreError.invalidManifest }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            decoded = Manifest()
        }
        try validate(decoded)
        let nextRevision = snapshotRevision &+ 1
        let snapshot = try scan(decoded, revision: nextRevision)
        manifest = decoded
        unavailable = snapshot.unavailable
        snapshotRevision = nextRevision
        return snapshot
    }

    /// Image decoding and format admission finish before this method. A new
    /// revision never overwrites the bytes referenced by a current desktop.
    func publish(stagingURL: URL, asset: OnlineImageAsset, width: Int, height: Int,
                 fileSizeBytes: Int64, fileExtension: String) throws -> OnlineImageLocalSnapshot {
        try ensureLoaded()
        try Task.checkCancellation()
        guard !asset.id.artworkID.isEmpty, asset.id.pageIndex >= 0,
              asset.id.source != .wallhaven || asset.id.pageIndex == 0,
              width > 0, height > 0, fileSizeBytes > 0,
              !fileExtension.isEmpty,
              fileExtension.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw StoreError.invalidManifest
        }
        var next = manifest!
        let oldIndex = next.records.firstIndex { $0.assetID == asset.id }
        let old = oldIndex.map { next.records[$0] }
        let revision = UUID()
        let relativePath = asset.id.source.rawValue + "/" + revision.uuidString + "." + fileExtension.lowercased()
        let record = OnlineImageLocalRecord(assetID: asset.id, title: asset.title, sourceURL: asset.sourceURL,
            author: asset.author, authorID: asset.authorID, tags: asset.tags, relativePath: relativePath,
            pixelWidth: width, pixelHeight: height, fileSizeBytes: fileSizeBytes,
            firstDownloadedAt: old?.firstDownloadedAt ?? Date(), revision: revision)
        let destination = try containedURL(relativePath: record.relativePath).url
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(at: stagingURL, to: destination)
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StoreError.invalidManifest }
            if let oldIndex {
                next.records[oldIndex] = record
                if let old { next.retiredPaths.append(old.relativePath) }
            } else { next.records.append(record) }
            return try commit(next, unavailable: unavailable.subtracting([asset.id]))
        } catch {
            // This UUID belongs only to this uncommitted attempt. Old records,
            // old revisions and service-owned staging are never cleaned here.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// The service has already confirmed source unlink. This operation only
    /// removes its exact captured record, never a newer replacement or a file.
    func removeRecord(id: OnlineImageAssetID, expectedRevision: UUID) throws -> OnlineImageLocalSnapshot {
        try ensureLoaded()
        var next = manifest!
        guard let index = next.records.firstIndex(where: { $0.assetID == id }),
              next.records[index].revision == expectedRevision else { throw StoreError.changedRecord }
        next.records.remove(at: index)
        return try commit(next, unavailable: unavailable.subtracting([id]))
    }

    /// Locator projection does no filesystem work. Disk consumption performs
    /// the symbolic-link and ordinary-file checks in load/publish instead.
    nonisolated func fileURL(for record: OnlineImageLocalRecord) throws -> URL {
        try relativeURL(relativePath: record.relativePath)
    }

    private func ensureLoaded() throws {
        if manifest == nil { _ = try load() }
    }

    private func commit(_ next: Manifest, unavailable nextUnavailable: Set<OnlineImageAssetID>) throws -> OnlineImageLocalSnapshot {
        let manifestURL = try containedURL(relativePath: "manifest.json").url
        let nextRevision = snapshotRevision &+ 1
        let snapshot = OnlineImageLocalSnapshot(records: next.records, unavailable: nextUnavailable,
            status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true), revision: nextRevision)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        // This is the final cancellation boundary. After atomic publication,
        // cancellation cannot turn a committed asset into failure or unlink it.
        try Task.checkCancellation()
        try data.write(to: manifestURL, options: .atomic)
        manifest = next
        unavailable = nextUnavailable
        snapshotRevision = nextRevision
        return snapshot
    }

    private func validate(_ value: Manifest) throws {
        var assets = Set<OnlineImageAssetID>(), paths = Set<String>()
        for record in value.records {
            guard !record.assetID.artworkID.isEmpty, record.assetID.pageIndex >= 0,
                  record.assetID.source != .wallhaven || record.assetID.pageIndex == 0,
                  record.pixelWidth > 0, record.pixelHeight > 0, record.fileSizeBytes > 0,
                  assets.insert(record.assetID).inserted, paths.insert(record.relativePath).inserted else {
                throw StoreError.invalidManifest
            }
        }
        for path in value.retiredPaths {
            guard paths.insert(path).inserted else { throw StoreError.invalidManifest }
            _ = try relativeURL(relativePath: path)
        }
    }

    private func scan(_ value: Manifest, revision: UInt64) throws -> OnlineImageLocalSnapshot {
        var unavailable = Set<OnlineImageAssetID>()
        for record in value.records {
            let resolved = try containedURL(relativePath: record.relativePath)
            if resolved.leafAttributes?[.type] as? FileAttributeType != .typeRegular { unavailable.insert(record.assetID) }
        }
        return OnlineImageLocalSnapshot(records: value.records, unavailable: unavailable,
            status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true), revision: revision)
    }

    nonisolated private func relativeURL(relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard root.isFileURL, !components.isEmpty, !relativePath.utf8.contains(0),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw StoreError.invalidPath }
        return root.appendingPathComponent(relativePath).standardizedFileURL
    }

    nonisolated private func containedURL(relativePath: String) throws -> (url: URL, leafAttributes: [FileAttributeKey: Any]?) {
        let url = try relativeURL(relativePath: relativePath)
        let resolved = Self.resolvingExistingAncestor(of: url)
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard !resolved.unresolvedSymbolicLink, resolved.url.path.hasPrefix(prefix), resolved.url.path != root.path else {
            throw StoreError.invalidPath
        }
        return (url, resolved.leafAttributes)
    }

    /// Foundation can spell /private/tmp differently before and after a leaf
    /// exists. Resolve the existing ancestor once, then append absent leaves;
    /// symbolic-link entries count as existing even if their targets vanished.
    nonisolated private static func resolvingExistingAncestor(of input: URL) -> (url: URL, unresolvedSymbolicLink: Bool, leafAttributes: [FileAttributeKey: Any]?) {
        guard input.isFileURL else { return (input, false, nil) }
        var ancestor = input.standardizedFileURL
        var missing: [String] = []
        var attributes = try? FileManager.default.attributesOfItem(atPath: ancestor.path)
        let leafAttributes = attributes
        while attributes == nil {
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { break }
            missing.append(ancestor.lastPathComponent)
            ancestor = parent
            attributes = try? FileManager.default.attributesOfItem(atPath: ancestor.path)
        }
        let resolved = ancestor.resolvingSymlinksInPath()
        let unresolvedSymbolicLink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
            && (try? FileManager.default.attributesOfItem(atPath: resolved.path))?[.type] as? FileAttributeType == .typeSymbolicLink
        return (missing.reversed().reduce(resolved) { $0.appendingPathComponent($1) }, unresolvedSymbolicLink, leafAttributes)
    }
}
