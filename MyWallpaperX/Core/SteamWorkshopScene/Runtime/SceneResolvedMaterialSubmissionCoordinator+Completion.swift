import Foundation
import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    func deferPreparedFrame() -> Bool {
        var emission = Emission()
        lock.lock()
        guard frameIsActive, !frameSealed, !frameRequiresDrop,
              frameFailure == nil, frameFailures == 0,
              activeTransactions.allSatisfy({ identity in
                  guard let ledger = activeByID[identity] else { return false }
                  return ledger.phase == .allocationCommitted
                      && !ledger.claimConsumed
                      && ledger.commandBuffer.status == .notEnqueued
              }) else {
            lock.unlock()
            return false
        }
        for identity in activeTransactions.reversed() {
            emission.append(terminalizeLedgerLocked(identity, as: .cancelled))
        }
        activeTransactions.removeAll(keepingCapacity: true)
        preparedLedgerByLayerID.removeAll(keepingCapacity: true)
        restoreScheduledTailsLocked()
        pruneCommandBufferRecordsLocked()
        frameRequiresDrop = true
        framePreparationComplete = false
        frameDeferred += 1
        lock.unlock()
        emit(emission)
        return true
    }

    enum LedgerTerminal {
        case succeeded(
            observations: [SceneGraphExecutionObservation],
            retainedHistoryPins: Set<ObjectIdentifier>
        )
        case failed(
            reasonCode: String,
            gpu: SceneGraphExecutionGPUCompletionStatus?
        )
        case cancelled
    }

    func completeCommandBuffer(
        identity: ObjectIdentifier,
        status: SceneGraphExecutionGPUCompletionStatus
    ) {
        lock.lock()
        guard var record = commandBufferRecords[identity] else {
            lock.unlock()
            return
        }
        if let terminal = record.terminalStatus {
            guard terminal == status else {
                terminalFailureReason = "command-buffer-terminal-status-conflict"
                lock.unlock()
                return
            }
        } else {
            record.terminalStatus = status
            commandBufferRecords[identity] = record
        }
        for index in pendingSubmissions.indices
        where pendingSubmissions[index].commandBufferIdentities.contains(identity) {
            let statuses = pendingSubmissions[index].commandBufferIdentities
                .compactMap { commandBufferRecords[$0]?.terminalStatus }
            if statuses.count
                == pendingSubmissions[index].commandBufferIdentities.count {
                pendingSubmissions[index].gpuStatus = statuses.allSatisfy {
                    $0 == .completed
                } ? .completed : .failed
            }
        }
        let emission = drainCompletedLocked()
        pruneCommandBufferRecordsLocked()
        lock.unlock()
        emit(emission)
    }

    func pruneCommandBufferRecordsLocked() {
        let active = Set(activeByID.values.map {
            ObjectIdentifier($0.commandBuffer)
        })
        let pending = pendingSubmissions.reduce(into: Set<ObjectIdentifier>()) {
            $0.formUnion($1.commandBufferIdentities)
        }
        let retained = active.union(pending)
        commandBufferRecords = commandBufferRecords.filter {
            retained.contains($0.key)
        }
    }

    func drainCompletedLocked() -> Emission {
        var emission = Emission()
        while let head = pendingSubmissions.first {
            if head.cancellationReason != nil {
                guard let reason = head.cancellationReason,
                      let status = head.gpuStatus else { break }
                pendingSubmissions.removeFirst()
                let terminal = cancellationTerminal(
                    reasonCode: reason,
                    gpuStatus: status,
                    submission: head
                )
                for identity in head.ledgerIDs {
                    emission.append(terminalizeLedgerLocked(
                        identity,
                        as: terminal
                    ))
                }
                releasePins(head.retiredHistoryPins)
                continue
            }
            guard let status = head.gpuStatus else { break }
            switch status {
            case .completed:
                guard submissionCanCommitLocked(head) else {
                    emission.append(failScheduledLocked(
                        headReason: "gpu-success-ledger-invariant-rejected"
                    ))
                    continue
                }
                let retained = historyPinIdentities(in: head.finalTails.values)
                let priorPins = committedTails.values.compactMap(\.historyPin)

                // State and history ownership become visible together while
                // the serial lock is held. No fallible work follows promotion.
                committedTails = head.finalTails
                for identity in head.ledgerIDs {
                    let observations = head.successObservationsByLedger[identity] ?? []
                    emission.append(terminalizeLedgerLocked(
                        identity,
                        as: .succeeded(
                            observations: observations,
                            retainedHistoryPins: retained
                        )
                    ))
                }
                releasePins(priorPins, retaining: retained)
                pendingSubmissions.removeFirst()
            case .failed:
                emission.append(failScheduledLocked(
                    headReason: "gpu-command-buffer-failed"
                ))
                continue
            }
        }
        if pendingSubmissions.isEmpty && activeTransactions.isEmpty {
            scheduledTails = committedTails
        }
        return emission
    }

    func cancellationTerminal(
        reasonCode: String,
        gpuStatus: SceneGraphExecutionGPUCompletionStatus,
        submission: PendingSubmission
    ) -> LedgerTerminal {
        guard gpuStatus == .completed else {
            return .failed(reasonCode: reasonCode, gpu: .failed)
        }
        // Only these host lifecycle exits discard a completed candidate silently.
        // Reprepare, device, executor, and unknown cancellations remain failures.
        switch reasonCode {
        case SceneGraphExecutionResetReason.surfaceStop.rawValue,
             SceneGraphExecutionResetReason.sceneSwitch.rawValue:
            return submissionCanCancelSilentlyLocked(submission)
                ? .cancelled
                : .failed(
                    reasonCode: "lifecycle-cancellation-ledger-invariant-rejected",
                    gpu: nil
                )
        default:
            return .failed(reasonCode: reasonCode, gpu: nil)
        }
    }

    func submissionCanCancelSilentlyLocked(
        _ submission: PendingSubmission
    ) -> Bool {
        let identities = Set(submission.ledgerIDs)
        guard !identities.isEmpty,
              identities.count == submission.ledgerIDs.count,
              !submission.commandBufferIdentities.isEmpty else { return false }
        return submissionCanCommitLocked(submission)
    }

    func submissionCanCommitLocked(_ submission: PendingSubmission) -> Bool {
        guard !submission.ledgerIDs.isEmpty,
              Set(submission.successObservationsByLedger.keys)
                == Set(submission.ledgerIDs),
              tailsAreValid(submission.finalTails) else { return false }
        return submission.ledgerIDs.allSatisfy { identity in
            guard let ledger = activeByID[identity] else { return false }
            return ledger.phase == .sealed
                && ledger.submissionID == submission.identity
                && ledger.ticketConsumed
                && ledger.compositorConsumed
        }
    }

    func failScheduledLocked(
        headReason: String
    ) -> Emission {
        var emission = Emission()
        guard !pendingSubmissions.isEmpty else {
            emission.diagnostics.append(headReason)
            return emission
        }
        pendingSubmissions[0].cancellationReason = headReason
        emission.diagnostics.append(headReason)
        return emission
    }

    /// The only removal point for `activeByID`. Repeated terminal events are
    /// harmless and cannot release pins or publish observations twice.
    func terminalizeLedgerLocked(
        _ identity: UInt64,
        as terminal: LedgerTerminal
    ) -> Emission {
        guard let ledger = activeByID.removeValue(forKey: identity) else {
            return .init()
        }
        activeTransactions.removeAll { $0 == identity }
        var emission = Emission()
        switch terminal {
        case let .succeeded(observations, retained):
            if let commit = ledger.commit {
                commit.submissionPin.release()
                releasePins(
                    commit.historyPinsByEffect.values,
                    retaining: retained
                )
            }
            emission.observations = observations
        case let .failed(reasonCode, gpu):
            emission.append(failureObservationsLocked(
                for: ledger,
                reasonCode: reasonCode,
                gpu: gpu
            ))
            ledger.commit?.releaseAll()
        case .cancelled:
            ledger.commit?.releaseAll()
        }
        return emission
    }

    func successObservationsLocked(
        ledgerIDs: [UInt64]
    ) -> [UInt64: [SceneGraphExecutionObservation]]? {
        var result: [UInt64: [SceneGraphExecutionObservation]] = [:]
        for identity in ledgerIDs {
            guard let ledger = activeByID[identity],
                  let blueprint = ledger.blueprint,
                  ledger.phase == .composited else { return nil }
            var observations: [SceneGraphExecutionObservation] = []
            for value in ledger.prepared.stages {
                guard let mappingGeneration = blueprint
                    .mappingGenerations[value.effect] else { return nil }
                do {
                    observations.append(try
                        SceneResolvedMaterialGraphObservationBuilder.make(
                            value,
                            frameIndex: ledger.frameIndex,
                            transactionID: ledger.identity,
                            executionEpoch: ledger.epoch,
                            mappingGeneration: mappingGeneration,
                            resetReason: blueprint.resetReasons[value.effect],
                            terminalEffect: ledger.prepared.stages[
                                ledger.prepared.stages.count - 1
                            ].effect,
                            outcome: .succeeded,
                            gpu: .completed
                        )
                    )
                } catch { return nil }
            }
            result[identity] = observations
        }
        return result
    }

    func failureObservationsLocked(
        for ledger: PreparedLedger,
        reasonCode: String,
        gpu: SceneGraphExecutionGPUCompletionStatus?
    ) -> Emission {
        var emission = Emission()
        for value in ledger.prepared.stages {
            let base = ledger.committedBaseTails[value.effect]
            do {
                emission.observations.append(try
                    SceneResolvedMaterialGraphObservationBuilder.make(
                        value,
                        frameIndex: ledger.frameIndex,
                        transactionID: ledger.identity,
                        executionEpoch: ledger.epoch,
                        mappingGeneration: base?.mappingGeneration ?? 0,
                        resetReason: nil,
                        committedBaseState: base?.state,
                        terminalEffect: ledger.prepared.stages[
                            ledger.prepared.stages.count - 1
                        ].effect,
                        outcome: .failed(reasonCode: reasonCode),
                        gpu: gpu
                    )
                )
            } catch {
                emission.diagnostics.append(
                    "failure-observation-invariant-rejected"
                )
            }
        }
        return emission
    }

    func candidateBlueprintLocked(
        for prepared: SceneResolvedMaterialGraphExecutor.PreparedChain,
        startingAt base: [Graph.EffectKey: Tail]
    ) -> CandidateBlueprint? {
        guard let terminal = prepared.stages.last?.effectOutputResource,
              terminal.resourceGeneration == prepared.finalResource.resourceGeneration,
              terminal.publication.isSameAtom(as: prepared.finalResource.publication),
              prepared.finalResource.publication.texture === prepared.finalTexture else {
            return nil
        }
        var current = base
        var states: [Graph.EffectKey: State] = [:]
        var resources: [
            Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]
        ] = [:]
        var mappings: [Graph.EffectKey: UInt64] = [:]
        var resets: [Graph.EffectKey: SceneGraphExecutionResetReason] = [:]
        for value in prepared.stages {
            let previous = current[value.effect]
            guard transitionResourcesAreValid(value),
                  let generation = mappingGenerationLocked(
                      previous: previous,
                      next: value.transition.nextState
                  ) else { return nil }
            if let reason = resetReasonLocked(
                previous: previous?.state,
                transaction: value.transition.transaction
            ) { resets[value.effect] = reason }
            states[value.effect] = value.transition.nextState
            resources[value.effect] = value.persistentResources
            mappings[value.effect] = generation
            current[value.effect] = .init(
                state: value.transition.nextState,
                persistentResources: value.persistentResources,
                historyPin: nil,
                mappingGeneration: generation
            )
        }
        return .init(
            states: states,
            resources: resources,
            mappingGenerations: mappings,
            resetReasons: resets
        )
    }

}
