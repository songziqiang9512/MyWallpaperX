import Foundation
import Darwin

/// A cheap revision of a file actually consumed by author interpretation.
/// These facts invalidate a derived cache; they never grant playback access.
nonisolated struct WebAuthorFileRevision: Codable, Equatable, Sendable {
    struct State: Codable, Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let mode: UInt16
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; mode = value.st_mode
            size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    let url: URL
    let state: State?

    init(_ url: URL) {
        self.url = url.standardizedFileURL
        var value = stat()
        state = lstat(url.path, &value) == 0 ? State(value) : nil
    }

    var isCurrent: Bool { Self(url) == self }
}

/// Preserve the resolver outcome too: a symlink or a previously missing local
/// dependency may change without changing its containing script's bytes.
nonisolated struct WebAuthorDependencyReference: Codable, Equatable, Sendable {
    let path: String
    let sourceURL: URL
    let rootURL: URL
    let resolvedURL: URL?

    var isCurrent: Bool {
        SteamWorkshopService.resolveWebResourceURL(path, relativeTo: sourceURL, rootURL: rootURL) == resolvedURL
    }
}
