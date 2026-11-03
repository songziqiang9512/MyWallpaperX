#if DEBUG
extension SceneMetalRenderer {
    func installResolvedMaterialExecutionEvidence(
        reportLines: [String],
        resolvedMaterialLayerIDs: Set<Int>,
        subjects: [SceneResolvedMaterialRuntimeBridge.ExactEffectSubject]
    ) {
        effectExecutionTelemetry.installPreparedAdmission(
            reportLines: reportLines,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        imageCompositor.resolvedMaterialRuntime?.installExecutionEvidence(
            subjects
        )
    }
}

#endif
