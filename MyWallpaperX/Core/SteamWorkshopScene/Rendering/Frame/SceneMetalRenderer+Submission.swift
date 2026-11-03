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
        particleBatches: [SceneParticleMetalPipeline.PreparedBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        initialVideoPresentation: InitialVideoPresentation? = nil
    ) -> PreparedFrame {
        let compositionSurface: ((UInt32, ObjectIdentifier) -> Void)?
#if DEBUG
        if let effectExecutionTrace, effectExecutionTrace.isCompositionSelected {
            compositionSurface = { displayID, identity in
                effectExecutionTrace.setCompositionSurface(displayID: displayID,
                    identity: String(UInt(bitPattern: identity)))
            }
        } else { compositionSurface = nil }
#else
        compositionSurface = nil
#endif
        return PreparedFrame(commandBuffer: commandBuffer, initialVideoPresentation: initialVideoPresentation, observeCompositionSurface: compositionSurface, submit: { present in
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
                effectExecutionTrace.setCompositionPresentRequested(present)
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
            if let effectExecutionTrace {
                effectExecutionTelemetry.recordCompositionCancellation(for: effectExecutionTrace)
            }
#endif
            imageCompositor.cancelUnsubmittedResolvedMaterialFrame(on: commandBuffer)
            sourceUpdateTransaction.cancel()
            compositionGroupRuntime?.cancel()
            reflectionFrame?.cancel()
            modelFrame.cancel()
            mainPassForSubmission?.cancelCompositionPins()
            frameDepthLeases.forEach { $0.cancel() }
            particlePipeline?.cancel(particleBatches, on: commandBuffer)
            discardUnsubmittedFrameResources()
        })
    }
}
