import Foundation
import Metal

enum SceneSubmissionLifecycleChecks {
    static func invalidationHistoryAndObservation(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            coordinator.invalidate(reason: .surfaceStop)
            results["normalInvalidateHasNoGraphDiagnostic"] = recorder.lines
                .allSatisfy { !$0.contains("axis=graph-execution diagnostic=") }
        }

        do {
            let coordinator = makeCoordinator(device)
            let priorResource = State.VersionedResource(
                token: .init(rawValue: "prior-history"),
                contentGeneration: 4
            )
            let nextResource = State.VersionedResource(
                token: .init(rawValue: "next-history"),
                contentGeneration: 4
            )
            let previous = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 1,
                logicalMapping: [historyIdentity: priorResource],
                historyLogicalIdentities: [historyIdentity],
                historyClosureIdentities: [historyIdentity]
            )
            let next = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 2,
                logicalMapping: [historyIdentity: nextResource],
                historyLogicalIdentities: [historyIdentity],
                historyClosureIdentities: [historyIdentity]
            )
            let transaction = State.Transaction(
                intents: [],
                mappingBefore: [historyIdentity: nextResource],
                mappingAfter: [historyIdentity: nextResource],
                allocationGeneration: 2,
                effectGeneration: 1,
                resetGeneration: 1
            )
            let copyOnWrite = coordinator.resetReasonLocked(
                previous: previous,
                next: next,
                transaction: transaction,
                historyRehydrateCopyCount: 1,
                historyContentDiscarded: false
            )
            results["stableHistoryAllocationClassifiesCopyOnWrite"] =
                copyOnWrite.valid && copyOnWrite.reason == .historyCopyOnWrite

            let changedResource = State.VersionedResource(
                token: .init(rawValue: "changed-history"),
                descriptor: .init(
                    extent: .init(width: 4, height: 4),
                    addressMode: .clampToEdge
                ),
                contentGeneration: 0
            )
            let changed = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 2,
                logicalMapping: [historyIdentity: changedResource],
                historyLogicalIdentities: [historyIdentity],
                historyClosureIdentities: [historyIdentity]
            )
            let reprepare = coordinator.resetReasonLocked(
                previous: previous,
                next: changed,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: true
            )
            results["descriptorChangeClassifiesAllocationReprepare"] =
                reprepare.valid && reprepare.reason == .allocationReprepare

            let emptyPrevious = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 1,
                logicalMapping: [:],
                historyLogicalIdentities: [],
                historyClosureIdentities: []
            )
            let emptyNext = State(
                effectGeneration: 1,
                resetGeneration: 1,
                allocationGeneration: 2,
                logicalMapping: [:],
                historyLogicalIdentities: [],
                historyClosureIdentities: []
            )
            let rebind = coordinator.resetReasonLocked(
                previous: emptyPrevious,
                next: emptyNext,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            results["historyFreeFreshIdentityClassifiesAllocationRebind"] =
                rebind.valid && rebind.reason == .allocationRebind

            let unknown = coordinator.resetReasonLocked(
                previous: previous,
                next: next,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            results["unknownHistoryTransitionRejected"] = !unknown.valid

            let initial = coordinator.resetReasonLocked(
                previous: nil,
                next: next,
                transaction: transaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            coordinator.invalidate(reason: .executorInvalidation)
            let invalidatedTransaction = State.Transaction(
                intents: [],
                mappingBefore: [:],
                mappingAfter: [:],
                allocationGeneration: 3,
                effectGeneration: 1,
                resetGeneration: coordinator.resetGeneration
            )
            let invalidatedNext = State(
                effectGeneration: 1,
                resetGeneration: coordinator.resetGeneration,
                allocationGeneration: 3,
                logicalMapping: [:],
                historyLogicalIdentities: [],
                historyClosureIdentities: []
            )
            let invalidated = coordinator.resetReasonLocked(
                previous: nil,
                next: invalidatedNext,
                transaction: invalidatedTransaction,
                historyRehydrateCopyCount: 0,
                historyContentDiscarded: false
            )
            results["freshAndInvalidatedInitialStatesKeepDistinctReasons"] =
                initial.valid && initial.reason == .initial
                && invalidated.valid
                && invalidated.reason == .executorInvalidation
        }

        for (key, reason) in [
            ("deviceLossInvalidateHasGraphDiagnostic", SceneGraphExecutionResetReason.deviceLoss),
            ("executorInvalidateHasGraphDiagnostic", SceneGraphExecutionResetReason.executorInvalidation),
        ] {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            coordinator.invalidate(reason: reason)
            results[key] = recorder.lines.contains {
                $0.contains("axis=graph-execution diagnostic=")
                    && $0.contains("runtime-invalidated-\(reason.rawValue)")
            }
        }

        for (key, reason) in [
            ("pendingSurfaceStopCancelsSilently", SceneGraphExecutionResetReason.surfaceStop),
            ("pendingSceneSwitchCancelsSilently", SceneGraphExecutionResetReason.sceneSwitch),
        ] {
            let cancellation = runPendingCancellation(
                device: device,
                queue: queue,
                reasonCode: reason.rawValue,
                gpuStatus: .completed
            )
            results[key] = cancellation.graphLines.isEmpty
                && cancellation.releasedPins
                && cancellation.clearedState
        }

        for (key, reason) in [
            ("allocationReprepareRemainsFailure", SceneGraphExecutionResetReason.allocationReprepare),
            ("effectReparseRemainsFailure", SceneGraphExecutionResetReason.effectReparse),
            ("deviceLossRemainsFailure", SceneGraphExecutionResetReason.deviceLoss),
            ("executorInvalidationRemainsFailure", SceneGraphExecutionResetReason.executorInvalidation),
        ] {
            let cancellation = runPendingCancellation(
                device: device,
                queue: queue,
                reasonCode: reason.rawValue,
                gpuStatus: .completed
            )
            results[key] = recordedFailure(
                cancellation,
                reasonCode: reason.rawValue,
                gpuStatus: nil
            )
        }

        let unknownCancellation = runPendingCancellation(
            device: device,
            queue: queue,
            reasonCode: "fixture-invariant-failure",
            gpuStatus: .completed
        )
        results["unknownCancellationRemainsFailure"] = recordedFailure(
            unknownCancellation,
            reasonCode: "fixture-invariant-failure",
            gpuStatus: nil
        )

        let failedSurfaceStop = runPendingCancellation(
            device: device,
            queue: queue,
            reasonCode: SceneGraphExecutionResetReason.surfaceStop.rawValue,
            gpuStatus: .failed
        )
        results["surfaceStopGPUFailureRemainsFailure"] = recordedFailure(
            failedSurfaceStop,
            reasonCode: SceneGraphExecutionResetReason.surfaceStop.rawValue,
            gpuStatus: .failed
        )

        let invalidSurfaceStop = runPendingCancellation(
            device: device,
            queue: queue,
            reasonCode: SceneGraphExecutionResetReason.surfaceStop.rawValue,
            gpuStatus: .completed,
            consumed: false
        )
        results["invalidSurfaceStopLedgerRemainsFailure"] = recordedFailure(
            invalidSurfaceStop,
            reasonCode: "lifecycle-cancellation-ledger-invariant-rejected",
            gpuStatus: nil
        )

        do {
            let prepared = makeObservationTransition(device: device)
            let success = try SceneResolvedMaterialGraphObservationBuilder.make(
                prepared,
                runtimeInstanceIdentity: "runtime-fixture",
                frameIndex: 10,
                transactionID: 12,
                executionEpoch: 11,
                mappingGeneration: 9,
                resetReason: .initial,
                terminalEffect: effect,
                terminalCompositorConsumed: true,
                outcome: .succeeded,
                gpu: .completed
            )
            let succeeded: Bool
            if case .succeeded = success.outcome { succeeded = true }
            else { succeeded = false }
            results["productionObservationBuilderSuccess"] = succeeded
                && success.identity.layerID == 7
                && success.nodeCounts.authored == 1
                && success.nodeCounts.material == 1
                && success.nodeCounts.rejected == 0
                && success.nodeCounts.compose == 1
                && success.composeSlotBefore == .primary
                && success.composeSlotAfter == .primary
                && success.finalOutput?.physicalIdentity
                    == "observation-output-token"
                && success.compositorConsumed
                && success.gpuCompletionStatus == .completed
                && success.resetReason == .initial
                && success.allocationGeneration == 3
                && success.mappingGeneration == 9
                && success.inputWidth == 2_048
                && success.inputHeight == 1_152
                && success.historyRehydrateCopyCount == 0
                && !success.historyContentDiscarded
                && success.transactionIdentity == "r4:11:12:0"
                && success.programIdentity == "fixture-program"

            let failed = try SceneResolvedMaterialGraphObservationBuilder.make(
                prepared,
                runtimeInstanceIdentity: "runtime-fixture",
                frameIndex: 10,
                transactionID: 13,
                executionEpoch: 11,
                mappingGeneration: 8,
                resetReason: .effectReparse,
                committedBaseState: makeCommittedObservationBase(),
                terminalEffect: effect,
                terminalCompositorConsumed: false,
                outcome: .failed(reasonCode: "fixture-gpu-failed"),
                gpu: .failed
            )
            let failedWithExpectedReason: Bool
            if case let .failed(reason) = failed.outcome {
                failedWithExpectedReason = reason == "fixture-gpu-failed"
            } else {
                failedWithExpectedReason = false
            }
            results["productionObservationBuilderFailure"] =
                failedWithExpectedReason
                && failed.nodeCounts.authored == 1
                && failed.nodeCounts.material == 0
                && failed.nodeCounts.rejected == 1
                && failed.nodeCounts.compose == 0
                && failed.composeSlotBefore == .none
                && failed.composeSlotAfter == .none
                && failed.finalOutput == nil
                && !failed.compositorConsumed
                && failed.gpuCompletionStatus == .failed
                && failed.resetReason == nil
                && failed.allocationGeneration == 2
                && failed.mappingGeneration == 8
                && failed.historyState == .reused
        }

    }

    static func ticketsPinsAndCompletionOrder(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            let texture = makeTexture(device, "ticket-final")
            let historyPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]),
                generation: 1
            )
            let tail = makeTail(
                device: device, token: "A", generation: 1, pin: historyPin
            )
            let commit = makeCommit(generation: 1, historyPin: historyPin)
            coordinator.frameIsActive = true
            _ = coordinator.observeCommandBufferLocked(buffer)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: buffer,
                prepared: makePrepared(device: device, texture: texture),
                commit: commit, candidate: [effect: tail], phase: .encoded
            )
            coordinator.activeTransactions = [1]
            let ticket = SceneResolvedMaterialRuntimeBridge.ExecutionTicket(
                identity: 1,
                epoch: coordinator.executionEpoch,
                finalTextureIdentity: ObjectIdentifier(texture),
                finalContent: .color(.resolved(.premultipliedAlpha)),
                consumesExternalPrimaryDependency: false,
                effectFailures: []
            )
            let firstOutcome = coordinator.markComposite(
                ticket, texture: texture, consumed: true
            )
            let firstWasConsumed: Bool
            if case .consumed = firstOutcome { firstWasConsumed = true }
            else { firstWasConsumed = false }
            let consumedOnce = coordinator.activeByID[1]?.phase == .outputConsumed
                && coordinator.activeByID[1]?.ticketConsumed == true
            let reusedOutcome = coordinator.markComposite(
                ticket, texture: texture, consumed: true
            )
            let reuseReason: String?
            if case let .failed(reasonCode) = reusedOutcome {
                reuseReason = reasonCode
            } else {
                reuseReason = nil
            }
            results["ticketIsSingleConsumption"] = firstWasConsumed
                && reuseReason == "final-composite-ticket-reused"
                && consumedOnce
                && coordinator.activeByID.isEmpty
                && coordinator.frameRequiresDrop
                && commit.submissionPin.releaseCount == 1
                && historyPin.releaseCount == 1
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            _ = coordinator.observeCommandBufferLocked(buffer)
            let oldPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]), generation: 1
            )
            let oldTail = makeTail(
                device: device, token: "A", generation: 1, pin: oldPin
            )
            coordinator.committedTails = [effect: oldTail]
            coordinator.scheduledTails = coordinator.committedTails
            let newPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "B")]), generation: 2
            )
            let newTail = makeTail(
                device: device, token: "B", generation: 2, pin: newPin
            )
            let commit = makeCommit(generation: 2, historyPin: newPin)
            let ledger = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: buffer, prepared: makePrepared(device: device),
                commit: commit, candidate: [effect: newTail],
                phase: .sealed, submissionID: 1, consumed: true
            )
            coordinator.activeByID[1] = ledger
            coordinator.pendingSubmissions = [.init(
                identity: 1, ledgerIDs: [1],
                commandBufferIdentities: [ObjectIdentifier(buffer)],
                finalTails: [effect: newTail], gpuStatus: nil,
                cancellationReason: nil, retiredHistoryPins: []
            )]
            coordinator.invalidate(reason: .surfaceStop)
            let heldBeforeCallback = oldPin.active && newPin.active
                && commit.submissionPin.active
                && coordinator.pendingSubmissions.count == 1
                && coordinator.committedTails.isEmpty
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0, status: .completed
            )
            results["invalidateDefersPinReleaseUntilTerminal"] = heldBeforeCallback
                && !oldPin.active && !newPin.active
                && !commit.submissionPin.active
                && oldPin.releaseCount == 1 && newPin.releaseCount == 1
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.committedTails.isEmpty
        }

        do {
            let coordinator = makeCoordinator(device)
            let first = queue.makeCommandBuffer()!
            let second = queue.makeCommandBuffer()!
            _ = coordinator.observeCommandBufferLocked(first)
            _ = coordinator.observeCommandBufferLocked(second)
            let retired = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "old")]), generation: 1
            )
            let firstCommit = makeCommit(generation: 2)
            let secondCommit = makeCommit(generation: 3)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1, commandBuffer: first,
                prepared: makePrepared(device: device), commit: firstCommit,
                phase: .sealed, submissionID: 9
            )
            coordinator.activeByID[2] = makeLedger(
                coordinator: coordinator, identity: 2, commandBuffer: second,
                prepared: makePrepared(device: device), commit: secondCommit,
                phase: .sealed, submissionID: 9
            )
            coordinator.pendingSubmissions = [.init(
                identity: 9, ledgerIDs: [1, 2],
                commandBufferIdentities: [
                    ObjectIdentifier(first), ObjectIdentifier(second)
                ],
                finalTails: [:],
                gpuStatus: nil, cancellationReason: "aggregate-cancelled",
                retiredHistoryPins: [retired]
            )]
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(second), observationID: coordinator.commandBufferRecords[ObjectIdentifier(second)]?.observationID ?? 0, status: .completed
            )
            let reverseHeld = coordinator.pendingSubmissions.count == 1
                && retired.active && firstCommit.submissionPin.active
                && secondCommit.submissionPin.active
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), observationID: coordinator.commandBufferRecords[ObjectIdentifier(first)]?.observationID ?? 0, status: .completed
            )
            results["aggregateBarrierWaitsForAllBuffers"] = reverseHeld
                && coordinator.pendingSubmissions.isEmpty
                && !retired.active && !firstCommit.submissionPin.active
                && !secondCommit.submissionPin.active
        }

        do {
            let coordinator = makeCoordinator(device)
            let first = queue.makeCommandBuffer()!
            let pinA = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "queue-A")]),
                generation: 1
            )
            let tailA = makeTail(
                device: device, token: "queue-A", generation: 1, pin: pinA
            )
            let commitA = makeCommit(generation: 1, historyPin: pinA)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: first, tail: tailA, commit: commitA
            )
            let successor = queue.makeCommandBuffer()!
            let stateBeforeDeferredFrame = (
                coordinator.nextTransactionID,
                coordinator.executionEpoch,
                coordinator.commandBufferRecords.count
            )
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 2, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            results["historyPendingDefersDescendantBeforeFramePrepare"] =
                coordinator.shouldDeferFrame
                && coordinator.frameRequiresDrop
                && coordinator.frameWaitsForPendingSubmission
                && coordinator.frameDeferred == 1
                && coordinator.nextTransactionID == stateBeforeDeferredFrame.0
                && coordinator.executionEpoch == stateBeforeDeferredFrame.1
                && coordinator.commandBufferRecords.count
                    == stateBeforeDeferredFrame.2
                && coordinator.commandBufferRecords[
                    ObjectIdentifier(successor)
                ] == nil
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
            _ = coordinator.endFrame()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), observationID: coordinator.commandBufferRecords[ObjectIdentifier(first)]?.observationID ?? 0, status: .completed
            )
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            let commit = makeCommit(generation: 1)
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 20, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator,
                identity: 1,
                commandBuffer: buffer,
                prepared: makePrepared(device: device),
                commit: commit,
                phase: .allocationCommitted,
                claimed: false
            )
            coordinator.activeTransactions = [1]
            coordinator.preparedLedgerByLayerID = [effect.layerID: 1]
            let deferred = coordinator.deferPreparedFrame()
            let report = coordinator.endFrame().last ?? ""
            results["preparedFrameDeferralCancelsWithoutFailure"] = deferred
                && !commit.submissionPin.active
                && commit.submissionPin.releaseCount == 1
                && coordinator.activeByID.isEmpty
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
                && report.contains("failures=0 deferred=1")
        }

        do {
            let coordinator = makeCoordinator(device)
            let first = queue.makeCommandBuffer()!
            let second = queue.makeCommandBuffer()!
            let commitA = makeCommit(generation: 1)
            let commitB = makeCommit(generation: 2)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: first, tail: nil, commit: commitA
            )
            let firstLeavesCapacity = !coordinator.shouldDeferFrame
            seedPendingSuccess(
                coordinator: coordinator, identity: 2,
                commandBuffer: second, tail: nil, commit: commitB
            )
            let stateBeforeDeferredFrame = (
                coordinator.nextTransactionID,
                coordinator.executionEpoch,
                coordinator.effectGeneration,
                coordinator.resetGeneration
            )
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let capacityDefersWithoutAdvancing = coordinator.frameRequiresDrop
                && coordinator.frameWaitsForPendingSubmission
                && coordinator.frameDeferred == 1
                && coordinator.pendingSubmissions.count == 2
                && coordinator.activeByID.count == 2
                && stateBeforeDeferredFrame.0 == coordinator.nextTransactionID
                && stateBeforeDeferredFrame.1 == coordinator.executionEpoch
                && stateBeforeDeferredFrame.2 == coordinator.effectGeneration
                && stateBeforeDeferredFrame.3 == coordinator.resetGeneration
                && coordinator.scheduledTails.isEmpty
            _ = coordinator.endFrame()

            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(second), observationID: coordinator.commandBufferRecords[ObjectIdentifier(second)]?.observationID ?? 0, status: .completed
            )
            let reverseCompletionHeld = coordinator.pendingSubmissions.count == 2
                && coordinator.committedTails.isEmpty
                && commitA.submissionPin.active && commitB.submissionPin.active
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), observationID: coordinator.commandBufferRecords[ObjectIdentifier(first)]?.observationID ?? 0, status: .completed
            )
            results["twoPendingSubmissionsUseBoundedCapacity"] = firstLeavesCapacity
                && capacityDefersWithoutAdvancing
                && Coordinator.maximumPendingSubmissions
                    == SceneResolvedMaterialInFlightCapacity.maximumSubmissions
            results["reverseGPUCompletionCommitsOnlyFromQueueHead"] =
                reverseCompletionHeld
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.activeByID.isEmpty
                && coordinator.committedTails.isEmpty
                && coordinator.scheduledTails.isEmpty
                && commitA.submissionPin.releaseCount == 1
                && commitB.submissionPin.releaseCount == 1
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            let first = queue.makeCommandBuffer()!
            let second = queue.makeCommandBuffer()!
            let commitA = makeCommit(generation: 1)
            let commitB = makeCommit(generation: 2)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: first,
                tail: nil,
                commit: commitA,
                prepared: makeObservedPrepared(device: device)
            )
            seedPendingSuccess(
                coordinator: coordinator, identity: 2,
                commandBuffer: second,
                tail: nil,
                commit: commitB,
                prepared: makeObservedPrepared(device: device)
            )
            let epochBeforeFailure = coordinator.executionEpoch
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(first), observationID: coordinator.commandBufferRecords[ObjectIdentifier(first)]?.observationID ?? 0, status: .failed
            )
            let independentSuccessRemains = !coordinator.shouldDeferFrame
                && coordinator.executionEpoch == epochBeforeFailure
                && coordinator.pendingSubmissions.count == 1
                && coordinator.pendingSubmissions[0].identity == 2
                && coordinator.pendingSubmissions[0].cancellationReason == nil
                && coordinator.committedTails.isEmpty
                && coordinator.scheduledTails.isEmpty
                && commitA.submissionPin.releaseCount == 1
                && commitB.submissionPin.active
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(second), observationID: coordinator.commandBufferRecords[ObjectIdentifier(second)]?.observationID ?? 0, status: .completed
            )
            let failureLines = recorder.lines.filter {
                $0.contains("axis=graph-execution")
                    && $0.contains("outcome=failed")
            }
            results["historyFreeFailureDoesNotCancelIndependentSuccess"] =
                independentSuccessRemains
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.activeByID.isEmpty
                && coordinator.committedTails.isEmpty
                && coordinator.scheduledTails.isEmpty
                && !coordinator.shouldDeferFrame
                && commitA.submissionPin.releaseCount == 1
                && commitB.submissionPin.releaseCount == 1
                && failureLines.contains {
                    $0.contains("failure=gpu-command-buffer-failed")
                        && $0.contains("gpuCompletion=failed")
                }
                && !failureLines.contains {
                    $0.contains("failure=ancestor-transaction-invalidated")
                }
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            _ = coordinator.observeCommandBufferLocked(buffer)
            coordinator.frameIsActive = true
            coordinator.frame = .init(frameIndex: 4)
            let firstCommit = makeCommit(generation: 1)
            let secondCommit = makeCommit(generation: 1)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1, commandBuffer: buffer,
                prepared: makePrepared(device: device), commit: firstCommit,
                blueprint: .init(
                    states: [:], resources: [:], mappingGenerations: [:],
                    resetReasons: [:]
                ),
                candidate: [:], phase: .outputConsumed, consumed: true
            )
            coordinator.activeByID[2] = makeLedger(
                coordinator: coordinator, identity: 2, commandBuffer: buffer,
                prepared: makePrepared(device: device), commit: secondCommit,
                blueprint: .init(
                    states: [:], resources: [:], mappingGenerations: [:],
                    resetReasons: [:]
                ),
                candidate: [:], phase: .outputConsumed, consumed: true
            )
            coordinator.activeTransactions = [1, 2]
            let sealed = coordinator.sealFrame(on: buffer)
            results["sameFrameTransactionsSealAsOneSubmission"] = sealed
                && coordinator.pendingSubmissions.count == 1
                && coordinator.pendingSubmissions[0].ledgerIDs == [1, 2]
                && coordinator.pendingSubmissions[0].commandBufferIdentities
                    == [ObjectIdentifier(buffer)]
                && coordinator.activeTransactions.isEmpty
                && coordinator.activeByID.count == 2
        }

        do {
            let coordinator = makeCoordinator(device)
            let bufferA = queue.makeCommandBuffer()!
            let pinA = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]), generation: 1
            )
            let tailA = makeTail(
                device: device, token: "A", generation: 1, pin: pinA
            )
            let commitA = makeCommit(generation: 1, historyPin: pinA)
            seedPendingSuccess(
                coordinator: coordinator, identity: 1,
                commandBuffer: bufferA, tail: tailA, commit: commitA
            )
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(bufferA), observationID: coordinator.commandBufferRecords[ObjectIdentifier(bufferA)]?.observationID ?? 0, status: .completed
            )
            let resetAfterA = coordinator.resetGeneration

            let bufferB = queue.makeCommandBuffer()!
            let pinB = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "B")]), generation: 2
            )
            let tailB = makeTail(
                device: device, token: "B", generation: 2, pin: pinB
            )
            let commitB = makeCommit(generation: 2, historyPin: pinB)
            seedPendingSuccess(
                coordinator: coordinator, identity: 2,
                commandBuffer: bufferB, tail: tailB, commit: commitB
            )
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(bufferB), observationID: coordinator.commandBufferRecords[ObjectIdentifier(bufferB)]?.observationID ?? 0, status: .failed
            )
            let baseForC = coordinator.scheduledTails[effect]
            let reusedA = baseForC?.state.logicalMapping[historyIdentity]?
                .token.rawValue == "A"
                && baseForC?.historyPin === pinA
                && coordinator.resetGeneration == resetAfterA

            let bufferC = queue.makeCommandBuffer()!
            let pinC = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "A")]), generation: 1
            )
            let tailC = makeTail(
                device: device, token: "A", generation: 1, pin: pinC
            )
            let commitC = makeCommit(generation: 1, historyPin: pinC)
            seedPendingSuccess(
                coordinator: coordinator, identity: 3,
                commandBuffer: bufferC, tail: tailC, commit: commitC
            )
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(bufferC), observationID: coordinator.commandBufferRecords[ObjectIdentifier(bufferC)]?.observationID ?? 0, status: .completed
            )
            results["aSuccessBFailureCReusesAWithoutReset"] = reusedA
                && commitB.submissionPin.releaseCount == 1
                && pinB.releaseCount == 1
                && pinA.releaseCount == 1
                && !pinA.active && pinC.active
                && coordinator.committedTails[effect]?.historyPin === pinC
                && coordinator.resetGeneration == resetAfterA
        }

    }

}
