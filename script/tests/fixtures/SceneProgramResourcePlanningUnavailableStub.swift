// Controlled boundary for compiler/value-only fixtures that do not compile
// the complete QuickJS family catalog. These gates do not claim resource
// discovery; test_scene_script_program_resources runs the real shared planner.
nonisolated enum SceneScriptQuickJSProgramCandidate {
    static func plannedOwnerSources(
        authoredDescriptor: SceneRenderDescriptor,
        runtimeDescriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        vectorProjection: SceneScriptVectorCandidateCatalog,
        plannedVectorTargets: Set<SceneDynamicTarget>,
        timelineTargets: Set<SceneDynamicTarget>,
        scalarExcludedTargets: Set<SceneDynamicTarget>,
        stringExcludedTargets: Set<SceneDynamicTarget>,
        excludedStandaloneCursorLayerIDs: Set<Int>,
        dynamicImageRequestsOnly: Bool = false
    ) -> [String] { [] }
}
