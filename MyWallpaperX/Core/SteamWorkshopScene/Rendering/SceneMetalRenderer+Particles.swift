import Metal
import simd

extension SceneMetalRenderer {
    func renderParticleBatches(
        _ batches: [SceneParticleDrawBatch],
        pipeline: SceneParticleMetalPipeline,
        model: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer
    ) {
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
                basis: basis
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
                    blendMode: batch.blendMode,
                    colorUVScale: batch.colorUVScale,
                    encoder: encoder
                )
            } else if let encoder = mainPass.encoder() {
                pipeline.draw(
                    texture: batch.texture,
                    instances: batch.instanceBuffer,
                    uniforms: uniforms,
                    blendMode: batch.blendMode,
                    colorUVScale: batch.colorUVScale,
                    encoder: encoder
                )
            }
            batch.instanceBuffer.markSubmitted(on: commandBuffer)
        }
    }
}
