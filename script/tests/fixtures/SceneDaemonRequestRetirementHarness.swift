import Foundation

// Production Runtime methods are inserted by the Python gate. Only their
// external Host/inbox/writer boundaries are scripted here; no AppKit/Metal/AV.
struct SceneAudioSpectrumCaptureDemand: Equatable {
    let requiresSpectrum: Bool
    let includesCurrentProcessOutput: Bool
    let scopeEpoch: UInt64
    static let none = Self(requiresSpectrum: false, includesCurrentProcessOutput: false, scopeEpoch: 0)
}
final class SceneAudioSpectrumInbox {
    static let shared = SceneAudioSpectrumInbox()
    var captureDemand = SceneAudioSpectrumCaptureDemand.none
}
enum SceneDaemonProtocol { static let version = 2 }
enum Command { case load, beginRetirement, publishAudioSpectrum(Int) }
struct Failure: Error { let code: String }
final class Commands {
    enum Entry { case droppable(Int), control(Result<Command, Failure>, Int) }
    var entries: [Entry] = []
    var takes = 0
    func takeNext() -> Entry? { takes += 1; return entries.isEmpty ? nil : entries.removeFirst() }
}
final class Host { var isEmptyForRequestRetirement = true }
final class Runtime {
    let commands = Commands()
    let host = Host()
    var isShuttingDown = false
    var pendingRequestRetirement: (requestID: UUID, operationID: UUID)?
    var currentRequestID: UUID?
    var audioDemand = SceneAudioSpectrumCaptureDemand.none
    var didReportNonSilentAudioPublication = true
    var events: [[String: Any]] = []
    var order: [String] = []
    var handledLoads = 0
    var shutdownCodes: [Int32] = []
    let requestID = UUID(), operationID = UUID()
    func emit(_ payload: [String: Any]) {
        events.append(payload)
        if payload["event"] as? String == "audioSpectrumDemandChanged" {
            order.append("audio:\(payload["requiresSpectrum"]!):\(payload["scopeEpoch"]!)")
        } else { order.append("ack:\(payload["requestRetired"]!)") }
    }
    func emitError(code: String, message: String) { order.append("error:" + code) }
    func shutdown(exitCode: Int32) { isShuttingDown = true; shutdownCodes.append(exitCode) }
    func handle(_ command: Command) {
        switch command {
        case .load: handledLoads += 1; order.append("load")
        case .beginRetirement: pendingRequestRetirement = (requestID, operationID)
        case .publishAudioSpectrum: order.append("frame")
        }
    }
    func begin() { pendingRequestRetirement = (requestID, operationID); currentRequestID = requestID }
    func drain() { drainPendingCommands() }
    func finish(accepted: Bool = true, known: Bool = true, succeeded: Bool = true,
                request: UUID? = nil, operation: UUID? = nil) {
        finishRequestRetirement(requestID: request ?? requestID, operationID: operation ?? operationID,
            accepted: accepted, knownRequest: known, succeeded: succeeded)
    }
    func publish(_ value: SceneAudioSpectrumCaptureDemand) { publishAudioSpectrumDemand(value) }

    // @PRODUCTION_METHODS@
}
@main enum Checks {
    static func main() throws {
        var checks: [String: Bool] = [:]
        let none = SceneAudioSpectrumCaptureDemand(requiresSpectrum: false,
            includesCurrentProcessOutput: false, scopeEpoch: 9)
        let oldPositive = SceneAudioSpectrumCaptureDemand(requiresSpectrum: true,
            includesCurrentProcessOutput: true, scopeEpoch: 8)
        SceneAudioSpectrumInbox.shared.captureDemand = none
        let pending = Runtime(); pending.begin(); pending.commands.entries = [.control(.success(.load), 1)]
        pending.drain()
        checks["strongPendingDoesNotTakeNextLoad"] = pending.commands.takes == 0 && pending.handledLoads == 0
        pending.audioDemand = oldPositive
        pending.finish()
        let ack = pending.events.last!
        checks["exactSuccessPublishesNoneBeforeAckThenDrainsOriginalInbox"] =
            pending.order == ["audio:false:9", "ack:true", "load"]
                && pending.pendingRequestRetirement == nil && pending.currentRequestID == nil
                && pending.handledLoads == 1 && pending.shutdownCodes.isEmpty
        checks["successAckRetainsExactWireIdentityAndWindowAcceptance"] =
            ack["requestID"] as? String == pending.requestID.uuidString
                && ack["operationID"] as? String == pending.operationID.uuidString
                && ack["accepted"] as? Bool == true && ack["requestRetired"] as? Bool == true
        let afterSuccess = pending.events.count
        pending.finish()
        checks["sameOperationCompletionIsIdempotent"] = pending.events.count == afterSuccess
            && pending.handledLoads == 1
        let midDrain = Runtime()
        midDrain.commands.entries = [.control(.success(.beginRetirement), 1), .control(.success(.load), 1)]
        midDrain.drain()
        checks["pendingBegunInsideOriginalDrainPausesBeforeFollowingLoad"] = midDrain.commands.takes == 1
            && midDrain.commands.entries.count == 1 && midDrain.handledLoads == 0
        let foreign = Runtime(); foreign.begin(); foreign.commands.entries = [.control(.success(.load), 1)]
        foreign.finish(request: UUID()); foreign.finish(operation: UUID())
        checks["wrongOldRequestOrOperationCannotFinishCurrentRetirement"] = foreign.events.isEmpty
            && foreign.pendingRequestRetirement?.operationID == foreign.operationID
            && foreign.commands.takes == 0 && foreign.shutdownCodes.isEmpty
        for reason in ["gpuFailed", "unknownRequest", "windowVisible", "hostOccupied", "audioStillDemanded"] {
            let rejected = Runtime(); rejected.begin()
            rejected.commands.entries = [.control(.success(.load), 1)]
            rejected.host.isEmptyForRequestRetirement = reason != "hostOccupied"
            SceneAudioSpectrumInbox.shared.captureDemand = reason == "audioStillDemanded" ? oldPositive : none
            rejected.finish(accepted: reason != "windowVisible", known: reason != "unknownRequest",
                            succeeded: reason != "gpuFailed")
            checks[reason + "CannotCertifyOrAdmitQueuedLoad"] = rejected.events.count == 1
                && rejected.events[0]["requestRetired"] as? Bool == false
                && rejected.handledLoads == 0 && rejected.commands.takes == 0
                && rejected.shutdownCodes == [70] && rejected.isShuttingDown
            if reason == "unknownRequest" {
                checks["unknownEmptyHostWithdrawalIsDistinctFromRetirement"] =
                    rejected.events[0]["accepted"] as? Bool == true
                        && rejected.host.isEmptyForRequestRetirement
            }
        }
        let scope = Runtime()
        let current = SceneAudioSpectrumCaptureDemand(requiresSpectrum: true,
            includesCurrentProcessOutput: true, scopeEpoch: 11)
        let otherPolicy = SceneAudioSpectrumCaptureDemand(requiresSpectrum: true,
            includesCurrentProcessOutput: false, scopeEpoch: 11)
        SceneAudioSpectrumInbox.shared.captureDemand = current
        scope.publish(oldPositive); scope.publish(otherPolicy)
        checks["delayedPositiveRequiresFullCurrentScopeAndProcessPolicy"] = scope.events.isEmpty
            && scope.audioDemand == .none
        scope.publish(current)
        SceneAudioSpectrumInbox.shared.captureDemand = none
        scope.publish(none); scope.publish(current)
        checks["latePositiveCannotReactivateAfterCurrentNone"] = scope.events.count == 2
            && scope.audioDemand == none && scope.events.last?["requiresSpectrum"] as? Bool == false
        SceneAudioSpectrumInbox.shared.captureDemand = current
        scope.publish(current); scope.publish(none)
        checks["lateNoneCannotRevokeNewScope"] = scope.events.count == 3 && scope.audioDemand == current
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
        precondition(checks.values.allSatisfy { $0 })
    }
}
