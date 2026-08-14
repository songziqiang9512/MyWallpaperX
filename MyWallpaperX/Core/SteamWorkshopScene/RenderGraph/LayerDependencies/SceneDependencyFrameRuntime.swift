import CoreGraphics
import Metal
import simd

final class SceneDependencyFrameRuntime {
    private struct EffectTargetReservation {
        let providerLayerID: Int
        let texture: MTLTexture
        let width: Int
        let height: Int
        let frameEpoch: UInt64
    }

    private let plan: SceneDependencyRenderPlan
    private let targetPool: SceneNamedRenderTargetPool
    private let captureTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-capture")
    private let bindingTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-binding")
    private var reservationFrameEpoch: UInt64?
    private var reservationsByProviderLayerID: [Int: EffectTargetReservation] = [:]

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int>,
        verifiedXRayStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey> = [],
        device: MTLDevice
    ) {
        self.plan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            verifiedXRayStageKeys: verifiedXRayStageKeys
        )
        self.targetPool = SceneNamedRenderTargetPool(device: device)
    }

    func requiresEffect(for consumerLayerID: Int) -> Bool {
        plan.requiredEffectConsumerLayerIDs.contains(consumerLayerID)
    }

    func requiresCapture(for providerLayerID: Int) -> Bool {
        plan.requiredProviderLayerIDs.contains(providerLayerID)
    }

    func blocksStaticLayerSourcePassthrough(for layerID: Int) -> Bool {
        plan.blocksStaticLayerSourcePassthrough(for: layerID)
    }

    func reserveEffectInput(
        for binding: SceneDependencyRenderPlan.Binding,
        providerLayer: SceneRenderDescriptor.Layer,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        frameEpoch: UInt64
    ) -> SceneDependencyEffectInput? {
        guard frameEpoch > 0,
              binding.providerLayerID == providerLayer.id,
              plan.bindingsByConsumerLayerID[binding.consumerLayerID] == binding,
              let geometry = SceneCaptureGeometryResolver.resolve(
                  kind: providerLayer.utilityLayer?.kind ?? .composition,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ), let extent = Self.normalizedExtent(
                  width: Int(geometry.pixelSize.width.rounded(.up)),
                  height: Int(geometry.pixelSize.height.rounded(.up))
              ) else {
            return nil
        }
        synchronizeReservations(to: frameEpoch)

        let texture: MTLTexture
        if let reservation = reservationsByProviderLayerID[providerLayer.id] {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == providerLayer.id,
                  reservation.width == extent.width,
                  reservation.height == extent.height else {
                return nil
            }
            texture = reservation.texture
        } else {
            guard let reservedTexture = targetPool.texture(
                      for: providerLayer.id,
                      width: extent.width,
                      height: extent.height
                  ), reservedTexture.width == extent.width,
                  reservedTexture.height == extent.height else {
                return nil
            }
            reservationsByProviderLayerID[providerLayer.id] = EffectTargetReservation(
                providerLayerID: providerLayer.id,
                texture: reservedTexture,
                width: extent.width,
                height: extent.height,
                frameEpoch: frameEpoch
            )
            texture = reservedTexture
        }

        return makeEffectInput(
            binding: binding,
            frameEpoch: frameEpoch,
            texture: texture
        )
    }

    func effectInput(
        for consumerLayerID: Int,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneDependencyEffectInput? {
        guard let binding = plan.bindingsByConsumerLayerID[consumerLayerID] else {
            return nil
        }
        let frameEpoch = textureRegistry.frameEpoch
        synchronizeReservations(to: frameEpoch)
        let identity = SceneFrameTextureIdentity.namedLayerTarget(SceneNamedTextureReference(
            providerLayerID: binding.providerLayerID,
            variant: .primary
        ))
        guard let texture = textureRegistry.texture(for: identity) else { return nil }
        if let reservation = reservationsByProviderLayerID[binding.providerLayerID] {
            guard reservation.frameEpoch == frameEpoch,
                  texture === reservation.texture else { return nil }
        }
        return makeEffectInput(
            binding: binding,
            frameEpoch: frameEpoch,
            texture: texture
        )
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
        let frameEpoch = textureRegistry.frameEpoch
        synchronizeReservations(to: frameEpoch)
        let identity = SceneFrameTextureIdentity.namedLayerTarget(SceneNamedTextureReference(
            providerLayerID: layer.id,
            variant: .primary
        ))
        let reservation = reservationsByProviderLayerID[layer.id]
        if reservation == nil, textureRegistry.texture(for: identity) != nil {
            return true
        }
        let captureKind = layer.utilityLayer?.kind ?? .composition
        guard let geometry = SceneCaptureGeometryResolver.resolve(
                  kind: captureKind,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ), let extent = Self.normalizedExtent(
                  width: Int(geometry.pixelSize.width.rounded(.up)),
                  height: Int(geometry.pixelSize.height.rounded(.up))
              ) else {
            captureTelemetry.recordFailure(layerID: layer.id)
            return false
        }
        let target: MTLTexture
        if let reservation {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == layer.id,
                  reservation.width == extent.width,
                  reservation.height == extent.height,
                  reservation.texture.width == extent.width,
                  reservation.texture.height == extent.height else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            if let publishedTexture = textureRegistry.texture(for: identity) {
                guard publishedTexture === reservation.texture else {
                    captureTelemetry.recordFailure(layerID: layer.id)
                    return false
                }
                return true
            }
            target = reservation.texture
        } else {
            guard let pooledTarget = targetPool.texture(
                      for: layer.id,
                      width: extent.width,
                      height: extent.height
                  ) else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            target = pooledTarget
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

    private func makeEffectInput(
        binding: SceneDependencyRenderPlan.Binding,
        frameEpoch: UInt64,
        texture: MTLTexture
    ) -> SceneDependencyEffectInput {
        SceneDependencyEffectInput(
            consumerLayerID: binding.consumerLayerID,
            providerLayerID: binding.providerLayerID,
            variant: .primary,
            slot: binding.slot,
            blendMode: binding.blendMode,
            frameEpoch: frameEpoch,
            texture: texture
        )
    }

    private func synchronizeReservations(to frameEpoch: UInt64) {
        guard reservationFrameEpoch != frameEpoch else { return }
        reservationFrameEpoch = frameEpoch
        reservationsByProviderLayerID.removeAll(keepingCapacity: true)
    }

    private static func normalizedExtent(
        width: Int,
        height: Int
    ) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let longestEdge = max(width, height)
        guard longestEdge > SceneNamedRenderTargetPool.maximumDimension else {
            return (width, height)
        }
        let scale = Double(SceneNamedRenderTargetPool.maximumDimension)
            / Double(longestEdge)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    private static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
}
