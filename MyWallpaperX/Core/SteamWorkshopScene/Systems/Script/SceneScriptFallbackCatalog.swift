import Foundation

/// Preserves the exact authored value whenever a shared-VM owner is absent
/// from the committed candidate. This catalog never evaluates JavaScript.
nonisolated struct SceneScriptFallbackCatalog: Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let targets: Set<SceneDynamicTarget>

    init?(
        authoredDescriptor: SceneRenderDescriptor,
        runtimeDescriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        vectorProjection: SceneScriptVectorCandidateCatalog,
        constructionReport: SceneScriptQuickJSProgramConstructionReport,
        timelineTargets: Set<SceneDynamicTarget>,
        scalarExcludedTargets: Set<SceneDynamicTarget>,
        stringExcludedTargets: Set<SceneDynamicTarget>,
        routeDisabledTargets: Set<SceneDynamicTarget>
    ) {
        let fallbackTargets = Set(constructionReport.vectorFailures.keys)
            .union(constructionReport.scalarFailures.keys)
            .union(constructionReport.stringFailures.keys)
            .union(routeDisabledTargets)
        targets = fallbackTargets
        definitions = (
            vectorProjection.uniqueCandidates.map(\.definition)
            + SceneScriptScalarProgram.projectedDefinitions(
                descriptor: authoredDescriptor,
                scriptBindings: scriptBindings,
                timelineTargets: timelineTargets,
                excludedTargets: scalarExcludedTargets
            )
            + SceneScriptStringProgram.projectedDefinitions(
                descriptor: runtimeDescriptor,
                scriptBindings: scriptBindings,
                excludedTargets: stringExcludedTargets
            )
        ).filter { fallbackTargets.contains($0.target) }
        guard Set(definitions.map(\.target)) == targets,
              Set(definitions.map(\.target)).count == definitions.count else {
            return nil
        }
    }
}
