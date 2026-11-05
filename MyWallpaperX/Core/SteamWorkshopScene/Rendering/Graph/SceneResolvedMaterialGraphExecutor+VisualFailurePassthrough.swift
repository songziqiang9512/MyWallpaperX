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
            guard bypassProven || stageCapability.supportsEffectEntryPassthrough
            else { return .graphStructureRejected }
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
            guard stageCapability.supportsEffectEntryPassthrough else { return rejection }
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
