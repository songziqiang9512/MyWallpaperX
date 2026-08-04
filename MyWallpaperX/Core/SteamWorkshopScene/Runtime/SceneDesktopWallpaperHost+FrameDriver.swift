import AppKit
import QuartzCore

extension SceneDesktopWallpaperHost {
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
        for surface in surfaces.values {
            surface.metalView.invalidateResolvedMaterialRuntime(reason: reason)
            surface.window.orderOut(nil)
            surface.window.close()
        }
        surfaces.removeAll()
        if clearContext {
            SceneAudioSpectrumInbox.shared.setDemand(false)
            videoTextureSourceRegistry?.stop()
            videoTextureSourceRegistry = nil
            launchContext = nil
#if DEBUG
            debugPointerOverride = nil
#endif
        }
    }

    func startFrameDriver() {
        frameTimer?.invalidate()
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            NSLog(
                "MWX DEBUG SCENE: phase=frame-driver-start paused=%@",
                sceneClock.isPaused ? "true" : "false"
            )
        }
#endif
        guard !sceneClock.isPaused else {
            frameTimer = nil
            return
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
#if DEBUG
        if Self.usesDebugEvidenceWindow {
            NSLog(
                "MWX DEBUG SCENE: phase=frame-driver-ready timer=%@",
                timer.isValid ? "active" : "inactive"
            )
        }
#endif
        renderFrame()
    }

    private func renderFrame() {
        guard let launchContext else { return }
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
        let timing = sceneClock.advance(hostTime: CACurrentMediaTime(), wallDate: wallDate)
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
            additionalDefinitions: launchContext.timeOfDayEffectScriptProgram.bindings.map(
                \.definition
            )
        )
        let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()
        let timelineValues = SceneTimelineRuntime.values(
            program: launchContext.timelineProgram, sceneTime: timing.sceneTime
        )
        let textScriptValues = SceneTextScriptRuntime.values(
            program: launchContext.textScriptProgram,
            wallDate: timing.wallDate
        )
        let timeOfDayEffectScriptValues = SceneTimeOfDayEffectScriptRuntime.values(
            program: launchContext.timeOfDayEffectScriptProgram,
            wallDate: timing.wallDate
        )
        for surface in surfaces.values {
            guard !surface.metalView.shouldDeferResolvedMaterialFrame else {
                continue
            }
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let dynamicValues = surface.evaluationTransaction.evaluate(
                frameIndex: timing.frameIndex, definitions: definitions,
                userValues: launchContext.liveState.userValues,
                timelineValues: timelineValues,
                sceneScriptValues: textScriptValues.merging(
                    timeOfDayEffectScriptValues,
                    uniquingKeysWith: { textValue, _ in textValue }
                )
            ).snapshot
            surface.metalView.renderFrame(
                timing: timing, dynamicValues: dynamicValues, audioSpectrum: audioSpectrum,
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
