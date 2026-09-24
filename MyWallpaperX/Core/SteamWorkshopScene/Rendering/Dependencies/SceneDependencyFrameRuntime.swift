import CoreGraphics
import Metal
import simd

enum SceneResolvedMaterialDependencyInputResolution {
    case ready(SceneDependencyEffectInput)
    case unavailable(reasonCode: String)
    case invalid(reasonCode: String)
}

enum SceneResolvedMaterialAggregateInputResolution {
    case ready([SceneDependencyEffectInput])
    case unavailable(reasonCode: String)
    case invalid(reasonCode: String)
}

enum SceneGraphOutputPublicationResult: Equatable {
    case published
    /// The prepared identity is still current, but the color product could
    /// not be encoded or published on this frame. Only color providers may
    /// localize this ordinary visual miss.
    case unavailable(reasonCode: String)
    /// Reservation, epoch, resource or registry identity no longer matches
    /// the prepared provider contract. Callers must fail closed.
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
            case geometry
            case resolvedMaterial
            case solidLayer

            init(_ bindingKind: SceneDependencyRenderPlan.Binding.Kind) {
                switch bindingKind {
                case .imageLayerBlend, .visibleImageGraphOutput:
                    self = .image
                case .geometryLayer:
                    self = .geometry
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
        /// Exact graph/source texture extent before a GeometryProduct
        /// rasterizes it into the provider-local publication target.
        let sourceWidth: Int
        let sourceHeight: Int
        let geometryResourceGeneration: UInt64?
        let geometrySamplingTexture: MTLTexture?
        let frameEpoch: UInt64
    }

    let plan: SceneDependencyRenderPlan
    let targetPool: SceneNamedRenderTargetPool
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
    /// Defensive same-frame publication identity. The claim/ticket bridge
    /// executes one graph per layer per frame, so a repeated
    /// `publishGraphOutputIfRequired` for the same layer is either the same
    /// ticket re-requested (reuse the completed publication, skip the second
    /// full-texture blit) or identity drift (fail closed). The map is scoped
    /// to the current frame epoch and is cleared with reservations.
    private var publishedGraphOutputSourcesByLayerID: [Int: MTLTexture] = [:]
#if DEBUG
    private var debugCaptureFault = SceneDependencyCaptureFault()
    var debugPreparedOutputInstallFailureRecorded = false
#endif

    var renderTargetResidentByteCost: Int { targetPool.residentByteCost }

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
        geometryProduct: SceneGeometryProduct? = nil,
        permitsGraphOutputSourceFallback: Bool = false
    ) -> SceneGraphOutputPublicationResult? {
        guard plan.requiredProviderLayerIDs.contains(layer.id) else { return nil }
        guard permitsGraphOutputSourceFallback
            || !plan.requiredGraphOutputProviderLayerIDs.contains(layer.id) else {
            // A graph-output provider publishes through the graph route, not
            // through this raw capture entry point. That is an ordinary
            // route-not-applicable miss: the caller keeps its previous
            // current and the consumer side localizes a missing publication.
            return .unavailable(
                reasonCode: "graph-provider-raw-capture-unavailable"
            )
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
            return .unavailable(reasonCode: "named-provider-capture-unavailable")
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
            return .published
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
        let hasNormalBindings = !providerBindings.isEmpty
        let hasStaticModelBindings = !staticModelBindings.isEmpty
        guard hasNormalBindings || hasStaticModelBindings else {
            captureTelemetry.recordFailure(layerID: layer.id)
            return .invalid(reasonCode: "named-provider-binding-missing")
        }
        guard hasNormalBindings != hasStaticModelBindings else {
            // Mixed image and static-model consumers are not a proven capture
            // shape. Keep the previous local radius instead of stopping the
            // frame; the consumer side still localizes its missing
            // publication.
            captureTelemetry.recordFailure(layerID: layer.id)
            return .unavailable(
                reasonCode: "named-provider-binding-shape-unsupported"
            )
        }
        guard let extent else {
            captureTelemetry.recordFailure(layerID: layer.id)
            // A reservation is this frame's identity proof for the provider.
            // Once it exists, failing to reconstruct the same extent is
            // identity drift and must fail closed; otherwise the source is
            // simply not ready and the ordinary local miss still applies.
            return reservation == nil
                ? .unavailable(
                    reasonCode: captureFailureReason
                        ?? "named-provider-source-unavailable"
                )
                : .invalid(
                    reasonCode: captureFailureReason
                        ?? "named-provider-capture-identity-invalid"
                )
        }
        let binding = providerBindings.first
        let providerTargetKind = binding.map {
            EffectTargetReservation.Kind($0.kind)
        }
        guard binding == nil || providerBindings.allSatisfy({
            EffectTargetReservation.Kind($0.kind) == providerTargetKind
        }) else {
            return .invalid(reasonCode: "named-provider-binding-kind-invalid")
        }
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
                return .invalid(reasonCode: "named-provider-reservation-invalid")
            }
            if let publishedTexture = textureRegistry
                .completeNamedLayerTargetTexture(
                    reference: reference,
                    frameEpoch: frameEpoch
                ) {
                guard publishedTexture === reservation.texture else {
                    captureTelemetry.recordFailure(layerID: layer.id)
                    return .invalid(reasonCode: "named-provider-publication-identity-invalid")
                }
                return .published
            }
            target = reservation.texture
        } else {
            guard let pooledTarget = targetPool.texture(
                      for: layer.id,
                      width: extent.width,
                      height: extent.height
                  ) else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return .unavailable(reasonCode: "named-provider-target-unavailable")
            }
            target = pooledTarget
        }

        let encoded: Bool
        switch binding?.kind {
        case .imageLayerBlend, .visibleImageGraphOutput:
            guard let sourceTexture, let sourceCandidate else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return .unavailable(reasonCode: "image-provider-source-unavailable")
            }
            guard sourceCandidate.texture === sourceTexture else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return .invalid(reasonCode: "image-provider-source-identity-invalid")
            }
            guard Self.isExactImageProviderCandidate(
                sourceCandidate,
                matching: sourceTexture
            ) else {
                // Unresolved content/sampling or a wrong-purpose candidate
                // means no exact provider atom exists yet. Keep the ordinary
                // local radius for that pending state.
                captureTelemetry.recordFailure(layerID: layer.id)
                return .unavailable(reasonCode: "image-provider-source-unavailable")
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
        case .geometryLayer:
            guard let sourceTexture,
                  let geometryProduct else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return .unavailable(reasonCode: "geometry-provider-source-unavailable")
            }
            return mainPass.encodeOffscreen {
                commandBuffer -> SceneGraphOutputPublicationResult in
                publishGeometryOutputIfRequired(
                    layerID: layer.id,
                    sourceTexture: sourceTexture,
                    geometryProduct: geometryProduct,
                    textureRegistry: textureRegistry,
                    commandBuffer: commandBuffer,
                    telemetry: captureTelemetry
                ) ?? .invalid(
                    reasonCode: "geometry-provider-publication-route-missing"
                )
            }
        case .resolvedMaterial:
            guard let utility = layer.utilityLayer,
                  let geometry = SceneCaptureGeometryResolver.resolve(
                      kind: utility.kind,
                      layerMVP: layerMVP,
                      viewportSize: viewportSize
                  ) else {
                captureTelemetry.recordFailure(layerID: layer.id)
                return .invalid(reasonCode: "resolved-provider-geometry-invalid")
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
                return .unavailable(reasonCode: "solid-provider-source-unavailable")
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
                return .unavailable(reasonCode: "static-model-provider-source-unavailable")
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
                return .invalid(reasonCode: "named-provider-registry-publication-invalid")
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
            ? .published
            : .unavailable(reasonCode: "named-provider-encode-unavailable")
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
        mainPass: SceneMainPassEncoder,
        geometryProduct: SceneGeometryProduct? = nil
    ) -> SceneGraphOutputPublicationResult? {
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
            geometryProduct: geometryProduct,
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
        geometryProduct: SceneGeometryProduct? = nil,
        content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
        imagePipeline: SceneImageLayerPipeline? = nil
    ) -> SceneGraphOutputPublicationResult? {
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
        guard let reservation = reservationsByProviderLayerID[layerID] else {
            publicationTelemetry.recordFailure(layerID: layerID)
            return .invalid(reasonCode: "named-provider-reservation-missing")
        }
        let reference = SceneNamedTextureReference(
            providerLayerID: layerID,
            variant: .primary
        )
        if let priorSource = publishedGraphOutputSourcesByLayerID[layerID] {
            guard let existing = textureRegistry
                      .completeNamedLayerTargetResource(
                          reference: reference,
                          frameEpoch: frameEpoch
                      ),
                  existing.publication.texture === reservation.texture else {
                publicationTelemetry.recordFailure(layerID: layerID)
                return .invalid(
                    reasonCode: "named-provider-publication-identity-invalid"
                )
            }
            if priorSource !== texture {
                let sameSourceExtent = reservation.sourceWidth == texture.width
                    && reservation.sourceHeight == texture.height
                publicationTelemetry.recordFailure(layerID: layerID)
                return .invalid(
                    reasonCode: sameSourceExtent
                        ? "named-provider-publication-identity-invalid"
                        : "named-provider-publication-target-extent-invalid"
                )
            }
            guard existing.publication.candidate.content == content else {
                publicationTelemetry.recordFailure(layerID: layerID)
                return .invalid(
                    reasonCode: "named-provider-publication-content-mismatch"
                )
            }
            return .published
        }
        if reservation.kind == .geometry {
            guard let geometryProduct else {
                publicationTelemetry.recordFailure(layerID: layerID)
                return .invalid(reasonCode: "geometry-provider-product-missing")
            }
            return publishGeometryOutputIfRequired(
                layerID: layerID,
                sourceTexture: texture,
                geometryProduct: geometryProduct,
                textureRegistry: textureRegistry,
                commandBuffer: commandBuffer,
                telemetry: publicationTelemetry,
                content: content
            )
        }
        // Within-cap extents keep the exact one-full-region-blit contract.
        // An over-cap resolved-color output may instead rasterize into its
        // aspect-normalized capped target - the same downsampling contract
        // the geometry route already owns. Preserved-channel (.data) content
        // never resamples and stays fail-closed over-cap.
        let withinCapBlit = reservation.width == reservation.sourceWidth
            && reservation.height == reservation.sourceHeight
        if !withinCapBlit {
            let normalized = Self.normalizedExtent(
                width: reservation.sourceWidth,
                height: reservation.sourceHeight
            )
            // The source format/renderTarget-usage checks the blit branch
            // makes are guaranteed upstream here: installPreparedGraphOutputs
            // enforces pool/output format and usage equality for demanded
            // providers, and the single image pipeline construction site
            // defaults to the pool's bgra8Unorm.
            guard content.isColorContent,
                  let imagePipeline,
                  let normalized,
                  normalized.width == reservation.width,
                  normalized.height == reservation.height,
                  reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == layerID,
                  reservation.texture !== texture,
                  reservation.sourceWidth == texture.width,
                  reservation.sourceHeight == texture.height,
                  texture.textureType == .type2D,
                  texture.sampleCount == 1,
                  texture.mipmapLevelCount == 1,
                  texture.usage.contains(.shaderRead) else {
                publicationTelemetry.recordFailure(layerID: layerID)
                return .invalid(
                    reasonCode: "named-provider-publication-target-extent-invalid"
                )
            }
            guard SceneOffscreenEffectRenderer.captureSource(
                sourceTexture: texture,
                target: reservation.texture,
                sourceUniforms: .neutral(),
                pipeline: imagePipeline,
                commandBuffer: commandBuffer
            ) else {
                publicationTelemetry.recordFailure(layerID: layerID)
                return .unavailable(
                    reasonCode: "named-provider-publication-encoder-unavailable"
                )
            }
            SceneGPUCensus.recordGraphOutputPublication(texture: reservation.texture)
            guard textureRegistry.publishReservedNamedLayerTarget(
                reference: reference,
                frameEpoch: frameEpoch,
                texture: reservation.texture,
                content: content
            ), textureRegistry.completeNamedLayerTargetResource(
                reference: reference,
                frameEpoch: frameEpoch
            )?.publication.texture === reservation.texture else {
                publicationTelemetry.recordFailure(layerID: layerID)
                return .invalid(reasonCode: "named-provider-registry-publication-invalid")
            }
            publicationTelemetry.record(
                layerID: layerID,
                encoded: true,
                on: commandBuffer
            )
            publishedGraphOutputSourcesByLayerID[layerID] = texture
            return .published
        }
        guard reservation.frameEpoch == frameEpoch,
              reservation.providerLayerID == layerID,
              reservation.texture !== texture,
              reservation.sourceWidth == texture.width,
              reservation.sourceHeight == texture.height,
              reservation.texture.pixelFormat == texture.pixelFormat,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.mipmapLevelCount == 1,
              texture.usage.contains(.renderTarget),
              texture.usage.contains(.shaderRead) else {
            publicationTelemetry.recordFailure(layerID: layerID)
            return .invalid(reasonCode: "named-provider-publication-identity-invalid")
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            publicationTelemetry.recordFailure(layerID: layerID)
            return .unavailable(reasonCode: "named-provider-publication-encoder-unavailable")
        }
        blit.label = "Scene named graph publication layer=\(layerID)"
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
            to: reservation.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        SceneGPUCensus.recordGraphOutputPublication(texture: texture)
        blit.endEncoding()
        guard textureRegistry.publishReservedNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch,
            texture: reservation.texture,
            content: content
        ), textureRegistry.completeNamedLayerTargetResource(
            reference: reference,
            frameEpoch: frameEpoch
        )?.publication.texture === reservation.texture else {
            publicationTelemetry.recordFailure(layerID: layerID)
            return .invalid(reasonCode: "named-provider-registry-publication-invalid")
        }
        publicationTelemetry.record(
            layerID: layerID,
            encoded: true,
            on: commandBuffer
        )
        publishedGraphOutputSourcesByLayerID[layerID] = texture
        return .published
    }

    func synchronizeReservations(to frameEpoch: UInt64) {
        guard reservationFrameEpoch != frameEpoch else { return }
        reservationFrameEpoch = frameEpoch
        reservationsByProviderLayerID.removeAll(keepingCapacity: true)
        demandedGraphOutputProviderLayerIDs.removeAll(keepingCapacity: true)
        publishedGraphOutputSourcesByLayerID.removeAll(keepingCapacity: true)
    }
}
