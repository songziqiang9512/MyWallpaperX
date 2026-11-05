import Foundation
import Darwin

/// A self-contained published input. The system host never opens the library,
/// credentials or the main App's settings to decide what it should render.
nonisolated struct ScreenSaverConfiguration: Codable, Equatable, Sendable {
    static let changedNotification = Notification.Name("com.songziqiang.MyWallpaperX.ScreenSaver.configurationChanged")
    enum Kind: String, Codable, Sendable { case video }

    struct Content: Codable, Equatable, Sendable {
        let kind: Kind
        let mediaGeneration: String
        let title: String
        /// Opaque App association for options-only edits; never playback authority.
        var sourceIdentity: String? = nil
        /// Only a deployed video can be decoded by this component.
        let entryRelativePath: String
        let posterRelativePath: String
    }

    let schemaVersion: Int
    let publicationID: UUID
    let content: Content?
    let fillMode: String
    let playsOnBattery: Bool

    init(content: Content?, fillMode: String = "aspectFill", playsOnBattery: Bool = false) {
        schemaVersion = 1
        publicationID = UUID()
        self.content = content
        self.fillMode = fillMode
        self.playsOnBattery = playsOnBattery
    }
}

nonisolated enum ScreenSaverPaths {
    static let applicationGroup = "H9QWU9XN8R.MWX"

    static func sharedRoot() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: applicationGroup) else {
            throw CocoaError(.fileReadNoPermission)
        }
        return container.appendingPathComponent("ScreenSaver", isDirectory: true)
    }

    static func mediaRoot(in root: URL, generation: String) throws -> URL {
        guard UUID(uuidString: generation) != nil else { throw CocoaError(.fileReadCorruptFile) }
        return root.appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(generation, isDirectory: true)
    }

    static func resource(_ relative: String, in mediaRoot: URL) throws -> URL {
        let url = mediaRoot.appendingPathComponent(relative).standardizedFileURL
        let canonical = url.resolvingSymlinksInPath()
        let root = mediaRoot.resolvingSymlinksInPath().standardizedFileURL
        guard !relative.isEmpty, !relative.hasPrefix("/"),
              canonical.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileReadNoPermission) }
        return canonical
    }
}

nonisolated final class ScreenSaverMediaLease: Sendable {
    private let descriptor: Int32
    init(root: URL) throws {
        let fd = Darwin.open(root.appendingPathComponent(".lease").path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw CocoaError(.fileReadUnknown)
        }
        descriptor = fd
    }
    deinit { Darwin.close(descriptor) }
}
