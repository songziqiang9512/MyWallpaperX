import Foundation

nonisolated struct LibraryCollectionsStartupPaths: Sendable {
    let videoIndexURL: URL
    let staticImageURL: URL
    let backupDirectoryURL: URL
    let publication: LibraryCollectionsMigrationPublicationPaths

    @MainActor static func applicationPaths() throws -> Self {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let library = support.appendingPathComponent("MyWallpaperX", isDirectory: true)
        let recovery = library.appendingPathComponent("library-collections-migration-v1", isDirectory: true)
        return Self(videoIndexURL: library.appendingPathComponent("wallpaper_index.sqlite3"),
            staticImageURL: support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "MyWallpaperX", isDirectory: true)
                .appendingPathComponent("sil_wallpapers.json"),
            backupDirectoryURL: recovery.appendingPathComponent("legacy-inputs", isDirectory: true),
            publication: .init(inputSnapshotURL: recovery.appendingPathComponent("input.json"),
                mappingManifestURL: recovery.appendingPathComponent("mapping.json"),
                stagingDatabaseURL: library.appendingPathComponent("user-collections.staging.sqlite3"),
                finalDatabaseURL: library.appendingPathComponent("user-collections.sqlite3"),
                publicationLockURL: recovery.appendingPathComponent("publication.lock")))
    }
}

nonisolated enum LibraryCollectionsStartupOutcome: Sendable {
    case ready(LibraryCollectionsMigrationPublicationResult)
    case recoveryRequired(String)

    var recoveryMessage: String? {
        if case .recoveryRequired(let message) = self { return message }
        return nil
    }
}

/// One pre-AppKit admission, with no source service or permanent event timer.
/// Keep NSApplication.run on the original synchronous entry stack: nesting it
/// inside an awaited MainActor job starves DispatchQueue.main on macOS.
@MainActor enum LibraryCollectionsStartupAdmission {
    private final class Completion { var outcome: LibraryCollectionsStartupOutcome? }

    static func waitForResult(timeout: TimeInterval = 120,
        operation: @escaping @Sendable () async throws -> LibraryCollectionsMigrationPublicationResult
    ) throws -> LibraryCollectionsStartupOutcome {
        let completion = Completion()
        let task = Task { @MainActor in
            do { completion.outcome = .ready(try await operation()) }
            catch { completion.outcome = .recoveryRequired(error.localizedDescription) }
            CFRunLoopStop(CFRunLoopGetMain())
        }
        // Exactly one bounded wait, before any delegate/legacy owner exists.
        CFRunLoopRunInMode(.defaultMode, timeout, false)
        guard let result = completion.outcome else {
            task.cancel()
            // Never start source owners while a cancelled I/O task can still
            // finish. The synchronous entry must end this launch on timeout.
            throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "资料库启动尚未完成，本次启动已停止；恢复文件已保留，请重新启动。"])
        }
        return result
    }

    @concurrent static func prepare(paths: LibraryCollectionsStartupPaths, needsViewPreferencesSeed: Bool = true,
        freezeDefaults: @escaping @MainActor @Sendable () throws -> Data = {
            try LegacyLibraryFrozenDefaults.rawValues(defaults: .standard)
        }
    ) async throws -> LibraryCollectionsMigrationPublicationResult {
        return try await LibraryCollectionsMigrationPublication.openOrMigrate(paths: paths.publication,
            backupDirectoryURL: paths.backupDirectoryURL, needsViewPreferencesSeed: needsViewPreferencesSeed) {
                let rawDefaults = try await freezeDefaults()
                try Task.checkCancellation()
                return try LegacyLibrarySnapshot.capture(rawDefaults: rawDefaults, indexURL: paths.videoIndexURL,
                    staticImageURL: paths.staticImageURL, backupDirectoryURL: paths.backupDirectoryURL,
                    inputSnapshotURL: paths.publication.inputSnapshotURL)
            }
    }
}
