import CoreFoundation
import Foundation

// Only transport and unrelated notification storage are leaves. The test
// compiles the real Client texture extension and real launch/event handlers.
@MainActor final class SceneDaemonClient {
    // This legacy texture harness has no product callbacks. Native endpoints
    // and their exact ticket/receipt behavior execute in test_scene_switch_endpoint.
    typealias PlaybackSwitchTicket = Int
    final class SwitchExecution {
        let generation: UInt64 = 0, requestID = UUID(), id = UUID(), ticket = 0
        var activated = false, presented = false
    }
    var pendingSwitchTicket: Int?, activeSwitchTicket: Int?
    var pendingSwitchExecution: SwitchExecution?, activeSwitchExecution: SwitchExecution?
    struct QueuedSwitchPreparation {
        let request:ScenePlaybackLoadRequest;let ticket:Int;let resourceLifetime:Int?
    }
    var queuedSwitchPreparation:QueuedSwitchPreparation?
    struct CommittedSwitchRecovery {let ticket:Int}
    var committedSwitchRecovery:CommittedSwitchRecovery?
    var switchPrepared: Bool?
    var switchVisible: ((Int, UUID) -> Void)?
    var switchFailed: ((Int, String) -> Void)?
    var switchLost: ((Int, String) -> Void)?
    func cancelSwitch(ticket: Int, completion: () -> Void) { completion() }
    func finishSwitchControlsAfterExit(generation: UInt64) {}
    func rememberCommittedSwitchForRecovery(){}
    func adoptQueuedSwitchPreparationForRecovery(){}
    func resumeCommittedSwitchRecoveryIfPossible(after ticket:Int?){}
    struct Transport {
        var isRunning = true
        func send(_ data: Data) {}
        func closeInput() {}
        func closeIO() {}
        func terminate() {}
        func scheduleForcedTermination(after seconds: Double) {}
        func requestGracefulStop(_ data: Data?) {}
    }
    struct ResourceLifetime {
        let lifetime: Int
        var rootURL: URL = URL(fileURLWithPath: "/own")
        var recordID: String? = "own"
    }
    var activeIntent: ScenePlaybackLoadRequest?
    var pendingIntent: ScenePlaybackLoadRequest?
    var activeResourceLifetime: ResourceLifetime?
    var pendingResourceLifetime: ResourceLifetime?
    var activeRecordID: String?
    var activeRequestID: UUID?
    struct ActiveCallbackPropertyFacts: Equatable {
        let transportGeneration: UInt64
        let requestID: UUID
        let recordID: String?
        let reachability: ScenePreparedCallbackPropertyReachability
    }
    var activeCallbackPropertyFacts: ActiveCallbackPropertyFacts?
    var pendingRequestID: UUID?
    var pendingPresentationRequestID:UUID?
    var pendingPresentationReachability:ScenePreparedCallbackPropertyReachability?
    var requestResourceLifetimes:[UUID:Int]=[:]
    var endpointReady = true
    var transport: Transport? = .init()
    var sessionGeneration: UInt64 = 1
    var launchState: SceneWallpaperLaunchState?
    var pendingTextureUpdates: [UInt64: PendingTextureUpdate] = [:]
    var textureUpdateAdmissionClosed = false
    var latestTextureRevisions: [String: UInt64] = [:]
    var lastPropertyRevision: UInt64 = 0
    var pendingPropertyRevisions: [UInt64: String] = [:]
    var sent: [[String: Any]] = []
    var launchControls:[[String:Any]]=[]
    var launches: [ScenePlaybackLoadRequest] = []
    var restartBackoff = Backoff()
    var restartWorkItem: DispatchWorkItem?
    var handshakeWorkItem: DispatchWorkItem?
    var latestFrameStats: Int?
    var retiringResourceLifetimes: [UInt64: [Int]] = [:]
    var expectedTerminationGenerations: Set<UInt64> = []
    var retiringTransports: [UInt64: Transport] = [:]
    var restartReasons: [String] = []
    var warmSessionPending = false
    struct Backoff { func reset() {} }
    func failPendingFrameCaptures() {}
    func revokeAudioSpectrumDemand(generation: UInt64) {}
    func revokeSystemMediaDemand(generation: UInt64) {}
    func finishShutdownIfPossible() {}
    func scheduleRestart(reason: String) { restartReasons.append(reason) }
    func ensureSession() -> Bool { true }
    func replayPendingIntent() { if let pendingIntent { launches.append(pendingIntent) } }
    func stop() {stop(postsLaunchState:false)}

    func hasIntent(for recordID: String) -> Bool {
        activeIntent?.recordID == recordID || pendingIntent?.recordID == recordID
    }
    func send(_ payload: [String: Any]) {
        if let command=payload["cmd"] as? String,
           ["commitCandidate","finalizeCandidate","cancelCandidate"].contains(command) {
            launchControls.append(payload)
        } else { sent.append(payload) }
    }
    func publishFailure(code: String, message: String) { fatalError(message) }
}

enum DaemonNewlineJSON {
    static func encodeJSONObject(_ value: [String: Any], options: JSONSerialization.WritingOptions) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: options)
    }
}

// Unrelated callback-panel metadata storage mirrors the production value API;
// command admission, acknowledgements and first-present handlers remain real.
nonisolated struct ScenePreparedCallbackPropertyReachability: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        let rootPath: String
        let projectWitness: String
        let sceneWitness: String
    }
    let source: Source
    let scriptGeneration: UInt64
    let propertyKeys: Set<String>
}
struct SceneWallpaperLaunchState {
    enum Phase: String {
        case accepted, preparingModel, preparingPrograms, preparingResources, preparingSurfaces
        case launched, cancelled, failed, stopped
    }
    let requestID: UUID
    let recordID: String?
    let phase: Phase
    let message: String
    var callbackPropertyReachability: ScenePreparedCallbackPropertyReachability? = nil
}
struct SceneFramePresentation {
    let requestID: UUID
    let recordID: String?
    let uptimeMicros: UInt64
}
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Self("own-launch-test")
    static let sceneWallpaperFirstFrameDidPresent = Self("own-first-test")
}

@main enum ControlChecks {
    @MainActor static func main() throws {
        func intent(_ path: String = "old.png") -> ScenePlaybackLoadRequest {
            .init(rootURL: URL(fileURLWithPath: "/own"),
                propertyOverrides: ["cover": .string(path)],
                userPropertyTextures: ["cover": .init(url: URL(fileURLWithPath: "/" + path), bookmarkData: nil)],
                recordID: "own")
        }
        func update(_ revision: UInt64, key: String = "cover", reset: Bool = false) -> ScenePlaybackTextureUpdate {
            .init(references: reset ? [:] : [key: .init(url: URL(fileURLWithPath: "/new.png"), bookmarkData: Data([1]))],
                resetKeys: reset ? [key] : [], values: [key: .string(reset ? "" : "new.png")],
                revision: revision, recordID: "own")
        }
        func client() -> SceneDaemonClient {
            let result = SceneDaemonClient()
            result.activeIntent = intent()
            result.activeRecordID = "own"
            result.activeRequestID = UUID()
            return result
        }
        func ack(_ client: SceneDaemonClient, _ revision: Any, _ outcome: String = "applied") {
            client.handleTextureUpdateResult(["revision": revision, "recordID": "own", "outcome": outcome])
        }
        func launch(_ client: SceneDaemonClient, id: UUID, phase: String) {
            if phase == "accepted" {
                // This helper models an expected launch round trip. The real
                // sender fixes the request ID before its accepted event; the
                // transport leaf here lets each scenario choose that ID.
                precondition(client.endpointReady && client.transport?.isRunning == true)
                precondition(client.pendingIntent?.recordID == "own")
                client.pendingRequestID = id
            }
            client.handleLaunchState(["requestID": id.uuidString, "recordID": "own", "phase": phase, "message": "own"])
        }
        func first(_ client: SceneDaemonClient, id: UUID) {
            client.handleFirstFrame(["requestID": id.uuidString, "recordID": "own", "uptimeMs": 1])
        }
        var checks: [String: Bool] = [:]
        do {
            let c = client()
            c.pendingIntent = intent()
            let sentRequestID = UUID()
            c.pendingRequestID = sentRequestID
            // Bypass the expected-round-trip helper: an unsolicited event
            // must not acquire the sender's identity or replace pending state.
            c.handleLaunchState(["requestID": UUID().uuidString, "recordID": "own",
                "phase": "accepted", "message": "foreign"])
            checks["foreign_accepted_keeps_sender_request_identity"] = c.pendingRequestID == sentRequestID
                && c.launchState == nil && c.activeIntent == intent() && c.pendingIntent == intent()
        }
        for retirement in ["stop", "switch", "termination"] {
            let c = client(); var results: [String: ScenePlaybackTextureUpdateOutcome] = [:]
            var reentrantCallsAccepted = false
            _ = c.applyUserTextureUpdate(update(1, reset: true)) { outcome in
                results["A"] = outcome
                let apply = c.applyUserTextureUpdate(update(2, key: "background", reset: true)) { results["B-apply"] = $0 }
                let reload = c.reloadUserTextureUpdate(update(3, key: "background", reset: true)) { results["B-reload"] = $0 }
                reentrantCallsAccepted = apply && reload
            }
            let sentBeforeRetirement = c.sent.count
            if retirement == "switch" {
                c.requestLaunch(.init(rootURL: URL(fileURLWithPath: "/next"),
                    propertyOverrides: [:], userPropertyTextures: [:], recordID: "next"))
            } else if retirement == "termination" {
                c.handleTermination(status: 9, generation: c.sessionGeneration)
            } else { c.stop(postsLaunchState: false) }
            let prefix = retirement + "_chain_"
            checks[prefix + "callbacks_complete"] = results.count == 3 && reentrantCallsAccepted
                && results["A"] == (retirement == "termination" ? .failed("Scene daemon disconnected") : .superseded)
                && results["B-apply"] == .superseded && results["B-reload"] == .superseded
            checks[prefix + "pending_empty"] = c.pendingTextureUpdates.isEmpty
            checks[prefix + "no_retired_send"] = c.sent.count == sentBeforeRetirement
        }
        do {
            let c = client(); var results: [String: ScenePlaybackTextureUpdateOutcome] = [:]
            _ = c.applyUserTextureUpdate(update(1)) { results["drained"] = $0
                c.finishPendingTextureUpdates(.superseded)
                _ = c.applyUserTextureUpdate(update(2)) { results["after-nested-apply"] = $0 }
                _ = c.reloadUserTextureUpdate(update(3)) { results["after-nested-reload"] = $0 }
            }
            let sentBeforeDrain = c.sent.count
            c.finishPendingTextureUpdates(.superseded)
            checks["nested_drain_keeps_admission_closed"] = results.count == 3
                && results.values.allSatisfy { $0 == .superseded }
                && c.pendingTextureUpdates.isEmpty && c.sent.count == sentBeforeDrain
            let accepted = c.applyUserTextureUpdate(update(4)) { results["retry"] = $0 }
            ack(c, 4)
            checks["normal_phase_retry_after_drain"] = accepted && results["retry"] == .applied
                && c.pendingTextureUpdates.isEmpty && c.sent.count == sentBeforeDrain + 1
        }
        do {
            let c = client(); var results: [ScenePlaybackTextureUpdateOutcome] = []
            _ = c.applyUserTextureUpdate(update(1)) { results.append($0) }
            c.stop(postsLaunchState: true)
            checks["explicit_stop_supersedes_before_transport_exit"] = results == [.superseded]
                && c.activeIntent == nil && c.pendingTextureUpdates.isEmpty
            c.handleTermination(status: 0, generation: c.sessionGeneration)
            checks["stop_exit_is_expected_and_silent"] = results == [.superseded] && c.restartReasons.isEmpty
        }
        do {
            let c = client(); var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.applyUserTextureUpdate(update(1)) { result = $0 }
            c.handleTermination(status: 9, generation: c.sessionGeneration)
            checks["transport_death_finishes_failed"] = result == .failed("Scene daemon disconnected")
                && c.pendingIntent == intent() && c.restartReasons == ["daemon-exited-9"]
        }
        for phase in ["cancelled", "failed"] {
            let c = client(); let candidate = UUID(); var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.reloadUserTextureUpdate(update(1)) { result = $0 }
            launch(c, id: candidate, phase: "accepted")
            launch(c, id: candidate, phase: phase)
            checks[phase == "cancelled" ? "cancelled_launch_supersedes" : "failed_launch_remains_failure"] =
                result == (phase == "cancelled" ? .superseded : .failed("own")) && c.activeIntent == intent()
        }
        for pendingTicket in [11, 22] {
            let c = client(), candidate = UUID()
            c.activeSwitchTicket = 11
            c.pendingIntent = intent()
            c.pendingRequestID = candidate
            c.pendingSwitchTicket = pendingTicket
            c.committedSwitchRecovery = .init(ticket: 11)
            var failures: [Int] = [], losses: [Int] = []
            c.switchFailed = { ticket, _ in failures.append(ticket) }
            c.switchLost = { ticket, _ in losses.append(ticket) }
            launch(c, id: candidate, phase: "failed")
            checks["healthy_active_survives_failed_ticket_\(pendingTicket)"] =
                c.activeIntent == intent() && failures == [pendingTicket] && losses.isEmpty
                && c.committedSwitchRecovery?.ticket == 11
        }
        do {
            let c = client(), candidate = UUID()
            c.activeIntent = nil
            c.activeRecordID = nil
            c.activeRequestID = nil
            c.pendingIntent = intent()
            c.pendingRequestID = candidate
            c.pendingSwitchTicket = 11
            c.committedSwitchRecovery = .init(ticket: 11)
            var failures: [Int] = [], losses: [Int] = []
            c.switchFailed = { ticket, _ in failures.append(ticket) }
            c.switchLost = { ticket, _ in losses.append(ticket) }
            launch(c, id: UUID(), phase: "failed")
            checks["stale_failure_cannot_lose_recovery"] = c.pendingRequestID == candidate
                && c.committedSwitchRecovery?.ticket == 11 && failures.isEmpty && losses.isEmpty
            launch(c, id: candidate, phase: "failed")
            checks["failed_committed_recovery_reports_loss_once"] = c.activeIntent == nil
                && c.pendingIntent == nil && c.committedSwitchRecovery == nil
                && failures.isEmpty && losses == [11]
            launch(c, id: candidate, phase: "failed")
            checks["duplicate_recovery_failure_is_terminal"] = failures.isEmpty && losses == [11]
        }
        do {
            let c = client(); var results: [ScenePlaybackTextureUpdateOutcome] = []
            _ = c.applyUserTextureUpdate(update(1)) { results.append($0) }
            checks["pending_keeps_accepted_replay"] = c.activeIntent == intent() && results.isEmpty
            ack(c, true); ack(c, -1); ack(c, 1.5)
            checks["invalid_ack_revision_ignored"] = results.isEmpty && c.pendingTextureUpdates.count == 1
            ack(c, 1, "failed")
            checks["failure_keeps_replay"] = c.activeIntent == intent() && results.count == 1
            _ = c.applyUserTextureUpdate(update(2)) { results.append($0) }
            ack(c, 2)
            checks["success_updates_replay"] = c.activeIntent?.propertyOverrides["cover"] == .string("new.png")
                && c.activeIntent?.userPropertyTextures["cover"]?.url.path == "/new.png"
        }
        do {
            let c = client(); var results: [String: ScenePlaybackTextureUpdateOutcome] = [:]
            _ = c.applyUserTextureUpdate(update(1)) { results["old"] = $0 }
            _ = c.applyUserTextureUpdate(update(2, key: "background")) { results["other"] = $0 }
            _ = c.applyUserTextureUpdate(update(3, reset: true)) { results["reset"] = $0 }
            checks["same_key_superseded_other_key_retained"] = results["old"] == .superseded
                && c.pendingTextureUpdates.count == 2
            ack(c, 1); ack(c, 2); ack(c, 3)
            checks["reset_wins_and_other_key_applies"] = results["reset"] == .applied && results["other"] == .applied
                && c.activeIntent?.userPropertyTextures["cover"] == nil
                && c.activeIntent?.userPropertyTextures["background"] != nil
            var duplicate: ScenePlaybackTextureUpdateOutcome?
            _ = c.applyUserTextureUpdate(update(3)) { duplicate = $0 }
            checks["duplicate_revision_superseded"] = duplicate == .superseded
        }
        do {
            let c = client(); var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.applyUserTextureUpdate(update(1)) { result = $0 }
            c.sessionGeneration += 1
            ack(c, 1)
            checks["old_generation_ack_ignored"] = result == nil
            c.finishPendingTextureUpdates(.failed("disconnected"))
            checks["death_finishes_waiter_without_relaunch"] = result == .failed("disconnected") && c.launches.isEmpty
        }
        do {
            let c = client(); let oldID = c.activeRequestID!; let candidate = UUID()
            c.pendingIntent = intent()
            var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.reloadUserTextureUpdate(update(1)) { result = $0 }
            first(c, id: oldID)
            checks["old_first_does_not_resume_pending_launch"] = result == nil && c.sent.isEmpty
            launch(c, id: candidate, phase: "accepted")
            launch(c, id: candidate, phase: "launched")
            checks["launched_is_not_ack"] = result == nil && c.sent.isEmpty
            first(c, id: candidate)
            checks["pending_launch_resumes_once_without_reload"] = c.launches.isEmpty && c.sent.count == 1 && result == nil
            ack(c, 1, "unavailable")
            checks["retry_unavailable_fails_without_loop"] = result == .failed("Scene runtime cannot accept this texture update")
                && c.launches.isEmpty
        }
        do {
            let c = client(); let oldID = c.activeRequestID!; let candidate = UUID()
            var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.reloadUserTextureUpdate(update(1)) { result = $0 }
            checks["fallback_requires_key_ready"] = c.launches.last?.requiredUserTextureKeys == ["cover"]
            first(c, id: oldID)
            launch(c, id: candidate, phase: "accepted")
            launch(c, id: candidate, phase: "launched")
            checks["fallback_launch_keeps_old_replay_until_first"] = result == nil && c.activeIntent == intent()
            first(c, id: oldID)
            checks["fallback_ignores_old_request_first"] = result == nil
            first(c, id: candidate)
            checks["fallback_first_commits_verified_candidate"] = result == .applied
                && c.activeIntent?.userPropertyTextures["cover"]?.url.path == "/new.png"
                && c.activeIntent?.requiredUserTextureKeys.isEmpty == true
                && c.sent.isEmpty
        }
        do {
            let c = client(); let candidate = UUID(); var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.reloadUserTextureUpdate(update(1)) { result = $0 }
            launch(c, id: candidate, phase: "accepted")
            launch(c, id: candidate, phase: "launched")
            c.finishPendingTextureUpdates(.failed("death"))
            checks["fallback_death_restores_old_replay"] = result == .failed("death") && c.activeIntent == intent()
        }
        do {
            let c = client(); let firstCandidate = UUID(); let latestCandidate = UUID()
            var results: [String: ScenePlaybackTextureUpdateOutcome] = [:]
            _ = c.reloadUserTextureUpdate(update(1)) { results["old"] = $0 }
            launch(c, id: firstCandidate, phase: "accepted")
            _ = c.reloadUserTextureUpdate(update(2, key: "background")) { results["other"] = $0 }
            var needsFallback: ScenePlaybackTextureUpdateOutcome?
            _ = c.applyUserTextureUpdate(update(3, reset: true)) { needsFallback = $0 }
            checks["new_selection_routes_superseding_fallback"] = needsFallback == .unavailable
            _ = c.reloadUserTextureUpdate(update(3, reset: true)) { results["latest"] = $0 }
            checks["same_key_fallback_replaces_candidate"] = c.launches.count == 2
                && c.launches.last?.userPropertyTextures["cover"] == nil
                && results["old"] == .superseded
            launch(c, id: latestCandidate, phase: "accepted")
            launch(c, id: latestCandidate, phase: "launched")
            checks["fallback_with_other_key_keeps_accepted_replay"] = c.activeIntent == intent()
            first(c, id: firstCandidate)
            checks["superseded_candidate_first_does_not_ack"] = results["latest"] == nil && results["other"] == nil
            first(c, id: latestCandidate)
            checks["different_key_waiter_survives_fallback_replacement"] = results["latest"] == .applied
                && results["other"] == nil && c.sent.count == 1
            ack(c, 2)
            checks["retargeted_other_key_commits"] = results["other"] == .applied
                && c.activeIntent?.userPropertyTextures["background"] != nil
                && c.activeIntent?.userPropertyTextures["cover"] == nil
        }
        do {
            let c = client(); let firstCandidate = UUID(); let failedCandidate = UUID()
            var old: ScenePlaybackTextureUpdateOutcome?; var latest: ScenePlaybackTextureUpdateOutcome?
            _ = c.reloadUserTextureUpdate(update(1)) { old = $0 }
            launch(c, id: firstCandidate, phase: "accepted")
            _ = c.reloadUserTextureUpdate(update(2)) { latest = $0 }
            launch(c, id: failedCandidate, phase: "accepted")
            launch(c, id: failedCandidate, phase: "failed")
            checks["superseding_fallback_failure_keeps_last_accepted"] = old == .superseded
                && latest == .failed("own") && c.activeIntent == intent()
        }
        for diesBeforeFirst in [false, true] {
            let c = client(); let candidate = UUID(); var result: ScenePlaybackTextureUpdateOutcome?
            _ = c.reloadUserTextureUpdate(update(1)) { result = $0 }
            launch(c, id: candidate, phase: "accepted")
            launch(c, id: candidate, phase: "launched")
            _ = c.applyUserTextureUpdate(update(2, key: "background")) { _ in }
            ack(c, 2)
            _ = c.applyPropertyValues(["rate": .number(7)], revision: 3, recordID: "own")
            c.handlePropertyUpdateResult(["revision": 3, "recordID": "own", "accepted": true])
            if diesBeforeFirst { c.finishPendingTextureUpdates(.failed("death")) }
            else { first(c, id: candidate) }
            let suffix = diesBeforeFirst ? "death" : "first"
            checks["fallback_window_other_texture_preserved_" + suffix] =
                c.activeIntent?.userPropertyTextures["background"]?.url.path == "/new.png"
            checks["fallback_window_scalar_preserved_" + suffix] =
                c.activeIntent?.propertyOverrides["rate"] == .number(7)
            checks["fallback_window_own_key_" + suffix] = result == (diesBeforeFirst ? .failed("death") : .applied)
                && c.activeIntent?.userPropertyTextures["cover"]?.url.path == (diesBeforeFirst ? "/old.png" : "/new.png")
        }
        do {
            func decode(_ payload: [String: Any]) -> Result<SceneDaemonCommand, SceneDaemonProtocolFailure> {
                SceneDaemonProtocol.decodeCommand(try! JSONSerialization.data(withJSONObject: payload))
            }
            let base: [String: Any] = ["v": 1, "cmd": "setUserTextures", "references": [:],
                "resetKeys": ["cover"], "values": ["cover": ""], "revision": 1, "recordID": "own"]
            if case .success(.setUserTextures(let u)) = decode(base) { checks["protocol_reset"] = u.isValid }
            else { checks["protocol_reset"] = false }
            var invalids = [[String: Any]]()
            for revision: Any in [true, -1, 0, 1.5] { var p = base; p["revision"] = revision; invalids.append(p) }
            var multiple = base; multiple["resetKeys"] = ["cover", "background"]; multiple["values"] = ["cover": "", "background": ""]; invalids.append(multiple)
            var overlap = base; overlap["references"] = ["cover": ["path": "/own.png"]]; invalids.append(overlap)
            var number = base; number["values"] = ["cover": 1]; invalids.append(number)
            checks["protocol_rejects_invalid_atomic_request"] = invalids.allSatisfy {
                if case .failure = decode($0) { return true }; return false
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks), as: UTF8.self))
    }
}
