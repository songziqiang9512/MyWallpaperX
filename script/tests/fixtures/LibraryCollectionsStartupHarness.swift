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
        let applicationBeforeAdmission = mode == "appkit" ? NSApplication.shared : nil
        let database = root.appendingPathComponent("user-collections.sqlite3")
        let probe = StartupProbe()
        var checks: [String: Bool] = [:]
        func start() throws -> LibraryCollectionsStartupOutcome {
            try LibraryCollectionsStartupAdmission.waitForResult(timeout: 15) {
                try await LibraryCollectionsStartupAdmission.prepare(at: database)
            }
        }
        if mode == "timeout" {
            do {
                _ = try LibraryCollectionsStartupAdmission.waitForResult(timeout: 0.01) {
                    try await Task.sleep(for: .seconds(5))
                    throw CocoaError(.fileReadUnknown)
                }
                checks["timeoutStopsAdmission"] = false
            } catch { checks["timeoutStopsAdmission"] = true }
            checks["timeoutDoesNotCreateDatabase"] = !FileManager.default.fileExists(atPath: database.path)
        } else if mode == "invalid" {
            let original = Data("not a SQLite database".utf8)
            try original.write(to: database)
            let result = try start()
            checks["realReadFailureRequiresRecovery"] = result.recoveryMessage != nil
            checks["failureDoesNotReplaceDatabase"] = try Data(contentsOf: database) == original
        } else {
            let oldInputs = ["old.sqlite3", "sil.json", "input.json", "map.json", "publication.lock"]
            for name in oldInputs { try Data("obsolete input".utf8).write(to: root.appendingPathComponent(name)) }
            guard case .ready(let store, let initial) = try start() else { fatalError("admission failed") }
            checks["freshCurrentDatabaseStartsEmpty"] = initial.playlists.isEmpty && initial.members.isEmpty
            checks["startupDoesNotReadOrPublishLegacyInputs"] = try oldInputs.allSatisfy {
                try Data(contentsOf: root.appendingPathComponent($0)) == Data("obsolete input".utf8)
            } && !FileManager.default.fileExists(atPath: root.appendingPathComponent("stage.sqlite3").path)
            if mode == "restart" || mode == "reset" {
                let saved = try LibraryCollectionsStartupAdmission.waitForResult {
                    let created = try await store.apply(.createPlaylist(.init(name: "Current", sidebarRank: 0)), expectedEpoch: initial.resetEpoch)
                    let snapshot = mode == "reset" ? try await store.reset(expectedEpoch: initial.resetEpoch) : created
                    return .ready(store: store, snapshot: snapshot)
                }
                guard case .ready(_, let expected) = saved, case .ready(_, let reopened) = try start() else { fatalError("restart failed") }
                checks["restartReadsCurrentRowsAndEpochWithoutReseeding"] = reopened == expected
                checks["resetRetainsEmptyCurrentState"] = mode != "reset" || reopened.playlists.isEmpty && reopened.resetEpoch != initial.resetEpoch
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
}
