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

            let unavailableReason = SceneResolvedMaterialRuntimeBridge.FrameInputs
                .DependencyUnavailability.providerSourceUnavailable.rawValue
            let skipped = makeCoordinator(device, layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [7: .externalAggregate(aggregate)])
            skipped.beginFrame(textureSnapshot: .init(frameIndex: 16, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            let installed = skipped.installFrameLocalFallbacks([7: unavailableReason])
            let suffixOnly = makeAtomicPrepared(device: device, layerID: 8, generation: 3)
            SceneResolvedMaterialGraphExecutor.preparedByToken = [8: suffixOnly]
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            let suffixOnlyTargets = makeAtomicTargets(layerID: 8, generation: 3)
            let suffixOnlyPool = SceneOffscreenTexturePool(factory: { _ in suffixOnlyTargets.prepared })
            let suffixOnlyBuffer = queue.makeCommandBuffer()!
            let bytes = device.makeBuffer(length: 4, options: .storageModeShared)!
            memset(bytes.contents(), 0, 4)
            let blit = suffixOnlyBuffer.makeBlitCommandEncoder()!
            blit.fill(buffer: bytes, range: 0..<4, value: 73)
            blit.endEncoding()
            let preparedSuffixOnly: Bool
            if case let .claimed(claim) = skipped.preflightClaim(layerID: 8),
               case .ready = skipped.prepareFrame([.init(claim: claim,
                    targetPlan: .init(token: claim.token, allocation: .init(graphPlan: .init(key: .init(layerID: 8)))),
                    sourceTexture: makeTexture(device, "retired-provider-healthy"), sourceUniforms: .init(),
                    sourcePipeline: .init(), frameInputs: .fixture)], pool: suffixOnlyPool,
                    commandBuffer: suffixOnlyBuffer) {
                preparedSuffixOnly = true
            } else { preparedSuffixOnly = false }
            let fallbackUnclaimed: Bool
            if case let .rejected(reason) = skipped.claim(layerID: 7) {
                fallbackUnclaimed = reason == unavailableReason
            } else { fallbackUnclaimed = false }
            var healthyConsumed = false
            if case let .claimed(claim) = skipped.claim(layerID: 8),
               case let .encoded(texture, ticket) = skipped.executeClaimed(claim: claim,
                    dependencyEffects: [], commandBuffer: suffixOnlyBuffer),
               case .consumed = skipped.markComposite(ticket, texture: texture, consumed: true) {
                healthyConsumed = true
            }
            let suffixOnlySealed = skipped.sealFrame(on: suffixOnlyBuffer)
            suffixOnlyBuffer.commit()
            suffixOnlyBuffer.waitUntilCompleted()
            skipped.completeCommandBuffer(identity: ObjectIdentifier(suffixOnlyBuffer),
                observationID: skipped.commandBufferRecords[ObjectIdentifier(suffixOnlyBuffer)]?.observationID ?? 0,
                status: suffixOnlyBuffer.status == .completed ? .completed : .failed)
            _ = skipped.endFrame()
            results["aggregateSourceUnavailableSkipsClaimAndKeepsSuffix"] = installed && preparedSuffixOnly
                && fallbackUnclaimed && healthyConsumed && suffixOnlySealed
                && SceneResolvedMaterialGraphExecutor.prepareTokens == [8]
                && suffixOnlyBuffer.status == .completed && suffixOnlyBuffer.error == nil
                && bytes.contents().load(as: UInt8.self) == 73 && skipped.frameFailures == 0
                && suffixOnlyTargets.commit.submissionPin.releaseCount == 1
            SceneResolvedMaterialGraphExecutor.preparedByToken = [:]

            let invalidAggregate = SceneDependencyRenderPlan.MultiProviderAggregate(consumerLayerID: 7,
                bindings: [secondBinding, firstBinding], authoredSlotOrder: aggregate.authoredSlotOrder)
            let invalidOwners: [SceneResolvedMaterialDependencyOwnership] = [
                .none, .graphInternal(referenceCount: 1), .externalAggregate(invalidAggregate)]
            results["sourceUnavailableFallbackRequiresDependencyContract"] = invalidOwners.allSatisfy { ownership in
                let invalid = makeCoordinator(device, dependencyOwnershipByLayerID: [7: ownership])
                invalid.beginFrame(textureSnapshot: .init(frameIndex: 17, valid: true),
                    dynamicSnapshot: .init(), frameInputs: .init())
                let rejected = !invalid.installFrameLocalFallbacks([7: unavailableReason])
                _ = invalid.endFrame()
                return rejected && invalid.frameLocalFallbacks.isEmpty
            }
        }

    }

    static func preparedProviderAndNamedSuffix(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        let pma: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
        let straight: SceneTextureContent = .color(.resolved(.straightAlpha))
        // The executor supplies metadata; this exercises the real coordinator,
        // while the geometry rasterizer's PMA pixels have a separate GPU gate.
        let scenarios: [(String, [Int], [SceneDependencyRenderPlan.Binding.Kind], SceneTextureContent,
                         [SceneTextureContent], String?)] = [
            ("preparedProviderOutputKeepsNamedReservationWithoutCompositorOwnership", [7], [.resolvedMaterial], pma, [pma], nil),
            ("geometryProviderStraightSourceKeepsPMAReservation", [7], [.geometryLayer], straight, [pma], nil),
            ("graphCopyProviderInheritsStraightContent", [7], [.resolvedMaterial], straight, [straight], nil),
            ("mixedAggregateGeometryThenImageKeepsContentOrder", [9, 7], [.geometryLayer, .imageLayerBlend], straight, [pma, straight], nil),
            ("mixedAggregateImageThenGeometryKeepsContentOrder", [7, 9], [.imageLayerBlend, .geometryLayer], straight, [straight, pma], nil),
            ("mixedAggregateWrongContentRejected", [9, 7], [.geometryLayer, .imageLayerBlend], straight, [pma, straight], "content"),
            ("mixedAggregateWrongTextureRejected", [9, 7], [.geometryLayer, .imageLayerBlend], straight, [pma, straight], "texture"),
            ("mixedAggregateWrongEpochRejected", [9, 7], [.geometryLayer, .imageLayerBlend], straight, [pma, straight], "epoch"),
            ("mixedAggregateWrongSlotRejected", [9, 7], [.geometryLayer, .imageLayerBlend], straight, [pma, straight], "slot"),
        ]
        for (resultKey, providerIDs, kinds, upstreamContent, expectedContents, drift) in scenarios {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.prepareTokens = []
            SceneResolvedMaterialGraphExecutor.preparedDependencyTextureByToken = [:]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            defer {
                SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
                SceneResolvedMaterialGraphExecutor.preparedDependencyTextureByToken = [:]
                SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
            }
            let layerIDs = providerIDs + [8]
            let preparedByID = Dictionary(uniqueKeysWithValues: layerIDs.enumerated().map { index, layerID in
                (layerID, makeAtomicPrepared(device: device, layerID: layerID,
                    generation: UInt64(index + 1), terminalContent: layerID == 8 ? pma : upstreamContent))
            })
            SceneResolvedMaterialGraphExecutor.preparedByToken = preparedByID
            let bindings = zip(providerIDs, kinds).map { providerID, kind in
                SceneDependencyRenderPlan.Binding(consumerLayerID: 8, providerLayerID: providerID,
                    slot: .init(effectID: "provider-\(providerID)", passIndex: 0, slotIndex: 1),
                    blendMode: 0, kind: kind, requiresResolvedMaterialProgram: true)
            }
            let ownership: SceneResolvedMaterialDependencyOwnership = bindings.count == 1
                ? .externalPrimary(bindings[0])
                : .externalAggregate(.init(consumerLayerID: 8, bindings: bindings,
                    authoredSlotOrder: bindings.map(\.slot)))
            let reservations = bindings.map { binding in
                dependencyInput(binding: binding,
                    texture: makeTexture(device, "named-reservation-\(binding.providerLayerID)"), frameEpoch: 13)
            }
            let expectedInputs = zip(reservations, expectedContents).map { $0.withContent($1) }
            let coordinator = makeCoordinator(device, layerIDs: layerIDs,
                dependencyOwnershipByLayerID: [8: ownership])
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(textureSnapshot: .init(frameIndex: 13, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            let claims = layerIDs.map { layerID -> SceneResolvedMaterialRuntimeBridge.ClaimedExecution in
                switch coordinator.preflightClaim(layerID: layerID) {
                case let .claimed(value): return value
                case let .rejected(reasonCode): fatalError(reasonCode)
                case .notMigrated: fatalError("claim unavailable")
                }
            }
            let targetsByID = Dictionary(uniqueKeysWithValues: layerIDs.enumerated().map { index, layerID in
                (layerID, makeAtomicTargets(layerID: layerID, generation: UInt64(index + 1)))
            })
            let pool = SceneOffscreenTexturePool(factory: { plan in
                targetsByID[plan.graphPlan.key.layerID]!.prepared
            })
            let preparation = coordinator.prepareFrame(claims.map { claim in
                .init(claim: claim,
                    targetPlan: .init(token: claim.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: claim.layerID)))),
                    sourceTexture: makeTexture(device, "nested-source-\(claim.layerID)"),
                    sourceUniforms: .init(), sourcePipeline: .init(),
                    frameInputs: .fixture.replacingDependencyEffects(claim.layerID == 8 ? reservations : []))
            }, pool: pool, commandBuffer: buffer)
            let preparedReady: Bool
            if case .ready = preparation { preparedReady = true }
            else { preparedReady = false }
            let outputs = coordinator.preparedOutputTexturesByLayerID()
            let retained = coordinator.preparedLedgerByLayerID[8]
                .flatMap { coordinator.activeByID[$0]?.preparedDependencyEffects } ?? []
            let namedReservationWasRetained = retained.count == expectedInputs.count
                && retained.map(\.providerLayerID) == providerIDs
                && zip(retained, expectedInputs).allSatisfy {
                    $0.content == $1.content && $0.texture === $1.texture
                }
                && layerIDs.allSatisfy { outputs?[$0] === preparedByID[$0]?.finalTexture }

            var providerPublished = true
            var providerTerminalIsNotCompositor = true
            for providerID in providerIDs {
                if case let .claimed(claim) = coordinator.claim(layerID: providerID),
                   case let .encoded(texture, ticket) = coordinator.executeClaimed(
                        claim: claim, dependencyEffects: [], commandBuffer: buffer),
                   case .consumed = coordinator.markNamedPublication(ticket, texture: texture, published: true) {
                    providerTerminalIsNotCompositor = providerTerminalIsNotCompositor
                        && coordinator.activeByID[ticket.identity]?.phase == .outputConsumed
                        && coordinator.activeByID[ticket.identity]?.outputConsumed == true
                        && coordinator.activeByID[ticket.identity]?.compositorConsumed == false
                } else { providerPublished = false }
            }
            var readyInputs = expectedInputs
            switch drift {
            case "content": readyInputs[0] = readyInputs[0].withContent(straight)
            case "texture": readyInputs[0] = dependencyInput(binding: bindings[0],
                texture: makeTexture(device, "named-ready-lookalike"), frameEpoch: 13)
            case "epoch": readyInputs[0] = dependencyInput(binding: bindings[0],
                texture: reservations[0].texture, frameEpoch: 14)
            case "slot": readyInputs[0] = dependencyInput(binding: bindings[0],
                texture: reservations[0].texture, frameEpoch: 13,
                slot: .init(effectID: bindings[0].slot.effectID, passIndex: 0, slotIndex: 2))
            default: break
            }
            var consumerComposited = false
            var consumerRejection: String?
            if case let .claimed(claim) = coordinator.claim(layerID: 8) {
                switch coordinator.executeClaimed(claim: claim,
                    dependencyEffects: readyInputs, commandBuffer: buffer) {
                case let .encoded(texture, ticket):
                    if case .consumed = coordinator.markComposite(ticket, texture: texture, consumed: true) {
                        consumerComposited = true
                    }
                case let .failed(reasonCode): consumerRejection = reasonCode
                }
            }
            if drift != nil {
                results[resultKey] = preparedReady && namedReservationWasRetained
                    && providerPublished && providerTerminalIsNotCompositor
                    && consumerRejection == "prepared-frame-consumption-rejected"
                    && !consumerComposited && buffer.status == .notEnqueued
                _ = coordinator.endFrame()
                continue
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(identity: ObjectIdentifier(buffer),
                observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil ? .completed : .failed)
            let succeeded = preparedReady && namedReservationWasRetained
                && providerPublished && providerTerminalIsNotCompositor && consumerComposited && sealed
                && buffer.status == .completed && buffer.error == nil
                && coordinator.activeByID.isEmpty && coordinator.pendingSubmissions.isEmpty
                && pool.batchCommitCount == 1
                && targetsByID.values.allSatisfy { $0.commit.submissionPin.releaseCount == 1 }
            results[resultKey] = succeeded
            let sharedKey = "preparedProviderOutputKeepsNamedReservationWithoutCompositorOwnership"
            results[sharedKey] = (results[sharedKey] ?? true) && succeeded
            _ = coordinator.endFrame()
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
