import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    /// Reserves the complete provider vector for one multi-provider claim.
    /// Every member is resolved and reserved in the plan's authored order; a
    /// missing source or malformed reservation rejects the whole unsafe unit.
    func reserveExternalAggregateDependencyInputs(
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        plans: [Int: SceneResolvedMaterialFrameTargetPlan],
        imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext,
        imageMVP: (SceneRenderDescriptor.Layer, [Float]?) -> simd_float4x4,
        baseMaterialSelections: inout [Int: SceneBaseMaterialTextureSelection],
        failureReason: inout String?
    ) -> [SceneDependencyEffectInput]? {
        guard aggregate.hasStrictBindingVector else {
            failureReason = "multi-provider-binding-vector-invalid"
            return nil
        }
        var dependencyEffects: [SceneDependencyEffectInput] = []
        for binding in aggregate.bindings {
            guard let providerLayer = layersByID[binding.providerLayerID] else {
                failureReason = "multi-provider-provider-missing"
                return nil
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
                failureReason =
                    "multi-provider-provider-source-"
                        + (providerSelection.rejectedProviderReason ?? "missing")
                return nil
            }
            var reason: String?
            guard let input = dependencyRuntime.reserveEffectInput(
                for: binding,
                providerLayer: providerLayer,
                providerTexture: providerSource.texture,
                providerCandidate: providerSource.candidate,
                layerMVP: imageMVP(
                    providerLayer,
                    imageTextures.layerSourceRenderSize(for: providerLayer.id)
                ),
                viewportSize: frameContext.screenSize,
                preparedOutputExtent: preparedGraphOutputExtent(
                    for: providerLayer.id,
                    plans: plans
                ),
                frameEpoch: textureRegistry.frameEpoch,
                failureReason: &reason
            ) else {
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

    /// Shared frame-local source-selection cache owner. The private wrapper in
    /// the main preflight file keeps its original access surface for callers;
    /// this implementation is shared by aggregate reservation as well.
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
