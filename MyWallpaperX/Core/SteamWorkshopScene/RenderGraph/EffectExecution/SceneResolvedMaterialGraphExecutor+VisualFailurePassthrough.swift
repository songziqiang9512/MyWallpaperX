import Metal

extension SceneResolvedMaterialGraphExecutor {
    struct VisualFailureSnapshot {
        let pair: PairAtom
        let publications: [Graph.TextureIdentity: SceneFrameTextureResource]
        let commandCount: Int
        let programKeyCount: Int
    }

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
        snapshot: VisualFailureSnapshot,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        programKeys: inout [String],
        effectLocalFailureReasonCode: inout String?,
        boundedDetail: String? = nil,
        rejection: Failure = .graphStructureRejected
    ) -> Failure? {
        guard [
            "material-generic-owner-revoked",
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
            "material-variant-envelope-sampler-schema",
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
            "material-finalizer-host-uniform-declaration-conflict",
            "material-finalizer-uniform-declaration-conflict",
            "material-finalizer-optional-texture-unavailable",
            "material-finalizer-optional-texture-purpose-mismatch",
            "material-finalizer-optional-texture-content-mismatch",
            "material-finalizer-optional-texture-sampling-unresolved",
        ].contains(reasonCode),
              visualFailureTopologyIsSupported(
                  transition: transition,
                  graph: graph,
                  pairStep: pairStep,
                  snapshot: snapshot
              ),
              commands.count >= snapshot.commandCount,
              programKeys.count >= snapshot.programKeyCount else {
            return rejection
        }
        commands.removeSubrange(snapshot.commandCount ..< commands.count)
        programKeys.removeSubrange(snapshot.programKeyCount ..< programKeys.count)
        publications = snapshot.publications
        pair = snapshot.pair

        let publication: SceneFrameTextureResource
        if pairStep.inputMember == pairStep.outputMember {
            guard let value = pair.resource.rewrappedForGraphIdentity(
                pairStep.outputIdentity
            ) else { return rejection }
            publication = value
        } else {
            guard let copy = resourceEncoder?.prepareCopy(
                      source: pair.resource.publication.texture,
                      target: pairTexture(
                          lease: lease,
                          member: pairStep.outputMember
                      )
                  ),
                  let generation = nextPairGeneration(),
                  let value = pairResource(
                      lease: lease,
                      identity: pairStep.outputIdentity,
                      member: pairStep.outputMember,
                      generation: generation,
                      representation: pair.representation
                  ) else { return rejection }
            commands.append(.resource(copy))
            publication = value
        }
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
                effect: pairStep.effect,
                boundedDetail: boundedDetail
            )
        }
        return nil
    }

    private func visualFailureTopologyIsSupported(
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        snapshot: VisualFailureSnapshot
    ) -> Bool {
        guard graph.effects.count == 1,
              !graph.nodes.isEmpty,
              graph.blockers.isEmpty,
              let effect = graph.effects.first,
              effect.key == pairStep.effect,
              pairStep.inputMember == snapshot.pair.member,
              pairStep.nodes.count == graph.nodes.count,
              transition.nextState.historyClosureIdentities.isEmpty else {
            return false
        }
        if !graph.renderTargets.isEmpty {
            return visualFailureFramebufferTopologyIsSupported(
                transition: transition,
                graph: graph,
                effect: effect,
                pairStep: pairStep
            )
        }
        guard pairStep.fullFrameOutputWriteCount == graph.nodes.count,
              transition.transaction.intents.count == graph.nodes.count else {
            return false
        }
        let composeFlags: [Bool] = graph.nodes.compactMap { node in
            switch node.compose {
            case nil, .some(.bool(false)): false
            case .some(.bool(true)): true
            default: nil
            }
        }
        guard composeFlags.count == graph.nodes.count,
              composeFlags.last == false,
              composeFlags.dropLast().allSatisfy({ $0 }),
              pairStep.composeTransitionCount == max(0, graph.nodes.count - 1)
        else { return false }

        var current = snapshot.pair.member
        for ((node, pairNode), intent) in zip(
            zip(graph.nodes, pairStep.nodes),
            transition.transaction.intents
        ) {
            guard node.effect == effect.key,
                  node.kind == .material,
                  node.target == pairStep.outputIdentity,
                  node.commandSource == nil,
                  node.commandTarget == nil,
                  node.bindings.allSatisfy({
                      $0.texture == pairStep.inputIdentity
                  }),
                  let ordinal = node.materialOrdinal,
                  pairNode.nodeIndex == node.nodeIndex,
                  pairNode.kind == .material,
                  pairNode.currentMemberBeforeNode == current,
                  pairNode.fullFrameWriteMember == current.opposite,
                  pairNode.rotatesAfterNode == (node.compose == .bool(true)),
                  case let .material(
                      nodeIndex, materialOrdinal, bindings, target
                  ) = intent,
                  nodeIndex == node.nodeIndex,
                  materialOrdinal == ordinal,
                  bindings.isEmpty,
                  target == nil else { return false }
            current = pairNode.currentMemberAfterNode
        }
        return pairStep.outputMember == current.opposite
    }

    private func visualFailureFramebufferTopologyIsSupported(
        transition: State.Transition,
        graph: Graph,
        effect: Graph.Effect,
        pairStep: Pair.EffectStep
    ) -> Bool {
        guard graph.renderTargets.count == 1,
              let target = graph.renderTargets.first,
              !target.declaredUnique,
              target.clear == nil,
              target.conditions == nil,
              graph.nodes.count == 2,
              pairStep.nodes.count == 2,
              pairStep.fullFrameOutputWriteCount == 1,
              pairStep.composeTransitionCount == 0,
              pairStep.inputMember != pairStep.outputMember,
              transition.transaction.intents.count == 2,
              Set(transition.transaction.mappingBefore.keys) == [target.texture],
              Set(transition.transaction.mappingAfter.keys) == [target.texture]
        else { return false }
        let first = graph.nodes[0]
        let terminal = graph.nodes[1]
        let firstStep = pairStep.nodes[0]
        let terminalStep = pairStep.nodes[1]
        guard first.effect == effect.key,
              first.kind == .material,
              first.materialOrdinal == 0,
              first.target == target.texture,
              first.commandSource == nil,
              first.commandTarget == nil,
              first.compose == nil || first.compose == .bool(false),
              first.conditions == nil,
              first.bindings.contains(where: { $0.texture == effect.input }),
              first.bindings.allSatisfy({
                  $0.texture == effect.input && $0.conditions == nil
              }),
              terminal.effect == effect.key,
              terminal.kind == .material,
              terminal.materialOrdinal == 1,
              terminal.target == effect.output,
              terminal.commandSource == nil,
              terminal.commandTarget == nil,
              terminal.compose == nil || terminal.compose == .bool(false),
              terminal.conditions == nil,
              terminal.bindings.contains(where: { $0.texture == target.texture }),
              terminal.bindings.allSatisfy({
                  ($0.texture == target.texture || $0.texture == effect.input)
                    && $0.conditions == nil
              }),
              firstStep.nodeIndex == first.nodeIndex,
              firstStep.kind == .material,
              firstStep.currentMemberBeforeNode == pairStep.inputMember,
              firstStep.currentMemberAfterNode == pairStep.inputMember,
              firstStep.fullFrameWriteMember == nil,
              !firstStep.rotatesAfterNode,
              terminalStep.nodeIndex == terminal.nodeIndex,
              terminalStep.kind == .material,
              terminalStep.currentMemberBeforeNode == pairStep.inputMember,
              terminalStep.currentMemberAfterNode == pairStep.inputMember,
              terminalStep.fullFrameWriteMember == pairStep.outputMember,
              !terminalStep.rotatesAfterNode else { return false }
        guard case let .material(
                  firstNode, firstOrdinal, firstBindings, firstTarget
              ) = transition.transaction.intents[0],
              firstNode == first.nodeIndex,
              firstOrdinal == 0,
              firstBindings.isEmpty,
              firstTarget?.identity == target.texture,
              case let .material(
                  terminalNode, terminalOrdinal, terminalBindings, terminalTarget
              ) = transition.transaction.intents[1],
              terminalNode == terminal.nodeIndex,
              terminalOrdinal == 1,
              terminalBindings.count == terminal.bindings.filter({
                  $0.texture.kind == .framebuffer
              }).count,
              terminalBindings.contains(where: {
                  $0.identity == target.texture
              }),
              terminalTarget == nil else { return false }
        return true
    }

    private func recordEffectLocalFramePreparationFallback(
        reasonCode: String,
        effect: Graph.EffectKey,
        boundedDetail: String?
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
                + " layer=%d effect=%d descriptor=%@ detail=%@ count=%d",
            reasonCode,
            effect.layerID,
            effect.effectIndex,
            effect.descriptorID,
            boundedDetail ?? "-",
            count
        )
    }
}
