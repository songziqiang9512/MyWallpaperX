extension SceneMetalRenderer {
    func runtimeReportLines() -> [String] {
        let utilityLines = SceneUtilityLayerRuntimePlanner.reportLines(
            descriptor: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog
        )
        let candidateCount = renderDescriptor.layers.filter {
            $0.contentKind == "spotLight"
        }.count
        return utilityLines + authoredEffectCatalog.reportLines
            + spotLightRuntime.reportLines(candidateCount: candidateCount)
    }

    func authoredEffectPlan(for layerID: Int) -> SceneAuthoredEffectExecutionPlan? {
        authoredEffectCatalog.plansByLayerID[layerID]
    }

    func authoredEffectChain(for layerID: Int) -> SceneAuthoredEffectExecutionChain? {
        authoredEffectCatalog.chainsByLayerID[layerID]
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
        if let chain = authoredEffectChain(for: layer.id), chain.stages.count > 1 {
            let suffix = chain.irisInlineSuffix == nil ? "" : "; iris inline suffix"
            return "effect runtime authored-chain; \(chain.stages.count) stage(s); "
                + "\(chain.materialNodeCount) material pass(es)\(suffix)"
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
