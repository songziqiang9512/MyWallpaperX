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
        commandBuffer: MTLCommandBuffer
    ) -> SceneParticleDepthTargetLease? {
        let usesDepth = batches.contains { $0.renderState.requiresDepthAttachment }
        let targetExtent = mainPass.targetExtent
        let depthLease = usesDepth ? pipeline.acquireDepthTarget(
            width: targetExtent.width,
            height: targetExtent.height
        ) : nil
        guard !usesDepth || depthLease != nil else { return nil }
        var clearsDepth = usesDepth
        for batch in batches {
            let basis = particleBasis(
                for: batch,
                layerModel: model,
                cameraFrame: cameraFrame
            )
            let uniforms = SceneParticleLayerUniforms(
                viewProjection: cameraFrame.viewProjection(
                    usesPerspective: batch.usesPerspective
                ),
                layerModel: model,
                basis: basis,
                viewportSize: viewportSize
            )
            if let refraction = batch.refraction {
                let captured = mainPass.withReadableTarget { target, buffer in
                    pipeline.snapshot(target: target, commandBuffer: buffer)
                }
                guard let background = captured ?? nil,
                      let encoder = mainPass.encoder() else { continue }
                pipeline.drawRefraction(
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
            } else if let encoder = usesDepth
                ? mainPass.encoder(
                    depthTexture: depthLease?.texture,
                    clearsDepth: clearsDepth
                )
                : mainPass.encoder() {
                clearsDepth = false
                pipeline.draw(
                    texture: batch.texture,
                    instances: batch.instanceBuffer,
                    uniforms: uniforms,
                    renderState: batch.renderState,
                    colorUVScale: batch.colorUVScale,
                    colorSampling: batch.colorSampling,
                    usesDepthAttachment: usesDepth,
                    encoder: encoder
                )
            }
            batch.instanceBuffer.markSubmitted(on: commandBuffer)
        }
        return depthLease
    }
}
