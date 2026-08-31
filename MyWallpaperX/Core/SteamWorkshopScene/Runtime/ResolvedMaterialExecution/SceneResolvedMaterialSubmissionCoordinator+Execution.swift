import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    /// Rejects one prepared external-dependency transaction before encoding,
    /// releases only its allocation, and rebases independent successors on the
    /// last terminal-output tails. Integrity failures still use the frame-failure
    /// path; this entry point accepts only the typed ordinary capture miss.
    func rejectPreparedExternalDependencyLocally(
        layerID: Int,
        reasonCode: String
    ) -> Bool {
        guard reasonCode == "external-primary-provider-capture-unavailable"
        else { return false }
        var emission = Emission()
        lock.lock()
        guard terminalFailureReason == nil, frameIsActive,
              framePreparationComplete, !frameRequiresDrop,
              frameFailure == nil,
              frameLocalFallbacks[layerID] == nil,
              let identity = preparedLedgerByLayerID[layerID],
              let index = activeTransactions.firstIndex(of: identity),
              let ledger = activeByID[identity],
              ledger.layerID == layerID,
              let capability = capabilities.resolve(ledger.capabilityToken),
              capability.layerID == layerID,
              case .externalPrimary = capability.dependencyOwnership,
              ledger.phase == .allocationCommitted,
              !ledger.claimConsumed,
              dependencyReservationMatches(
                  ledger.preparedDependencyEffect,
                  unavailability: ledger.preparedDependencyUnavailability,
                  ownership: capability.dependencyOwnership
              ),
              ledger.prepared.historyTokensByEffect.isEmpty,
              ledger.prepared.stages.allSatisfy({
                  $0.transition.nextState.historyClosureIdentities.isEmpty
                      && ledger.committedBaseTails[$0.effect] == nil
              }),
              ledger.commandBuffer.status == .notEnqueued,
              activeTransactions[..<index].allSatisfy({
                  activeByID[$0]?.phase == .outputConsumed
              }) else {
            lock.unlock()
            return false
        }
        let successorIDs = Array(
            activeTransactions[activeTransactions.index(after: index)...]
        )
        var rebasedTails = scheduledTails
        var rebasedByIdentity: [UInt64: [Graph.EffectKey: Tail]] = [:]
        for successorID in successorIDs {
            guard let successor = activeByID[successorID],
                  successor.phase == .allocationCommitted,
                  let blueprint = successor.blueprint,
                  let commit = successor.commit else {
                lock.unlock()
                return false
            }
            rebasedTails = committedCandidateTailsLocked(
                blueprint: blueprint,
                startingAt: rebasedTails,
                commit: commit,
                prepared: successor.prepared
            )
            guard tailsAreValid(rebasedTails) else {
                lock.unlock()
                return false
            }
            rebasedByIdentity[successorID] = rebasedTails
        }
        emission = terminalizeLedgerLocked(
            identity,
            as: .failed(reasonCode: reasonCode, gpu: nil)
        )
        preparedLedgerByLayerID.removeValue(forKey: layerID)
        frameLocalFallbacks[layerID] = reasonCode
        for successorID in successorIDs {
            activeByID[successorID]?.candidateTails =
                rebasedByIdentity[successorID]
        }
        emission.diagnostics.append(
            "dependency-subgraph-local-rejection layer=\(layerID) reason=\(reasonCode)"
        )
        lock.unlock()
        emit(emission)
        return true
    }

    func executeClaimed(
        claim: Bridge.ClaimedExecution,
        dependencyEffect: SceneDependencyEffectInput?,
        sceneBackgroundTexture: MTLTexture? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> Bridge.ExecutionResult {
        var emission = Emission()
        lock.lock()
        guard terminalFailureReason == nil, frameIsActive,
              framePreparationComplete, !frameRequiresDrop,
              frameFailure == nil, let executor, let frame,
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
                  preparedUnavailability:
                    ledger.preparedDependencyUnavailability,
                  ready: dependencyEffect,
                  ownership: claim.dependencyOwnership
              ), sceneBackgroundTextureMatches(
                  prepared: ledger.prepared.sceneBackgroundResource,
                  ready: sceneBackgroundTexture,
                  requirement: claim.sceneBackgroundRequirement,
                  frameEpoch: frame.textureRegistrySnapshot.frameEpoch
              ),
              activeTransactions[..<index].allSatisfy({
                  activeByID[$0]?.phase == .outputConsumed
              }), activeTransactions[activeTransactions.index(after: index)...]
                .allSatisfy({ activeByID[$0]?.phase == .allocationCommitted })
        else {
            let reason = commandBuffer.status == .notEnqueued
                ? "prepared-frame-consumption-rejected"
                : "transaction-armed-after-submit"
            let detail = preparedFrameConsumptionRejectionDetailLocked(
                claim: claim,
                dependencyEffect: dependencyEffect,
                sceneBackgroundTexture: sceneBackgroundTexture,
                commandBuffer: commandBuffer
            )
            emission = claimedFailureLocked(reason: reason)
            emission.diagnostics.append(
                "\(reason) layer=\(claim.layerID) detail=\(detail)"
            )
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        let encodeResult = executor.encodeResult(
            ledger.prepared,
            commandBuffer: commandBuffer
        )
        guard case .success = encodeResult else {
            let reason: String
            if case let .failure(failure) = encodeResult {
                reason = "command-append-\(failure.rawValue)"
            } else {
                reason = "command-append-result-invariant"
            }
            emission = claimedFailureLocked(reason: reason)
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        ledger.phase = .encoded
        activeByID[identity] = ledger
        frameEncoded += 1
        let consumesExternalPrimaryDependency: Bool
        if case .externalPrimary = claim.dependencyOwnership,
           ledger.preparedDependencyUnavailability == nil {
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
                    consumesExternalPrimaryDependency,
                effectFailures: ledger.prepared.stages.compactMap { stage in
                    guard let reasonCode = stage.effectLocalFailureReasonCode else {
                        return nil
                    }
                    return .init(
                        layerID: stage.effect.layerID,
                        effectIndex: stage.effect.effectIndex,
                        descriptorID: stage.effect.descriptorID,
                        reasonCode: reasonCode
                    )
                }
            )
        )
        lock.unlock()
        return result
    }

    private func preparedFrameConsumptionRejectionDetailLocked(
        claim: Bridge.ClaimedExecution,
        dependencyEffect: SceneDependencyEffectInput?,
        sceneBackgroundTexture: MTLTexture?,
        commandBuffer: MTLCommandBuffer
    ) -> String {
        guard terminalFailureReason == nil else { return "runtime-terminal" }
        guard frameIsActive else { return "frame-inactive" }
        guard framePreparationComplete else { return "frame-not-prepared" }
        guard !frameRequiresDrop else { return "frame-drop-required" }
        guard frameFailure == nil else { return "frame-failure-recorded" }
        guard executor != nil else { return "executor-unavailable" }
        guard let frame else { return "frame-snapshot-unavailable" }
        guard let identity = preparedLedgerByLayerID[claim.layerID]
        else { return "prepared-ledger-missing" }
        guard let index = activeTransactions.firstIndex(of: identity)
        else { return "prepared-order-missing" }
        guard let ledger = activeByID[identity]
        else { return "prepared-ledger-unavailable" }
        guard ledger.layerID == claim.layerID else { return "layer-mismatch" }
        guard ledger.capabilityToken == claim.token
        else { return "capability-token-mismatch" }
        guard ledger.claimConsumed else { return "claim-not-consumed" }
        guard ledger.phase == .allocationCommitted
        else { return "ledger-phase-\(ledger.phase.rawValue)" }
        guard ledger.commandBuffer === commandBuffer
        else { return "command-buffer-mismatch" }
        guard commandBuffer.status == .notEnqueued
        else { return "command-buffer-status-\(commandBuffer.status.rawValue)" }
        guard dependenciesMatch(
            prepared: ledger.preparedDependencyEffect,
            preparedUnavailability: ledger.preparedDependencyUnavailability,
            ready: dependencyEffect,
            ownership: claim.dependencyOwnership
        ) else { return "dependency-input-mismatch" }
        guard sceneBackgroundTextureMatches(
            prepared: ledger.prepared.sceneBackgroundResource,
            ready: sceneBackgroundTexture,
            requirement: claim.sceneBackgroundRequirement,
            frameEpoch: frame.textureRegistrySnapshot.frameEpoch
        ) else { return "scene-background-mismatch" }
        guard activeTransactions[..<index].allSatisfy({
            activeByID[$0]?.phase == .outputConsumed
        }) else { return "predecessor-output-not-consumed" }
        guard activeTransactions[activeTransactions.index(after: index)...]
            .allSatisfy({ activeByID[$0]?.phase == .allocationCommitted })
        else { return "successor-phase-mismatch" }
        return "unknown"
    }

    func dependencyReservationMatches(
        _ input: SceneDependencyEffectInput?,
        unavailability:
            Bridge.FrameInputs.DependencyUnavailability? = nil,
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        switch ownership {
        case .none, .graphInternal:
            return input == nil && unavailability == nil
        case .externalPrimary(let binding):
            switch binding.kind {
            case .resolvedMaterial:
                guard binding.slot.slotIndex == 1,
                      binding.blendMode == 0 else { return false }
            case .solidLayer:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 3,
                      binding.blendMode == 0 else { return false }
            case .imageLayerBlend:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 1,
                      SceneImageLayerBlendDependencyContract.supports(
                          blendMode: binding.blendMode
                      ),
                      binding.blendMode == 0
                        || binding.requiresResolvedMaterialProgram else {
                    return false
                }
            case .visibleImageGraphOutput:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 1,
                      binding.blendMode == 0 else { return false }
            }
            if let unavailability {
                return input == nil
                    && unavailability == .providerSourceUnavailable
            }
            guard let input else { return false }
            return input.consumerLayerID == binding.consumerLayerID
                && input.providerLayerID == binding.providerLayerID
                && input.variant == .primary
                && input.slot == binding.slot
                && input.blendMode == binding.blendMode
        }
    }

    func sceneBackgroundReservationMatches(
        _ resource: SceneFrameTextureResource?,
        requirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?,
        frameEpoch: UInt64
    ) -> Bool {
        switch (requirement, resource) {
        case (nil, nil):
            return true
        case let (requirement?, resource?):
            return resource.isCompleteSceneBackground(
                consumerLayerID: requirement.layerID,
                frameEpoch: frameEpoch
            )
        case (nil, _?), (_?, nil):
            return false
        }
    }

    private func dependenciesMatch(
        prepared: SceneDependencyEffectInput?,
        preparedUnavailability:
            Bridge.FrameInputs.DependencyUnavailability?,
        ready: SceneDependencyEffectInput?,
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        guard dependencyReservationMatches(
                prepared,
                unavailability: preparedUnavailability,
                ownership: ownership
              ),
              preparedUnavailability == nil
                || ready == nil,
              preparedUnavailability != nil
                || dependencyReservationMatches(ready, ownership: ownership) else {
            return false
        }
        if preparedUnavailability != nil { return true }
        guard let prepared, let ready else { return true }
        return prepared.frameEpoch == ready.frameEpoch
            && prepared.texture === ready.texture
    }

    func preparedExternalDependencyBypassReason(layerID: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, framePreparationComplete,
              !frameRequiresDrop, frameFailure == nil,
              let identity = preparedLedgerByLayerID[layerID],
              let ledger = activeByID[identity],
              ledger.layerID == layerID,
              ledger.phase == .allocationCommitted,
              !ledger.claimConsumed,
              let unavailable = ledger.preparedDependencyUnavailability,
              ledger.preparedDependencyEffect == nil,
              ledger.prepared.stages.contains(where: {
                  $0.effect.layerID == layerID
                      && $0.effectLocalFailureReasonCode == unavailable.rawValue
              }) else { return nil }
        return unavailable.rawValue
    }

    private func sceneBackgroundTextureMatches(
        prepared: SceneFrameTextureResource?,
        ready: MTLTexture?,
        requirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?,
        frameEpoch: UInt64
    ) -> Bool {
        guard sceneBackgroundReservationMatches(
            prepared,
            requirement: requirement,
            frameEpoch: frameEpoch
        ) else { return false }
        guard let prepared, let ready else {
            return prepared == nil && ready == nil
        }
        return prepared.publication.texture === ready
    }
}
