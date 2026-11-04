import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    /// Reserves available provider inputs in authored order. Missing sources
    /// leave their operations unavailable; malformed resources remain errors.
    func reserveExternalAggregateDependencyInputs(
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        liveLayerIDs: Set<Int>,
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
            guard liveLayerIDs.contains(binding.providerLayerID),
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
