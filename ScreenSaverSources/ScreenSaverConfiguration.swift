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
    static func currentUserRoot() throws -> URL {
        var entry = passwd()
        var resolved: UnsafeMutablePointer<passwd>?
        let capacity = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        var storage = [CChar](repeating: 0, count: capacity)
        let result = getpwuid_r(getuid(), &entry, &storage, storage.count, &resolved)
        guard result == 0, let home = resolved?.pointee.pw_dir else {
            throw CocoaError(.fileReadNoPermission)
        }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MyWallpaperX/ScreenSaver", isDirectory: true)
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
