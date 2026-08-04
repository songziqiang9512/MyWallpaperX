import Foundation

nonisolated extension SceneAuthoredEffectExecutionChain {
    enum LegacyRecoveryKind: Equatable {
        case terminalIrisInlineSuffix
        case xRayPrefix
        case isolatedCursorRipple
        case isolatedShine
    }

    enum ExecutionRoute {
        case completePrograms
        case legacyRecovery(LegacyRecoveryKind)
    }

    private init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        stagePrograms: [SceneEffectStageProgram],
        legacyRecoveryStages: [SceneAuthoredEffectExecutionPlan],
        route executionRoute: ExecutionRoute,
        irisInlineSuffix: SceneIrisInlineSuffixPlan? = nil,
        isolatedCursorRippleOmittedEffectPaths: [String] = [],
        isolatedShineOmittedEffectPaths: [String] = []
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.stagePrograms = stagePrograms
        self.legacyRecoveryStages = legacyRecoveryStages
        self.executionRoute = executionRoute
        self.irisInlineSuffix = irisInlineSuffix
        self.isolatedCursorRippleOmittedEffectPaths =
            isolatedCursorRippleOmittedEffectPaths
        self.isolatedShineOmittedEffectPaths = isolatedShineOmittedEffectPaths
    }

    static func complete(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        stagePrograms: [SceneEffectStageProgram]
    ) -> Self? {
        guard programsConserveCompleteGraph(
            stagePrograms,
            layerID: layerID,
            renderGraph: renderGraph
        ) else {
            return nil
        }
        return Self(
            layerID: layerID,
            renderGraph: renderGraph,
            stagePrograms: stagePrograms,
            legacyRecoveryStages: [],
            route: .completePrograms
        )
    }

    static func legacyRecovery(
        layerID: Int,
        authoredRenderGraph: SceneAuthoredEffectRenderPlan,
        renderGraph: SceneAuthoredEffectRenderPlan,
        stagePrograms: [SceneEffectStageProgram],
        kind: LegacyRecoveryKind,
        irisInlineSuffix: SceneIrisInlineSuffixPlan? = nil
    ) -> Self? {
        switch kind {
        case .terminalIrisInlineSuffix:
            guard stagePrograms.count + 1 == authoredRenderGraph.effects.count,
                  irisInlineSuffix?.effectKey
                    == authoredRenderGraph.effects.last?.key else {
                return nil
            }
        case .xRayPrefix:
            guard irisInlineSuffix == nil,
                  stagePrograms.count == 1,
                  stagePrograms.first?.executionPlan.xRay != nil else {
                return nil
            }
        case .isolatedCursorRipple, .isolatedShine:
            return nil
        }
        guard programsConserveStrictPrefix(
            stagePrograms,
            layerID: layerID,
            authoredRenderGraph: authoredRenderGraph,
            executionRenderGraph: renderGraph
        ) else {
            return nil
        }
        return Self(
            layerID: layerID,
            renderGraph: renderGraph,
            stagePrograms: stagePrograms,
            legacyRecoveryStages: [],
            route: .legacyRecovery(kind),
            irisInlineSuffix: irisInlineSuffix
        )
    }

    static func legacyRecovery(
        layerID: Int,
        authoredRenderGraph: SceneAuthoredEffectRenderPlan,
        renderGraph: SceneAuthoredEffectRenderPlan,
        legacyRecoveryStages: [SceneAuthoredEffectExecutionPlan],
        kind: LegacyRecoveryKind,
        omittedEffectPaths: [String]
    ) -> Self? {
        switch kind {
        case .isolatedCursorRipple, .isolatedShine:
            break
        case .terminalIrisInlineSuffix, .xRayPrefix:
            return nil
        }
        guard manualRecoveryConservesIdentity(
            layerID: layerID,
            authoredRenderGraph: authoredRenderGraph,
            executionRenderGraph: renderGraph,
            stages: legacyRecoveryStages,
            kind: kind,
            omittedEffectPaths: omittedEffectPaths
        ) else {
            return nil
        }
        return Self(
            layerID: layerID,
            renderGraph: renderGraph,
            stagePrograms: [],
            legacyRecoveryStages: legacyRecoveryStages,
            route: .legacyRecovery(kind),
            isolatedCursorRippleOmittedEffectPaths: kind == .isolatedCursorRipple
                ? omittedEffectPaths
                : [],
            isolatedShineOmittedEffectPaths: kind == .isolatedShine
                ? omittedEffectPaths
                : []
        )
    }

    private static func programsConserveCompleteGraph(
        _ programs: [SceneEffectStageProgram],
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan
    ) -> Bool {
        firstProgramConservationViolation(
            programs,
            layerID: layerID,
            renderGraph: renderGraph
        ) == nil
    }

    static func firstProgramConservationViolation(
        _ programs: [SceneEffectStageProgram],
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan
    ) -> (
        ordinal: Int?,
        effectKey: SceneAuthoredEffectRenderPlan.EffectKey?,
        definitionPath: String?
    )? {
        guard renderGraph.layerID == layerID, !programs.isEmpty else {
            return (
                programs.first?.authoredOrdinal,
                programs.first?.effectKey ?? renderGraph.effects.first?.key,
                programs.first?.definitionPath
                    ?? renderGraph.effects.first?.definitionPath
            )
        }
        let sharedCount = min(programs.count, renderGraph.effects.count)
        for ordinal in 0..<sharedCount {
            let program = programs[ordinal]
            let effect = renderGraph.effects[ordinal]
            let expectedInputRole: SceneAuthoredEffectInputRole = ordinal == 0
                ? .layerSource
                : .priorEffectOutput
            guard program.authoredOrdinal == ordinal,
                  program.effectKey == effect.key,
                  program.definitionPath == effect.definitionPath,
                  program.inputRole == expectedInputRole,
                  let expectedGraph = SceneAuthoredEffectChainPlanner.stageGraph(
                      effect: effect,
                      in: renderGraph
                  ),
                  SceneEffectStageProgram.graphsMatch(
                      program.stageGraph,
                      expectedGraph
                  ) else {
                return (ordinal, program.effectKey, program.definitionPath)
            }
        }
        guard programs.count == renderGraph.effects.count else {
            let ordinal = sharedCount
            return (
                ordinal,
                programs.indices.contains(ordinal)
                    ? programs[ordinal].effectKey
                    : renderGraph.effects[ordinal].key,
                programs.indices.contains(ordinal)
                    ? programs[ordinal].definitionPath
                    : renderGraph.effects[ordinal].definitionPath
            )
        }
        return nil
    }

    private static func programsConserveStrictPrefix(
        _ programs: [SceneEffectStageProgram],
        layerID: Int,
        authoredRenderGraph: SceneAuthoredEffectRenderPlan,
        executionRenderGraph: SceneAuthoredEffectRenderPlan
    ) -> Bool {
        guard !programs.isEmpty,
              programs.count < authoredRenderGraph.effects.count,
              programsConserveOrderedPrefix(
                  programs,
                  layerID: layerID,
                  authoredRenderGraph: authoredRenderGraph
              ),
              let finalOutput = programs.last?.stageGraph.finalOutput else {
            return false
        }
        let includedKeys = Set(
            authoredRenderGraph.effects.prefix(programs.count).map(\.key)
        )
        let expectedPrefix = SceneAuthoredEffectRenderPlan(
            layerID: layerID,
            effects: Array(authoredRenderGraph.effects.prefix(programs.count)),
            renderTargets: authoredRenderGraph.renderTargets.filter {
                $0.texture.effect.map(includedKeys.contains) == true
            },
            nodes: authoredRenderGraph.nodes.filter {
                includedKeys.contains($0.effect)
            },
            finalOutput: finalOutput,
            blockers: []
        )
        return SceneEffectStageProgram.graphsMatch(
            executionRenderGraph,
            expectedPrefix
        )
    }

    private static func programsConserveOrderedPrefix(
        _ programs: [SceneEffectStageProgram],
        layerID: Int,
        authoredRenderGraph: SceneAuthoredEffectRenderPlan
    ) -> Bool {
        guard authoredRenderGraph.layerID == layerID,
              !programs.isEmpty,
              programs.count <= authoredRenderGraph.effects.count else {
            return false
        }
        return programs.enumerated().allSatisfy { ordinal, program in
            let effect = authoredRenderGraph.effects[ordinal]
            let inputRole: SceneAuthoredEffectInputRole = ordinal == 0
                ? .layerSource
                : .priorEffectOutput
            guard program.authoredOrdinal == ordinal,
                  program.effectKey == effect.key,
                  program.definitionPath == effect.definitionPath,
                  program.inputRole == inputRole,
                  let expectedGraph = SceneAuthoredEffectChainPlanner.stageGraph(
                      effect: effect,
                      in: authoredRenderGraph
                  ) else {
                return false
            }
            return SceneEffectStageProgram.graphsMatch(
                program.stageGraph,
                expectedGraph
            )
        }
    }

    private static func manualRecoveryConservesIdentity(
        layerID: Int,
        authoredRenderGraph: SceneAuthoredEffectRenderPlan,
        executionRenderGraph: SceneAuthoredEffectRenderPlan,
        stages: [SceneAuthoredEffectExecutionPlan],
        kind: LegacyRecoveryKind,
        omittedEffectPaths: [String]
    ) -> Bool {
        guard authoredRenderGraph.layerID == layerID,
              executionRenderGraph.layerID == layerID,
              executionRenderGraph.effects.count == 1,
              stages.count == 1,
              let stage = stages.first,
              stage.layerID == layerID,
              stage.inputRole == .layerSource,
              !stage.usesLegacyComposeNormalization,
              let executedKey = executionRenderGraph.effects.first?.key else {
            return false
        }
        let authoredEffects = authoredRenderGraph.effects.filter {
            $0.key == executedKey
        }
        guard authoredEffects.count == 1,
              let authoredEffect = authoredEffects.first,
              let authoredStageGraph = SceneAuthoredEffectChainPlanner.stageGraph(
                  effect: authoredEffect,
                  in: authoredRenderGraph
              ),
              let expectedGraph = SceneAuthoredEffectChainPlanner
                .rebaseStageToLayerSource(authoredStageGraph),
              SceneEffectStageProgram.graphsMatch(
                  executionRenderGraph,
                  expectedGraph
              ),
              SceneEffectStageProgram.graphsMatch(
                  stage.renderGraph,
                  expectedGraph
              ),
              stage.materialNodeCount
                == expectedGraph.nodes.filter({ $0.kind == .material }).count,
              stage.logicalRenderTargetCount
                == expectedGraph.renderTargets.count else {
            return false
        }
        let expectedOmittedPaths = authoredRenderGraph.effects.compactMap {
            $0.key == executedKey ? nil : $0.definitionPath
        }
        guard omittedEffectPaths == expectedOmittedPaths else { return false }
        switch kind {
        case .isolatedCursorRipple:
            guard let plan = stage.cursorRipple, stage.shine == nil else {
                return false
            }
            return plan.layerID == layerID
                && plan.effectKey == executedKey
                && SceneEffectStageProgram.graphsMatch(
                    plan.renderGraph,
                    expectedGraph
                )
        case .isolatedShine:
            guard let plan = stage.shine, stage.cursorRipple == nil else {
                return false
            }
            let expectedTargets = Set(expectedGraph.renderTargets.map(\.texture))
            return plan.layerID == layerID
                && plan.effectKey == executedKey
                && SceneEffectStageProgram.graphsMatch(
                    plan.renderGraph,
                    expectedGraph
                )
                && plan.firstHalfTarget != plan.secondHalfTarget
                && expectedTargets.count == 2
                && Set([plan.firstHalfTarget, plan.secondHalfTarget])
                    == expectedTargets
        case .terminalIrisInlineSuffix, .xRayPrefix:
            return false
        }
    }
}
