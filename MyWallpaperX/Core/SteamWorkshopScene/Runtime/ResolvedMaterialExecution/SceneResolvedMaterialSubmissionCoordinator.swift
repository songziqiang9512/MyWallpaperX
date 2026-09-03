import Foundation
import Metal

/// Owns the atomic boundary from a prepared graph candidate through GPU
/// completion. Only the terminalizer removes a prepared ledger.
final class SceneResolvedMaterialSubmissionCoordinator: @unchecked Sendable {
    typealias Bridge = SceneResolvedMaterialRuntimeBridge
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    typealias LogSink = Bridge.LogSink
    typealias Commit = ScenePreparedPersistentGraphTargets.Commit

    static let maximumTransactionsPerSubmission = 1_024
    static let maximumPendingSubmissions =
        SceneResolvedMaterialInFlightCapacity.maximumSubmissions
    static let maximumTransitionsPerTransaction =
        SceneResolvedMaterialExecutionCapabilityAdmission.maximumEffectsPerLayer
    static let maximumTransitionsPerSubmission = 1_024
    static let maximumObservedNodesPerSubmission =
        SceneResolvedMaterialExecutionCapabilityAdmission.maximumNodesPerLayer
    struct Tail {
        let state: State
        /// Exactly the readable history closure; pair and scratch resources
        /// never survive GPU completion in a tail.
        let persistentResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let historyPin: SceneGraphRenderTargetResidencyPin?
        let mappingGeneration: UInt64
    }

    struct CandidateBlueprint {
        let states: [Graph.EffectKey: State]
        let resources: [
            Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]
        ]
        let mappingGenerations: [Graph.EffectKey: UInt64]
        let resetReasons: [Graph.EffectKey: SceneGraphExecutionResetReason]
    }

    enum LedgerPhase: Int {
        case prepared, allocationCommitted, encoded, outputConsumed, sealed
    }

    struct PreparedLedger {
        let identity, epoch, frameIndex: UInt64
        let layerID: Int
        let capabilityToken:
            SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph
        let preparedDependencyEffect: SceneDependencyEffectInput?
        let preparedDependencyUnavailability:
            Bridge.FrameInputs.DependencyUnavailability?
        let commandBuffer: MTLCommandBuffer
        let committedBaseTails: [Graph.EffectKey: Tail]
        var blueprint: CandidateBlueprint?
        var candidateTails: [Graph.EffectKey: Tail]?
        var commit: Commit?
        var phase: LedgerPhase = .prepared
        var claimConsumed = false
        var ticketConsumed = false
        var outputConsumed = false
        var compositorConsumed = false
        var submissionID: UInt64?
    }

    struct PendingSubmission {
        let identity: UInt64
        let ledgerIDs: [UInt64]
        let commandBufferIdentities: Set<ObjectIdentifier>
        let finalTails: [Graph.EffectKey: Tail]
        let successObservationsByLedger: [
            UInt64: [SceneGraphExecutionObservation]
        ]
        var gpuStatus: SceneGraphExecutionGPUCompletionStatus?
        var cancellationReason: String?
        var retiredHistoryPins: [SceneGraphRenderTargetResidencyPin]
    }

    struct CommandBufferRecord {
        let buffer: MTLCommandBuffer
        var terminalStatus: SceneGraphExecutionGPUCompletionStatus?
    }

    struct Emission {
        var observations: [SceneGraphExecutionObservation] = []
        var diagnostics: [String] = []

        mutating func append(_ other: Self) {
            observations.append(contentsOf: other.observations)
            diagnostics.append(contentsOf: other.diagnostics)
        }
    }

    let executor: SceneResolvedMaterialGraphExecutor?
    let capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    let telemetry: SceneGraphExecutionTelemetry
    let logSink: LogSink
    let capturesExecutionObservations: Bool
    let lock = NSLock()
    /// Scopes transaction and allocation counters to this coordinator lifetime.
    /// It is deliberately independent from replaceable physical texture pools.
    let runtimeInstanceIdentity = UUID().uuidString.lowercased()

    var frame: SceneResolvedMaterialFrameSnapshot?
    var frameFailure: SceneResolvedMaterialFailure?
    var frameIsActive = false
    var frameSealed = false
    var frameRequiresDrop = false
    var frameWaitsForPendingSubmission = false
    var committedTails: [Graph.EffectKey: Tail] = [:]
    var scheduledTails: [Graph.EffectKey: Tail] = [:]
    var activeByID: [UInt64: PreparedLedger] = [:]
    /// Ordered ledgers belonging to the currently open command-buffer frame.
    var activeTransactions: [UInt64] = []
    var preparedLedgerByLayerID: [Int: UInt64] = [:]
    var frameLocalFallbacks: [Int: String] = [:]
    var framePreparationComplete = false
    var pendingSubmissions: [PendingSubmission] = []
    var commandBufferRecords: [ObjectIdentifier: CommandBufferRecord] = [:]
    var nextTransactionID: UInt64 = 0
    var nextSubmissionID: UInt64 = 0
    var executionEpoch: UInt64 = 1
    var effectGeneration: UInt64 = 1
    var resetGeneration: UInt64 = 1
    var resetReasonByGeneration: [UInt64: SceneGraphExecutionResetReason] = [:]
    var terminalFailureReason: String?
    var frameClaimed = 0
    var frameEncoded = 0
    var frameFailures = 0
    var frameDeferred = 0
    var lastReportSignature: String?
    var lastLocalFallbackSignature: String?

    init(
        device: MTLDevice,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        capturesExecutionObservations: Bool = true,
        logSink: @escaping LogSink
    ) {
        self.capabilities = capabilities
        executor = .init(device: device, capabilities: capabilities)
        telemetry = .init(logSink: logSink)
        self.logSink = logSink
        self.capturesExecutionObservations = capturesExecutionObservations
    }

    func installFrameLocalFallbacks(_ fallbacks: [Int: String]) -> Bool {
        let allowedReasons: Set<String> = [
            "function-invocation-unknown-effect",
            "function-invocation-unknown-function",
            "frame-target-plan-rejected",
            "frame-target-plan-unsupported-target-descriptor",
            "utility-composition-subtree-source-coverage-unavailable",
        ]
        var diagnostic: String?
        lock.lock()
        guard frameIsActive, !framePreparationComplete,
              !frameRequiresDrop, frameFailure == nil,
              frameLocalFallbacks.isEmpty,
              fallbacks.allSatisfy({ layerID, reasonCode in
                  capabilities.claim(layerID: layerID) != nil
                      && allowedReasons.contains(reasonCode)
              }) else {
            lock.unlock()
            return false
        }
        frameLocalFallbacks = fallbacks
        let entries = fallbacks.keys.sorted().compactMap { layerID in
            fallbacks[layerID].map { "\(layerID):\($0)" }
        }.joined(separator: ",")
        let signature = "count=\(fallbacks.count) entries=\(entries)"
        if !fallbacks.isEmpty, signature != lastLocalFallbackSignature {
            lastLocalFallbackSignature = signature
            diagnostic = "layer-local-fallback \(signature)"
        }
        lock.unlock()
        if let diagnostic {
            logSink(
                "MWX DEBUG SCENE: schema=1 axis=graph-execution diagnostic=\(diagnostic)"
            )
        }
        return true
    }

    /// A rollback suffix keeps every predecessor allocation pinned until all
    /// dependent command buffers reach a terminal callback. No new frame may
    /// derive state from that suffix even when nominal capacity remains.
    func submissionQueueAcceptsFrameLocked() -> Bool {
        pendingSubmissions.count < Self.maximumPendingSubmissions
            && pendingSubmissions.allSatisfy {
                $0.cancellationReason == nil && $0.finalTails.isEmpty
            }
    }

    func restoreScheduledTailsLocked() {
        scheduledTails = pendingSubmissions.last(where: {
            $0.cancellationReason == nil
        })?.finalTails ?? committedTails
    }

    func prepareFrame(
        _ requests: [Bridge.FramePreparationRequest],
        pool: SceneOffscreenTexturePool?,
        commandBuffer: MTLCommandBuffer
    ) -> Bridge.FramePreparationResult {
        var emission = Emission()
        lock.lock()
        guard terminalFailureReason == nil, frameIsActive,
              !frameRequiresDrop, !frameWaitsForPendingSubmission,
              frameFailure == nil, let frame,
              !framePreparationComplete,
              activeTransactions.isEmpty,
              preparedLedgerByLayerID.isEmpty else {
            let reason = terminalFailureReason ?? (frameRequiresDrop
                ? "frame-command-buffer-invalidated" : "frame-envelope-invalid")
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }
        guard commandBuffer.status == .notEnqueued,
              requests.count <= Self.maximumTransactionsPerSubmission,
              Set(requests.map { $0.claim.layerID }).count == requests.count,
              Set(requests.map { $0.claim.token }).count == requests.count,
              nextTransactionID <= UInt64.max - UInt64(requests.count) else {
            let reason = commandBuffer.status == .notEnqueued
                ? "frame-preparation-capacity" : "transaction-armed-after-submit"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }
        guard !requests.isEmpty else {
            framePreparationComplete = true
            lock.unlock()
            return .ready
        }
        guard let executor, let pool else {
            let reason = executor == nil
                ? "graph-executor-unavailable" : "frame-target-pool-unavailable"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }
        guard observeCommandBufferLocked(commandBuffer) else {
            let reason = "command-buffer-observer-install-rejected"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }

        guard requests.allSatisfy({ request in
            let claim = request.claim
            guard request.targetPlan.token == claim.token,
                  request.targetPlan.allocation.graphPlan.key.layerID
                    == claim.layerID,
                  let capability = capabilities.resolve(claim.token),
                  capability.layerID == claim.layerID,
                  capability.pairPlan.layerID == claim.layerID,
                  capability.effectSubjectsAreConserved,
                  capability.dependencyOwnership == claim.dependencyOwnership,
                  dependencyReservationMatches(
                      request.frameInputs.dependencyEffect,
                      unavailability:
                        request.frameInputs.dependencyUnavailability,
                      ownership: claim.dependencyOwnership
                  ), sceneBackgroundReservationMatches(
                      request.sceneBackgroundResource,
                      requirement: claim.sceneBackgroundRequirement,
                      frameEpoch: frame.textureRegistrySnapshot.frameEpoch
                  ) else { return false }
            return true
        }) else {
            let reason = "frame-preparation-request-ownership-mismatch"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }
        let targetAllocations = requests.map { $0.targetPlan.allocation }
        switch pool.preflightPersistentGraphTargets(targetAllocations) {
        case .ready:
            break
        case .temporarilyBlocked:
            let reason = "frame-target-plan-temporarily-blocked"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        case let .rejected(reasonCode):
            emission = framePreparationFailureLocked([], reason: reasonCode)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reasonCode)
        }
        guard let preparedTargets = pool.preparePersistentGraphTargets(
            framePlans: targetAllocations
        ) else {
            let reason = "frame-target-plan-allocation-failed"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }

        var candidates: [PreparedFrameCandidate] = []
        var provisionalTails = scheduledTails
        let externallyConsumedProviderLayerIDs = Set(requests.compactMap {
            request -> Int? in
            guard case let .externalPrimary(binding) =
                request.claim.dependencyOwnership else { return nil }
            return binding.providerLayerID
        })
        for index in requests.indices {
            let request = requests[index]
            let claim = request.claim
            let targets = preparedTargets[index]
            let preparedDependencyEffect: SceneDependencyEffectInput?
            let preparedDependencyUnavailability =
                request.frameInputs.dependencyUnavailability
            switch claim.dependencyOwnership {
            case .none, .graphInternal:
                preparedDependencyEffect = request.frameInputs.dependencyEffect
            case let .externalPrimary(binding):
                let original = request.frameInputs.dependencyEffect
                let providerCandidates = candidates.filter {
                    $0.layerID == binding.providerLayerID
                }
                guard providerCandidates.count <= 1 else {
                    let reason = "prepared-provider-output-ambiguous"
                    emission = framePreparationFailureLocked(
                        candidates, reason: reason
                    )
                    lock.unlock()
                    emit(emission)
                    return .rejected(reasonCode: reason)
                }
                if preparedDependencyUnavailability != nil {
                    guard original == nil, providerCandidates.isEmpty else {
                        let reason = "prepared-provider-unavailability-mismatch"
                        emission = framePreparationFailureLocked(
                            candidates, reason: reason
                        )
                        lock.unlock()
                        emit(emission)
                        return .rejected(reasonCode: reason)
                    }
                    preparedDependencyEffect = nil
                } else if let provider = providerCandidates.first {
                    guard let original,
                          original.providerLayerID == provider.layerID else {
                        let reason = "prepared-provider-input-mismatch"
                        emission = framePreparationFailureLocked(
                            candidates, reason: reason
                        )
                        lock.unlock()
                        emit(emission)
                        return .rejected(reasonCode: reason)
                    }
                    // The provider's graph target may be reused by a later
                    // transaction in the same frame. Keep the independently
                    // reserved named target as the consumer input; the
                    // renderer copies the provider final into it between the
                    // ordered transactions.
                    preparedDependencyEffect = original
                } else {
                    preparedDependencyEffect = original
                }
            }
            let frameInputs = request.frameInputs
                .withDependencyEffect(preparedDependencyEffect)
            let result = executor.prepare(
                token: claim.token,
                leases: targets.leases,
                historyRehydrateCopiesByEffect:
                    targets.historyRehydrateCopiesByEffect,
                frame: frame,
                sceneBackgroundResource: request.sceneBackgroundResource,
                sourceTexture: request.sourceTexture,
                sourceUniforms: request.sourceUniforms,
                sourcePipeline: request.sourcePipeline,
                frameInputs: frameInputs,
                commandBuffer: commandBuffer,
                previousStates: provisionalTails.mapValues(\.state),
                previousGraphResources:
                    provisionalTails.mapValues(\.persistentResources),
                materialFunctionInvocations:
                    request.materialFunctionInvocations,
                effectGeneration: effectGeneration,
                resetGeneration: resetGeneration
            )
            guard case let .success(prepared) = result else {
                let reason: String
                switch result {
                case let .failure(failure):
                    if failure == .graphStructureRejected {
                        reason = "graph-preflight-\(failure.rawValue)"
                            + "-layer-\(claim.layerID)"
                    } else {
                        reason = "graph-preflight-\(failure.rawValue)"
                    }
                    let hasCapturedMainSource: Bool
                    if case .capturedMainTargetTexture = claim.sourceRoute {
                        hasCapturedMainSource = true
                    } else {
                        hasCapturedMainSource = false
                    }
                    if failure.isColorContractVisualRejection,
                       hasCapturedMainSource,
                       claim.dependencyOwnership == .none,
                       !externallyConsumedProviderLayerIDs.contains(claim.layerID) {
                        let fallbackReason =
                            "captured-main-color-contract-unproven"
                        frameLocalFallbacks[claim.layerID] = fallbackReason
                        let entries = frameLocalFallbacks.keys.sorted()
                            .compactMap { layerID in
                                frameLocalFallbacks[layerID].map {
                                    "\(layerID):\($0)"
                                }
                            }.joined(separator: ",")
                        let signature = "count=\(frameLocalFallbacks.count)"
                            + " entries=\(entries)"
                        if signature != lastLocalFallbackSignature {
                            lastLocalFallbackSignature = signature
                            emission.diagnostics.append(
                                "layer-local-fallback \(signature)"
                                    + " preflight=\(failure.rawValue)"
                            )
                        }
                        continue
                    }
                case .success:
                    reason = "graph-preflight-result-invariant"
                }
                emission = framePreparationFailureLocked(
                    candidates, reason: reason
                )
                lock.unlock()
                emit(emission)
                return .rejected(reasonCode: reason)
            }
            guard let blueprint = candidateBlueprintLocked(
                for: prepared,
                startingAt: provisionalTails
            ), candidateIsCommitReadyLocked(
                targets: targets,
                prepared: prepared,
                blueprint: blueprint
            ), let tails = provisionalCandidateTailsLocked(
                blueprint: blueprint,
                startingAt: provisionalTails,
                prepared: prepared
            ) else {
                let reason = "persistent-allocation-commit-rejected"
                emission = framePreparationFailureLocked(
                    candidates, reason: reason
                )
                lock.unlock()
                emit(emission)
                return .rejected(reasonCode: reason)
            }
            candidates.append(.init(
                layerID: claim.layerID,
                capabilityToken: claim.token,
                prepared: prepared,
                preparedDependencyEffect: preparedDependencyEffect,
                preparedDependencyUnavailability:
                    preparedDependencyUnavailability,
                commandBuffer: commandBuffer,
                committedBaseTails: committedTails,
                blueprint: blueprint,
                targets: targets
            ))
            provisionalTails = tails
        }

        guard preparedEvidenceFitsLocked(candidates.map(\.prepared)) else {
            let reason = "execution-evidence-capacity"
            emission = framePreparationFailureLocked(candidates, reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }
        let commits: [Commit]
        if candidates.isEmpty {
            commits = []
        } else {
            guard let committed = pool.commitAndPinPersistentGraphTargets(
                candidates.map(\.targets),
                historyTokensByTarget: candidates.map {
                    $0.prepared.historyTokensByEffect
                },
                discardedHistoryEffectsByTarget: candidates.map { candidate in
                    Set(candidate.prepared.stages.compactMap { stage in
                        stage.discardedPersistentTargetState ? stage.effect : nil
                    })
                },
                commandBuffer: commandBuffer
            ) else {
                let reason = "persistent-allocation-commit-rejected"
                emission = framePreparationFailureLocked(
                    candidates, reason: reason
                )
                lock.unlock()
                emit(emission)
                return .rejected(reasonCode: reason)
            }
            commits = committed
        }

        let firstIdentity = nextTransactionID + 1
        nextTransactionID += UInt64(candidates.count)
        var candidateTails = scheduledTails
        for (offset, pair) in zip(candidates, commits).enumerated() {
            let (candidate, commit) = pair
            candidateTails = committedCandidateTailsLocked(
                blueprint: candidate.blueprint,
                startingAt: candidateTails,
                commit: commit,
                prepared: candidate.prepared
            )
            let identity = firstIdentity + UInt64(offset)
            activeByID[identity] = .init(
                identity: identity,
                epoch: executionEpoch,
                frameIndex: frame.frameIndex,
                layerID: candidate.layerID,
                capabilityToken: candidate.capabilityToken,
                prepared: candidate.prepared,
                preparedDependencyEffect: candidate.preparedDependencyEffect,
                preparedDependencyUnavailability:
                    candidate.preparedDependencyUnavailability,
                commandBuffer: candidate.commandBuffer,
                committedBaseTails: candidate.committedBaseTails,
                blueprint: candidate.blueprint,
                candidateTails: candidateTails,
                commit: commit,
                phase: .allocationCommitted
            )
            activeTransactions.append(identity)
            preparedLedgerByLayerID[candidate.layerID] = identity
        }
        framePreparationComplete = true
        lock.unlock()
        emit(emission)
        return .ready
    }

    func preparedOutputTexturesByLayerID() -> [Int: MTLTexture]? {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, framePreparationComplete,
              !frameRequiresDrop, frameFailure == nil else { return nil }
        var result: [Int: MTLTexture] = [:]
        for identity in activeTransactions {
            guard let ledger = activeByID[identity],
                  ledger.phase == .allocationCommitted,
                  result.updateValue(
                      ledger.prepared.finalTexture,
                      forKey: ledger.layerID
                  ) == nil else {
                return nil
            }
        }
        return result
    }

}
