import Metal

final class SceneImageBlendRuntime {
    private struct PreparedTarget {
        let source: MTLTexture
        let provider: MTLTexture
        let providerGeneration: UInt64
        let target: MTLTexture
    }

    private let plan: SceneImageBlendRenderPlan
    private let pipeline: SceneImageBlendPipeline
    private let targetPool: SceneNamedRenderTargetPool
    private let telemetry = SceneGPUCompletionTelemetry(phase: "image-blend")
    private var preparedTargets: [Int: PreparedTarget] = [:]

    init?(
        plan: SceneImageBlendRenderPlan,
        device: MTLDevice
    ) {
        guard let pipeline = SceneImageBlendPipeline(device: device) else { return nil }
        self.plan = plan
        self.pipeline = pipeline
        self.targetPool = SceneNamedRenderTargetPool(device: device)
    }

    func preparedTexture(
        for consumerLayerID: Int,
        sourceTexture: MTLTexture,
        textureRegistry: SceneFrameTextureRegistry,
        mainPass: SceneMainPassEncoder
    ) -> MTLTexture? {
        guard let operation = plan.operationsByConsumerLayerID[consumerLayerID],
              let resolution = textureRegistry.resolve(operation.textureSelection),
              let target = targetPool.texture(
                  for: consumerLayerID,
                  width: sourceTexture.width,
                  height: sourceTexture.height
              ) else {
            return nil
        }
        let providerTexture = resolution.texture
        if let prepared = preparedTargets[consumerLayerID],
           prepared.source === sourceTexture,
           prepared.provider === providerTexture,
           prepared.providerGeneration == resolution.generation,
           prepared.target === target {
            return prepared.target
        }
        let encoded = mainPass.encodeOffscreen { commandBuffer in
            let encoded = pipeline.encode(
                source: sourceTexture,
                blend: providerTexture,
                target: target,
                multiply: operation.multiply,
                alphaMultiply: operation.alphaMultiply,
                writesAlpha: operation.writesAlpha,
                commandBuffer: commandBuffer
            )
            telemetry.record(
                layerID: consumerLayerID,
                encoded: encoded,
                on: commandBuffer
            )
            return encoded
        }
        guard encoded else { return nil }
        preparedTargets[consumerLayerID] = PreparedTarget(
            source: sourceTexture,
            provider: providerTexture,
            providerGeneration: resolution.generation,
            target: target
        )
        return target
    }
}
