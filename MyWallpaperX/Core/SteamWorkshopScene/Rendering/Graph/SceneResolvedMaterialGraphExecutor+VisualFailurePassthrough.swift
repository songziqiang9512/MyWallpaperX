import Metal

extension SceneResolvedMaterialGraphExecutor {
    struct VisualFailureSnapshot {
        let pair: PairAtom
        let publications: [Graph.TextureIdentity: SceneFrameTextureResource]
        let commandCount: Int
    }

    /// Applies one effect-entry passthrough after the outer loop has chosen
    /// the source representation. The only GPU work remains the original pair copy.
    func preparePassthrough(
        _ passthrough: StagePassthrough,
        stageCapability: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        snapshot: VisualFailureSnapshot,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        effectLocalFailureReasonCode: inout String?,
        effectLocalActivationBypassReasonCode: inout String?
    ) -> Failure? {
        let reasonCode: String
        let boundedDetail: String?
        let rejection: Failure
        let isActivation: Bool
        switch passthrough {
        case let .activation(reason, bypassProven):
            guard bypassProven || activationBypassIsProvable(
                reasonCode: reason, stageCapability: stageCapability,
                transition: transition, graph: graph, pairStep: pairStep, snapshot: snapshot
            ) else { return .graphStructureRejected }
            reasonCode = reason
            boundedDetail = nil
            rejection = .graphStructureRejected
            isActivation = true
        case let .visualFailure(reason, detail, failure):
            reasonCode = reason
            boundedDetail = detail
            rejection = failure
            isActivation = false
        }
        if !isActivation {
            let ordinaryReason = [
                "material-generic-owner-revoked",
                "material-variant-envelope-frontend",
                "material-variant-envelope-shader-preparation",
                "material-variant-envelope-color-contract",
                "material-variant-envelope-sampler-schema",
                "material-variant-envelope-uniform-schema",
                "material-variant-envelope-animated-frame-metadata",
                "material-variant-envelope-texture-purpose",
                "material-variant-envelope-texture-binding",
                "material-dynamic-uniform-contributor-policy",
                "material-dynamic-uniform-contributor-producer-unavailable",
                "material-dynamic-uniform-script-attachment-unproven",
                "material-dynamic-uniform-producer-unavailable",
                "material-pass-preparation-library-compilation",
                "material-pass-preparation-vertex-function",
                "material-pass-preparation-fragment-function",
                "material-pass-preparation-pipeline-compilation",
                "material-pass-preparation-pipeline-not-prepared",
                "material-finalizer-dynamic-uniform-binding",
                "material-finalizer-host-input-unavailable",
                "material-finalizer-static-uniform-binding",
                "material-finalizer-host-uniform-declaration-conflict",
                "material-finalizer-uniform-declaration-conflict",
                "material-finalizer-color-contract",
                "material-variant-selection-key-unstable",
                "material-finalizer-optional-texture-unavailable",
                "material-finalizer-optional-texture-purpose-mismatch",
                "material-finalizer-optional-texture-content-mismatch",
                "material-finalizer-optional-texture-sampling-unresolved",
                "material-finalizer-scene-environment-unavailable",
                "material-finalizer-system-provider-pending",
                "material-finalizer-system-provider-unavailable",
                "material-finalizer-system-provider-purpose-mismatch",
                "material-finalizer-system-provider-sampling-unresolved",
                "effect-activation-visibility-type-invalid",
                "effect-activation-scalar-type-invalid",
                "dependency-stage-reference-unavailable",
                "dependency-stage-secondary-reference-unavailable",
                "dependency-stage-reference-unsupported",
                "external-primary-provider-source-unavailable",
            ].contains(reasonCode)
            let framebufferPreparationLimitation =
                reasonCode == "material-variant-envelope-invariant"
                    && !graph.renderTargets.isEmpty
            let ordinaryColorContractLimitation =
                reasonCode != "material-finalizer-color-contract"
                    || graph.renderTargets.isEmpty
            guard stageCapability.preEncodeVisualFailureSlots != nil,
                  ordinaryReason || framebufferPreparationLimitation
                    || reasonCode == "material-optional-named-fallback-unproven",
                  ordinaryColorContractLimitation,
                  visualFailureTopologyIsSupported(
                      stageCapability: stageCapability,
                      reasonCode: reasonCode,
                      transition: transition,
                      graph: graph,
                      pairStep: pairStep,
                      snapshot: snapshot
                  ) else {
                return rejection
            }
        }
        let failure = prepareStagePassthrough(
            pairStep: pairStep,
            lease: lease,
            snapshot: snapshot,
            pair: &pair,
            publications: &publications,
            commands: &commands,
            rejection: rejection
        )
        guard failure == nil else { return failure }
        if isActivation {
            effectLocalActivationBypassReasonCode = reasonCode
            return nil
        }
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.fallbackBranches)
#endif
        effectLocalFailureReasonCode = reasonCode
        if reasonCode.hasPrefix("material-pass-preparation-")
            || reasonCode.hasPrefix("material-finalizer-") {
#if DEBUG
            recordEffectLocalFramePreparationFallback(
                reasonCode: reasonCode,
                effect: pairStep.effect,
                boundedDetail: boundedDetail
            )
#endif
        }
        return nil
    }

    /// Reasons whose inactivity is expected author/provider behaviour rather
    /// than a visual failure or a fallback to an old renderer.
    private static let activationBypassReasonCodes: Set<String> = [
        "effect-activation-visibility-disabled",
        "effect-activation-pointer-provider-unavailable",
        "effect-activation-scalar-below-minimum",
        "initially-inactive-property-stage-passthrough",
        "inactive-dependency-preproof-mismatch",
    ]

    /// Read-only proof that an inactive stage may be bypassed without
    /// disturbing the pair, committed transition or history closure. The
    /// caller decides whether an unprovable bypass keeps the effect executed
    /// or drops the frame; only optional visibility uses the non-fatal path.
    func activationBypassIsProvable(
        reasonCode: String,
        stageCapability: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        snapshot: VisualFailureSnapshot
    ) -> Bool {
        guard stageCapability.preEncodeVisualFailureSlots != nil,
              Self.activationBypassReasonCodes.contains(reasonCode) else {
            return false
        }
        return visualFailureTopologyIsSupported(
            stageCapability: stageCapability,
            reasonCode: reasonCode,
            transition: transition,
            graph: graph,
            pairStep: pairStep,
            snapshot: snapshot
        )
    }

    private func prepareStagePassthrough(
        pairStep: Pair.EffectStep,
        lease: SceneGraphRenderTargetLease,
        snapshot: VisualFailureSnapshot,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        rejection: Failure
    ) -> Failure? {
        guard commands.count >= snapshot.commandCount else {
            return rejection
        }
        commands.removeSubrange(snapshot.commandCount ..< commands.count)
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
        return nil
    }

    private func visualFailureTopologyIsSupported(
        stageCapability: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
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
              pairStep.nodes.count == graph.nodes.count else {
            return false
        }
        if reasonCode == "dependency-stage-reference-unavailable"
            || reasonCode == "dependency-stage-secondary-reference-unavailable"
            || reasonCode == "material-optional-named-fallback-unproven"
            || reasonCode == "external-primary-provider-source-unavailable" {
            guard transition.nextState.historyClosureIdentities.isEmpty else {
                return false
            }
            return dependencyStageFailureTopologyIsSupported(
                stageCapability: stageCapability,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                snapshot: snapshot
            )
        }
        if !graph.renderTargets.isEmpty {
            return preEncodeVisualFailureGraphTopologyIsSupported(
                stageCapability: stageCapability,
                transition: transition,
                graph: graph
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
        stageCapability: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        snapshot: VisualFailureSnapshot
    ) -> Bool {
        if !graph.renderTargets.isEmpty {
            return visualFailureFramebufferTopologyIsSupported(
                stageCapability: stageCapability,
                transition: transition,
                graph: graph
            )
        }
        guard stageCapability.passthroughTopologies.contains(.dependencyStage),
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
        stageCapability: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
        transition: State.Transition,
        graph: Graph
    ) -> Bool {
        guard stageCapability.passthroughTopologies.contains(.framebuffer),
              transition.nextState.historyClosureIdentities.isEmpty,
              transition.transaction.intents.count == graph.nodes.count,
              visualFailureGraphTransitionMatches(
                  transition: transition,
                  graph: graph
              ) else {
            return false
        }
        return true
    }

    private func preEncodeVisualFailureGraphTopologyIsSupported(
        stageCapability: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
        transition: State.Transition,
        graph: Graph
    ) -> Bool {
        stageCapability.passthroughTopologies.contains(.preEncodeGraph)
            && visualFailureGraphTransitionMatches(
                transition: transition,
                graph: graph
            )
    }

    private func visualFailureGraphTransitionMatches(
        transition: State.Transition,
        graph: Graph
    ) -> Bool {
        let targets = Set(graph.renderTargets.map(\.texture))
        guard Set(transition.transaction.mappingBefore.keys) == targets,
              Set(transition.transaction.mappingAfter.keys) == targets,
              transition.transaction.allocationGeneration > 0 else {
            return false
        }
        let nodeIntents = transition.transaction.intents.compactMap { intent -> State.Intent? in
            if case let .initialize(identity, _, reason) = intent {
                guard targets.contains(identity) else { return intent }
                if case .materialFunctionClear = reason { return intent }
                return nil
            }
            return intent
        }
        guard nodeIntents.count == graph.nodes.count else { return false }
        for (node, intent) in zip(graph.nodes, nodeIntents) {
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
#if DEBUG
    private func recordEffectLocalFramePreparationFallback(
        reasonCode: String,
        effect: Graph.EffectKey,
        boundedDetail: String?
    ) {
        guard capturesExecutionDiagnostics else { return }
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
#endif
}
