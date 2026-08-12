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
        originalSourceTexture: MTLTexture?,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command]
    ) -> Failure? {
        let sampleTexture = program.executionPlan.inputRole == .layerSource
            ? originalSourceTexture ?? pair.resource.publication.texture
            : pair.resource.publication.texture
        let sourceSampleExtent = SIMD2<Float>(
            Float(sampleTexture.width), Float(sampleTexture.height)
        )
        if program.executionPlan.supportsUnifiedFullFrameComposeStage {
            return prepareDedicatedFullFrameComposeStage(
                program: program,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                lease: lease,
                sourcePipeline: sourcePipeline,
                time: time,
                sourceSampleExtent: sourceSampleExtent,
                inputs: inputs,
                pair: &pair,
                publications: &publications,
                commands: &commands
            )
        }
        if program.executionPlan.supportsUnifiedLogicalTargetStage {
            return prepareDedicatedGraphStage(
                program: program,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                lease: lease,
                sourcePipeline: sourcePipeline,
                time: time,
                sourceSampleExtent: sourceSampleExtent,
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
                  time: time,
                  sourceSampleExtent: sourceSampleExtent
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

    private func prepareDedicatedFullFrameComposeStage(
        program: SceneEffectStageProgram,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float,
        sourceSampleExtent: SIMD2<Float>,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command]
    ) -> Failure? {
        guard program.effectKey == pairStep.effect,
              program.stageGraph.effects.first?.key == pairStep.effect,
              program.executionPlan.logicalRenderTargetCount == 0,
              graph.nodes.count == 2,
              graph.renderTargets.isEmpty,
              pairStep.nodes.count == 2,
              pairStep.composeTransitionCount == 1,
              pairStep.fullFrameOutputWriteCount == 2,
              pairStep.inputMember == pair.member,
              pairStep.outputMember == pairStep.inputMember,
              transition.nextState.historyClosureIdentities.isEmpty,
              transition.transaction.intents.count == 2,
              lease.table.plan.logicalTargets.isEmpty,
              lease.table.inputOutputAliased,
              lease.table.inputTexture === pair.resource.publication.texture,
              lease.table.inputTexture === lease.table.outputTexture,
              lease.table.fullFramePair.first !== lease.table.fullFramePair.second,
              lease.table.outputTexture === pairTexture(
                  lease: lease,
                  member: pairStep.outputMember
              ) else {
            return .dedicatedLeafRejected(reason: "full-frame-compose-contract")
        }
        let firstNode = graph.nodes[0]
        let secondNode = graph.nodes[1]
        let firstPairNode = pairStep.nodes[0]
        let secondPairNode = pairStep.nodes[1]
        guard firstNode.compose == .bool(true),
              secondNode.compose == nil,
              firstNode.target == pairStep.outputIdentity,
              secondNode.target == pairStep.outputIdentity,
              firstNode.bindings.isEmpty,
              secondNode.bindings.isEmpty,
              firstPairNode.currentMemberBeforeNode == pair.member,
              firstPairNode.fullFrameWriteMember == pair.member.opposite,
              firstPairNode.rotatesAfterNode,
              firstPairNode.currentMemberAfterNode == pair.member.opposite,
              secondPairNode.currentMemberBeforeNode == pair.member.opposite,
              secondPairNode.fullFrameWriteMember == pair.member,
              !secondPairNode.rotatesAfterNode,
              secondPairNode.currentMemberAfterNode == pair.member.opposite else {
            return .dedicatedLeafRejected(reason: "full-frame-compose-topology")
        }
        for (node, intent) in zip(graph.nodes, transition.transaction.intents) {
            guard case let .material(index, ordinal, bindings, target) = intent,
                  index == node.nodeIndex,
                  ordinal == node.materialOrdinal,
                  bindings.isEmpty,
                  target == nil else {
                return .dedicatedLeafRejected(reason: "full-frame-compose-intent")
            }
        }

        let stagePreparation = SceneEffectStageRenderer.prepareStage(
            program.executionPlan,
            sourceTexture: pair.resource.publication.texture,
            targets: lease.table,
            inputs: inputs,
            sourcePipeline: sourcePipeline,
            time: time,
            sourceSampleExtent: sourceSampleExtent
        )
        guard case let .ready(prepared) = stagePreparation else {
            guard case let .rejected(reason) = stagePreparation else {
                return .dedicatedLeafRejected(reason: "preparation-invariant")
            }
            return .dedicatedLeafRejected(reason: reason)
        }
        guard let composeGeneration = nextPairGeneration(),
              let composePublication = pairResource(
                  lease: lease,
                  identity: pairStep.inputIdentity,
                  member: pair.member.opposite,
                  generation: composeGeneration,
                  representation: .premultipliedAlpha
              ), let outputGeneration = nextPairGeneration(),
              let outputPublication = pairResource(
                  lease: lease,
                  identity: pairStep.outputIdentity,
                  member: pairStep.outputMember,
                  generation: outputGeneration,
                  representation: .premultipliedAlpha
              ) else { return .graphPublicationRejected }
        commands.append(.dedicated(prepared))
        publications[pairStep.inputIdentity] = composePublication
        publications[pairStep.outputIdentity] = outputPublication
        pair = .init(
            member: pairStep.outputMember,
            resource: outputPublication,
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
        sourceSampleExtent: SIMD2<Float>,
        inputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command]
    ) -> Failure? {
        guard program.effectKey == pairStep.effect,
              program.stageGraph.effects.first?.key == pairStep.effect,
              program.executionPlan.logicalRenderTargetCount > 0,
              graph.nodes.count > 1,
              graph.nodes.count == pairStep.nodes.count,
              graph.renderTargets.count
                == program.executionPlan.logicalRenderTargetCount,
              graph.renderTargets.allSatisfy({ !$0.declaredUnique }),
              transition.nextState.historyClosureIdentities.isEmpty,
              transition.transaction.intents.count == graph.nodes.count,
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
            let intent = transition.transaction.intents[index]
            guard pairNode.nodeIndex == node.nodeIndex,
                  pairNode.kind == pairNodeKind(node.kind),
                  dedicatedIntent(intent, matches: node) else {
                return .dedicatedLeafRejected(reason: "graph-stage-topology")
            }
        }
        guard pairStep.nodes.last?.fullFrameWriteMember == pairStep.outputMember else {
            return .dedicatedLeafRejected(reason: "graph-stage-output")
        }

        let stagePreparation = SceneEffectStageRenderer.prepareStage(
            program.executionPlan,
            sourceTexture: pair.resource.publication.texture,
            targets: lease.table,
            inputs: inputs,
            sourcePipeline: sourcePipeline,
            time: time,
            sourceSampleExtent: sourceSampleExtent
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
