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
        let stagePreparation = SceneAuthoredEffectChainRenderer.prepareStage(
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
}
