import CoreGraphics
import Metal
import simd

enum SceneResolvedMaterialDependencyInputResolution {
    case ready(SceneDependencyEffectInput)
    case unavailable(reasonCode: String)
    case invalid(reasonCode: String)
}

final class SceneDependencyFrameRuntime {
    enum GraphOutputPublicationRole {
        /// The authored visible layer publishes before its normal main-pass
        /// composite consumes the same graph execution ticket.
        case visibleMainLoop
        /// A hidden provider prepass publishes as its terminal output.
        case namedProviderPrepass
    }

    struct EffectTargetReservation {
        enum Kind: Hashable {
            case image
            case resolvedMaterial
            case solidLayer

            init(_ bindingKind: SceneDependencyRenderPlan.Binding.Kind) {
                switch bindingKind {
                case .imageLayerBlend, .visibleImageGraphOutput:
                    self = .image
                case .resolvedMaterial:
                    self = .resolvedMaterial
                case .solidLayer:
                    self = .solidLayer
                }
            }
        }

        let providerLayerID: Int
        /// Provider-target shape. Consumer route kinds remain on each binding;
        /// both image binding forms publish the same provider-owned texture.
        let kind: Kind
        let texture: MTLTexture
        let width: Int
        let height: Int
        let frameEpoch: UInt64
    }

    let plan: SceneDependencyRenderPlan
    private let targetPool: SceneNamedRenderTargetPool
    private let captureTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-capture")
    private let namedGraphOutputPublicationTelemetry = SceneGPUCompletionTelemetry(
        phase: "named-graph-output-publication"
    )
    private let visibleGraphOutputPublicationTelemetry = SceneGPUCompletionTelemetry(
        phase: "visible-graph-output-publication"
    )
    let bindingTelemetry = SceneGPUCompletionTelemetry(phase: "named-target-binding")
    private var reservationFrameEpoch: UInt64?
    var demandedGraphOutputProviderLayerIDs: Set<Int> = []
    var reservationsByProviderLayerID: [Int: EffectTargetReservation] = [:]
#if DEBUG
    private var debugCaptureFault = SceneDependencyCaptureFault()
    var debugPreparedOutputInstallFailureRecorded = false
#endif

    init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int>,
        verifiedXRayStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey> = [],
        admittedResolvedMaterialReferences: Set<SceneDependencyRenderPlan.Reference> = [],
        device: MTLDevice
    ) {
        self.plan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            verifiedXRayStageKeys: verifiedXRayStageKeys,
            admittedResolvedMaterialReferences:
                admittedResolvedMaterialReferences
        )
        self.targetPool = SceneNamedRenderTargetPool(device: device)
    }

    func requiresEffect(for consumerLayerID: Int) -> Bool {
        plan.requiredEffectConsumerLayerIDs.contains(consumerLayerID)
    }

    func requiresCapture(for providerLayerID: Int) -> Bool {
        plan.requiredProviderLayerIDs.contains(providerLayerID)
    }

    func requiresGraphOutputCapture(for providerLayerID: Int) -> Bool {
        plan.requiredGraphOutputProviderLayerIDs.contains(providerLayerID)
    }

    func requiresDemandedGraphOutputCapture(for providerLayerID: Int) -> Bool {
        demandedGraphOutputProviderLayerIDs.contains(providerLayerID)
    }

    func resolvedMaterialPreparationOrder(
        authoredLayerIDs: [Int]
    ) -> [Int]? {
        plan.resolvedMaterialPreparationOrder(
            authoredLayerIDs: authoredLayerIDs
        )
    }

    func resolvedMaterialExecutionLayerIDs(
        visibleRootLayerIDs: Set<Int>,
        availableExecutionLayerIDs: Set<Int>
    ) -> Set<Int> {
        plan.resolvedMaterialExecutionLayerIDs(
            visibleRootLayerIDs: visibleRootLayerIDs,
            availableExecutionLayerIDs: availableExecutionLayerIDs
        )
    }

    func forwardDependencyPreparationOrder(
        authoredLayerIDs: [Int],
        activeExecutionLayerIDs: Set<Int>,
        activeStaticModelConsumerLayerIDs: Set<Int> = []
    ) -> [Int]? {
        plan.forwardDependencyPreparationOrder(
            authoredLayerIDs: authoredLayerIDs,
            activeExecutionLayerIDs: activeExecutionLayerIDs,
            activeStaticModelConsumerLayerIDs:
                activeStaticModelConsumerLayerIDs
        )
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
        preparedOutputExtent: (width: Int, height: Int)? = nil,
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
        guard plan.bindingsByConsumerLayerID[binding.consumerLayerID] == binding
            || plan.aggregateBindingIsPlanned(binding) else {
            failureReason = "binding-not-planned"
            return nil
        }
        // Aggregate members are an ordered, image-primary vector. Keep the
        // strict shape check at reservation time so a forged/partially
        // reconstructed member cannot acquire a named target and only fail
        // later during graph execution.
        if plan.aggregateBindingIsPlanned(binding) {
            guard binding.consumerLayerID != binding.providerLayerID,
                  binding.referenceSlots == [binding.slot],
                  binding.kind == .imageLayerBlend,
                  binding.blendMode == 0,
                  binding.requiresResolvedMaterialProgram else {
                failureReason = "aggregate-binding-shape-mismatch"
                return nil
            }
        }
        guard let extent = Self.captureExtent(
            binding: binding,
            providerLayer: providerLayer,
            providerTexture: providerTexture,
            providerCandidate: providerCandidate,
            layerMVP: layerMVP,
            viewportSize: viewportSize,
            preparedOutputExtent: preparedOutputExtent,
            failureReason: &failureReason
        ) else {
            return nil
        }
        synchronizeReservations(to: frameEpoch)
        if plan.requiredGraphOutputProviderLayerIDs.contains(providerLayer.id) {
            demandedGraphOutputProviderLayerIDs.insert(providerLayer.id)
        }

        let texture: MTLTexture
        if let reservation = reservationsByProviderLayerID[providerLayer.id] {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == providerLayer.id,
                  reservation.kind == .init(binding.kind),
                  reservation.width == extent.width,
                  reservation.height == extent.height,
                  Self.isValidDependencyTexture(reservation.texture) else {
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
                  reservedTexture.height == extent.height,
                  Self.isValidDependencyTexture(reservedTexture) else {
                failureReason = "target-pool-unavailable"
                return nil
            }
            reservationsByProviderLayerID[providerLayer.id] = EffectTargetReservation(
                providerLayerID: providerLayer.id,
                kind: .init(binding.kind),
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
        let reference = SceneNamedTextureReference(
            providerLayerID: binding.providerLayerID,
            variant: .primary
        )
        guard let texture = textureRegistry.completeNamedLayerTargetTexture(
            reference: reference,
            frameEpoch: frameEpoch
        ) else { return nil }
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

    /// Resolves every publication in a multi-provider aggregate in authored
    /// slot order. Missing or mismatched members reject the whole aggregate so
    /// execution cannot silently consume a partial provider set.
    func aggregateEffectInputs(
        for aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        textureRegistry: SceneFrameTextureRegistry
    ) -> [SceneDependencyEffectInput]? {
        let frameEpoch = textureRegistry.frameEpoch
        guard frameEpoch > 0,
              aggregate.hasStrictBindingVector,
              plan.multiProviderAggregatesByConsumerLayerID[
                  aggregate.consumerLayerID
              ] == aggregate else { return nil }
        synchronizeReservations(to: frameEpoch)
        // `hasStrictBindingVector` proves this is already canonical. Do not
        // sort here: silently reordering a corrupted aggregate would hide an
        // authored slot/order mismatch from the execution ledger.
        let orderedBindings = aggregate.bindings
        var inputs: [SceneDependencyEffectInput] = []
        for binding in orderedBindings {
            let reference = SceneNamedTextureReference(
                providerLayerID: binding.providerLayerID,
                variant: .primary
            )
            guard let reservation = reservationsByProviderLayerID[
                binding.providerLayerID
            ], reservation.frameEpoch == frameEpoch,
                  let texture = textureRegistry.completeNamedLayerTargetTexture(
                      reference: reference,
                      frameEpoch: frameEpoch
                  ), texture === reservation.texture else { return nil }
            inputs.append(makeEffectInput(
                binding: binding,
                frameEpoch: frameEpoch,
                texture: texture
            ))
        }
        return aggregateInputVectorIsValid(
            inputs,
            aggregate: aggregate,
            frameEpoch: frameEpoch
        ) ? inputs : nil
    }

    func aggregateEffectInputs(
        for consumerLayerID: Int,
        textureRegistry: SceneFrameTextureRegistry
    ) -> [SceneDependencyEffectInput]? {
        guard let aggregate = plan
            .multiProviderAggregatesByConsumerLayerID[consumerLayerID] else {
            return nil
        }
        return aggregateEffectInputs(
            for: aggregate,
            textureRegistry: textureRegistry
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
              reservation.kind == .init(binding.kind) else {
            return .invalid(reasonCode: "external-primary-reservation-mismatch")
        }
        let reference = SceneNamedTextureReference(
            providerLayerID: binding.providerLayerID,
            variant: .primary
        )
        guard let texture = textureRegistry.completeNamedLayerTargetTexture(
            reference: reference,
            frameEpoch: frameEpoch
        ) else {
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
        guard plan.bindingsByConsumerLayerID[consumerLayerID] != nil
            || plan.multiProviderAggregatesByConsumerLayerID[
                consumerLayerID
            ] != nil else { return }
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
        providerAlpha: Float? = nil,
        providerColor: SIMD3<Float>? = nil,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        pipeline: SceneImageLayerPipeline,
        textureRegistry: SceneFrameTextureRegistry,
        mainPass: SceneMainPassEncoder,
        permitsGraphOutputSourceFallback: Bool = false
    ) -> Bool? {
        guard plan.requiredProviderLayerIDs.contains(layer.id) else { return nil }
        guard permitsGraphOutputSourceFallback
            || !plan.requiredGraphOutputProviderLayerIDs.contains(layer.id) else {
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
        let reference = SceneNamedTextureReference(
            providerLayerID: layer.id,
            variant: .primary
        )
        let reservation = reservationsByProviderLayerID[layer.id]
        if reservation == nil,
           textureRegistry.completeNamedLayerTargetTexture(
               reference: reference,
               frameEpoch: frameEpoch
           ) != nil {
            return true
        }
        let providerBindings = plan.bindingsByConsumerLayerID.values.filter {
            $0.providerLayerID == layer.id
        } + plan.multiProviderAggregatesByConsumerLayerID.values.flatMap {
            $0.bindings.filter { $0.providerLayerID == layer.id }
        }
        let staticModelBindings = plan.staticModelBindingsByConsumerLayerID.values
            .filter { $0.providerLayerID == layer.id }
        var captureFailureReason: String?
        let extent = captureExtentForProvider(
            layer: layer,
            providerBindings: providerBindings,
            hasStaticModelBinding: !staticModelBindings.isEmpty,
            reservation: reservation,
            frameEpoch: frameEpoch,
            sourceTexture: sourceTexture,
            sourceCandidate: sourceCandidate,
            layerMVP: layerMVP,
            viewportSize: viewportSize,
            failureReason: &captureFailureReason
        )
        guard (providerBindings.isEmpty != staticModelBindings.isEmpty),
              let extent else {
            captureTelemetry.recordFailure(layerID: layer.id)
            return false
        }
        let binding = providerBindings.first
        let providerTargetKind = binding.map {
            EffectTargetReservation.Kind($0.kind)
        }
        guard binding == nil || providerBindings.allSatisfy({
            EffectTargetReservation.Kind($0.kind) == providerTargetKind
        }) else { return false }
        let target: MTLTexture
        if let reservation {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == layer.id,
                  binding.map({
                      reservation.kind == .init($0.kind)
                  }) == true,
                  reservation.width == extent.width,
                  reservation.height == extent.height,
                  reservation.texture.width == extent.width,
                  reservation.texture.height == extent.height else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            if let publishedTexture = textureRegistry
                .completeNamedLayerTargetTexture(
                    reference: reference,
                    frameEpoch: frameEpoch
                ) {
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
        switch binding?.kind {
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
                    sourceCandidate.sampling.applying(
                        clampUVs: layer.clampUVs,
                        noInterpolation: layer.noInterpolation
                    ).imageLayerUniformMode,
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
            uniforms.alpha = max(0, providerAlpha ?? Float(layer.alpha ?? 1))
            let color = usesAuthoredLayerColor
                ? providerColor ?? SIMD3(layer.colorRGB ?? [], fill: 1)
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
        case nil:
            guard !staticModelBindings.isEmpty,
                  let sourceTexture,
                  let providerSource = Self.staticModelProviderSource(
                      layer: layer,
                      texture: sourceTexture,
                      candidate: sourceCandidate
                  ) else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
            var uniforms = SceneLayerFragmentUniforms.neutral()
            uniforms.alpha = max(0, providerAlpha ?? Float(layer.alpha ?? 1))
            let color = usesAuthoredLayerColor
                ? providerColor ?? SIMD3(layer.colorRGB ?? [], fill: 1)
                : SIMD3(repeating: 1)
            uniforms.tint = SIMD4(color.x, color.y, color.z, 1)
            uniforms.textureFrame0 = providerSource.textureFrame.uniform0
            uniforms.textureFrame1 = providerSource.textureFrame.uniform1
            uniforms.sourceSampling = SIMD2(
                providerSource.sampling.applying(
                    clampUVs: layer.clampUVs,
                    noInterpolation: layer.noInterpolation
                ).imageLayerUniformMode,
                0
            )
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
            guard textureRegistry.publishReservedNamedLayerTarget(
                reference: SceneNamedTextureReference(
                    providerLayerID: layer.id,
                    variant: .primary
                ),
                frameEpoch: frameEpoch,
                texture: target
            ), textureRegistry.completeNamedLayerTargetTexture(
                reference: reference,
                frameEpoch: frameEpoch
            ) === target else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return false
            }
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

    /// Publishes the exact current source when a visible effect graph has no
    /// product owner. This is the named-target half of the same fail-soft
    /// source passthrough used by the compositor: downstream consumers receive
    /// the preserved current source, never an unpublished reservation or an
    /// unrelated texture atom.
    func captureGraphSourceFallbackIfRequired(
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
        guard plan.requiredGraphOutputProviderLayerIDs.contains(layer.id) else {
            return nil
        }
        return captureProviderIfRequired(
            layer: layer,
            sourceTexture: sourceTexture,
            sourceCandidate: sourceCandidate,
            usesAuthoredLayerColor: usesAuthoredLayerColor,
            layerMVP: layerMVP,
            viewportSize: viewportSize,
            pipeline: pipeline,
            textureRegistry: textureRegistry,
            mainPass: mainPass,
            permitsGraphOutputSourceFallback: true
        )
    }

    /// Publishes an effectful provider's unified graph output into the exact
    /// named-target reservation. The graph runtime remains the producer and
    /// this registry remains the sole same-frame provider publication owner.
    func publishGraphOutputIfRequired(
        layerID: Int,
        texture: MTLTexture,
        publicationRole: GraphOutputPublicationRole,
        textureRegistry: SceneFrameTextureRegistry,
        commandBuffer: MTLCommandBuffer,
        content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
    ) -> Bool? {
        guard plan.requiredGraphOutputProviderLayerIDs.contains(layerID) else {
            return nil
        }
        // Publication is a provider action. One provider may legitimately feed
        // aggregate `.imageLayerBlend` consumers and singular
        // `.visibleImageGraphOutput` consumers at the same time, so consumer
        // binding kinds cannot select or veto this route.
        let publicationTelemetry: SceneGPUCompletionTelemetry
        switch publicationRole {
        case .visibleMainLoop:
            publicationTelemetry = visibleGraphOutputPublicationTelemetry
        case .namedProviderPrepass:
            publicationTelemetry = namedGraphOutputPublicationTelemetry
        }
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
        let reference = SceneNamedTextureReference(
            providerLayerID: layerID,
            variant: .primary
        )
        guard textureRegistry.publishReservedNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch,
            texture: reservation.texture,
            content: content
        ), textureRegistry.completeNamedLayerTargetTexture(
            reference: reference,
            frameEpoch: frameEpoch
        ) === reservation.texture else {
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

    func synchronizeReservations(to frameEpoch: UInt64) {
        guard reservationFrameEpoch != frameEpoch else { return }
        reservationFrameEpoch = frameEpoch
        reservationsByProviderLayerID.removeAll(keepingCapacity: true)
        demandedGraphOutputProviderLayerIDs.removeAll(keepingCapacity: true)
    }
}
