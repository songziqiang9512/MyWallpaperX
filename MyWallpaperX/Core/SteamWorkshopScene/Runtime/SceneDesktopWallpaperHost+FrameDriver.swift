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
        let sceneScriptProgramTimerFrameState = self.sceneScriptProgramTimerFrameState(launchContext)
        guard sceneScriptProgramTimerFrameState.scalar.isComplete && sceneScriptProgramTimerFrameState.string.isComplete && sceneScriptProgramTimerFrameState.vector.isComplete && sceneScriptProgramTimerFrameState.cursor.isComplete else { discardSceneScriptProgramTimerFrameState(launchContext, sceneScriptProgramTimerFrameState); return .dropped }
        guard surfaces.values.allSatisfy({
            !$0.metalView.shouldDeferResolvedMaterialFrame
        }) else { discardSceneScriptProgramTimerFrameState(launchContext, sceneScriptProgramTimerFrameState)
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
        let audioSpectrumFrame = SceneAudioSpectrumInbox.shared.prepareFrame()
        let audioSpectrum = audioSpectrumFrame.snapshot
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
        let preliminarySceneScriptResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: timing.frameIndex,
            generation: 0,
            index: definitionIndex,
            userValues: launchContext.liveState.userValues,
            timelineValues: timelineValues,
            sceneScriptValues: boundedSceneScriptValues
        )
        let preliminaryForSceneScript = preliminarySceneScriptResolution.snapshot
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
        let sharedFrameTransactionFailure =
            launchContext.propertyVectorScriptProgram.requiresSharedFrameTransaction
            ? launchContext.propertyVectorScriptProgram.domain?
                .beginSharedFrameTransaction()
            : nil
        let sceneScriptVideoSnapshots = videoTextureSourceRegistry?
            .sceneScriptSnapshots(sceneTime: timing.sceneTime) ?? [:]
        let sceneScriptLayerSnapshotFailure: SceneScriptScalarRuntimeFailure?
        do {
            if let sharedFrameTransactionFailure {
                throw sharedFrameTransactionFailure
            }
            try launchContext.propertyVectorScriptProgram.domain?.publishLayerSnapshot(
                    preliminaryForSceneScript,
                    descriptor: launchContext.runtimeInput.renderDescriptor,
                    videoSnapshots: sceneScriptVideoSnapshots,
                    catalogToken: launchContext.frameSchema.sceneScriptLayerCatalogToken,
                    runtimeFieldLayerIDs: launchContext.frameSchema.sceneScriptRuntimeFieldLayerIDs,
                    awaitingHostFrameOutcome: true
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
        let sceneScriptProgramFrameState = self.sceneScriptProgramFrameState(
            launchContext
        )
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
        let projectedSceneScriptVectorInputs = preliminaryForSceneScript
            .typedValues(
                for: launchContext.propertyVectorScriptProgram.inputTargets,
                valueTypes:
                    launchContext.propertyVectorScriptProgram.inputValueTypes
            )
        let sceneScriptVectorInputs = launchContext.sceneScriptVectorMediaRoute
            .admittedVectorInputs(
                projectedSceneScriptVectorInputs,
                mediaOwnerTargets: launchContext.propertyVectorMediaTargets
            )
        let sceneScriptStringInputs = preliminaryForSceneScript.typedValues(
            for: launchContext.sceneScriptStringProgram.inputTargets,
            valueTypes: launchContext.sceneScriptStringProgram.inputValueTypes
        )
        let sceneScriptInputs = preliminaryForSceneScript.typedValues(
            for: launchContext.sceneScriptScalarProgram.inputTargets,
            valueTypes: launchContext.sceneScriptScalarProgram.inputValueTypes
        )
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
                userPropertiesJSON: userPropertiesJSON, propertyRevision: launchContext.liveState.revision,
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
        for failure in runtimeValidationFailures {
            let subsystem: String
            switch failure.subsystem {
            case .animation:
                subsystem = "animationCommands"
            case .video:
                subsystem = "videoCommands"
            case .puppetBone:
                subsystem = "puppetBoneMutations"
            }
            NSLog(
                "MWX SceneScript VM: %@=%d owner=%@ callback=rejected failure=%@ fallback=previous-current",
                subsystem,
                failure.commandCount,
                String(describing: failure.ownerTarget),
                failure.reason
            )
        }
        let animationMutations = admittedOwnerEffects.flatMap(
            \.animationMutations
        )
        let puppetBoneMutations = admittedOwnerEffects.flatMap(
            \.puppetBoneMutations
        )
        let videoCommands = admittedOwnerEffects.flatMap(\.videoCommands)
        func admittedValues(
            _ values: [SceneDynamicTarget: SceneDynamicValue]
        ) -> [SceneDynamicTarget: SceneDynamicValue] {
            values.filter { !rejectedOwnerTargets.contains($0.key) }
        }
        var admittedSceneScriptValues = admittedValues(
            sceneScriptStringResult.values
        )
        admittedSceneScriptValues.merge(
            admittedValues(sceneScriptResult.values),
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        admittedSceneScriptValues.merge(
            admittedValues(sceneScriptVectorResult.values),
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        // The preliminary snapshot already contains authored, user-property,
        // timeline, and stateful SceneScript lanes. Overlay only the current
        // admitted results so surface preparation does not walk every
        // definition a second time on the same frame.
        let sharedSurfaceResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: timing.frameIndex,
            generation: 0,
            index: definitionIndex,
            base: preliminarySceneScriptResolution,
            sceneScriptValues: admittedSceneScriptValues
        )
        let materialFunctionMutations = admittedOwnerEffects.flatMap(\.materialFunctionMutations)
        var pendingSurfaceEvaluations: [(Surface, SceneSurfaceEvaluationTransaction.PendingEvaluation)] = []
        var frameOutcomes: [SceneMetalRenderer.FrameOutcome] = []
        frameOutcomes.reserveCapacity(surfaces.count)
        let parallaxPointerStates = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.key, $0.value.metalView.snapshotParallaxPointerSmoother()) })
        let pointerPreviousStates = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.key, $0.value.metalView.snapshotPointerPrevious()) })
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
                frameIndex: timing.frameIndex,
                resolution: sharedSurfaceResolution
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
                layerTopology: layerTopology.resolvingDynamicMaterialColors(from: dynamicValues),
                dynamicTextFieldsByLayerID:
                    launchContext.frameSchema.dynamicTextFieldsByLayerID,
                materialFunctionMutations: materialFunctionMutations,
                puppetBoneMutations: puppetBoneMutations,
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
            // A deferred/dropped surface must not consume a frame index or move the host-time anchor.
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
            for (displayID, batch) in cursorPreparation.drainedPointerBatches {
                surfaces[displayID]?.metalView
                    .restoreSceneScriptPointerEvents(batch)
            }
            if let cursorEdgeState {
                launchContext.sceneScriptCursorProgram
                    .restoreEdgeState(cursorEdgeState)
            }
            restoreSceneScriptProgramFrameState(launchContext, sceneScriptProgramFrameState)
            restoreSceneScriptProgramTimerFrameState(launchContext, sceneScriptProgramTimerFrameState)
            launchContext.sceneScriptStorageSession?.discardFrameTransaction()
            _ = launchContext.propertyVectorScriptProgram.domain?
                .discardSharedFrameTransaction()
            surfaces.values.forEach { $0.metalView.discardPreparedParticleFrame() }
            surfaces.values.forEach { $0.metalView.discardPreparedSpriteFrames() }
            surfaces.values.forEach { $0.metalView.discardPreparedMaterialAssetFrame() }
            surfaces.values.forEach { $0.metalView.discardPreparedFrameTexturePublication() }
            surfaces.values.forEach { $0.metalView.discardPreparedMediaThumbnailUpdate() }
            surfaces.values.forEach { $0.metalView.discardPreparedVideoFrames() }
            surfaces.values.forEach { $0.metalView.discardPreparedDynamicTextUpdate() }
            discardSceneScriptFrameOutcome(launchContext)
            return frameOutcomes.contains(where: { $0.isDeferred })
                ? .busy : .dropped
        }
        surfaces.values.forEach { $0.metalView.commitPreparedParticleFrame() }
        surfaces.values.forEach { $0.metalView.commitPreparedMaterialAssetFrame() }
        surfaces.values.forEach { $0.metalView.commitPreparedFrameTexturePublication() }
        surfaces.values.forEach { $0.metalView.commitPreparedMediaThumbnailUpdate() }
        surfaces.values.forEach { $0.metalView.commitPreparedVideoFrames() }
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
        SceneAudioSpectrumInbox.shared.commitFrame(audioSpectrumFrame)
        discardSceneScriptProgramTimerFrameState(launchContext, sceneScriptProgramTimerFrameState)
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
