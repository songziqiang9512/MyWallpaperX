import Foundation

extension SceneMetalView {
    func commitPreparedParticleFrame() {
        particlePlayback?.commitPreparedFrame()
    }

    func discardPreparedParticleFrame() {
        particlePlayback?.discardPreparedFrame()
    }

    var hasParticleAudioConsumer: Bool {
        particlePlayback?.hasAudioConsumer == true
    }

    func advanceParticles(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) -> [SceneParticleDrawBatch] {
        guard let particlePlayback else { return [] }
        performanceTelemetry?.beginStage("particle-prepare-frame")
        particlePlayback.prepareFrame()
        performanceTelemetry?.endStage("particle-prepare-frame")
        performanceTelemetry?.beginStage("particle-pointer-projection")
        let pointerLocalPositions = renderer.particlePointerLocalPositions(
            frameContext: frameContext,
            cameraFrame: cameraFrame,
            demandedLayerIDs: particlePlayback.pointerControlPointLayerIDs
        )
        performanceTelemetry?.endStage("particle-pointer-projection")
        performanceTelemetry?.beginStage("particle-advance")
        let batches = particlePlayback.advance(
            by: timing.simulationFrameTime,
            dynamicValues: dynamicValues,
            pointerLocalPositions: pointerLocalPositions,
            audioSpectrum: frameContext.audioSpectrum
        )
        performanceTelemetry?.endStage("particle-advance")
        return batches
    }

    func teardownParticlePlayback(reason: SceneGraphExecutionResetReason) {
        defer { particlePlayback = nil }
        guard let observation = particlePlayback?.teardown(reason: reason.rawValue) else {
            return
        }
        let snapshot = observation.snapshotBeforeTeardown
        NSLog(
            "MWX Particle: lifecycle=teardown id=%@ reason=%@ layers=%d rootSystems=%d childSystems=%d rootParticles=%d childParticles=%d batches=%d route=generic-only",
            observation.lifecycleIdentity.uuidString,
            observation.reason,
            snapshot.activeLayerCount,
            snapshot.rootSystemCount,
            snapshot.childSystemCount,
            snapshot.rootParticleCount,
            snapshot.childParticleCount,
            observation.batchCountBeforeTeardown
        )
    }
}
