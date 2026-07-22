extension SceneMetalRenderer {
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
        SceneEffectRuntimePlanner.offscreenPassCount(for: layer)
    }

    func effectRuntimeSummary(
        for layer: SceneRenderDescriptor.Layer,
        hasWaterRippleNormal: Bool = false,
        hasOpacityMask: Bool = false,
        hasWaterMask: Bool = false,
        hasFoliageMask: Bool = false
    ) -> String? {
        SceneEffectRuntimePlanner.runtimeSummary(
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
