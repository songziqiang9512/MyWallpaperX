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
    /// not a fabricated shader result. Live resource availability, target,
    /// dependency and runtime encode failures never reach this path.
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
            "material-variant-envelope-animated-frame-metadata",
            "material-variant-envelope-texture-purpose",
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
            "dependency-stage-reference-unavailable",
            "dependency-stage-secondary-reference-unavailable",
        ].contains(reasonCode),
              visualFailureTopologyIsSupported(
                  reasonCode: reasonCode,
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
        reasonCode: String,
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
        if reasonCode == "dependency-stage-reference-unavailable"
            || reasonCode == "dependency-stage-secondary-reference-unavailable" {
            return dependencyStageFailureTopologyIsSupported(
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                snapshot: snapshot
            )
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

    private func dependencyStageFailureTopologyIsSupported(
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        snapshot: VisualFailureSnapshot
    ) -> Bool {
        if !graph.renderTargets.isEmpty {
            guard let effect = graph.effects.first else { return false }
            return visualFailureFramebufferTopologyIsSupported(
                transition: transition,
                graph: graph,
                effect: effect,
                pairStep: pairStep
            )
        }
        guard SceneResolvedMaterialExecutionCapabilityCatalog
                .dependencyStageFailureMayPassthrough(
                    graph,
                    pairStep: pairStep
                ),
              pairStep.inputMember == snapshot.pair.member,
              transition.transaction.intents.count == 1,
              let node = graph.nodes.first,
              let pairNode = pairStep.nodes.first,
              case let .material(
                  nodeIndex, materialOrdinal, bindings, target
              ) = transition.transaction.intents[0],
              nodeIndex == node.nodeIndex,
              materialOrdinal == node.materialOrdinal,
              bindings.isEmpty,
              target == nil,
              pairNode.nodeIndex == node.nodeIndex,
              pairNode.kind == .material,
              pairNode.currentMemberBeforeNode == snapshot.pair.member,
              pairNode.fullFrameWriteMember == snapshot.pair.member.opposite,
              !pairNode.rotatesAfterNode,
              pairStep.outputMember == snapshot.pair.member.opposite else {
            return false
        }
        return true
    }

    private func visualFailureFramebufferTopologyIsSupported(
        transition: State.Transition,
        graph: Graph,
        effect: Graph.Effect,
        pairStep: Pair.EffectStep
    ) -> Bool {
        let targets = Set(graph.renderTargets.map(\.texture))
        guard SceneResolvedMaterialExecutionCapabilityCatalog
                .visualFailureFramebufferTopologyMayPassthrough(
                    graph,
                    effect: effect,
                    pairStep: pairStep
                ),
              transition.transaction.intents.count == graph.nodes.count,
              Set(transition.transaction.mappingBefore.keys) == targets,
              Set(transition.transaction.mappingAfter.keys) == targets else {
            return false
        }
        for (node, intent) in zip(
            graph.nodes,
            transition.transaction.intents
        ) {
            switch (node.kind, intent) {
            case let (.material, .material(
                nodeIndex, materialOrdinal, bindings, target
            )):
                let expectedBindings = node.bindings
                    .filter { $0.texture.kind == .framebuffer }
                    .sorted { ($0.slot ?? Int.max) < ($1.slot ?? Int.max) }
                guard node.nodeIndex == nodeIndex,
                      node.materialOrdinal == materialOrdinal,
                      bindings.count == expectedBindings.count,
                      zip(bindings, expectedBindings).allSatisfy({
                          $0.identity == $1.texture && $0.slot == $1.slot
                      }),
                      target?.identity == (node.target?.kind == .framebuffer
                          ? node.target : nil) else { return false }

            case let (.copy, .copy(
                nodeIndex, _, source, _, target, _
            )), let (.swap, .swap(
                nodeIndex, _, source, _, target, _
            )):
                guard node.nodeIndex == nodeIndex,
                      node.commandSource == source,
                      node.commandTarget == target else { return false }

            default:
                return false
            }
        }
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
