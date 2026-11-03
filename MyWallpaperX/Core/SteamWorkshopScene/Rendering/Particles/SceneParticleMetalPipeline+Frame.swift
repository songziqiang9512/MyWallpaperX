import Metal
import simd

extension SceneParticleMetalPipeline {
    func drawBatches(
        _ batches: [PreparedBatch],
        model: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame,
        layerUsesPerspective: Bool = false,
        viewportSize: SIMD2<Float>,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        preparedDepth: SceneParticleDepthTargetPool.Acquisition? = nil,
        performanceObservations: inout [SceneParticlePerformanceObservation]?
    ) -> SceneParticleDepthTargetLease? {
        // Install completion ownership before the first draw.  A command can
        // cross the enqueue/commit boundary as soon as the shared renderer
        // seals the frame; registering here keeps every later slot mark out of
        // that unsafe window.
        for batch in batches {
            if !batch.instanceBuffer.armSubmission(on: commandBuffer) {
                batches.forEach { _ = $0.instanceBuffer.cancelPending() }
                return nil
            }
        }
        let usesDepth = batches.contains { $0.draw.renderState.depthWriteEnabled }
        let targetExtent = mainPass.targetExtent
        let depthLease: SceneParticleDepthTargetLease?
        if usesDepth {
            let acquisition = preparedDepth ?? acquireDepthTarget(
                width: targetExtent.width, height: targetExtent.height, on: commandBuffer
            )
            switch acquisition {
            case let .acquired(lease): depthLease = lease
            case .busyOtherFrame, .currentFrameCapacityExceeded, .invalidExtent, .allocationFailed:
                depthLease = nil
            }
        } else {
            depthLease = nil
        }
        guard !usesDepth || depthLease != nil else {
            batches.forEach { _ = $0.instanceBuffer.cancelPending() }
            return nil
        }
        var clearsDepth = usesDepth
        for prepared in batches {
            let batch = prepared.draw
            let instanceBuffer = prepared.instanceBuffer
            let uniforms = cameraFrame.particleUniforms(
                layerModel: model,
                orientation: batch.orientation,
                orientationAxis: batch.orientationAxis,
                usesPerspective: batch.usesPerspective,
                usesSceneCamera: batch.renderState.usesSceneCamera,
                inheritsNativeSceneCamera: batch.inheritsNativeSceneCamera,
                layerUsesPerspective: layerUsesPerspective,
                viewportSize: viewportSize,
                sizeIsWorldSpace: batch.sizeIsWorldSpace
            )
            let didEncode: Bool
            if let refraction = batch.refraction {
                let captured = mainPass.withReadableTarget { target, buffer in
                    snapshot(target: target, commandBuffer: buffer)
                }
                if let background = captured ?? nil,
                   let encoder = mainPass.encoder(
                       depthTexture: depthLease?.texture,
                       clearsDepth: clearsDepth
                   ) {
                    didEncode = drawRefraction(
                        texture: batch.texture,
                        binding: refraction,
                        background: background,
                        instances: instanceBuffer,
                        uniforms: uniforms,
                        renderState: batch.renderState,
                        colorUVScale: batch.colorUVScale,
                        colorSampling: batch.colorSampling,
                        usesDepthAttachment: usesDepth,
                        encoder: encoder
                    )
                } else {
                    didEncode = false
                }
            } else if let encoder = usesDepth
                ? mainPass.encoder(
                    depthTexture: depthLease?.texture,
                    clearsDepth: clearsDepth
                )
                : mainPass.encoder() {
                didEncode = draw(
                    texture: batch.texture,
                    instances: instanceBuffer,
                    uniforms: uniforms,
                    renderState: batch.renderState,
                    colorUVScale: batch.colorUVScale,
                    colorSampling: batch.colorSampling,
                    usesDepthAttachment: usesDepth,
                    encoder: encoder
                )
            } else {
                didEncode = false
            }
            if didEncode {
                clearsDepth = false
#if DEBUG
                performanceObservations?.append(SceneParticlePerformanceObservation(
                    layerID: batch.layerID,
                    instanceCount: instanceBuffer.count,
                    isRefraction: batch.refraction != nil
                ))
#endif
                // Reserve the slot for this command only after the pipeline
                // confirms that a draw was actually encoded.  The renderer's
                // outer defer handles a later preflight/seal rejection while
                // the command is still not enqueued.
                if !instanceBuffer.markSubmitted(on: commandBuffer) {
                    // A completed/error command cannot own a slot. The draw
                    // was synchronous, so releasing this still-current
                    // candidate is safe only when the command is already
                    // terminal.  An enqueued/committed command may still be
                    // reading the instance buffer; leave that ownership alone
                    // and let its completion handler release the slot.
                    if commandBuffer.status == .completed
                        || commandBuffer.status == .error
                    {
                        _ = instanceBuffer.cancelPending()
                    }
                }
            } else {
                _ = instanceBuffer.cancelPending()
            }
        }
        return depthLease
    }
}
