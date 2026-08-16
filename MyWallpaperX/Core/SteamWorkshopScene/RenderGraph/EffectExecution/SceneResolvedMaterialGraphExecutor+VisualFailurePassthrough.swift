import Metal

extension SceneResolvedMaterialGraphExecutor {
    /// Preserves the previous current for one launch-time visual contract or
    /// pre-encode frame preparation failure. This is an exact pair-member copy,
    /// not a fabricated shader result. Resource, target, dependency and runtime
    /// encode failures never reach this path.
    func prepareVisualFailurePassthrough(
        reasonCode: String,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        programKeys: inout [String],
        effectLocalFailureReasonCode: inout String?,
        rejection: Failure = .graphStructureRejected
    ) -> Failure? {
        guard [
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
            "material-variant-envelope-uniform-schema",
            "material-dynamic-uniform-contributor-policy",
            "material-dynamic-uniform-contributor-producer-unavailable",
            "material-dynamic-uniform-script-attachment-unproven",
            "material-dynamic-uniform-producer-unavailable",
            "material-pass-preparation-library-compilation",
            "material-pass-preparation-vertex-function",
            "material-pass-preparation-fragment-function",
            "material-pass-preparation-pipeline-compilation",
            "material-finalizer-dynamic-uniform-binding",
            "material-finalizer-static-uniform-binding",
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
            return rejection
        }
        commands.append(.resource(copy))
        publications[pairStep.outputIdentity] = publication
        pair = .init(
            member: pairStep.outputMember,
            resource: publication,
            representation: pair.representation
        )
        programKeys.append("visual-failure-passthrough:\(reasonCode)")
        effectLocalFailureReasonCode = reasonCode
        if reasonCode.hasPrefix("material-pass-preparation-")
            || reasonCode.hasPrefix("material-finalizer-") {
            recordEffectLocalFramePreparationFallback(
                reasonCode: reasonCode,
                effect: effect.key
            )
        }
        return nil
    }

    private func recordEffectLocalFramePreparationFallback(
        reasonCode: String,
        effect: Graph.EffectKey
    ) {
        let identity = "\(effect.layerID):\(effect.effectIndex):"
            + "\(effect.descriptorID):\(reasonCode)"
        effectLocalFallbackLock.lock()
        let count = effectLocalFallbackCounts[identity, default: 0] + 1
        effectLocalFallbackCounts[identity] = count
        effectLocalFallbackLock.unlock()
        guard count & (count - 1) == 0 else { return }
        NSLog(
            "MWX resolved material renderer fallback phase=frame-preparation"
                + " outcome=effect-local-passthrough reason=%@"
                + " layer=%d effect=%d descriptor=%@ count=%d",
            reasonCode,
            effect.layerID,
            effect.effectIndex,
            effect.descriptorID,
            count
        )
    }
}
