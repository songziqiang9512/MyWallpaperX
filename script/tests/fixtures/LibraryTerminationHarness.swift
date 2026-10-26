import AppKit
import Combine
import Foundation
import SQLite3

// Original Sequence/transaction and actual metadata owners are compiled.
// Media, process exit, and profile operations are recording leaves.
@MainActor private final class WallpaperManager {
    static let shared = WallpaperManager()
    var playbackSwitch = PlaybackSwitchTransaction()
    var sequence = WallpaperPlaybackSequence()
    var flushes = 0
    var desktopRestorations = 0
    func restoreSystemDesktopWallpaperOnTermination() { desktopRestorations += 1 }
    var playbackIntentEpoch: UInt64 { playbackSwitch.epoch }
    @discardableResult func beginPlaybackIntent() -> UInt64 { sequence.stop(); run(playbackSwitch.stop()); return playbackSwitch.epoch }
    func flushPersistentState() { flushes += 1 }
    func play(_ reference: WallpaperReference) throws {
        let source = try WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 1,
            entries: [.init(reference: reference, runtime: .video, isPlayable: true)])
        let proposal = sequence.proposeSelection(reference, from: source)!
        let (ticket, effects) = playbackSwitch.begin(.video)
        precondition(sequence.stage(proposal, ticket: ticket))
        run(effects); run(playbackSwitch.prepared(ticket, executionID: UUID()))
    }
    private func run(_ initial: [PlaybackSwitchTransaction.Effect]) {
        var effects = initial
        while !effects.isEmpty {
            switch effects.removeFirst() {
            case .output(let operation): effects += playbackSwitch.activityCompleted(operation, succeeded: true)
            case .activate(let selection): effects += playbackSwitch.visible(selection.ticket, executionID: selection.executionID!)
            case .commit(let selection, let recovery): _ = sequence.commit(selection.ticket, recovery: recovery)
            case .cancel(let barrier, _): effects += playbackSwitch.cancelled(barrier)
            case .retire(let barrier, _), .handoff(let barrier, _, _): effects += playbackSwitch.retired(barrier)
            default: break
            }
        }
    }
}
@MainActor private final class WallpaperEngine {
    static let shared = WallpaperEngine()
    var cleanups = 0
    func adoptIntentEpoch(_ epoch: UInt64) {}
    func cleanup() { cleanups += 1 }
}
@MainActor private final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    var shutdowns = 0
    func shutdown() { shutdowns += 1 }
}
@MainActor private final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    func advanceWebLaunchIntentGeneration() {}
}
@MainActor private final class DaemonPlaybackProcessRegistry {
    static let shared = DaemonPlaybackProcessRegistry()
    struct Result { var allExited: Bool; var remainingProcessIdentifiers: [Int32] { [] } }
    var acceptsNewProcesses = true
    var drainCalls = 0
    func closeAdmission() { acceptsNewProcesses = false }
    func waitForExit(_ completion: (Result) -> Void) { drainCalls += 1; completion(.init(allExited: true)) }
}
@MainActor private final class TestWorkspace {
    let collections: UserCollectionsController
    var editingAllowed = true
    init(_ collections: UserCollectionsController) { self.collections = collections }
    func setPersonalSettingsReady(_ ready: Bool) { editingAllowed = ready }
    func flush() async -> String? { await collections.flush() }
}
@MainActor private final class TestProfile {
    var allowsEditing = true
    var generation = 0
    func prepareForTermination() { generation += 1 }
}
@MainActor private enum MyWallpaperXApplication {
    static var libraryWorkspace: TestWorkspace?
    static var personalSettings: TestProfile?
    private static var isPreparingLibraryTermination = false
    // ACTUAL_APP_HELPERS
}
@MainActor private enum MainWindowCoordinator { static func mainWindow() -> NSWindow? { nil } }
@MainActor private func makeAppAlert(title: String, message: String) -> String { title + message }
@MainActor private func presentAppAlert(_ alert: String, in window: NSWindow?) { ProbeApplication.alerts.append(alert) }
@MainActor private final class ProbeApplication: NSApplication {
    var replies: [Bool] = []
    static var alerts: [String] = []
    override func reply(toApplicationShouldTerminate shouldTerminate: Bool) { replies.append(shouldTerminate) }
}
@MainActor private final class AppDelegate: NSObject {
    var statusBarController: NSObject? = NSObject()
    var pendingInitialWindowOpen: DispatchWorkItem?
    var didPrepareProductTermination = false
    var terminationReplyPending = false
    // ACTUAL_TERMINATION_METHODS
}
nonisolated final class TestSQLGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasEntered = false
    private let release = DispatchSemaphore(value: 0)
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return hasEntered }
    func block() { lock.lock(); hasEntered = true; lock.unlock(); release.wait() }
    func unblock() { release.signal() }
}

@main private enum LibraryTerminationChecks {
    @MainActor static func main() async throws {
        let app = ProbeApplication.shared as! ProbeApplication
        app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let a = WallpaperReference(provider: .videoLibrary, sourceID: "A")
        let b = WallpaperReference(provider: .videoLibrary, sourceID: "B")
        var checks: [String: Bool] = [:]
        func wait(_ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
            return condition()
        }
        do {
            let store = UserCollectionsStore(url: root.appendingPathComponent("tail.sqlite3"))
            let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
            let playlistGate = TestSQLGate(), historyGate = TestSQLGate()
            try await store.installTestGate(playlistGate, name: "playlist_gate", table: "playlists")
            try await store.installTestGate(historyGate, name: "history_gate", table: "recent")
            controller.onOrganizationTransaction = { _, _, _, _ in controller.recordSuccessfulUse(a, locator: nil, sequence: 1) }
            let create = Task { @MainActor in try await controller.createPlaylist(name: "Queued first") }
            guard await wait({ playlistGate.entered }) else { fatalError("playlist SQL never entered") }
            var finished = false
            let flushing = Task { @MainActor in let result = await controller.flush(); finished = true; return result }
            try? await Task.sleep(for: .milliseconds(15))
            playlistGate.unblock()
            guard await wait({ historyGate.entered }) else { fatalError("late history SQL never entered") }
            try? await Task.sleep(for: .milliseconds(15))
            checks["flush-waits-for-new-tail-admitted-during-awaited-transaction"] = !finished
            historyGate.unblock()
            let result = await flushing.value
            _ = try await create.value
            checks["stable-flush-publishes-late-real-sqlite-history"] = result == nil && controller.snapshot.recent.map(\.reference) == [a]
            try await store.removeTestGate(name: "playlist_gate")
            try await store.removeTestGate(name: "history_gate")
            do { _ = try await controller.duplicatePlaylist(UUID()) } catch {}
            checks["failed-ui-command-remains-reported"] = controller.lastError != nil
            checks["old-validation-error-does-not-pretend-to-be-unsaved-metadata"] = await controller.flush() == nil
        }
        do {
            let store = UserCollectionsStore(url: root.appendingPathComponent("quit.sqlite3"))
            let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
            let workspace = TestWorkspace(controller), profile = TestProfile()
            MyWallpaperXApplication.libraryWorkspace = workspace
            MyWallpaperXApplication.personalSettings = profile
            try await store.installHistoryFailure()
            controller.recordSuccessfulUse(a, locator: nil, sequence: 1)
            checks["real-sqlite-trigger-failure-retains-unsaved-success"] = await controller.flush() != nil
            let manager = WallpaperManager.shared
            try manager.play(a)
            let originalTicket = manager.playbackSwitch.committed?.ticket
            let delegate = AppDelegate()
            checks["quit-begins-reversible-editing-barrier"] = delegate.applicationShouldTerminate(app) == .terminateLater
                && !workspace.editingAllowed && profile.generation == 1
            checks["duplicate-quit-coalesces-before-flush-result"] = delegate.applicationShouldTerminate(app) == .terminateLater && profile.generation == 1
            guard await wait({ app.replies.count == 1 }) else { fatalError("quit failure never replied") }
            checks["failed-quit-keeps-original-output-process-admission-and-status-item"] = app.replies == [false]
                && DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses && delegate.statusBarController != nil
                && !delegate.didPrepareProductTermination && WallpaperEngine.shared.cleanups == 0
                && SceneDaemonClient.shared.shutdowns == 0 && manager.playbackSwitch.committed?.ticket == originalTicket
            checks["failed-quit-restores-editing-and-reports-one-error"] = workspace.editingAllowed && !delegate.terminationReplyPending
                && ProbeApplication.alerts.count == 1
            checks["failed-quit-does-not-release-system-desktop-ownership"] = manager.desktopRestorations == 0
            try manager.play(b)
            checks["new-explicit-play-after-cancelled-quit-commits-new-original-ticket"] = manager.sequence.committed?.reference == b
                && manager.playbackSwitch.committed?.ticket != originalTicket
            let newList = try await controller.createPlaylist(name: "Still writable after cancelled quit")
            checks["cancelled-quit-still-allows-real-relationship-transaction"] = controller.snapshot.playlists.map(\.id) == [newList]
            try await store.removeTestGate(name: "history_failure")
            controller.recordSuccessfulUse(b, locator: nil, sequence: 2)
            _ = delegate.applicationShouldTerminate(app)
            guard await wait({ app.replies.count == 2 }) else { fatalError("repaired quit never replied") }
            checks["retry-persists-original-failed-success-before-new-success"] = controller.snapshot.recent.map(\.reference) == [b, a]
            checks["successful-flush-precedes-one-irreversible-cleanup-and-drain"] = app.replies == [false, true]
                && !DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses && delegate.didPrepareProductTermination
                && delegate.statusBarController == nil && WallpaperEngine.shared.cleanups == 1
                && SceneDaemonClient.shared.shutdowns == 1 && DaemonPlaybackProcessRegistry.shared.drainCalls == 1
            checks["successful-quit-restores-desktop-once-after-the-durable-flush"] = manager.desktopRestorations == 1
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

// SQL_GATE_EXTENSION_BEGIN
extension UserCollectionsStore {
    func installTestGate(_ gate: TestSQLGate, name: String, table: String) throws {
        try open()
        let pointer = Unmanaged.passUnretained(gate).toOpaque()
        guard sqlite3_create_function_v2(database, name, 0, SQLITE_UTF8, pointer, { context, _, _ in
            guard let pointer = sqlite3_user_data(context) else { return }
            Unmanaged<TestSQLGate>.fromOpaque(pointer).takeUnretainedValue().block()
            sqlite3_result_int(context, 0)
        }, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        try execute("CREATE TEMP TRIGGER \(name) BEFORE INSERT ON \(table) BEGIN SELECT \(name)(); END")
    }
    func removeTestGate(name: String) throws { try execute("DROP TRIGGER \(name)") }
    func installHistoryFailure() throws {
        try execute("CREATE TEMP TRIGGER history_failure BEFORE INSERT ON recent BEGIN SELECT RAISE(ABORT, 'fixture persistence failure'); END")
    }
}
// SQL_GATE_EXTENSION_END
