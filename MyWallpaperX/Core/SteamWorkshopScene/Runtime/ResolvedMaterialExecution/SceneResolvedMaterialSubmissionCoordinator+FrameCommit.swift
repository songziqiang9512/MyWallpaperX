import Foundation
import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    struct PreparedFrameCandidate {
        let layerID: Int
        let capabilityToken:
            SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph
        let preparedDependencyEffect: SceneDependencyEffectInput?
        let commandBuffer: MTLCommandBuffer
        let committedBaseTails: [Graph.EffectKey: Tail]
        let blueprint: CandidateBlueprint
        let targets: ScenePreparedPersistentGraphTargets
    }

    func preparedEvidenceFitsLocked(
        _ preparedGraphs: [SceneResolvedMaterialGraphExecutor.PreparedGraph]
    ) -> Bool {
        var transitionCount = 0
        var nodeCount = 0
        for preparedGraph in preparedGraphs {
            let stages = preparedGraph.stages
            guard !stages.isEmpty,
                  stages.count <= Self.maximumTransitionsPerTransaction
            else { return false }
            let (nextTransitions, transitionOverflow) = transitionCount
                .addingReportingOverflow(stages.count)
            guard !transitionOverflow,
                  nextTransitions <= Self.maximumTransitionsPerSubmission else {
                return false
            }
            transitionCount = nextTransitions
            for value in stages {
                let (nextNodes, nodeOverflow) = nodeCount
                    .addingReportingOverflow(value.graph.nodes.count)
                guard !nodeOverflow,
                      nextNodes <= Self.maximumObservedNodesPerSubmission else {
                    return false
                }
                nodeCount = nextNodes
            }
        }
        return true
    }

    func framePreparationFailureLocked(
        _: [PreparedFrameCandidate],
        reason: String
    ) -> Emission {
        frameFailures += 1
        frameRequiresDrop = true
        framePreparationComplete = false
        preparedLedgerByLayerID.removeAll(keepingCapacity: true)
        pruneCommandBufferRecordsLocked()
        return .init(observations: [], diagnostics: [reason])
    }

    func candidateIsCommitReadyLocked(
        targets: ScenePreparedPersistentGraphTargets,
        prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph,
        blueprint: CandidateBlueprint
    ) -> Bool {
        let effects = Set(prepared.stages.map(\.effect))
        let generations = Set(prepared.stages.map {
            $0.transition.transaction.allocationGeneration
        })
        let discardedHistoryEffects = Set(prepared.stages.compactMap { stage in
            stage.discardedPersistentTargetState ? stage.effect : nil
        })
        guard !effects.isEmpty,
              effects.count == prepared.stages.count,
              generations.count == 1,
              let generation = generations.first,
              targets.leases.count == prepared.stages.count,
              targets.leases.allSatisfy({ $0.generation == generation }),
              Set(blueprint.states.keys) == effects,
              Set(blueprint.resources.keys) == effects,
              Set(blueprint.mappingGenerations.keys) == effects,
              Set(prepared.historyTokensByEffect.keys).isSubset(of: effects),
              discardedHistoryEffects.isDisjoint(
                  with: prepared.historyTokensByEffect.keys
              ),
              prepared.historyTokensByEffect.values.allSatisfy({ !$0.isEmpty })
        else { return false }
        return prepared.stages.allSatisfy { value in
            guard let state = blueprint.states[value.effect],
                  let resources = blueprint.resources[value.effect],
                  state.allocationGeneration == generation else { return false }
            let identities = state.historyClosureIdentities
            let tokens = Set(state.logicalMapping.compactMap { identity, version in
                identities.contains(identity) ? version.token : nil
            })
            guard Set(resources.keys) == identities,
                  tokens == (prepared.historyTokensByEffect[
                      value.effect,
                      default: []
                  ])
            else { return false }
            guard value.discardedPersistentTargetState else { return true }
            return value.effectLocalFailureReasonCode != nil
                && !value.graph.renderTargets.isEmpty
                && value.transition.transaction.intents.isEmpty
                && value.transition.transaction.mappingBefore.isEmpty
                && value.transition.transaction.mappingAfter.isEmpty
                && value.transition.nextState.historyClosureIdentities.isEmpty
                && value.frameResources.isEmpty
                && value.persistentResources.isEmpty
        }
    }

    func provisionalCandidateTailsLocked(
        blueprint: CandidateBlueprint,
        startingAt base: [Graph.EffectKey: Tail],
        prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph
    ) -> [Graph.EffectKey: Tail]? {
        var tails = base
        for value in prepared.stages {
            guard let state = blueprint.states[value.effect],
                  let resources = blueprint.resources[value.effect],
                  let mapping = blueprint.mappingGenerations[value.effect]
            else { return nil }
            guard !state.historyClosureIdentities.isEmpty else {
                tails.removeValue(forKey: value.effect)
                continue
            }
            tails[value.effect] = .init(
                state: state,
                persistentResources: resources,
                historyPin: nil,
                mappingGeneration: mapping
            )
        }
        return tails
    }

    func committedCandidateTailsLocked(
        blueprint: CandidateBlueprint,
        startingAt base: [Graph.EffectKey: Tail],
        commit: Commit,
        prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph
    ) -> [Graph.EffectKey: Tail] {
        var tails = base
        for value in prepared.stages {
            guard let state = blueprint.states[value.effect],
                  let resources = blueprint.resources[value.effect],
                  let mapping = blueprint.mappingGenerations[value.effect]
            else { continue }
            guard !state.historyClosureIdentities.isEmpty else {
                tails.removeValue(forKey: value.effect)
                continue
            }
            tails[value.effect] = .init(
                state: state,
                persistentResources: resources,
                historyPin: commit.historyPinsByEffect[value.effect],
                mappingGeneration: mapping
            )
        }
        return tails
    }

    /// Installed before the first allocation commit or encoded command. Metal
    /// forbids adding completion handlers after command-buffer `commit()`.
    func observeCommandBufferLocked(_ commandBuffer: MTLCommandBuffer) -> Bool {
        guard commandBuffer.status == .notEnqueued else { return false }
        let identity = ObjectIdentifier(commandBuffer)
        if let current = commandBufferRecords[identity] {
            return current.buffer === commandBuffer
        }
        commandBufferRecords[identity] = .init(
            buffer: commandBuffer,
            terminalStatus: nil
        )
        commandBuffer.addCompletedHandler { [self] buffer in
            let status: SceneGraphExecutionGPUCompletionStatus =
                buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            Task { @MainActor [self] in
                self.completeCommandBuffer(identity: identity, status: status)
            }
        }
        return true
    }

    /// All ledgers in one authored frame are required to share one buffer. The
    /// aggregate fallback keeps every candidate pinned if corrupted state ever
    /// exposes more than one in-flight buffer. A `.notEnqueued` buffer is owned
    /// by the current synchronous render call and is abandoned when sealing
    /// fails; only an already-submitted buffer may defer terminal release.
    func failActiveFrameRespectingGPUOwnershipLocked(
        reason: String
    ) -> Emission {
        frameRequiresDrop = true
        var emission = Emission()
        let identities = activeTransactions
        let bufferIdentities = Set(identities.compactMap {
            activeByID[$0].map { ObjectIdentifier($0.commandBuffer) }
        })
        var pendingBuffers = Set<ObjectIdentifier>()
        for identity in bufferIdentities {
            guard let record = commandBufferRecords[identity] else {
                let buffer = identities.compactMap { activeByID[$0] }
                    .first { ObjectIdentifier($0.commandBuffer) == identity }?
                    .commandBuffer
                if let buffer, buffer.status != .notEnqueued,
                   buffer.status != .completed, buffer.status != .error {
                    terminalFailureReason = "command-buffer-observer-missing"
                    pendingBuffers.insert(identity)
                }
                continue
            }
            if record.terminalStatus == nil,
               record.buffer.status != .notEnqueued,
               record.buffer.status != .completed,
               record.buffer.status != .error {
                pendingBuffers.insert(identity)
            }
        }

        if pendingBuffers.isEmpty {
            for identity in identities {
                let bufferID = activeByID[identity].map {
                    ObjectIdentifier($0.commandBuffer)
                }
                let gpu = bufferID.flatMap {
                    commandBufferRecords[$0]?.terminalStatus
                } == .failed ? SceneGraphExecutionGPUCompletionStatus.failed : nil
                emission.append(terminalizeLedgerLocked(
                    identity,
                    as: .failed(reasonCode: reason, gpu: gpu)
                ))
            }
        } else {
            let submissionID: UInt64
            if nextSubmissionID < UInt64.max {
                nextSubmissionID += 1
                submissionID = nextSubmissionID
            } else {
                terminalFailureReason = "submission-id-overflow"
                emission.diagnostics.append("submission-id-overflow")
                submissionID = .max
            }
            for identity in identities {
                activeByID[identity]?.phase = .sealed
                activeByID[identity]?.submissionID = submissionID
            }
            pendingSubmissions.append(.init(
                identity: submissionID,
                ledgerIDs: identities,
                commandBufferIdentities: pendingBuffers,
                finalTails: committedTails,
                successObservationsByLedger: [:],
                gpuStatus: nil,
                cancellationReason: reason,
                retiredHistoryPins: []
            ))
        }

        if frameSealed {
            for index in pendingSubmissions.indices
            where pendingSubmissions[index].cancellationReason == nil {
                pendingSubmissions[index].cancellationReason = reason
            }
        }
        activeTransactions.removeAll(keepingCapacity: true)
        preparedLedgerByLayerID.removeAll(keepingCapacity: true)
        framePreparationComplete = false
        restoreScheduledTailsLocked()
        invalidateEpochLocked()
        pruneCommandBufferRecordsLocked()
        emission.diagnostics.append(reason)
        return emission
    }

    func markComposite(
        _ ticket: Bridge.ExecutionTicket,
        texture: MTLTexture,
        consumed: Bool
    ) -> Bridge.CompositeOutcome {
        markFinalOutput(
            ticket,
            texture: texture,
            consumed: consumed,
            compositor: true,
            reasonPrefix: "final-composite"
        )
    }

    func markNamedPublication(
        _ ticket: Bridge.ExecutionTicket,
        texture: MTLTexture,
        published: Bool
    ) -> Bridge.CompositeOutcome {
        markFinalOutput(
            ticket,
            texture: texture,
            consumed: published,
            compositor: false,
            reasonPrefix: "named-publication"
        )
    }

    private func markFinalOutput(
        _ ticket: Bridge.ExecutionTicket,
        texture: MTLTexture,
        consumed: Bool,
        compositor: Bool,
        reasonPrefix: String
    ) -> Bridge.CompositeOutcome {
        var emission = Emission()
        lock.lock()
        guard ticket.epoch == executionEpoch,
              var ledger = activeByID[ticket.identity],
              ledger.epoch == ticket.epoch,
              activeTransactions.contains(ticket.identity) else {
            let reason = "\(reasonPrefix)-ticket-missing"
            if frameIsActive {
                frameFailures += 1
                emission = failActiveFrameLocked(reason: reason)
            }
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        guard !ledger.ticketConsumed else {
            let reason = "\(reasonPrefix)-ticket-reused"
            frameFailures += 1
            emission = failActiveFrameLocked(reason: reason)
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        ledger.ticketConsumed = true
        activeByID[ticket.identity] = ledger
        guard ticket.finalTextureIdentity == ObjectIdentifier(texture),
              texture === ledger.prepared.finalTexture,
              ledger.phase == .encoded,
              ledger.candidateTails != nil else {
            let reason = "\(reasonPrefix)-texture-mismatch"
            frameFailures += 1
            emission = failActiveFrameLocked(reason: reason)
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        guard consumed, ledger.commandBuffer.status == .notEnqueued else {
            let reason = consumed
                ? "transaction-armed-after-submit"
                : "\(reasonPrefix)-failed"
            frameFailures += 1
            emission = failActiveFrameLocked(reason: reason)
            lock.unlock()
            emit(emission)
            return .failed(reasonCode: reason)
        }
        ledger.outputConsumed = true
        ledger.compositorConsumed = compositor
        ledger.phase = .outputConsumed
        activeByID[ticket.identity] = ledger
        scheduledTails = ledger.candidateTails ?? scheduledTails
        lock.unlock()
        return .consumed
    }

    @discardableResult
    func sealFrame(on commandBuffer: MTLCommandBuffer) -> Bool {
        var emission = Emission()
        lock.lock()
        guard frameIsActive, terminalFailureReason == nil,
              frameFailure == nil, frameFailures == 0,
              !frameRequiresDrop else {
            if frameIsActive, !activeTransactions.isEmpty {
                emission = failActiveFrameLocked(
                    reason: "frame-invalidated-before-seal"
                )
            }
            lock.unlock()
            emit(emission)
            return false
        }
        guard submissionQueueAcceptsFrameLocked(),
              commandBuffer.status == .notEnqueued else {
            frameFailures += 1
            emission = failActiveFrameLocked(
                reason: "frame-seal-invariant-failed"
            )
            lock.unlock()
            emit(emission)
            return false
        }
        guard !activeTransactions.isEmpty else {
            frameSealed = true
            lock.unlock()
            return true
        }
        let commandBufferIdentity = ObjectIdentifier(commandBuffer)
        guard let observedBuffer = commandBufferRecords[commandBufferIdentity],
              observedBuffer.buffer === commandBuffer,
              activeTransactions.allSatisfy({ identity in
            guard let ledger = activeByID[identity] else { return false }
            return ledger.phase == .outputConsumed
                && ledger.commandBuffer === commandBuffer
        }), tailsAreValid(scheduledTails),
            let observations = successObservationsLocked(
                ledgerIDs: activeTransactions
            ) else {
            frameFailures += 1
            emission = failActiveFrameLocked(
                reason: "frame-success-blueprint-rejected"
            )
            lock.unlock()
            emit(emission)
            return false
        }
        guard nextSubmissionID < UInt64.max else {
            frameFailures += 1
            terminalFailureReason = "submission-id-overflow"
            emission = failActiveFrameLocked(reason: "submission-id-overflow")
            lock.unlock()
            emit(emission)
            return false
        }
        nextSubmissionID += 1
        let submissionID = nextSubmissionID
        let ledgerIDs = activeTransactions
        for identity in ledgerIDs {
            activeByID[identity]?.phase = .sealed
            activeByID[identity]?.submissionID = submissionID
        }
        pendingSubmissions.append(.init(
            identity: submissionID,
            ledgerIDs: ledgerIDs,
            commandBufferIdentities: [commandBufferIdentity],
            finalTails: scheduledTails,
            successObservationsByLedger: observations,
            gpuStatus: nil,
            cancellationReason: nil,
            retiredHistoryPins: []
        ))
        activeTransactions.removeAll(keepingCapacity: true)
        frameSealed = true
        lock.unlock()
        return true
    }
}
