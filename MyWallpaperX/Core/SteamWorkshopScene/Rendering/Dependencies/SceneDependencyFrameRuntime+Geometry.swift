import CoreGraphics
import Metal
import simd

extension SceneDependencyFrameRuntime {
    static func geometryPublicationExtent(
        _ product: SceneGeometryProduct
    ) -> (width: Int, height: Int)? {
        let size = product.authoredSize
        guard size.x.isFinite, size.y.isFinite,
              size.x >= 1, size.y >= 1 else { return nil }
        let width = Int(size.x.rounded())
        let height = Int(size.y.rounded())
        guard abs(Float(width) - size.x) <= 0.001,
              abs(Float(height) - size.y) <= 0.001 else {
            return nil
        }
        return normalizedExtent(width: width, height: height)
    }

    /// Maps authored model pixels into a transparent local render target. The
    /// same Y contract as the orthographic Scene path is applied here; world,
    /// camera, parallax and consumer placement remain outside this target.
    static func geometryPublicationMVP(
        _ product: SceneGeometryProduct
    ) -> simd_float4x4? {
        guard geometryPublicationExtent(product) != nil else { return nil }
        // The target may be proportionally downsampled to the named-target
        // pool limit, but the mesh remains authored in the product's local
        // coordinate space. Using target pixels here would scale or crop a
        // valid oversized Puppet publication.
        let halfWidth = product.authoredSize.x * 0.5
        let halfHeight = product.authoredSize.y * 0.5
        return SceneMatrix.ortho(
            left: -halfWidth,
            right: halfWidth,
            bottom: halfHeight,
            top: -halfHeight,
            near: -1,
            far: 1
        ) * SceneMatrix.scale(SIMD3(1, -1, 1))
    }

    /// Reserves the one provider-owned target for an exact typed dependency.
    /// Geometry adds source generation and placement constraints, while all
    /// binding kinds retain the same frame-epoch and physical-texture owner.
    func reserveEffectInput(
        for binding: SceneDependencyRenderPlan.Binding,
        providerLayer: SceneRenderDescriptor.Layer,
        providerTexture: MTLTexture?,
        providerCandidate: SceneTextureCandidate?,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        preparedOutputExtent: (width: Int, height: Int)? = nil,
        geometryProduct: SceneGeometryProduct? = nil,
        providerOutputMVP: simd_float4x4? = nil,
        consumerOutputMVP: simd_float4x4? = nil,
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
        // Aggregate members are an ordered, primary vector. Keep the strict
        // shape check at reservation time so a forged/partial member cannot
        // acquire a target and fail only after graph execution has started.
        if plan.aggregateBindingIsPlanned(binding) {
            guard binding.consumerLayerID != binding.providerLayerID,
                  binding.referenceSlots == [binding.slot],
                  binding.kind == .imageLayerBlend
                    || binding.kind == .geometryLayer,
                  binding.blendMode == 0,
                  binding.requiresResolvedMaterialProgram else {
                failureReason = "aggregate-binding-shape-mismatch"
                return nil
            }
        }
        let requiresGraphOutput = plan.requiredGraphOutputProviderLayerIDs
            .contains(providerLayer.id)
        // Prepared extents come from the provider's frame plan. A caller may
        // not turn an unplanned raw provider into a graph publication by
        // supplying a size. A required provider can still have no executable
        // graph this frame; its original source fallback keeps raw eligibility.
        guard preparedOutputExtent.map({
            requiresGraphOutput && $0.width > 0 && $0.height > 0
        }) ?? true else {
            failureReason = "prepared-output-plan-invalid"
            return nil
        }
        guard let extent = Self.captureExtent(
            binding: binding,
            providerLayer: providerLayer,
            providerTexture: providerTexture,
            providerCandidate: providerCandidate,
            geometryProduct: geometryProduct,
            providerOutputMVP: providerOutputMVP,
            consumerOutputMVP: consumerOutputMVP,
            layerMVP: layerMVP,
            viewportSize: viewportSize,
            preparedOutputExtent: preparedOutputExtent,
            usesPreparedGraphOutput: requiresGraphOutput && preparedOutputExtent != nil,
            failureReason: &failureReason
        ) else {
            return nil
        }
        let sourceExtent: (width: Int, height: Int)
        if let preparedOutputExtent {
            sourceExtent = preparedOutputExtent
        } else if let providerTexture {
            sourceExtent = (providerTexture.width, providerTexture.height)
        } else {
            sourceExtent = extent
        }
        guard let texture = reserveProviderTarget(
            providerLayerID: providerLayer.id,
            kind: .init(binding.kind),
            extent: extent,
            sourceExtent: sourceExtent,
            geometryProduct: geometryProduct,
            frameEpoch: frameEpoch,
            failureReason: &failureReason
        ) else { return nil }
        // Graph outputs obtain their actual content from the prepared graph
        // in the submission coordinator. Raw image providers preserve their
        // source representation; geometry and main/solid captures publish PMA.
        let preservesRawImage = preparedOutputExtent == nil
            && (binding.kind == .imageLayerBlend || binding.kind == .visibleImageGraphOutput)
        return makeEffectInput(
            binding: binding,
            frameEpoch: frameEpoch,
            texture: texture,
            content: preservesRawImage
                ? Self.rawImageCaptureContent(providerCandidate?.content)
                : .color(.resolved(.premultipliedAlpha))
        )
    }

    /// The provider owns one physical reservation, independently of whether
    /// an effect slot or a model material requested its current graph output.
    func reserveProviderTarget(
        providerLayerID: Int,
        kind: EffectTargetReservation.Kind,
        extent: (width: Int, height: Int),
        sourceExtent: (width: Int, height: Int),
        geometryProduct: SceneGeometryProduct? = nil,
        frameEpoch: UInt64,
        failureReason: inout String?
    ) -> MTLTexture? {
        synchronizeReservations(to: frameEpoch)
        if plan.requiredGraphOutputProviderLayerIDs.contains(providerLayerID) {
            demandedGraphOutputProviderLayerIDs.insert(providerLayerID)
        }

        let texture: MTLTexture
        if let reservation = reservationsByProviderLayerID[providerLayerID] {
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == providerLayerID,
                  reservation.kind == kind,
                  reservation.width == extent.width,
                  reservation.height == extent.height,
                  reservation.sourceWidth == sourceExtent.width,
                  reservation.sourceHeight == sourceExtent.height,
                  reservation.geometryResourceGeneration
                    == geometryProduct?.resourceGeneration,
                  reservation.geometrySamplingTexture
                    === geometryProduct?.samplingTexture,
                  Self.isValidDependencyTexture(reservation.texture) else {
                failureReason = "reservation-mismatch"
                return nil
            }
            texture = reservation.texture
        } else {
            guard let reservedTexture = targetPool.texture(
                      for: providerLayerID,
                      width: extent.width,
                      height: extent.height
                  ), reservedTexture.width == extent.width,
                  reservedTexture.height == extent.height,
                  Self.isValidDependencyTexture(reservedTexture) else {
                failureReason = "target-pool-unavailable"
                return nil
            }
            reservationsByProviderLayerID[providerLayerID] =
                EffectTargetReservation(
                    providerLayerID: providerLayerID,
                    kind: kind,
                    texture: reservedTexture,
                    width: extent.width,
                    height: extent.height,
                    sourceWidth: sourceExtent.width,
                    sourceHeight: sourceExtent.height,
                    geometryResourceGeneration:
                        geometryProduct?.resourceGeneration,
                    geometrySamplingTexture: geometryProduct?.samplingTexture,
                    frameEpoch: frameEpoch
                )
            texture = reservedTexture
        }

        return texture
    }

    func captureExtentForProvider(
        layer: SceneRenderDescriptor.Layer,
        providerBindings: [SceneDependencyRenderPlan.Binding],
        hasStaticModelBinding: Bool,
        reservation: EffectTargetReservation?,
        frameEpoch: UInt64,
        sourceTexture: MTLTexture?,
        sourceCandidate: SceneTextureCandidate?,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        failureReason: inout String?
    ) -> (width: Int, height: Int)? {
        if plan.requiredGraphOutputProviderLayerIDs.contains(layer.id),
           let reservation,
           reservation.frameEpoch == frameEpoch {
            // A graph provider may carry a lower-resolution source texture.
            // Its named target follows the prepared graph allocation extent.
            return (reservation.width, reservation.height)
        }
        if let reservation,
           reservation.frameEpoch == frameEpoch,
           reservation.kind == .geometry {
            return (reservation.width, reservation.height)
        }
        if let binding = providerBindings.first {
            return Self.captureExtent(
                binding: binding,
                providerLayer: layer,
                providerTexture: sourceTexture,
                providerCandidate: sourceCandidate,
                layerMVP: layerMVP,
                viewportSize: viewportSize,
                failureReason: &failureReason
            )
        }
        guard hasStaticModelBinding else { return nil }
        return Self.staticModelCaptureExtent(
            providerLayer: layer,
            providerTexture: sourceTexture,
            providerCandidate: sourceCandidate,
            failureReason: &failureReason
        )
    }

    static func normalizedExtent(
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

    static func captureExtent(
        binding: SceneDependencyRenderPlan.Binding,
        providerLayer: SceneRenderDescriptor.Layer,
        providerTexture: MTLTexture?,
        providerCandidate: SceneTextureCandidate?,
        geometryProduct: SceneGeometryProduct? = nil,
        providerOutputMVP: simd_float4x4? = nil,
        consumerOutputMVP: simd_float4x4? = nil,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        preparedOutputExtent: (width: Int, height: Int)? = nil,
        usesPreparedGraphOutput: Bool = false,
        failureReason: inout String?
    ) -> (width: Int, height: Int)? {
        switch binding.kind {
        case .imageLayerBlend, .visibleImageGraphOutput:
            guard binding.providerLayerID == providerLayer.id,
                  let providerTexture,
                  providerTexture.textureType == .type2D,
                  providerTexture.sampleCount == 1,
                  providerTexture.usage.contains(.shaderRead) else {
                failureReason = "image-provider-invalid"
                return nil
            }
            if let providerCandidate,
               !isExactImageProviderCandidate(
                   providerCandidate,
                   matching: providerTexture,
                   requiresExactMapping: false
               ) {
                failureReason = "image-provider-invalid"
                return nil
            }
            if !usesPreparedGraphOutput,
               providerCandidate?.axisAlignedMappedUVScale(
                   expectedPurpose: providerCandidate?.purpose ?? .premultipliedColor
               ) == nil {
                // Specialized sprite loading intentionally has no Candidate;
                // its prepared graph source is validated by the original
                // source capture. Raw capture still needs its exact profile.
                // Missing that visual metadata is not a forged resource.
                failureReason = "image-provider-mapping-unavailable"
                return nil
            }
            return normalizedExtent(
                width: preparedOutputExtent?.width ?? providerTexture.width,
                height: preparedOutputExtent?.height ?? providerTexture.height
            )
        case .geometryLayer:
            guard binding.providerLayerID == providerLayer.id,
                  let providerTexture,
                  let geometryProduct,
                  geometryProduct.matchesInstalledSource(
                      layerID: providerLayer.id,
                      texture: providerTexture
                  ) else {
                failureReason = "geometry-provider-source-identity-invalid"
                return nil
            }
            guard geometryProduct.effectSourceExtentContract
                    == .exactSamplingTexture else {
                failureReason = "geometry-provider-source-extent-invalid"
                return nil
            }
            guard let providerOutputMVP,
                  let consumerOutputMVP else {
                failureReason = "geometry-provider-placement-missing"
                return nil
            }
            guard geometryProduct.supportsNamedProviderPlacement(
                    providerOutputMVP: providerOutputMVP,
                    consumerOutputMVP: consumerOutputMVP
                  ) else {
                failureReason = "geometry-provider-placement-mismatch"
                return nil
            }
            guard let extent = geometryPublicationExtent(geometryProduct) else {
                failureReason = "geometry-provider-publication-extent-invalid"
                return nil
            }
            return extent
        case .resolvedMaterial:
            // A hidden effect-chain provider admitted by the hidden-provider
            // contract publishes its graph output later in this same frame.
            // The preflight deliberately passes no base texture for
            // resolvedMaterial consumers, so the reservation extent follows
            // the provider's prepared graph output extent, with its source
            // texture as the texture-backed fallback.
            if providerLayer.utilityLayer == nil,
               providerLayer.effects.contains(where: { $0.visible != false }) {
                guard binding.providerLayerID == providerLayer.id else {
                    failureReason = "provider-layer-mismatch"
                    return nil
                }
                if let preparedOutputExtent {
                    // Over-cap graph outputs rasterize into the capped named
                    // target (aspect-preserving, same contract as the
                    // geometry route); within-cap extents stay identity so
                    // the blit publication route keeps its exact contract.
                    guard preparedOutputExtent.width > 0,
                          preparedOutputExtent.height > 0 else {
                        failureReason = "prepared-output-extent-invalid"
                        return nil
                    }
                    let longestEdge = max(
                        preparedOutputExtent.width,
                        preparedOutputExtent.height
                    )
                    if longestEdge
                        <= SceneNamedRenderTargetPool.maximumDimension {
                        return preparedOutputExtent
                    }
                    return normalizedExtent(
                        width: preparedOutputExtent.width,
                        height: preparedOutputExtent.height
                    )
                }
                guard let providerTexture else {
                    failureReason = "image-provider-invalid"
                    return nil
                }
                return normalizedExtent(
                    width: providerTexture.width,
                    height: providerTexture.height
                )
            }
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
                width: preparedOutputExtent?.width ?? providerTexture.width,
                height: preparedOutputExtent?.height ?? providerTexture.height
            )
        }
    }

    static func isExactImageProviderCandidate(
        _ candidate: SceneTextureCandidate,
        matching texture: MTLTexture,
        requiresExactMapping: Bool = true
    ) -> Bool {
        let physical = candidate.physicalSize
        let mapped = candidate.mappedSize
        guard candidate.texture === texture,
              candidate.purpose == (candidate.content == .color(.resolved(.straightAlpha))
                ? .straightAlbedo : .premultipliedColor),
              candidate.content.isResolved,
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback,
              physical.width == CGFloat(texture.width),
              physical.height == CGFloat(texture.height),
              mapped.width.isFinite, mapped.height.isFinite,
              mapped.width > 0, mapped.height > 0,
              mapped.width.rounded() == mapped.width,
              mapped.height.rounded() == mapped.height,
              mapped.width <= physical.width,
              mapped.height <= physical.height,
              candidate.materialProgramUVTransform() != nil,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.usage.contains(.shaderRead) else {
            return false
        }
        // Unlike SlotBinding, this raw profile has no UV-area floor. A tiny
        // positive mapped region is still valid; do not tighten that contract.
        return !requiresExactMapping || candidate.axisAlignedMappedUVScale(
            expectedPurpose: candidate.purpose
        ) != nil
    }

    /// Encodes either the original atlas or its graph-final color through the
    /// provider's GeometryProduct into the already reserved authored-local
    /// named target. Publication becomes visible only after the geometry draw
    /// has been accepted on this frame's command buffer.
    func publishGeometryOutputIfRequired(
        layerID: Int,
        sourceTexture: MTLTexture,
        geometryProduct: SceneGeometryProduct,
        textureRegistry: SceneFrameTextureRegistry,
        commandBuffer: MTLCommandBuffer,
        telemetry: SceneGPUCompletionTelemetry,
        content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
        sourceTextureFrame: SceneTextureUVTransform = .identity,
        retainAuxiliary: SceneGeometryProduct.AuxiliaryRetainer? = nil
    ) -> SceneGraphOutputPublicationResult? {
        guard plan.requiredProviderLayerIDs.contains(layerID) else { return nil }
        let frameEpoch = textureRegistry.frameEpoch
        synchronizeReservations(to: frameEpoch)
        guard let reservation = reservationsByProviderLayerID[layerID] else {
            telemetry.recordFailure(layerID: layerID)
            return .invalid(reasonCode: "geometry-provider-reservation-missing")
        }
        guard case let .color(.resolved(representation)) = content,
              representation == .premultipliedAlpha
                || representation == .straightAlpha || representation == .opaque,
              reservation.kind == .geometry,
              reservation.frameEpoch == frameEpoch,
              reservation.providerLayerID == layerID,
              reservation.geometryResourceGeneration
                == geometryProduct.resourceGeneration,
              reservation.geometrySamplingTexture
                === geometryProduct.samplingTexture,
              geometryProduct.matchesInstalledSource(
                  layerID: layerID,
                  texture: geometryProduct.samplingTexture
              ),
              sourceTexture.width == reservation.sourceWidth,
              sourceTexture.height == reservation.sourceHeight,
              sourceTexture.textureType == .type2D,
              sourceTexture.sampleCount == 1,
              sourceTexture.usage.contains(.shaderRead),
              let mvp = Self.geometryPublicationMVP(geometryProduct) else {
            telemetry.recordFailure(layerID: layerID)
            return .invalid(reasonCode: "geometry-provider-publication-identity-invalid")
        }
        guard geometryProduct.isPreparedForPublication(commandBuffer) else {
            telemetry.recordFailure(layerID: layerID)
            return .unavailable(reasonCode: "geometry-provider-pose-unavailable")
        }
        if let prepare = geometryProduct.prepare {
            guard let retainAuxiliary else {
                telemetry.recordFailure(layerID: layerID)
                return .unavailable(reasonCode: "geometry-provider-auxiliary-owner-unavailable")
            }
            prepare(commandBuffer, SIMD2(reservation.texture.width, reservation.texture.height),
                    mvp, retainAuxiliary)
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = reservation.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = .init(
            red: 0, green: 0, blue: 0, alpha: 0
        )
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            telemetry.recordFailure(layerID: layerID)
            return .unavailable(reasonCode: "geometry-provider-encoder-unavailable")
        }
        encoder.label = "Scene named geometry publication layer=\(layerID)"
        // This existing geometry raster applies vertex/clip coverage and writes
        // associated color. Associate a straight graph input once at that
        // compositor boundary, then publish the actual PMA result.
        var uniforms = SceneLayerFragmentUniforms.neutral()
        uniforms.sourceSampling.y = representation == .straightAlpha ? 1 : 0
        uniforms.textureFrame0 = sourceTextureFrame.uniform0
        uniforms.textureFrame1 = sourceTextureFrame.uniform1
        let encoded = geometryProduct.encode(
            encoder,
            sourceTexture,
            nil,
            mvp,
            uniforms,
            nil
        )
        encoder.endEncoding()
        guard encoded else {
            telemetry.recordFailure(layerID: layerID)
            return .unavailable(reasonCode: "geometry-provider-encode-unavailable")
        }
        let reference = SceneNamedTextureReference(
            providerLayerID: layerID,
            variant: .primary
        )
        guard textureRegistry.publishReservedNamedLayerTarget(
            reference: reference,
            frameEpoch: frameEpoch,
            texture: reservation.texture,
            content: .color(.resolved(.premultipliedAlpha))
        ), textureRegistry.completeNamedLayerTargetResource(
            reference: reference,
            frameEpoch: frameEpoch
        )?.publication.texture === reservation.texture else {
            telemetry.recordFailure(layerID: layerID)
            return .invalid(reasonCode: "geometry-provider-registry-publication-invalid")
        }
        telemetry.record(layerID: layerID, encoded: true, on: commandBuffer)
        return .published
    }
}
