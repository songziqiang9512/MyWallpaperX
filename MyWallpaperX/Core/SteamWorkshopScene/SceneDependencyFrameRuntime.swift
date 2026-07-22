import CoreGraphics
import Metal
import simd

final class SceneDependencyFrameRuntime {
    private let plan: SceneDependencyRenderPlan
    private let targetPool: SceneNamedRenderTargetPool
    private let imageBlendRuntime: SceneImageBlendRuntime?
    private let captureTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-capture")
    private let bindingTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-binding")

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        device: MTLDevice
    ) {
        self.plan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs
        )
        self.targetPool = SceneNamedRenderTargetPool(device: device)
        self.imageBlendRuntime = SceneImageBlendRuntime(
            plan: SceneImageBlendRenderPlan(
                descriptor: descriptor,
                visibleLayerIDs: visibleLayerIDs
            ),
            device: device
        )
    }

    func requiresEffect(for consumerLayerID: Int) -> Bool {
        plan.requiredEffectConsumerLayerIDs.contains(consumerLayerID)
    }

    func requiresCapture(for providerLayerID: Int) -> Bool {
        plan.requiredProviderLayerIDs.contains(providerLayerID)
    }

    func effectInput(
        for consumerLayerID: Int,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneDependencyEffectInput? {
        guard let binding = plan.bindingsByConsumerLayerID[consumerLayerID],
              let texture = textureRegistry.texture(for: .namedLayerTarget(.init(
                  providerLayerID: binding.providerLayerID,
                  variant: .primary
              ))) else {
            return nil
        }
        return SceneDependencyEffectInput(texture: texture, blendMode: binding.blendMode)
    }

    func preparedSourceTexture(
        for consumerLayerID: Int,
        sourceTexture: MTLTexture,
        textureRegistry: SceneFrameTextureRegistry,
        mainPass: SceneMainPassEncoder
    ) -> MTLTexture {
        imageBlendRuntime?.preparedTexture(
            for: consumerLayerID,
            sourceTexture: sourceTexture,
            textureRegistry: textureRegistry,
            mainPass: mainPass
        ) ?? sourceTexture
    }

    func recordBindingIfRequired(
        for consumerLayerID: Int,
        encoded: Bool,
        on commandBuffer: MTLCommandBuffer
    ) {
        guard plan.bindingsByConsumerLayerID[consumerLayerID] != nil else { return }
        bindingTelemetry.record(layerID: consumerLayerID, encoded: encoded, on: commandBuffer)
    }

    func recordBindingFailure(for consumerLayerID: Int) {
        guard plan.requiredEffectConsumerLayerIDs.contains(consumerLayerID) else { return }
        bindingTelemetry.recordFailure(layerID: consumerLayerID)
    }

    @discardableResult
    func captureProviderIfRequired(
        layer: SceneRenderDescriptor.Layer,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        pipeline: SceneImageLayerPipeline,
        textureRegistry: SceneFrameTextureRegistry,
        mainPass: SceneMainPassEncoder
    ) -> Bool? {
        guard plan.requiredProviderLayerIDs.contains(layer.id) else { return nil }
        let identity = SceneFrameTextureIdentity.namedLayerTarget(SceneNamedTextureReference(
            providerLayerID: layer.id,
            variant: .primary
        ))
        guard textureRegistry.texture(for: identity) == nil else { return true }
        guard let utility = layer.utilityLayer,
              let geometry = SceneCaptureGeometryResolver.resolve(
                  kind: utility.kind,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ),
              let target = targetPool.texture(
                  for: layer.id,
                  width: Int(geometry.pixelSize.width.rounded(.up)),
                  height: Int(geometry.pixelSize.height.rounded(.up))
              ) else {
            captureTelemetry.recordFailure(layerID: layer.id)
            return false
        }

        var didObserveCommandBuffer = false
        let encoded = mainPass.withReadableTarget { sourceTexture, commandBuffer in
            didObserveCommandBuffer = true
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = target
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            descriptor.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: descriptor
            ) else {
                captureTelemetry.record(layerID: layer.id, encoded: false, on: commandBuffer)
                return false
            }
            var uniforms = SceneLayerFragmentUniforms.neutral()
            uniforms.textureFrame0 = geometry.sourceUV.uniform0
            uniforms.textureFrame1 = geometry.sourceUV.uniform1
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(
                texture: sourceTexture,
                shakeMaskTexture: nil,
                waterMaskTexture: nil,
                foliageMaskTexture: nil,
                auxMaskTexture: nil,
                dependencyTexture: nil,
                mvp: Self.fullTargetMVP,
                uniforms: uniforms,
                encoder: encoder
            )
            encoder.endEncoding()
            captureTelemetry.record(layerID: layer.id, encoded: true, on: commandBuffer)
            return true
        } ?? false
        if !didObserveCommandBuffer {
            captureTelemetry.recordFailure(layerID: layer.id)
        }
        if encoded {
            textureRegistry.set(.ready(target), for: identity)
        }
        return encoded
    }

    private static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
}
