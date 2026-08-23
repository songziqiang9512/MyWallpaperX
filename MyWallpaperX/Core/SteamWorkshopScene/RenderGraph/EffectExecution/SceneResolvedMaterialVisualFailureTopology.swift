import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    /// Bounded launch-time isolation for one ordinary effect whose only
    /// missing input is an unavailable forward named provider. The provider
    /// is not fabricated or reordered; the exact effect becomes a pair copy.
    static func dependencyStageFailureMayPassthrough(
        _ graph: Graph,
        pairStep: SceneLayerFullFramePairPlan.EffectStep?
    ) -> Bool {
        guard graph.effects.count == 1,
              graph.blockers.isEmpty,
              let effect = graph.effects.first,
              let pairStep, pairStep.effect == effect.key else { return false }
        if !graph.renderTargets.isEmpty {
            return visualFailureFramebufferTopologyMayPassthrough(
                graph,
                effect: effect,
                pairStep: pairStep
            )
        }
        guard graph.nodes.count == 1,
              let node = graph.nodes.first,
              pairStep.nodes.count == 1,
              pairStep.fullFrameOutputWriteCount == 1,
              pairStep.composeTransitionCount == 0,
              pairStep.inputMember != pairStep.outputMember,
              node.effect == effect.key,
              node.kind == .material,
              node.target == effect.output,
              node.commandSource == nil,
              node.commandTarget == nil,
              node.conditions == nil,
              node.compose == nil || node.compose == .bool(false),
              node.bindings.allSatisfy({
                  $0.conditions == nil
                    && ($0.texture == effect.input
                        || $0.texture.kind == .unresolved)
              }) else { return false }
        return true
    }

    /// A Program/finalizer/pipeline failure happens before any authored graph
    /// command is encoded. At that boundary every graph already accepted by
    /// the shared target planner can be skipped atomically: the executor keeps
    /// the effect-entry current, preserves only committed history, and drops
    /// the candidate node/command prefix. This predicate deliberately does not
    /// admit unavailable dependencies; those retain the narrower no-history
    /// contract above because their producer lifecycle is a separate owner.
    static func preEncodeVisualFailureGraphMayPassthrough(
        _ graph: Graph,
        effect: Graph.Effect,
        pairStep: SceneLayerFullFramePairPlan.EffectStep
    ) -> Bool {
        guard graph.effects.count == 1,
              graph.effects[0].key == effect.key,
              graph.blockers.isEmpty,
              !graph.nodes.isEmpty,
              graph.nodes.count == pairStep.nodes.count,
              pairStep.effect == effect.key,
              let inputRole = SceneAuthoredEffectInputValidator.role(
                  for: effect.input,
                  layerID: graph.layerID
              ), case .success = SceneGraphRenderTargetPlan.make(
                  graph: graph,
                  inputRole: inputRole,
                  inputWidth: 1,
                  inputHeight: 1
              ) else { return false }
        return true
    }

    /// Admits only a same-effect, non-persistent FBO graph whose reads are
    /// dominated by authored writes. The graph may interleave ordinary
    /// material, copy and swap nodes, but it must have one terminal full-frame
    /// output and cannot hide history, clear, condition or compose semantics.
    static func visualFailureFramebufferTopologyMayPassthrough(
        _ graph: Graph,
        effect: Graph.Effect,
        pairStep: SceneLayerFullFramePairPlan.EffectStep
    ) -> Bool {
        let targetIdentities = Set(graph.renderTargets.map(\.texture))
        guard !targetIdentities.isEmpty,
              targetIdentities.count == graph.renderTargets.count,
              graph.renderTargets.allSatisfy({ target in
                  !target.declaredUnique
                    && target.clear == nil
                    && target.conditions == nil
              }),
              graph.nodes.count >= 2,
              pairStep.nodes.count == graph.nodes.count,
              pairStep.fullFrameOutputWriteCount == 1,
              pairStep.composeTransitionCount == 0,
              pairStep.inputMember != pairStep.outputMember else { return false }

        var initializedTargets = Set<Graph.TextureIdentity>()
        var consumedTargets = Set<Graph.TextureIdentity>()
        var materialOrdinals: [Int] = []
        var terminalReadsFramebuffer = false
        for (offset, pair) in zip(graph.nodes, pairStep.nodes).enumerated() {
            let node = pair.0
            let pairNode = pair.1
            guard node.effect == effect.key,
                  node.nodeIndex == pairNode.nodeIndex,
                  node.definitionPassIndex == pairNode.definitionPassIndex,
                  node.conditions == nil,
                  node.compose == nil || node.compose == .bool(false),
                  pairNode.currentMemberBeforeNode == pairStep.inputMember,
                  pairNode.currentMemberAfterNode == pairStep.inputMember,
                  !pairNode.rotatesAfterNode else { return false }

            switch node.kind {
            case .material:
                guard pairNode.kind == .material,
                      let ordinal = node.materialOrdinal,
                      node.commandSource == nil,
                      node.commandTarget == nil,
                      node.bindings.allSatisfy({ binding in
                          binding.conditions == nil
                            && (binding.texture == effect.input
                                || (targetIdentities.contains(binding.texture)
                                    && initializedTargets.contains(binding.texture)))
                      }) else { return false }
                materialOrdinals.append(ordinal)
                consumedTargets.formUnion(node.bindings.compactMap { binding in
                    targetIdentities.contains(binding.texture)
                        ? binding.texture : nil
                })
                if node.target == effect.output {
                    guard offset == graph.nodes.indices.last,
                          pairNode.fullFrameWriteMember == pairStep.outputMember,
                          node.bindings.contains(where: {
                              targetIdentities.contains($0.texture)
                          }) else { return false }
                    terminalReadsFramebuffer = true
                } else {
                    guard let target = node.target,
                          targetIdentities.contains(target),
                          pairNode.fullFrameWriteMember == nil else { return false }
                    initializedTargets.insert(target)
                }

            case .copy:
                guard pairNode.kind == .copy,
                      node.materialOrdinal == nil,
                      node.target == nil,
                      node.bindings.isEmpty,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      targetIdentities.contains(source),
                      initializedTargets.contains(source),
                      targetIdentities.contains(target),
                      pairNode.fullFrameReadMember == nil,
                      pairNode.fullFrameWriteMember == nil else { return false }
                consumedTargets.insert(source)
                initializedTargets.insert(target)

            case .swap:
                guard pairNode.kind == .swap,
                      node.materialOrdinal == nil,
                      node.target == nil,
                      node.bindings.isEmpty,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      targetIdentities.contains(source),
                      initializedTargets.contains(source),
                      targetIdentities.contains(target),
                      initializedTargets.contains(target),
                      pairNode.fullFrameReadMember == nil,
                      pairNode.fullFrameWriteMember == nil else { return false }
                consumedTargets.insert(source)
                consumedTargets.insert(target)

            case .unknownCommand:
                return false
            }
        }
        return terminalReadsFramebuffer
            && materialOrdinals.count >= 2
            && zip(materialOrdinals, materialOrdinals.dropFirst())
                .allSatisfy({ $0 < $1 })
            && initializedTargets == targetIdentities
            && consumedTargets == targetIdentities
    }
}
