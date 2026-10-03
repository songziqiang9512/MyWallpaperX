import Foundation
import Metal

enum SceneSubmissionAtomicPreparationChecks {
    static func rollbackAndTransitiveCapture(
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

        do {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            SceneResolvedMaterialGraphExecutor.preparedByToken = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2),
                9: makeAtomicPrepared(device: device, layerID: 9, generation: 3),
                10: makeAtomicPrepared(device: device, layerID: 10, generation: 4),
            ]
            let binding7 = externalPrimaryBinding(
                consumerLayerID: 7, providerLayerID: 42
            )
            let binding8 = externalPrimaryBinding(
                consumerLayerID: 8, providerLayerID: 7
            )
            let binding9 = externalPrimaryBinding(
                consumerLayerID: 9, providerLayerID: 8
            )
            let dependencyTexture7 = makeTexture(
                device, "cascading-dependency-reservation-7"
            )
            let dependencyTexture8 = makeTexture(
                device, "cascading-dependency-reservation-8"
            )
            let dependencyTexture9 = makeTexture(
                device, "cascading-dependency-reservation-9"
            )
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8, 9, 10],
                dependencyOwnershipByLayerID: [
                    7: .externalPrimary(binding7),
                    8: .externalPrimary(binding8),
                    9: .externalPrimary(binding9),
                ],
                logSink: recorder.append
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
                dynamicSnapshot: .init(),
                frameInputs: .init()
            )
            func cascadingPreflightClaim(_ layerID: Int) ->
                SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let claims = [7, 8, 9, 10].map(cascadingPreflightClaim)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let targets9 = makeAtomicTargets(layerID: 9, generation: 3)
            let targets10 = makeAtomicTargets(layerID: 10, generation: 4)
            let preparedTargets = [
                7: targets7.prepared,
                8: targets8.prepared,
                9: targets9.prepared,
                10: targets10.prepared,
            ]
            let pool = SceneOffscreenTexturePool(factory: { plan in
                preparedTargets[plan.graphPlan.key.layerID]
            })
            let dependencies = [
                7: dependencyInput(
                    binding: binding7,
                    texture: dependencyTexture7,
                    frameEpoch: 3
                ),
                8: dependencyInput(
                    binding: binding8,
                    texture: dependencyTexture8,
                    frameEpoch: 3
                ),
                9: dependencyInput(
                    binding: binding9,
                    texture: dependencyTexture9,
                    frameEpoch: 3
                ),
            ]
            let prepared = coordinator.prepareFrame(
                claims.map { claim in
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
                            device, "cascading-source-\(claim.layerID)"
                        ),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: dependencies[claim.layerID].map {
                            .fixture.replacingDependencyEffects([$0])
                        } ?? .fixture
                    )
                },
                pool: pool,
                commandBuffer: buffer
            )
            let preparedReady: Bool
            if case .ready = prepared { preparedReady = true }
            else { preparedReady = false }
            let rejectionReason =
                "external-primary-provider-capture-unavailable"
            let cascadingRejections = [7, 8, 9].map { layerID in
                coordinator.rejectPreparedExternalDependencyLocally(
                    layerID: layerID,
                    reasonCode: rejectionReason
                )
            }
            let claim10ForExecution: SceneResolvedMaterialRuntimeBridge
                .ClaimedExecution
            switch coordinator.claim(layerID: 10) {
            case let .claimed(value): claim10ForExecution = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let execution = coordinator.executeClaimed(
                claim: claim10ForExecution,
                dependencyEffects: [],
                commandBuffer: buffer
            )
            let independentEncoded: Bool
            let independentComposited: Bool
            switch execution {
            case let .encoded(texture, ticket):
                independentEncoded = true
                if case .consumed = coordinator.markComposite(
                    ticket, texture: texture, consumed: true
                ) {
                    independentComposited = true
                } else {
                    independentComposited = false
                }
            case .failed:
                independentEncoded = false
                independentComposited = false
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
            let rejectionDiagnostics = recorder.lines.filter {
                $0.contains("dependency-subgraph-local-rejection layer=")
            }
            results["cascadingDependencyCaptureFailureRejectsTransitiveSubgraph"] =
                preparedReady
                && cascadingRejections == [true, true, true]
                && independentEncoded
                && independentComposited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && coordinator.activeByID.isEmpty
                && coordinator.pendingSubmissions.isEmpty
                && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1
                && targets9.commit.submissionPin.releaseCount == 1
                && targets10.commit.submissionPin.releaseCount == 1
                && coordinator.frameFailures == 0
                && rejectionDiagnostics.count == 3
                && [7, 8, 9].allSatisfy { layerID in
                    rejectionDiagnostics.contains(where: {
                        $0.contains("layer=\(layerID) ")
                    })
                }
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
        }

    }

    static func externalDependencyCapture(
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
            let binding = externalPrimaryBinding(consumerLayerID: 7)
            let dependencyTexture = makeTexture(
                device, "local-dependency-failure-reservation"
            )
            let dependency = dependencyInput(
                binding: binding,
                texture: dependencyTexture,
                frameEpoch: 3
            )
            let recorder = LogRecorder()
            let coordinator = makeCoordinator(
                device,
                layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [7: .externalPrimary(binding)],
                logSink: recorder.append
            )
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(
                textureSnapshot: .init(frameIndex: 3, valid: true),
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
            let claim7 = preflightClaim(7)
            let claim8 = preflightClaim(8)
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            let pool = SceneOffscreenTexturePool(factory: { plan in
                switch plan.graphPlan.key.layerID {
                case 7: targets7.prepared
                case 8: targets8.prepared
                default: nil
                }
            })
            let prepared = coordinator.prepareFrame(
                [
                    .init(
                        claim: claim7,
                        targetPlan: .init(
                            token: claim7.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 7))
                            )
                        ),
                        sourceTexture: makeTexture(device, "local-source-7"),
                        sourceUniforms: .init(),
                        sourcePipeline: .init(),
                        frameInputs: .fixture.replacingDependencyEffects(
                            [dependency]
                        )
                    ),
                    .init(
                        claim: claim8,
                        targetPlan: .init(
                            token: claim8.token,
                            allocation: .init(
                                graphPlan: .init(key: .init(layerID: 8))
                            )
                        ),
                        sourceTexture: makeTexture(device, "local-source-8"),
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
            let integrityReasonRejected = !coordinator
                .rejectPreparedExternalDependencyLocally(
                    layerID: 7,
                    reasonCode: "external-primary-reservation-missing"
                )
            let rejectedLocally = coordinator
                .rejectPreparedExternalDependencyLocally(
                    layerID: 7,
                    reasonCode:
                        "external-primary-provider-capture-unavailable"
                )
            let claim8ForExecution: SceneResolvedMaterialRuntimeBridge
                .ClaimedExecution
            switch coordinator.claim(layerID: 8) {
            case let .claimed(value): claim8ForExecution = value
            case let .rejected(reasonCode): fatalError(reasonCode)
            case .notMigrated: fatalError("claim unavailable")
            }
            let execution = coordinator.executeClaimed(
                claim: claim8ForExecution,
                dependencyEffects: [],
                commandBuffer: buffer
            )
            let encoded: Bool
            let composited: Bool
            switch execution {
            case let .encoded(texture, ticket):
                encoded = true
                if case .consumed = coordinator.markComposite(
                    ticket, texture: texture, consumed: true
                ) {
                    composited = true
                } else {
                    composited = false
                }
            case .failed:
                encoded = false
                composited = false
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
            results["externalDependencyCaptureFailureRejectsOnlyItsSubgraph"] =
                preparedReady
                && integrityReasonRejected
                && rejectedLocally
                && encoded
                && composited
                && sealed
                && buffer.status == .completed
                && buffer.error == nil
                && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1
                && coordinator.frameFailures == 0
                && recorder.lines.contains(where: {
                    $0.contains("dependency-subgraph-local-rejection layer=7")
                })
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
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2),
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
            _ = coordinator.endFrame()
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
        }

    }

}
