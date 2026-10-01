//
//  SteamWorkshopLibraryTransaction+FailedVisibility.swift
//  MyWallpaperX
//
//  库发布元数据的可见性面：索引读取、原子发布、GC 扫描与条目移除。
//  自 SteamWorkshopLibraryTransaction.swift 尾部拆出，逻辑未变。
//

import Foundation
import Darwin

extension SteamWorkshopLibraryTransaction {
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
            // A targeted lookup in a local-only library has no metadata. Whole-index
            // GC still requires an existing, readable index before reclaiming anything.
            if errno == ENOENT && (!requireComplete || matchingItemID != nil || matchingFilename != nil) { return [:] }
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

    /// One index entry exactly as the GC scan read it: bytes under the
    /// pinned-FD discipline plus the birth-qualified identity and mtime of
    /// that exact directory entry. The GC delete phase replays the identity
    /// so a replacement that landed after the scan is refused.
    struct PublishedMetadataEntryScan: Sendable {
        let name: String
        let data: Data
        let identity: SteamWorkshopStagingLeaseIdentity
        let modified: TimeInterval
    }

    /// Enumerates every index entry (item- and video-named alike) with an
    /// identity-carrying read. A per-entry failure skips that entry alone —
    /// an unreadable entry is not evidence of an orphan.
    static func scanPublishedMetadataEntries(libraryRoot: URL) throws -> [PublishedMetadataEntryScan] {
        let library = try absoluteDirectory(libraryRoot)
        let index = try directory(library, metadataName)
        var result: [PublishedMetadataEntryScan] = []
        for name in try childNames(index, limit: 100_000) {
            try Task.checkCancellation()
            guard name.hasSuffix(".json"),
                  let file = try? openFile(index, name),
                  let value = try? info(file, regular: true) else { continue }
            do {
                let data = try readData(file, maximumBytes: 4 * 1024 * 1024)
                result.append(PublishedMetadataEntryScan(
                    name: name,
                    data: data,
                    identity: try validatedFilesystemIdentity(value),
                    modified: TimeInterval(value.st_mtimespec.tv_sec)
                        + TimeInterval(value.st_mtimespec.tv_nsec) / 1_000_000_000
                ))
            } catch { continue }
        }
        return result
    }

    /// Index GC's only removal step: unlink the entry only when the directory
    /// entry still resolves to the exact scanned object (birth-qualified
    /// identity match). Every publish path replaces entries via temporary
    /// file + renameat, which always mints a new inode, so a replacement that
    /// landed after the scan fails the match and the new index survives —
    /// even for a mutation the caller's actor serialization cannot see.
    /// Returns false when the entry is already gone or was replaced; that is
    /// a keep, never an error.
    static func removeMetadataEntryIfUnchanged(
        name: String,
        expected identity: SteamWorkshopStagingLeaseIdentity,
        libraryRoot: URL
    ) throws -> Bool {
        try require(name.utf8.count <= 255 && name.hasSuffix(".json")
            && !name.contains("/") && !name.utf8.contains(0))
        let library = try absoluteDirectory(libraryRoot)
        let index = try directory(library, metadataName)
        var value = stat()
        guard fstatat(index.value, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            try require(errno == ENOENT)
            return false
        }
        guard (value.st_mode & S_IFMT) == S_IFREG,
              let current = try? validatedFilesystemIdentity(value),
              current == identity else { return false }
        try require(unlinkat(index.value, name, 0) == 0, "下载索引清理失败。")
        _ = fsync(index.value)
        return true
    }
}
