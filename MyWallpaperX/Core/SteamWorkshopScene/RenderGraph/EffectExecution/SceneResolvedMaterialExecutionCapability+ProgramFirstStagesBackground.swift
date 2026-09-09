import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct SceneBackgroundCandidate {
        let product: SceneGraphAdmissionProduct
        let key: MaterialKey
        let slot: Int
        let consumerLayerID: Int
        let variants: SceneResolvedMaterialVariantCache
    }

    static func sceneBackgroundRequirement(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [StageCapability]
    ) -> Result<SceneBackgroundRequirement?, Rejection> {
        var candidates: [SceneBackgroundCandidate] = []
        for stage in stages {
            guard case let .resolved(product, materials, _) = stage else { continue }
            for material in materials.values {
                let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
                guard snapshot.allEntriesReady,
                      !snapshot.variants.isEmpty,
                      let activeSlots = material.variants
                        .launchEnvelopeActiveTextureSlots else { continue }
                for slot in activeSlots.sorted() {
                    let selected = material.template.textureSlots.indices.contains(slot)
                        ? material.template.textureSlots[slot]?
                            .candidates.last?.reference : nil
                    let consumerLayerID: Int?
                    if case let .provider(.sceneBackground(layerID))? = selected {
                        consumerLayerID = layerID
                    } else if selected == nil,
                              snapshot.variants.allSatisfy({ variant in
                                  guard let sampler = variant.activeSamplers[slot]
                                  else { return false }
                                  return SceneResolvedMaterialTextureResolver
                                    .sceneBackgroundDefault(
                                        template: material.template,
                                        sampler: sampler,
                                        slot: slot
                                    ) != nil
                              }) {
                        consumerLayerID = material.template.effectContext?
                            .key.layerID
                    } else {
                        consumerLayerID = nil
                    }
                    guard let consumerLayerID else { continue }
                    candidates.append(.init(
                        product: product,
                        key: material.key,
                        slot: slot,
                        consumerLayerID: consumerLayerID,
                        variants: material.variants
                    ))
                }
            }
        }
        guard !candidates.isEmpty else { return .success(nil) }
        guard Set(candidates.map(\.key)).count == candidates.count,
              let candidate = candidates.sorted(by: {
                  if $0.key.effect.effectIndex != $1.key.effect.effectIndex {
                      return $0.key.effect.effectIndex < $1.key.effect.effectIndex
                  }
                  if $0.key.nodeIndex != $1.key.nodeIndex {
                      return $0.key.nodeIndex < $1.key.nodeIndex
                  }
                  return $0.slot < $1.slot
              }).first else {
            return .failure(rejection("scene-background-provider-ambiguous"))
        }
        let dependencyIsCompatible = switch admitted.dependencyOwnership {
        case .none, .externalPrimary: true
        case .graphInternal, .externalAggregate: false
        }
        guard admitted.sourceRoute == .capturedLayerTexture,
              admitted.isVisibleExecutionRoot,
              !admitted.isGraphOutputProvider,
              dependencyIsCompatible,
              candidates.allSatisfy({ sceneBackgroundCandidateIsOrdered(
                  $0,
                  admittedLayerID: admitted.layerID,
                  pairPlan: admitted.pairPlan
              ) }) else {
            return .failure(rejection("scene-background-compose-shape"))
        }
        return .success(.init(
            layerID: admitted.layerID,
            effect: candidate.key.effect,
            nodeIndex: candidate.key.nodeIndex,
            slot: candidate.slot,
            bindingCount: candidates.count
        ))
    }

    static func sceneBackgroundCandidateIsOrdered(
        _ candidate: SceneBackgroundCandidate,
        admittedLayerID: Int,
        pairPlan: SceneLayerFullFramePairPlan
    ) -> Bool {
        let graph = candidate.product.graph
        let nodes = graph.nodes.sorted { $0.nodeIndex < $1.nodeIndex }
        guard candidate.consumerLayerID == admittedLayerID,
              graph.layerID == admittedLayerID,
              graph.effects.count == 1,
              graph.blockers.isEmpty,
              let effect = graph.effects.first,
              candidate.key.effect == effect.key,
              let candidateNode = nodes.first(where: {
                  $0.nodeIndex == candidate.key.nodeIndex
              }),
              candidateNode.kind == .material,
              candidateNode.effect == effect.key,
              candidateNode.commandSource == nil,
              candidateNode.commandTarget == nil,
              let pairStep = pairPlan.effects.first(where: {
                  $0.effect == effect.key
              }),
              pairStep.nodes.count == nodes.count else { return false }

        if graph.renderTargets.isEmpty {
            if sceneBackgroundCandidateHasTypedSinglePassColorABI(candidate) {
                guard nodes.count == 1,
                      candidateNode.nodeIndex == nodes[0].nodeIndex,
                      candidateNode.target == effect.output,
                      candidateNode.compose == nil
                        || candidateNode.compose == .bool(false),
                      pairStep.composeTransitionCount == 0,
                      pairStep.fullFrameOutputWriteCount == 1,
                      pairStep.inputMember != pairStep.outputMember else {
                    return false
                }
                return true
            }
            guard nodes.count == 2,
                  candidateNode.nodeIndex == nodes[0].nodeIndex,
                  candidate.slot == 1,
                  nodes[0].kind == .material,
                  nodes[1].kind == .material,
                  nodes[0].effect == effect.key,
                  nodes[1].effect == effect.key,
                  nodes[0].target == effect.output,
                  nodes[1].target == effect.output,
                  nodes[0].compose == .bool(true),
                  nodes[1].compose == nil || nodes[1].compose == .bool(false),
                  nodes.allSatisfy({ node in
                      node.bindings.allSatisfy { $0.texture == effect.input }
                  }),
                  pairStep.composeTransitionCount == 1,
                  pairStep.fullFrameOutputWriteCount == 2,
                  pairStep.inputMember == pairStep.outputMember else { return false }
            return true
        }

        guard candidate.product.clearFunctions.functions.isEmpty,
              candidateNode.nodeIndex == nodes.last?.nodeIndex,
              candidateNode.target == effect.output,
              candidateNode.compose == nil
                || candidateNode.compose == .bool(false),
              nodes.dropLast().allSatisfy({ $0.target != effect.output }),
              pairStep.composeTransitionCount == 0,
              pairStep.fullFrameOutputWriteCount == 1,
              pairStep.inputMember != pairStep.outputMember
        else { return false }
        return true
    }

    static func sceneBackgroundCandidateHasTypedSinglePassColorABI(
        _ candidate: SceneBackgroundCandidate
    ) -> Bool {
        let snapshot = candidate.variants.launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady,
              !snapshot.variants.isEmpty else { return false }
        return snapshot.variants.allSatisfy { variant in
            guard variant.activeSamplers[candidate.slot] != nil else {
                return true
            }
            return variant.premultipliedColorInputSlots.contains(candidate.slot)
        } && snapshot.variants.contains { variant in
            variant.activeSamplers[candidate.slot] != nil
                && variant.premultipliedColorInputSlots.contains(candidate.slot)
        }
    }

}
