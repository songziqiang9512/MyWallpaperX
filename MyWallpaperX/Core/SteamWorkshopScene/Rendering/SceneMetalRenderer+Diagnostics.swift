extension SceneMetalRenderer {
    func runtimeReportLines() -> [String] {
        let utilityLines = SceneUtilityLayerRuntimePlanner.reportLines(
            descriptor: renderDescriptor,
            resolvedMaterialLayerIDs:
                imageCompositor.resolvedMaterialRuntime?.executionLayerIDs ?? []
        )
        let candidateCount = renderDescriptor.layers.filter {
            $0.contentKind == "spotLight"
        }.count
        let dispositionCatalog = SceneEffectRuntimeDispositionCatalog(
            descriptor: renderDescriptor,
            admissionCatalog: effectAdmissionCatalog,
            resolvedMaterialSubjects: imageCompositor.resolvedMaterialRuntime?
                .runtimeDispositionSubjects ?? []
        )
        imageCompositor.resolvedMaterialRuntime?.installExecutionEvidence(
            dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects
        )
        let dispositionLines = dispositionCatalog.reportLines
            + (imageCompositor.resolvedMaterialRuntime?.executionEvidenceReportLines ?? [])
        return SceneLayerVisibility.reportLines(in: renderDescriptor)
            + utilityLines + effectAdmissionCatalog.reportLines
            + dispositionLines
            + spotLightRuntime.reportLines(candidateCount: candidateCount)
    }

    func unifiedDedicatedEffectStages(
        for layerID: Int
    ) -> [SceneEffectStageExecutionPlan] {
        imageCompositor.resolvedMaterialRuntime?.dedicatedEffectStages(
            for: layerID
        ) ?? []
    }

    var resolvedMaterialExecutionLayerIDs: Set<Int> {
        imageCompositor.resolvedMaterialRuntime?.executionLayerIDs ?? []
    }

    func dedicatedEffectResourceStages(
        for layerID: Int
    ) -> [SceneEffectStageExecutionPlan] {
        unifiedDedicatedEffectStages(for: layerID)
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

    func effectRuntimeSummary(
        for layer: SceneRenderDescriptor.Layer
    ) -> String? {
        if effectAdmissionCatalog.resolvedMaterialExecutionLayerIDs.contains(layer.id) {
            return "effect runtime resolved-material-graph; graph owner"
        }
        return nil
    }
}
