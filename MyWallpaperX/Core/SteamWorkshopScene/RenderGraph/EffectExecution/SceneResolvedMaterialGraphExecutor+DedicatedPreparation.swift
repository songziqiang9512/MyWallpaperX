import Metal

extension SceneResolvedMaterialGraphExecutor {
    func prepareDedicated(
        program: SceneEffectStageProgram,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command]
    ) -> Failure? {
        if program.executionPlan.supportsUnifiedLogicalTargetStage
            || program.executionPlan.supportsUnifiedHistoryTargetStage {
            return prepareDedicatedGraphStage(
                program: program,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                lease: lease,
                sourcePipeline: sourcePipeline,
                time: time,
                inputs: inputs,
                pair: &pair,
                publications: &publications,
                commands: &commands
            )
        }
        guard program.stageGraph.effects.first?.key == pairStep.effect,
              program.effectKey == pairStep.effect,
              graph.nodes.count == 1,
              pairStep.nodes.count == 1,
              let node = graph.nodes.first,
              let expectedOrdinal = node.materialOrdinal,
              let pairNode = pairStep.nodes.first,
              pairNode.nodeIndex == node.nodeIndex,
              pairNode.kind == .material,
              pairNode.currentMemberBeforeNode == pair.member,
              pairNode.fullFrameWriteMember == pairStep.outputMember,
              transition.transaction.intents.count == 1,
              case let .material(nodeIndex, ordinal, bindings, fboTarget) =
                  transition.transaction.intents[0],
              nodeIndex == node.nodeIndex,
              ordinal == expectedOrdinal,
              bindings.isEmpty,
              case nil = fboTarget,
              let generation = nextPairGeneration(),
              let publication = pairResource(
                  lease: lease,
                  identity: pairStep.outputIdentity,
                  member: pairStep.outputMember,
                  generation: generation,
                  representation: .premultipliedAlpha
              ) else { return .dedicatedLeafRejected(reason: "graph-contract") }
        let stagePreparation = SceneEffectStageRenderer.prepareStage(
                  program.executionPlan,
                  sourceTexture: pair.resource.publication.texture,
                  targets: lease.table,
                  inputs: inputs,
                  sourcePipeline: sourcePipeline,
                  time: time
              )
        guard case let .ready(prepared) = stagePreparation else {
            guard case let .rejected(reason) = stagePreparation else {
                return .dedicatedLeafRejected(reason: "preparation-invariant")
            }
            return .dedicatedLeafRejected(reason: reason)
        }
        commands.append(.dedicated(prepared))
        publications[pairStep.outputIdentity] = publication
        pair = .init(
            member: pairStep.outputMember,
            resource: publication,
            representation: .premultipliedAlpha
        )
        return nil
    }

    private func prepareDedicatedGraphStage(
        program: SceneEffectStageProgram,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command]
    ) -> Failure? {
        let isHistoryStage = program.executionPlan.supportsUnifiedHistoryTargetStage
        let historyIdentities = Set(lease.table.plan.logicalTargets.compactMap {
            $0.lifetime.requiresHistorySeed ? $0.identity : nil
        })
        let initializationIntents = transition.transaction.intents.compactMap {
            intent -> (Graph.TextureIdentity, State.VersionedResource,
                State.InitializationReason)? in
            guard case let .initialize(identity, resource, reason) = intent else {
                return nil
            }
            return (identity, resource, reason)
        }
        let graphIntents = transition.transaction.intents.filter {
            guard case .initialize = $0 else { return true }
            return false
        }
        let expectedInitializationIdentities = Set(
            transition.transaction.mappingBefore.compactMap { identity, resource in
                historyIdentities.contains(identity) && resource.contentGeneration == 0
                    ? identity : nil
            }
        )
        guard program.effectKey == pairStep.effect,
              program.stageGraph.effects.first?.key == pairStep.effect,
              program.executionPlan.supportsUnifiedLogicalTargetStage
                || isHistoryStage,
              program.executionPlan.logicalRenderTargetCount > 0,
              graph.nodes.count > 1,
              graph.nodes.count == pairStep.nodes.count,
              graph.renderTargets.count
                == program.executionPlan.logicalRenderTargetCount,
              graph.renderTargets.allSatisfy({ !$0.declaredUnique }),
              isHistoryStage
                ? (!historyIdentities.isEmpty
                    && transition.nextState.historyClosureIdentities
                        == historyIdentities)
                : (historyIdentities.isEmpty
                    && transition.nextState.historyClosureIdentities.isEmpty),
              Set(initializationIntents.map(\.0))
                == expectedInitializationIdentities,
              initializationIntents.count == expectedInitializationIdentities.count,
              graphIntents.count == graph.nodes.count,
              pairStep.inputMember == pair.member,
              lease.table.inputTexture === pair.resource.publication.texture,
              lease.table.outputTexture === pairTexture(
                  lease: lease,
                  member: pairStep.outputMember
              ) else {
            return .dedicatedLeafRejected(reason: "graph-stage-contract")
        }
        for (index, node) in graph.nodes.enumerated() {
            let pairNode = pairStep.nodes[index]
            let intent = graphIntents[index]
            guard pairNode.nodeIndex == node.nodeIndex,
                  pairNode.kind == pairNodeKind(node.kind),
                  dedicatedIntent(intent, matches: node) else {
                return .dedicatedLeafRejected(reason: "graph-stage-topology")
            }
        }
        guard pairStep.nodes.last?.fullFrameWriteMember == pairStep.outputMember else {
            return .dedicatedLeafRejected(reason: "graph-stage-output")
        }

        for (identity, resource, reason) in initializationIntents {
            guard isHistoryStage,
                  historyIdentities.contains(identity),
                  reason == .transparentHistorySeed,
                  let target = lease.texturesByToken[resource.token],
                  let initialization = initialization(reason),
                  let prepared = resourceEncoder?.prepareInitialization(
                      target: target,
                      clear: initialization.clear
                  ), let publication = framebufferResource(
                      lease: lease,
                      identity: identity,
                      resource: resource,
                      representation: initialization.representation
                  ) else {
                return .resourceCommandRejected
            }
            commands.append(.resource(prepared))
            publications[identity] = publication
        }

        let stagePreparation = SceneEffectStageRenderer.prepareStage(
            program.executionPlan,
            sourceTexture: pair.resource.publication.texture,
            targets: lease.table,
            inputs: inputs,
            sourcePipeline: sourcePipeline,
            time: time
        )
        guard case let .ready(prepared) = stagePreparation else {
            guard case let .rejected(reason) = stagePreparation else {
                return .dedicatedLeafRejected(reason: "preparation-invariant")
            }
            return .dedicatedLeafRejected(reason: reason)
        }

        for (identity, resource) in transition.transaction.mappingAfter
            where resource.contentGeneration > 0 {
            guard identity.kind == .framebuffer,
                  let publication = framebufferResource(
                      lease: lease,
                      identity: identity,
                      resource: resource,
                      representation: .premultipliedAlpha
                  ) else {
                return .graphPublicationRejected
            }
            publications[identity] = publication
        }
        guard let generation = nextPairGeneration(),
              let publication = pairResource(
                  lease: lease,
                  identity: pairStep.outputIdentity,
                  member: pairStep.outputMember,
                  generation: generation,
                  representation: .premultipliedAlpha
              ) else { return .graphPublicationRejected }
        commands.append(.dedicated(prepared))
        publications[pairStep.outputIdentity] = publication
        pair = .init(
            member: pairStep.outputMember,
            resource: publication,
            representation: .premultipliedAlpha
        )
        return nil
    }

    private func pairNodeKind(_ kind: Graph.NodeKind) -> Pair.NodeKind? {
        switch kind {
        case .material: .material
        case .copy: .copy
        case .swap: .swap
        case .unknownCommand: nil
        }
    }

    private func dedicatedIntent(
        _ intent: State.Intent,
        matches node: Graph.Node
    ) -> Bool {
        switch (intent, node.kind) {
        case let (.material(index, ordinal, _, _), .material):
            index == node.nodeIndex && ordinal == node.materialOrdinal
        case let (.copy(index, _, source, _, target, _), .copy):
            index == node.nodeIndex && source == node.commandSource
                && target == node.commandTarget
        case let (.swap(index, _, source, _, target, _), .swap):
            index == node.nodeIndex && source == node.commandSource
                && target == node.commandTarget
        default:
            false
        }
    }
}
