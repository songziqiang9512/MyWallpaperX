extension SceneMetalRenderer {
    func installResolvedMaterialExecutionEvidence() {
        let dispositionCatalog = SceneEffectRuntimeDispositionCatalog(
            descriptor: renderDescriptor,
            admissionCatalog: effectAdmissionCatalog,
            resolvedMaterialSubjects: imageCompositor.resolvedMaterialRuntime?
                .runtimeDispositionSubjects ?? []
        )
        imageCompositor.resolvedMaterialRuntime?.installExecutionEvidence(
            dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects
        )
    }
}
