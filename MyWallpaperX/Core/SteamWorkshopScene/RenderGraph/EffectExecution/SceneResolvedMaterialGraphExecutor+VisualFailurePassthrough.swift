import Metal

extension SceneResolvedMaterialGraphExecutor {
    /// Preserves the previous current for one launch-time visual shader
    /// preparation/frontend failure. This is an exact pair-member copy, not a
    /// fabricated shader result. Resource, target, dependency and runtime
    /// failures never reach this path.
    func prepareVisualFailurePassthrough(
        reasonCode: String,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        programKeys: inout [String]
    ) -> Failure? {
        guard [
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
        ].contains(reasonCode),
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              graph.blockers.isEmpty,
              let effect = graph.effects.first,
              let node = graph.nodes.first,
              effect.key == pairStep.effect,
              node.effect == effect.key,
              node.kind == .material,
              node.target == pairStep.outputIdentity,
              node.bindings.allSatisfy({
                  $0.texture == pairStep.inputIdentity
              }),
              pairStep.nodes.count == 1,
              let pairNode = pairStep.nodes.first,
              pairNode.nodeIndex == node.nodeIndex,
              pairNode.kind == .material,
              pairNode.currentMemberBeforeNode == pair.member,
              pairNode.fullFrameWriteMember == pairStep.outputMember,
              !pairNode.rotatesAfterNode,
              pairNode.currentMemberAfterNode == pair.member,
              pairStep.inputMember == pair.member,
              pairStep.inputMember != pairStep.outputMember,
              pairStep.composeTransitionCount == 0,
              transition.nextState.historyClosureIdentities.isEmpty,
              transition.transaction.intents.count == 1,
              case let .material(
                  nodeIndex, ordinal, bindings, target
              ) = transition.transaction.intents[0],
              let materialOrdinal = node.materialOrdinal,
              nodeIndex == node.nodeIndex,
              ordinal == materialOrdinal,
              bindings.isEmpty,
              target == nil,
              let copy = resourceEncoder?.prepareCopy(
                  source: pair.resource.publication.texture,
                  target: pairTexture(
                      lease: lease,
                      member: pairStep.outputMember
                  )
              ),
              let generation = nextPairGeneration(),
              let publication = pairResource(
                  lease: lease,
                  identity: pairStep.outputIdentity,
                  member: pairStep.outputMember,
                  generation: generation,
                  representation: pair.representation
              ) else {
            return .graphStructureRejected
        }
        commands.append(.resource(copy))
        publications[pairStep.outputIdentity] = publication
        pair = .init(
            member: pairStep.outputMember,
            resource: publication,
            representation: pair.representation
        )
        programKeys.append("visual-failure-passthrough:\(reasonCode)")
        return nil
    }
}
