import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    func prepareGraph(
        _ context: PreparationContext,
        dependencyEffects: [SceneDependencyEffectInput],
        executor: SceneResolvedMaterialGraphExecutor,
        frame: SceneResolvedMaterialFrameSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> Result<SceneResolvedMaterialGraphExecutor.PreparedGraph,
        SceneResolvedMaterialGraphExecutor.Failure> {
        let request = context.request
        return executor.prepare(
            token: request.claim.token,
            leases: context.targets.leases,
            historyRehydrateCopiesByEffect: context.targets.historyRehydrateCopiesByEffect,
            frame: frame,
            sceneBackgroundResource: request.sceneBackgroundResource,
            sourceTexture: request.sourceTexture,
            sourceUniforms: request.sourceUniforms,
            sourcePipeline: request.sourcePipeline,
            framebufferSourceMaterial: request.framebufferSourceMaterial,
            sourceLighting: request.sourceLighting,
            terminalReplayTarget: request.terminalReplayTarget,
            terminalReplayBlendMode: request.terminalReplayBlendMode,
            terminalReplayIsOptional: request.terminalReplayIsOptional,
            pool: context.pool,
            frameInputs: request.frameInputs.withDependencyEffects(dependencyEffects),
            commandBuffer: commandBuffer,
            previousStates: context.previousTails.mapValues(\.state),
            previousGraphResources: context.previousTails.mapValues(\.persistentResources),
            materialFunctionInvocations: request.materialFunctionInvocations,
            effectGeneration: effectGeneration, resetGeneration: resetGeneration,
            executionTrace: context.executionTrace
        )
    }

    func dependencyEffectsReservationMatches(
        _ effects: [SceneDependencyEffectInput],
        ownership: SceneResolvedMaterialDependencyOwnership,
        frameEpoch: UInt64
    ) -> Bool {
        guard case let .externalAggregate(aggregate) = ownership else {
            return false
        }
        guard frameEpoch > 0 else { return false }
        var inputs = effects.makeIterator()
        var input = inputs.next()
        for binding in aggregate.bindings {
            guard let current = input else { return true }
            guard current.slot == binding.slot else { continue }
            guard current.consumerLayerID == binding.consumerLayerID,
                  current.providerLayerID == binding.providerLayerID,
                  current.variant == .primary,
                  current.blendMode == binding.blendMode,
                  current.frameEpoch == frameEpoch else { return false }
            input = inputs.next()
        }
        return input == nil
    }

    func executeClaimed(
        claim: Bridge.ClaimedExecution,
        dependencyEffects: [SceneDependencyEffectInput] = [],
        sceneBackgroundTexture: MTLTexture? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> Bridge.ExecutionResult {
        var emission = Emission()
        lock.lock()
        switch admitClaimedExecutionLocked(
            claim: claim,
            dependencyEffects: dependencyEffects,
            sceneBackgroundTexture: sceneBackgroundTexture,
            commandBuffer: commandBuffer
        ) {
        case let .rejected(detail):
            let reason = commandBuffer.status == .notEnqueued
                ? "prepared-frame-consumption-rejected"
                : "transaction-armed-after-submit"
            emission = claimedFailureLocked(reason: reason)
#if DEBUG
            emission.diagnostics.append(
                "\(reason) layer=\(claim.layerID) detail=\(detail)"
            )
#endif

            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        case let .accepted(admittedLedger, identity, executor):
            var ledger = admittedLedger
            if dependencyEffects.count < ledger.preparedDependencyEffects.count {
                guard let frame,
                      let updated = refreshPreparedDependencySuffixLocked(
                        from: identity, dependencyEffects: dependencyEffects,
                        executor: executor, frame: frame, commandBuffer: commandBuffer
                      ) else {
                    emission = claimedFailureLocked(reason: "prepared-frame-consumption-rejected")
#if DEBUG
                    emission.diagnostics.append("late-dependency-preparation-rejected layer=\(claim.layerID)")
#endif
                    lock.unlock()
                    emit(emission)
                    return .failed(reasonCode: "prepared-frame-consumption-rejected")
                }
                ledger = updated
            }
#if DEBUG
            let encodeResult = SceneGPUStageTimestampHook.graphScope(commandBuffer,
                layerID: claim.layerID, ledgerID: identity) {
                executor.encodeResult(ledger.prepared, commandBuffer: commandBuffer)
            }
#else
            let encodeResult = executor.encodeResult(
                ledger.prepared,
                commandBuffer: commandBuffer
            )
#endif
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
            ledger.preparationContext = nil
            activeByID[identity] = ledger
            frameEncoded += 1
            let effectFailures: [Bridge.ExecutionTicket.EffectFailure] =
                ledger.prepared.stages.compactMap { stage in
                    guard let reasonCode = stage.effectLocalFailureReasonCode else { return nil }
                    return .init(layerID: stage.effect.layerID,
                        effectIndex: stage.effect.effectIndex,
                        descriptorID: stage.effect.descriptorID, reasonCode: reasonCode)
                }
            let result = executionOutput(for: ledger, effectFailures: effectFailures)
            lock.unlock()
            return result
        }
    }

    func outputForComposite(
        layerID: Int,
        commandBuffer: MTLCommandBuffer
    ) -> Bridge.ExecutionResult? {
        lock.lock()
        defer { lock.unlock() }
        guard terminalFailureReason == nil, frameIsActive,
              framePreparationComplete, !frameRequiresDrop,
              frameFailure == nil else {
            return .failed(reasonCode: "composite-output-frame-unavailable")
        }
        guard let identity = preparedLedgerByLayerID[layerID] else { return nil }
        guard let ledger = activeByID[identity], ledger.layerID == layerID,
              ledger.epoch == executionEpoch,
              ledger.commandBuffer === commandBuffer,
              commandBuffer.status == .notEnqueued else {
            return .failed(reasonCode: "composite-output-identity-mismatch")
        }
        guard !ledger.compositorConsumed else {
            return .failed(reasonCode: "final-composite-ticket-reused")
        }
        guard ledger.localOutputFailureReasonCode == nil else { return nil }
        guard ledger.phase == .outputConsumed, ledger.ticketConsumed,
              ledger.prepared.terminalMaterialReplay == nil else {
            return .failed(reasonCode: "composite-output-not-ready")
        }
        guard case let .color(.resolved(representation)) =
                ledger.prepared.finalResource.publication.candidate.content,
              representation != .independentAlphaSignal else { return nil }
        return executionOutput(for: ledger, effectFailures: [])
    }

    private func executionOutput(
        for ledger: PreparedLedger,
        effectFailures: [Bridge.ExecutionTicket.EffectFailure]
    ) -> Bridge.ExecutionResult {
        .encoded(
            texture: ledger.prepared.finalTexture,
            ticket: .init(
                identity: ledger.identity,
                epoch: ledger.epoch,
                finalTextureIdentity: ObjectIdentifier(ledger.prepared.finalTexture),
                finalContent: ledger.prepared.finalResource.publication.candidate.content,
                consumesExternalPrimaryDependency: !ledger.preparedDependencyEffects.isEmpty,
                effectFailures: effectFailures,
                hasTerminalMaterialReplay: ledger.prepared.terminalMaterialReplay != nil,
                terminalReplayBlendMode:
                    ledger.prepared.terminalMaterialReplay?.role.terminalReplayBlendMode ?? 0,
                terminalReadsCurrentAttachment:
                    ledger.prepared.terminalMaterialReplay?.role.readsCurrentAttachment == true
            )
        )
    }

    /// The single admission ladder for a claimed execution.
    ///
    /// Acceptance carries the ledger and identity the caller consumes; rejection
    /// carries the reason that reaches the log, so the decision and its explanation
    /// cannot disagree. The earlier split ladder omitted the capability clauses here
    /// and could report a reason that did not match the clause that actually failed.
    private enum ClaimedExecutionAdmission {
        case accepted(
            ledger: PreparedLedger,
            identity: UInt64,
            executor: SceneResolvedMaterialGraphExecutor
        )
        case rejected(detail: String)
    }

    private func admitClaimedExecutionLocked(
        claim: Bridge.ClaimedExecution,
        dependencyEffects: [SceneDependencyEffectInput],
        sceneBackgroundTexture: MTLTexture?,
        commandBuffer: MTLCommandBuffer
    ) -> ClaimedExecutionAdmission {
        guard terminalFailureReason == nil else { return .rejected(detail: "runtime-terminal") }
        guard frameIsActive else { return .rejected(detail: "frame-inactive") }
        guard framePreparationComplete else { return .rejected(detail: "frame-not-prepared") }
        guard !frameRequiresDrop else { return .rejected(detail: "frame-drop-required") }
        guard frameFailure == nil else { return .rejected(detail: "frame-failure-recorded") }
        guard let executor else { return .rejected(detail: "executor-unavailable") }
        guard let frame else { return .rejected(detail: "frame-snapshot-unavailable") }
        guard let identity = preparedLedgerByLayerID[claim.layerID]
        else { return .rejected(detail: "prepared-ledger-missing") }
        guard let index = activeTransactions.firstIndex(of: identity)
        else { return .rejected(detail: "prepared-order-missing") }
        guard let ledger = activeByID[identity]
        else { return .rejected(detail: "prepared-ledger-unavailable") }
        guard ledger.layerID == claim.layerID else { return .rejected(detail: "layer-mismatch") }
        guard ledger.capabilityToken == claim.token
        else { return .rejected(detail: "capability-token-mismatch") }
        guard let capability = capabilities.resolve(ledger.capabilityToken)
        else { return .rejected(detail: "capability-unresolved") }
        guard capability.layerID == claim.layerID
        else { return .rejected(detail: "capability-layer-mismatch") }
        guard ledger.claimConsumed else { return .rejected(detail: "claim-not-consumed") }
        guard ledger.phase == .allocationCommitted
        else { return .rejected(detail: "ledger-phase-\(ledger.phase.rawValue)") }
        guard ledger.commandBuffer === commandBuffer
        else { return .rejected(detail: "command-buffer-mismatch") }
        guard commandBuffer.status == .notEnqueued
        else { return .rejected(detail: "command-buffer-status-\(commandBuffer.status.rawValue)") }
        guard dependenciesMatch(
            preparedEffects: ledger.preparedDependencyEffects,
            preparedUnavailability: ledger.preparedDependencyUnavailability,
            readyEffects: dependencyEffects
        ) else { return .rejected(detail: "dependency-input-mismatch") }
        guard sceneBackgroundTextureMatches(
            prepared: ledger.prepared.sceneBackgroundResource,
            ready: sceneBackgroundTexture,
            requirement: claim.sceneBackgroundRequirement,
            frameEpoch: frame.textureRegistrySnapshot.frameEpoch
        ) else { return .rejected(detail: "scene-background-mismatch") }
        guard activeTransactions[..<index].allSatisfy({
            activeByID[$0]?.phase == .outputConsumed
        }) else { return .rejected(detail: "predecessor-output-not-consumed") }
        guard activeTransactions[activeTransactions.index(after: index)...]
            .allSatisfy({ activeByID[$0]?.phase == .allocationCommitted })
        else { return .rejected(detail: "successor-phase-mismatch") }
        return .accepted(ledger: ledger, identity: identity, executor: executor)
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
            if let unavailability {
                return input == nil
                    && unavailability == .providerSourceUnavailable
            }
            guard let input,
                  let frameEpoch = frame?.textureRegistrySnapshot.frameEpoch,
                  frameEpoch > 0, input.frameEpoch == frameEpoch else { return false }
            return input.consumerLayerID == binding.consumerLayerID
                && input.providerLayerID == binding.providerLayerID
                && input.variant == .primary
                && input.slot == binding.slot
                && input.blendMode == binding.blendMode
        case .externalAggregate:
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
        preparedEffects: [SceneDependencyEffectInput],
        preparedUnavailability:
            Bridge.FrameInputs.DependencyUnavailability?,
        readyEffects: [SceneDependencyEffectInput]
    ) -> Bool {
        guard readyEffects.count <= preparedEffects.count else { return false }
        if preparedUnavailability != nil { return readyEffects.isEmpty }
        guard let frameEpoch = frame?.textureRegistrySnapshot.frameEpoch else { return false }
        var inputs = readyEffects.makeIterator()
        var input = inputs.next()
        for prepared in preparedEffects {
            guard let ready = input else { return true }
            guard prepared.slot == ready.slot else { continue }
            guard prepared.consumerLayerID == ready.consumerLayerID,
                  prepared.providerLayerID == ready.providerLayerID,
                  prepared.variant == ready.variant,
                  prepared.blendMode == ready.blendMode,
                  prepared.frameEpoch == frameEpoch,
                  ready.frameEpoch == frameEpoch,
                  prepared.content == ready.content,
                  prepared.texture === ready.texture else { return false }
            input = inputs.next()
        }
        return input == nil
    }

    private func reprepareDependenciesLocked(
        _ ledger: inout PreparedLedger,
        dependencyEffects: [SceneDependencyEffectInput],
        executor: SceneResolvedMaterialGraphExecutor,
        frame: SceneResolvedMaterialFrameSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let context = ledger.preparationContext, let commit = ledger.commit,
              case let .success(prepared) = prepareGraph(
                context, dependencyEffects: dependencyEffects,
                executor: executor, frame: frame, commandBuffer: commandBuffer
              ), let blueprint = candidateBlueprintLocked(
                for: prepared, startingAt: context.previousTails
              ), candidateIsCommitReadyLocked(
                targets: context.targets, prepared: prepared, blueprint: blueprint
              ) else { return false }
        for (effect, tokens) in prepared.historyTokensByEffect {
            guard historyPinMatches(commit.historyPinsByEffect[effect],
                effect: effect, tokens: tokens, generation: commit.submissionPin.generation)
            else { return false }
        }
        ledger.prepared = prepared
        ledger.preparedDependencyEffects = dependencyEffects
        ledger.blueprint = blueprint
        return true
    }

    private func refreshPreparedDependencySuffixLocked(
        from identity: UInt64,
        dependencyEffects: [SceneDependencyEffectInput],
        executor: SceneResolvedMaterialGraphExecutor,
        frame: SceneResolvedMaterialFrameSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> PreparedLedger? {
        guard let index = activeTransactions.firstIndex(of: identity),
              var first = activeByID[identity],
              reprepareDependenciesLocked(&first, dependencyEffects: dependencyEffects,
                executor: executor, frame: frame, commandBuffer: commandBuffer)
        else { return nil }
        activeByID[identity] = first
        var tails = scheduledTails
        for transactionID in activeTransactions[index...] {
            guard var ledger = activeByID[transactionID],
                  let commit = ledger.commit else { return nil }
            if transactionID != identity, let context = ledger.preparationContext {
                var contentChanged = false
                let effects = ledger.preparedDependencyEffects.map { input in
                    let binding: SceneDependencyRenderPlan.Binding?
                    switch context.request.claim.dependencyOwnership {
                    case let .externalPrimary(value): binding = value
                    case let .externalAggregate(aggregate):
                        binding = aggregate.bindings.first { $0.slot == input.slot }
                    case .none, .graphInternal: binding = nil
                    }
                    guard binding?.kind != .geometryLayer,
                          let providerID = preparedLedgerByLayerID[input.providerLayerID],
                          let provider = activeByID[providerID] else { return input }
                    let content = provider.prepared.finalResource.publication.candidate.content
                    guard content != input.content else { return input }
                    contentChanged = true
                    return input.withContent(content)
                }
                if contentChanged,
                   !reprepareDependenciesLocked(&ledger, dependencyEffects: effects,
                    executor: executor, frame: frame, commandBuffer: commandBuffer) {
                    return nil
                }
            }
            guard let blueprint = ledger.blueprint else { return nil }
            tails = committedCandidateTailsLocked(blueprint: blueprint,
                startingAt: tails, commit: commit, prepared: ledger.prepared)
            guard tailsAreValid(tails) else { return nil }
            ledger.candidateTails = tails
            activeByID[transactionID] = ledger
        }
        return activeByID[identity]
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
              ledger.preparedDependencyEffects.isEmpty else { return nil }
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
