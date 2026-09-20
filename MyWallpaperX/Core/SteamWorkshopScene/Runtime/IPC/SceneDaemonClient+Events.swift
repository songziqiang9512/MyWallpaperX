import CoreFoundation
import Foundation

@MainActor
extension SceneDaemonClient {
    func consumeOutput(_ data: Data, generation: UInt64) {
        guard activeEventAdmission.accepts(generation: generation) else {
            return
        }
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
            case "audioSpectrumDemandChanged":
                handleAudioSpectrumDemand(payload, generation: generation)
            case "audioSpectrumPublished":
                handleAudioSpectrumPublication(payload, generation: generation)
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
            activeResourceLifetime = pendingResourceLifetime
            activeRecordID = pendingIntent?.recordID
            activeRequestID = requestID
            pendingIntent = nil
            pendingResourceLifetime = nil
            pendingRequestID = nil
        } else if phase == .cancelled || phase == .failed {
            pendingIntent = nil
            pendingResourceLifetime = nil
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
              let drawCalls = Self.unsignedInteger(payload["drawCalls"]),
              let pipelineStateBinds = Self.unsignedInteger(
                  payload["pipelineStateBinds"]
              ),
              let geometryDrawCalls = Self.unsignedInteger(
                  payload["geometryDrawCalls"]
              ),
              let fallbackBranches = Self.unsignedInteger(
                  payload["fallbackBranches"]
              ),
              let gpuAllocatedBytes = Self.unsignedInteger(
                  payload["gpuAllocatedBytes"]
              ),
              let renderTargetPoolBytes = Self.unsignedInteger(
                  payload["renderTargetPoolBytes"]
              ) else {
            return
        }
        let stats = SceneDaemonFrameStats(
            rendered: rendered,
            busy: busy,
            dropped: dropped,
            drawCalls: drawCalls,
            pipelineStateBinds: pipelineStateBinds,
            geometryDrawCalls: geometryDrawCalls,
            fallbackBranches: fallbackBranches,
            gpuAllocatedBytes: gpuAllocatedBytes,
            renderTargetPoolBytes: renderTargetPoolBytes,
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

    private func handleAudioSpectrumDemand(
        _ payload: [String: Any],
        generation: UInt64
    ) {
        guard endpointReady,
              activeEventAdmission.accepts(generation: generation),
              let requiresSpectrum = payload["requiresSpectrum"] as? Bool,
              let includesDaemonProcessOutput = payload[
                "includesDaemonProcessOutput"
              ] as? Bool,
              let scopeEpoch = Self.unsignedInteger(payload["scopeEpoch"]),
              (!requiresSpectrum || scopeEpoch > 0),
              requiresSpectrum || !includesDaemonProcessOutput else {
            publishFailure(
                code: "malformed-event",
                message: "Invalid Scene audio spectrum demand"
            )
            return
        }
        let demand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: requiresSpectrum,
            includesCurrentProcessOutput: includesDaemonProcessOutput,
            scopeEpoch: scopeEpoch
        )
        guard audioSpectrumDemandGeneration != generation
                || audioSpectrumDemand != demand else { return }
        audioSpectrumDemand = demand
        audioSpectrumDemandGeneration = generation
        WallpaperEngine.shared.setSceneDaemonAudioSpectrumDemand(
            demand,
            generation: generation
        )
        NotificationCenter.default.post(
            name: .sceneDaemonAudioSpectrumDemandDidChange,
            object: demand
        )
    }

    private func handleAudioSpectrumPublication(
        _ payload: [String: Any],
        generation: UInt64
    ) {
        guard endpointReady,
              activeEventAdmission.accepts(generation: generation),
              audioSpectrumDemandGeneration == generation,
              let scopeEpoch = Self.unsignedInteger(payload["scopeEpoch"]),
              let includesDaemonProcessOutput = payload[
                "includesDaemonProcessOutput"
              ] as? Bool,
              let peakValue = Self.double(payload["peak"]),
              peakValue.isFinite, peakValue > 0,
              scopeEpoch == audioSpectrumDemand.scopeEpoch,
              includesDaemonProcessOutput
                == audioSpectrumDemand.includesCurrentProcessOutput else {
            return
        }
        NotificationCenter.default.post(
            name: .sceneDaemonAudioSpectrumDidPublish,
            object: SceneDaemonAudioSpectrumPublication(
                scopeEpoch: scopeEpoch,
                includesDaemonProcessOutput: includesDaemonProcessOutput,
                peak: Float(peakValue)
            )
        )
    }

    func revokeAudioSpectrumDemand(generation: UInt64) {
        guard audioSpectrumDemandGeneration == generation else { return }
        let hadDemand = audioSpectrumDemand.requiresSpectrum
        audioSpectrumDemand = .none
        audioSpectrumDemandGeneration = nil
        guard hadDemand else { return }
        WallpaperEngine.shared.setSceneDaemonAudioSpectrumDemand(
            .none,
            generation: generation
        )
        NotificationCenter.default.post(
            name: .sceneDaemonAudioSpectrumDemandDidChange,
            object: SceneAudioSpectrumCaptureDemand.none
        )
    }

    func handleTermination(status: Int32, generation: UInt64) {
        if let retiring = retiringTransports.removeValue(forKey: generation) {
            retiring.closeIO()
            retiringResourceLifetimes.removeValue(forKey: generation)
        }
        if expectedTerminationGenerations.remove(generation) != nil {
            revokeAudioSpectrumDemand(generation: generation)
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
        revokeAudioSpectrumDemand(generation: generation)

        let recoveryUsesPendingIntent = pendingIntent != nil
        let recoveryIntent = pendingIntent ?? activeIntent
        let recoveryResourceLifetime = recoveryUsesPendingIntent
            ? pendingResourceLifetime
            : activeResourceLifetime
        activeIntent = nil
        activeResourceLifetime = nil
        activeRecordID = nil
        activeRequestID = nil
        pendingRequestID = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        guard let recoveryIntent else { return }
        pendingIntent = recoveryIntent
        pendingResourceLifetime = recoveryResourceLifetime
        scheduleRestart(reason: "daemon-exited-\(status)")
    }

    private var activeEventAdmission: SceneDaemonEventAdmission {
        SceneDaemonEventAdmission(
            sessionGeneration: sessionGeneration,
            hasActiveTransport: transport != nil,
            generationIsRetiring: retiringTransports[sessionGeneration] != nil,
            terminationIsExpected: expectedTerminationGenerations.contains(
                sessionGeneration
            )
        )
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
            pendingResourceLifetime = nil
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
