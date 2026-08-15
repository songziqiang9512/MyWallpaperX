import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    func executeClaimed(
        claim: Bridge.ClaimedExecution,
        dependencyEffect: SceneDependencyEffectInput?,
        commandBuffer: MTLCommandBuffer
    ) -> Bridge.ExecutionResult {
        var emission = Emission()
        lock.lock()
        guard terminalFailureReason == nil, frameIsActive,
              framePreparationComplete, !frameRequiresDrop,
              frameFailure == nil, let executor,
              let identity = preparedLedgerByLayerID[claim.layerID],
              let index = activeTransactions.firstIndex(of: identity),
              var ledger = activeByID[identity],
              ledger.layerID == claim.layerID,
              ledger.capabilityToken == claim.token,
              ledger.claimConsumed,
              ledger.phase == .allocationCommitted,
              ledger.commandBuffer === commandBuffer,
              commandBuffer.status == .notEnqueued,
              dependenciesMatch(
                  prepared: ledger.preparedDependencyEffect,
                  ready: dependencyEffect,
                  ownership: claim.dependencyOwnership
              ),
              activeTransactions[..<index].allSatisfy({
                  activeByID[$0]?.phase == .composited
              }), activeTransactions[activeTransactions.index(after: index)...]
                .allSatisfy({ activeByID[$0]?.phase == .allocationCommitted })
        else {
            let reason = commandBuffer.status == .notEnqueued
                ? "prepared-frame-consumption-rejected"
                : "transaction-armed-after-submit"
            emission = claimedFailureLocked(reason: reason)
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        guard executor.encode(ledger.prepared, commandBuffer: commandBuffer) else {
            emission = claimedFailureLocked(reason: "command-append-failed")
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: "command-append-failed")
        }
        ledger.phase = .encoded
        activeByID[identity] = ledger
        frameEncoded += 1
        let consumesExternalPrimaryDependency: Bool
        if case .externalPrimary = claim.dependencyOwnership {
            consumesExternalPrimaryDependency = true
        } else {
            consumesExternalPrimaryDependency = false
        }
        let result = Bridge.ExecutionResult.encoded(
            texture: ledger.prepared.finalTexture,
            ticket: .init(
                identity: identity,
                epoch: executionEpoch,
                finalTextureIdentity: ObjectIdentifier(ledger.prepared.finalTexture),
                consumesExternalPrimaryDependency:
                    consumesExternalPrimaryDependency
            )
        )
        lock.unlock()
        return result
    }

    func dependencyReservationMatches(
        _ input: SceneDependencyEffectInput?,
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        switch ownership {
        case .none, .graphInternal:
            return input == nil
        case .externalPrimary(let binding):
            switch binding.kind {
            case .clippingMask:
                guard binding.slot.slotIndex == 1 else { return false }
            case .proceduralNoiseLayer:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 3,
                      binding.blendMode == 0 else { return false }
            case .imageLayerBlend:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 1,
                      binding.blendMode == 0 else { return false }
            }
            guard let input else { return false }
            return input.consumerLayerID == binding.consumerLayerID
                && input.providerLayerID == binding.providerLayerID
                && input.variant == .primary
                && input.slot == binding.slot
                && input.blendMode == binding.blendMode
        }
    }

    private func dependenciesMatch(
        prepared: SceneDependencyEffectInput?,
        ready: SceneDependencyEffectInput?,
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        guard dependencyReservationMatches(prepared, ownership: ownership),
              dependencyReservationMatches(ready, ownership: ownership) else {
            return false
        }
        guard let prepared, let ready else { return true }
        return prepared.frameEpoch == ready.frameEpoch
            && prepared.texture === ready.texture
    }
}
