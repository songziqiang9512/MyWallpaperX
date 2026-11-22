import Darwin
import Foundation

/// Stateless file-only operations shared by the local source owners. Managed
/// downloads retain their original transaction/lease deletion implementation.
nonisolated enum WallpaperSourceFileDeletion {
    struct Prepared: Sendable {
        let url: URL
        let device: UInt64
        let inode: UInt64
    }

    struct Outcome: Sendable {
        let sourceFileDeleted: Bool
        let failureMessage: String?
        var succeeded: Bool { sourceFileDeleted && failureMessage == nil }
    }

    static func prepare(_ url: URL) throws -> Prepared {
        guard url.isFileURL else { throw failure(String(localized: "Not a local source file")) }
        let url = url.standardizedFileURL
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let bundle = bundleURL.path
        let path = url.resolvingSymlinksInPath().path
        guard bundleURL.pathExtension != "app" || path != bundle && !path.hasPrefix(bundle + "/") else {
            throw failure(String(localized: "Can’t delete built-in app resources"))
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw posixFailure() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw failure(String(localized: "Only confirmed regular source files can be deleted; folders and symbolic links can’t")) }
        return Prepared(url: url, device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino))
    }

    static func remove(_ prepared: Prepared) -> Outcome {
        let outcome = unlinkPrepared(prepared)
        return outcome.succeeded ? synchronizeDirectory(after: prepared) : outcome
    }

    /// Source owners call this inside their original MainActor admission turn.
    /// No callback/yield may separate the final busy check from this unlink.
    static func unlinkPrepared(_ prepared: Prepared) -> Outcome {
        do {
            var info = stat()
            guard lstat(prepared.url.path, &info) == 0 else { throw posixFailure() }
            guard info.st_mode & S_IFMT == S_IFREG,
                  UInt64(truncatingIfNeeded: info.st_dev) == prepared.device, UInt64(info.st_ino) == prepared.inode else {
                throw failure(String(localized: "The source file’s identity changed; the replaced file wasn’t deleted"))
            }
            guard Darwin.unlink(prepared.url.path) == 0 else { throw posixFailure() }
            return Outcome(sourceFileDeleted: true, failureMessage: nil)
        } catch {
            return Outcome(sourceFileDeleted: false, failureMessage: String(localized: "Source file not deleted:") + error.localizedDescription)
        }
    }

    /// The potentially slow durability acknowledgement stays on the source's
    /// existing worker. Failure here must retain the already-completed effect.
    static func synchronizeDirectory(after prepared: Prepared) -> Outcome {
        do {
            let directory = open(prepared.url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard directory >= 0 else { throw posixFailure() }
            defer { close(directory) }
            guard fsync(directory) == 0 else { throw posixFailure() }
            return Outcome(sourceFileDeleted: true, failureMessage: nil)
        } catch {
            return Outcome(sourceFileDeleted: true, failureMessage: String(localized: "Source file deleted, but disk sync didn't finish:") + error.localizedDescription)
        }
    }

    private static func failure(_ message: String) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func posixFailure() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
