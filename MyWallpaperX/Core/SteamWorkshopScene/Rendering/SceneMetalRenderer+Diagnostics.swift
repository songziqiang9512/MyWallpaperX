extension SceneMetalRenderer {
    func runtimeReportLines(
        effectTextures: SceneLayerEffectTextureStore
    ) -> [String] {
        let utilityLines = SceneUtilityLayerRuntimePlanner.reportLines(
            descriptor: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog,
            resolvedMaterialLayerIDs:
                imageCompositor.resolvedMaterialRuntime?.executionLayerIDs ?? []
        )
        let candidateCount = renderDescriptor.layers.filter {
            $0.contentKind == "spotLight"
        }.count
        let resourceAvailability = Dictionary(uniqueKeysWithValues:
            renderDescriptor.layers.filter { !$0.effects.isEmpty }.map { layer in
                (layer.id, SceneLegacyEffectResourceAvailability(
                    hasIrisMask: effectTextures.irisMasks[layer.id] != nil,
                    hasOpacityMask: effectTextures.opacityMasks[layer.id] != nil,
                    hasWaterMask: effectTextures.waterMasks[layer.id] != nil,
                    hasFoliageMask: effectTextures.foliageMasks[layer.id] != nil,
                    hasWaterRippleNormal:
                        effectTextures.waterRippleNormals[layer.id] != nil
                ))
            }
        )
        let dispositionCatalog = SceneEffectRuntimeDispositionCatalog(
            descriptor: renderDescriptor,
            authoredCatalog: authoredEffectCatalog,
            resourcesByLayerID: resourceAvailability,
            resolvedMaterialSubjects: imageCompositor.resolvedMaterialRuntime?
                .runtimeDispositionSubjects ?? []
        )
        imageCompositor.resolvedMaterialRuntime?.installExecutionEvidence(
            dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects
        )
        let dispositionLines = dispositionCatalog.reportLines
            + (imageCompositor.resolvedMaterialRuntime?.executionEvidenceReportLines ?? [])
        return utilityLines + authoredEffectCatalog.reportLines
            + dispositionLines
            + spotLightRuntime.reportLines(candidateCount: candidateCount)
    }

    func authoredEffectPlan(for layerID: Int) -> SceneAuthoredEffectExecutionPlan? {
        authoredEffectCatalog.plansByLayerID[layerID]
    }

    func authoredEffectChain(for layerID: Int) -> SceneAuthoredEffectExecutionChain? {
        authoredEffectCatalog.chainsByLayerID[layerID]
    }

    func unifiedDedicatedEffectStages(
        for layerID: Int
    ) -> [SceneAuthoredEffectExecutionPlan] {
        imageCompositor.resolvedMaterialRuntime?.dedicatedEffectStages(
            for: layerID
        ) ?? []
    }

    var resolvedMaterialExecutionLayerIDs: Set<Int> {
        imageCompositor.resolvedMaterialRuntime?.executionLayerIDs ?? []
    }

    func effectTextureStages(
        for layerID: Int
    ) -> [SceneAuthoredEffectExecutionPlan] {
        let unified = unifiedDedicatedEffectStages(for: layerID)
        return unified.isEmpty
            ? authoredEffectChain(for: layerID)?.executionStages ?? []
            : unified
    }

    func blocksLegacyGaussianBlur(for layerID: Int) -> Bool {
        authoredEffectCatalog.legacyGaussianBlurBlockedLayerIDs.contains(layerID)
    }

    func debugPlacementSummary(for layer: SceneRenderDescriptor.Layer) -> String {
        SceneLayerPlacementSummary.make(
            layer: layer,
            worldFrame: worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        )
    }

    func diagnostics() -> SceneMetalRendererDiagnostic {
        let layers = renderDescriptor.layers
        let imageCount = layers.filter(\.isImageRenderable).count
        let particleCount = layers.filter { $0.contentKind == "particle" }.count
        let textCount = layers.filter { $0.contentKind == "text" }.count
        let containerCount = layers.filter { $0.contentKind == "container" }.count
        let effectPassCount = layers.flatMap(\.effects).flatMap(\.passes).count

        var gaps = renderDescriptor.firstStageRendererGaps
        if effectPassCount > 0 {
            gaps.append("effect shader execution (\(effectPassCount) passes)")
        }
        if renderDescriptor.materialPasses.contains(where: { $0.shaderPath != nil }) {
            gaps.append("material shader compilation")
        }
        return SceneMetalRendererDiagnostic(
            imageLayerCount: imageCount,
            particleLayerCount: particleCount,
            textLayerCount: textCount,
            containerLayerCount: containerCount,
            effectPassCount: effectPassCount,
            materialPassCount: renderDescriptor.materialPasses.count,
            rendererGaps: gaps
        )
    }

    func offscreenPassCount(for layer: SceneRenderDescriptor.Layer) -> Int {
        authoredEffectChain(for: layer.id)?.materialNodeCount
            ?? SceneEffectRuntimePlanner.offscreenPassCount(for: layer)
    }

    func effectRuntimeSummary(
        for layer: SceneRenderDescriptor.Layer,
        hasWaterRippleNormal: Bool = false,
        hasOpacityMask: Bool = false,
        hasWaterMask: Bool = false,
        hasFoliageMask: Bool = false
    ) -> String? {
        if let chain = authoredEffectChain(for: layer.id) {
            let executionStageCount = chain.executionStages.count
            if executionStageCount > 1 {
                let suffix = chain.irisInlineSuffix == nil
                    ? ""
                    : "; iris inline suffix"
                return "effect runtime authored-chain; \(executionStageCount) stage(s); "
                    + "\(chain.materialNodeCount) material pass(es)\(suffix)"
            }
        }
        return SceneEffectRuntimePlanner.runtimeSummary(
            for: layer,
            hasWaterRippleNormal: hasWaterRippleNormal,
            hasOpacityMask: hasOpacityMask,
            hasWaterMask: hasWaterMask,
            hasFoliageMask: hasFoliageMask,
            authoredEffectPlan: authoredEffectPlan(for: layer.id),
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur(for: layer.id)
        )
    }
}
