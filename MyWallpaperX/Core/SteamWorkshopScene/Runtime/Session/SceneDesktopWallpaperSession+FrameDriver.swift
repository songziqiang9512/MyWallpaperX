import AppKit
import QuartzCore
private enum SceneFrameDriverAttempt {
    case rendered
    case busy
    case dropped
    case inactive
}
extension SceneDesktopWallpaperSession {
    /// 帧节奏由性能预算档驱动（M0.7）：60=standard，30=efficient；
    /// 档位经 `.setPerformanceProfile` 命令热切换，下一次排帧生效。
    private var sceneFrameInterval: TimeInterval {
        1.0 / Double(performanceProfile.maxFPS)
    }
    private var sceneBusyFrameRetryInterval: TimeInterval {
        max(0.001, sceneFrameInterval / 8.0)
    }
#if DEBUG
    static let debugSceneTimeOverride: TimeInterval? = {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
              let rawValue = ProcessInfo.processInfo.environment[
                "MYWALLPAPERX_SCENE_DEBUG_SCENE_TIME"
              ],
              let value = TimeInterval(rawValue),
              value.isFinite,
              value >= 0 else { return nil }
        return value
    }()
    static let debugWallDateOverride: Date? = {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
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
        ScenePerformanceHUDController.shared.showIfNeeded()
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            NSLog(
                "MWX DEBUG SCENE: phase=frame-driver-start paused=%@",
                sceneClock.isPaused ? "true" : "false"
            )
        }
#endif
        // A newly loaded or rebuilt paused surface still needs its frozen first
        // frame. scheduleFrameDriver keeps the repeating driver stopped.
        let initialDeadline = CACurrentMediaTime()
        pausedFrameRetryDeadline = sceneClock.isPaused ? initialDeadline + 1 : nil
        let attempt = renderFrame()
        scheduleFrameDriver(after: attempt, scheduledDeadline: initialDeadline)
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
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
        let now = CACurrentMediaTime()
        // A paused first frame may briefly wait for a drawable or an in-flight
        // GPU transaction. Reuse this driver with a bounded admission deadline.
        let retryPausedFrame = (attempt == .busy || attempt == .dropped)
            && pausedFrameRetryDeadline.map { now < $0 } == true
        guard launchContext != nil, !sceneClock.isPaused || retryPausedFrame else {
            frameTimer?.invalidate()
            frameTimer = nil
            frameDriverDeadline = nil
            return
        }
        let nextDeadline: CFTimeInterval
        switch attempt {
        case .rendered:
            ScenePerformanceCounterHub.shared.bump(.framesRendered)
            ScenePerformanceCounterHub.shared.recordLaunchPhase(
                .firstVisibleFrame,
                uptimeMicros: ScenePerformanceCounterHub.nowUptimeMicros()
            )
            let cadenceDeadline = scheduledDeadline + sceneFrameInterval
            // Realign narrowly late frames at current host time; fast frames
            // still honor cadence while busy gate keeps history graphs serial.
            nextDeadline = max(cadenceDeadline, now)
        case .busy:
            ScenePerformanceCounterHub.shared.bump(.framesBusy)
            // History-bearing graphs remain single-frame-in-flight. A short
            // retry prevents a slight overrun from losing a full 60 Hz slot.
            nextDeadline = now + sceneBusyFrameRetryInterval
        case .dropped:
            ScenePerformanceCounterHub.shared.bump(.framesDropped)
            // A hard frame rejection did not produce a drawable, but it is
            // not an in-flight resource wait. Keep normal cadence without
            // reporting the attempt as rendered.
            nextDeadline = max(scheduledDeadline + sceneFrameInterval, now)
        case .inactive:
            ScenePerformanceCounterHub.shared.bump(.framesInactive)
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
            self.scheduleFrameDriver(after: attempt, scheduledDeadline: deadline)
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }
    private func renderFrame() -> SceneFrameDriverAttempt {
        // Preparing the paused first frame can admit new media providers. They
        // must inherit the pause even when the scene clock was already frozen.
        defer { if sceneClock.isPaused { setPlaybackPaused(true) } }
        // Always-on counters: bypass-only recording, no control flow change.
        ScenePerformanceCounterHub.shared.bump(.frameAttempts)
        let hubCPUFrameStart = ProcessInfo.processInfo.systemUptime
        defer {
            ScenePerformanceCounterHub.shared.add(
                .cpuFrameMicros,
                ScenePerformanceCounterHub.micros(since: hubCPUFrameStart)
            )
        }
        guard launchContext != nil, !surfaces.isEmpty else { return .inactive }
        if sceneClock.isPaused && surfaces.values.allSatisfy({ $0.metalView.hasSimulationFrame }) {
            _ = refreshPausedMediaPublications()
            return renderSurfaces()
        }
        promotePendingDeferredLayerVisibilityIfReady()
        guard let launchContext else { return .inactive }
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
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
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            SceneFramePerformanceTelemetry.debugEvidence.recordFrameDelta(
                raw: timing.rawFrameTime,
                dropped: timing.droppedFrameTime
            )
        }
#endif
        let definitionIndex = launchContext.dynamicDefinitionIndex
        let audioSpectrumFrame = SceneAudioSpectrumInbox.shared.prepareFrame()
        let audioSpectrum = audioSpectrumFrame.snapshot
        let timelineValues = launchContext.timelinePlaybackRuntime.values(
            sceneTime: timing.sceneTime
        )
        let mediaInput = SceneMediaThumbnailInbox.shared.latest()
        let mediaThumbnailSnapshots = Dictionary(uniqueKeysWithValues:
            surfaces.map { displayID, surface in
                (
                    displayID,
                    surface.metalView.prepareMediaThumbnail()
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
        let previousSceneScriptValues = evaluationTransaction
            .previousValues(for: sceneScriptStatefulTargets)
            .filter { target, _ in
                launchContext.liveState.userValues[target] == nil
                    && timelineValues[target] == nil
            }
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
        let puppetAnimationFrame = launchContext.puppetAnimationPlaybackRuntime.advance(
            frameIndex: timing.frameIndex, sceneTime: timing.sceneTime,
            dynamicValues: preliminaryForSceneScript)
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
        let sceneScriptTextureAnimationSnapshots = launchContext.textureAnimationPlaybackRuntime.snapshots(
            sceneTime: timing.sceneTime)
        let puppetPoseFrames = surfaces.mapValues {
            $0.metalView.prepareSceneScriptPuppetPoseFrame(
                timing: timing, puppetAnimationFrame: puppetAnimationFrame
            )
        }
        let sceneScriptPuppetPoseFrame = surfaces.count == 1
            ? puppetPoseFrames.values.first ?? .empty : .empty
        let particleObservations = particlePlaybackObservations(
            context: launchContext,
            committed: layerMutationSnapshot.particlePlayback
        )
        let particleInstanceLayerIDs = Set(launchContext.particleLayerIDs.filter {
            particleVisibilityResourcesPrepared(layerID: $0, context: launchContext)
        })
        let sceneScriptLayerSnapshotFailure: SceneScriptScalarRuntimeFailure?
        do {
            try launchContext.propertyVectorScriptProgram.domain?.publishPuppetAnimationSnapshot(
                puppetAnimationFrame.animationSnapshots)
            try launchContext.propertyVectorScriptProgram.domain?.publishLayerSnapshot(
                    preliminaryForSceneScript,
                    descriptor: launchContext.runtimeInput.renderDescriptor,
                    videoSnapshots: sceneScriptVideoSnapshots,
                    textureAnimationSnapshots:
                        sceneScriptTextureAnimationSnapshots,
                    particlePlaybackObservations: particleObservations,
                    particleInstanceLayerIDs: particleInstanceLayerIDs,
                    puppetAttachmentFrames:
                        sceneScriptPuppetPoseFrame.attachmentFrames,
                    destroyedAuthoredLayerIDs:
                        layerMutationSnapshot.destroyedAuthoredLayerIDs,
                    catalogToken: launchContext.frameSchema.sceneScriptLayerCatalogToken,
                    runtimeFieldLayerIDs: launchContext.frameSchema.sceneScriptRuntimeFieldLayerIDs,
                    awaitingHostFrameOutcome: true
                )
            if surfaces.count == 1 {
                try surfaces.values.first?.metalView
                    .publishSceneScriptPuppetPoseFrame(
                        sceneScriptPuppetPoseFrame,
                        context: launchContext,
                        timing: timing,
                        dynamicValues: preliminaryForSceneScript
                    )
            }
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
        let particleEmission = beginParticleEmissionFrame(context: launchContext, timing: timing,
            preliminary: preliminarySceneScriptResolution, topology: layerMutationSnapshot,
            poses: puppetPoseFrames, audio: audioSpectrum, inputSurfaceIDs: Set(mediaThumbnailSnapshots.keys))
        defer {
            particleEmission?.discard()
            launchContext.propertyVectorScriptProgram.domain?.endParticlePlaybackFrame()
        }
        let cursorBatch = prepareSceneScriptCursorBatch(
            launchContext: launchContext,
            timing: timing,
            preliminaryForSceneScript: preliminaryForSceneScript,
            puppetAttachmentFrames:
                sceneScriptPuppetPoseFrame.attachmentFrames,
            layerSnapshotFailure: sceneScriptLayerSnapshotFailure
        )
        let sceneScriptProgramFrameState = self.sceneScriptProgramFrameState(
            launchContext
        )
        let cursorResult: SceneScriptCursorFrameResult
        if let failure = sceneScriptLayerSnapshotFailure {
            cursorResult = .init(
                failures: Dictionary(uniqueKeysWithValues:
                    launchContext.sceneScriptCursorProgram.ownerTargets.map {
                        ($0, failure)
                    }
                ),
                materialFunctionMutations: [], animationMutations: [],
                layerMutations: [], inputBatchOverflowed: false
            )
        } else {
            cursorResult = launchContext.sceneScriptCursorProgram.dispatch(
                batch: cursorBatch, frame: sceneScriptFrame,
                userPropertiesJSON: userPropertiesJSON,
                effectivePropertyValues: launchContext.liveState.effectiveValues,
                propertyRevision: launchContext.liveState.revision, audioSpectrum: audioSpectrum
            )
        }
        if cursorResult.inputBatchOverflowed {
            NSLog(
                "MWX SceneScript VM: event=cursor batch=rejected reason=event-budget fallback=previous-current"
            )
        }
        for (target, failure) in cursorResult.failures {
            NSLog(
                "MWX SceneScript VM: target=%@ event=cursor failure=%@ code=%@ fallback=previous-current",
                String(describing: target),
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
        // Cursor callbacks run before update; preserve that order for writes
        // to the same owner/bone in one frame.
        let ownerEffects = cursorResult.ownerEffects
            + coordinatedSceneScript.ownerEffects
        let layerMutationCount = ownerEffects.reduce(0) {
            $0 + $1.layerMutations.count
        }
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow, timing.frameIndex == 0 {
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
        // A later callback can fail after this owner has already produced
        // cursor effects. Reject the whole owner result before admission.
        // A pure visible return has no side-effect bundle. Seed its rejection
        // here so its value, any earlier cursor writes and storage readers
        // share the same fixed-point owner decision as an explicit setter.
        let unpreparedParticleVisibilityOwners: Set<SceneDynamicTarget> = Set([
            sceneScriptVectorResult.values,
            sceneScriptStringResult.values,
            sceneScriptResult.values,
        ].flatMap { values in
            values.compactMap { entry -> SceneDynamicTarget? in
                guard case let .layer(layerID, .visibility) = entry.key,
                      case .bool(true) = entry.value,
                      !self.layerVisibilityResourcesPrepared(
                        layerID: layerID, context: launchContext
                      ) else { return nil }
                return entry.key
            }
        })
        let executionFailedOwners = Set(cursorResult.failures.keys)
            .union(sceneScriptVectorResult.failures.keys)
            .union(sceneScriptStringResult.failures.keys)
            .union(sceneScriptResult.failures.keys)
            .union(unpreparedParticleVisibilityOwners)
        // Visibility, instance alpha and explicit emission consume one admitted frame value.
        // Other authored setters retain their existing next-cadence contract.
        func frameScriptValues(_ admitted: [SceneScriptOwnerEffects],
                               excluding rejected: Set<SceneDynamicTarget>)
            -> [SceneDynamicTarget: SceneDynamicValue] {
            var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
            for mutation in admitted.filter({ !rejected.contains($0.ownerTarget) }).flatMap(\.layerMutations)
                where !mutation.isDynamic && mutation.kind == .upsert {
                if mutation.fields.contains(.visibility) {
                    values[.layer(layerID: mutation.layerID, field: .visibility)] = .bool(mutation.visible)
                }
                if mutation.fields.contains(.particleAlpha) {
                    values[.particle(layerID: mutation.layerID, field: .alpha)] = .scalar(mutation.particleAlpha)
                }
            }
            values.merge(sceneScriptStringResult.values.filter { !rejected.contains($0.key) }) { _, current in current }
            values.merge(sceneScriptResult.values.filter { !rejected.contains($0.key) }) { _, current in current }
            values.merge(sceneScriptVectorResult.values.filter { !rejected.contains($0.key) }) { _, current in current }
            return values
        }
        var settledTimelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
        func timelineProjection(_ admitted: [SceneScriptOwnerEffects],
                             excluding rejected: Set<SceneDynamicTarget>)
            -> Result<[SceneDynamicTarget: SceneDynamicValue], SceneTimelinePlaybackFailure> {
            let eligible = admitted.filter { !rejected.contains($0.ownerTarget) }
            return launchContext.timelinePlaybackRuntime.preview(
                eligible.flatMap(\.animationMutations), sceneTime: timing.sceneTime
            ).map { timeline in
                settledTimelineValues = timeline
                return timeline
            }
        }
        func rejectTimelineProjection(_ failure: SceneTimelinePlaybackFailure,
                                      from admitted: [SceneScriptOwnerEffects]) -> Set<SceneDynamicTarget> {
            let failed = admitted.filter { owner in
                guard !owner.animationMutations.isEmpty else { return false }
                if case let .unknownTarget(target) = failure {
                    return owner.animationMutations.contains { $0.target == target }
                }
                return true
            }
            runtimeValidationFailures += failed.map { .init(ownerTarget: $0.ownerTarget,
                subsystem: .animation, commandCount: $0.animationMutations.count,
                reason: String(describing: failure)) }
            return Set(failed.map(\.ownerTarget))
        }
        let fixedPoint = launchContext.sceneScriptDynamicLayerRuntime
            .preflightOwnerEffectsToFixedPoint(
                ownerEffects, excludingOwners: executionFailedOwners,
                particleObservations: particleObservations,
                validateParticleTransitions: { transitions in
                    transitions.isEmpty || (!self.surfaces.isEmpty
                        && Set(self.surfaces.keys) == self.preparedSurfaceIDs
                        && self.surfaces.values.allSatisfy {
                            $0.scriptGeneration == launchContext.propertyVectorScriptProgram.generation
                                && $0.metalView.validateParticlePlaybackTransitions(transitions)
                        })
                },
                rejectingParticleTransitions: { transitions, admitted, rejected in
                    guard transitions.contains(where: { $0.action == .emit }) else { return [] }
                    guard let particleEmission else {
                        return Set(admitted.filter { !$0.particlePlaybackCommands.isEmpty }.map(\.ownerTarget))
                    }
                    let timeline: [SceneDynamicTarget: SceneDynamicValue]
                    switch timelineProjection(admitted, excluding: rejected) {
                    case let .success(projected): timeline = projected
                    case let .failure(failure):
                        return rejectTimelineProjection(failure, from: admitted)
                    }
                    let resolution = SceneDynamicSnapshotResolver().resolve(
                        frameIndex: timing.frameIndex, generation: 0, index: definitionIndex,
                        base: preliminarySceneScriptResolution, timelineValues: timeline,
                        sceneScriptValues: frameScriptValues(admitted, excluding: rejected))
                    guard let failed = particleEmission.prepare(transitions, visibility: { instance in
                        self.surfaces[instance.surfaceID]?.metalView.particlePlaybackVisibility(
                            layerID: instance.layerID, dynamicValues: resolution.snapshot)
                    }) else { return [] }
                    return Set(admitted.filter { bundle in
                        bundle.particlePlaybackCommands.contains {
                            $0.callbackEpoch == failed.callbackEpoch && $0.ordinal == failed.ordinal
                        }
                    }.map(\.ownerTarget))
                },
                rejectingDependents: {
                    launchContext.sceneScriptStorageSession?.resolveRejectedOwners($0) ?? $0
                }
            ) { admitted in
                let failures = SceneScriptOwnerEffectsRuntimeValidation
                    .failures(
                        for: admitted,
                        timelineRuntime: launchContext.timelinePlaybackRuntime,
                        textureAnimationRuntime:
                            launchContext.textureAnimationPlaybackRuntime,
                        videoRegistry: videoTextureSourceRegistry,
                        timing: timing,
                        puppetAnimationRuntime: launchContext.puppetAnimationPlaybackRuntime
                    )
                runtimeValidationFailures.append(contentsOf: failures)
                let unpreparedParticleOwners = admitted.compactMap {
                    owner -> SceneDynamicTarget? in
                    guard owner.layerMutations.contains(where: { mutation in
                        guard !mutation.isDynamic, mutation.kind == .upsert else { return false }
                        if mutation.fields.contains(.particleAlpha),
                           launchContext.particleLayerIDs.contains(mutation.layerID),
                           !self.particleVisibilityResourcesPrepared(
                                layerID: mutation.layerID, context: launchContext
                           ) { return true }
                        return mutation.fields.contains(.visibility) && mutation.visible
                            && !self.layerVisibilityResourcesPrepared(
                                layerID: mutation.layerID, context: launchContext
                            )
                    }) else { return nil }
                    return owner.ownerTarget
                }
                let rejected = Set(failures.map(\.ownerTarget)).union(unpreparedParticleOwners)
                switch timelineProjection(admitted, excluding: rejected) {
                case .success: break
                case let .failure(failure):
                    return rejected.union(rejectTimelineProjection(failure, from: admitted))
                }
                return rejected
            }
        let admission = fixedPoint.admission
        let admittedOwnerEffects = admission.admittedEffects
        var rejectedOwnerTargets = fixedPoint.externallyRejectedOwners
        rejectedOwnerTargets.formUnion(admission.rejectedOwners.compactMap(
            \.ownerTarget
        ))
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow, timing.frameIndex == 0 {
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
            NSLog(
                "MWX SceneScript VM: %@=%d owner=%@ callback=rejected failure=%@ fallback=previous-current",
                failure.subsystem.rawValue,
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
        let textureAnimationCommands = admittedOwnerEffects.flatMap(
            \.textureAnimationCommands
        )
        // The preliminary snapshot already contains authored, user-property,
        // timeline, and stateful SceneScript lanes. Overlay only the current
        // admitted results so surface preparation does not walk every
        // definition a second time on the same frame.
        let sharedSurfaceResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: timing.frameIndex, generation: 0, index: definitionIndex,
            base: preliminarySceneScriptResolution, timelineValues: settledTimelineValues,
            sceneScriptValues: frameScriptValues(admittedOwnerEffects, excluding: rejectedOwnerTargets))
        let materialFunctionMutations = admittedOwnerEffects.flatMap(\.materialFunctionMutations)
        let pendingEvaluation = evaluationTransaction.prepare(
            frameIndex: timing.frameIndex, resolution: sharedSurfaceResolution
        )
        let installsEmission = admission.layerPlan.particleTransitions.contains { $0.action == .emit }
        if installsEmission {
            particleEmission?.install()
            let stopped = Set(admission.layerPlan.particleTransitions.filter { $0.action == .stop }.map(\.layerID))
            for (id, surface) in surfaces {
                surface.metalView.clearStoppedParticlePlaybackCaches(stopped)
#if DEBUG
                surface.metalView.logExplicitParticleInstall(admission.layerPlan.particleTransitions,
                    frame: timing.frameIndex, surface: id)
#endif
            }
        }
        for (displayID, surface) in surfaces {
            guard let mediaThumbnailSnapshot =
                mediaThumbnailSnapshots[displayID] else {
                continue
            }
            let resolvedDynamicValues = pendingEvaluation.resolution.snapshot
#if DEBUG
            let dynamicValues: SceneDynamicSnapshot
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
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
                if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
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
            surface.metalView.applyParticlePlaybackTransitions(admission.layerPlan.particleTransitions)
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                for transition in admission.layerPlan.particleTransitions {
                    NSLog("MWX DEBUG SCENE: phase=particle-transition-consumed frame=%llu layer=%d revision=%llu action=%d surface=%u",
                          timing.frameIndex, transition.layerID, transition.revision, transition.action.rawValue, displayID)
                }
            }
#endif
            surface.didSubmitSimulationFrame = false
            surface.metalView.updateSimulation(
                timing: timing, dynamicValues: dynamicValues,
                puppetAnimationFrame: puppetAnimationFrame,
                layerTopology: layerTopology,
                dynamicTextFieldsByLayerID:
                    launchContext.frameSchema.dynamicTextFieldsByLayerID,
                materialFunctionMutations: materialFunctionMutations,
                puppetBoneMutations: puppetBoneMutations,
                mediaThumbnail: mediaThumbnailSnapshot,
                mediaInput: mediaInput,
                audioSpectrum: audioSpectrum,
                performanceTelemetry: SceneDesktopWallpaperHost.usesDebugEvidenceWindow
                    ? SceneFramePerformanceTelemetry.debugEvidence : nil
            )
        }
        let attempt = renderSurfaces()
        restoreSceneScriptProgramFrameState(
            launchContext, sceneScriptProgramFrameState,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        commitSimulatedSceneFrame(
            launchContext,
            pendingEvaluation: pendingEvaluation,
            pendingSharedLayerAlpha: pendingSharedLayerAlpha,
            animationMutations: animationMutations,
            videoCommands: videoCommands,
            textureAnimationCommands: textureAnimationCommands,
            puppetAnimationCommands: admittedOwnerEffects.flatMap(\.puppetAnimationCommands),
            scriptFrame: sceneScriptFrame,
            timing: timing,
            layerPlan: admission.layerPlan,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        SceneAudioSpectrumInbox.shared.commitFrame(audioSpectrumFrame)
        // This cadence consumed its inputs regardless of GPU availability.
        // A later cadence samples fresh state; it never replays this VM frame.
        return attempt
    }
    /// Refresh resources for the already-consumed cadence only when the whole
    /// current surface cohort is terminal. A partial completion is not a draw.
    @discardableResult
    func refreshPausedMediaPublications() -> Bool {
        let publications = surfaces.mapValues { $0.metalView.pausedMediaThumbnailPublication() }
        guard !surfaces.isEmpty, Set(surfaces.keys) == preparedSurfaceIDs,
              Set(surfaces.values.map { $0.metalView.simulationFrameIndex }).count == 1,
              publications.values.allSatisfy({ $0 != nil }),
              Set(publications.values.compactMap { $0?.generation }).count == 1 else { return false }
        var changed = false
        for (id, surface) in surfaces {
            if let publication = publications[id] ?? nil,
               surface.metalView.refreshPausedMediaThumbnail(publication) {
                surface.didSubmitSimulationFrame = false
                changed = true
            }
        }
        return changed
    }

    private func renderSurfaces() -> SceneFrameDriverAttempt {
        var frameOutcomes: [SceneMetalRenderer.FrameOutcome] = []
        frameOutcomes.reserveCapacity(surfaces.count)
        for (displayID, surface) in surfaces {
            if sceneClock.isPaused && surface.didSubmitSimulationFrame { continue }
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let frameOutcome = surface.metalView.renderFrame(
                performanceTelemetry: SceneDesktopWallpaperHost.usesDebugEvidenceWindow
                    ? SceneFramePerformanceTelemetry.debugEvidence : nil
            )
            if onFirstFrameCompletion != nil || sceneClock.isPaused,
               case let .prepared(candidate) = frameOutcome {
                if sceneClock.isPaused { surface.pendingPausedFrame = candidate }
                candidate.whenCompleted { [weak self, weak surface, weak candidate] succeeded in
                    DispatchQueue.main.async {
                        guard let self, let surface, self.surfaces[displayID] === surface else { return }
                        self.onFirstFrameCompletion?(displayID, succeeded)
                        guard self.surfaces[displayID] === surface,
                              let candidate, surface.pendingPausedFrame === candidate else { return }
                        surface.pendingPausedFrame = nil
                        guard self.sceneClock.isPaused, !succeeded else { return }
                        surface.didSubmitSimulationFrame = false
                        self.scheduleFrameDriver(after: .dropped, scheduledDeadline: CACurrentMediaTime())
                    }
                }
            }
            frameOutcomes.append(frameOutcome)
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
               surface.metalView.simulationFrameIndex <= 2,
               case let .prepared(candidate) = frameOutcome {
                candidate.observeCompletion(frameIndex: surface.metalView.simulationFrameIndex, surfaceID: displayID)
            }
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
               debugRejectPreparedFrameOnce == surface.metalView.simulationFrameIndex,
               frameOutcomes.count == surfaces.count {
                debugRejectPreparedFrameOnce = nil
                if case let .prepared(candidate) = frameOutcome { candidate.cancel() }
                frameOutcomes[frameOutcomes.count - 1] = .dropped(
                    reasonCode: "debug-evidence-prepared-surface-rejected"
                )
                NSLog("MWX DEBUG SCENE: phase=surface-submission state=rejected frame=%llu surface=%u totalSurfaces=%d", surface.metalView.simulationFrameIndex, displayID, surfaces.count)
            }
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                SceneFramePerformanceTelemetry.debugEvidence.recordMainFrame(
                    duration: ProcessInfo.processInfo.systemUptime - mainFrameStart
                )
            }
#endif
            let outcomeIndex = frameOutcomes.count - 1
            let submitted = SceneMetalRenderer.submitPreparedFrame(frameOutcomes[outcomeIndex])
            frameOutcomes[outcomeIndex] = submitted
            if submitted.isSubmitted {
                surface.didSubmitSimulationFrame = true
                surface.metalView.commitPreparedMaterialAssetFrame()
                surface.metalView.commitPreparedFrameTexturePublication()
                surface.metalView.commitPreparedMediaThumbnailUpdate()
                surface.metalView.commitPreparedDynamicTextUpdate()
            } else {
                if frameOutcome.isPrepared { surface.pendingPausedFrame = nil }
                surface.metalView.discardPreparedMaterialAssetFrame()
                surface.metalView.discardPreparedFrameTexturePublication()
                surface.metalView.discardPreparedMediaThumbnailUpdate()
                surface.metalView.discardPreparedDynamicTextUpdate()
            }
        }
        // The shared provider version is resolved once. A failed surface may
        // not roll back a source already referenced by another submitted GPU.
        videoTextureSourceRegistry?.commitPreparedFrame()
        if sceneClock.isPaused && !surfaces.values.allSatisfy(\.didSubmitSimulationFrame) {
            return frameOutcomes.contains(where: \.isDeferred) ? .busy : .dropped
        }
        return frameOutcomes.contains(where: \.isSubmitted) ? .rendered : .dropped
    }
#if DEBUG
    private func logDebugDynamicLayerVisibilityIfChanged(
        descriptor: SceneRenderDescriptor,
        snapshot: SceneDynamicSnapshot
    ) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: descriptor,
            snapshot: snapshot
        )
        let records = descriptor.layers.compactMap { layer -> String? in
            let resolved = snapshot[.layer(layerID: layer.id, field: .visibility)]
            let value: Bool
            if let resolved, case let .bool(current) = resolved.value {
                value = current
            } else {
                value = layer.visible ?? true
            }
            return "layer=\(layer.id) source=\(resolved?.source.rawValue ?? "authored")"
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
}


extension SceneDesktopWallpaperSession {
    func particlePlaybackObservations(
        context: SceneDesktopWallpaperLaunchContext,
        committed: [Int: SceneParticlePlaybackSnapshot]
    ) -> [Int: SceneParticlePlaybackObservation] {
        guard !surfaces.isEmpty, Set(surfaces.keys) == preparedSurfaceIDs,
              surfaces.values.allSatisfy({ $0.scriptGeneration == context.propertyVectorScriptProgram.generation }) else { return [:] }
        var observations: [Int: SceneParticlePlaybackObservation] = [:]
        for layer in context.runtimeInput.renderDescriptor.layers where layer.contentKind == "particle" {
            let current = committed[layer.id] ?? .init()
            var live = false, pending = false, rearm = false, complete = true
            for surface in surfaces.values {
                guard let value = surface.metalView.particlePlaybackObservation(layerID: layer.id),
                      value.intent == current.intent, value.revision == current.revision else { complete = false; break }
                live = live || value.liveAny
                pending = pending || value.emissionPending
                rearm = rearm || value.rearmHasWork
            }
            if complete {
                observations[layer.id] = .init(liveAny: live, emissionPending: pending,
                    rearmHasWork: rearm, intent: current.intent, revision: current.revision)
            }
        }
        return observations
    }
}
