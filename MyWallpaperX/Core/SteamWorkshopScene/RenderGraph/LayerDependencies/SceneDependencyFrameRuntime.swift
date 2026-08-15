import CoreGraphics
import Metal
import simd

final class SceneDependencyFrameRuntime {
    private struct EffectTargetReservation {
        let providerLayerID: Int
        let kind: SceneDependencyRenderPlan.Binding.Kind
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
        providerTexture: MTLTexture?,
        providerCandidate: SceneTextureCandidate?,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        frameEpoch: UInt64
    ) -> SceneDependencyEffectInput? {
        guard frameEpoch > 0,
              binding.providerLayerID == providerLayer.id,
              plan.bindingsByConsumerLayerID[binding.consumerLayerID] == binding,
              let extent = Self.captureExtent(
                  binding: binding,
                  providerLayer: providerLayer,
                  providerTexture: providerTexture,
                  providerCandidate: providerCandidate,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ) else {
            return nil
        }
        synchronizeReservations(to: frameEpoch)

        let texture: MTLTexture
        if let reservation = reservationsByProviderLayerID[providerLayer.id] {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == providerLayer.id,
                  reservation.kind == binding.kind,
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
                kind: binding.kind,
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
        sourceTexture: MTLTexture?,
        sourceCandidate: SceneTextureCandidate?,
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
        let providerBindings = plan.bindingsByConsumerLayerID.values.filter {
            $0.providerLayerID == layer.id
        }
        guard let binding = providerBindings.first,
              providerBindings.allSatisfy({ $0.kind == binding.kind }),
              let extent = Self.captureExtent(
                  binding: binding,
                  providerLayer: layer,
                  providerTexture: sourceTexture,
                  providerCandidate: sourceCandidate,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ) else {
            captureTelemetry.recordFailure(layerID: layer.id)
            return false
        }
        let target: MTLTexture
        if let reservation {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == layer.id,
                  reservation.kind == binding.kind,
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

        let encoded: Bool
        switch binding.kind {
        case .imageLayerBlend:
            guard let sourceTexture,
                  let sourceCandidate,
                  Self.isExactImageProviderCandidate(
                      sourceCandidate,
                      matching: sourceTexture
                  ) else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            encoded = mainPass.encodeOffscreen { commandBuffer in
                var uniforms = SceneLayerFragmentUniforms.neutral()
                uniforms.textureFrame0 = sourceCandidate.uvTransform.uniform0
                uniforms.textureFrame1 = sourceCandidate.uvTransform.uniform1
                let didEncode = SceneOffscreenEffectRenderer.captureSource(
                    sourceTexture: sourceTexture,
                    target: target,
                    sourceUniforms: uniforms,
                    pipeline: pipeline,
                    commandBuffer: commandBuffer
                )
                captureTelemetry.record(
                    layerID: layer.id,
                    encoded: didEncode,
                    on: commandBuffer
                )
                return didEncode
            }
        case .clippingMask, .proceduralNoiseLayer:
            guard let utility = layer.utilityLayer,
                  let geometry = SceneCaptureGeometryResolver.resolve(
                      kind: utility.kind,
                      layerMVP: layerMVP,
                      viewportSize: viewportSize
                  ) else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            var didObserveCommandBuffer = false
            encoded = mainPass.withReadableTarget { mainTexture, commandBuffer in
                didObserveCommandBuffer = true
                var uniforms = SceneLayerFragmentUniforms.neutral()
                uniforms.textureFrame0 = geometry.sourceUV.uniform0
                uniforms.textureFrame1 = geometry.sourceUV.uniform1
                let didEncode = SceneOffscreenEffectRenderer.captureSource(
                    sourceTexture: mainTexture,
                    target: target,
                    sourceUniforms: uniforms,
                    pipeline: pipeline,
                    commandBuffer: commandBuffer
                )
                captureTelemetry.record(
                    layerID: layer.id,
                    encoded: didEncode,
                    on: commandBuffer
                )
                return didEncode
            } ?? false
            if !didObserveCommandBuffer {
                captureTelemetry.recordFailure(layerID: layer.id)
            }
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

    private static func captureExtent(
        binding: SceneDependencyRenderPlan.Binding,
        providerLayer: SceneRenderDescriptor.Layer,
        providerTexture: MTLTexture?,
        providerCandidate: SceneTextureCandidate?,
        layerMVP: simd_float4x4,
        viewportSize: CGSize
    ) -> (width: Int, height: Int)? {
        switch binding.kind {
        case .imageLayerBlend:
            guard binding.providerLayerID == providerLayer.id,
                  let providerTexture,
                  let providerCandidate,
                  isExactImageProviderCandidate(
                      providerCandidate,
                      matching: providerTexture
                  ) else { return nil }
            return normalizedExtent(
                width: providerTexture.width,
                height: providerTexture.height
            )
        case .clippingMask, .proceduralNoiseLayer:
            guard let utility = providerLayer.utilityLayer,
                  let geometry = SceneCaptureGeometryResolver.resolve(
                      kind: utility.kind,
                      layerMVP: layerMVP,
                      viewportSize: viewportSize
                  ) else { return nil }
            return normalizedExtent(
                width: Int(geometry.pixelSize.width.rounded(.up)),
                height: Int(geometry.pixelSize.height.rounded(.up))
            )
        }
    }

    private static func isExactImageProviderCandidate(
        _ candidate: SceneTextureCandidate,
        matching texture: MTLTexture
    ) -> Bool {
        guard candidate.texture === texture,
              candidate.purpose == .premultipliedColor,
              candidate.content.isResolved,
              candidate.sampling == .linearClamp,
              candidate.axisAlignedMappedUVScale(
                  expectedPurpose: .premultipliedColor
              ) == SIMD2(repeating: 1),
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.usage.contains(.shaderRead) else {
            return false
        }
        return true
    }
}
