import AppKit
import Darwin
import Foundation

@MainActor final class StartupProbe {
    var freezes = 0
    var mainQueueDelivered = false
    var didLaunch = false
}

@MainActor final class StartupAppDelegate: NSObject, NSApplicationDelegate {
    let probe: StartupProbe
    init(_ probe: StartupProbe) { self.probe = probe }
    func applicationDidFinishLaunching(_ notification: Notification) { probe.didLaunch = true }
}

@main enum LibraryCollectionsStartupHarness {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        // Match the product entry, which obtains NSApplication before choosing
        // daemon/direct-product routing, but installs no delegate until ready.
        let applicationBeforeAdmission = mode == "appkit" ? NSApplication.shared : nil
        let domain = ProcessInfo.processInfo.environment["MWX_STARTUP_TEST_DOMAIN"]!
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: ProcessInfo.processInfo.environment["MWX_STARTUP_TEST_DOMAIN"]!) }
        let paths = makePaths(root)
        let probe = StartupProbe()
        let encoder = JSONEncoder()
        let video = VideoWallpaper(id: "offline-video", title: "Video", path: "/offline/video.mp4", tags: ["Original"])
        defaults.set(try encoder.encode([video]), forKey: "Wallpapers")
        defaults.set(try encoder.encode(["Original"]), forKey: "WallpaperTags")
        defaults.set("secret-must-not-be-backed-up", forKey: "SteamApiKey")
        try Data("[{\"id\":\"image\",\"title\":\"Image\",\"path\":\"/offline/image.png\",\"tags\":[\"Original\"]}]".utf8)
            .write(to: paths.staticImageURL)
        var checks: [String: Bool] = [:]
        func start() throws -> LibraryCollectionsStartupOutcome {
            try LibraryCollectionsStartupAdmission.waitForResult(timeout: 15) {
                try await LibraryCollectionsStartupAdmission.prepare(paths: paths) {
                    probe.freezes += 1
                    return try LegacyLibraryFrozenDefaults.rawValues(defaults: UserDefaults(suiteName: domain)!)
                }
            }
        }
        switch mode {
        case "wrong-defaults":
            defaults.set("original wrong type", forKey: "Wallpapers")
            let outcome = try start()
            let raw = try Data(contentsOf: paths.backupDirectoryURL.appendingPathComponent("raw-defaults.plist"))
            let values = try PropertyListSerialization.propertyList(from: raw, options: [], format: nil) as! [String: Any]
            checks["wrongTypeIsRecoveryNotEmptySuccess"] = outcome.recoveryMessage != nil && !exists(paths.publication.finalDatabaseURL)
            checks["rawOriginalTypeSavedBeforeTypedDecode"] = values["Wallpapers"] as? String == "original wrong type"
            checks["rawWhitelistExcludesCredential"] = values["SteamApiKey"] == nil
            checks["failureDoesNotPublishTypedInputOrCompletion"] = !exists(paths.publication.inputSnapshotURL)
                && !exists(paths.backupDirectoryURL.appendingPathComponent("manifest.json"))
        case "missing-stage", "missing-map", "missing-backup":
            let residual = mode == "missing-stage" ? paths.publication.stagingDatabaseURL :
                mode == "missing-map" ? paths.publication.mappingManifestURL : paths.backupDirectoryURL
            if mode == "missing-backup" {
                try FileManager.default.createDirectory(at: residual, withIntermediateDirectories: true)
                try Data("original".utf8).write(to: residual.appendingPathComponent("sentinel"))
            } else {
                try FileManager.default.createDirectory(at: residual.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("original".utf8).write(to: residual)
            }
            let outcome = try start()
            checks["orphanRecoveryStateNeverRecaptures"] = outcome.recoveryMessage != nil && probe.freezes == 0
            checks["orphanRecoveryStatePreserved"] = try Data(contentsOf: mode == "missing-backup" ? residual.appendingPathComponent("sentinel") : residual) == Data("original".utf8)
            checks["orphanHasNoPublishedDatabase"] = !exists(paths.publication.finalDatabaseURL)
        case "capture-gap", "saved-map":
            setenv("MWX_STARTUP_TEST_FAULT", mode == "capture-gap" ? "after-input" : "after-map", 1)
            let first = try start()
            unsetenv("MWX_STARTUP_TEST_FAULT")
            let input = try Data(contentsOf: paths.publication.inputSnapshotURL)
            let mapping = try? Data(contentsOf: paths.publication.mappingManifestURL)
            checks["interruptionRetainsDurableInputBeforeCompletion"] = first.recoveryMessage != nil &&
                (mode != "capture-gap" || !exists(paths.backupDirectoryURL.appendingPathComponent("manifest.json")))
            defaults.set("live source changed after failed launch", forKey: "Wallpapers")
            try FileManager.default.removeItem(at: paths.staticImageURL)
            let second = try start()
            if case .ready(let result) = second {
                checks["retryUsesSavedInputWithoutRefreeze"] = probe.freezes == 1 && result.snapshot.members.count == 2
                checks["savedInputBytesNotRewritten"] = try Data(contentsOf: paths.publication.inputSnapshotURL) == input
                if let mapping {
                    let saved = try JSONDecoder().decode(LibraryCollectionsMigrationManifest.self, from: mapping)
                    checks["savedMappingPreservesUUIDs"] = result.snapshot.playlists.map(\.id) == saved.tagMappings.map(\.playlistID)
                    checks["savedMappingBytesNotRewritten"] = try Data(contentsOf: paths.publication.mappingManifestURL) == mapping
                }
            } else { checks["retryUsesSavedInputWithoutRefreeze"] = false }
        case "timeout":
            do {
                _ = try LibraryCollectionsStartupAdmission.waitForResult(timeout: 0.01) {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw CocoaError(.fileReadUnknown)
                }
                checks["timeoutStopsAdmission"] = false
            } catch { checks["timeoutStopsAdmission"] = true }
            checks["timeoutNeverAdmitsOrCreatesAStore"] = !exists(paths.publication.finalDatabaseURL) && probe.freezes == 0
        default:
            let first = try start()
            guard case .ready(let result) = first else { fatalError("first admission failed") }
            checks["preCleanupCaptureRetainsOfflineReferences"] = result.snapshot.members.count == 2 && probe.freezes == 1
            checks["durableInputPrecedesCompleteCapture"] = exists(paths.publication.inputSnapshotURL)
                && exists(paths.backupDirectoryURL.appendingPathComponent("manifest.json"))
            if mode == "restart" || mode == "reset" {
                let changed = try LibraryCollectionsStartupAdmission.waitForResult {
                    let playlist = result.snapshot.playlists[0]
                    var replacement = playlist.metadata; replacement.name = "User changed"
                    let state = mode == "reset" ? try await result.store.reset(expectedEpoch: result.snapshot.resetEpoch) :
                        try await result.store.apply(.editPlaylistMetadata(id: playlist.id, expected: playlist.metadata,
                            replacement: replacement, coverAsset: nil, at: Date()), expectedEpoch: result.snapshot.resetEpoch)
                    return .init(store: result.store, snapshot: state, disposition: result.disposition)
                }
                guard case .ready(let saved) = changed else { fatalError("edit failed") }
                defaults.set("obsolete invalid fallback", forKey: "Wallpapers")
                try FileManager.default.removeItem(at: paths.staticImageURL)
                try FileManager.default.removeItem(at: paths.backupDirectoryURL)
                try FileManager.default.removeItem(at: paths.publication.inputSnapshotURL)
                try Data("obsolete broken map".utf8).write(to: paths.publication.mappingManifestURL)
                let repeated = try start()
                if case .ready(let reopened) = repeated {
                    checks["existingFinalBypassesAllOldInputs"] = probe.freezes == 1 && reopened.snapshot == saved.snapshot
                    checks["resetMarkerOrLaterEditRemainsAuthoritative"] = mode == "reset" ?
                        reopened.snapshot.migrationManifestID == "reset-complete" : reopened.snapshot.playlists[0].name == "User changed"
                } else { checks["existingFinalBypassesAllOldInputs"] = false }
            }
            if mode == "appkit" {
                let app = applicationBeforeAdmission!
                app.setActivationPolicy(.prohibited)
                let delegate = StartupAppDelegate(probe)
                app.delegate = delegate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { probe.mainQueueDelivered = true }
                let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        app.stop(nil)
                        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                            timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
                        app.postEvent(event, atStart: false)
                    }
                }
                withExtendedLifetime((delegate, timer)) { app.run() }
                checks["syncEntryDeliversMainQueueAfterBootstrap"] = probe.mainQueueDelivered && probe.didLaunch
            }
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private static func makePaths(_ root: URL) -> LibraryCollectionsStartupPaths {
        let recovery = root.appendingPathComponent("recovery", isDirectory: true)
        return .init(videoIndexURL: root.appendingPathComponent("old.sqlite3"), staticImageURL: root.appendingPathComponent("sil.json"),
            backupDirectoryURL: recovery.appendingPathComponent("capture", isDirectory: true),
            publication: .init(inputSnapshotURL: recovery.appendingPathComponent("input.json"),
                mappingManifestURL: recovery.appendingPathComponent("map.json"),
                stagingDatabaseURL: root.appendingPathComponent("stage.sqlite3"), finalDatabaseURL: root.appendingPathComponent("final.sqlite3"),
                publicationLockURL: recovery.appendingPathComponent("publication.lock")))
    }
}
