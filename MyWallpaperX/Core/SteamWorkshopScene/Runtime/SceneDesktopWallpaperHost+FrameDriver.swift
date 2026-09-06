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
    case dropped
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
                launchContext.preparedDeviceResources.baseImages
                    .cancelDeferredPreparation()
            }
            if let pending = pendingDeferredLayerVisibilityUpdate {
                logDeferredLayerVisibilityTransition(
                    generation: pending.generation,
                    layerIDs: pending.layerIDs,
                    state: "cancelled:surface-stop"
                )
            }
            pendingDeferredLayerVisibilityUpdate = nil
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
            let cadenceDeadline = scheduledDeadline + sceneFrameInterval
            // Realign narrowly late frames at current host time; fast frames
            // still honor cadence while busy gate keeps history graphs serial.
            nextDeadline = max(cadenceDeadline, now)
        case .busy:
            // History-bearing graphs remain single-frame-in-flight. A short
            // retry prevents a slight overrun from losing a full 60 Hz slot.
            nextDeadline = now + sceneBusyFrameRetryInterval
        case .dropped:
            // A hard frame rejection did not produce a drawable, but it is
            // not an in-flight resource wait. Keep normal cadence without
            // reporting the attempt as rendered.
            nextDeadline = max(scheduledDeadline + sceneFrameInterval, now)
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
        guard launchContext != nil, !surfaces.isEmpty else { return .inactive }
        promotePendingDeferredLayerVisibilityIfReady()
        guard let launchContext else { return .inactive }
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
        let clockState = sceneClock.snapshot()
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
        let definitionIndex = launchContext.dynamicDefinitionIndex
        let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()
        let timelineObservationState = launchContext.timelinePlaybackRuntime
            .observationSnapshot()
        let timelineValues = launchContext.timelinePlaybackRuntime.values(
            sceneTime: timing.sceneTime
        )
        let mediaInput = SceneMediaThumbnailInbox.shared.latest()
        let mediaThumbnailSnapshots = Dictionary(uniqueKeysWithValues:
            surfaces.map { displayID, surface in
                (
                    displayID,
                    surface.metalView.prepareMediaThumbnail(from: mediaInput)
                )
            }
        )
        let mediaThumbnailGenerationIsTerminal =
            !mediaThumbnailSnapshots.isEmpty
            && mediaThumbnailSnapshots.values.allSatisfy {
                $0.generation == mediaInput.generation
                    && $0.pendingGeneration == nil
            }
        let sceneScriptMediaThumbnailEvent = mediaThumbnailGenerationIsTerminal
            ? SceneScriptMediaThumbnailEventInput(snapshot: mediaInput) : nil
        let sceneScriptMediaPlaybackEvent =
            SceneScriptMediaPlaybackEventInput(snapshot: mediaInput)
        let sceneScriptMediaPropertiesEvent =
            SceneScriptMediaPropertiesEventInput(snapshot: mediaInput)
        let sceneScriptMediaTimelineEvent =
            SceneScriptMediaTimelineEventInput(snapshot: mediaInput)
        let sceneScriptMediaEvents = SceneScriptMediaFrameEvents(
            playback: sceneScriptMediaPlaybackEvent,
            properties: sceneScriptMediaPropertiesEvent,
            thumbnail: sceneScriptMediaThumbnailEvent,
            timeline: sceneScriptMediaTimelineEvent
        )
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
        let pendingSharedLayerAlpha = sharedLayerAlphaRuntime.prepareValues(
            effectivePropertyValues: launchContext.liveState.effectiveValues,
            frameTime: timing.simulationFrameTime
        )
        let sharedLayerAlphaValues = pendingSharedLayerAlpha.values
        let layerMutationSnapshot = launchContext.sceneScriptDynamicLayerRuntime
            .snapshot()
        // SceneScript `update(value)` receives the current published value;
        // the authored descriptor is only the seed. Carry forward typed
        // targets when no higher-priority user/timeline producer is present.
        let sceneScriptStatefulTargets = launchContext.sceneScriptStatefulTargets
        let previousSceneScriptValues = surfaces.values.first?.evaluationTransaction
            .previousValues(for: sceneScriptStatefulTargets)
            .filter { target, _ in
                !launchContext.liveState.userValues.keys.contains(target)
                    && !timelineValues.keys.contains(target)
            } ?? [:]
        var commonSceneScriptValues = previousSceneScriptValues
        commonSceneScriptValues.merge(textScriptValues) { _, current in current }
        commonSceneScriptValues.merge(sharedLayerAlphaValues) { _, current in current }
        commonSceneScriptValues.merge(
            layerMutationSnapshot.authoredLayerValues
        ) { _, committedMutation in committedMutation }
        let boundedSceneScriptValues = commonSceneScriptValues
        let preliminaryForSceneScript = SceneDynamicSnapshotResolver().resolve(
            frameIndex: timing.frameIndex,
            generation: 0,
            index: definitionIndex,
            userValues: launchContext.liveState.userValues,
            timelineValues: timelineValues,
            sceneScriptValues: boundedSceneScriptValues
        ).snapshot
        let userPropertiesJSON = launchContext.propertyVectorScriptProgram
            .userPropertiesJSON(
                effectiveValues: launchContext.liveState.effectiveValues,
                revision: launchContext.liveState.revision
            )
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
        launchContext.sceneScriptStorageSession?.beginFrameTransaction()
        let sceneScriptVideoSnapshots = videoTextureSourceRegistry?
            .sceneScriptSnapshots(sceneTime: timing.sceneTime) ?? [:]
        let sceneScriptLayerSnapshotFailure: SceneScriptScalarRuntimeFailure?
        do {
            try launchContext.propertyVectorScriptProgram.domain?
                .publishLayerSnapshot(
                    preliminaryForSceneScript,
                    descriptor: launchContext.runtimeInput.renderDescriptor,
                    videoSnapshots: sceneScriptVideoSnapshots,
                    catalogToken: launchContext.frameSchema
                        .sceneScriptLayerCatalogToken
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
        let cursorPreparation = prepareSceneScriptCursorBatch(
            launchContext: launchContext,
            timing: timing,
            preliminaryForSceneScript: preliminaryForSceneScript,
            layerSnapshotFailure: sceneScriptLayerSnapshotFailure
        )
        let cursorBatch = cursorPreparation.batch
        let cursorResult: SceneScriptCursorFrameResult
        var cursorEdgeState: SceneScriptCursorEdgeState?
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
            cursorEdgeState = launchContext.sceneScriptCursorProgram
                .edgeStateSnapshot()
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
                mediaOwnerTargets: launchContext.propertyVectorMediaTargets
            )
        let sceneScriptStringInputs = launchContext.sceneScriptStringProgram.bindings
            .reduce(into: [SceneDynamicTarget: SceneDynamicValue]()) { inputs, binding in
                guard let resolved = preliminaryForSceneScript[binding.target],
                      case .string = resolved.value else { return }
                inputs[binding.target] = resolved.value
            }
        let sceneScriptInputs = launchContext.sceneScriptScalarProgram.bindings.reduce(
            into: [SceneDynamicTarget: SceneDynamicValue]()
        ) { inputs, binding in
            guard let resolved = preliminaryForSceneScript[binding.target],
                  case .scalar = resolved.value else { return }
            inputs[binding.target] = resolved.value
        }
        let coordinatedSceneScript: SceneScriptMediaFrameCoordinatorResult
        if let failure = sceneScriptLayerSnapshotFailure {
            coordinatedSceneScript = .init(
                vector: .init(
                    values: [:],
                    failures: Dictionary(uniqueKeysWithValues:
                        launchContext.propertyVectorScriptProgram.bindings.map {
                            ($0.definition.target, failure)
                        }
                    ),
                    materialFunctionMutations: [], animationMutations: [],
                    layerMutations: [], videoCommands: [],
                    videoCommandTargets: []
                ),
                string: .init(
                    values: [:],
                    failures: Dictionary(uniqueKeysWithValues:
                        launchContext.sceneScriptStringProgram.bindings.map {
                            ($0.target, failure)
                        }
                    ),
                    materialFunctionMutations: [], animationMutations: [],
                    layerMutations: []
                ),
                scalar: .init(
                    values: [:],
                    failures: Dictionary(uniqueKeysWithValues:
                        launchContext.sceneScriptScalarProgram.bindings.map {
                            ($0.target, failure)
                        }
                    ),
                    materialFunctionMutations: [], animationMutations: [],
                    layerMutations: []
                ),
                materialFunctionMutations: [],
                animationMutations: [],
                layerMutations: [],
                videoCommands: []
            )
        } else {
            coordinatedSceneScript = launchContext.frameSchema.mediaFrameCoordinator.evaluate(
                vectorInputs: sceneScriptVectorInputs,
                stringInputs: sceneScriptStringInputs,
                scalarInputs: sceneScriptInputs,
                effectivePropertyValues: launchContext.liveState.effectiveValues,
                frame: sceneScriptFrame,
                userPropertiesJSON: userPropertiesJSON,
                events: sceneScriptMediaEvents,
                audioSpectrum: audioSpectrum
            )
        }
        let sceneScriptVectorResult = coordinatedSceneScript.vector
        let sceneScriptStringResult = coordinatedSceneScript.string
        let sceneScriptResult = coordinatedSceneScript.scalar
        for failures in [
            sceneScriptVectorResult.failures,
            sceneScriptStringResult.failures,
            sceneScriptResult.failures,
        ] {
            for (target, failure) in failures {
                NSLog(
                    "MWX SceneScript VM: target=%@ failure=%@ code=%@ fallback=current-frame-lower-priority",
                    String(describing: target),
                    String(describing: failure),
                    failure.code
                )
            }
        }
        let layerTopology = layerMutationSnapshot
        let ownerEffects = coordinatedSceneScript.ownerEffects
            + cursorResult.ownerEffects
        let layerMutationCount = ownerEffects.reduce(0) {
            $0 + $1.layerMutations.count
        }
#if DEBUG
        if Self.usesDebugEvidenceWindow, timing.frameIndex == 0 {
            let effectSummary = ownerEffects.map { effect in
                let dynamicCount = effect.layerMutations.filter(\.isDynamic).count
                return "owner=\(effect.ownerTarget)"
                    + ":layers=\(effect.layerMutations.count)"
                    + ":dynamic=\(dynamicCount)"
            }.joined(separator: ",")
            NSLog(
                "MWX DEBUG SCENE: phase=owner-effects frame=%llu vectorValues=%d vectorFailures=%d vectorLayers=%d vectorOwners=%d cursorOwners=%d totalLayers=%d summary=%@",
                timing.frameIndex,
                sceneScriptVectorResult.values.count,
                sceneScriptVectorResult.failures.count,
                sceneScriptVectorResult.layerMutations.count,
                coordinatedSceneScript.vector.ownerEffects.count,
                cursorResult.ownerEffects.count,
                layerMutationCount,
                effectSummary
            )
        }
#endif
        var runtimeValidationFailures:
            [SceneScriptOwnerEffectsRuntimeFailure] = []
        let fixedPoint = launchContext.sceneScriptDynamicLayerRuntime
            .preflightOwnerEffectsToFixedPoint(ownerEffects) { admitted in
                let failures = SceneScriptOwnerEffectsRuntimeValidation
                    .failures(
                        for: admitted,
                        timelineRuntime: launchContext.timelinePlaybackRuntime,
                        videoRegistry: videoTextureSourceRegistry,
                        timing: timing
                    )
                runtimeValidationFailures.append(contentsOf: failures)
                return Set(failures.map(\.ownerTarget))
            }
        let admission = fixedPoint.admission
        let admittedOwnerEffects = admission.admittedEffects
        var rejectedOwnerTargets = fixedPoint.externallyRejectedOwners
        rejectedOwnerTargets.formUnion(admission.rejectedOwners.compactMap(
            \.ownerTarget
        ))
#if DEBUG
        if Self.usesDebugEvidenceWindow, timing.frameIndex == 0 {
            let admittedLayers = admittedOwnerEffects.reduce(0) {
                $0 + $1.layerMutations.count
            }
            let admittedDynamicLayers = admittedOwnerEffects.reduce(0) {
                $0 + $1.layerMutations.filter(\.isDynamic).count
            }
            NSLog(
                "MWX DEBUG SCENE: phase=owner-effects-admission frame=%llu admittedOwners=%d rejectedOwners=%d externallyRejected=%d admittedLayers=%d admittedDynamic=%d topologyRevision=%llu",
                timing.frameIndex,
                admittedOwnerEffects.count,
                admission.rejectedOwners.count,
                fixedPoint.externallyRejectedOwners.count,
                admittedLayers,
                admittedDynamicLayers,
                launchContext.sceneScriptDynamicLayerRuntime.topologyRevision
            )
        }
#endif
        for rejected in admission.rejectedOwners {
            NSLog(
                "MWX SceneScript VM: layerMutations=%d owner=%@ callback=rejected failure=%@ fallback=previous-current",
                layerMutationCount,
                rejected.ownerTarget.map(String.init(describing:))
                    ?? "frame-integrity",
                String(describing: rejected.failure)
            )
        }
        var rejectedVideoTargets = Set<SceneDynamicTarget>()
        for failure in runtimeValidationFailures {
            let subsystem: String
            switch failure.subsystem {
            case .animation:
                subsystem = "animationCommands"
            case .video:
                subsystem = "videoCommands"
                rejectedVideoTargets.insert(failure.ownerTarget)
            }
            NSLog(
                "MWX SceneScript VM: %@=%d owner=%@ callback=rejected failure=%@ fallback=previous-current",
                subsystem,
                failure.commandCount,
                String(describing: failure.ownerTarget),
                failure.reason
            )
        }
        if !rejectedVideoTargets.isEmpty {
            launchContext.propertyVectorScriptProgram
                .rejectVideoCommandTargets(rejectedVideoTargets)
        }
        let animationMutations = admittedOwnerEffects.flatMap(
            \.animationMutations
        )
        let videoCommands = admittedOwnerEffects.flatMap(\.videoCommands)
        func admittedValues(
            _ values: [SceneDynamicTarget: SceneDynamicValue]
        ) -> [SceneDynamicTarget: SceneDynamicValue] {
            values.filter { !rejectedOwnerTargets.contains($0.key) }
        }
        commonSceneScriptValues.merge(
            admittedValues(sceneScriptStringResult.values),
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        commonSceneScriptValues.merge(
            admittedValues(sceneScriptResult.values),
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        commonSceneScriptValues.merge(
            admittedValues(sceneScriptVectorResult.values),
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        let materialFunctionMutations = admittedOwnerEffects.flatMap(
            \.materialFunctionMutations
        )
        var pendingSurfaceEvaluations:
            [(Surface, SceneSurfaceEvaluationTransaction.PendingEvaluation)] = []
        var frameOutcomes: [SceneMetalRenderer.FrameOutcome] = []
        frameOutcomes.reserveCapacity(surfaces.count)
        let parallaxPointerStates = Dictionary(uniqueKeysWithValues: surfaces.map {
            ($0.key, $0.value.metalView.snapshotParallaxPointerSmoother())
        })
        let pointerPreviousStates = Dictionary(uniqueKeysWithValues: surfaces.map {
            ($0.key, $0.value.metalView.snapshotPointerPrevious())
        })
        for (displayID, surface) in surfaces {
            guard let mediaThumbnailSnapshot =
                mediaThumbnailSnapshots[displayID] else {
                frameOutcomes.append(.deferred(
                    reasonCode: "media-thumbnail-snapshot-unavailable"
                ))
                continue
            }
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let pendingEvaluation = surface.evaluationTransaction.prepare(
                frameIndex: timing.frameIndex, index: definitionIndex,
                userValues: launchContext.liveState.userValues,
                timelineValues: timelineValues,
                sceneScriptValues: commonSceneScriptValues
            )
            pendingSurfaceEvaluations.append((surface, pendingEvaluation))
            let resolvedDynamicValues = pendingEvaluation.resolution.snapshot
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
#if DEBUG
            logDebugDynamicLayerVisibilityIfChanged(
                descriptor: launchContext.runtimeInput.renderDescriptor,
                snapshot: dynamicValues
            )
#endif
            let frameOutcome = surface.metalView.renderFrame(
                timing: timing, dynamicValues: dynamicValues,
                layerTopology: layerTopology.resolvingDynamicMaterialColors(
                    from: dynamicValues
                ),
                materialFunctionMutations: materialFunctionMutations,
                mediaThumbnail: mediaThumbnailSnapshot,
                audioSpectrum: audioSpectrum,
                performanceTelemetry: Self.usesDebugEvidenceWindow
                    ? SceneFramePerformanceTelemetry.debugEvidence : nil
            )
            frameOutcomes.append(frameOutcome)
#if DEBUG
            if Self.usesDebugEvidenceWindow {
                SceneFramePerformanceTelemetry.debugEvidence.recordMainFrame(
                    duration: ProcessInfo.processInfo.systemUptime - mainFrameStart
                )
            }
#endif
        }
        let allSurfacesSubmitted = frameOutcomes.count == surfaces.count
            && frameOutcomes.allSatisfy(\.isSubmitted)
        guard allSurfacesSubmitted else {
            // Shared clock is part of the frame transaction; a deferred/dropped
            // surface must not consume a frame index or move the host-time anchor.
            sceneClock.restore(clockState)
            launchContext.timelinePlaybackRuntime.restoreObservationState(
                timelineObservationState
            )
            for (displayID, state) in parallaxPointerStates {
                surfaces[displayID]?.metalView.restoreParallaxPointerSmoother(state)
            }
            for (displayID, previous) in pointerPreviousStates {
                surfaces[displayID]?.metalView.restorePointerPrevious(previous)
            }
            // The cursor producer advanced before the outcome was known.
            // A deferred/dropped frame must not consume pointer events or
            // advance edge state: re-insert the drained batches and restore
            // the pre-dispatch snapshot so the next frame still sees every
            // press/release/click edge for the same input.
            for (displayID, batch) in cursorPreparation.drainedPointerBatches {
                surfaces[displayID]?.metalView
                    .restoreSceneScriptPointerEvents(batch)
            }
            if let cursorEdgeState {
                launchContext.sceneScriptCursorProgram
                    .restoreEdgeState(cursorEdgeState)
            }
            launchContext.sceneScriptStorageSession?.discardFrameTransaction()
            surfaces.values.forEach { $0.metalView.discardPreparedDynamicTextUpdate() }
            finalizeSceneScriptLayerMutations(launchContext, committing: false)
            return frameOutcomes.contains(where: { $0.isDeferred })
                ? .busy : .dropped
        }
        surfaces.values.forEach { $0.metalView.commitPreparedDynamicTextUpdate() }
        commitSubmittedSceneFrame(
            launchContext,
            pendingSurfaceEvaluations: pendingSurfaceEvaluations,
            pendingSharedLayerAlpha: pendingSharedLayerAlpha,
            animationMutations: animationMutations,
            videoCommands: videoCommands,
            timing: timing,
            layerPlan: admission.layerPlan,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        return .rendered
    }

#if DEBUG
    private func logDebugDynamicLayerVisibilityIfChanged(
        descriptor: SceneRenderDescriptor,
        snapshot: SceneDynamicSnapshot
    ) {
        guard Self.usesDebugEvidenceWindow else { return }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: descriptor,
            snapshot: snapshot
        )
        let records = descriptor.layers.compactMap { layer -> String? in
            guard let resolved = snapshot[
                .layer(layerID: layer.id, field: .visibility)
            ], case let .bool(value) = resolved.value else { return nil }
            return "layer=\(layer.id) source=\(resolved.source.rawValue)"
                + " value=\(value)"
                + " effective=\(visibleLayerIDs.contains(layer.id))"
        }
        let signature = records.joined(separator: "|")
        guard signature != debugDynamicLayerVisibilitySignature else { return }
        debugDynamicLayerVisibilitySignature = signature
        for record in records {
            NSLog(
                "MWX dynamic layer visibility: schema=dynamic-layer-visibility-v1 frame=%llu generation=%llu %@",
                snapshot.frameIndex,
                snapshot.generation,
                record
            )
        }
    }
#endif

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
