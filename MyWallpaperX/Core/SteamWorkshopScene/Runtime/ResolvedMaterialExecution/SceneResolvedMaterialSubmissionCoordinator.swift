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
        case prepared, allocationCommitted, encoded, composited, sealed
    }

    struct PreparedLedger {
        let identity, epoch, frameIndex: UInt64
        let layerID: Int
        let capabilityToken:
            SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph
        let preparedDependencyEffect: SceneDependencyEffectInput?
        let commandBuffer: MTLCommandBuffer
        let committedBaseTails: [Graph.EffectKey: Tail]
        var blueprint: CandidateBlueprint?
        var candidateTails: [Graph.EffectKey: Tail]?
        var commit: Commit?
        var phase: LedgerPhase = .prepared
        var claimConsumed = false
        var ticketConsumed = false
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
    let lock = NSLock()

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
        logSink: @escaping LogSink
    ) {
        self.capabilities = capabilities
        executor = .init(device: device, capabilities: capabilities)
        telemetry = .init(logSink: logSink)
        self.logSink = logSink
    }

    func installFrameLocalFallbacks(_ fallbacks: [Int: String]) -> Bool {
        let allowedReasons: Set<String> = [
            "function-invocation-unknown-effect",
            "function-invocation-unknown-function",
            "frame-target-plan-rejected",
            "frame-target-plan-unsupported-target-descriptor",
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
                      request.dedicatedInputs.dependencyEffect,
                      ownership: claim.dependencyOwnership
                  ), sceneBackgroundReservationMatches(
                      request.sceneBackgroundResource,
                      requirement: claim.sceneBackgroundRequirement,
                      frameEpoch: frame.textureRegistrySnapshot.frameEpoch
                  ) else { return false }
            return true
        }), let preparedTargets = pool.preparePersistentGraphTargets(
            framePlans: requests.map { $0.targetPlan.allocation }
        ) else {
            let reason = "frame-target-plan-consumption-failed"
            emission = framePreparationFailureLocked([], reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
        }

        var candidates: [PreparedFrameCandidate] = []
        var provisionalTails = scheduledTails
        for index in requests.indices {
            let request = requests[index]
            let claim = request.claim
            let targets = preparedTargets[index]
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
                dedicatedInputs: request.dedicatedInputs,
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
                    reason = "graph-preflight-\(failure.rawValue)"
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
                preparedDependencyEffect: request.dedicatedInputs.dependencyEffect,
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
        guard let commits = pool.commitAndPinPersistentGraphTargets(
            candidates.map(\.targets),
            historyTokensByTarget: candidates.map {
                $0.prepared.historyTokensByEffect
            },
            commandBuffer: commandBuffer
        ) else {
            let reason = "persistent-allocation-commit-rejected"
            emission = framePreparationFailureLocked(candidates, reason: reason)
            lock.unlock()
            emit(emission)
            return .rejected(reasonCode: reason)
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
        return .ready
    }

}
