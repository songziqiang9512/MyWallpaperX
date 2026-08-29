import AppKit
import QuartzCore

private let sceneFrameInterval: TimeInterval = 1.0 / 60.0
private let sceneBusyFrameRetryInterval = max(
    0.001,
    sceneFrameInterval / 8.0
)

private enum SceneFrameDriverAttempt {
    case rendered
    case busy
    case inactive
}

extension SceneDesktopWallpaperHost {
#if DEBUG
    static let debugSceneTimeOverride: TimeInterval? = {
        guard usesDebugEvidenceWindow,
              let rawValue = ProcessInfo.processInfo.environment[
                "MYWALLPAPERX_SCENE_DEBUG_SCENE_TIME"
              ],
              let value = TimeInterval(rawValue),
              value.isFinite,
              value >= 0 else { return nil }
        return value
    }()

    static let debugWallDateOverride: Date? = {
        guard usesDebugEvidenceWindow,
              let rawValue = ProcessInfo.processInfo.environment[
                "MYWALLPAPERX_SCENE_DEBUG_WALL_DATE"
              ] else { return nil }
        return ISO8601DateFormatter().date(from: rawValue)
    }()
#endif

    func teardownSurfaces(
        clearContext: Bool,
        reason: SceneGraphExecutionResetReason
    ) {
#if DEBUG
        if Self.usesDebugEvidenceWindow, launchContext != nil {
            NSLog(
                "MWX DEBUG SCENE: phase=surface-teardown clearContext=%@ timer=%@ surfaces=%d",
                clearContext ? "true" : "false",
                frameTimer?.isValid == true ? "active" : "inactive",
                surfaces.count
            )
        }
#endif
        if clearContext {
            screenReconciliationWorkItem?.cancel()
            screenReconciliationWorkItem = nil
            screenTopology = []
            removePointerEventMonitors()
        }
        frameTimer?.invalidate()
        frameTimer = nil
        frameDriverDeadline = nil
        for surface in surfaces.values {
            surface.metalView.invalidateResolvedMaterialRuntime(reason: reason)
            surface.metalView.teardownParticlePlayback(reason: reason)
            surface.window.orderOut(nil)
            surface.window.close()
        }
        surfaces.removeAll()
#if DEBUG
        debugSurfaceReferenceFrames.removeAll(keepingCapacity: false)
#endif
        if clearContext {
            if let launchContext {
                teardownSceneScriptOwners(launchContext, reason: reason)
            }
            SceneAudioSpectrumInbox.shared.setDemand(false)
            sharedLayerAlphaRuntime = .init(program: .empty)
#if DEBUG
            debugDropDynamicValuesFrameIndex = nil
            debugDidDropDynamicValues = false
            debugDidLogDynamicValuesRecovery = false
#endif
            videoTextureSourceRegistry?.stop()
            videoTextureSourceRegistry = nil
            soundPlaybackRegistry?.stop()
            soundPlaybackRegistry = nil
            launchContext = nil
#if DEBUG
            debugPointerOverride = nil
#endif
        }
    }

    func teardownSceneScriptOwners(
        _ context: SceneDesktopWallpaperLaunchContext,
        reason: SceneGraphExecutionResetReason
    ) {
        let hostTime = CACurrentMediaTime()
#if DEBUG
        let wallDate = Self.debugWallDateOverride ?? Date()
#else
        let wallDate = Date()
#endif
        let frame = SceneScriptFrameInput(timing: .init(
            frameIndex: 0,
            hostTime: hostTime,
            sceneTime: sceneClock.currentSceneTime(hostTime: hostTime),
            rawFrameTime: 0,
            simulationFrameTime: 0,
            droppedFrameTime: 0,
            wallDate: wallDate
        ))
        let userPropertiesJSON = context.propertyVectorScriptProgram
            .userPropertiesJSON(effectiveValues: context.liveState.effectiveValues)
        let outcomes = context.sceneScriptScalarProgram.teardown(
            frame: frame, userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptStringProgram.teardown(
            frame: frame, userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptCursorProgram.teardown(
            frame: frame, userPropertiesJSON: userPropertiesJSON
        ) + context.propertyVectorScriptProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        )
        let destroyCallbacks = outcomes.filter(\.destroyCallbackInvoked).count
        let quiescent = outcomes.filter(\.snapshot.isQuiescent).count
        let failures = outcomes.compactMap(\.failure)
        NSLog(
            "MWX SceneScript VM: lifecycle=teardown reason=%@ owners=%d destroyCallbacks=%d quiescent=%d failures=%d timers=%d jobs=%d mutations=%d dynamicLayers=%d route=generic-only",
            String(describing: reason), outcomes.count, destroyCallbacks,
            quiescent, failures.count,
            outcomes.reduce(0) { $0 + $1.snapshot.activeTimerCount },
            outcomes.filter(\.snapshot.hasJobResidue).count,
            outcomes.reduce(0) { $0 + $1.snapshot.pendingLayerMutationCount },
            outcomes.reduce(0) { $0 + $1.snapshot.activeDynamicLayerCount }
        )
    }

    func startFrameDriver() {
        frameTimer?.invalidate()
        frameTimer = nil
        frameDriverDeadline = nil
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            NSLog(
                "MWX DEBUG SCENE: phase=frame-driver-start paused=%@",
                sceneClock.isPaused ? "true" : "false"
            )
        }
#endif
        guard !sceneClock.isPaused else { return }
        let initialDeadline = CACurrentMediaTime()
        let attempt = renderFrame()
        scheduleFrameDriver(
            after: attempt,
            scheduledDeadline: initialDeadline
        )
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            NSLog(
                "MWX DEBUG SCENE: phase=frame-driver-ready timer=%@",
                frameTimer?.isValid == true ? "active" : "inactive"
            )
        }
#endif
    }

    private func scheduleFrameDriver(
        after attempt: SceneFrameDriverAttempt,
        scheduledDeadline: CFTimeInterval
    ) {
        guard launchContext != nil, !sceneClock.isPaused else {
            frameTimer?.invalidate()
            frameTimer = nil
            frameDriverDeadline = nil
            return
        }
        let now = CACurrentMediaTime()
        let nextDeadline: CFTimeInterval
        switch attempt {
        case .rendered:
            var cadenceDeadline = scheduledDeadline + sceneFrameInterval
            while cadenceDeadline <= now {
                cadenceDeadline += sceneFrameInterval
            }
            nextDeadline = cadenceDeadline
        case .busy:
            // History-bearing graphs remain single-frame-in-flight. A short
            // retry prevents a slight overrun from losing a full 60 Hz slot.
            nextDeadline = now + sceneBusyFrameRetryInterval
        case .inactive:
            frameTimer?.invalidate()
            frameTimer = nil
            frameDriverDeadline = nil
            return
        }
        armFrameDriver(at: nextDeadline)
    }

    private func armFrameDriver(at deadline: CFTimeInterval) {
        frameTimer?.invalidate()
        frameDriverDeadline = deadline
        let delay = max(0.000_001, deadline - CACurrentMediaTime())
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.frameTimer = nil
            let attempt = self.renderFrame()
            self.scheduleFrameDriver(
                after: attempt,
                scheduledDeadline: deadline
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func renderFrame() -> SceneFrameDriverAttempt {
        guard let launchContext, !surfaces.isEmpty else { return .inactive }
        guard surfaces.values.allSatisfy({
            !$0.metalView.shouldDeferResolvedMaterialFrame
        }) else {
            return .busy
        }
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            SceneFramePerformanceTelemetry.debugEvidence.recordDriverCallback()
        }
#endif
        updateMouseLocations()
#if DEBUG
        let wallDate = Self.debugWallDateOverride ?? Date()
#else
        let wallDate = Date()
#endif
        let advancedTiming = sceneClock.advance(
            hostTime: CACurrentMediaTime(),
            wallDate: wallDate
        )
#if DEBUG
        let timing: SceneFrameTiming
        if let sceneTime = Self.debugSceneTimeOverride {
            timing = SceneFrameTiming(
                frameIndex: advancedTiming.frameIndex,
                hostTime: advancedTiming.hostTime,
                sceneTime: sceneTime,
                rawFrameTime: advancedTiming.rawFrameTime,
                simulationFrameTime: advancedTiming.simulationFrameTime,
                droppedFrameTime: advancedTiming.droppedFrameTime,
                wallDate: advancedTiming.wallDate
            )
        } else {
            timing = advancedTiming
        }
#else
        let timing = advancedTiming
#endif
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            SceneFramePerformanceTelemetry.debugEvidence.recordFrameDelta(
                raw: timing.rawFrameTime,
                dropped: timing.droppedFrameTime
            )
        }
#endif
        let definitions = SceneDynamicDefinitionMerger.merge(
            propertyDefinitions: launchContext.runtimeInput.propertyBindingProgram.definitions,
            timelineProgram: launchContext.timelineProgram,
            textScriptProgram: launchContext.textScriptProgram,
            additionalDefinitions: launchContext.sharedLayerAlphaProgram.definitions
                + launchContext.propertyVectorScriptProgram.definitions
                + launchContext.sceneScriptFallbackDefinitions
                + launchContext.sceneScriptScalarProgram.definitions
                + launchContext.sceneScriptStringProgram.definitions
                + launchContext.sceneScriptDynamicLayerRuntime
                    .authoredTransformDefinitions
        )
        let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()
        let timelineValues = launchContext.timelinePlaybackRuntime.values(
            sceneTime: timing.sceneTime
        )
        let mediaInput = SceneMediaThumbnailInbox.shared.latest()
        let sceneScriptMediaThumbnailEvent =
            SceneScriptMediaThumbnailEventInput(snapshot: mediaInput)
        let sceneScriptMediaPlaybackEvent =
            SceneScriptMediaPlaybackEventInput(snapshot: mediaInput)
        let sceneScriptMediaPropertiesEvent =
            SceneScriptMediaPropertiesEventInput(snapshot: mediaInput)
        let mediaProperties = mediaInput.properties.map {
            SceneTextMediaPropertiesSnapshot(
                title: $0.title,
                artist: $0.artist,
                generation: mediaInput.propertiesGeneration
            )
        } ?? .empty
        let textScriptValues = SceneTextScriptRuntime.values(
            program: launchContext.textScriptProgram,
            wallDate: timing.wallDate,
            mediaProperties: mediaProperties
        )
        let sharedLayerAlphaValues = sharedLayerAlphaRuntime.values(
            effectivePropertyValues: launchContext.liveState.effectiveValues,
            frameTime: timing.simulationFrameTime
        )
        let layerMutationSnapshot = launchContext.sceneScriptDynamicLayerRuntime
            .snapshot()
        var commonSceneScriptValues = textScriptValues.merging(
            sharedLayerAlphaValues,
            uniquingKeysWith: { existing, _ in existing }
        ).merging(
            layerMutationSnapshot.authoredLayerValues,
            uniquingKeysWith: { _, committedMutation in committedMutation }
        )
        let boundedSceneScriptValues = commonSceneScriptValues
        let preliminaryForSceneScript = SceneDynamicSnapshotResolver().resolve(
            frameIndex: timing.frameIndex,
            generation: 0,
            definitions: definitions,
            userValues: launchContext.liveState.userValues,
            timelineValues: timelineValues,
            sceneScriptValues: boundedSceneScriptValues
        ).snapshot
        let userPropertiesJSON = launchContext.propertyVectorScriptProgram
            .userPropertiesJSON(effectiveValues: launchContext.liveState.effectiveValues)
        let sceneScriptSurfaceInput = surfaces.count == 1
            ? surfaces.values.first?.metalView.sceneScriptSurfaceInput(
                timing: timing,
                dynamicValues: preliminaryForSceneScript
            )
            : nil
        let sceneScriptFrame = SceneScriptFrameInput(
            timing: timing,
            surface: sceneScriptSurfaceInput
        )
        let sceneScriptLayerSnapshotFailure: SceneScriptScalarRuntimeFailure?
        do {
            try launchContext.propertyVectorScriptProgram.domain?
                .publishLayerSnapshot(
                    preliminaryForSceneScript,
                    descriptor: launchContext.runtimeInput.renderDescriptor
                )
            sceneScriptLayerSnapshotFailure = nil
        } catch let failure as SceneScriptScalarRuntimeFailure {
            sceneScriptLayerSnapshotFailure = failure
        } catch {
            sceneScriptLayerSnapshotFailure = .invalidArgument(
                String(describing: error)
            )
        }
        if let failure = sceneScriptLayerSnapshotFailure {
            NSLog(
                "MWX SceneScript VM: family=shared-domain frame=%llu failure=%@ code=%@ fallback=previous-current",
                timing.frameIndex, String(describing: failure), failure.code
            )
        }
        let cursorBatch: SceneScriptCursorFrameBatch
        if sceneScriptLayerSnapshotFailure != nil {
            cursorBatch = .init(samples: [], overflowed: false)
        } else if surfaces.count == 1,
                  let metalView = surfaces.values.first?.metalView {
            cursorBatch = metalView.sceneScriptCursorFrameBatch(
                ownerLayerIDs: launchContext.sceneScriptCursorProgram.ownerLayerIDs,
                capturedOwnerLayerIDs:
                    launchContext.sceneScriptCursorProgram.capturedOwnerLayerIDs,
                timing: timing,
                dynamicValues: preliminaryForSceneScript
            )
        } else {
            let cursorHits = surfaces.values.reduce(
                into: [Int: SceneScriptCursorHit]()
            ) { result, surface in
                _ = surface.metalView.drainSceneScriptPointerEvents()
                result.merge(surface.metalView.sceneScriptCursorHits(
                    ownerLayerIDs: launchContext.sceneScriptCursorProgram.ownerLayerIDs,
                    timing: timing,
                    dynamicValues: preliminaryForSceneScript
                )) { existing, _ in existing }
            }
            cursorBatch = .init(
                samples: [.init(
                    hits: cursorHits,
                    primaryButtonIsDown: surfaces.values.contains {
                        $0.metalView.pointerState.isPrimaryButtonDown
                    }
                )],
                overflowed: false
            )
        }
        let cursorResult: SceneScriptCursorFrameResult
        if let failure = sceneScriptLayerSnapshotFailure {
            cursorResult = .init(
                failures: Dictionary(uniqueKeysWithValues:
                    launchContext.sceneScriptCursorProgram.ownerLayerIDs.map {
                        ($0, failure)
                    }
                ),
                materialFunctionMutations: [], animationMutations: [],
                layerMutations: [], inputBatchOverflowed: false
            )
        } else {
            cursorResult = launchContext.sceneScriptCursorProgram.dispatch(
                batch: cursorBatch,
                frame: sceneScriptFrame,
                userPropertiesJSON: userPropertiesJSON
            )
        }
        if cursorResult.inputBatchOverflowed {
            NSLog(
                "MWX SceneScript VM: event=cursor batch=rejected reason=event-budget fallback=previous-current"
            )
        }
        for (layerID, failure) in cursorResult.failures {
            NSLog(
                "MWX SceneScript VM: layerID=%d event=cursor failure=%@ code=%@ fallback=previous-current",
                layerID,
                String(describing: failure),
                failure.code
            )
        }
        let projectedSceneScriptVectorInputs =
            launchContext.propertyVectorScriptProgram.bindings.reduce(
                into: [SceneDynamicTarget: SceneDynamicValue]()
            ) { inputs, binding in
                let target = binding.definition.target
                guard let resolved = preliminaryForSceneScript[target],
                      resolved.value.valueType == binding.definition.valueType else {
                    return
                }
                inputs[target] = resolved.value
            }
        let sceneScriptVectorInputs = launchContext.sceneScriptVectorMediaRoute
            .admittedVectorInputs(
                projectedSceneScriptVectorInputs,
                mediaOwnerTargets: launchContext.propertyVectorMediaPassTargets
            )
        let sceneScriptVectorResult: SceneScriptVectorFrameResult
        if let failure = sceneScriptLayerSnapshotFailure {
            sceneScriptVectorResult = .init(
                values: [:],
                failures: Dictionary(uniqueKeysWithValues:
                    launchContext.propertyVectorScriptProgram.bindings.map {
                        ($0.definition.target, failure)
                    }
                ),
                materialFunctionMutations: [], animationMutations: [],
                layerMutations: []
            )
        } else {
            sceneScriptVectorResult = launchContext.propertyVectorScriptProgram.evaluate(
                inputs: sceneScriptVectorInputs,
                effectivePropertyValues: launchContext.liveState.effectiveValues,
                frame: sceneScriptFrame,
                mediaThumbnailEvent: sceneScriptMediaThumbnailEvent,
                mediaPlaybackEvent: sceneScriptMediaPlaybackEvent,
                audioSpectrum: audioSpectrum
            )
        }
        for (target, failure) in sceneScriptVectorResult.failures {
            NSLog(
                "MWX SceneScript VM: target=%@ failure=%@ code=%@ fallback=current-frame-lower-priority",
                String(describing: target),
                String(describing: failure),
                failure.code
            )
        }
        commonSceneScriptValues.merge(
            sceneScriptVectorResult.values,
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        let sceneScriptStringInputs = launchContext.sceneScriptStringProgram.bindings
            .reduce(into: [SceneDynamicTarget: SceneDynamicValue]()) { inputs, binding in
                guard let resolved = preliminaryForSceneScript[binding.target],
                      case .string = resolved.value else { return }
                inputs[binding.target] = resolved.value
            }
        let sceneScriptStringResult: SceneScriptStringFrameResult
        if let failure = sceneScriptLayerSnapshotFailure {
            sceneScriptStringResult = .init(
                values: [:],
                failures: Dictionary(uniqueKeysWithValues:
                    launchContext.sceneScriptStringProgram.bindings.map {
                        ($0.target, failure)
                    }
                ),
                materialFunctionMutations: [], animationMutations: [],
                layerMutations: []
            )
        } else {
            sceneScriptStringResult = launchContext.sceneScriptStringProgram.evaluate(
                inputs: sceneScriptStringInputs,
                frame: sceneScriptFrame,
                userPropertiesJSON: userPropertiesJSON,
                mediaThumbnailEvent: sceneScriptMediaThumbnailEvent,
                mediaPlaybackEvent: sceneScriptMediaPlaybackEvent,
                mediaPropertiesEvent: sceneScriptMediaPropertiesEvent,
                audioSpectrum: audioSpectrum
            )
        }
        for (target, failure) in sceneScriptStringResult.failures {
            NSLog(
                "MWX SceneScript VM: target=%@ failure=%@ code=%@ fallback=current-frame-lower-priority",
                String(describing: target),
                String(describing: failure),
                failure.code
            )
        }
        commonSceneScriptValues.merge(
            sceneScriptStringResult.values,
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        let sceneScriptInputs = launchContext.sceneScriptScalarProgram.bindings.reduce(
            into: [SceneDynamicTarget: SceneDynamicValue]()
        ) { inputs, binding in
            guard let resolved = preliminaryForSceneScript[binding.target],
                  case .scalar = resolved.value else { return }
            inputs[binding.target] = resolved.value
        }
        let sceneScriptResult: SceneScriptScalarFrameResult
        if let failure = sceneScriptLayerSnapshotFailure {
            sceneScriptResult = .init(
                values: [:],
                failures: Dictionary(uniqueKeysWithValues:
                    launchContext.sceneScriptScalarProgram.bindings.map {
                        ($0.target, failure)
                    }
                ),
                materialFunctionMutations: [], animationMutations: [],
                layerMutations: []
            )
        } else {
            sceneScriptResult = launchContext.sceneScriptScalarProgram.evaluate(
                inputs: sceneScriptInputs,
                frame: sceneScriptFrame,
                userPropertiesJSON: userPropertiesJSON,
                mediaThumbnailEvent: sceneScriptMediaThumbnailEvent,
                mediaPlaybackEvent: sceneScriptMediaPlaybackEvent,
                audioSpectrum: audioSpectrum
            )
        }
        if !sceneScriptResult.failures.isEmpty {
            for (target, failure) in sceneScriptResult.failures {
                NSLog(
                    "MWX SceneScript VM: target=%@ failure=%@ code=%@ fallback=current-frame-lower-priority",
                    String(describing: target),
                    String(describing: failure),
                    failure.code
                )
            }
        }
        commonSceneScriptValues.merge(
            sceneScriptResult.values,
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        let layerMutations = sceneScriptVectorResult.layerMutations
            + sceneScriptStringResult.layerMutations
            + sceneScriptResult.layerMutations
            + cursorResult.layerMutations
        let layerTopology = layerMutationSnapshot
        let animationMutations = cursorResult.animationMutations
            + sceneScriptVectorResult.animationMutations
            + sceneScriptStringResult.animationMutations
            + sceneScriptResult.animationMutations
        if !animationMutations.isEmpty {
            switch launchContext.timelinePlaybackRuntime.apply(
                animationMutations,
                sceneTime: timing.sceneTime
            ) {
            case .success:
                NSLog(
                    "MWX SceneScript VM: animationCommands=%d callback=committed nextFrame=true route=generic-only",
                    animationMutations.count
                )
            case let .failure(failure):
                NSLog(
                    "MWX SceneScript VM: animationCommands=%d callback=rejected failure=%@ fallback=previous-current",
                    animationMutations.count,
                    String(describing: failure)
                )
            }
        }
        for surface in surfaces.values {
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let resolvedDynamicValues = surface.evaluationTransaction.evaluate(
                frameIndex: timing.frameIndex, definitions: definitions,
                userValues: launchContext.liveState.userValues,
                timelineValues: timelineValues,
                sceneScriptValues: commonSceneScriptValues
            ).snapshot
#if DEBUG
            let dynamicValues: SceneDynamicSnapshot
            if Self.usesDebugEvidenceWindow,
               debugDropDynamicValuesFrameIndex == timing.frameIndex {
                dynamicValues = .empty(
                    frameIndex: resolvedDynamicValues.frameIndex,
                    generation: resolvedDynamicValues.generation
                )
                if !debugDidDropDynamicValues {
                    debugDidDropDynamicValues = true
                    NSLog(
                        "MWX DEBUG SCENE: phase=dynamic-snapshot-fault state=dropped frame=%llu generation=%llu resolvedValues=%d",
                        resolvedDynamicValues.frameIndex,
                        resolvedDynamicValues.generation,
                        resolvedDynamicValues.count
                    )
                }
            } else {
                dynamicValues = resolvedDynamicValues
                if Self.usesDebugEvidenceWindow,
                   debugDidDropDynamicValues,
                   !debugDidLogDynamicValuesRecovery,
                   let faultFrameIndex = debugDropDynamicValuesFrameIndex,
                   timing.frameIndex > faultFrameIndex {
                    debugDidLogDynamicValuesRecovery = true
                    NSLog(
                        "MWX DEBUG SCENE: phase=dynamic-snapshot-fault state=recovered frame=%llu generation=%llu resolvedValues=%d",
                        resolvedDynamicValues.frameIndex,
                        resolvedDynamicValues.generation,
                        resolvedDynamicValues.count
                    )
                }
            }
#else
            let dynamicValues = resolvedDynamicValues
#endif
            surface.metalView.renderFrame(
                timing: timing, dynamicValues: dynamicValues,
                layerTopology: layerTopology,
                materialFunctionMutations:
                    cursorResult.materialFunctionMutations
                    + sceneScriptVectorResult.materialFunctionMutations
                    + sceneScriptStringResult.materialFunctionMutations
                    + sceneScriptResult.materialFunctionMutations,
                mediaInput: mediaInput,
                audioSpectrum: audioSpectrum,
                performanceTelemetry: Self.usesDebugEvidenceWindow
                    ? SceneFramePerformanceTelemetry.debugEvidence : nil
            )
#if DEBUG
            if Self.usesDebugEvidenceWindow {
                SceneFramePerformanceTelemetry.debugEvidence.recordMainFrame(
                    duration: ProcessInfo.processInfo.systemUptime - mainFrameStart
                )
            }
#endif
        }
        if !layerMutations.isEmpty {
            switch launchContext.sceneScriptDynamicLayerRuntime.apply(layerMutations) {
            case .success:
                NSLog(
                    "MWX SceneScript VM: layerMutations=%d callback=committed nextFrame=true route=generic-only",
                    layerMutations.count
                )
            case let .failure(failure):
                NSLog(
                    "MWX SceneScript VM: layerMutations=%d callback=rejected failure=%@ fallback=previous-current",
                    layerMutations.count,
                    String(describing: failure)
                )
            }
        }
        return .rendered
    }

    func updateMouseLocations() {
#if DEBUG
        if let debugPointerOverride {
            surfaces.values.forEach { $0.metalView.applyPointerState(debugPointerOverride) }
            return
        }
#endif
        let mouseLocation = NSEvent.mouseLocation
        surfaces.values.forEach { $0.metalView.updateMouseLocationInScreen(mouseLocation) }
    }
}
