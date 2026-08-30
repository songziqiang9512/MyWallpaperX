import CoreGraphics
import Metal
import simd

enum SceneResolvedMaterialDependencyInputResolution {
    case ready(SceneDependencyEffectInput)
    case unavailable(reasonCode: String)
    case invalid(reasonCode: String)
}

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
    private let namedGraphOutputPublicationTelemetry = SceneGPUCompletionTelemetry(
        phase: "named-graph-output-publication"
    )
    private let visibleGraphOutputPublicationTelemetry = SceneGPUCompletionTelemetry(
        phase: "visible-graph-output-publication"
    )
    private let bindingTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-binding")
    private var reservationFrameEpoch: UInt64?
    private var reservationsByProviderLayerID: [Int: EffectTargetReservation] = [:]
#if DEBUG
    private var debugCaptureFault = SceneDependencyCaptureFault()
#endif

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

    func requiresForwardCapture(for providerLayerID: Int) -> Bool {
        plan.bindingsByConsumerLayerID.values.contains {
            $0.providerLayerID == providerLayerID
                && $0.requiresForwardCapture
        }
    }

    func requiresGraphOutputCapture(for providerLayerID: Int) -> Bool {
        plan.requiredGraphOutputProviderLayerIDs.contains(providerLayerID)
    }

    /// Verifies that every prepared provider output can be copied into its
    /// independently reserved named target. The reservation must remain a
    /// distinct texture because graph target allocation is free to reuse a
    /// provider's final texture for a later transaction in the same frame.
    func installPreparedGraphOutputs(
        _ outputsByLayerID: [Int: MTLTexture],
        frameEpoch: UInt64
    ) -> Bool {
        synchronizeReservations(to: frameEpoch)
        for providerLayerID in plan.requiredGraphOutputProviderLayerIDs.sorted() {
            guard let output = outputsByLayerID[providerLayerID] else {
                // A frame-local visual fallback deliberately leaves the
                // provisional reservation unpublished so dependants take the
                // existing ordinary provider-miss path.
                continue
            }
            guard let reservation = reservationsByProviderLayerID[providerLayerID],
                  reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == providerLayerID,
                  reservation.width == output.width,
                  reservation.height == output.height,
                  reservation.texture !== output,
                  reservation.texture.pixelFormat == output.pixelFormat,
                  output.textureType == .type2D,
                  output.sampleCount == 1,
                  output.mipmapLevelCount == 1,
                  output.usage.contains(.renderTarget),
                  output.usage.contains(.shaderRead) else {
                return false
            }
        }
        return true
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
        frameEpoch: UInt64,
        failureReason: inout String?
    ) -> SceneDependencyEffectInput? {
        guard frameEpoch > 0 else {
            failureReason = "frame-epoch-invalid"
            return nil
        }
        guard binding.providerLayerID == providerLayer.id else {
            failureReason = "provider-layer-mismatch"
            return nil
        }
        guard plan.bindingsByConsumerLayerID[binding.consumerLayerID] == binding else {
            failureReason = "binding-not-planned"
            return nil
        }
        guard let extent = Self.captureExtent(
            binding: binding,
            providerLayer: providerLayer,
            providerTexture: providerTexture,
            providerCandidate: providerCandidate,
            layerMVP: layerMVP,
            viewportSize: viewportSize,
            failureReason: &failureReason
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
                failureReason = "reservation-mismatch"
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
                failureReason = "target-pool-unavailable"
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

    /// Resolves a dependency already reserved by unified frame preparation.
    /// A valid reservation without a same-frame publication is an ordinary
    /// provider visual failure; reservation/epoch/object drift remains an
    /// integrity rejection and must not enter the local passthrough path.
    func resolvedMaterialEffectInputResolution(
        for consumerLayerID: Int,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneResolvedMaterialDependencyInputResolution {
        guard let binding = plan.bindingsByConsumerLayerID[consumerLayerID] else {
            return .invalid(reasonCode: "external-primary-binding-missing")
        }
        let frameEpoch = textureRegistry.frameEpoch
        guard frameEpoch > 0 else {
            return .invalid(reasonCode: "external-primary-frame-epoch-invalid")
        }
        synchronizeReservations(to: frameEpoch)
        guard let reservation = reservationsByProviderLayerID[
            binding.providerLayerID
        ] else {
            return .invalid(reasonCode: "external-primary-reservation-missing")
        }
        guard reservation.frameEpoch == frameEpoch,
              reservation.providerLayerID == binding.providerLayerID,
              reservation.kind == binding.kind else {
            return .invalid(reasonCode: "external-primary-reservation-mismatch")
        }
        let identity = SceneFrameTextureIdentity.namedLayerTarget(
            SceneNamedTextureReference(
                providerLayerID: binding.providerLayerID,
                variant: .primary
            )
        )
        guard let texture = textureRegistry.texture(for: identity) else {
            return .unavailable(
                reasonCode: "external-primary-provider-capture-unavailable"
            )
        }
        guard texture === reservation.texture else {
            return .invalid(reasonCode: "external-primary-publication-mismatch")
        }
        return .ready(makeEffectInput(
            binding: binding,
            frameEpoch: frameEpoch,
            texture: texture
        ))
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
        usesAuthoredLayerColor: Bool = true,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        pipeline: SceneImageLayerPipeline,
        textureRegistry: SceneFrameTextureRegistry,
        mainPass: SceneMainPassEncoder
    ) -> Bool? {
        guard plan.requiredProviderLayerIDs.contains(layer.id) else { return nil }
        guard !plan.requiredGraphOutputProviderLayerIDs.contains(layer.id) else {
            return false
        }
#if DEBUG
        if debugCaptureFault.shouldDropCapture(
            for: layer.id,
            orderedProviderLayerIDs: plan.requiredProviderLayerIDs.sorted()
        ) {
            captureTelemetry.recordFailure(layerID: layer.id)
            NSLog(
                "MWX DEBUG SCENE: phase=named-provider-capture-fault state=dropped provider=%d reason=debug-evidence-injected-capture-failure",
                layer.id
            )
            return false
        }
#endif
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
        var captureFailureReason: String?
        guard let binding = providerBindings.first,
              providerBindings.allSatisfy({ $0.kind == binding.kind }),
              let extent = Self.captureExtent(
                  binding: binding,
                  providerLayer: layer,
                  providerTexture: sourceTexture,
                  providerCandidate: sourceCandidate,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize,
                  failureReason: &captureFailureReason
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
        case .imageLayerBlend, .visibleImageGraphOutput:
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
                uniforms.sourceSampling = SIMD2(
                    sourceCandidate.sampling.imageLayerUniformMode,
                    0
                )
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
        case .resolvedMaterial:
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
        case .solidLayer:
            guard let sourceTexture else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            var uniforms = SceneLayerFragmentUniforms.neutral()
            uniforms.alpha = max(0, Float(layer.alpha ?? 1))
            let color = usesAuthoredLayerColor
                ? SIMD3(layer.colorRGB ?? [], fill: 1)
                : SIMD3(repeating: 1)
            uniforms.tint = SIMD4(color.x, color.y, color.z, 1)
            uniforms.textureFrame0 = SceneTextureUVTransform.identity.uniform0
            uniforms.textureFrame1 = SceneTextureUVTransform.identity.uniform1
            encoded = mainPass.encodeOffscreen { commandBuffer in
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
        }
        if encoded {
            textureRegistry.set(.ready(target), for: identity)
#if DEBUG
            if debugCaptureFault.observeSuccessfulCapture(for: layer.id) {
                NSLog(
                    "MWX DEBUG SCENE: phase=named-provider-capture-fault state=recovered provider=%d frameEpoch=%llu",
                    layer.id,
                    frameEpoch
                )
            }
#endif
        }
        return encoded
    }

    /// Publishes an effectful provider's unified graph output into the exact
    /// named-target reservation. The graph runtime remains the producer and
    /// this registry remains the sole same-frame provider publication owner.
    func publishGraphOutputIfRequired(
        layerID: Int,
        texture: MTLTexture,
        textureRegistry: SceneFrameTextureRegistry,
        commandBuffer: MTLCommandBuffer
    ) -> Bool? {
        guard plan.requiredGraphOutputProviderLayerIDs.contains(layerID) else {
            return nil
        }
        guard let publicationTelemetry = graphOutputPublicationTelemetry(
            for: layerID
        ) else { return false }
        let frameEpoch = textureRegistry.frameEpoch
        synchronizeReservations(to: frameEpoch)
        guard let reservation = reservationsByProviderLayerID[layerID],
              reservation.frameEpoch == frameEpoch,
              reservation.providerLayerID == layerID,
              reservation.texture !== texture,
              reservation.width == texture.width,
              reservation.height == texture.height,
              reservation.texture.pixelFormat == texture.pixelFormat,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.mipmapLevelCount == 1,
              texture.usage.contains(.renderTarget),
              texture.usage.contains(.shaderRead),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            publicationTelemetry.recordFailure(layerID: layerID)
            return false
        }
        blit.label = "Scene named graph publication layer=\(layerID)"
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: texture.width,
                height: texture.height,
                depth: 1
            ),
            to: reservation.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        let identity = SceneFrameTextureIdentity.namedLayerTarget(
            SceneNamedTextureReference(
                providerLayerID: layerID,
                variant: .primary
            )
        )
        textureRegistry.set(.ready(reservation.texture), for: identity)
        guard textureRegistry.texture(for: identity) === reservation.texture else {
            publicationTelemetry.recordFailure(layerID: layerID)
            return false
        }
        publicationTelemetry.record(
            layerID: layerID,
            encoded: true,
            on: commandBuffer
        )
        return true
    }

    private func graphOutputPublicationTelemetry(
        for providerLayerID: Int
    ) -> SceneGPUCompletionTelemetry? {
        let kinds = Set(plan.bindingsByConsumerLayerID.values.compactMap {
            $0.providerLayerID == providerLayerID ? $0.kind : nil
        })
        guard kinds.count == 1, let kind = kinds.first else { return nil }
        return kind == .visibleImageGraphOutput
            ? visibleGraphOutputPublicationTelemetry
            : namedGraphOutputPublicationTelemetry
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
        viewportSize: CGSize,
        failureReason: inout String?
    ) -> (width: Int, height: Int)? {
        switch binding.kind {
        case .imageLayerBlend, .visibleImageGraphOutput:
            guard binding.providerLayerID == providerLayer.id,
                  let providerTexture,
                  let providerCandidate,
                  isExactImageProviderCandidate(
                      providerCandidate,
                      matching: providerTexture
                  ) else {
                failureReason = "image-provider-invalid"
                return nil
            }
            return normalizedExtent(
                width: providerTexture.width,
                height: providerTexture.height
            )
        case .resolvedMaterial:
            guard let utility = providerLayer.utilityLayer,
                  let geometry = SceneCaptureGeometryResolver.resolve(
                      kind: utility.kind,
                      layerMVP: layerMVP,
                      viewportSize: viewportSize
                  ) else {
                failureReason = "resolved-material-geometry-invalid"
                return nil
            }
            return normalizedExtent(
                width: Int(geometry.pixelSize.width.rounded(.up)),
                height: Int(geometry.pixelSize.height.rounded(.up))
            )
        case .solidLayer:
            guard binding.providerLayerID == providerLayer.id else {
                failureReason = "provider-layer-mismatch"
                return nil
            }
            guard let providerTexture else {
                failureReason = "solid-provider-texture-missing"
                return nil
            }
            return normalizedExtent(
                width: providerTexture.width,
                height: providerTexture.height
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
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback,
              candidate.axisAlignedMappedUVScale(
                  expectedPurpose: .premultipliedColor
              ) != nil,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.usage.contains(.shaderRead) else {
            return false
        }
        return true
    }
}
