import Foundation
import Metal

enum SceneSubmissionPublicationChecks {
    /// Literal Executor responses exercise Coordinator delivery and lifetime.
    /// The real GraphExecutor/App gates own rollback and pixel correctness.
    static func lateNamedInputAvailability(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        let cases: [(String, String)] = [
            ("steady", "lateNamedInputsNormalPrepareOnce"),
            ("late", "lateNamedInputsSubsetRepreparesOnceAndKeepsAOnlySuffix"),
            ("empty", "lateNamedInputsEmptyRepreparesOnceAndKeepsIndependentSuffix"),
            ("texture", "lateNamedInputsForeignTextureRejectedBeforeReprepare"),
            ("epoch", "lateNamedInputsForeignEpochRejectedBeforeReprepare"),
            ("content", "lateNamedInputsForeignContentRejectedBeforeReprepare"),
            ("order", "lateNamedInputsReorderedReadyRejectedBeforeReprepare"),
        ]
        for (mode, key) in cases {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
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
            let a = externalPrimaryBinding(consumerLayerID: 7, providerLayerID: 41,
                slotIndex: 4, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let b = externalPrimaryBinding(consumerLayerID: 7, providerLayerID: 42,
                slotIndex: 6, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let suffixA = externalPrimaryBinding(consumerLayerID: 8, providerLayerID: 41,
                slotIndex: 3, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let aTexture = makeTexture(device, "late-A")
            let inputs = [dependencyInput(binding: a, texture: aTexture, frameEpoch: 15),
                dependencyInput(binding: b, texture: makeTexture(device, "late-B"), frameEpoch: 15)]
            let suffixInputs = mode == "empty" ? [] : [dependencyInput(
                binding: suffixA, texture: aTexture, frameEpoch: 15)]
            let entry = makeTexture(device, "literal-effect-entry")
            let original = makeAtomicPrepared(device: device, layerID: 7, generation: 1)
            let replacement = makeAtomicPrepared(device: device, layerID: 7, generation: 1,
                terminalTexture: entry, failureReason: "material-finalizer-named-provider-unavailable")
            let suffix = makeAtomicPrepared(device: device, layerID: 8, generation: 2)
            SceneResolvedMaterialGraphExecutor.preparedByToken = [7: original, 8: suffix]
            SceneResolvedMaterialGraphExecutor.preparedResponsesByToken = [7: [original, replacement]]
            let coordinator = makeCoordinator(device, layerIDs: [7, 8],
                dependencyOwnershipByLayerID: [
                    7: .externalAggregate(.init(consumerLayerID: 7, bindings: [a, b])),
                    8: mode == "empty" ? .none : .externalPrimary(suffixA)])
            let targets7 = makeAtomicTargets(layerID: 7, generation: 1)
            let targets8 = makeAtomicTargets(layerID: 8, generation: 2)
            var pool: SceneOffscreenTexturePool? = .init(factory: { plan in
                plan.graphPlan.key.layerID == 7 ? targets7.prepared : targets8.prepared
            })
            weak var poolWitness = pool
            let poolID = ObjectIdentifier(pool!)
            let buffer = queue.makeCommandBuffer()!
            let trace = SceneEffectExecutionFrameTrace(frameIndex: 15,
                telemetry: .init(logSink: { _ in }))
            coordinator.beginFrame(textureSnapshot: .init(frameIndex: 15, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            let claims = [7, 8].map { id -> SceneResolvedMaterialRuntimeBridge.ClaimedExecution in
                guard case let .claimed(claim) = coordinator.preflightClaim(layerID: id)
                else { fatalError("claim unavailable") }
                return claim
            }
            let preparation = coordinator.prepareFrame(claims.map { claim in
                .init(claim: claim, targetPlan: .init(token: claim.token,
                    allocation: .init(graphPlan: .init(key: .init(layerID: claim.layerID)))),
                    sourceTexture: entry, sourceUniforms: .init(), sourcePipeline: .init(),
                    frameInputs: .fixture.replacingDependencyEffects(claim.layerID == 7 ? inputs : suffixInputs))
            }, pool: pool, commandBuffer: buffer, executionTrace: trace)
            guard case .ready = preparation else { results[key] = false; continue }
            let preparedOnce = SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                && pool!.batchCommitCount == 1
                && coordinator.activeByID.values.filter { $0.preparationContext != nil }.count
                    == (mode == "empty" ? 1 : 2)
            pool = nil
            let contextRetainedPool = poolWitness != nil
            var ready = inputs
            switch mode {
            case "late": ready = [inputs[0]]
            case "empty": ready = []
            case "texture": ready = [dependencyInput(binding: a,
                texture: makeTexture(device, "foreign-late-A"), frameEpoch: 15)]
            case "epoch": ready = [dependencyInput(binding: a, texture: aTexture, frameEpoch: 16)]
            case "content": ready = [inputs[0].withContent(.color(.resolved(.straightAlpha)))]
            case "order": ready = Array(inputs.reversed())
            default: break
            }
            guard case let .claimed(claim7) = coordinator.claim(layerID: 7) else {
                results[key] = false; _ = coordinator.endFrame(); continue
            }
            let execution = coordinator.executeClaimed(claim: claim7,
                dependencyEffects: ready, commandBuffer: buffer)
            if !["steady", "late", "empty"].contains(mode) {
                let rejected: Bool
                if case let .failed(reason) = execution {
                    rejected = reason == "prepared-frame-consumption-rejected"
                } else { rejected = false }
                _ = coordinator.endFrame()
                results[key] = preparedOnce && contextRetainedPool && rejected
                    && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8]
                    && SceneResolvedMaterialGraphExecutor.encodeInputs.isEmpty
                    && coordinator.activeByID.isEmpty && poolWitness == nil
                    && targets7.commit.submissionPin.releaseCount == 1
                    && targets8.commit.submissionPin.releaseCount == 1
                continue
            }
            guard case let .encoded(texture7, ticket7) = execution,
                  case .consumed = coordinator.markComposite(ticket7, texture: texture7, consumed: true)
            else { results[key] = false; _ = coordinator.endFrame(); continue }
            let expectedTokens = mode == "steady" ? [7, 8] : [7, 8, 7]
            let replacedGraph = SceneResolvedMaterialGraphExecutor.encodeInputs.first?.finalTexture
                === (mode == "steady" ? original.finalTexture : entry)
            let failureMatches = mode == "steady" ? ticket7.effectFailures.isEmpty
                : ticket7.effectFailures.first?.reasonCode == "material-finalizer-named-provider-unavailable"
            let contextReleased = coordinator.activeByID[ticket7.identity]?.phase == .outputConsumed
                && coordinator.activeByID[ticket7.identity]?.preparationContext == nil
                && (mode == "empty" ? poolWitness == nil : poolWitness?.batchCommitCount == 1)
            var suffixConsumed = false
            if case let .claimed(claim8) = coordinator.claim(layerID: 8),
               case let .encoded(texture, ticket) = coordinator.executeClaimed(claim: claim8,
                    dependencyEffects: suffixInputs, commandBuffer: buffer),
               case .consumed = coordinator.markComposite(ticket, texture: texture, consumed: true) {
                suffixConsumed = true
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit(); buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(identity: ObjectIdentifier(buffer),
                observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil ? .completed : .failed)
            _ = coordinator.endFrame()
            let calls = SceneResolvedMaterialGraphExecutor.prepareCalls.filter { $0.token == 7 }
            let contextInputsPreserved = calls.allSatisfy { $0.poolID == poolID && $0.frameIndex == 15
                && $0.traceID == ObjectIdentifier(trace)
                && $0.frameTime == calls[0].frameTime && $0.time == calls[0].time
                && $0.leaseGenerations == [1] }
            results[key] = preparedOnce && contextRetainedPool && replacedGraph && failureMatches
                && contextReleased && suffixConsumed && sealed && contextInputsPreserved
                && SceneResolvedMaterialGraphExecutor.prepareTokens == expectedTokens
                && (mode == "steady" || calls.last?.inputs.count == ready.count)
                && poolWitness == nil && targets7.commit.submissionPin.releaseCount == 1
                && targets8.commit.submissionPin.releaseCount == 1 && coordinator.frameFailures == 0
                && buffer.status == .completed && buffer.error == nil
        }
    }

    static func lateProviderContentPropagation(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        let pma: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
        let straight: SceneTextureContent = .color(.resolved(.straightAlpha))
        for mode in ["changed", "geometry", "foreign"] {
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
            let a = externalPrimaryBinding(consumerLayerID: 7, providerLayerID: 41,
                kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let b = externalPrimaryBinding(consumerLayerID: 7, providerLayerID: 42,
                slotIndex: 2, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let read7 = externalPrimaryBinding(consumerLayerID: 8, providerLayerID: 7,
                kind: mode == "geometry" ? .geometryLayer : .imageLayerBlend,
                requiresResolvedMaterialProgram: true)
            let read8 = externalPrimaryBinding(consumerLayerID: 9, providerLayerID: 8,
                kind: .imageLayerBlend, requiresResolvedMaterialProgram: true)
            let inputs7 = [a, b].map { dependencyInput(binding: $0,
                texture: makeTexture(device, "provider-input-\($0.providerLayerID)"), frameEpoch: 19) }
            let input8 = dependencyInput(binding: read7,
                texture: makeTexture(device, "reservation-7"), frameEpoch: 19)
            let input9 = dependencyInput(binding: read8,
                texture: makeTexture(device, "reservation-8"), frameEpoch: 19)
            let old8Content = mode == "geometry" ? pma : straight
            let old = [
                7: makeAtomicPrepared(device: device, layerID: 7, generation: 1, terminalContent: straight),
                8: makeAtomicPrepared(device: device, layerID: 8, generation: 2, terminalContent: old8Content),
                9: makeAtomicPrepared(device: device, layerID: 9, generation: 3, terminalContent: old8Content),
                10: makeAtomicPrepared(device: device, layerID: 10, generation: 4),
            ]
            let fresh7 = makeAtomicPrepared(device: device, layerID: 7, generation: 1,
                terminalContent: pma, terminalTexture: old[7]!.finalTexture,
                failureReason: "material-finalizer-named-provider-unavailable")
            let fresh8 = makeAtomicPrepared(device: device, layerID: 8, generation: 2,
                terminalContent: pma, terminalTexture: old[8]!.finalTexture)
            let fresh9 = makeAtomicPrepared(device: device, layerID: 9, generation: 3,
                terminalContent: pma, terminalTexture: old[9]!.finalTexture)
            SceneResolvedMaterialGraphExecutor.preparedByToken = old
            SceneResolvedMaterialGraphExecutor.preparedResponsesByToken = [
                7: [old[7]!, fresh7],
                8: mode == "changed" ? [old[8]!, fresh8] : [old[8]!],
                9: mode == "changed" ? [old[9]!, fresh9] : [old[9]!],
                10: [old[10]!],
            ]
            let coordinator = makeCoordinator(device, layerIDs: [7, 8, 9, 10],
                dependencyOwnershipByLayerID: [
                    7: .externalAggregate(.init(consumerLayerID: 7, bindings: [a, b])),
                    8: .externalPrimary(read7), 9: .externalPrimary(read8)])
            let targets = Dictionary(uniqueKeysWithValues: [7, 8, 9, 10].enumerated().map {
                ($0.element, makeAtomicTargets(layerID: $0.element, generation: UInt64($0.offset + 1)))
            })
            let pool = SceneOffscreenTexturePool(factory: { targets[$0.graphPlan.key.layerID]!.prepared })
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(textureSnapshot: .init(frameIndex: 19, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            let claims = [7, 8, 9, 10].map { id -> SceneResolvedMaterialRuntimeBridge.ClaimedExecution in
                guard case let .claimed(claim) = coordinator.preflightClaim(layerID: id)
                else { fatalError("claim unavailable") }
                return claim
            }
            let byID = [7: inputs7, 8: [input8], 9: [input9], 10: []]
            let preparation = coordinator.prepareFrame(claims.map { claim in
                .init(claim: claim, targetPlan: .init(token: claim.token,
                    allocation: .init(graphPlan: .init(key: .init(layerID: claim.layerID)))),
                    sourceTexture: makeTexture(device, "content-source-\(claim.layerID)"),
                    sourceUniforms: .init(), sourcePipeline: .init(),
                    frameInputs: .fixture.replacingDependencyEffects(byID[claim.layerID]!))
            }, pool: pool, commandBuffer: buffer)
            guard case .ready = preparation,
                  case let .claimed(claim7) = coordinator.claim(layerID: 7),
                  case let .encoded(texture7, ticket7) = coordinator.executeClaimed(claim: claim7,
                    dependencyEffects: mode == "foreign" ? inputs7 : [inputs7[0]], commandBuffer: buffer),
                  case .consumed = coordinator.markNamedPublication(ticket7, texture: texture7, published: true)
            else { results["lateProviderContentSetup_\(mode)"] = false; _ = coordinator.endFrame(); continue }
            if mode == "foreign" {
                var rejected = false
                if case let .claimed(claim8) = coordinator.claim(layerID: 8),
                   case let .failed(reason) = coordinator.executeClaimed(claim: claim8,
                        dependencyEffects: [input8.withContent(pma)], commandBuffer: buffer) {
                    rejected = reason == "prepared-frame-consumption-rejected"
                }
                results["lateProviderForeignContentDoesNotTriggerReprepare"] = rejected
                    && SceneResolvedMaterialGraphExecutor.prepareTokens == [7, 8, 9, 10]
                    && SceneResolvedMaterialGraphExecutor.encodeInputs.count == 1 && pool.batchCommitCount == 1
                _ = coordinator.endFrame()
                continue
            }
            let updated = [8, 9].allSatisfy { id in
                guard let ledgerID = coordinator.preparedLedgerByLayerID[id],
                      let ledger = coordinator.activeByID[ledgerID] else { return false }
                return ledger.preparedDependencyEffects.first?.content == pma
                    && ledger.prepared.finalResource.publication.candidate.content == pma
            }
            var suffixSucceeded = true
            for (id, inputs) in [(8, [input8.withContent(pma)]), (9, [input9.withContent(pma)]), (10, [])] {
                guard case let .claimed(claim) = coordinator.claim(layerID: id),
                      case let .encoded(texture, ticket) = coordinator.executeClaimed(claim: claim,
                        dependencyEffects: inputs, commandBuffer: buffer) else { suffixSucceeded = false; break }
                let outcome = id == 8
                    ? coordinator.markNamedPublication(ticket, texture: texture, published: true)
                    : coordinator.markComposite(ticket, texture: texture, consumed: true)
                if case .consumed = outcome {} else { suffixSucceeded = false; break }
            }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit(); buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(identity: ObjectIdentifier(buffer),
                observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil ? .completed : .failed)
            _ = coordinator.endFrame()
            let expected = mode == "changed" ? [7, 8, 9, 10, 7, 8, 9] : [7, 8, 9, 10, 7]
            results[mode == "changed" ? "lateProviderContentRepreparesOnlyAffectedSuffix"
                : "lateProviderContentKeepsGeometryReservationPMA"] = updated && suffixSucceeded && sealed
                    && SceneResolvedMaterialGraphExecutor.prepareTokens == expected && pool.batchCommitCount == 1
                    && targets.values.allSatisfy { $0.commit.submissionPin.releaseCount == 1 }
                    && coordinator.frameFailures == 0 && buffer.status == .completed && buffer.error == nil
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
                : .externalAggregate(.init(consumerLayerID: 8, bindings: bindings))
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

        try deferredAuthoredComposite(device: device, queue: queue, results: &results)
    }

    static func deferredAuthoredComposite(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        let cases = [
            ("published", "namedOutputLaterCompositesWithoutRewindingSuccessors"),
            ("ordinary-miss", "visiblePublicationMissRetainsAuthoredOutputAndHistory"),
            ("hidden-miss", "hiddenPublicationMissCannotBorrowDiscardedOutput"),
            ("data", "namedDataNeverBecomesAuthoredColor"),
            ("alpha-signal", "namedIndependentAlphaNeverBecomesAuthoredColor"),
            ("duplicate", "authoredOutputRejectsRepeatedBorrowAndComposite"),
            ("stale", "authoredOutputRejectsStaleReceipt"),
            ("foreign", "authoredOutputRejectsForeignTexture"),
        ]
        for (mode, key) in cases {
            SceneResolvedMaterialGraphExecutor.prepareCallCount = 0
            SceneResolvedMaterialGraphExecutor.encodeInputs = []
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            defer {
                SceneResolvedMaterialGraphExecutor.preparedByToken = [:]
                SceneResolvedMaterialGraphExecutor.encodeInputs = []
                SceneResolvedMaterialGraphExecutor.encodeSucceeds = false
            }
            let ids = [9, 8, 7] // U supplies P, then C; U's main draw is last.
            let prepared = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
                var content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
                if id == 9 {
                    if mode == "data" { content = .data }
                    else if mode == "alpha-signal" { content = .color(.resolved(.independentAlphaSignal)) }
                }
                return (id, makeAtomicPrepared(device: device, layerID: id,
                    generation: UInt64(index + 1), terminalContent: content))
            })
            SceneResolvedMaterialGraphExecutor.preparedByToken = prepared
            let bindings = [externalPrimaryBinding(consumerLayerID: 8, providerLayerID: 9),
                externalPrimaryBinding(consumerLayerID: 7, providerLayerID: 8)]
            let inputs = Dictionary(uniqueKeysWithValues: bindings.map { binding in
                (binding.consumerLayerID, dependencyInput(binding: binding,
                    texture: makeTexture(device, "separate-named-\(binding.providerLayerID)"), frameEpoch: 31)
                    .withContent(prepared[binding.providerLayerID]!.finalResource.publication.candidate.content))
            })
            let coordinator = makeCoordinator(device, layerIDs: ids,
                dependencyOwnershipByLayerID: [8: .externalPrimary(bindings[0]), 7: .externalPrimary(bindings[1])])
            // C retires real prior history. Restoring U's old candidate tails
            // after C runs would wrongly resurrect it.
            let oldPin = SceneGraphRenderTargetResidencyPin(
                purpose: .history(effect, [.init(rawValue: "C-prior")]), generation: 1)
            let prior = makeTail(device: device, token: "C-prior", generation: 1, pin: oldPin)
            coordinator.committedTails = [effect: prior]
            coordinator.scheduledTails = [effect: prior]
            let targets = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
                (id, makeAtomicTargets(layerID: id, generation: UInt64(index + 1)))
            })
            let pool = SceneOffscreenTexturePool(factory: { targets[$0.graphPlan.key.layerID]!.prepared })
            let buffer = queue.makeCommandBuffer()!
            coordinator.beginFrame(textureSnapshot: .init(frameIndex: 31, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            let requests = ids.map { id -> SceneResolvedMaterialRuntimeBridge.FramePreparationRequest in
                guard case let .claimed(claim) = coordinator.preflightClaim(layerID: id) else {
                    fatalError("deferred composite preflight unavailable")
                }
                return .init(claim: claim, targetPlan: .init(token: claim.token,
                    allocation: .init(graphPlan: .init(key: .init(layerID: id)))),
                    sourceTexture: makeTexture(device, "authored-source-\(id)"),
                    sourceUniforms: .init(), sourcePipeline: .init(),
                    frameInputs: .fixture.replacingDependencyEffects(inputs[id].map { [$0] } ?? []))
            }
            guard case .ready = coordinator.prepareFrame(requests, pool: pool, commandBuffer: buffer),
                  case let .claimed(uClaim) = coordinator.claim(layerID: 9),
                  case let .encoded(uTexture, uTicket) = coordinator.executeClaimed(
                    claim: uClaim, commandBuffer: buffer) else {
                results[key] = false
                _ = coordinator.endFrame()
                continue
            }
            let uReceipt: SceneResolvedMaterialRuntimeBridge.CompositeOutcome
            switch mode {
            case "ordinary-miss": uReceipt = coordinator.markOutputReady(uTicket, texture: uTexture)
            case "hidden-miss": uReceipt = coordinator.discardNamedPublicationOutputLocally(
                uTicket, texture: uTexture, reasonCode: "named-provider-publication-unavailable")
            default: uReceipt = coordinator.markNamedPublication(uTicket, texture: uTexture, published: true)
            }
            guard case .consumed = uReceipt else {
                results[key] = false
                _ = coordinator.endFrame()
                continue
            }
            let uIdentity = uTicket.identity
            var downstream = coordinator.scheduledTails[effect]?.historyPin === oldPin
            for id in [8, 7] {
                let ready: [SceneDependencyEffectInput] = id == 8 && (mode == "ordinary-miss" || mode == "hidden-miss")
                    ? [] : inputs[id].map { [$0] } ?? []
                guard case let .claimed(claim) = coordinator.claim(layerID: id),
                      case let .encoded(texture, ticket) = coordinator.executeClaimed(
                        claim: claim, dependencyEffects: ready, commandBuffer: buffer) else {
                    downstream = false
                    break
                }
                let receipt = id == 8
                    ? coordinator.markNamedPublication(ticket, texture: texture, published: true)
                    : coordinator.markComposite(ticket, texture: texture, consumed: true)
                if case .failed = receipt { downstream = false }
            }
            let beforeBorrow = (SceneResolvedMaterialGraphExecutor.prepareCallCount,
                SceneResolvedMaterialGraphExecutor.encodeInputs.count, pool.batchCommitCount)
            let tailsRetired = coordinator.scheduledTails.isEmpty
            let borrowed = coordinator.outputForComposite(layerID: 9, commandBuffer: buffer)
            var borrowedCorrectly = false
            if mode == "hidden-miss" || mode == "data" || mode == "alpha-signal" {
                borrowedCorrectly = borrowed == nil
                    && coordinator.activeByID[uIdentity]?.compositorConsumed == false
                if mode == "hidden-miss" {
                    borrowedCorrectly = borrowedCorrectly && coordinator.preparedLedgerByLayerID[9] == nil
                        && coordinator.frameLocalFallbacks[9] == "named-provider-publication-unavailable"
                }
            } else if case let .encoded(texture, ticket)? = borrowed {
                let foreignBuffer = queue.makeCommandBuffer()!
                let wrongBufferRejected: Bool
                if case .failed? = coordinator.outputForComposite(layerID: 9, commandBuffer: foreignBuffer) {
                    wrongBufferRejected = true
                } else { wrongBufferRejected = false }
                borrowedCorrectly = texture === uTexture && ticket == uTicket && wrongBufferRejected
                    && coordinator.preparedLedgerByLayerID[9] == uIdentity
                    && coordinator.frameLocalFallbacks[9] == nil && oldPin.active
                let receiptTicket = mode == "stale" ? SceneResolvedMaterialRuntimeBridge.ExecutionTicket(
                    identity: ticket.identity, epoch: ticket.epoch + 1,
                    finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                    consumesExternalPrimaryDependency: ticket.consumesExternalPrimaryDependency,
                    effectFailures: ticket.effectFailures) : ticket
                let receipt = coordinator.markComposite(receiptTicket,
                    texture: mode == "foreign" ? makeTexture(device, "foreign-final") : texture, consumed: true)
                if mode == "stale" || mode == "foreign" {
                    if case .failed = receipt {
                        results[key] = downstream && tailsRetired && borrowedCorrectly
                            && coordinator.frameRequiresDrop && coordinator.frameFailures > 0
                    } else { results[key] = false }
                    _ = coordinator.endFrame()
                    continue
                }
                if case .failed = receipt { borrowedCorrectly = false }
                if mode == "duplicate" {
                    let repeatedBorrow: Bool
                    if case .failed? = coordinator.outputForComposite(layerID: 9, commandBuffer: buffer) {
                        repeatedBorrow = true
                    } else { repeatedBorrow = false }
                    if case .failed = coordinator.markComposite(ticket, texture: texture, consumed: true) {
                        results[key] = downstream && tailsRetired && borrowedCorrectly && repeatedBorrow
                            && coordinator.frameRequiresDrop && coordinator.frameFailures > 0
                    } else { results[key] = false }
                    _ = coordinator.endFrame()
                    continue
                }
                borrowedCorrectly = borrowedCorrectly
                    && coordinator.activeByID[uIdentity]?.compositorConsumed == true
            }
            let noSecondWork = beforeBorrow.0 == SceneResolvedMaterialGraphExecutor.prepareCallCount
                && beforeBorrow.1 == SceneResolvedMaterialGraphExecutor.encodeInputs.count
                && beforeBorrow.2 == pool.batchCommitCount && beforeBorrow.1 == 3
            let historiesStayedRetired = coordinator.scheduledTails.isEmpty
            let pinsRetained = targets.values.allSatisfy { $0.commit.submissionPin.active }
            let sealed = coordinator.sealFrame(on: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            coordinator.completeCommandBuffer(identity: ObjectIdentifier(buffer),
                observationID: coordinator.commandBufferRecords[ObjectIdentifier(buffer)]?.observationID ?? 0,
                status: buffer.status == .completed && buffer.error == nil ? .completed : .failed)
            results[key] = downstream && tailsRetired && borrowedCorrectly && noSecondWork
                && historiesStayedRetired && pinsRetained && sealed && buffer.status == .completed
                && buffer.error == nil && coordinator.committedTails.isEmpty && oldPin.releaseCount == 1
                && pool.batchCommitCount == 1 && coordinator.activeByID.isEmpty
                && targets.values.allSatisfy { $0.commit.submissionPin.releaseCount == 1 }
            _ = coordinator.endFrame()
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
