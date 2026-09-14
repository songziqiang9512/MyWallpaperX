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
                              snapshot.variants.contains(where: { variant in
                                  // A readiness-combo variant may be the only
                                  // form that samples this default slot; the
                                  // frame requirement exists as soon as any
                                  // launch variant can select it.
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
        // A same-layer composite reference lives in the named-target
        // namespace while the scene background is a renderer-owned
        // same-frame snapshot in its own identity; the target contract
        // keeps both namespaces distinct, so an owned composite does not
        // alias the background provider.
        let dependencyIsCompatible = switch admitted.dependencyOwnership {
        case .none, .externalPrimary, .graphInternal: true
        case .externalAggregate: false
        }
        let ordered = candidates.allSatisfy {
            sceneBackgroundCandidateIsOrdered(
                $0,
                admittedLayerID: admitted.layerID,
                pairPlan: admitted.pairPlan
            )
        }
        // Both capture routes can supply the background requirement: an
        // ordinary layer reads it via its captured layer texture, and a
        // utility composition reads the same typed publication through its
        // captured main-target execution.
        let routeSupportsBackground = admitted.sourceRoute
            == .capturedLayerTexture
            || admitted.sourceRoute == .capturedMainTargetTexture
#if DEBUG
        if !(routeSupportsBackground
                && admitted.isVisibleExecutionRoot
                && !admitted.isGraphOutputProvider
                && dependencyIsCompatible
                && ordered) {
            NSLog(
                "MWX DEBUG SCENE: phase=capability-admission layer=%d scene-background-compose-shape route=%@ visible=%d provider=%d depCompat=%d ordered=%d",
                admitted.layerID,
                String(describing: admitted.sourceRoute),
                admitted.isVisibleExecutionRoot ? 1 : 0,
                admitted.isGraphOutputProvider ? 1 : 0,
                dependencyIsCompatible ? 1 : 0,
                ordered ? 1 : 0
            )
        }
#endif
        guard routeSupportsBackground,
              admitted.isVisibleExecutionRoot,
              !admitted.isGraphOutputProvider,
              dependencyIsCompatible,
              ordered else {
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
              graph.blockers.isEmpty else { return false }

        // A multi-effect generic-only chain rides the same ordered handoff the
        // dependency runtime proves per layer: every effect is one ordinary
        // material node with a single full-frame output write, no raw compose,
        // and an alternating pair member. The scene-background demand is a
        // same-frame main-target snapshot in its own identity namespace, so it
        // composes with same-layer composite references instead of aliasing
        // them. FBO graphs and non-typed multi-effect shapes stay closed.
        if graph.effects.count > 1 {
            let renderTargetsEmpty = graph.renderTargets.isEmpty
            let nodeShapesValid = nodes.allSatisfy { node in
                node.kind == .material
                    && node.commandSource == nil
                    && node.commandTarget == nil
                    && (node.compose == nil || node.compose == .bool(false))
                    && node.conditions == nil
            }
            let stepShapesValid = pairPlan.effects.count == graph.effects.count
                && pairPlan.effects.allSatisfy { step in
                    step.composeTransitionCount == 0
                        && step.fullFrameOutputWriteCount == 1
                        && step.inputMember != step.outputMember
                        && step.nodes.count == 1
                        && graph.effects.contains { $0.key == step.effect }
                }
            let outputTargetsValid = graph.effects.allSatisfy { effect in
                nodes.contains(where: {
                    $0.effect == effect.key
                        && $0.target == effect.output
                })
            }
            let candidateValid = graph.effects.first(where: {
                $0.key == candidate.key.effect
            }).flatMap { candidateEffect -> Bool? in
                nodes.first(where: {
                    $0.nodeIndex == candidate.key.nodeIndex
                        && $0.effect == candidateEffect.key
                }).map { $0.target == candidateEffect.output }
            } ?? false
            let abiValid = sceneBackgroundCandidateHasTypedSinglePassColorABI(
                candidate
            )
#if DEBUG
            if !(renderTargetsEmpty && nodeShapesValid && stepShapesValid
                    && outputTargetsValid && candidateValid && abiValid) {
                NSLog(
                    "MWX DEBUG SCENE: phase=capability-admission layer=%d background-ordered effects=%d nodes=%d rt=%d nodeShapes=%d stepShapes=%d outTargets=%d candidate=%d abi=%d steps=%@",
                    admittedLayerID,
                    graph.effects.count,
                    nodes.count,
                    renderTargetsEmpty ? 1 : 0,
                    nodeShapesValid ? 1 : 0,
                    stepShapesValid ? 1 : 0,
                    outputTargetsValid ? 1 : 0,
                    candidateValid ? 1 : 0,
                    abiValid ? 1 : 0,
                    pairPlan.effects.map { step in
                        "(eff\(step.effect.effectIndex) n\(step.nodes.count) c\(step.composeTransitionCount) w\(step.fullFrameOutputWriteCount) m\(step.inputMember)\(step.outputMember))"
                    }.joined()
                )
            }
#endif
            guard renderTargetsEmpty, nodeShapesValid, stepShapesValid,
                  outputTargetsValid, candidateValid, abiValid else {
                return false
            }
            return true
        }

        guard graph.effects.count == 1,
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
              pairStep.nodes.count == nodes.count else {
            #if DEBUG
            NSLog(
                "MWX DEBUG SCENE: phase=capability-admission layer=%d background-single-identity effects=%d nodes=%d rt=%d candidateNode=%d pairSteps=%d stepNodes=%d",
                admittedLayerID,
                graph.effects.count,
                nodes.count,
                graph.renderTargets.isEmpty ? 1 : 0,
                candidate.key.nodeIndex,
                pairPlan.effects.count,
                pairPlan.effects.first?.nodes.count ?? -1
            )
            #endif
            return false
        }

        if graph.renderTargets.isEmpty {
            // A candidate may satisfy both typed color ABI and the strict
            // two-node compose shape; evaluate the compose shape first so a
            // two-pass chain is not hard-failed by the single-pass branch.
            let composeShapeCandidate = nodes.count == 2
            let typedABI = sceneBackgroundCandidateHasTypedSinglePassColorABI(
                candidate
            )
            if typedABI && !composeShapeCandidate {
                let typedShapeValid = nodes.count == 1
                    && candidateNode.nodeIndex == nodes[0].nodeIndex
                    && candidateNode.target == effect.output
                    && (candidateNode.compose == nil
                        || candidateNode.compose == .bool(false))
                    && pairStep.composeTransitionCount == 0
                    && pairStep.fullFrameOutputWriteCount == 1
                    && pairStep.inputMember != pairStep.outputMember
                #if DEBUG
                if !typedShapeValid {
                    NSLog(
                        "MWX DEBUG SCENE: phase=capability-admission layer=%d background-typed-shape nodes=%d compose=%@ cTrans=%d writes=%d members=%d-%d",
                        admittedLayerID,
                        nodes.count,
                        candidateNode.compose.map { "\($0)" } ?? "nil",
                        pairStep.composeTransitionCount,
                        pairStep.fullFrameOutputWriteCount,
                        pairStep.inputMember == .zero ? 0 : 1,
                        pairStep.outputMember == .zero ? 0 : 1
                    )
                }
                #endif
                guard typedShapeValid else { return false }
                return true
            }
            // The background slot follows the authored sampler contract
            // (any slot may declare the `_rt_FullFrameBuffer` default); the
            // compose shape and the typed purpose facts own the safety.
            guard nodes.count == 2,
                  candidateNode.nodeIndex == nodes[0].nodeIndex,
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
