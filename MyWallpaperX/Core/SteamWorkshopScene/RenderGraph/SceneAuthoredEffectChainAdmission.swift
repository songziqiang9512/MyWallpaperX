import Foundation

nonisolated enum SceneAuthoredEffectChainAdmission {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Coverage {
        case complete
        case terminalIrisInlineSuffix(effect: EffectKey)
        case xRayPrefix(omitted: [EffectKey])
        case isolatedCursorRipple(executed: EffectKey, omitted: [EffectKey])
        case isolatedShine(executed: EffectKey, omitted: [EffectKey])

        var code: String {
            switch self {
            case .complete: "complete"
            case .terminalIrisInlineSuffix: "terminal-iris-inline-suffix"
            case .xRayPrefix: "xray-prefix"
            case .isolatedCursorRipple: "isolated-cursor-ripple"
            case .isolatedShine: "isolated-shine"
            }
        }
    }

    case accepted(
        chain: SceneAuthoredEffectExecutionChain,
        coverage: Coverage
    )
    case rejected(SceneAuthoredEffectChainRejection)

    var chain: SceneAuthoredEffectExecutionChain? {
        guard case .accepted(let chain, _) = self else { return nil }
        return chain
    }

    var coverage: Coverage? {
        guard case .accepted(_, let coverage) = self else { return nil }
        return coverage
    }

    var rejection: SceneAuthoredEffectChainRejection? {
        guard case .rejected(let rejection) = self else { return nil }
        return rejection
    }
}

nonisolated struct SceneAuthoredEffectChainRejection {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum Code: String, CaseIterable {
        case graphBlocked = "graph-blocked"
        case emptyEffectChain = "empty-effect-chain"
        case layerDescriptorMissing = "layer-descriptor-missing"
        case layerDescriptorAmbiguous = "layer-descriptor-ambiguous"
        case effectLayerMismatch = "effect-layer-mismatch"
        case invalidEffectIndex = "invalid-effect-index"
        case emptyEffectDescriptorID = "empty-effect-descriptor-id"
        case duplicateEffectKey = "duplicate-effect-key"
        case nonMonotonicEffectOrder = "non-monotonic-effect-order"
        case discontinuousEffectInput = "discontinuous-effect-input"
        case invalidEffectOutput = "invalid-effect-output"
        case emptyEffectNodeList = "empty-effect-node-list"
        case duplicateEffectNodeReference = "duplicate-effect-node-reference"
        case finalOutputMismatch = "final-output-mismatch"
        case nodeCoverageMismatch = "node-coverage-mismatch"
        case orphanNodeEffect = "orphan-node-effect"
        case orphanRenderTargetEffect = "orphan-render-target-effect"
        case stageNodeMissing = "stage-node-missing"
        case stageNodeAmbiguous = "stage-node-ambiguous"
        case stageNodeEffectMismatch = "stage-node-effect-mismatch"
        case unsupportedStage = "unsupported-stage"
        case recoveryInvariantViolation = "recovery-invariant-violation"
        case duplicateGraph = "duplicate-graph"
    }

    let code: Code
    let layerID: Int
    let effectOrdinal: Int?
    let effectKey: Graph.EffectKey?
    let definitionPath: String?
    let nodeIndex: Int?
    let observedCount: Int?
    let blockerReasons: [Graph.BlockerReason]

    init(
        code: Code,
        layerID: Int,
        effectOrdinal: Int? = nil,
        effectKey: Graph.EffectKey? = nil,
        definitionPath: String? = nil,
        nodeIndex: Int? = nil,
        observedCount: Int? = nil,
        blockerReasons: [Graph.BlockerReason] = []
    ) {
        self.code = code
        self.layerID = layerID
        self.effectOrdinal = effectOrdinal
        self.effectKey = effectKey
        self.definitionPath = definitionPath
        self.nodeIndex = nodeIndex
        self.observedCount = observedCount
        self.blockerReasons = blockerReasons
    }
}

extension SceneAuthoredEffectChainPlanner {
    nonisolated static func admit(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectChainAdmission {
        if !graph.blockers.isEmpty {
            return reject(.init(
                code: .graphBlocked,
                layerID: graph.layerID,
                blockerReasons: graph.blockers.map(\.reason)
            ))
        }
        guard !graph.effects.isEmpty else {
            return reject(.init(code: .emptyEffectChain, layerID: graph.layerID))
        }
        let layerCount = descriptor.layers.filter { $0.id == graph.layerID }.count
        guard layerCount == 1 else {
            return reject(.init(
                code: layerCount == 0
                    ? .layerDescriptorMissing
                    : .layerDescriptorAmbiguous,
                layerID: graph.layerID,
                observedCount: layerCount
            ))
        }
        if let rejection = outerChainRejection(graph) {
            return reject(rejection)
        }

        var stages: [SceneAuthoredEffectExecutionPlan] = []
        stages.reserveCapacity(graph.effects.count)
        for (ordinal, effect) in graph.effects.enumerated() {
            let stageGraph: Graph
            switch stageGraphAdmission(effect: effect, in: graph) {
            case .accepted(let graph):
                stageGraph = graph
            case .rejected(let rejection):
                return reject(rejection)
            }
            let inputRole: SceneAuthoredEffectInputRole = ordinal == 0
                ? .layerSource
                : .priorEffectOutput
            if let stage = resolveStage(
                stageGraph: stageGraph,
                inputRole: inputRole,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            ) {
                stages.append(stage)
                continue
            }
            if let recovered = recoveredAdmission(
                plannedStages: stages,
                unsupportedOrdinal: ordinal,
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            ) {
                return recovered
            }
            return reject(.init(
                code: .unsupportedStage,
                layerID: graph.layerID,
                effectOrdinal: ordinal,
                effectKey: effect.key,
                definitionPath: effect.definitionPath
            ))
        }

        return .accepted(
            chain: SceneAuthoredEffectExecutionChain(
                layerID: graph.layerID,
                renderGraph: graph,
                stages: stages
            ),
            coverage: .complete
        )
    }

    private nonisolated static func recoveredAdmission(
        plannedStages: [SceneAuthoredEffectExecutionPlan],
        unsupportedOrdinal: Int,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectChainAdmission? {
        if let chain = irisInlineSuffix(
            plannedStages: plannedStages,
            unsupportedOrdinal: unsupportedOrdinal,
            graph: graph,
            descriptor: descriptor,
            shaderContracts: shaderContracts
        ), let effect = chain.irisInlineSuffix?.effectKey {
            return .accepted(
                chain: chain,
                coverage: .terminalIrisInlineSuffix(effect: effect)
            )
        }
        if let chain = isolatedCursorRippleChain(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: shaderContracts
        ) {
            return isolatedAdmission(chain: chain, graph: graph, cursorRipple: true)
        }
        if let chain = isolatedShineChain(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: shaderContracts
        ) {
            return isolatedAdmission(chain: chain, graph: graph, cursorRipple: false)
        }
        if let chain = xRayPrefix(
            plannedStages: plannedStages,
            unsupportedOrdinal: unsupportedOrdinal,
            graph: graph,
            descriptor: descriptor
        ) {
            let accepted = Set(chain.stages.compactMap {
                $0.renderGraph.effects.first?.key
            })
            let omitted = graph.effects.map(\.key).filter { !accepted.contains($0) }
            return .accepted(chain: chain, coverage: .xRayPrefix(omitted: omitted))
        }
        return nil
    }

    private nonisolated static func isolatedAdmission(
        chain: SceneAuthoredEffectExecutionChain,
        graph: Graph,
        cursorRipple: Bool
    ) -> SceneAuthoredEffectChainAdmission {
        let executedKeys = chain.stages.compactMap {
            $0.renderGraph.effects.first?.key
        }
        guard executedKeys.count == 1, let executed = executedKeys.first else {
            return reject(.init(
                code: .recoveryInvariantViolation,
                layerID: graph.layerID,
                observedCount: executedKeys.count
            ))
        }
        let omitted = graph.effects.map(\.key).filter { $0 != executed }
        let coverage: SceneAuthoredEffectChainAdmission.Coverage = cursorRipple
            ? .isolatedCursorRipple(executed: executed, omitted: omitted)
            : .isolatedShine(executed: executed, omitted: omitted)
        return .accepted(chain: chain, coverage: coverage)
    }

    private nonisolated static func outerChainRejection(
        _ graph: Graph
    ) -> SceneAuthoredEffectChainRejection? {
        var expectedInput = SceneAuthoredEffectInputValidator.layerSource(
            layerID: graph.layerID
        )
        var seenEffects = Set<Graph.EffectKey>()
        var seenNodeIndices = Set<Int>()
        var lastEffectIndex: Int?

        for (ordinal, effect) in graph.effects.enumerated() {
            let context = { (code: SceneAuthoredEffectChainRejection.Code) in
                SceneAuthoredEffectChainRejection(
                    code: code,
                    layerID: graph.layerID,
                    effectOrdinal: ordinal,
                    effectKey: effect.key,
                    definitionPath: effect.definitionPath
                )
            }
            guard effect.key.layerID == graph.layerID else {
                return context(.effectLayerMismatch)
            }
            guard effect.key.effectIndex >= 0 else {
                return context(.invalidEffectIndex)
            }
            guard !effect.key.descriptorID.isEmpty else {
                return context(.emptyEffectDescriptorID)
            }
            guard seenEffects.insert(effect.key).inserted else {
                return context(.duplicateEffectKey)
            }
            guard lastEffectIndex.map({ effect.key.effectIndex > $0 }) ?? true else {
                return context(.nonMonotonicEffectOrder)
            }
            guard effect.input == expectedInput else {
                return context(.discontinuousEffectInput)
            }
            guard validOutput(effect.output, effect: effect.key, layerID: graph.layerID) else {
                return context(.invalidEffectOutput)
            }
            guard !effect.nodeIndices.isEmpty else {
                return context(.emptyEffectNodeList)
            }
            for nodeIndex in effect.nodeIndices {
                guard seenNodeIndices.insert(nodeIndex).inserted else {
                    return .init(
                        code: .duplicateEffectNodeReference,
                        layerID: graph.layerID,
                        effectOrdinal: ordinal,
                        effectKey: effect.key,
                        definitionPath: effect.definitionPath,
                        nodeIndex: nodeIndex
                    )
                }
            }
            expectedInput = effect.output
            lastEffectIndex = effect.key.effectIndex
        }

        guard graph.finalOutput == expectedInput else {
            return .init(code: .finalOutputMismatch, layerID: graph.layerID)
        }
        guard seenNodeIndices == Set(graph.nodes.map(\.nodeIndex)) else {
            return .init(code: .nodeCoverageMismatch, layerID: graph.layerID)
        }
        guard graph.nodes.allSatisfy({ seenEffects.contains($0.effect) }) else {
            return .init(code: .orphanNodeEffect, layerID: graph.layerID)
        }
        guard graph.renderTargets.allSatisfy({
            $0.texture.effect.map(seenEffects.contains) == true
        }) else {
            return .init(code: .orphanRenderTargetEffect, layerID: graph.layerID)
        }
        return nil
    }

    private nonisolated static func validOutput(
        _ output: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        output.kind == .effectOutput
            && output.layerID == layerID
            && output.effect == effect
            && output.name == nil
    }

    private nonisolated static func reject(
        _ rejection: SceneAuthoredEffectChainRejection
    ) -> SceneAuthoredEffectChainAdmission {
#if DEBUG
        print(
            "MWX authored effect chain rejected layer=\(rejection.layerID) "
                + "reason=\(rejection.code.rawValue)"
        )
#endif
        return .rejected(rejection)
    }
}
