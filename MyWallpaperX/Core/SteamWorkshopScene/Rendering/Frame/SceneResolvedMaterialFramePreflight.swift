import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    func admitResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:],
        imagePipeline: SceneImageLayerPipeline?,
        userPropertyTextures: [String: MTLTexture],
        userPropertyStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainTarget: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> SceneMetalRenderer.ResolvedMaterialFrameAdmission {
        // Publish this frame's typed resources before target sizing or source
        // admission. Otherwise preflight reads a stale/empty registry while
        // preparation later encodes the current provider into that target.
        beginTextureFrame(
            imageTextures, userPropertyTextures, userPropertyStates,
            mediaThumbnail, frameContext
        )
        // Source selection is frame-scoped: provider readiness and authored
        // fallback state are refreshed above, then shared by target sizing and
        // preparation request construction below.
        var baseMaterialSelections: [Int: SceneBaseMaterialTextureSelection] = [:]
        switch preflightResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            offscreenTexturePool: offscreenTexturePool,
            performanceTelemetry: performanceTelemetry,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            commandBuffer: commandBuffer,
            baseMaterialSelections: &baseMaterialSelections
        ) {
        case let .ready(plans, localFallbacks):
            guard imageCompositor.installResolvedMaterialFrameLocalFallbacks(
                localFallbacks
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    "frame-local-fallback-install-rejected"
                )
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return .rejected(
                    reasonCode: "frame-local-fallback-install-rejected"
                )
            }
            var requestFailureReason: String?
            guard let requests = resolvedMaterialFramePreparationRequests(
                plans: plans,
                imageTextures: imageTextures,
                spriteAnimations: spriteAnimations,
                spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
                performanceTelemetry: performanceTelemetry,
                specializedBaseTextureSamplings: specializedBaseTextureSamplings,
                imagePipeline: imagePipeline,
                offscreenTexturePool: offscreenTexturePool,
                frameContext: frameContext,
                worldFramesByLayerID: worldFramesByLayerID,
                cameraFrame: cameraFrame,
                parallaxConfiguration: parallaxConfiguration,
                mainTarget: mainTarget,
                failureReason: &requestFailureReason,
                baseMaterialSelections: &baseMaterialSelections
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    requestFailureReason ?? "frame-preparation-request-invalid"
                )
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return .rejected(
                    reasonCode: requestFailureReason
                        ?? "frame-preparation-request-invalid"
                )
            }
            performanceTelemetry?.beginStage("admit-prepare-frame")
            defer { performanceTelemetry?.endStage("admit-prepare-frame") }
            switch imageCompositor.prepareResolvedMaterialFrame(
                requests,
                pool: offscreenTexturePool,
                commandBuffer: commandBuffer,
                performanceTelemetry: performanceTelemetry
            ) {
            case .ready:
                guard let preparedOutputs = imageCompositor
                        .preparedResolvedMaterialOutputTexturesByLayerID(),
                      dependencyRuntime.installPreparedGraphOutputs(
                        preparedOutputs,
                        frameEpoch: textureRegistry.frameEpoch
                      ) else {
                    imageCompositor.recordResolvedMaterialFramePreflightFailure(
                        "prepared-provider-output-install-rejected"
                    )
                    _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                    return .rejected(
                        reasonCode: "prepared-provider-output-install-rejected"
                    )
                }
            case .rejected:
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return .rejected(
                    reasonCode: "resolved-material-frame-preparation-rejected"
                )
            }
            return .ready(plans: plans)
        case .deferred:
            _ = imageCompositor.deferResolvedMaterialFrame()
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return .deferred(
                reasonCode: "resolved-material-preflight-deferred"
            )
        case .rejected(let reasonCode):
            imageCompositor.recordResolvedMaterialFramePreflightFailure(reasonCode)
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return .rejected(reasonCode: reasonCode)
        }
    }

    func preflightResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        commandBuffer: MTLCommandBuffer,
        baseMaterialSelections: inout [Int: SceneBaseMaterialTextureSelection]
    ) -> SceneResolvedMaterialGraphComposition.FramePreflightResult {
        performanceTelemetry?.beginStage("admit-preflight-targets")
        defer { performanceTelemetry?.endStage("admit-preflight-targets") }
        let viewportSize = frameContext.screenSize
        guard let orderedLayers = resolvedMaterialPreparationLayers else {
            return .rejected(
                reasonCode: "resolved-material-preparation-order-invalid"
            )
        }
        let availableExecutionLayerIDs =
            imageCompositor.resolvedMaterialRuntime?.executionLayerIDs ?? []
        let frameVisibleRootLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: renderDescriptor,
            layersByID: layersByID,
            snapshot: frameContext.dynamicValues
        )
        let activeExecutionLayerIDs = dependencyRuntime
            .resolvedMaterialExecutionLayerIDs(
                visibleRootLayerIDs: frameVisibleRootLayerIDs,
                availableExecutionLayerIDs: availableExecutionLayerIDs
            )
        var requests: [
            SceneResolvedMaterialGraphComposition.FrameTargetRequest
        ] = []
        var sourceCoverageFallbacks: [Int: String] = [:]
        let materialFunctionMutationsByLayerID = Dictionary(
            grouping: frameContext.materialFunctionMutations,
            by: \.layerID
        )
        func materialFunctionInvocations(
            for layer: SceneRenderDescriptor.Layer
        ) -> [SceneGraphMaterialFunctionInvocationRequest] {
            (materialFunctionMutationsByLayerID[layer.id] ?? [])
                .map { mutation in
                    let descriptorID: String
                    if layer.effects.indices.contains(mutation.effectIndex) {
                        descriptorID = layer.effects[mutation.effectIndex].id
                    } else {
                        descriptorID = "invalid-effect-index-\(mutation.effectIndex)"
                    }
                    return SceneGraphMaterialFunctionInvocationRequest(
                        effect: .init(
                            layerID: layer.id,
                            effectIndex: mutation.effectIndex,
                            descriptorID: descriptorID
                        ),
                        functionName: mutation.functionName,
                        frameEpoch: textureRegistry.frameEpoch
                    )
                }
        }
        for layer in orderedLayers {
            var directDrawOutputModelViewProjection: simd_float4x4?
            // A utility composition owns a graph transaction only when its
            // typed utility plan can actually capture and consume that
            // transaction.  Keeping an unsupported utility claim in the
            // prepared ledger would leave it allocation-committed forever;
            // the strict predecessor gate would then reject an unrelated
            // later image layer.  The ordinary composition fallback remains
            // available for this frame-local unsupported unit.
            if layer.contentKind == "composition",
               layer.utilityLayer?.kind == .composition,
               !utilityCaptureLayerIDs.contains(layer.id) {
                continue
            }
            // An accepted dynamic root that is false in the committed frame
            // owns no graph transaction and cannot make its hidden provider
            // reject unrelated visible output. Product-authority rejections
            // are intentionally not in `availableExecutionLayerIDs` and still
            // flow through the ordinary fail-closed claim path below.
            if availableExecutionLayerIDs.contains(layer.id),
               !activeExecutionLayerIDs.contains(layer.id) {
                continue
            }
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layer.id
            )
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch route {
            case .unclaimed:
                continue
            case let .localFallback(reasonCode):
                return .rejected(reasonCode: reasonCode)
            case let .rejected(reasonCode):
                return .rejected(reasonCode: reasonCode)
            case let .claimed(value):
                claim = value
            }
            if case let .externalPrimary(binding) = claim.dependencyOwnership,
               binding.kind != .resolvedMaterial,
               imageTextures.isLayerSourcePending(binding.providerLayerID) {
                sourceCoverageFallbacks[layer.id] = "layer-source-not-ready"
                continue
            }
            let desiredSize: CGSize
            let effectSourceExtentContract = imageTextures.geometryProducts[
                layer.id
            ]?.effectSourceExtentContract ?? .scalableStandard
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                let selection = cachedBaseMaterialTextureSelection(
                    for: layer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer,
                            dynamicValues: frameContext.dynamicValues
                        ),
                    cache: &baseMaterialSelections
                )
                let selectedSource: SceneBaseMaterialTextureSource
                switch selection {
                case let .source(value):
                    selectedSource = value
                case .missing:
                    // An asynchronous source must not hold the entire scene
                    // at frame zero: submission also lets its decoder warm up.
                    // No source is fabricated; retry this layer next frame.
                    sourceCoverageFallbacks[layer.id] = "layer-source-not-ready"
                    continue
                case let .rejected(reasonCode):
                    return .rejected(reasonCode: reasonCode)
                }
                if imageTextures.geometryProducts[layer.id] != nil {
                    // A Puppet graph processes the atlas before skinning. Its
                    // target therefore follows the atlas sampling extent and
                    // never the pose coverage or viewport projection.
                    desiredSize = selectedSource.candidate?.mappedSize
                        ?? CGSize(
                            width: selectedSource.texture.width,
                            height: selectedSource.texture.height
                        )
                    break
                }
                if layer.contentKind != "solid" {
                    guard let extent = SceneLayerEffectSourceExtent.resolve(
                        publishedRenderSizeWH:
                            imageTextures.layerSourceEffectRenderSize(for: layer.id),
                        authoredRenderSizeWH: layer.renderSizeWH,
                        candidateMappedSize: selectedSource.candidate?.mappedSize
                    ) else {
                        return .rejected(
                            reasonCode: "layer-effect-source-extent-unavailable"
                        )
                    }
                    // The effect chain rasterizes this source once and the
                    // compositor draws the capture with the layer transform:
                    // when the authored scale enlarges the layer on canvas,
                    // capturing at the authored surface size would upscale
                    // the whole chain (maintainer-observed character blur).
                    // The world model matrix column lengths are the layer's
                    // on-canvas pixel extent of the unit quad and are
                    // invariant to parallax translation, so they give a
                    // stable per-layer size; quantize upward to absorb
                    // script-animated scale jitter without pool churn.
                    let model = imageModelMatrix(
                        for: layer,
                        worldFramesByLayerID: worldFramesByLayerID,
                        renderSizeOverride: imageTextures.layerSourceRenderSize(
                            for: layer.id
                        ),
                        parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                        configuration: parallaxConfiguration,
                        visibleHalfExtents: cameraFrame.coverHalfExtents,
                        usesPerspective: cameraFrame.resolvesPerspective(for: layer)
                    )
                    let onCanvasWidth = simd_length(model.columns.0)
                    let onCanvasHeight = simd_length(model.columns.1)
                    func quantizedUp(_ value: CGFloat) -> CGFloat {
                        guard value.isFinite, value > 0 else { return 0 }
                        let quantum: CGFloat = 128
                        return (value / quantum).rounded(.up) * quantum
                    }
                    desiredSize = CGSize(
                        width: max(
                            extent.pixelSize.width,
                            quantizedUp(CGFloat(onCanvasWidth))
                        ),
                        height: max(
                            extent.pixelSize.height,
                            quantizedUp(CGFloat(onCanvasHeight))
                        )
                    )
                    break
                }
                let model = imageModelMatrix(
                    for: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(
                        for: layer.id
                    ),
                    parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: cameraFrame.resolvesPerspective(for: layer)
                )
                guard let projectedSize =
                    SceneCaptureGeometryResolver.projectedPixelSize(
                    layerMVP: cameraFrame.viewProjection(for: layer) * model,
                    viewportSize: viewportSize
                    ) else {
                    return .rejected(
                        reasonCode: "solid-offscreen-size-unavailable"
                    )
                }
                desiredSize = projectedSize
            case .capturedMainTargetTexture:
                guard let utility = layer.utilityLayer,
                      layer.contentKind == utility.kind.rawValue,
                      case let .success(sourceRoute) =
                        SceneUtilityLayerSourceRoute.resolve(
                          layer: layer,
                          descriptor: renderDescriptor
                      ) else {
                    return .rejected(
                        reasonCode: "utility-source-shape-invalid"
                    )
                }
                if sourceRoute.capturesCompositionSubtree,
                   !hasOpaqueFullViewportUtilitySource(
                       route: sourceRoute,
                       imageTextures: imageTextures,
                       frameContext: frameContext,
                       worldFramesByLayerID: worldFramesByLayerID,
                       cameraFrame: cameraFrame,
                       parallaxConfiguration: parallaxConfiguration
                   ) {
                    sourceCoverageFallbacks[layer.id] =
                        "utility-composition-subtree-source-coverage-unavailable"
                    continue
                }
                let model = imageModelMatrix(
                    for: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: cameraFrame.resolvesPerspective(for: layer)
                )
                guard let geometry = SceneCaptureGeometryResolver.resolve(
                    kind: utility.kind,
                    layerMVP: cameraFrame.viewProjection(for: layer) * model,
                    viewportSize: viewportSize
                ) else {
                    return .rejected(
                        reasonCode: "utility-offscreen-size-unavailable"
                    )
                }
                desiredSize = geometry.pixelSize
            case .transparentDirectDraw:
                guard layer.contentKind == "quad",
                      case let .authoredCanvasDirectDraw(geometryContract) =
                        claim.frameInputContract.emittedOutputGeometrySource,
                      let model = directDrawOutputModelMatrix(
                          for: layer,
                          contract: geometryContract,
                          worldFramesByLayerID: worldFramesByLayerID,
                          parallaxMouseNormalized:
                              frameContext.cameraParallaxPosition,
                          configuration: parallaxConfiguration
                      ) else {
                    return .rejected(
                        reasonCode: "direct-draw-output-geometry-invalid"
                    )
                }
                let outputMVP = cameraFrame.viewProjection(for: layer) * model
                guard let projectedSize =
                        SceneCaptureGeometryResolver.projectedPixelSize(
                            layerMVP: outputMVP,
                            viewportSize: frameContext.screenSize
                        ) else {
                    return .rejected(
                        reasonCode: "direct-draw-offscreen-size-unavailable"
                    )
                }
                directDrawOutputModelViewProjection = outputMVP
                desiredSize = projectedSize
            }
            requests.append(.init(
                claim: claim,
                effectSourceExtentContract: effectSourceExtentContract,
                requestedWidth: max(1, Int(desiredSize.width.rounded(.up))),
                requestedHeight: max(1, Int(desiredSize.height.rounded(.up))),
                directDrawOutputModelViewProjection:
                    directDrawOutputModelViewProjection,
                materialFunctionInvocations: materialFunctionInvocations(for: layer)
            ))
        }
        guard !requests.isEmpty else {
            return .ready(
                plans: [:],
                localFallbacks: sourceCoverageFallbacks
            )
        }
        guard let offscreenTexturePool else {
            return .rejected(reasonCode: "frame-target-pool-unavailable")
        }
        let result = SceneResolvedMaterialGraphComposition.preflight(
            requests: requests,
            pool: offscreenTexturePool,
            commandBuffer: commandBuffer
        )
        guard case let .ready(plans, localFallbacks) = result else {
            return result
        }
        var mergedFallbacks = sourceCoverageFallbacks
        mergedFallbacks.merge(localFallbacks) { _, graphReason in graphReason }
        return .ready(plans: plans, localFallbacks: mergedFallbacks)
    }

    func resolvedMaterialFramePreparationRequests(
        plans: [Int: SceneResolvedMaterialFrameTargetPlan],
        imageTextures: SceneBaseImageTextureSnapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:],
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainTarget: MTLTexture,
        failureReason: inout String?,
        baseMaterialSelections: inout [Int: SceneBaseMaterialTextureSelection]
    ) -> [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest]? {
        performanceTelemetry?.beginStage("admit-prep-requests")
        defer { performanceTelemetry?.endStage("admit-prep-requests") }
        func invalid(_ reasonCode: String) -> [
            SceneResolvedMaterialRuntimeBridge.FramePreparationRequest
        ]? {
            failureReason = "frame-preparation-request-invalid:\(reasonCode)"
            return nil
        }
        guard !plans.isEmpty else { return [] }
        guard let imagePipeline, offscreenTexturePool != nil else {
            return invalid("shared-input-unavailable")
        }
        let time = Float(frameContext.sceneTime)
        let imageMVP: (SceneRenderDescriptor.Layer, [Float]?) -> simd_float4x4 = {
            layer, renderSizeOverride in
            cameraFrame.viewProjection(for: layer) * self.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                renderSizeOverride: renderSizeOverride,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: cameraFrame.resolvesPerspective(for: layer)
            )
        }
        let geometryMVP: (
            SceneRenderDescriptor.Layer, SceneGeometryProduct
        ) -> simd_float4x4 = { layer, product in
            cameraFrame.viewProjection(for: layer) * self.geometryModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                authoredSize: product.authoredSize,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: cameraFrame.resolvesPerspective(for: layer)
            )
        }
        var result: [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest] = []
        guard let preparationLayerIDs = resolvedMaterialPreparationLayerIDs else {
            return invalid("resolved-material-preparation-order-invalid")
        }
        let materialFunctionMutationsByLayerID = Dictionary(
            grouping: frameContext.materialFunctionMutations,
            by: \.layerID
        )
        for layerID in preparationLayerIDs {
            guard let plan = plans[layerID] else { continue }
            guard let layer = layersByID[layerID],
                  let layerModelMatrix = worldFramesByLayerID[layerID] else {
                return invalid("layer-\(layerID)-world-frame-missing")
            }
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layerID
            )
            guard case let .claimed(claim) = route,
                  claim.token == plan.token else {
                return invalid("layer-\(layerID)-claim-token-mismatch")
            }
            let dependencyEffect: SceneDependencyEffectInput?
            var dependencyEffects: [SceneDependencyEffectInput] = []
            let dependencyUnavailability:
                SceneResolvedMaterialRuntimeBridge.FrameInputs
                    .DependencyUnavailability?
            switch claim.dependencyOwnership {
            case .none, .graphInternal:
                dependencyEffect = nil
                dependencyUnavailability = nil
            case .externalPrimary(let binding):
                guard binding.consumerLayerID == layerID,
                      let providerLayer = layersByID[binding.providerLayerID] else {
                    return invalid("layer-\(layerID)-dependency-binding-invalid")
                }
                let providerMVP = imageMVP(
                    providerLayer,
                    imageTextures.layerSourceRenderSize(for: providerLayer.id)
                )
                let preparedOutputExtent = preparedGraphOutputExtent(for: binding.providerLayerID, plans: plans)
                var dependencyFailureReason: String?
                func reserveDependencyInput(
                    _ source: SceneBaseMaterialTextureSource?
                ) -> SceneDependencyEffectInput? {
                    dependencyRuntime.reserveEffectInput(
                        for: binding,
                        providerLayer: providerLayer,
                        providerTexture: source?.texture,
                        providerCandidate: source?.candidate,
                        layerMVP: providerMVP,
                        viewportSize: frameContext.screenSize,
                        preparedOutputExtent: preparedOutputExtent,
                        frameEpoch: textureRegistry.frameEpoch,
                        failureReason: &dependencyFailureReason
                    )
                }
                if binding.kind == .resolvedMaterial {
                    // A composition provider captures the readable main target.
                    // Its reservation extent comes from typed utility geometry,
                    // so requiring an unrelated base texture would suppress a
                    // provider that can publish later in this same frame.
                    guard let reservedInput = reserveDependencyInput(nil) else {
                        return invalid(
                            "layer-\(layerID)-dependency-input-invalid"
                                + (dependencyFailureReason.map { "-\($0)" } ?? "")
                        )
                    }
                    dependencyEffect = reservedInput
                    dependencyUnavailability = nil
                    break
                }
                let providerSelection = cachedBaseMaterialTextureSelection(
                    for: providerLayer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: providerLayer,
                            dynamicValues: frameContext.dynamicValues
                        ),
                    cache: &baseMaterialSelections
                )
                guard let providerSource = providerSelection.source else {
                    switch providerSelection {
                    case .missing:
                        dependencyEffect = nil
                        dependencyUnavailability = .providerSourceUnavailable
                    case let .rejected(reasonCode):
                        return invalid(
                            "layer-\(layerID)-dependency-provider-source-"
                                + reasonCode
                        )
                    case .source:
                        return invalid(
                            "layer-\(layerID)-dependency-provider-source-invariant"
                        )
                    }
                    break
                }
                guard let reservedInput = reserveDependencyInput(
                    providerSource
                ) else {
                    return invalid(
                        "layer-\(layerID)-dependency-input-invalid"
                            + (dependencyFailureReason.map { "-\($0)" } ?? "")
                    )
                }
                dependencyEffect = reservedInput
                dependencyUnavailability = nil
            case let .externalAggregate(aggregate):
                var aggregateFailureReason: String?
                guard let reservedInputs =
                    reserveExternalAggregateDependencyInputs(
                        aggregate: aggregate,
                        plans: plans,
                        imageTextures: imageTextures,
                        frameContext: frameContext,
                        imageMVP: imageMVP,
                        baseMaterialSelections: &baseMaterialSelections,
                        failureReason: &aggregateFailureReason
                    ) else {
                    return invalid(
                        aggregateFailureReason
                            ?? "multi-provider-reservation-invalid"
                    )
                }
                dependencyEffects = reservedInputs
                dependencyEffect = nil
                dependencyUnavailability = nil
            }
            let sourceMVP: simd_float4x4
            let outputMVP: simd_float4x4
            let sourceTexture: MTLTexture?
            let sourceCandidate: SceneTextureCandidate?
            let sourceUsesAuthoredLayerColor: Bool
            let textureFrame: SceneTextureUVTransform
            let capturesMainTarget: Bool
            let effectSourceExtent: SceneLayerEffectSourceExtent?
            var sourceUniforms: SceneLayerFragmentUniforms? = nil
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                let sourceSelection = cachedBaseMaterialTextureSelection(
                    for: layer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer,
                            dynamicValues: frameContext.dynamicValues
                        ),
                    cache: &baseMaterialSelections
                )
                guard let source = sourceSelection.source else {
                    return invalid(
                        "layer-\(layerID)-source-texture-"
                            + (sourceSelection.rejectedProviderReason ?? "missing")
                    )
                }
                if let geometry = imageTextures.geometryProducts[layerID] {
                    // Effects operate on normalized atlas UV. Scale the unit
                    // effect card to authored pixels for pointer/projection
                    // uniforms; the final mesh draw still consumes raw vertex
                    // positions with the unscaled geometry MVP exactly once.
                    sourceMVP = geometryMVP(layer, geometry)
                        * SceneMatrix.scale(SIMD3(
                            geometry.authoredSize.x,
                            geometry.authoredSize.y,
                            1
                        ))
                } else {
                    sourceMVP = imageMVP(
                        layer,
                        imageTextures.layerSourceRenderSize(for: layerID)
                    )
                }
                outputMVP = sourceMVP
                sourceTexture = source.texture
                sourceCandidate = source.candidate
                sourceUsesAuthoredLayerColor = source.usesAuthoredLayerColor
                textureFrame = spriteAnimations[layerID].map {
                    $0.transform(
                        at: spriteAnimationPlaybackTimes[layerID] ?? 0
                    )
                } ?? .identity
                capturesMainTarget = false
                if layer.contentKind == "solid" {
                    // Solid sources are sized by projected coverage in
                    // preflight, not by an imported image's authored extent.
                    // Use that accepted target, including zero-area helpers.
                    let size = plan.allocation.graphPlan.fullFramePair.descriptor.extent
                    effectSourceExtent = SceneLayerEffectSourceExtent(pixelSize: CGSize(
                        width: size.width, height: size.height
                    ))
                    break
                }
                guard let extent = SceneLayerEffectSourceExtent.resolve(
                        publishedRenderSizeWH:
                            imageTextures.layerSourceEffectRenderSize(for: layerID),
                    authoredRenderSizeWH: layer.renderSizeWH,
                    candidateMappedSize: source.candidate?.mappedSize
                ) else {
                    return invalid(
                        "layer-\(layerID)-effect-source-extent-unavailable"
                    )
                }
                effectSourceExtent = extent
            case .capturedMainTargetTexture:
                guard let utility = layer.utilityLayer,
                      layer.contentKind == utility.kind.rawValue,
                      case .success = SceneUtilityLayerSourceRoute.resolve(
                          layer: layer,
                          descriptor: renderDescriptor
                      ) else {
                    return invalid("layer-\(layerID)-utility-source-shape-invalid")
                }
                sourceMVP = imageMVP(layer, nil)
                guard let geometry = SceneCaptureGeometryResolver.resolve(
                    kind: utility.kind,
                    layerMVP: sourceMVP,
                    viewportSize: frameContext.screenSize
                ) else {
                    return invalid("layer-\(layerID)-utility-geometry-invalid")
                }
                outputMVP = geometry.outputMVP
                sourceTexture = mainTarget
                sourceCandidate = nil
                sourceUsesAuthoredLayerColor = false
                textureFrame = geometry.sourceUV
                capturesMainTarget = true
                effectSourceExtent = SceneLayerEffectSourceExtent(
                    pixelSize: geometry.pixelSize
                )
            case .transparentDirectDraw:
                guard layer.contentKind == "quad",
                      case .authoredCanvasDirectDraw = claim.frameInputContract
                        .emittedOutputGeometrySource,
                      let directDrawOutputMVP =
                        plan.directDrawOutputModelViewProjection else {
                    return invalid(
                        "layer-\(layerID)-direct-draw-output-geometry-invalid"
                    )
                }
                sourceMVP = directDrawOutputMVP
                outputMVP = sourceMVP
                sourceTexture = nil
                sourceCandidate = nil
                sourceUsesAuthoredLayerColor = false
                textureFrame = .identity
                capturesMainTarget = false
                effectSourceExtent = nil
            }
            let effectProjectionMVP: simd_float4x4 = switch
                claim.frameInputContract.effectTextureProjectionSource
            {
            case .emittedOutputGeometry:
                outputMVP
            }
            guard let effectTextureProjectionMatrixInverse =
                    SceneLayerCursorGeometry.effectProjectionInverse(
                        effectProjectionMVP,
                        required: claim.frameInputContract
                            .requiresInvertibleEffectTextureProjection
                    ) else {
                return invalid("layer-\(layerID)-effect-projection-inverse-invalid")
            }
            let cursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: effectProjectionMVP
            )
            let previousCursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.previous,
                modelViewProjection: effectProjectionMVP
            )
            if let texture = sourceTexture {
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: texture,
                    baseTextureCandidate: sourceCandidate,
                    baseTextureSampling: specializedBaseTextureSamplings[layerID],
                    masks: .empty,
                    textureFrame: textureFrame,
                    mvp: outputMVP,
                    uniforms: .init(
                        time: time,
                        alpha: capturesMainTarget ? 1 : SceneDynamicLayerValues.alpha(
                            layerID: layerID,
                            authoredValue: layer.alpha,
                            snapshot: frameContext.dynamicValues
                        ),
                        cursorUV: cursor ?? .zero,
                        previousCursorUV: previousCursor ?? cursor ?? .zero,
                        cursorIsInside:
                            frameContext.pointer.isInside && cursor != nil,
                        previousCursorIsInside:
                            frameContext.pointer.isInside && previousCursor != nil,
                        primaryButtonIsDown:
                            frameContext.pointer.isPrimaryButtonDown,
                        frameTime: Float(frameContext.frameTime),
                        tint: capturesMainTarget || !sourceUsesAuthoredLayerColor
                            ? SIMD3(repeating: 1)
                            : SceneDynamicLayerValues.color(
                            layerID: layerID,
                            authoredValue: layer.colorRGB,
                            snapshot: frameContext.dynamicValues
                        )
                    ),
                    offscreenTexturePool: nil,
                    effectSourceExtent: effectSourceExtent,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil
                )
                guard let uniforms = imageCompositor.sourceFragmentUniforms(
                    for: request,
                    routesOffscreen: true
                ) else {
                    return invalid("layer-\(layerID)-source-uniforms-invalid")
                }
                sourceUniforms = uniforms
            }
            let sceneBackgroundResource: SceneFrameTextureResource?
            if let requirement = claim.sceneBackgroundRequirement {
                guard requirement.layerID == layerID,
                      let resource = SceneFrameTextureResource
                        .sameFrameSceneBackground(
                            consumerLayerID: layerID,
                            frameEpoch: textureRegistry.frameEpoch,
                            texture: mainTarget
                        ) else {
                    return invalid("layer-\(layerID)-scene-background-invalid")
                }
                sceneBackgroundResource = resource
            } else {
                sceneBackgroundResource = nil
            }
            let frameInputs = SceneResolvedMaterialRuntimeBridge.FrameInputs(
                dynamicValues: frameContext.dynamicValues,
                cursorUV: cursor ?? .zero,
                previousCursorUV: previousCursor ?? cursor ?? .zero,
                pointerIsInside: frameContext.pointer.isInside && cursor != nil,
                previousPointerIsInside:
                    frameContext.pointer.isInside && previousCursor != nil,
                pointerMovement: simd_length(
                    frameContext.pointer.current - frameContext.pointer.previous
                ) * 0.5,
                primaryButtonIsDown: frameContext.pointer.isPrimaryButtonDown,
                layerModelMatrix: layerModelMatrix,
                effectTextureProjectionMatrixInverse:
                    effectTextureProjectionMatrixInverse,
                frameTime: Float(frameContext.frameTime),
                time: time,
                audioSpectrum: frameContext.audioSpectrum,
                dependencyEffect: dependencyEffect,
                dependencyEffects: dependencyEffects,
                dependencyUnavailability: dependencyUnavailability
            )
            let materialFunctionInvocations =
                (materialFunctionMutationsByLayerID[layerID] ?? [])
                .map { mutation in
                    let descriptorID: String
                    if layer.effects.indices.contains(mutation.effectIndex) {
                        descriptorID = layer.effects[mutation.effectIndex].id
                    } else {
                        descriptorID = "invalid-effect-index-\(mutation.effectIndex)"
                    }
                    return SceneGraphMaterialFunctionInvocationRequest(
                        effect: .init(
                            layerID: layerID,
                            effectIndex: mutation.effectIndex,
                            descriptorID: descriptorID
                        ),
                        functionName: mutation.functionName,
                        frameEpoch: textureRegistry.frameEpoch
                    )
                }
            let request = SceneResolvedMaterialRuntimeBridge.FramePreparationRequest(
                claim: claim,
                targetPlan: plan,
                materialFunctionInvocations: materialFunctionInvocations,
                sceneBackgroundResource: sceneBackgroundResource,
                sourceTexture: sourceTexture,
                sourceUniforms: sourceUniforms,
                sourcePipeline: imagePipeline,
                frameInputs: frameInputs
            )
            result.append(request)
        }
        guard result.count == plans.count else {
            return invalid("plan-count-mismatch")
        }
        return result
    }

    private func cachedBaseMaterialTextureSelection(
        for layer: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        readyProviderUsesAuthoredLayerColor: Bool,
        cache: inout [Int: SceneBaseMaterialTextureSelection]
    ) -> SceneBaseMaterialTextureSelection {
        // The companion delegates to the canonical `baseMaterialTextureSelection(`
        // owner; this private wrapper preserves the original cache surface.
        cachedBaseMaterialTextureSelectionImpl(
            for: layer,
            imageTextures: imageTextures,
            readyProviderUsesAuthoredLayerColor:
                readyProviderUsesAuthoredLayerColor,
            cache: &cache
        )
    }
}
