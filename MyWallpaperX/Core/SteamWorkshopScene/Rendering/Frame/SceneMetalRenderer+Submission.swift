import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    /// Installs both resolution closures without running them. The caller
    /// transfers rollback ownership only after this candidate is returned.
    func makePreparedFrame(
        commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable,
        encodeFrameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)?,
        onDrawableWillPresent: ((CAMetalDrawable) -> Void)?,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        particlePerformanceObservations: [SceneParticlePerformanceObservation]?,
        performanceTelemetry: SceneFramePerformanceTelemetry?,
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime?,
        sourceUpdateTransaction: SceneSourceUpdateTransaction,
        frameDepthLeases: [SceneParticleDepthTargetLease],
        reflectionFrame: ReflectionFrame?,
        modelFrame: StaticModelFrame,
        mainPassForSubmission: SceneMainPassEncoder?,
        particleBatches: [SceneParticleDrawBatch]
    ) -> PreparedFrame {
        return PreparedFrame(commandBuffer: commandBuffer, submit: {
            encodeFrameReadback?(drawable.texture, commandBuffer)
            onDrawableWillPresent?(drawable)
            commandBuffer.present(drawable)
            if let effectExecutionTrace {
                effectExecutionTelemetry.observeSharedCommandBuffer(
                    for: effectExecutionTrace, on: commandBuffer
                )
            }
            if let particlePerformanceObservations {
                performanceTelemetry?.recordParticleSubmission(
                    particlePerformanceObservations, on: commandBuffer
                )
            }
            performanceTelemetry?.recordSubmitted(on: commandBuffer)
            compositionGroupRuntime?.arm()
            sourceUpdateTransaction.arm(on: commandBuffer)
            frameDepthLeases.forEach { $0.arm(on: commandBuffer) }
            reflectionFrame?.arm()
            modelFrame.arm(on: commandBuffer)
            mainPassForSubmission?.armCompositionPins()
            commandBuffer.commit()
            sourceUpdateTransaction.didSubmit()
        }, cancel: {
            imageCompositor.cancelUnsubmittedResolvedMaterialFrame(on: commandBuffer)
            sourceUpdateTransaction.cancel()
            compositionGroupRuntime?.cancel()
            reflectionFrame?.cancel()
            modelFrame.cancel()
            mainPassForSubmission?.cancelCompositionPins()
            frameDepthLeases.forEach { $0.cancel() }
            particleBatches.forEach {
                _ = $0.instanceBuffer.cancelUncommittedSubmission(on: commandBuffer)
                _ = $0.instanceBuffer.cancelPending()
            }
            discardUnsubmittedFrameResources()
        })
    }
}
