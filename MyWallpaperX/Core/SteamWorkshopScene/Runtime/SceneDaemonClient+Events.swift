import CoreFoundation
import Foundation

@MainActor
extension SceneDaemonClient {
    func consumeOutput(_ data: Data, generation: UInt64) {
        guard generation == sessionGeneration else { return }
        for frame in outputFrames.append(data) {
            guard let payload = try? JSONSerialization.jsonObject(with: frame)
                    as? [String: Any],
                  Self.integer(payload["v"]) == SceneDaemonProtocol.version else {
                publishFailure(
                    code: "malformed-event",
                    message: "Scene daemon emitted an invalid v1 event"
                )
                continue
            }
            if payload["role"] as? String == "scene-daemon" {
                handshakeWorkItem?.cancel()
                handshakeWorkItem = nil
                endpointReady = true
                replayPendingIntent()
                continue
            }
            guard let event = payload["event"] as? String else { continue }
            switch event {
            case "launchStateChanged": handleLaunchState(payload)
            case "firstFramePresented": handleFirstFrame(payload)
            case "frameStats": handleFrameStats(payload)
            case "propertyUpdateResult": handlePropertyUpdateResult(payload)
            case "error":
                publishFailure(
                    code: payload["code"] as? String ?? "daemon-error",
                    message: payload["message"] as? String
                        ?? "Unknown Scene daemon error"
                )
            case "exited": break
            default:
                publishFailure(
                    code: "unsupported-event",
                    message: "Unsupported Scene daemon event: \(event)"
                )
            }
        }
    }

    private func handleLaunchState(_ payload: [String: Any]) {
        guard let rawPhase = payload["phase"] as? String,
              let phase = SceneWallpaperLaunchState.Phase(rawValue: rawPhase),
              let rawRequestID = payload["requestID"] as? String,
              let requestID = UUID(uuidString: rawRequestID),
              let message = payload["message"] as? String else {
            publishFailure(code: "malformed-event", message: "Invalid launch state")
            return
        }
        let recordID = payload["recordID"] as? String
        if phase == .accepted {
            guard pendingIntent?.recordID == recordID else { return }
            pendingRequestID = requestID
        } else {
            guard pendingRequestID == requestID else { return }
        }

        let state = SceneWallpaperLaunchState(
            requestID: requestID,
            recordID: recordID,
            phase: phase,
            message: message
        )
        launchState = state
        if phase == .launched {
            activeIntent = pendingIntent
            activeRecordID = pendingIntent?.recordID
            activeRequestID = requestID
            pendingIntent = nil
            pendingRequestID = nil
        } else if phase == .cancelled || phase == .failed {
            pendingIntent = nil
            pendingRequestID = nil
        }
        NotificationCenter.default.post(
            name: .sceneWallpaperLaunchStateDidChange,
            object: state
        )
    }

    private func handleFirstFrame(_ payload: [String: Any]) {
        guard let rawRequestID = payload["requestID"] as? String,
              let requestID = UUID(uuidString: rawRequestID),
              requestID == activeRequestID,
              let uptimeMs = Self.double(payload["uptimeMs"]),
              uptimeMs >= 0 else { return }
        restartBackoff.reset()
        let presentation = SceneFramePresentation(
            requestID: requestID,
            recordID: payload["recordID"] as? String,
            uptimeMicros: UInt64(uptimeMs * 1_000)
        )
        NotificationCenter.default.post(
            name: .sceneWallpaperFirstFrameDidPresent,
            object: presentation
        )
    }

    private func handleFrameStats(_ payload: [String: Any]) {
        guard let rendered = Self.unsignedInteger(payload["rendered"]),
              let busy = Self.unsignedInteger(payload["busy"]),
              let dropped = Self.unsignedInteger(payload["dropped"]),
              let drawCalls = Self.unsignedInteger(payload["drawCalls"]) else {
            return
        }
        let stats = SceneDaemonFrameStats(
            rendered: rendered,
            busy: busy,
            dropped: dropped,
            drawCalls: drawCalls,
            cpuFrameMs: Self.double(payload["cpuFrameMs"])
        )
        latestFrameStats = stats
        NotificationCenter.default.post(
            name: .sceneDaemonFrameStatsDidChange,
            object: stats
        )
    }

    private func handlePropertyUpdateResult(_ payload: [String: Any]) {
        guard let revision = Self.unsignedInteger(payload["revision"]),
              let recordID = payload["recordID"] as? String,
              let accepted = payload["accepted"] as? Bool,
              pendingPropertyRevisions.removeValue(forKey: revision)
                == recordID else { return }
        guard !accepted,
              let request = activeIntent,
              request.recordID == recordID else { return }
        requestLaunch(request)
    }

    func handleTermination(status: Int32, generation: UInt64) {
        if let retiring = retiringTransports.removeValue(forKey: generation) {
            retiring.closeIO()
        }
        if expectedTerminationGenerations.remove(generation) != nil {
            finishShutdownIfPossible()
            return
        }
        guard generation == sessionGeneration else { return }
        handshakeWorkItem?.cancel()
        handshakeWorkItem = nil
        transport?.closeIO()
        transport = nil
        endpointReady = false
        latestFrameStats = nil

        let recoveryIntent = pendingIntent ?? activeIntent
        activeIntent = nil
        activeRecordID = nil
        activeRequestID = nil
        pendingRequestID = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        guard let recoveryIntent else { return }
        pendingIntent = recoveryIntent
        scheduleRestart(reason: "daemon-exited-\(status)")
    }

    func scheduleRestart(reason: String) {
        guard pendingIntent != nil, restartWorkItem == nil else { return }
        guard restartBackoff.consecutiveFailureCount < maximumRestartAttempts else {
            let requestID = pendingRequestID ?? UUID()
            let recordID = pendingIntent?.recordID
            let state = SceneWallpaperLaunchState(
                requestID: requestID,
                recordID: recordID,
                phase: .failed,
                message: "Scene daemon 连续启动失败，已停止自动重试"
            )
            launchState = state
            pendingIntent = nil
            pendingRequestID = nil
            NotificationCenter.default.post(
                name: .sceneWallpaperLaunchStateDidChange,
                object: state
            )
            publishFailure(code: "restart-exhausted", message: reason)
            return
        }
        let delay = restartBackoff.nextDelay()
        publishFailure(code: "daemon-disconnected", message: reason)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWorkItem = nil
            guard self.pendingIntent != nil else { return }
            _ = self.ensureSession()
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func publishFailure(code: String, message: String) {
        let failure = SceneDaemonClientFailure(
            code: code,
            message: message,
            recordID: pendingIntent?.recordID ?? activeIntent?.recordID
        )
        NotificationCenter.default.post(
            name: .sceneDaemonClientDidFail,
            object: failure
        )
    }

    func finishShutdownIfPossible() {
        guard transport == nil, retiringTransports.isEmpty,
              !shutdownCompletions.isEmpty else { return }
        let completions = shutdownCompletions
        shutdownCompletions.removeAll(keepingCapacity: true)
        RunLoop.main.perform(inModes: [.common]) {
            completions.forEach { $0() }
        }
    }

    private static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.intValue
        return NSNumber(value: value) == number ? value : nil
    }

    private static func unsignedInteger(_ raw: Any?) -> UInt64? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.uint64Value
        return NSNumber(value: value) == number ? value : nil
    }

    private static func double(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}
