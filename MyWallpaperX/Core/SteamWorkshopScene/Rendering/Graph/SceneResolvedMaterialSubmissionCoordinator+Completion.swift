import Foundation
import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    /// Seal transfers ledgers to pendingSubmissions, but does not enqueue the
    /// buffer. A failed sibling surface can cancel that precise pending suffix
    /// without waiting for a completion that will never occur.
    func cancelUnsubmittedFrame(on commandBuffer: MTLCommandBuffer) {
        lock.lock()
        guard commandBuffer.status == .notEnqueued else {
            lock.unlock()
            return
        }
        let bufferID = ObjectIdentifier(commandBuffer)
        if preparedSceneColor?.commandBufferID == bufferID || preparedDisplayScratch?.commandBufferID == bufferID {
            cancelPreparedSceneColorLocked()
        }
        guard let index = pendingSubmissions.firstIndex(where: {
            $0.commandBufferIdentities.contains(bufferID)
        }) else {
            pruneCommandBufferRecordsLocked()
            lock.unlock()
            return // No pending submission; unsubmitted terminal reservation was released.
        }
        guard index == pendingSubmissions.count - 1,
              activeTransactions.isEmpty,
              pendingSubmissions[index].commandBufferIdentities == [bufferID],
              commandBufferRecords[bufferID]?.buffer === commandBuffer else {
            lock.unlock()
            return // Never release a different or already dependent candidate.
        }
        let cancelled = pendingSubmissions.removeLast()
        cancelled.displayScratchPin?.release()
        if let sceneColor = cancelled.sceneColor { completeSceneColorLocked(sceneColor, succeeded: false) }
        var emission = Emission()
        for identity in cancelled.ledgerIDs.reversed() {
            emission.append(terminalizeLedgerLocked(identity, as: .cancelled))
        }
        releasePins(cancelled.retiredHistoryPins)
        restoreScheduledTailsLocked()
        pruneCommandBufferRecordsLocked()
        lock.unlock()
        emit(emission)
    }

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
        cancelPreparedSceneColorLocked()
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
        observationID: UInt64,
        status: SceneGraphExecutionGPUCompletionStatus
    ) {
        lock.lock()
        // Both addresses and Metal wrapper instances can outlive/reuse a
        // registration. Only that registration may resolve its ledger.
        guard var record = commandBufferRecords[identity],
              record.observationID == observationID else {
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
        var retained = active.union(pending)
        if let id = preparedSceneColor?.commandBufferID { retained.insert(id) }
        if let id = preparedDisplayScratch?.commandBufferID { retained.insert(id) }
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
                head.displayScratchPin?.release()
                if let sceneColor = head.sceneColor { completeSceneColorLocked(sceneColor, succeeded: false) }
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
                // the serial lock is held. Observation failures cannot undo promotion.
                committedTails = head.finalTails
                head.displayScratchPin?.release()
                if let sceneColor = head.sceneColor {
                    let promoted = completeSceneColorLocked(sceneColor, succeeded: true)
                    if promoted, capturesExecutionObservations {
                        emission.diagnostics.append("scene-color-completed frame=\(sceneColor.producerReceipt.frameIndex) allocation=\(sceneColor.lease.targets.identity.generation) member=\(sceneColor.member) authoredDraw=\(sceneColor.requiresDraw) mapped=\(sceneColor.displayMapped == true) intent=\(sceneColor.intent) sourceSubmission=\(sceneColor.producerReceipt.commandBufferObservationID)")
                    }
                }
                for identity in head.ledgerIDs {
                    emission.append(terminalizeLedgerLocked(
                        identity,
                        as: .succeeded(
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
        guard !identities.isEmpty || submission.sceneColor != nil || submission.displayScratchPin != nil,
              identities.count == submission.ledgerIDs.count,
              !submission.commandBufferIdentities.isEmpty else { return false }
        return submissionCanCommitLocked(submission)
    }

    func submissionCanCommitLocked(_ submission: PendingSubmission) -> Bool {
        guard !submission.ledgerIDs.isEmpty || submission.sceneColor != nil || submission.displayScratchPin != nil,
              submission.sceneColor.map({ $0.epoch == executionEpoch && $0.matchesCurrentEpoch }) != false,
              tailsAreValid(submission.finalTails) else { return false }
        return submission.ledgerIDs.allSatisfy { identity in
            guard let ledger = activeByID[identity] else { return false }
            return ledger.phase == .sealed
                && ledger.submissionID == submission.identity
                && ledger.ticketConsumed
                && ledger.outputConsumed
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
        case let .succeeded(retained):
            if let commit = ledger.commit {
                commit.submissionPin.release()
                releasePins(
                    commit.historyPinsByEffect.values,
                    retaining: retained
                )
            }
            emission.append(successObservationsLocked(for: ledger))
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

    /// Observations describe a terminal result; they never authorize it.
    /// The sealed ledger already passed the same product checks in both modes.
    func successObservationsLocked(for ledger: PreparedLedger) -> Emission {
        var emission = Emission()
        guard capturesExecutionObservations else { return emission }
        for value in ledger.prepared.stages {
            let localFailure = ledger.localOutputFailureReasonCode
            let committedBase = ledger.committedBaseTails[value.effect]
            guard let mappingGeneration = localFailure == nil
                ? ledger.blueprint?.mappingGenerations[value.effect]
                : committedBase?.mappingGeneration ?? 0 else {
                emission.diagnostics.append(
                    "success-observation-mapping-generation-missing"
                    + "-layer-\(value.effect.layerID)"
                    + "-effect-\(value.effect.effectIndex)"
                )
                continue
            }
            do {
                emission.observations.append(try
                    SceneResolvedMaterialGraphObservationBuilder.make(
                        value,
                        runtimeInstanceIdentity: runtimeInstanceIdentity,
                        frameIndex: ledger.frameIndex,
                        transactionID: ledger.identity,
                        executionEpoch: ledger.epoch,
                        mappingGeneration: mappingGeneration,
                        resetReason: localFailure == nil
                            ? ledger.blueprint?.resetReasons[value.effect] : nil,
                        committedBaseState: localFailure == nil
                            ? nil : committedBase?.state,
                        terminalEffect: ledger.prepared.stages[
                            ledger.prepared.stages.count - 1
                        ].effect,
                        terminalCompositorConsumed: ledger.compositorConsumed,
                        outcome: localFailure.map {
                            .failed(reasonCode: $0)
                        } ?? .succeeded,
                        gpu: localFailure == nil ? .completed : nil,
                        dependencyProviders: ledger.preparedDependencyEffects
                            .map(\.providerLayerID)
                    )
                )
            } catch {
                emission.diagnostics.append(
                    "success-observation-\(String(describing: error))"
                    + "-layer-\(value.effect.layerID)"
                    + "-effect-\(value.effect.effectIndex)"
                )
            }
        }
        return emission
    }

    func failureObservationsLocked(
        for ledger: PreparedLedger,
        reasonCode: String,
        gpu: SceneGraphExecutionGPUCompletionStatus?
    ) -> Emission {
        var emission = Emission()
        guard capturesExecutionObservations else { return emission }
        for value in ledger.prepared.stages {
            let base = ledger.committedBaseTails[value.effect]
            do {
                emission.observations.append(try
                    SceneResolvedMaterialGraphObservationBuilder.make(
                        value,
                        runtimeInstanceIdentity: runtimeInstanceIdentity,
                        frameIndex: ledger.frameIndex,
                        transactionID: ledger.identity,
                        executionEpoch: ledger.epoch,
                        mappingGeneration: base?.mappingGeneration ?? 0,
                        resetReason: nil,
                        committedBaseState: base?.state,
                        terminalEffect: ledger.prepared.stages[
                            ledger.prepared.stages.count - 1
                        ].effect,
                        terminalCompositorConsumed: false,
                        outcome: .failed(reasonCode: reasonCode),
                        gpu: gpu,
                        dependencyProviders:
                            ledger.preparedDependencyEffects
                                .map(\.providerLayerID)
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
        for prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph,
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
            let lifecycle = resetReasonLocked(
                previous: previous?.state,
                next: value.transition.nextState,
                transaction: value.transition.transaction,
                historyRehydrateCopyCount: value.historyRehydrateCopyCount,
                historyContentDiscarded: value.historyContentDiscarded
            )
            guard lifecycle.valid else { return nil }
            if let reason = lifecycle.reason { resets[value.effect] = reason }
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
