import Foundation
import Metal

enum SceneSubmissionPublicationChecks {
    static func aggregatePublicationMiss(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2),
            ]
            let firstBinding = SceneDependencyRenderPlan.Binding(
                consumerLayerID: 7,
                providerLayerID: 41,
                slot: .init(effectID: "first", passIndex: 0, slotIndex: 1),
                blendMode: 0,
                kind: .imageLayerBlend,
                requiresResolvedMaterialProgram: true
            )
            let secondBinding = SceneDependencyRenderPlan.Binding(
                consumerLayerID: 7,
                providerLayerID: 42,
                slot: .init(effectID: "second", passIndex: 0, slotIndex: 1),
                blendMode: 0,
                kind: .imageLayerBlend,
                requiresResolvedMaterialProgram: true
            )
            let aggregate = SceneDependencyRenderPlan.MultiProviderAggregate(
                consumerLayerID: 7,
                bindings: [firstBinding, secondBinding],
                authoredSlotOrder: [firstBinding.slot, secondBinding.slot]
            )
            let inputs = [firstBinding, secondBinding].map { binding in
                dependencyInput(
                    binding: binding,
                    texture: makeTexture(
                        device,
                        "aggregate-local-\(binding.providerLayerID)"
                    ),
                    frameEpoch: 15
                )
            }
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [
                    7: .externalAggregate(aggregate)
                ]
            )
            let aggregateTargets = makeAtomicTargets(
                layerID: 7,
                generation: 1
            )
            let suffixTargets = makeAtomicTargets(
                layerID: 8,
                generation: 2
            )
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? aggregateTargets.prepared : suffixTargets.prepared
            })
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 15, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func aggregateClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let consumerClaim = aggregateClaim(7)
            let suffixClaim = aggregateClaim(8)
            let prepared = coordinator.prepareFrame(
                [
                    .init(
                        claim: consumerClaim,
                        targetPlan: .init(
                            token: consumerClaim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 7))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "aggregate-local-consumer"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: SceneResolvedMaterialRuntimeBridge
                            .FrameInputs.fixture.replacingDependencyEffects(
                                inputs
                            )
                    ),
                    .init(
                        claim: suffixClaim,
                        targetPlan: .init(
                            token: suffixClaim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 8))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "aggregate-local-suffix"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = prepared { preparedReady = true }
            else { preparedReady = false }
            let rejected = coordinator.rejectPreparedExternalDependencyLocally(
                layerID: 7,
                reasonCode: "external-primary-provider-capture-unavailable"
            )
            let suffixComposited: Bool
            switch coordinator.claim(layerID: 8) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffects: [],
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markComposite(
                        ticket,
                        texture: texture,
                        consumed: true
                    ) {
                        suffixComposited = true
                    } else { suffixComposited = false }
                case .failed:
                    suffixComposited = false
                }
            case .rejected, .notMigrated:
                suffixComposited = false
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            _ = coordinator.endFrame()
            results["aggregatePublicationMissRejectsOnlyConsumer"] =
                aggregate.hasStrictBindingVector
                && preparedReady
                && rejected
                && suffixComposited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && coordinator.frameFailures == 0
                && aggregateTargets.commit.submissionPin.releaseCount == 1
                && suffixTargets.commit.submissionPin.releaseCount == 1
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

    }

    static func preparedProviderAndNamedSuffix(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor
                .preparedDependencyTextureByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            let providerPrepared = makeAtomicPrepared(
                device: device,
                layerID: 7,
                generation: 1
            )
            let consumerPrepared = makeAtomicPrepared(
                device: device,
                layerID: 8,
                generation: 2
            )
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: providerPrepared,
                8: consumerPrepared,
            ]
            let binding = externalPrimaryBinding(
                consumerLayerID: 8,
                providerLayerID: 7
            )
            let provisionalTexture = makeTexture(
                device,
                "nested-dependency-provisional"
            )
            let provisionalInput = dependencyInput(
                binding: binding,
                texture: provisionalTexture,
                frameEpoch: 13
            )
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [8: .externalPrimary(binding)]
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 13, valid: true),
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
            let providerClaim = preflightClaim(7)
            let consumerClaim = preflightClaim(8)
            let providerTargets = makeAtomicTargets(
                layerID: 7,
                generation: 1
            )
            let consumerTargets = makeAtomicTargets(
                layerID: 8,
                generation: 2
            )
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? providerTargets.prepared : consumerTargets.prepared
            })
            let preparation = coordinator.prepareFrame(
                [
                    .init(
                        claim: providerClaim,
                        targetPlan: .init(
                            token: providerClaim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 7))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "nested-provider-source"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    ),
                    .init(
                        claim: consumerClaim,
                        targetPlan: .init(
                            token: consumerClaim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 8))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "nested-consumer-source"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                            .replacingDependencyEffects([provisionalInput])
                    ),
                ],
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = preparation { preparedReady = true }
            else { preparedReady = false }
            let outputs = coordinator.preparedOutputTexturesByLayerID()
            let namedReservationWasRetained =
                SceneResolvedMaterialGraphExecutor
                    .preparedDependencyTextureByToken[8]
                    == ObjectIdentifier(provisionalTexture)
                && outputs?[7] === providerPrepared.finalTexture
                && outputs?[8] === consumerPrepared.finalTexture

            let providerPublished: Bool
            let providerTerminalIsNotCompositor: Bool
            switch coordinator.claim(layerID: 7) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffects: [],
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markNamedPublication(
                        ticket,
                        texture: texture,
                        published: true
                    ) {
                        providerPublished = true
                    } else {
                        providerPublished = false
                    }
                    providerTerminalIsNotCompositor =
                        coordinator.activeByID[ticket.identity]?.phase
                            == .outputConsumed
                        && coordinator.activeByID[ticket.identity]?
                            .outputConsumed == true
                        && coordinator.activeByID[ticket.identity]?
                            .compositorConsumed == false
                case .failed:
                    providerPublished = false
                    providerTerminalIsNotCompositor = false
                }
            case .rejected, .notMigrated:
                providerPublished = false
                providerTerminalIsNotCompositor = false
            }

            let consumerComposited: Bool
            let readyInput = dependencyInput(
                binding: binding,
                texture: provisionalTexture,
                frameEpoch: 13
            )
            switch coordinator.claim(layerID: 8) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffects: [readyInput],
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markComposite(
                        ticket,
                        texture: texture,
                        consumed: true
                    ) {
                        consumerComposited = true
                    } else {
                        consumerComposited = false
                    }
                case .failed:
                    consumerComposited = false
                }
            case .rejected, .notMigrated:
                consumerComposited = false
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            results[
                "preparedProviderOutputKeepsNamedReservationWithoutCompositorOwnership"
            ] = preparedReady
                && namedReservationWasRetained
                && providerPublished
                && providerTerminalIsNotCompositor
                && consumerComposited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && pool.batchCommitCount == 1
                && providerTargets.commit.submissionPin.releaseCount == 1
                && consumerTargets.commit.submissionPin.releaseCount == 1
            _ = coordinator.endFrame()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
            SceneResolvedMaterialGraphExecutor
                .preparedDependencyTextureByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
        }

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            let providerPrepared = makeAtomicPrepared(
                device: device,
                layerID: 7,
                generation: 1
            )
            let suffixPrepared = makeAtomicPrepared(
                device: device,
                layerID: 8,
                generation: 2
            )
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: providerPrepared,
                8: suffixPrepared,
            ]
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8],
                logSink: { recorder.append($0) }
            )
            let providerTargets = makeAtomicTargets(
                layerID: 7,
                generation: 1
            )
            let suffixTargets = makeAtomicTargets(
                layerID: 8,
                generation: 2
            )
            let pool = SceneOffscreenTexturePool(factory: { plan in
                plan.graphPlan.key.layerID == 7
                    ? providerTargets.prepared : suffixTargets.prepared
            })
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 14, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func localClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let providerClaim = localClaim(7)
            let suffixClaim = localClaim(8)
            let preparation = coordinator.prepareFrame(
                [providerClaim, suffixClaim].map { claim in
                    .init(
                        claim: claim,
                        targetPlan: .init(
                            token: claim.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(
                                    layerID: claim.layerID
                                ))
                            )
                        ),
                        sourceTexture: makeTexture(
                            device,
                            "named-publication-local-\(claim.layerID)"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture
                    )
                },
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = preparation { preparedReady = true }
            else { preparedReady = false }

            var providerDiscarded = false
            var namedPublicationIntegrityReasonRejected = false
            switch coordinator.claim(layerID: 7) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffects: [],
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    // Identity/epoch drift must not enter the ordinary
                    // local-discard route; only the typed ordinary miss may.
                    if case .failed = coordinator
                        .discardNamedPublicationOutputLocally(
                            ticket,
                            texture: texture,
                            reasonCode:
                                "named-provider-publication-identity-invalid"
                        ) {
                        namedPublicationIntegrityReasonRejected = true
                    }
                    if case .consumed = coordinator
                        .discardNamedPublicationOutputLocally(
                            ticket,
                            texture: texture,
                            reasonCode:
                                "named-provider-publication-unavailable"
                        ) {
                        providerDiscarded = true
                    }
                case .failed:
                    break
                }
            case .rejected, .notMigrated:
                break
            }

            let suffixComposited: Bool
            switch coordinator.claim(layerID: 8) {
            case let .claimed(claim):
                switch coordinator.executeClaimed(
                    claim: claim,
                    dependencyEffects: [],
                    commandBuffer: buffer
                ) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markComposite(
                        ticket,
                        texture: texture,
                        consumed: true
                    ) {
                        suffixComposited = true
                    } else {
                        suffixComposited = false
                    }
                case .failed:
                    suffixComposited = false
                }
            case .rejected, .notMigrated:
                suffixComposited = false
            }
            let stayedLocal = coordinator.frameFailures == 0
                && coordinator.frameRequiresDrop == false
                && coordinator.frameLocalFallbacks[7]
                    == "named-provider-publication-unavailable"
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(
                identity: ObjectIdentifier(buffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil
                    ? .completed : .failed
            )
            _ = coordinator.endFrame()
            results["namedPublicationMissKeepsSuffixAndFrameLocal"] =
                preparedReady
                && providerDiscarded
                && namedPublicationIntegrityReasonRejected
                && suffixComposited
                && stayedLocal
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && providerTargets.commit.submissionPin.releaseCount == 1
                && suffixTargets.commit.submissionPin.releaseCount == 1
                && recorder.lines.contains {
                    $0.contains("named-publication-local-discard layer=7")
                }
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

    }

    static func repeatedTerminalPublication(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(
                    device: device,
                    layerID: 7,
                    generation: 2,
                    terminalSampling: .linearRepeat
                ),
            ]
            let previousPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(
                    effect,
                    [.init(rawValue: "terminal-repeat-safe-history")]
                ),
                generation: 1
            )
            let previousTail = makeTail(
                device: device,
                token: "terminal-repeat-safe-history",
                generation: 1,
                pin: previousPin
            )
            let previousResource = previousTail.persistentResources[historyIdentity]!
            let coordinator = makeCoordinator(device)
            coordinator.committedTails = [effect: previousTail]
            coordinator.scheduledTails = coordinator.committedTails
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 4, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(value): claim = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let targets = makeAtomicTargets(layerID: 7, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { _ in targets.prepared })
            let transactionIDBefore = coordinator.nextTransactionID
            let outcome = coordinator.prepareFrame(
                [.init(
                    claim: claim,
                    targetPlan: .init(
                        token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))
                    ),
                    sourceTexture: makeTexture(device, "repeat-terminal-source"),
                    sourceUniforms: .init(),
                    sourcePipeline: .init(),
                    frameInputs: .fixture
                )],
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
            let previousPublicationPreserved: Bool = {
                guard let committed = coordinator.committedTails[effect],
                      let scheduled = coordinator.scheduledTails[effect],
                      committed.historyPin === previousPin,
                      scheduled.historyPin === previousPin,
                      committed.mappingGeneration == previousTail.mappingGeneration,
                      scheduled.mappingGeneration == previousTail.mappingGeneration,
                      let current = committed.persistentResources[historyIdentity],
                      current.publication.isSameAtom(
                          as: previousResource.publication
                      ),
                      current.publication.candidate.sampling == .linearClamp,
                      current.publication.requestIdentity == .graph(historyIdentity),
                      current.publication.texture === previousResource.publication.texture,
                      case let .provider(.graph(generation, token)) =
                        current.publication.candidate.identity else { return false }
                return generation == 1
                    && token == "terminal-repeat-safe-history"
                    && current.resourceGeneration == 1
                    && current.publication.contentGeneration == 1
            }()
            results["repeatTerminalPublicationRejectsBeforeLedgerAndPreservesPreviousCurrent"] =
                reason == "persistent-allocation-commit-rejected"
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [7]
                && coordinator.activeByID.isEmpty
                && coordinator.activeTransactions.isEmpty
                && coordinator.preparedLedgerByLayerID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && coordinator.nextTransactionID == transactionIDBefore
                && coordinator.commandBufferRecords.isEmpty
                && coordinator.frameFailures == 1
                && coordinator.frameRequiresDrop
                && !coordinator.framePreparationComplete
                && coordinator.frameClaimed == 0
                && pool.batchCommitCount == 0
                && targets.commit.submissionPin.releaseCount == 0
                && buffer.status == .notEnqueued
                && previousPin.active
                && previousPin.releaseCount == 0
                && previousPublicationPreserved
                && postFailureClaimRejected
            targets.commit.releaseAll()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

    }

}
