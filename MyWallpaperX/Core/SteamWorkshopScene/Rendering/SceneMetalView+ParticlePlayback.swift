import Foundation

extension SceneMetalView {
    var hasParticleAudioConsumer: Bool {
        particlePlayback?.hasAudioConsumer == true
    }

    func advanceParticles(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame
    ) -> [SceneParticleDrawBatch] {
        particlePlayback?.advance(
            by: timing.simulationFrameTime,
            dynamicValues: dynamicValues,
            pointerLocalPositions: renderer.particlePointerLocalPositions(
                frameContext: frameContext,
                cameraFrame: cameraFrame
            ),
            audioSpectrum: frameContext.audioSpectrum
        ) ?? []
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
