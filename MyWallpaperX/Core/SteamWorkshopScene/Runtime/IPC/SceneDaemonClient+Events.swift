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
                    message: "Scene daemon emitted an invalid protocol event"
                )
                continue
            }
#if DEBUG
            debugStartupWireObserver?(generation, debugProcessIdentifier,
                UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000), payload)
#endif
            if payload["role"] as? String == "scene-daemon" {
                handshakeWorkItem?.cancel()
                handshakeWorkItem = nil
                sourceSchemaVersion = Self.integer(payload["sourceSchemaVersion"])
                requestRetirementSchemaVersion = nil
                if let capability = payload["requestRetirementSchemaVersion"] as? NSNumber,
                   CFGetTypeID(capability) != CFBooleanGetTypeID(),
                   !["f", "d"].contains(String(cString: capability.objCType)),
                   Self.unsignedInteger(capability) == 1 {
                    requestRetirementSchemaVersion = 1
                }
                endpointReady = true
#if DEBUG
                if debugStartupPrefixObserver != nil {
                    observeDebugStartupPrefix(.helloObserved,
                        childStartupUptimes: Self.debugStartupUptimes(payload["debugStartupPrefixUptimes"]))
                }
#endif
                replayPendingIntent()
                continue
            }
            guard let event = payload["event"] as? String else { continue }
            switch event {
            case "candidatePrepared": handleCandidatePrepared(payload)
            case "switchControlResult": handleSwitchControlResult(payload, generation: generation)
            case "launchResourcesReleased":
                if SceneDaemonProtocol.boolean(payload["resourcesRetired"]) == true,
                   let raw = payload["requestID"] as? String, let requestID = UUID(uuidString: raw) {
                    requestResourceLifetimes.removeValue(forKey: requestID)
                }
            case "launchStateChanged": handleLaunchState(payload)
            case "firstFramePresented": handleFirstFrame(payload)
            case "frameStats": handleFrameStats(payload)
            case "propertyUpdateResult": handlePropertyUpdateResult(payload)
            case "textureUpdateResult": handleTextureUpdateResult(payload)
            case "shortcutUpdateResult": handleShortcutUpdateResult(payload)
            case "systemMediaDemandChanged":
                handleSystemMediaDemand(payload, generation: generation)
            case "systemMediaAcknowledged":
                handleSystemMediaAcknowledgement(payload, generation: generation)
            case "systemMediaReplayRequested":
                handleSystemMediaReplayRequest(payload, generation: generation)
            case "audioSpectrumDemandChanged":
                handleAudioSpectrumDemand(payload, generation: generation)
            case "audioSpectrumPublished":
                handleAudioSpectrumPublication(payload, generation: generation)
            case "frameCaptured": handleFrameCaptured(payload)
            case "frameCaptureFailed": handleFrameCaptureFailure(payload)
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

    private func handleCandidatePrepared(_ payload: [String: Any]) {
        guard let raw = payload["requestID"] as? String,
              let requestID = UUID(uuidString: raw),
              requestID == pendingRequestID, pendingIntent != nil else { return }
        if reportPreparedSwitch(requestID: requestID) { return }
#if DEBUG
        guard switchPrepared == nil else { return }
        send(["v": SceneDaemonProtocol.version, "cmd": "commitCandidate",
              "requestID": requestID.uuidString])
#endif
    }

    private func handleFrameCaptured(_ payload: [String: Any]) {
        guard let requestID = payload["requestID"] as? String,
              let path = payload["path"] as? String else {
            return
        }
        pendingFrameCaptureCompletions
            .removeValue(forKey: requestID)?(URL(fileURLWithPath: path))
    }

    private func handleFrameCaptureFailure(_ payload: [String: Any]) {
        guard let requestID = payload["requestID"] as? String else {
            return
        }
        pendingFrameCaptureCompletions.removeValue(forKey: requestID)?(nil)
    }

    func handleLaunchState(_ payload: [String: Any]) {
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
            guard pendingRequestID == requestID,
                  let pendingIntent, pendingIntent.recordID == recordID else { return }
            bindDeferredTextureUpdates(recordID: recordID, requestID: requestID)
        } else {
            guard pendingRequestID == requestID,
                  let pendingIntent, pendingIntent.recordID == recordID else { return }
        }

        let reachability: ScenePreparedCallbackPropertyReachability?
        if phase == .launched, let raw = payload["callbackPropertyReachability"],
           JSONSerialization.isValidJSONObject(raw),
           let data = try? JSONSerialization.data(withJSONObject: raw),
           let decoded = try? JSONDecoder().decode(ScenePreparedCallbackPropertyReachability.self, from: data),
           decoded.scriptGeneration > 0,
           decoded.source.rootPath == pendingIntent?.rootURL.resolvingSymlinksInPath().standardizedFileURL.path {
            reachability = decoded
        } else { reachability = nil }

        let state = SceneWallpaperLaunchState(
            requestID: requestID,
            recordID: recordID,
            phase: phase,
            message: message,
            callbackPropertyReachability: reachability
        )
        launchState = state
        if phase == .launched {
            // The previous Scene remains rollback-capable in the daemon until
            // this exact request's real presentation is accepted below.
            pendingPresentationRequestID = requestID
            pendingPresentationReachability = reachability
        } else if phase == .cancelled || phase == .failed {
            let ticket = pendingSwitchTicket
            pendingIntent = nil
            pendingResourceLifetime = nil
            pendingRequestID = nil
            pendingPresentationRequestID = nil
            pendingPresentationReachability = nil
            pendingSwitchTicket = nil
            pendingSwitchExecution = nil
            finishTextureReload(recordID: recordID,
                outcome: phase == .cancelled ? .superseded : .failed(message))
            if let ticket {
                if activeIntent == nil, committedSwitchRecovery?.ticket == ticket {
                    committedSwitchRecovery = nil
                    switchLost?(ticket, message)
                } else { switchFailed?(ticket, message) }
            }
            resumeCommittedSwitchRecoveryIfPossible(after: ticket)
        }
        NotificationCenter.default.post(
            name: .sceneWallpaperLaunchStateDidChange,
            object: state
        )
    }

    private func handleFirstFrame(_ payload: [String: Any]) {
        guard let rawRequestID = payload["requestID"] as? String,
              let requestID = UUID(uuidString: rawRequestID),
              let uptimeMs = Self.double(payload["uptimeMs"]),
              uptimeMs >= 0 else { return }
        if requestID == pendingPresentationRequestID, requestID == pendingRequestID, pendingIntent != nil {
            if let execution = pendingSwitchExecution, let visible = switchVisible {
                guard execution.generation == sessionGeneration,
                      execution.requestID == requestID, execution.activated,
                      !execution.presented else { return }
                execution.presented = true
                visible(execution.ticket, execution.id)
            } else {
#if DEBUG
                guard switchPrepared == nil else { return }
                commitPresentedScene(requestID: requestID)
#else
                return
#endif
            }
        } else if requestID != activeRequestID { return }
        if requestID == activeRequestID {
            resumeDeferredTextureUpdates(recordID: activeIntent?.recordID, requestID: requestID)
        }
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
        if (idleTransport != nil || hasRequestRetirementControl), demand.requiresSpectrum { return }
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
        // Control completions run after this termination has invalidated every
        // execution below; a synchronous product callback may start a new child.
        defer { finishSwitchControlsAfterExit(generation: generation) }
        if let retiring = retiringTransports.removeValue(forKey: generation) {
            retiring.closeIO()
            retiringResourceLifetimes.removeValue(forKey: generation)
        }
        if expectedTerminationGenerations.remove(generation) != nil {
            revokeAudioSpectrumDemand(generation: generation)
            revokeSystemMediaDemand(generation: generation)
            finishShutdownIfPossible()
            return
        }
        guard generation == sessionGeneration else { return }
        discardIdleTransport()
        handshakeWorkItem?.cancel()
        handshakeWorkItem = nil
        transport?.closeIO()
        transport = nil
        endpointReady = false
        sourceSchemaVersion = nil
        requestRetirementSchemaVersion = nil
        latestFrameStats = nil
        rememberCommittedSwitchForRecovery()
        adoptQueuedSwitchPreparationForRecovery()
        let recoveryUsesPendingIntent = pendingIntent != nil
        let recoveryIntent = pendingIntent ?? activeIntent
        let recoveryTicket = recoveryUsesPendingIntent ? pendingSwitchTicket : activeSwitchTicket
        let recoveryResourceLifetime = recoveryUsesPendingIntent
            ? pendingResourceLifetime
            : activeResourceLifetime
        requestResourceLifetimes.removeAll()
        activeIntent = nil
        activeResourceLifetime = nil
        activeRecordID = nil
        activeRequestID = nil
        activeSwitchExecution = nil
        pendingSwitchExecution = nil
        pendingRequestID = nil
        pendingPresentationRequestID = nil
        pendingPresentationReachability = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        pendingIntent = recoveryIntent
        pendingSwitchTicket = recoveryTicket
        pendingResourceLifetime = recoveryResourceLifetime
        activeCallbackPropertyFacts = nil
        if recoveryIntent != nil { scheduleRestart(reason: "daemon-exited-\(status)") }
        // Notify external completions only after recovery facts are coherent;
        // they may synchronously request a newer product selection.
        failPendingFrameCaptures()
        finishPendingShortcutUpdates(.failed("Scene daemon disconnected"))
        finishPendingTextureUpdates(.failed("Scene daemon disconnected"))
        revokeAudioSpectrumDemand(generation: generation)
        revokeSystemMediaDemand(generation: generation)
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
            let ticket = pendingSwitchTicket
            pendingIntent = nil
            pendingResourceLifetime = nil
            pendingRequestID = nil
            pendingSwitchTicket = nil
            pendingSwitchExecution = nil
            NotificationCenter.default.post(
                name: .sceneWallpaperLaunchStateDidChange,
                object: state
            )
            publishFailure(code: "restart-exhausted", message: reason)
            if let ticket {
                if committedSwitchRecovery?.ticket == ticket {
                    committedSwitchRecovery = nil
                    switchLost?(ticket, state.message)
                } else { switchFailed?(ticket, state.message) }
            }
            resumeCommittedSwitchRecoveryIfPossible(after: ticket)
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
        // A later playback request must not keep an earlier shutdown waiting.
        let generations = Set(retiringTransports.keys)
        let completions = shutdownCompletions.filter { $0.generations.isDisjoint(with: generations) }
        shutdownCompletions.removeAll { $0.generations.isDisjoint(with: generations) }
        guard !completions.isEmpty else { return }
        RunLoop.main.perform(inModes: [.common]) {
            completions.forEach { $0.completion() }
        }
    }

#if DEBUG
    /// Diagnostics only: malformed telemetry never changes hello admission.
    static func debugStartupUptimes(_ raw: Any?) -> [String: UInt64]? {
        let keys: Set<String> = ["schemaVersion", "pid", "entryObserved", "appKitBegin",
            "appKitReturned", "runtimeBegin", "runtimeReturned", "helloSnapshotCaptured"]
        guard let values = raw as? [String: Any], Set(values.keys) == keys else { return nil }
        var result: [String: UInt64] = [:]
        for (key, rawValue) in values {
            guard let number = rawValue as? NSNumber,
                  !["f", "d"].contains(String(cString: number.objCType)),
                  let value = unsignedInteger(number) else { return nil }
            result[key] = value
        }
        return result
    }

#endif
    private static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.intValue
        return NSNumber(value: value) == number ? value : nil
    }

    static func unsignedInteger(_ raw: Any?) -> UInt64? {
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
