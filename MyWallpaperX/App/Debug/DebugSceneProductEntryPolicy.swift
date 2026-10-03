#if DEBUG
import Darwin
import Foundation

/// DEBUG-only admission policy for the product-entry Scene probe. Keeping the
/// argument and path checks separate from the runner makes the negative safety
/// cases executable without constructing product singletons.
struct DebugSceneProductEntryPolicy {
    private static let daemonClientFlag = "--mwx-debug-scene-daemon-client"
    private static let productEntryFlag = "--mwx-debug-scene-product-entry"
    private static let sceneRootFlag = "--mwx-debug-scene-root"

    static func requiresProductCoordinator(arguments: [String]) -> Bool {
        arguments.contains(daemonClientFlag)
            && arguments.contains(productEntryFlag)
            && argumentValue(after: sceneRootFlag, in: arguments) != nil
    }

    static func protectedUserHomeURL() -> URL? {
        guard let passwordEntry = getpwuid(getuid()),
              let homePointer = passwordEntry.pointee.pw_dir else {
            return nil
        }
        let path = String(cString: homePointer)
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
    }

    static func protectedWorkshopRootURL() -> URL? {
        protectedUserHomeURL()?
            .appendingPathComponent(
                "Movies/MyWallpaperX/创意工坊",
                isDirectory: true
            )
            .resolvingSymlinksInPath().standardizedFileURL
    }

    static func isolatedExistingDirectory(
        rawPath: String,
        disjointFrom protectedRootURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = URL(fileURLWithPath: trimmed, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else { return nil }
        let protectedRoot = protectedRootURL
            .resolvingSymlinksInPath().standardizedFileURL
        guard !pathsOverlap(candidate.path, protectedRoot.path) else {
            return nil
        }
        return candidate
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs
            || lhs.hasPrefix(rhs + "/")
            || rhs.hasPrefix(lhs + "/")
    }

    private static func argumentValue(
        after flag: String,
        in arguments: [String]
    ) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1),
              !arguments[index + 1].isEmpty else { return nil }
        return arguments[index + 1]
    }
}
#endif
