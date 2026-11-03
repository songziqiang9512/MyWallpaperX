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
#if DEBUG
        var observationBatchOrdinal = 0
#endif
        for prepared in batches {
            let batch = prepared.draw
            let instanceBuffer = prepared.instanceBuffer
#if DEBUG
            let observeBindings: ((MTLTexture, SceneParticleRefractionBinding.NormalArguments?, MTLTexture?, Int) -> Void)?
            if let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                let target = mainPass.compositionTarget
                let depth = depthLease.map { SceneCompositionTextureObservation($0.texture, role: "particle-depth") }
                let ordinal = observationBatchOrdinal
                let layerID = batch.layerID
                let colorUV = [batch.colorUVScale.x, batch.colorUVScale.y]
                let sampling = String(describing: batch.colorSampling)
                var batchDetails = ["batchOrdinal": String(ordinal),
                        "particlePath": batch.particlePath,
                        "childTemplateIndex": batch.childTemplateIndex.map(String.init) ?? "root",
                        "rendererComponentIndex": batch.debugRendererComponentIndex.map(String.init) ?? "implicit",
                        "rendererKind": batch.debugRendererKind ?? "unknown"]
                if let depth { batchDetails["depthTextureToken"] = depth.textureToken }
                observeBindings = { color, normal, background, count in
                    var details = batchDetails
                    details["instanceCount"] = String(count)
                    var source = SceneCompositionTextureObservation(color, role: "particle-color")
                    source.uv = colorUV
                    source.sampling = sampling
                    trace.recordComposition(.init(kind: "particle", layerID: layerID, slot: 0,
                        source: source, target: target, details: details))
                    if let normal {
                        var source = SceneCompositionTextureObservation(normal.texture, role: "particle-normal")
                        source.uv = [normal.uvScale.x, normal.uvScale.y]
                        source.sampling = String(describing: normal.sampling)
                        var normalDetails = details
                        normalDetails["usesParticleFrames"] = String(normal.usesParticleFrames)
                        normalDetails["authoredFormat"] = normal.authoredFormat.map { String($0.rawValue) } ?? "unknown"
                        trace.recordComposition(.init(kind: "particle", layerID: layerID, slot: 1,
                            source: source, target: target, details: normalDetails))
                    }
                    if let background {
                        trace.recordComposition(.init(kind: "particle", layerID: layerID, slot: 2,
                            source: .init(background, role: "particle-background"), target: target, details: details))
                    }
                }
            } else { observeBindings = nil }
            observationBatchOrdinal += 1
#else
            let observeBindings: ((MTLTexture, SceneParticleRefractionBinding.NormalArguments?, MTLTexture?, Int) -> Void)? = nil
#endif
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
                    let background = snapshot(target: target, commandBuffer: buffer)
#if DEBUG
                    if let background, let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                        trace.recordComposition(.init(kind: "particle-background-copy", layerID: batch.layerID,
                            source: .init(target, role: "main-color"), target: .init(background, role: "particle-background"),
                            access: "copy-source", outcome: "encoded"))
                    }
#endif
                    return background
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
                        encoder: encoder, observeBindings: observeBindings
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
                    encoder: encoder, observeBindings: observeBindings
                )
            } else {
                didEncode = false
            }
#if DEBUG
            if !didEncode, let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                trace.recordComposition(.init(kind: "particle", layerID: batch.layerID,
                    target: mainPass.compositionTarget, outcome: "failed", reason: "particle-draw-not-encoded",
                    details: ["childTemplateIndex": batch.childTemplateIndex.map(String.init) ?? "root",
                        "batchOrdinal": String(observationBatchOrdinal - 1)]))
            }
#endif
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
