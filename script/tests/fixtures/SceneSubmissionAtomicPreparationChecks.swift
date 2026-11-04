import Foundation
import Metal

enum SceneSubmissionAtomicPreparationChecks {
    static func lateHistoryRollback(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        for mode in ["restore", "discard", "uncovered"] {
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.prepareCalls = []
            SceneResolvedMaterialGraphExecutor.encodeInputs = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            defer {
                SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
                SceneResolvedMaterialGraphExecutor.preparedResponsesByToken = [:]
                SceneResolvedMaterialGraphExecutor.prepareCalls = []
                SceneResolvedMaterialGraphExecutor.encodeInputs = []
            }
            let temporary = Graph.TextureIdentity(kind: .framebuffer,
                layerID: 7, effect: effect, name: "swap-temporary")
            let tokenA = State.PhysicalToken(rawValue: "history-A")
            let tokenB = State.PhysicalToken(rawValue: "history-B")
            let tokenC = State.PhysicalToken(rawValue: "foreign-history-C")
            let versionA = State.VersionedResource(token: tokenA, contentGeneration: 1)
            let versionB = State.VersionedResource(token: tokenB, contentGeneration: 1)
            let versionC = State.VersionedResource(token: tokenC, contentGeneration: 1)
            let before = [historyIdentity: versionA, temporary: versionB]
            let after = [historyIdentity: versionB, temporary: versionA]
            let foreign = [historyIdentity: versionA, temporary: versionC]
            let textureA = makeTexture(device, "history-A")
            let textureB = makeTexture(device, "history-B")
            let beforeResources = [
                historyIdentity: makeResource(texture: textureA, token: tokenA.rawValue, generation: 1),
                temporary: makeResource(identity: temporary, texture: textureB, token: tokenB.rawValue, generation: 1),
            ]
            let afterResources = [
                historyIdentity: makeResource(texture: textureB, token: tokenB.rawValue, generation: 1),
                temporary: makeResource(identity: temporary, texture: textureA, token: tokenA.rawValue, generation: 1),
            ]
            let foreignResources = [historyIdentity: beforeResources[historyIdentity]!,
                temporary: makeResource(identity: temporary, texture: makeTexture(device, "history-C"),
                    token: tokenC.rawValue, generation: 1)]
            let closure: Set<Graph.TextureIdentity> = [historyIdentity, temporary]
            let baseState = State(effectGeneration: 1, resetGeneration: 1, allocationGeneration: 1,
                logicalMapping: before, historyLogicalIdentities: [historyIdentity], historyClosureIdentities: closure)
            let output = makeAtomicPrepared(device: device, layerID: 7, generation: 1).stages[0]
            // These are literal executor responses, not a second rollback implementation.
            func response(mapping: [Graph.TextureIdentity: State.VersionedResource],
                resources: [Graph.TextureIdentity: SceneFrameTextureResource],
                intents: [State.Intent], tokens: Set<State.PhysicalToken>,
                failed: Bool = false, discarded: Bool = false
            ) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
                let graph = Graph(layerID: 7, effects: [.init(key: effect)],
                    nodes: [.init(nodeIndex: 0, kind: .swap, commandSource: historyIdentity, commandTarget: temporary)],
                    renderTargets: [historyIdentity, temporary])
                let stage = SceneResolvedMaterialGraphExecutor.PreparedStage(effect: effect, graph: graph,
                    pairStep: .init(effect: effect, inputIdentity: output.pairStep.inputIdentity,
                        outputIdentity: output.pairStep.outputIdentity, inputMember: .zero,
                        outputMember: .zero, nodes: [.init(nodeIndex: 0, kind: .swap, rotatesAfterNode: false)]),
                    transition: .init(nextState: .init(effectGeneration: 1, resetGeneration: 1, allocationGeneration: 1,
                        logicalMapping: mapping, historyLogicalIdentities: discarded ? [] : [historyIdentity],
                        historyClosureIdentities: discarded ? [] : closure),
                        transaction: .init(intents: intents, mappingBefore: discarded ? [:] : before,
                            mappingAfter: mapping, allocationGeneration: 1, effectGeneration: 1, resetGeneration: 1)),
                    inputWidth: 2, inputHeight: 2, fullFramePairIsShared: false, fullFramePairGeneration: 1,
                    historyRehydrateCopyCount: 0, historyContentDiscarded: false,
                    frameResources: resources, persistentResources: resources,
                    effectOutputResource: output.effectOutputResource, programCacheKeys: ["literal-swap"],
                    effectLocalFailureReasonCode: failed ? "material-finalizer-named-provider-unavailable" : nil,
                    effectLocalActivationBypassReasonCode: nil, discardedPersistentTargetState: discarded)
                return .init(stages: [stage], finalResource: stage.effectOutputResource,
                    finalTexture: stage.effectOutputResource.publication.texture,
                    historyTokensByEffect: tokens.isEmpty ? [:] : [effect: tokens])
            }
            let original = response(mapping: after, resources: afterResources,
                intents: [.swap(nodeIndex: 0, commandOrdinal: 0, source: historyIdentity,
                    sourceResource: versionA, target: temporary, targetResource: versionB)], tokens: [tokenA, tokenB])
            let replacement = mode == "discard"
                ? response(mapping: [:], resources: [:], intents: [], tokens: [], failed: true, discarded: true)
                : response(mapping: mode == "restore" ? before : foreign,
                    resources: mode == "restore" ? beforeResources : foreignResources,
                    intents: [], tokens: mode == "restore" ? [tokenA, tokenB] : [tokenA, tokenC], failed: true)
            SceneResolvedMaterialGraphExecutor.preparedByToken = [7: original]
            SceneResolvedMaterialGraphExecutor.preparedResponsesByToken = [7: [original, replacement]]
            let binding = externalPrimaryBinding(kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let reserved = dependencyInput(binding: binding, texture: makeTexture(device, "history-provider"), frameEpoch: 23)
            let coordinator = makeCoordinator(device, dependencyOwnershipByLayerID: [7: .externalPrimary(binding)])
            let oldPin = SceneGraphRenderTargetResidencyPin(purpose: .history(effect, [tokenA, tokenB]), generation: 1)
            let previous = Coordinator.Tail(state: baseState, persistentResources: beforeResources,
                historyPin: oldPin, mappingGeneration: 5)
            coordinator.committedTails = [effect: previous]
            coordinator.scheduledTails = [effect: previous]
            let newPin = SceneGraphRenderTargetResidencyPin(purpose: .history(effect, [tokenA, tokenB]), generation: 1)
            let lease = makeAtomicTargets(layerID: 7, generation: 1).prepared.leases[0]
            let commit = ScenePreparedPersistentGraphTargets.Commit(leases: [lease],
                submissionPin: .init(purpose: .submission, generation: 1), historyPinsByEffect: [effect: newPin])
            let targets = ScenePreparedPersistentGraphTargets(leases: [lease], action: { _, _, _ in commit })
            let pool = SceneOffscreenTexturePool(factory: { _ in targets })
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(textureSnapshot: .init(frameIndex: 23, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            guard case let .claimed(preflight) = coordinator.preflightClaim(layerID: 7),
                  case .ready = coordinator.prepareFrame([.init(claim: preflight,
                    targetPlan: .init(token: preflight.token, allocation: .init(graphPlan: .init(key: .init(layerID: 7)))),
                    sourceTexture: output.effectOutputResource.publication.texture,
                    sourceUniforms: .init(), sourcePipeline: .init(),
                    frameInputs: .fixture.replacingDependencyEffects([reserved]))], pool: pool, commandBuffer: buffer),
                  let ledgerID = coordinator.preparedLedgerByLayerID[7],
                  case let .claimed(claim) = coordinator.claim(layerID: 7) else {
                results["lateHistorySetup_\(mode)"] = false; _ = coordinator.endFrame(); continue
            }
            let provisionalSwapped = coordinator.activeByID[ledgerID]?.candidateTails?[effect]?.state.logicalMapping == after
                && coordinator.activeByID[ledgerID]?.preparationContext != nil
            let execution = coordinator.executeClaimed(claim: claim, dependencyEffects: [], commandBuffer: buffer)
            let calls = SceneResolvedMaterialGraphExecutor.prepareCalls
            let originalBaseReused = calls.count == 2 && calls.allSatisfy {
                $0.previousStates[effect] == baseState
                    && $0.previousResources[effect]?[historyIdentity]?.publication.texture === textureA
                    && $0.previousResources[effect]?[temporary]?.publication.texture === textureB
            }
            if mode == "uncovered" {
                var rejected = false
                if case let .failed(reason) = execution { rejected = reason == "prepared-frame-consumption-rejected" }
                _ = coordinator.endFrame()
                results["lateHistoryUncoveredPhysicalTokenRejectsBeforeEncode"] = provisionalSwapped && originalBaseReused
                    && rejected && SceneResolvedMaterialGraphExecutor.encodeInputs.isEmpty && pool.batchCommitCount == 1
                    && commit.submissionPin.releaseCount == 1 && newPin.releaseCount == 1 && oldPin.active
                coordinator.invalidate(reason: .surfaceStop)
                continue
            }
            guard case let .encoded(texture, ticket) = execution,
                  case .consumed = coordinator.markComposite(ticket, texture: texture, consumed: true)
            else { results["lateHistoryExecution_\(mode)"] = false; _ = coordinator.endFrame(); continue }
            let tail = coordinator.activeByID[ledgerID]?.candidateTails?[effect]
            let rebuilt = mode == "discard" ? tail == nil
                : tail?.state.logicalMapping == before && tail?.historyPin === newPin && tail?.mappingGeneration == 5
            let contextReleased = coordinator.activeByID[ledgerID]?.phase == .outputConsumed
                && coordinator.activeByID[ledgerID]?.preparationContext == nil
            let pinsUntilCompletion = newPin.active && oldPin.active && commit.submissionPin.active
            let coveredSubset = coordinator.historyPinMatches(newPin, effect: effect,
                tokens: [tokenA], generation: 1)
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit(); buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(identity: ObjectIdentifier(buffer),
                observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil ? .completed : .failed)
            _ = coordinator.endFrame()
            let committed = mode == "discard" ? coordinator.committedTails[effect] == nil
                : coordinator.committedTails[effect]?.state.logicalMapping == before
            results[mode == "discard" ? "lateHistoryDiscardReleasesUnusedPinAtCompletion"
                : "lateHistorySwapRollbackKeepsOriginalCoveredPin"] = provisionalSwapped && originalBaseReused
                    && rebuilt && contextReleased && pinsUntilCompletion && coveredSubset && committed && sealed
                    && pool.batchCommitCount == 1 && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 7]
                    && commit.submissionPin.releaseCount == 1 && oldPin.releaseCount == 1
                    && (mode == "discard" ? newPin.releaseCount == 1 : newPin.active)
                    && coordinator.frameFailures == 0 && buffer.status == .completed && buffer.error == nil
            coordinator.invalidate(reason: .surfaceStop)
        }
    }

    static func atomicPreparationRollback(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
            ]
            let coordinator = makeCoordinator(device, layerIDs: [7, 8])
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func claim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claim7 = claim(7)
            let claim8 = claim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                switch plan.graphPlan.key.layerID {
                case 7: targets7.prepared
                case 8: targets8.prepared
                default: nil
                }
            })
            let outcome = coordinator.prepareFrame(
                [
                    .init(
                        claim: claim7,
                        targetPlan: .init(
                            token: claim7.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                        ),
                        sourceTexture: makeTexture(device, "atomic-source-7"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                    .init(
                        claim: claim8,
                        targetPlan: .init(
                            token: claim8.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 8)))
                        ),
                        sourceTexture: makeTexture(device, "atomic-source-8"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let reason: String
            switch outcome {
            case let .rejected(value): reason = value
            case .ready: reason = "ready"
            }
            let postFailureClaimRejected: Bool
            switch coordinator.claim(layerID: 7) {
            case let .rejected(reasonCode):
                postFailureClaimRejected =
                    reasonCode == "frame-candidate-not-prepared"
            case .claimed, .notMigrated:
                postFailureClaimRejected = false
            }
            results["secondPreparationFailureRollsBackWholeFrame"] =
                reason == "graph-preflight-fixture-preflight-unavailable"
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                && targets7.commit.submissionPin.releaseCount == 0
                && pool.batchCommitCount == 0
                && coordinator.activeByID.isEmpty
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
                && !coordinator.framePreparationComplete
                && coordinator.frameRequiresDrop
                && coordinator.frameClaimed == 0
                && postFailureClaimRejected
            targets7.commit.releaseAll()
            targets8.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

    }

    static func twoCandidateSubmission(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1, nodeCount: 32_769),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2, nodeCount: 32_769),
            ]
            let coordinator = makeCoordinator(device, layerIDs: [7, 8])
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 4, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func preflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let preflight7 = preflightClaim(7)
            let preflight8 = preflightClaim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? targets7.prepared : targets8.prepared
            })
            let prepared = coordinator.prepareFrame(
                [
                    .init(
                        claim: preflight7,
                        targetPlan: .init(
                            token: preflight7.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                        ),
                        sourceTexture: makeTexture(device, "success-source-7"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                    .init(
                        claim: preflight8,
                        targetPlan: .init(
                            token: preflight8.token,
                            allocation: .init(graphPlan: .init(key: .init(layerID: 8)))
                        ),
                        sourceTexture: makeTexture(device, "success-source-8"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let atomicallyPublished: Bool
            if case .ready = prepared {
                atomicallyPublished = coordinator.framePreparationComplete
                    && coordinator.activeByID.count == 2
                    && Set(coordinator.preparedLedgerByLayerID.keys) == [7, 8]
                    && coordinator.frameClaimed == 0
            } else {
                atomicallyPublished = false
            }
            func consume(_ layerID: Int) -> Bool {
                let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
                switch coordinator.claim(layerID: layerID) {
                case let .claimed(value): claim = value
                case .rejected, .notMigrated: return false
                }
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffects: [],
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    let outcome = coordinator.markComposite(
                        ticket,
                        texture: texture,
                        consumed: true
                    )
                    if case .consumed = outcome { return true }
                    return false
                case .failed:
                    return false
                }
            }
            let consumed = consume(7) && consume(8)
            let composited = coordinator.activeByID.values.allSatisfy {
                $0.phase == .outputConsumed && $0.compositorConsumed
            }
            let sealed = coordinator.sealFrame(on: buffer)
            let oneSubmission = coordinator.pendingSubmissions.count == 1
                && coordinator.pendingSubmissions[0].ledgerIDs.count == 2
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: .completed
            )
            results["twoCandidatesPublishConsumeAndCommitAtomically"] =
                atomicallyPublished
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                && consumed && composited && sealed && oneSubmission
                && coordinator.frameClaimed == 2
                && coordinator.frameEncoded == 2
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && pool.batchCommitCount == 1
                && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1
            results["largeGraphsBeyondObservationAggregateCapSubmit"] =
                results["twoCandidatesPublishConsumeAndCommitAtomically"] == true
                && coordinator.frameFailures == 0
            _ = coordinator.endFrame()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
        }

    }

}
