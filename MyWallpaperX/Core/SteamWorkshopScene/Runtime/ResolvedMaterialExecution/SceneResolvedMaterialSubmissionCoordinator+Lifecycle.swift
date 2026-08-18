import Foundation

extension SceneResolvedMaterialSubmissionCoordinator {
    var shouldDeferFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !submissionQueueAcceptsFrameLocked()
    }

    func beginFrame(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) {
        var emission = Emission()
        lock.lock()
        if frameIsActive || !activeTransactions.isEmpty {
            emission = failActiveFrameLocked(reason: "frame-reentered-before-end")
        }
        frameIsActive = true
        frameSealed = false
        framePreparationComplete = false
        preparedLedgerByLayerID.removeAll(keepingCapacity: true)
        frameLocalFallbacks.removeAll(keepingCapacity: true)
        let waits = !submissionQueueAcceptsFrameLocked()
        frameRequiresDrop = waits
        frameWaitsForPendingSubmission = waits
        frameClaimed = 0
        frameEncoded = 0
        frameFailures = 0
        frameDeferred = waits ? 1 : 0
        switch SceneResolvedMaterialFrameSnapshot.validated(
            textureSnapshot: textureSnapshot,
            dynamicSnapshot: dynamicSnapshot,
            frameInputs: frameInputs
        ) {
        case let .success(value):
            frame = value
            frameFailure = nil
        case let .failure(failure):
            frame = nil
            frameFailure = failure
        }
        lock.unlock()
        emit(emission)
    }

    /// Ends the surface runtime before its pool is reset. In-flight ledgers and
    /// retired committed history stay pinned until their terminal callback.
    func invalidate(reason: SceneGraphExecutionResetReason) {
        lock.lock()
        var emission = Emission()
        if !activeTransactions.isEmpty {
            emission.append(failActiveFrameLocked(reason: reason.rawValue))
        }
        let pendingIDs = Set(pendingSubmissions.flatMap(\.ledgerIDs))
        for identity in activeByID.keys.sorted() where !pendingIDs.contains(identity) {
            emission.append(terminalizeLedgerLocked(
                identity,
                as: .failed(reasonCode: reason.rawValue, gpu: nil)
            ))
        }
        let committedPins = committedTails.values.compactMap(\.historyPin)
        if pendingSubmissions.isEmpty {
            releasePins(committedPins)
        } else {
            let retirementIndex = pendingSubmissions.index(
                before: pendingSubmissions.endIndex
            )
            if pendingSubmissions[retirementIndex].cancellationReason == nil {
                pendingSubmissions[retirementIndex].cancellationReason = reason.rawValue
            }
            if pendingSubmissions[retirementIndex].retiredHistoryPins.isEmpty {
                pendingSubmissions[retirementIndex].retiredHistoryPins = committedPins
            }
            for index in pendingSubmissions.indices {
                if pendingSubmissions[index].cancellationReason == nil {
                    pendingSubmissions[index].cancellationReason = reason.rawValue
                }
            }
        }
        committedTails.removeAll(keepingCapacity: false)
        scheduledTails.removeAll(keepingCapacity: false)
        activeTransactions.removeAll(keepingCapacity: false)
        preparedLedgerByLayerID.removeAll(keepingCapacity: false)
        frameLocalFallbacks.removeAll(keepingCapacity: false)
        frame = nil
        frameFailure = nil
        frameIsActive = false
        frameSealed = false
        frameRequiresDrop = false
        frameWaitsForPendingSubmission = false
        framePreparationComplete = false
        frameClaimed = 0
        frameEncoded = 0
        frameFailures = 0
        frameDeferred = 0
        resetReasonByGeneration.removeAll(keepingCapacity: false)
        invalidateEpochLocked()
        _ = advanceResetLocked(reason: reason)
        switch reason {
        case .surfaceStop, .sceneSwitch:
            break
        default:
            emission.diagnostics.append("runtime-invalidated-\(reason.rawValue)")
        }
        lock.unlock()
        emit(emission)
    }

    func failActiveFrameLocked(reason: String) -> Emission {
        failActiveFrameRespectingGPUOwnershipLocked(reason: reason)
    }

    func claimedFailureLocked(reason: String) -> Emission {
        frameFailures += 1
        guard !frameRequiresDrop else { return .init() }
        return failActiveFrameLocked(reason: reason)
    }

    func invalidateEpochLocked() {
        guard executionEpoch < UInt64.max else {
            terminalFailureReason = "execution-epoch-overflow"
            return
        }
        executionEpoch += 1
    }

    @discardableResult
    func advanceResetLocked(reason: SceneGraphExecutionResetReason) -> Bool {
        guard resetGeneration < UInt64.max else {
            terminalFailureReason = "reset-generation-overflow"
            return false
        }
        resetGeneration += 1
        resetReasonByGeneration[resetGeneration] = reason
        if resetReasonByGeneration.count > 64,
           let oldest = resetReasonByGeneration.keys.min() {
            resetReasonByGeneration.removeValue(forKey: oldest)
        }
        guard executor?.reset() != false else {
            terminalFailureReason = "executor-reset-generation-overflow"
            return false
        }
        return true
    }

    @discardableResult
    func endFrame() -> [String] {
        var emission = Emission()
        lock.lock()
        if !frameSealed && !activeTransactions.isEmpty {
            frameFailures += 1
            emission = failActiveFrameLocked(reason: "frame-ended-before-seal")
        }
        let pendingCount = pendingSubmissions.reduce(0) {
            $0 + $1.ledgerIDs.count
        }
        let line = "resolved material runtime audit: schema=scene-graph-executor-v1"
            + " claimed=\(frameClaimed) encoded=\(frameEncoded)"
            + " failures=\(frameFailures) deferred=\(frameDeferred)"
            + " pending=\(pendingCount) gpuEncoded=\(frameEncoded)"
            + " localFallbacks=\(frameLocalFallbacks.count)"
        let shouldLog = line != lastReportSignature
        if shouldLog { lastReportSignature = line }
        frame = nil
        frameFailure = nil
        frameIsActive = false
        frameSealed = false
        frameRequiresDrop = false
        frameWaitsForPendingSubmission = false
        framePreparationComplete = false
        preparedLedgerByLayerID.removeAll(keepingCapacity: true)
        frameLocalFallbacks.removeAll(keepingCapacity: true)
        lock.unlock()
        emit(emission)
        if shouldLog { logSink(line) }
        return [line]
    }

    func commitIsValid(
        _ commit: Commit,
        preparedTargets: ScenePreparedPersistentGraphTargets,
        prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph
    ) -> Bool {
        let effects = Set(prepared.stages.map(\.effect))
        let generations = Set(prepared.stages.map {
            $0.transition.transaction.allocationGeneration
        })
        guard effects.count == prepared.stages.count,
              generations.count == 1,
              let generation = generations.first,
              leasesHaveSameAtoms(commit.leases, preparedTargets.leases),
              Set(commit.historyPinsByEffect.keys)
                == Set(prepared.historyTokensByEffect.keys),
              Set(prepared.historyTokensByEffect.keys).isSubset(of: effects),
              prepared.historyTokensByEffect.values.allSatisfy({ !$0.isEmpty }),
              commit.submissionPin.generation == generation,
              commit.submissionPin.purpose == .submission else { return false }
        return commit.historyPinsByEffect.allSatisfy { effect, pin in
            historyPinMatches(
                pin,
                effect: effect,
                tokens: prepared.historyTokensByEffect[effect],
                generation: generation
            )
        }
    }

    func leasesHaveSameAtoms(
        _ lhs: [SceneGraphRenderTargetLease],
        _ rhs: [SceneGraphRenderTargetLease]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            guard left.generation == right.generation,
                  left.table.plan == right.table.plan,
                  left.fullFramePair.first == right.fullFramePair.first,
                  left.fullFramePair.second == right.fullFramePair.second,
                  Set(left.texturesByToken.keys) == Set(right.texturesByToken.keys)
            else { return false }
            return left.texturesByToken.allSatisfy { token, texture in
                right.texturesByToken[token] === texture
            }
        }
    }

    func historyPinMatches(
        _ pin: SceneGraphRenderTargetResidencyPin?,
        effect: Graph.EffectKey,
        tokens: Set<State.PhysicalToken>?,
        generation: UInt64?
    ) -> Bool {
        guard let tokens, !tokens.isEmpty else { return pin == nil }
        guard let pin, let generation,
              pin.generation == generation,
              case let .history(pinEffect, pinTokens) = pin.purpose else {
            return false
        }
        return pinEffect == effect && pinTokens == tokens
    }

    func tailsAreValid(_ tails: [Graph.EffectKey: Tail]) -> Bool {
        tails.allSatisfy { effect, tail in
            let state = tail.state
            let identities = state.historyClosureIdentities
            let readable = state.logicalMapping.filter {
                identities.contains($0.key) && $0.value.contentGeneration > 0
            }
            guard Set(readable.keys) == identities,
                  resourcesMatchMapping(
                      tail.persistentResources,
                      mapping: state.logicalMapping,
                      allocationGeneration: state.allocationGeneration
                  ) else { return false }
            let tokens = Set(readable.values.map(\.token))
            return historyPinMatches(
                tail.historyPin,
                effect: effect,
                tokens: tokens.isEmpty ? nil : tokens,
                generation: state.allocationGeneration
            )
        }
    }

    func transitionResourcesAreValid(
        _ value: SceneResolvedMaterialGraphExecutor.PreparedStage
    ) -> Bool {
        let transaction = value.transition.transaction
        let next = value.transition.nextState
        guard resourcesMatchMapping(
            value.frameResources,
            mapping: transaction.mappingAfter,
            allocationGeneration: transaction.allocationGeneration
        ), resourcesMatchMapping(
            value.persistentResources,
            mapping: next.logicalMapping,
            allocationGeneration: next.allocationGeneration
        ), Set(value.persistentResources.keys) == next.historyClosureIdentities,
           physicalMapping(next) == transaction.mappingAfter.mapValues(\.token),
           SceneGraphRenderTargetLease.graphSamplingMatches(
               value.effectOutputResource,
               expectedSampling: .linearClamp
           ),
           value.effectOutputResource.publication.requestIdentity
                == .graph(value.pairStep.outputIdentity),
           value.effectOutputResource.resourceGeneration > 0,
           value.effectOutputResource.publication.contentGeneration
                == value.effectOutputResource.resourceGeneration,
           case let .provider(.graph(generation, token)) =
                value.effectOutputResource.publication.candidate.identity,
           generation == transaction.allocationGeneration,
           !transaction.mappingAfter.values.contains(where: {
               $0.token.rawValue == token
           }) else { return false }
        return true
    }

    func resourcesMatchMapping(
        _ resources: [Graph.TextureIdentity: SceneFrameTextureResource],
        mapping: [Graph.TextureIdentity: State.VersionedResource],
        allocationGeneration: UInt64?
    ) -> Bool {
        let readable = mapping.filter { $0.value.contentGeneration > 0 }
        guard Set(resources.keys) == Set(readable.keys),
              let allocationGeneration else { return false }
        return readable.allSatisfy { identity, versioned in
            guard let resource = resources[identity],
                  SceneGraphRenderTargetLease.graphSamplingMatches(
                      resource,
                      descriptor: versioned.descriptor
                  ),
                  resource.publication.requestIdentity == .graph(identity),
                  resource.resourceGeneration == versioned.contentGeneration,
                  resource.publication.contentGeneration
                    == versioned.contentGeneration,
                  case let .provider(.graph(generation, token)) =
                    resource.publication.candidate.identity else { return false }
            return generation == allocationGeneration
                && token == versioned.token.rawValue
        }
    }

    func mappingGenerationLocked(previous: Tail?, next: State) -> UInt64? {
        guard let previous else { return 1 }
        let changed = previous.state.allocationGeneration != next.allocationGeneration
            || physicalMapping(previous.state) != physicalMapping(next)
        guard changed else { return previous.mappingGeneration }
        guard previous.mappingGeneration < UInt64.max else { return nil }
        return previous.mappingGeneration + 1
    }

    func resetReasonLocked(
        previous: State?,
        transaction: State.Transaction
    ) -> SceneGraphExecutionResetReason? {
        guard let previous else { return .initial }
        if previous.effectGeneration != transaction.effectGeneration {
            return .effectReparse
        }
        if previous.resetGeneration != transaction.resetGeneration {
            return resetReasonByGeneration[transaction.resetGeneration]
                ?? .executorInvalidation
        }
        if previous.allocationGeneration != transaction.allocationGeneration {
            return .allocationReprepare
        }
        return nil
    }

    func physicalMapping(
        _ state: State
    ) -> [Graph.TextureIdentity: State.PhysicalToken] {
        state.logicalMapping.mapValues(\.token)
    }

    func historyPinIdentities<S: Sequence>(
        in tails: S
    ) -> Set<ObjectIdentifier> where S.Element == Tail {
        Set(tails.compactMap(\.historyPin).map(ObjectIdentifier.init))
    }

    func releasePins<S: Sequence>(
        _ pins: S,
        retaining retained: Set<ObjectIdentifier> = []
    ) where S.Element == SceneGraphRenderTargetResidencyPin {
        var released = Set<ObjectIdentifier>()
        for pin in pins {
            let identity = ObjectIdentifier(pin)
            guard !retained.contains(identity),
                  released.insert(identity).inserted else { continue }
            pin.release()
        }
    }

    func emit(_ emission: Emission) {
        emission.observations.forEach { _ = telemetry.record($0) }
        emission.diagnostics.forEach {
            logSink("MWX DEBUG SCENE: schema=1 axis=graph-execution diagnostic=\($0)")
        }
    }
}
