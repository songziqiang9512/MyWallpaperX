import Foundation
import Metal

enum SceneSubmissionAdmissionChecks {
    static func dependencyBindings(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            let binding = externalPrimaryBinding()
            let reservedTexture = makeTexture(device, "dependency-reservation")
            let reserved = dependencyInput(
                binding: binding,
                texture: reservedTexture
            )
            let exact = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture
                )
            )
            results["externalDependencyExactReadyMatchIssuesTicket"] =
                exact.reasonCode == "encoded"
                && exact.consumesExternalPrimaryDependency == true

            let missing = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: nil
            )
            results["externalDependencyMissingReadyRejected"] =
                missing.reasonCode == "prepared-frame-consumption-rejected"

            let wrongProvider = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    providerLayerID: binding.providerLayerID + 1
                )
            )
            results["externalDependencyWrongProviderRejected"] =
                wrongProvider.reasonCode
                    == "prepared-frame-consumption-rejected"

            let wrongSlot = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    slot: .init(
                        effectID: binding.slot.effectID,
                        passIndex: binding.slot.passIndex,
                        slotIndex: binding.slot.slotIndex + 1
                    )
                )
            )
            results["externalDependencyWrongSlotRejected"] =
                wrongSlot.reasonCode == "prepared-frame-consumption-rejected"

            let wrongBlend = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    blendMode: binding.blendMode == 5 ? 0 : 5
                )
            )
            results["externalDependencyWrongBlendRejected"] =
                wrongBlend.reasonCode == "prepared-frame-consumption-rejected"

            let stale = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    frameEpoch: reserved.frameEpoch + 1
                )
            )
            results["externalDependencyWrongEpochRejected"] =
                stale.reasonCode == "prepared-frame-consumption-rejected"

            let wrongObject = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: makeTexture(device, "dependency-ready-lookalike")
                )
            )
            results["externalDependencyWrongObjectRejected"] =
                wrongObject.reasonCode
                    == "prepared-frame-consumption-rejected"
        }

        do {
            let binding = externalPrimaryBinding(
                slotIndex: 1,
                blendMode: 0,
                kind: .geometryLayer,
                requiresResolvedMaterialProgram: true
            )
            let reservedTexture = makeTexture(
                device,
                "geometry-dependency-reservation"
            )
            let reserved = dependencyInput(
                binding: binding,
                texture: reservedTexture
            )
            let exact = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture
                )
            )
            results["geometryDependencyExactReadyMatchIssuesTicket"] =
                exact.reasonCode == "encoded"
                && exact.consumesExternalPrimaryDependency == true

            let wrongSlotBinding = externalPrimaryBinding(
                slotIndex: 2,
                blendMode: 0,
                kind: .geometryLayer,
                requiresResolvedMaterialProgram: true
            )
            let wrongSlot = executeExternalDependency(
                device: device,
                queue: queue,
                binding: wrongSlotBinding,
                preparedDependencyEffect: dependencyInput(
                    binding: wrongSlotBinding,
                    texture: reservedTexture
                ),
                readyDependencyEffect: dependencyInput(
                    binding: wrongSlotBinding,
                    texture: reservedTexture
                )
            )
            results["geometryDependencyWrongSlotRejected"] =
                wrongSlot.reasonCode != "encoded"
                && wrongSlot.consumesExternalPrimaryDependency != true
        }

        do {
            let binding = externalPrimaryBinding(
                slotIndex: 3,
                blendMode: 0,
                kind: .solidLayer
            )
            let reservedTexture = makeTexture(
                device,
                "solid-dependency-reservation"
            )
            let reserved = dependencyInput(
                binding: binding,
                texture: reservedTexture
            )
            let exact = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture
                )
            )
            results["solidDependencyExactReadyMatchIssuesTicket"] =
                exact.reasonCode == "encoded"
                && exact.consumesExternalPrimaryDependency == true

            let missing = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: nil
            )
            results["solidDependencyMissingReadyRejected"] =
                missing.reasonCode == "prepared-frame-consumption-rejected"

            let secondary = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    variant: .secondary
                )
            )
            results["solidDependencySecondaryRejected"] =
                secondary.reasonCode == "prepared-frame-consumption-rejected"

            let wrongEffect = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    slot: .init(
                        effectID: "wrong-effect",
                        passIndex: binding.slot.passIndex,
                        slotIndex: binding.slot.slotIndex
                    )
                )
            )
            results["solidDependencyWrongEffectRejected"] =
                wrongEffect.reasonCode == "prepared-frame-consumption-rejected"

            let wrongPass = executeExternalDependency(
                device: device,
                queue: queue,
                binding: binding,
                preparedDependencyEffect: reserved,
                readyDependencyEffect: dependencyInput(
                    binding: binding,
                    texture: reservedTexture,
                    slot: .init(
                        effectID: binding.slot.effectID,
                        passIndex: 1,
                        slotIndex: binding.slot.slotIndex
                    )
                )
            )
            results["solidDependencyWrongPassRejected"] =
                wrongPass.reasonCode == "prepared-frame-consumption-rejected"

            let programBinding = externalPrimaryBinding(
                slotIndex: 1,
                blendMode: 0,
                kind: .solidLayer,
                requiresResolvedMaterialProgram: true
            )
            let programReserved = dependencyInput(
                binding: programBinding,
                texture: reservedTexture
            ).withContent(.data)
            let programExact = executeExternalDependency(
                device: device,
                queue: queue,
                binding: programBinding,
                preparedDependencyEffect: programReserved,
                readyDependencyEffect: dependencyInput(
                    binding: programBinding,
                    texture: reservedTexture
                ).withContent(.data)
            )
            results["solidProgramDependencySlotOneIssuesTicket"] =
                programExact.reasonCode == "encoded"
                && programExact.consumesExternalPrimaryDependency == true
            let changedContent = executeExternalDependency(
                device: device, queue: queue, binding: programBinding,
                preparedDependencyEffect: programReserved,
                readyDependencyEffect: dependencyInput(
                    binding: programBinding, texture: reservedTexture
                )
            )
            results["solidProgramDependencyContentDriftRejected"] =
                changedContent.reasonCode == "prepared-frame-consumption-rejected"

        }

    }

    static func capabilityAndTargetAdmission(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            let coordinator = makeCoordinator(device)
            let admitted: Bool
            switch coordinator.preflightClaim(layerID: 7) {
            case .claimed: admitted = true
            case .rejected, .notMigrated: admitted = false
            }
            results["claimUsesCentralCapabilityAdmission"] = admitted
                && coordinator.frameClaimed == 0
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 2, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let rejectedBeforePrepare: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                rejectedBeforePrepare = reasonCode == "frame-candidate-not-prepared"
            case .claimed, .notMigrated:
                rejectedBeforePrepare = false
            }
            let emptyOutcome = coordinator.prepareFrame(
                [],
                pool: nil,
                commandBuffer: buffer
            )
            let emptyReady: Bool
            if case .ready = emptyOutcome { emptyReady = true }
            else { emptyReady = false }
            results["claimWaitsForAtomicFramePreparation"] =
                rejectedBeforePrepare
                && emptyReady
                && coordinator.framePreparationComplete
                && coordinator.frameClaimed == 0
                && coordinator.activeByID.isEmpty
                && coordinator.sealFrame(on: buffer)
            _ = coordinator.endFrame()
        }

        do {
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(
                    device: device,
                    layerID: 7,
                    generation: 1,
                    discardedPersistentTargetState: true
                ),
            ]
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            guard case let .claimed(claim) = coordinator.preflightClaim(
                layerID: 7
            ) else { fatalError("discard fixture claim unavailable") }
            let targets = makeAtomicTargets(layerID: 7, generation: 1)
            let pool = SceneOffscreenTexturePool(prepared: targets.prepared)
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: .init(
                        token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                    ),
                    sourceTexture: makeTexture(device, "discard-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    frameInputs: .fixture
                )],
                pool: pool,
                commandBuffer: buffer
            )
            let ready: Bool
            if case .ready = outcome { ready = true }
            else { ready = false }
            results["typedHistoryDiscardReachesPoolExactly"] =
                ready
                && pool.batchCommitCount == 1
                && pool.discardedHistoryEffectsByCommit == [
                    [Set([effect(for: 7)])],
                ]
                && targets.commit.historyPinsByEffect.isEmpty
            _ = coordinator.endFrame()
            targets.commit.releaseAll()
        }

        do {
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(
                    device: device,
                    layerID: 7,
                    generation: 1,
                    discardedPersistentTargetState: true,
                    forgedDiscardTransaction: true
                ),
            ]
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 4, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            guard case let .claimed(claim) = coordinator.preflightClaim(
                layerID: 7
            ) else { fatalError("forged discard fixture claim unavailable") }
            let targets = makeAtomicTargets(layerID: 7, generation: 1)
            let pool = SceneOffscreenTexturePool(prepared: targets.prepared)
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: .init(
                        token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                    ),
                    sourceTexture: makeTexture(device, "forged-discard-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    frameInputs: .fixture
                )],
                pool: pool,
                commandBuffer: buffer
            )
            let reason: String
            if case let .rejected(value) = outcome { reason = value }
            else { reason = "ready" }
            results["forgedHistoryDiscardRejectedBeforePoolCommit"] =
                reason == "persistent-allocation-commit-rejected"
                && pool.batchCommitCount == 0
                && pool.discardedHistoryEffectsByCommit.isEmpty
            _ = coordinator.endFrame()
            targets.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

    }

    static func fallbackAndFrameConsumption(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            let coordinator = makeCoordinator(device, resolvesClaims: false)
            coordinator.frameIsActive = true
            let reason: String
            switch coordinator.preflightClaim(layerID: 7) {
            case let .rejected(reasonCode): reason = reasonCode
            case .claimed: reason = "claimed"
            case .notMigrated: reason = "not-migrated"
            }
            coordinator.recordClaimedFailure(reasonCode: reason)
            results["invalidCapabilityTokenRejectsWithoutLegacyFallback"] =
                reason == "execution-capability-token-invalid"
                && coordinator.frameClaimed == 0
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 21, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let reason = "frame-target-plan-unsupported-target-descriptor"
            let installed = coordinator.installFrameLocalFallbacks([7: reason])
            let rejectedWithTypedReason: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                rejectedWithTypedReason = reasonCode == reason
            case .claimed, .notMigrated:
                rejectedWithTypedReason = false
            }
            results["typedTargetDescriptorFallbackRemainsLayerLocal"] =
                installed && rejectedWithTypedReason
                && recorder.lines.contains {
                    $0.contains("layer-local-fallback count=1 entries=7:\(reason)")
                }
        }

        for (reason, resultKey) in [
            ("utility-composition-subtree-source-coverage-unavailable",
             "utilitySubtreeCoverageFallbackRemainsLayerLocal"),
            ("layer-source-not-ready", "pendingSourceFallbackRemainsLayerLocal")
        ] {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 22, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let installed = coordinator.installFrameLocalFallbacks([7: reason])
            let rejectedWithTypedReason: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                rejectedWithTypedReason = reasonCode == reason
            case .claimed, .notMigrated:
                rejectedWithTypedReason = false
            }
            let preparedWithoutRootTarget: Bool
            switch coordinator.prepareFrame([], pool: nil, commandBuffer: buffer) {
            case .ready:
                preparedWithoutRootTarget = true
            case .rejected:
                preparedWithoutRootTarget = false
            }
            let frameStayedLocal = !coordinator.frameRequiresDrop
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            let audit = coordinator.endFrame().joined(separator: "\n")
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 23, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init()
            )
            let recoverable: Bool
            if case .claimed = coordinator.preflightClaim(layerID: 7) {
                recoverable = coordinator.frameLocalFallbacks.isEmpty
            } else { recoverable = false }
            results[resultKey] =
                installed && rejectedWithTypedReason
                && preparedWithoutRootTarget && frameStayedLocal && sealed && recoverable
                && buffer.status == .completed
                && audit.contains("failures=0")
                && audit.contains("localFallbacks=1")
                && recorder.lines.contains {
                    $0.contains("layer-local-fallback count=1 entries=7:\(reason)")
                }
        }

        do {
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                logSink: { recorder.append($0) }
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.frameIsActive = true
            coordinator.frame = .init(frameIndex: 1)
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(value): claim = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let targetPlan = SceneResolvedMaterialFrameTargetPlan(
                token: claim.token,
                allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
            )
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: targetPlan,
                    sourceTexture: makeTexture(device, "preflight-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    frameInputs: .fixture
                )],
                pool: .init(),
                commandBuffer: buffer
            )
            let expected = "graph-preflight-fixture-preflight-unavailable"
            let reason: String
            switch outcome {
            case let .rejected(value): reason = value
            case .ready: reason = "ready"
            }
            results["preflightFailureReasonReachesCoordinatorEvidence"] =
                reason == expected
                && recorder.lines.contains {
                    $0.contains("axis=graph-execution diagnostic=\(expected)")
                }
                && coordinator.frameClaimed == 0
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
        }

        do {
            let coordinator = makeCoordinator(device)
            let buffer = queue.makeCommandBuffer()!
            let prepared = makePrepared(device: device)
            let firstCommit = makeCommit(generation: 1)
            let secondCommit = makeCommit(generation: 1)
            coordinator.frameIsActive = true
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: buffer, prepared: prepared,
                commit: firstCommit, phase: .allocationCommitted,
                claimed: false
            )
            coordinator.activeByID[2] = makeLedger(
                coordinator: coordinator, identity: 2,
                commandBuffer: buffer, prepared: prepared,
                commit: secondCommit, phase: .allocationCommitted
            )
            coordinator.activeTransactions = [1, 2]
            coordinator.preparedLedgerByLayerID = [7: 1]
            coordinator.framePreparationComplete = true
            let claimed: Bool
            switch coordinator.claim(layerID: 7) {
            case .claimed: claimed = true
            case .rejected: claimed = false
            case .notMigrated: claimed = false
            }
            coordinator.recordClaimedFailure(reasonCode: "post-claim-failed")
            results["postClaimFailureDropsWholeFrame"] = claimed
                && coordinator.frameClaimed == 1
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
                && coordinator.activeByID.isEmpty
                && firstCommit.submissionPin.releaseCount == 1
                && secondCommit.submissionPin.releaseCount == 1
                && coordinator.resetGeneration == 1
        }

        do {
            let coordinator = makeCoordinator(device)
            let firstBuffer = queue.makeCommandBuffer()!
            let foreignBuffer = queue.makeCommandBuffer()!
            let commit = makeCommit(generation: 1)
            coordinator.frameIsActive = true
            coordinator.frame = .init(frameIndex: 1)
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator, identity: 1,
                commandBuffer: firstBuffer,
                prepared: makePrepared(device: device),
                commit: commit, phase: .allocationCommitted
            )
            coordinator.activeTransactions = [1]
            coordinator.preparedLedgerByLayerID = [7: 1]
            coordinator.framePreparationComplete = true
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(value): claim = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let outcome = coordinator.executeClaimed(
                claim: claim,
                dependencyEffects: [],
                commandBuffer: foreignBuffer
            )
            let reason: String
            switch outcome {
            case let .failed(value): reason = value
            case .encoded: reason = "encoded"
            }
            results["foreignBufferRejectedBeforePrepare"] =
                reason == "prepared-frame-consumption-rejected"
                && SceneResolvedMaterialGraphExecutor.prepareCallCount == 0
                && coordinator.activeByID.isEmpty
                && commit.submissionPin.releaseCount == 1
        }

    }

}
