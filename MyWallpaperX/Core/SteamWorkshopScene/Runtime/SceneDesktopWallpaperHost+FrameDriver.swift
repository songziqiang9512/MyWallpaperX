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
        }
        frameTimer?.invalidate()
        frameTimer = nil
        frameDriverDeadline = nil
        for surface in surfaces.values {
            surface.metalView.invalidateResolvedMaterialRuntime(reason: reason)
            surface.window.orderOut(nil)
            surface.window.close()
        }
        surfaces.removeAll()
#if DEBUG
        debugSurfaceReferenceFrames.removeAll(keepingCapacity: false)
#endif
        if clearContext {
            SceneAudioSpectrumInbox.shared.setDemand(false)
            sharedLayerAlphaRuntime = .init(program: .empty)
            audioScaledValueRuntime = .init(program: .empty)
#if DEBUG
            debugAudioScaledValueValues = [:]
            debugAudioScaledValueFrameIndex = 0
            debugAudioScaledValueGeneration = 0
            debugAudioScaledValueWasSilent = true
            debugDropDynamicValuesFrameIndex = nil
            debugDidDropDynamicValues = false
            debugDidLogDynamicValuesRecovery = false
#endif
            videoTextureSourceRegistry?.stop()
            videoTextureSourceRegistry = nil
            launchContext?.sceneScriptScalarProgram.invalidate()
            launchContext?.propertyVectorScriptProgram.invalidate()
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
            additionalDefinitions: launchContext.mediaPlaybackPlaceholderFadeProgram.bindings.map(
                \.definition
            ) + launchContext.mediaColorTransitionProgram.bindings.map(
                \.definition
            ) + launchContext.sharedLayerAlphaProgram.definitions
                + launchContext.launchOriginTransitionProgram.definitions
                + launchContext.hoverOriginTransitionProgram.definitions
                + launchContext.audioScaledValueProgram.definitions
                + launchContext.propertyVectorScriptProgram.definitions
                + launchContext.sceneScriptScalarProgram.definitions
        )
        let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()
        let timelineValues = SceneTimelineRuntime.values(
            program: launchContext.timelineProgram, sceneTime: timing.sceneTime
        )
        let mediaInput = SceneMediaThumbnailInbox.shared.latest()
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
        let mediaPlaybackPlaceholderFadeValues =
            mediaPlaybackPlaceholderFadeRuntime.values(
                playbackEventState: mediaInput.playbackState,
                frameTime: timing.simulationFrameTime
            )
        let mediaColorTransitionValues = mediaColorTransitionRuntime.values(
            effectivePropertyValues: launchContext.liveState.effectiveValues,
            mediaInput: mediaInput,
            frameTime: timing.simulationFrameTime
        )
        let sharedLayerAlphaValues = sharedLayerAlphaRuntime.values(
            effectivePropertyValues: launchContext.liveState.effectiveValues,
            frameTime: timing.simulationFrameTime
        )
        let audioScaledValueValues = audioScaledValueRuntime.values(
            audioSpectrum: audioSpectrum,
            frameTime: timing.simulationFrameTime
        )
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            debugAudioScaledValueValues = audioScaledValueValues
            debugAudioScaledValueFrameIndex = timing.frameIndex
            debugAudioScaledValueGeneration = audioSpectrum.generation
            debugAudioScaledValueWasSilent = audioSpectrum.isSilent
        }
#endif
        var commonSceneScriptValues = textScriptValues.merging(
            mediaPlaybackPlaceholderFadeValues,
            uniquingKeysWith: { textValue, _ in textValue }
        ).merging(
            mediaColorTransitionValues,
            uniquingKeysWith: { existing, _ in existing }
        ).merging(
            sharedLayerAlphaValues,
            uniquingKeysWith: { existing, _ in existing }
        ).merging(
            audioScaledValueValues,
            uniquingKeysWith: { existing, _ in existing }
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
        let sceneScriptVectorInputs = launchContext.propertyVectorScriptProgram.bindings
            .reduce(into: [SceneDynamicTarget: SceneDynamicValue]()) { inputs, binding in
                let target = binding.definition.target
                guard let resolved = preliminaryForSceneScript[target],
                      case .vector3 = resolved.value else { return }
                inputs[target] = resolved.value
            }
        let sceneScriptVectorResult = launchContext.propertyVectorScriptProgram.evaluate(
            inputs: sceneScriptVectorInputs,
            effectivePropertyValues: launchContext.liveState.effectiveValues,
            frame: SceneScriptFrameInput(timing: timing),
            layerSnapshot: preliminaryForSceneScript
        )
        for (target, failure) in sceneScriptVectorResult.failures {
            NSLog(
                "MWX SceneScript VM: target=%@ failure=%@ code=%@ fallback=previous-current",
                String(describing: target),
                String(describing: failure),
                failure.code
            )
        }
        commonSceneScriptValues.merge(
            sceneScriptVectorResult.values,
            uniquingKeysWith: { _, genericValue in genericValue }
        )
        let sceneScriptInputs = launchContext.sceneScriptScalarProgram.bindings.reduce(
            into: [SceneDynamicTarget: SceneDynamicValue]()
        ) { inputs, binding in
            guard let resolved = preliminaryForSceneScript[binding.target],
                  case .scalar = resolved.value else { return }
            inputs[binding.target] = resolved.value
        }
        let sceneScriptResult = launchContext.sceneScriptScalarProgram.evaluate(
            inputs: sceneScriptInputs,
            frame: SceneScriptFrameInput(timing: timing),
            userPropertiesJSON: launchContext.propertyVectorScriptProgram
                .userPropertiesJSON(
                    effectiveValues: launchContext.liveState.effectiveValues
                )
        )
        if !sceneScriptResult.failures.isEmpty {
            for (target, failure) in sceneScriptResult.failures {
                NSLog(
                    "MWX SceneScript VM: target=%@ failure=%@ code=%@ fallback=previous-current",
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
        for surface in surfaces.values {
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let currentLaunchOriginTransitionValues =
                surface.launchOriginTransitionRuntime.currentValues(
                    effectivePropertyValues:
                        launchContext.liveState.effectiveValues
                )
            let preliminarySceneScriptValues = commonSceneScriptValues.merging(
                currentLaunchOriginTransitionValues,
                uniquingKeysWith: { existing, _ in existing }
            )
            let needsInteractionSnapshot =
                !launchContext.launchOriginTransitionProgram.cohorts.isEmpty
                || !launchContext.hoverOriginTransitionProgram.cohorts.isEmpty
            let preliminary: SceneDynamicSnapshot? = needsInteractionSnapshot
                ? SceneDynamicSnapshotResolver().resolve(
                    frameIndex: timing.frameIndex,
                    generation: 0,
                    definitions: definitions,
                    userValues: launchContext.liveState.userValues,
                    timelineValues: timelineValues,
                    sceneScriptValues: preliminarySceneScriptValues
                ).snapshot
                : nil
            let clickedOwners = preliminary.map {
                surface.metalView.launchOriginInteractionOwnerLayerIDs(
                    program: launchContext.launchOriginTransitionProgram,
                    timing: timing,
                    dynamicValues: $0
                )
            } ?? []
            let launchOriginTransitionValues =
                surface.launchOriginTransitionRuntime.values(
                    clickedOwnerLayerIDs: clickedOwners,
                    primaryButtonIsDown:
                        surface.metalView.pointerState.isPrimaryButtonDown,
                    effectivePropertyValues:
                        launchContext.liveState.effectiveValues
                )
            let hoverOriginTransitionValues: [SceneDynamicTarget: SceneDynamicValue]
            if let preliminary,
               !launchContext.hoverOriginTransitionProgram.cohorts.isEmpty {
                let hovered = surface.metalView.hoveredOriginOwnerLayerIDs(
                    program: launchContext.hoverOriginTransitionProgram,
                    timing: timing,
                    dynamicValues: preliminary
                )
                hoverOriginTransitionValues =
                    surface.hoverOriginTransitionRuntime.values(
                        hoveredOwnerLayerIDs: hovered,
                        effectivePropertyValues:
                            launchContext.liveState.effectiveValues
                    )
            } else {
                hoverOriginTransitionValues = [:]
            }
            let resolvedDynamicValues = surface.evaluationTransaction.evaluate(
                frameIndex: timing.frameIndex, definitions: definitions,
                userValues: launchContext.liveState.userValues,
                timelineValues: timelineValues,
                sceneScriptValues: commonSceneScriptValues.merging(
                    launchOriginTransitionValues,
                    uniquingKeysWith: { existing, _ in existing }
                ).merging(
                    hoverOriginTransitionValues,
                    uniquingKeysWith: { existing, _ in existing }
                )
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
                materialFunctionMutations:
                    sceneScriptVectorResult.materialFunctionMutations
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
