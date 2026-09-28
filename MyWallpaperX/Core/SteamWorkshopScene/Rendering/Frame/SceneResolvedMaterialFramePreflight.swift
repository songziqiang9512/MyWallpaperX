import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    func admitResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        frameVisibleLayerIDs: Set<Int>,
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
        // fallback state are refreshed above, then shared by the single
        // preflight walk that also builds the preparation requests below.
        var baseMaterialSelections: [Int: SceneBaseMaterialTextureSelection] = [:]
        switch preflightResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            spriteAnimations: spriteAnimations,
            spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
            performanceTelemetry: performanceTelemetry,
            specializedBaseTextureSamplings: specializedBaseTextureSamplings,
            imagePipeline: imagePipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameVisibleLayerIDs: frameVisibleLayerIDs,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            mainTarget: mainTarget,
            commandBuffer: commandBuffer,
            baseMaterialSelections: &baseMaterialSelections
        ) {
        case let .ready(plans, localFallbacks, preparationRequests):
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
            performanceTelemetry?.beginStage("admit-prepare-frame")
            defer { performanceTelemetry?.endStage("admit-prepare-frame") }
            switch imageCompositor.prepareResolvedMaterialFrame(
                preparationRequests,
                pool: offscreenTexturePool,
                commandBuffer: commandBuffer,
                performanceTelemetry: performanceTelemetry
            ) {
            case .ready:
                // Observation only: splits admit-prepare-frame into the
                // coordinator's preparation and the provider-output install so
                // the remaining unattributed share can be located.
                performanceTelemetry?.beginStage("admit-install-graph-outputs")
                defer {
                    performanceTelemetry?.endStage("admit-install-graph-outputs")
                }
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
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:],
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameVisibleLayerIDs: Set<Int>,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainTarget: MTLTexture,
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
        // The renderer already walked the frame's visible layer set from the
        // same snapshot. The dependency runtime intersects it with the base
        // execution layers (dynamic-layer IDs drop out there); a destroyed
        // base layer stays equivalent as well — a destroyed provider is
        // pulled back in by the consumer-closure expansion whenever a
        // visible consumer needs it, so the second full walk is redundant.
        let frameVisibleRootLayerIDs = frameVisibleLayerIDs
        let activeExecutionLayerIDs = dependencyRuntime
            .resolvedMaterialExecutionLayerIDs(
                visibleRootLayerIDs: frameVisibleRootLayerIDs,
                availableExecutionLayerIDs: availableExecutionLayerIDs
            )
        var byLayerID: [Int: SceneResolvedMaterialFrameTargetPlan] = [:]
        var allocationPlans: [ScenePersistentGraphTargetFramePlan] = []
        var preparationRequests: [
            SceneResolvedMaterialRuntimeBridge.FramePreparationRequest
        ] = []
        var sourceCoverageFallbacks: [Int: String] = [:]
        var graphTargetFallbacks: [Int: String] = [:]
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
        func invalid(
            _ reasonCode: String
        ) -> SceneResolvedMaterialGraphComposition.FramePreflightResult {
            .rejected(reasonCode: "frame-preparation-request-invalid:\(reasonCode)")
        }
        let orderingContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: commandBuffer
        )
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
        for layer in orderedLayers {
            let layerID = layer.id
            var directDrawOutputModelViewProjection: simd_float4x4?
            // Values the preparation request consumes, captured by the same
            // single pass that sizes the frame target.
            var capturedLayerSource: SceneBaseMaterialTextureSource?
            var utilityCaptureGeometry: SceneCaptureGeometry?
            var effectSourceExtent: SceneLayerEffectSourceExtent?
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
                layerID
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
                    sourceCoverageFallbacks[layerID] = "layer-source-not-ready"
                    continue
                case let .rejected(reasonCode):
                    return .rejected(reasonCode: reasonCode)
                }
                capturedLayerSource = selectedSource
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
                    effectSourceExtent = extent
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
                utilityCaptureGeometry = geometry
                desiredSize = geometry.pixelSize
            case .transparentDirectDraw:
                guard layer.contentKind == "quad",
                      case .authoredCanvasDirectDraw =
                        claim.frameInputContract.emittedOutputGeometrySource,
                      let model = directDrawOutputModelMatrix(
                          for: layer,
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
            let invocations = materialFunctionInvocations(for: layer)
            var invocationFailure: String?
            var materialFunctionTargetsByEffect: [
                SceneAuthoredEffectRenderPlan.EffectKey:
                    Set<SceneAuthoredEffectRenderPlan.TextureIdentity>
            ] = [:]
            for invocation in invocations {
                guard claim.admittedGraphs.contains(where: {
                    $0.effects.first?.key == invocation.effect
                }) else {
                    invocationFailure = "function-invocation-unknown-effect"
                    break
                }
                guard let function = claim.clearFunctionsByEffect[invocation.effect]
                    .flatMap({ $0.function(named: invocation.functionName) }) else {
                    invocationFailure = "function-invocation-unknown-function"
                    break
                }
                materialFunctionTargetsByEffect[invocation.effect, default: []]
                    .formUnion(function.targets)
            }
            if let invocationFailure {
                graphTargetFallbacks[claim.layerID] = invocationFailure
                continue
            }
            let requestedWidth = max(1, Int(desiredSize.width.rounded(.up)))
            let requestedHeight = max(1, Int(desiredSize.height.rounded(.up)))
            guard requestedWidth > 0, requestedHeight > 0 else {
                graphTargetFallbacks[claim.layerID] = "frame-target-plan-rejected"
                continue
            }
            guard let offscreenTexturePool else {
                return .rejected(reasonCode: "frame-target-pool-unavailable")
            }
            let allocation: ScenePersistentGraphTargetFramePlan
            switch offscreenTexturePool.framePlanResultForPersistentGraphTargets(
                admittedGraphs: claim.admittedGraphs,
                materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
                pairPlan: claim.pairPlan,
                extentPolicy: effectSourceExtentContract.targetPolicy,
                requestedWidth: requestedWidth,
                requestedHeight: requestedHeight,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: orderingContext,
                plansMemoIdentity: .init(
                    capabilityToken: claim.token,
                    layerID: claim.layerID
                )
            ) {
            case let .success(value): allocation = value
            case let .failure(failure):
                graphTargetFallbacks[claim.layerID] =
                    failure.localFallbackReasonCode
                continue
            }
            let consumesExternalPrimaryDependency: Bool
            switch claim.dependencyOwnership {
            case .externalPrimary, .externalAggregate:
                consumesExternalPrimaryDependency = true
            default:
                consumesExternalPrimaryDependency = false
            }
            let frameTargetPlan = SceneResolvedMaterialFrameTargetPlan(
                token: claim.token,
                allocation: allocation,
                consumesExternalPrimaryDependency: consumesExternalPrimaryDependency,
                directDrawOutputModelViewProjection:
                    directDrawOutputModelViewProjection
            )
            guard allocation.graphPlan.key.layerID == claim.layerID,
                  byLayerID.updateValue(frameTargetPlan, forKey: claim.layerID) == nil
            else {
                graphTargetFallbacks[claim.layerID] = "frame-target-plan-rejected"
                continue
            }
            allocationPlans.append(allocation)
            // The preparation request for this layer is assembled in the same
            // pass; dependency providers precede consumers in the preparation
            // order, so every `preparedGraphOutputExtent` lookup below sees
            // the same projection the former second walk read from the
            // completed plan dictionary.
            guard let layerModelMatrix = worldFramesByLayerID[layerID] else {
                return invalid("layer-\(layerID)-world-frame-missing")
            }
            var dependencyEffects: [SceneDependencyEffectInput] = []
            let dependencyUnavailability:
                SceneResolvedMaterialRuntimeBridge.FrameInputs
                    .DependencyUnavailability?
            switch claim.dependencyOwnership {
            case .none, .graphInternal:
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
                let preparedOutputExtent = preparedGraphOutputExtent(
                    for: binding.providerLayerID,
                    plans: byLayerID
                )
                var dependencyFailureReason: String?
                func reserveDependencyInput(
                    _ source: SceneBaseMaterialTextureSource?
                ) -> SceneDependencyEffectInput? {
                    let geometryProduct: SceneGeometryProduct?
                    let providerOutputMVP: simd_float4x4?
                    let consumerOutputMVP: simd_float4x4?
                    if binding.kind == .geometryLayer,
                       let source,
                       let product = imageTextures.geometryProduct(
                           for: providerLayer.id,
                           matching: source.texture
                       ) {
                        geometryProduct = product
                        providerOutputMVP = geometryMVP(providerLayer, product)
                            * SceneMatrix.scale(SIMD3(
                                product.authoredSize.x,
                                product.authoredSize.y,
                                1
                            ))
                        if let consumerProduct = imageTextures.geometryProducts[
                            layer.id
                        ] {
                            consumerOutputMVP = geometryMVP(
                                layer,
                                consumerProduct
                            ) * SceneMatrix.scale(SIMD3(
                                consumerProduct.authoredSize.x,
                                consumerProduct.authoredSize.y,
                                1
                            ))
                        } else {
                            consumerOutputMVP = imageMVP(
                                layer,
                                imageTextures.layerSourceRenderSize(
                                    for: layer.id
                                )
                            )
                        }
                    } else {
                        geometryProduct = nil
                        providerOutputMVP = nil
                        consumerOutputMVP = nil
                    }
                    return dependencyRuntime.reserveEffectInput(
                        for: binding,
                        providerLayer: providerLayer,
                        providerTexture: source?.texture,
                        providerCandidate: source?.candidate,
                        layerMVP: providerMVP,
                        viewportSize: frameContext.screenSize,
                        preparedOutputExtent: preparedOutputExtent,
                        geometryProduct: geometryProduct,
                        providerOutputMVP: providerOutputMVP,
                        consumerOutputMVP: consumerOutputMVP,
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
                    dependencyEffects = [reservedInput]
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
                        dependencyEffects = []
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
                dependencyEffects = [reservedInput]
                dependencyUnavailability = nil
            case let .externalAggregate(aggregate):
                var aggregateFailureReason: String?
                guard let reservedInputs =
                    reserveExternalAggregateDependencyInputs(
                        aggregate: aggregate,
                        plans: byLayerID,
                        imageTextures: imageTextures,
                        frameContext: frameContext,
                        imageMVP: imageMVP,
                        geometryMVP: geometryMVP,
                        baseMaterialSelections: &baseMaterialSelections,
                        failureReason: &aggregateFailureReason
                    ) else {
                    return invalid(
                        aggregateFailureReason
                            ?? "multi-provider-reservation-invalid"
                    )
                }
                dependencyEffects = reservedInputs
                dependencyUnavailability = nil
            }
            let sourceMVP: simd_float4x4
            let outputMVP: simd_float4x4
            let sourceTexture: MTLTexture?
            let sourceCandidate: SceneTextureCandidate?
            let sourceUsesAuthoredLayerColor: Bool
            let textureFrame: SceneTextureUVTransform
            let capturesMainTarget: Bool
            var sourceUniforms: SceneLayerFragmentUniforms? = nil
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                guard let source = capturedLayerSource else {
                    return invalid("layer-\(layerID)-source-texture-missing")
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
                    let size = frameTargetPlan.allocation.graphPlan.fullFramePair
                        .descriptor.extent
                    effectSourceExtent = SceneLayerEffectSourceExtent(pixelSize: CGSize(
                        width: size.width, height: size.height
                    ))
                }
            case .capturedMainTargetTexture:
                sourceMVP = imageMVP(layer, nil)
                guard let geometry = utilityCaptureGeometry else {
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
                guard let directDrawOutputMVP =
                        directDrawOutputModelViewProjection else {
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
                    SceneLayerCursorGeometry.effectTextureProjectionInverse(
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
                    finalCompositeAlpha: nil
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
                effectOutputModelViewProjection: effectProjectionMVP,
                effectTextureProjectionMatrixInverse:
                    effectTextureProjectionMatrixInverse,
                frameTime: Float(frameContext.frameTime),
                time: time,
                audioSpectrum: frameContext.audioSpectrum,
                dependencyEffects: dependencyEffects,
                dependencyUnavailability: dependencyUnavailability
            )
            guard let imagePipeline else {
                return invalid("shared-input-unavailable")
            }
            preparationRequests.append(.init(
                claim: claim,
                targetPlan: frameTargetPlan,
                materialFunctionInvocations: invocations,
                sceneBackgroundResource: sceneBackgroundResource,
                sourceTexture: sourceTexture,
                sourceUniforms: sourceUniforms,
                sourcePipeline: imagePipeline,
                frameInputs: frameInputs
            ))
        }
        guard !byLayerID.isEmpty else {
            // Every attempted planning failed: the graph-target fallbacks
            // must still install so the skipped claimed layers keep taking
            // the bounded local-fallback claim route instead of a hard
            // frame drop.
            var mergedFallbacks = sourceCoverageFallbacks
            mergedFallbacks.merge(graphTargetFallbacks) { _, graphReason in
                graphReason
            }
            return .ready(
                plans: [:],
                localFallbacks: mergedFallbacks,
                preparationRequests: []
            )
        }
        guard let offscreenTexturePool else {
            return .rejected(reasonCode: "frame-target-pool-unavailable")
        }
        switch offscreenTexturePool.preflightPersistentGraphTargets(
            allocationPlans
        ) {
        case .ready:
            var mergedFallbacks = sourceCoverageFallbacks
            mergedFallbacks.merge(graphTargetFallbacks) { _, graphReason in
                graphReason
            }
            return .ready(
                plans: byLayerID,
                localFallbacks: mergedFallbacks,
                preparationRequests: preparationRequests
            )
        case .temporarilyBlocked:
            return .deferred
        case .rejected(let reasonCode):
            return .rejected(reasonCode: reasonCode)
        }
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
