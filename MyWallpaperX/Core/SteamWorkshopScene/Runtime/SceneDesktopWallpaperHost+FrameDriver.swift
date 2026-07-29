import AppKit
import QuartzCore

extension SceneDesktopWallpaperHost {
    func startFrameDriver() {
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
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
        let timing = sceneClock.advance(hostTime: CACurrentMediaTime(), wallDate: Date())
        let definitions = SceneDynamicDefinitionMerger.merge(
            propertyDefinitions: launchContext.runtimeInput.propertyBindingProgram.definitions,
            timelineProgram: launchContext.timelineProgram,
            textScriptProgram: launchContext.textScriptProgram
        )
        let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()
        let timelineValues = SceneTimelineRuntime.values(
            program: launchContext.timelineProgram, sceneTime: timing.sceneTime
        )
        let textScriptValues = SceneTextScriptRuntime.values(
            program: launchContext.textScriptProgram,
            wallDate: timing.wallDate
        )
        for surface in surfaces.values {
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let dynamicValues = surface.evaluationTransaction.evaluate(
                frameIndex: timing.frameIndex, definitions: definitions,
                userValues: launchContext.liveState.userValues,
                timelineValues: timelineValues,
                sceneScriptValues: textScriptValues
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
