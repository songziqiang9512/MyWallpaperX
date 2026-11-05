import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    func reserveResolvedMaterialDependencyInputs(
        ownership: SceneResolvedMaterialDependencyOwnership,
        excludingSlots: Set<SceneEffectPassSlot>,
        layer: SceneRenderDescriptor.Layer,
        liveLayerIDs: Set<Int>, pendingGraphLayerIDs: Set<Int>,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        plans: [Int: SceneResolvedMaterialFrameTargetPlan],
        imageTextures: SceneBaseImageTextureSnapshot, frameContext: SceneFrameContext,
        imageMVP: (SceneRenderDescriptor.Layer, [Float]?) -> simd_float4x4,
        providerPlacement: (SceneRenderDescriptor.Layer) -> (mvp: simd_float4x4, viewport: CGSize),
        geometryMVP: (SceneRenderDescriptor.Layer, SceneGeometryProduct) -> simd_float4x4,
        baseMaterialSelections: inout [Int: SceneBaseMaterialTextureSelection],
        failureReason: inout String?
    ) -> (effects: [SceneDependencyEffectInput],
          unavailable: SceneResolvedMaterialRuntimeBridge.FrameInputs.DependencyUnavailability?)? {
        let layerID = layer.id
        var dependencyEffects: [SceneDependencyEffectInput] = []
        let dependencyUnavailability: SceneResolvedMaterialRuntimeBridge.FrameInputs.DependencyUnavailability?
        switch ownership {
        case .none, .graphInternal:
            dependencyUnavailability = nil
        case .externalPrimary(let binding):
            if binding.referenceSlots.allSatisfy(excludingSlots.contains) {
                return ([], .providerSourceUnavailable)
            }
            guard !pendingGraphLayerIDs.contains(binding.providerLayerID),
                  liveLayerIDs.contains(binding.providerLayerID),
                  !dependencyRuntime.plan.cyclicLayerIDs.contains(binding.providerLayerID),
                  let providerLayer = layersByID[binding.providerLayerID] else {
                dependencyEffects = []
                dependencyUnavailability = .providerSourceUnavailable
                break
            }
            let placement = providerPlacement(providerLayer)
            let preparedOutputExtent = preparedGraphOutputExtent(
                for: binding.providerLayerID,
                plans: plans
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
                    layerMVP: placement.mvp,
                    viewportSize: placement.viewport,
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
                    failureReason = "layer-\(layerID)-dependency-input-invalid"
                        + (dependencyFailureReason.map { "-\($0)" } ?? "")
                    return nil
                }
                dependencyEffects = [reservedInput]
                dependencyUnavailability = nil
                break
            }
            let providerSelection = cachedBaseMaterialTextureSelectionImpl(
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
                case .missing, .pendingAuthoredVideo:
                    dependencyEffects = []
                    dependencyUnavailability = .providerSourceUnavailable
                case let .rejected(reasonCode):
                    failureReason = "layer-\(layerID)-dependency-provider-source-" + reasonCode
                    return nil
                case .source:
                    failureReason = "layer-\(layerID)-dependency-provider-source-invariant"
                    return nil
                }
                break
            }
            if binding.kind == .geometryLayer,
               imageTextures.geometryProducts[providerLayer.id] == nil {
                dependencyEffects = []
                dependencyUnavailability = .providerSourceUnavailable
                break
            }
            guard let reservedInput = reserveDependencyInput(
                providerSource
            ) else {
                if dependencyFailureReason == "image-provider-mapping-unavailable" {
                    dependencyEffects = []
                    dependencyUnavailability = .providerSourceUnavailable
                    break
                }
                failureReason = "layer-\(layerID)-dependency-input-invalid"
                    + (dependencyFailureReason.map { "-\($0)" } ?? "")
                return nil
            }
            dependencyEffects = [reservedInput]
            dependencyUnavailability = nil
        case let .externalAggregate(aggregate):
            var aggregateFailureReason: String?
            guard let reservedInputs =
                reserveExternalAggregateDependencyInputs(
                    aggregate: aggregate, excludingSlots: excludingSlots,
                    liveLayerIDs: liveLayerIDs,
                    pendingGraphLayerIDs: pendingGraphLayerIDs,
                    layersByID: layersByID,
                    plans: plans,
                    imageTextures: imageTextures,
                    frameContext: frameContext,
                    imageMVP: imageMVP,
                    providerPlacement: providerPlacement,
                    geometryMVP: geometryMVP,
                    baseMaterialSelections: &baseMaterialSelections,
                    failureReason: &aggregateFailureReason
                ) else {
                failureReason = aggregateFailureReason ?? "multi-provider-reservation-invalid"
                return nil
            }
            dependencyEffects = reservedInputs
            dependencyUnavailability = nil
        }
        return (dependencyEffects, dependencyUnavailability)
    }

    /// Reserves available provider inputs in authored order. Missing sources
    /// leave their operations unavailable; malformed resources remain errors.
    func reserveExternalAggregateDependencyInputs(
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        excludingSlots: Set<SceneEffectPassSlot>,
        liveLayerIDs: Set<Int>,
        pendingGraphLayerIDs: Set<Int>,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        plans: [Int: SceneResolvedMaterialFrameTargetPlan],
        imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext,
        imageMVP: (SceneRenderDescriptor.Layer, [Float]?) -> simd_float4x4,
        providerPlacement: (SceneRenderDescriptor.Layer) -> (mvp: simd_float4x4, viewport: CGSize),
        geometryMVP: (
            SceneRenderDescriptor.Layer, SceneGeometryProduct
        ) -> simd_float4x4,
        baseMaterialSelections: inout [Int: SceneBaseMaterialTextureSelection],
        failureReason: inout String?
    ) -> [SceneDependencyEffectInput]? {
        guard let consumerLayer = layersByID[aggregate.consumerLayerID] else {
            failureReason = "multi-provider-consumer-missing"
            return nil
        }
        let consumerOutputMVP = imageMVP(
            consumerLayer,
            imageTextures.layerSourceRenderSize(for: consumerLayer.id)
        )
        var dependencyEffects: [SceneDependencyEffectInput] = []
        for binding in aggregate.bindings {
            if binding.referenceSlots.allSatisfy(excludingSlots.contains) { continue }
            guard !pendingGraphLayerIDs.contains(binding.providerLayerID),
                  liveLayerIDs.contains(binding.providerLayerID),
                  !dependencyRuntime.plan.cyclicLayerIDs.contains(binding.providerLayerID),
                  let providerLayer = layersByID[binding.providerLayerID] else { continue }
            let providerSource: SceneBaseMaterialTextureSource?
            if binding.kind == .resolvedMaterial {
                providerSource = nil
            } else {
                switch cachedBaseMaterialTextureSelectionImpl(
                    for: providerLayer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: providerLayer,
                            dynamicValues: frameContext.dynamicValues
                        ),
                    cache: &baseMaterialSelections
                ) {
                case let .source(source): providerSource = source
                case .missing, .pendingAuthoredVideo: continue
                case let .rejected(reason):
                    failureReason = "multi-provider-provider-source-" + reason
                    return nil
                }
            }
            let geometryProduct: SceneGeometryProduct?
            let providerOutputMVP: simd_float4x4?
            if binding.kind == .geometryLayer {
                guard let product = imageTextures.geometryProducts[providerLayer.id]
                else { continue }
                geometryProduct = product
                providerOutputMVP = geometryMVP(providerLayer, product)
                    * SceneMatrix.scale(SIMD3(
                        product.authoredSize.x,
                        product.authoredSize.y,
                        1
                    ))
            } else {
                geometryProduct = nil
                providerOutputMVP = nil
            }
            var reason: String?
            let placement = providerPlacement(providerLayer)
            guard let input = dependencyRuntime.reserveEffectInput(
                for: binding,
                providerLayer: providerLayer,
                providerTexture: providerSource?.texture,
                providerCandidate: providerSource?.candidate,
                layerMVP: placement.mvp,
                viewportSize: placement.viewport,
                preparedOutputExtent: preparedGraphOutputExtent(
                    for: providerLayer.id,
                    plans: plans
                ),
                geometryProduct: geometryProduct,
                providerOutputMVP: providerOutputMVP,
                consumerOutputMVP: binding.kind == .geometryLayer
                    ? consumerOutputMVP : nil,
                frameEpoch: textureRegistry.frameEpoch,
                failureReason: &reason
            ) else {
                if reason == "image-provider-mapping-unavailable" { continue }
                failureReason =
                    "multi-provider-reservation-invalid"
                        + (reason.map { "-\($0)" } ?? "")
                return nil
            }
            dependencyEffects.append(input)
        }
        return dependencyEffects
    }

    func preparedGraphOutputExtent(
        for providerLayerID: Int,
        plans: [Int: SceneResolvedMaterialFrameTargetPlan]
    ) -> (width: Int, height: Int)? {
        guard dependencyRuntime.plan.requiredGraphOutputProviderLayerIDs
            .contains(providerLayerID),
              let providerPlan = plans[providerLayerID] else {
            return nil
        }
        let extent = providerPlan.allocation.graphPlan.fullFramePair.descriptor.extent
        return (extent.width, extent.height)
    }

    /// Shared frame-local source-selection cache owner. Both the main
    /// preflight pass and aggregate reservation call this implementation
    /// directly for their frame-local cache surface.
    func cachedBaseMaterialTextureSelectionImpl(
        for layer: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        readyProviderUsesAuthoredLayerColor: Bool,
        cache: inout [Int: SceneBaseMaterialTextureSelection]
    ) -> SceneBaseMaterialTextureSelection {
        if let cached = cache[layer.id] {
            return cached
        }
        let selection = baseMaterialTextureSelection(
            for: layer,
            imageTextures: imageTextures,
            readyProviderUsesAuthoredLayerColor:
                readyProviderUsesAuthoredLayerColor
        )
        cache[layer.id] = selection
        return selection
    }
}
