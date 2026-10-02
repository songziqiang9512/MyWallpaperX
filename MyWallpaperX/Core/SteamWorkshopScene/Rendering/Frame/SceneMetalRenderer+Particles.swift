import Metal
import simd

extension SceneMetalRenderer {
    func renderParticleBatches(
        _ batches: [SceneParticleDrawBatch],
        pipeline: SceneParticleMetalPipeline,
        model: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame,
        viewportSize: SIMD2<Float>,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        preparedDepth: StaticModelFrame.Depth? = nil,
        performanceObservations: inout [SceneParticlePerformanceObservation]?
    ) -> SceneParticleDepthTargetLease? {
        // Install completion ownership before the first draw.  A command can
        // cross the enqueue/commit boundary as soon as the shared renderer
        // seals the frame; registering here keeps every later slot mark out of
        // that unsafe window.
        var armedBuffers: Set<ObjectIdentifier> = []
        for batch in batches {
            let identity = ObjectIdentifier(batch.instanceBuffer)
            if armedBuffers.insert(identity).inserted,
               !batch.instanceBuffer.armSubmission(on: commandBuffer) {
                batches.forEach { _ = $0.instanceBuffer.cancelPending() }
                return nil
            }
        }
        let usesDepth = batches.contains { $0.renderState.requiresDepthAttachment }
        let targetExtent = mainPass.targetExtent
        let depthLease: SceneParticleDepthTargetLease?
        if let preparedDepth {
            depthLease = preparedDepth.lease
        } else {
            depthLease = usesDepth ? pipeline.acquireDepthTarget(
                width: targetExtent.width, height: targetExtent.height) : nil
        }
        guard !usesDepth || depthLease != nil else {
            batches.forEach { _ = $0.instanceBuffer.cancelPending() }
            return nil
        }
        var clearsDepth = usesDepth
        for batch in batches {
            let basis = cameraFrame.basis(
                for: batch.orientation,
                layerModel: model,
                orientationAxis: batch.orientationAxis ?? SIMD3<Float>(0, 0, 1)
            )
            let uniforms = SceneParticleLayerUniforms(
                viewProjection: cameraFrame.viewProjection(
                    usesPerspective: batch.usesPerspective
                ),
                layerModel: model,
                basis: basis,
                viewportSize: viewportSize,
                sizeIsWorldSpace: batch.sizeIsWorldSpace,
                viewBasis: cameraFrame.basis(for: .screen)
            )
            let didEncode: Bool
            if let refraction = batch.refraction {
                let captured = mainPass.withReadableTarget { target, buffer in
                    pipeline.snapshot(target: target, commandBuffer: buffer)
                }
                if let background = captured ?? nil,
                   let encoder = mainPass.encoder() {
                    didEncode = pipeline.drawRefraction(
                        texture: batch.texture,
                        binding: refraction,
                        background: background,
                        instances: batch.instanceBuffer,
                        uniforms: uniforms,
                        renderState: batch.renderState,
                        colorUVScale: batch.colorUVScale,
                        colorSampling: batch.colorSampling,
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
                let encoded = pipeline.draw(
                    texture: batch.texture,
                    instances: batch.instanceBuffer,
                    uniforms: uniforms,
                    renderState: batch.renderState,
                    colorUVScale: batch.colorUVScale,
                    colorSampling: batch.colorSampling,
                    usesDepthAttachment: usesDepth,
                    encoder: encoder
                )
                if encoded { clearsDepth = false }
                didEncode = encoded
            } else {
                didEncode = false
            }
            if didEncode {
                performanceObservations?.append(SceneParticlePerformanceObservation(
                    layerID: batch.layerID,
                    instanceCount: batch.instanceBuffer.count,
                    isRefraction: batch.refraction != nil
                ))
                // Reserve the slot for this command only after the pipeline
                // confirms that a draw was actually encoded.  The renderer's
                // outer defer handles a later preflight/seal rejection while
                // the command is still not enqueued.
                if !batch.instanceBuffer.markSubmitted(on: commandBuffer) {
                    // A completed/error command cannot own a slot. The draw
                    // was synchronous, so releasing this still-current
                    // candidate is safe only when the command is already
                    // terminal.  An enqueued/committed command may still be
                    // reading the instance buffer; leave that ownership alone
                    // and let its completion handler release the slot.
                    if commandBuffer.status == .completed
                        || commandBuffer.status == .error
                    {
                        _ = batch.instanceBuffer.cancelPending()
                    }
                }
            } else {
                _ = batch.instanceBuffer.cancelPending()
            }
        }
        return depthLease
    }
}
