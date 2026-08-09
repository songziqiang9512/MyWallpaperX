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
}
