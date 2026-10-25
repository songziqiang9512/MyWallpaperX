import Foundation
import Combine
import QuartzCore

@MainActor enum Trace {static var values:[String]=[]}
@MainActor final class PlaybackCommandMultiplexer {
    static let shared=PlaybackCommandMultiplexer();var isPlaybackPaused=false
}
@MainActor final class SceneDaemonClient {
    static let shared=SceneDaemonClient()
    func cancelSwitch(ticket:PlaybackSwitchTicket,completion:@escaping()->Void){completion()}
    func stop(){}
}
extension Notification.Name {static let wallpaperSwitchDidFail=Self("switch-failed")}

/// Only the Workspace value lookup is a leaf. The action factory and both
/// product Stop owners below are copied unchanged by the driver.
@MainActor final class StopWorkspace {
    let manager: WallpaperManager
    let snapshot: WallpaperPlaybackSequence.Snapshot
    var unexpectedPlays = 0
    let relationships = (resetEpoch: UUID(), fixture: true)
    let presentation = StopPresentation()
    init(_ manager: WallpaperManager, _ snapshot: WallpaperPlaybackSequence.Snapshot) {
        self.manager = manager; self.snapshot = snapshot
    }
    func isPlaying(_ reference: WallpaperReference) -> Bool {
        manager.libraryPlaybackSequence.committed?.reference == reference
            && manager.libraryPlaybackSequence.committed?.ticket == manager.playbackSwitch.committed?.ticket
    }
    func capturePlaybackSnapshot(for reference: WallpaperReference) throws -> WallpaperPlaybackSequence.Snapshot { snapshot }
    func play(_ reference: WallpaperReference, from snapshot: WallpaperPlaybackSequence.Snapshot) { unexpectedPlays += 1 }
}
@MainActor final class StopPresentation { var page = 0 }
// Unavailable recovery is a separate tested consumer; this fixture exercises
// the real available-video primary action and both original Stop owners.
@MainActor final class WallpaperLibraryImportCoordinator {
    static func canRelocate<T>(_ item: WallpaperContentItem, relationships: T) -> Bool { false }
    func chooseReplacement(for reference: WallpaperReference) { preconditionFailure("Unexpected relocation") }
}
@MainActor enum WallpaperLibraryDownloadRecovery {
    static func makePrimaryAction<W,S,O>(for item: WallpaperContentItem, workspace: W, steam: S, online: O) -> (() -> Void)? { nil }
}

@MainActor final class WallpaperLibraryCommands {
    let workspace: StopWorkspace
    let manager: WallpaperManager
    let imports = WallpaperLibraryImportCoordinator(), steam = (), online = ()
    var canOrganize: Bool { false }
    init(_ workspace: StopWorkspace) { self.workspace = workspace; manager = workspace.manager }
    // ACTUAL_PRIMARY_ACTIONS
}

@main enum PlaybackExplicitStopChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        let paths = ["/controlled-first.mp4", "/controlled-second.mp4"]
        let references = paths.map { WallpaperReference(provider: .videoLibrary, sourceID: $0) }
        let snapshot = try WallpaperPlaybackSequence.Snapshot(source: .page(.playlist(UUID())), revision: 1,
            entries: references.map { .init(reference: $0, runtime: .video, isPlayable: true) })
        func content(_ index: Int) -> WallpaperContentItem {
            .init(reference: references[index], providerReference: references[index], locator: .init(mediaKind: .video),
                title: "Controlled video", kind: .video, publishedAvailability: .available,
                capabilities: [.play, .organize], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        func setup() -> (WallpaperManager, WallpaperEngine, StopWorkspace, WallpaperLibraryCommands) {
            let engine = WallpaperEngine(); WallpaperEngine.shared = engine
            let manager = WallpaperManager()
            manager.wallpapers = paths.map { VideoWallpaper(path: $0) }
            engine.switchPrepared = { [weak manager] ticket, endpoint in manager?.switchPrepared(ticket, endpoint: endpoint) }
            engine.switchVisible = { [weak manager] ticket, id in manager?.switchVisible(ticket, executionID: id) }
            engine.switchFailed = { [weak manager] ticket, reason in manager?.switchFailed(ticket, reason: reason) }
            manager.libraryPlaybackDispatcher = { [weak manager] pending in
                guard let manager else { return false }
                let wallpaper = VideoWallpaper(path: pending.proposal.entry.reference.sourceID)
                manager.pendingWallpaper = wallpaper
                manager.prepareVideoSwitch(wallpaper, libraryPending: pending)
                return true
            }
            let workspace = StopWorkspace(manager, snapshot)
            return (manager, engine, workspace, WallpaperLibraryCommands(workspace))
        }
        func event(_ type: String, execution: WallpaperEngine.VideoSwitchExecution,
                   session: WallpaperEngine.DisplayDaemonSession) -> DaemonEvent {
            var value = DaemonEvent(type: type, displayID: session.displayID,
                requestID: execution.requests[session.displayID], message: nil, videoPath: execution.path, contentKind: "video")
            value.cohortID = execution.id; value.activationID = execution.activationID; value.preparationGeneration = 1
            let rect = PlaybackSurfaceVisibility.Rect(CGRect(x: 0, y: 0, width: 200, height: 100))
            value.visibility = [.init(displayID: session.displayID, windowID: 10,
                expectedPID: session.process.processIdentifier, expectedLevel: 2, displayExists: true,
                localFrame: rect, screenFrame: rect, displayFrame: rect, localLevel: 2, localAlpha: 1,
                visible: true, miniaturized: false, onActiveSpace: true, serverPID: session.process.processIdentifier,
                serverFrame: rect, serverLevel: 2, serverAlpha: 1, onscreen: true)]
            return value
        }
        func prepare(_ manager: WallpaperManager, _ engine: WallpaperEngine, index: Int)
            -> (PlaybackSwitchTicket, WallpaperEngine.VideoSwitchExecution) {
            let ticket = manager.requestLibraryPlayback(reference: references[index], from: snapshot)!
            let execution = engine.videoCandidate!
            for session in execution.sessions.values { engine.videoDidPrepare(event("prepared", execution: execution, session: session), session: session) }
            return (ticket, execution)
        }
        func show(_ engine: WallpaperEngine, _ execution: WallpaperEngine.VideoSwitchExecution) {
            for session in execution.sessions.values { engine.videoDidBecomeVisible(event("ready", execution: execution, session: session), session: session) }
        }
        do {
            let (manager, engine, workspace, commands) = setup()
            let (ticket, execution) = prepare(manager, engine, index: 0); show(engine, execution)
            precondition(manager.playbackSwitch.committed?.ticket == ticket
                && manager.libraryPlaybackSequence.committed?.ticket == ticket && execution.finalized)
            let sessions = execution.sessions.values.sorted { $0.displayID < $1.displayID }
            precondition(sessions.count == 2 && sessions.allSatisfy { $0.process.isRunning })
            var settlements = 0
            manager.switchSettlementObservers[ticket] = [{ settlements += 1 }]
            let stop = commands.makePrimaryAction(for: content(0))!
            stop()
            checks["fixed-primary-stop-revokes-sequence-clock-without-playing-again"] = manager.libraryPlaybackSequence.committed == nil
                && manager.playbackSwitch.committed == nil && manager.autoSwitchTimer == nil
                && manager.libraryRotationDeadline.deadline == nil && workspace.unexpectedPlays == 0
            checks["explicit-stop-does-not-ack-before-real-process-exit"] = settlements == 0
                && manager.playbackSwitch.retirements.count == 1 && manager.switchEndpoints[execution.id] != nil
                && engine.displaySessions.isEmpty && sessions.allSatisfy { $0.process.isRunning && $0.transport.stopRequested }
            checks["explicit-stop-keeps-original-execution-owned-before-physical-exit"] = engine.videoExecutions[execution.id] === execution
                && execution.retirementDisplays == Set(sessions.map(\.displayID)) && execution.retirementCompletions.count == 1
            // The same old native action is revoked by its captured ticket.
            stop()
            checks["repeated-old-stop-action-does-not-duplicate-retirement"] = manager.playbackSwitch.retirements.count == 1
                && execution.retirementCompletions.count == 1 && settlements == 0
            // Unlike the revoked captured button, this enters both real Stop
            // bodies again while their first physical retirement is pending.
            let originalBarriers = Set(manager.playbackSwitch.retirements.keys)
            manager.stopCurrentPlayback()
            checks["repeated-generic-stop-keeps-one-live-retirement-owner"] = Set(manager.playbackSwitch.retirements.keys) == originalBarriers
                && engine.videoExecutions[execution.id] === execution
                && execution.retirementCompletions.count == 1 && settlements == 0
            engine.videoSessionDidExit(WallpaperEngine.DisplayDaemonSession(99), wasCurrent: false)
            sessions[0].transport.end()
            checks["first-display-exit-and-foreign-session-cannot-ack-last-display"] = settlements == 0
                && manager.playbackSwitch.retirements.count == 1 && manager.switchEndpoints[execution.id] != nil
                && sessions[1].process.isRunning
            sessions[1].transport.end()
            sessions[1].transport.end()
            checks["explicit-stop-last-display-exit-settles-transaction-and-endpoint-once"] = settlements == 1
                && manager.playbackSwitch.retirements.isEmpty && manager.switchEndpoints.isEmpty
                && manager.switchSelections.isEmpty && engine.videoExecutions.isEmpty
                && execution.retirementDisplays.isEmpty && execution.retirementCompletions.isEmpty
                && engine.activeVideoExecution == nil && engine.activeVideoPlayback == nil
                && manager.libraryPlaybackSequence.committed == nil && manager.autoSwitchTimer == nil
        }
        do {
            let (manager, engine, _, commands) = setup()
            let (old, execution) = prepare(manager, engine, index: 0); show(engine, execution)
            let sessions = execution.sessions.values.sorted { $0.displayID < $1.displayID }
            var settlements = 0
            manager.switchSettlementObservers[old] = [{ settlements += 1 }]
            commands.makePrimaryAction(for: content(0))!()
            let (next, candidate) = prepare(manager, engine, index: 1)
            checks["new-pending-waits-for-original-video-retirement"] = manager.playbackSwitch.pending?.selection.ticket == next
                && manager.libraryPlaybackSequence.pending?.ticket == next && !candidate.activated && settlements == 0
            sessions[0].transport.end(); sessions[1].transport.end()
            checks["old-stop-retirement-callback-does-not-clear-new-pending"] = settlements == 1
                && manager.playbackSwitch.retirements.isEmpty && manager.playbackSwitch.pending?.selection.ticket == next
                && manager.libraryPlaybackSequence.pending?.ticket == next && candidate.activated
                && manager.switchEndpoints[execution.id] == nil && manager.switchEndpoints[candidate.id] != nil
                && candidate.sessions.values.allSatisfy { $0.process.isRunning && !$0.transport.stopRequested }
            // In the negative control a stuck barrier leaves this unactivated;
            // do not fake visibility to erase the observed failure.
            if candidate.activated {
                show(engine, candidate)
                precondition(manager.playbackSwitch.committed?.ticket == next)
            }
            manager.stopCurrentPlayback()
            for session in candidate.sessions.values { session.transport.end() }
        }
        do {
            let (manager, engine, _, _) = setup()
            let (_, execution) = prepare(manager, engine, index: 0); show(engine, execution)
            let sessions = Array(execution.sessions.values)
            // Existing direct Engine callers have no registered Manager
            // retirement. Their original immediate cleanup stays intact.
            engine.stopPlayback()
            checks["direct-engine-stop-without-retirement-keeps-prior-cleanup-semantics"] = engine.videoExecutions.isEmpty
                && engine.activeVideoExecution == nil && engine.activeVideoPlayback == nil
                && engine.displaySessions.isEmpty && sessions.allSatisfy { $0.transport.stopRequested }
            for session in sessions { session.transport.end() }
            manager.stopAutoSwitchTimer()
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
