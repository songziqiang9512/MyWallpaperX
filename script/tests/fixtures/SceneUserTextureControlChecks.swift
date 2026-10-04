import CoreFoundation
import Foundation

// Only transport and unrelated notification storage are leaves. The test
// compiles the real Client texture extension and real launch/event handlers.
@MainActor final class SceneDaemonClient {
    struct Transport { var isRunning = true }
    var activeIntent: ScenePlaybackLoadRequest?
    var pendingIntent: ScenePlaybackLoadRequest?
    var activeResourceLifetime: Int?
    var pendingResourceLifetime: Int?
    var activeRecordID: String?
    var activeRequestID: UUID?
    var pendingRequestID: UUID?
    var endpointReady = true
    var transport: Transport? = .init()
    var sessionGeneration: UInt64 = 1
    var launchState: SceneWallpaperLaunchState?
    var pendingTextureUpdates: [UInt64: PendingTextureUpdate] = [:]
    var latestTextureRevisions: [String: UInt64] = [:]
    var lastPropertyRevision: UInt64 = 0
    var pendingPropertyRevisions: [UInt64: String] = [:]
    var sent: [[String: Any]] = []
    var launches: [ScenePlaybackLoadRequest] = []
    var restartBackoff = Backoff()
    struct Backoff { func reset() {} }

    func hasIntent(for recordID: String) -> Bool {
        activeIntent?.recordID == recordID || pendingIntent?.recordID == recordID
    }
    func send(_ payload: [String: Any]) { sent.append(payload) }
    func requestLaunch(_ request: ScenePlaybackLoadRequest) {
        finishPendingTextureUpdates(.superseded)
        latestTextureRevisions.removeAll()
        pendingIntent = request
        pendingRequestID = nil
        launches.append(request)
    }
    func publishFailure(code: String, message: String) { fatalError(message) }
}

struct SceneWallpaperLaunchState {
    enum Phase: String { case accepted, launched, cancelled, failed, stopped }
    let requestID: UUID
    let recordID: String?
    let phase: Phase
    let message: String
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
            client.handleLaunchState(["requestID": id.uuidString, "recordID": "own", "phase": phase, "message": "own"])
        }
        func first(_ client: SceneDaemonClient, id: UUID) {
            client.handleFirstFrame(["requestID": id.uuidString, "recordID": "own", "uptimeMs": 1])
        }
        var checks: [String: Bool] = [:]
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
