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
        particleBatches: [SceneParticleDrawBatch],
        initialVideoPresentation: InitialVideoPresentation? = nil
    ) -> PreparedFrame {
        return PreparedFrame(commandBuffer: commandBuffer, initialVideoPresentation: initialVideoPresentation, submit: { present in
#if DEBUG
            if !SceneGPUStageTimestampHook.isSelected(commandBuffer) {
                encodeFrameReadback?(drawable.texture, commandBuffer)
            }
            SceneGPUStageTimestampHook.submitted(commandBuffer)
#else
            encodeFrameReadback?(drawable.texture, commandBuffer)
#endif
            if present {
                onDrawableWillPresent?(drawable)
                commandBuffer.present(drawable)
            } else {
                commandBuffer.addCompletedHandler { _ in withExtendedLifetime(drawable) {} }
            }
#if DEBUG
            if let effectExecutionTrace {
                effectExecutionTelemetry.observeSharedCommandBuffer(
                    for: effectExecutionTrace, on: commandBuffer
                )
            }
#endif
            if let particlePerformanceObservations {
#if DEBUG
                performanceTelemetry?.recordParticleSubmission(
                    particlePerformanceObservations, on: commandBuffer
                )
#endif

            }
#if DEBUG
            performanceTelemetry?.recordSubmitted(on: commandBuffer)
#endif

            compositionGroupRuntime?.arm()
            sourceUpdateTransaction.arm(on: commandBuffer)
            frameDepthLeases.forEach { $0.arm(on: commandBuffer) }
            reflectionFrame?.arm()
            modelFrame.arm(on: commandBuffer)
            mainPassForSubmission?.armCompositionPins()
            commandBuffer.commit()
            sourceUpdateTransaction.didSubmit()
        }, cancel: {
#if DEBUG
            SceneGPUStageTimestampHook.cancel(commandBuffer, reason: "prepared-frame-cancelled")
#endif
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
