import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    func dependencyEffectsReservationMatches(
        _ effects: [SceneDependencyEffectInput],
        ownership: SceneResolvedMaterialDependencyOwnership,
        frameEpoch: UInt64
    ) -> Bool {
        guard case let .externalAggregate(aggregate) = ownership else {
            return false
        }
        return aggregateDependencyEffectsMatch(
            effects,
            aggregate: aggregate,
            frameEpoch: frameEpoch
        )
    }

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
              externalDependencyOwnershipIsSupported(
                  capability.dependencyOwnership
              ),
              ledger.phase == .allocationCommitted,
              !ledger.claimConsumed,
              preparedDependencyReservationMatches(
                  ledger,
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

    private func preparedDependencyReservationMatches(
        _ ledger: PreparedLedger,
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        switch ownership {
        case .externalPrimary:
            return ledger.preparedDependencyEffects.isEmpty
                && dependencyReservationMatches(
                    ledger.preparedDependencyEffect,
                    unavailability: ledger.preparedDependencyUnavailability,
                    ownership: ownership
                )
        case .externalAggregate:
            guard ledger.preparedDependencyEffect == nil,
                  ledger.preparedDependencyUnavailability == nil,
                  let frameEpoch = frame?.textureRegistrySnapshot.frameEpoch
            else { return false }
            return dependencyEffectsReservationMatches(
                ledger.preparedDependencyEffects,
                ownership: ownership,
                frameEpoch: frameEpoch
            )
        case .none, .graphInternal:
            return false
        }
    }

    private func externalDependencyOwnershipIsSupported(
        _ ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        switch ownership {
        case .externalPrimary, .externalAggregate:
            return true
        case .none, .graphInternal:
            return false
        }
    }

    func executeClaimed(
        claim: Bridge.ClaimedExecution,
        dependencyEffect: SceneDependencyEffectInput?,
        dependencyEffects: [SceneDependencyEffectInput] = [],
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
              let capability = capabilities.resolve(ledger.capabilityToken),
              capability.layerID == claim.layerID,
              capability.dependencyOwnership == claim.dependencyOwnership,
              ledger.claimConsumed,
              ledger.phase == .allocationCommitted,
              ledger.commandBuffer === commandBuffer,
              commandBuffer.status == .notEnqueued,
              dependenciesMatch(
                  prepared: ledger.preparedDependencyEffect,
                  preparedEffects: ledger.preparedDependencyEffects,
                  preparedUnavailability:
                    ledger.preparedDependencyUnavailability,
                  ready: dependencyEffect,
                  readyEffects: dependencyEffects,
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
                dependencyEffects: dependencyEffects,
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
        } else if case let .externalAggregate(aggregate) = claim.dependencyOwnership,
                  !aggregate.providerLayerIDs.isEmpty {
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
                finalContent: ledger.prepared.finalResource.publication.candidate.content,
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
        dependencyEffects: [SceneDependencyEffectInput] = [],
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
            preparedEffects: ledger.preparedDependencyEffects,
            preparedUnavailability: ledger.preparedDependencyUnavailability,
            ready: dependencyEffect,
            readyEffects: dependencyEffects,
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
                      (
                        binding.slot.slotIndex == 3
                            || (binding.slot.slotIndex == 1
                                && binding.requiresResolvedMaterialProgram)
                      ),
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
            case .geometryLayer:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 1,
                      binding.blendMode == 0,
                      binding.requiresResolvedMaterialProgram else {
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
        case .externalAggregate:
            // Aggregate execution is intentionally fail-closed until the
            // submission ledger carries the complete ordered input vector.
            return false
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
        preparedEffects: [SceneDependencyEffectInput],
        preparedUnavailability:
            Bridge.FrameInputs.DependencyUnavailability?,
        ready: SceneDependencyEffectInput?,
        readyEffects: [SceneDependencyEffectInput],
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        if case let .externalAggregate(aggregate) = ownership {
            // Aggregate owners never use the legacy singular field or an
            // unavailability marker. Both vectors must match the exact
            // authored consumer/provider/slot/variant/blend order in the
            // current frame epoch and preserve physical texture identity.
            guard prepared == nil,
                  ready == nil,
                  preparedUnavailability == nil,
                  let frameEpoch = frame?.textureRegistrySnapshot.frameEpoch,
                  aggregateDependencyEffectsMatch(
                      preparedEffects,
                      aggregate: aggregate,
                      frameEpoch: frameEpoch
                  ),
                  aggregateDependencyEffectsMatch(
                      readyEffects,
                      aggregate: aggregate,
                      frameEpoch: frameEpoch
                  ) else {
                return false
            }
            return zip(preparedEffects, readyEffects).allSatisfy {
                $0.consumerLayerID == $1.consumerLayerID
                    && $0.providerLayerID == $1.providerLayerID
                    && $0.variant == $1.variant
                    && $0.slot == $1.slot
                    && $0.blendMode == $1.blendMode
                    && $0.frameEpoch == $1.frameEpoch
                    && $0.content == $1.content
                    && $0.texture === $1.texture
            }
        }
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
            && prepared.content == ready.content
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

    /// Checks one aggregate vector without reducing it to a provider/slot
    /// set. The order and every identity-bearing field are part of the frame
    /// contract; texture validation also rejects cross-provider aliasing that
    /// could make two authored inputs observe one physical target.
    private func aggregateDependencyEffectsMatch(
        _ effects: [SceneDependencyEffectInput],
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        frameEpoch: UInt64
    ) -> Bool {
        guard frameEpoch > 0,
              aggregate.hasStrictBindingVector,
              effects.count == aggregate.bindings.count else {
            return false
        }
        var texturesByProvider: [Int: MTLTexture] = [:]
        var textureIdentities = Set<ObjectIdentifier>()
        for (effect, binding) in zip(effects, aggregate.bindings) {
            guard effect.consumerLayerID == aggregate.consumerLayerID,
                  effect.consumerLayerID == binding.consumerLayerID,
                  effect.providerLayerID == binding.providerLayerID,
                  effect.variant == .primary,
                  effect.slot == binding.slot,
                  effect.blendMode == binding.blendMode,
                  effect.frameEpoch == frameEpoch,
                  isValidAggregateDependencyTexture(effect.texture) else {
                return false
            }
            if let existing = texturesByProvider[effect.providerLayerID] {
                guard existing === effect.texture else { return false }
            } else {
                texturesByProvider[effect.providerLayerID] = effect.texture
                guard textureIdentities.insert(
                    ObjectIdentifier(effect.texture)
                ).inserted else {
                    return false
                }
            }
        }
        return true
    }

    private func isValidAggregateDependencyTexture(
        _ texture: MTLTexture
    ) -> Bool {
        texture.width > 0
            && texture.height > 0
            && texture.textureType == .type2D
            && texture.sampleCount == 1
            && texture.mipmapLevelCount == 1
            && texture.usage.contains(.renderTarget)
            && texture.usage.contains(.shaderRead)
    }
}
