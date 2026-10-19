import Foundation
import Metal

// The graph itself is opaque in this coordinator-only fixture. These hooks
// observe the real coordinator's one-shot handoff without issuing GPU work.
enum SceneSubmissionTerminalReplayFixture {
    static var expectedTarget: MTLTexture?
    static var succeeds = true
    static var commandBuffers: [ObjectIdentifier] = []
    static var replayModes: [Int?] = []
    static var attachmentReads: [Bool] = []
}

enum SceneGPUCensus {
    static func recordMainPassRender(usesDepth: Bool) { _ = usesDepth }
}

extension SceneResolvedMaterialGraphExecutor {
    func encodeTerminalReplay(
        _ prepared: PreparedGraph,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        var targetMatches = false
        _ = mainPass.encodePreparedDraw { target, _ in
            targetMatches = target === SceneSubmissionTerminalReplayFixture.expectedTarget
            return nil // Observation only: never begin a Metal encoder.
        }
        guard let replay = prepared.terminalMaterialReplay,
              mainPass.belongs(to: commandBuffer), targetMatches else {
            return false
        }
        SceneSubmissionTerminalReplayFixture.commandBuffers.append(
            ObjectIdentifier(commandBuffer)
        )
        SceneSubmissionTerminalReplayFixture.replayModes.append(replay.role.terminalReplayBlendMode)
        SceneSubmissionTerminalReplayFixture.attachmentReads.append(replay.role.readsCurrentAttachment)
        return SceneSubmissionTerminalReplayFixture.succeeds
    }
}

enum SceneSubmissionTerminalReplayChecks {
    static func run(device: MTLDevice, queue: MTLCommandQueue) -> [String: Bool] {
        var results: [String: Bool] = [:]
        func scenario(
            replay: Bool = true,
            supportsReplay: Bool = true,
            blendMode: Int = 0,
            readsCurrentAttachment: Bool = false,
            content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
            mutate: (Coordinator, inout SceneResolvedMaterialRuntimeBridge.ExecutionTicket) -> Void = { _, _ in },
            wrongBuffer: Bool = false,
            wrongTarget: Bool = false,
            succeeds: Bool = true,
            legacyReceipt: Bool = false,
            namedReceipt: Bool = false,
            ordinaryAfterNotApplicable: Bool = false,
            repeated: Bool = false,
            dependencyKind: SceneDependencyRenderPlan.Binding.Kind? = nil,
            providerUnavailable: Bool = false
        ) -> (outcome: String, calls: Int, consumed: Bool, dropped: Bool,
              dependencyConsumed: Bool, bypassReason: String?) {
            let binding = dependencyKind.map {
                externalPrimaryBinding(slotIndex: $0 == .solidLayer ? 3 : 1,
                    kind: $0)
            }
            var capability = makeCapabilities(dependencyOwnershipByLayerID:
                binding.map { [7: .externalPrimary($0)] } ?? [:]
            ).capabilitiesByLayerID[7]!
            capability.supportsTerminalMaterialReplay = supportsReplay
            capability.terminalReplayBlendMode = blendMode
            if readsCurrentAttachment { capability.sourceRoute = .capturedMainTargetTexture }
            let coordinator = Coordinator(
                device: device,
                capabilities: .init(capability: capability),
                logSink: { _ in }
            )
            let buffer = queue.makeCommandBuffer()!
            let target = makeTexture(device, "terminal-main")
            var prepared = makePrepared(device: device)
            let original = prepared.finalResource.publication
            prepared = .init(
                stages: prepared.stages,
                finalResource: .init(publication: .init(
                    requestIdentity: original.requestIdentity,
                    candidate: .init(texture: original.texture,
                        identity: original.candidate.identity, purpose: original.candidate.purpose,
                        sampling: original.candidate.sampling, content: content),
                    contentGeneration: original.contentGeneration),
                    resourceGeneration: prepared.finalResource.resourceGeneration),
                finalTexture: prepared.finalTexture,
                historyTokensByEffect: prepared.historyTokensByEffect
            )
            prepared.terminalMaterialReplay = replay
                ? .init(role: .init(terminalReplayBlendMode: blendMode,
                                   readsCurrentAttachment: readsCurrentAttachment)) : nil
            let dependencyEffects = binding.flatMap { binding in
                providerUnavailable ? nil : dependencyInput(binding: binding,
                    texture: makeTexture(device, "terminal-named-provider"))
            }.map { [$0] } ?? []
            let unavailable: SceneResolvedMaterialRuntimeBridge.FrameInputs.DependencyUnavailability? =
                providerUnavailable ? .providerSourceUnavailable : nil
            if let unavailable {
                let stage = makeObservationTransition(device: device)
                let passthrough = SceneResolvedMaterialGraphExecutor.PreparedStage(
                    effect: stage.effect, graph: stage.graph, pairStep: stage.pairStep,
                    transition: stage.transition, inputWidth: stage.inputWidth,
                    inputHeight: stage.inputHeight,
                    fullFramePairIsShared: stage.fullFramePairIsShared,
                    fullFramePairGeneration: stage.fullFramePairGeneration,
                    historyRehydrateCopyCount: stage.historyRehydrateCopyCount,
                    historyContentDiscarded: stage.historyContentDiscarded,
                    frameResources: stage.frameResources,
                    persistentResources: stage.persistentResources,
                    effectOutputResource: prepared.finalResource,
                    programCacheKeys: stage.programCacheKeys,
                    effectLocalFailureReasonCode: unavailable.rawValue,
                    effectLocalActivationBypassReasonCode: nil,
                    discardedPersistentTargetState: false
                )
                // Model an already-prepared ordinary local passthrough. This
                // fixture does not claim to prepare or draw the missing provider.
                prepared = .init(stages: [passthrough],
                    finalResource: prepared.finalResource,
                    finalTexture: prepared.finalTexture,
                    historyTokensByEffect: prepared.historyTokensByEffect)
            }
            coordinator.frameIsActive = true
            coordinator.framePreparationComplete = true
            coordinator.frame = .init(frameIndex: 13)
            coordinator.activeTransactions = [1]
            coordinator.preparedLedgerByLayerID = [7: 1]
            coordinator.activeByID[1] = .init(
                identity: 1, epoch: coordinator.executionEpoch,
                frameIndex: 13, layerID: 7, capabilityToken: .init(value: 7),
                prepared: prepared,
                preparedDependencyEffects: dependencyEffects,
                preparedDependencyUnavailability: unavailable,
                commandBuffer: buffer,
                committedBaseTails: coordinator.committedTails,
                blueprint: nil,
                candidateTails: [:],
                commit: makeCommit(generation: 1),
                phase: binding == nil ? .encoded : .allocationCommitted,
                claimConsumed: binding == nil, ticketConsumed: false,
                outputConsumed: false, compositorConsumed: false,
                submissionID: nil
            )
            var ticket = SceneResolvedMaterialRuntimeBridge.ExecutionTicket(
                identity: 1,
                epoch: coordinator.executionEpoch,
                finalTextureIdentity: ObjectIdentifier(prepared.finalTexture),
                finalContent: prepared.finalResource.publication.candidate.content,
                consumesExternalPrimaryDependency: false,
                effectFailures: [],
                hasTerminalMaterialReplay: replay,
                terminalReplayBlendMode: blendMode,
                terminalReadsCurrentAttachment: readsCurrentAttachment
            )
            let bypassReason = coordinator.preparedExternalDependencyBypassReason(layerID: 7)
            if binding != nil {
                SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
                guard case let .claimed(claim) = coordinator.claim(layerID: 7),
                      case let .encoded(_, issuedTicket) = coordinator.executeClaimed(
                        claim: claim, dependencyEffects: dependencyEffects,
                        commandBuffer: buffer
                      ) else {
                    return ("dependency-execution-rejected", 0, false,
                            coordinator.frameRequiresDrop, false, bypassReason)
                }
                ticket = issuedTicket
            }
            mutate(coordinator, &ticket)
            SceneSubmissionTerminalReplayFixture.expectedTarget = target
            SceneSubmissionTerminalReplayFixture.succeeds = succeeds
            SceneSubmissionTerminalReplayFixture.commandBuffers = []
            SceneSubmissionTerminalReplayFixture.replayModes = []
            SceneSubmissionTerminalReplayFixture.attachmentReads = []
            let main = SceneMainPassEncoder(
                commandBuffer: wrongBuffer ? queue.makeCommandBuffer()! : buffer,
                target: wrongTarget ? makeTexture(device, "foreign-main") : target,
                clearColor: MTLClearColorMake(0, 0, 0, 0),
                clearEnabled: true
            )
            func outcome() -> String {
                if legacyReceipt || namedReceipt {
                    let value = namedReceipt
                        ? coordinator.markNamedPublication(ticket, texture: prepared.finalTexture, published: true)
                        : coordinator.markComposite(ticket, texture: prepared.finalTexture, consumed: true)
                    switch value {
                    case .consumed: return "consumed"
                    case let .failed(reason): return reason
                    }
                }
                switch coordinator.drawTerminalMaterialReplay(ticket, mainPass: main) {
                case .notApplicable:
                    guard ordinaryAfterNotApplicable else { return "not-applicable" }
                    switch coordinator.markComposite(ticket, texture: prepared.finalTexture, consumed: true) {
                    case .consumed: return "consumed"
                    case let .failed(reason): return reason
                    }
                case .consumed: return "consumed"
                case let .failed(reason): return reason
                }
            }
            var value = outcome()
            let consumed = coordinator.activeByID[1]?.outputConsumed == true
                && coordinator.activeByID[1]?.compositorConsumed == true
                && coordinator.activeByID[1]?.ticketConsumed == true
                && coordinator.activeByID[1]?.phase == .outputConsumed
            if repeated { value = outcome() }
            return (value, SceneSubmissionTerminalReplayFixture.commandBuffers.count,
                    consumed, coordinator.frameRequiresDrop,
                    ticket.consumesExternalPrimaryDependency, bypassReason)
        }
        // Exercise the real coordinator request/prepare/issue chain. The fake
        // executor transports the request mode; the seed deliberately has none.
        func propagatedRole(blendMode: Int = 31, readsAttachment: Bool = false,
                            replay: Bool = true) -> Bool {
            var capability = makeCapabilities().capabilitiesByLayerID[7]!
            capability.supportsTerminalMaterialReplay = true
            capability.terminalReplayBlendMode = blendMode
            if readsAttachment { capability.sourceRoute = .capturedMainTargetTexture }
            let coordinator = Coordinator(device: device,
                capabilities: .init(capability: capability), logSink: { _ in })
            let buffer = queue.makeCommandBuffer()!
            let target = makeTexture(device, "additive-prepared-main")
            var prepared = makeAtomicPrepared(device: device, layerID: 7, generation: 1)
            prepared.terminalMaterialReplay = replay
                ? .init(role: .init(terminalReplayBlendMode: nil)) : nil
            let previousPrepared = SceneResolvedMaterialGraphExecutor.preparedByToken
            let previousEncode = SceneResolvedMaterialGraphExecutor.encodeSucceeds
            SceneResolvedMaterialGraphExecutor.preparedByToken = [7: prepared]
            SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
            defer {
                coordinator.cancelUnsubmittedFrame(on: buffer)
                SceneResolvedMaterialGraphExecutor.preparedByToken = previousPrepared
                SceneResolvedMaterialGraphExecutor.encodeSucceeds = previousEncode
            }
            coordinator.beginFrame(textureSnapshot: .init(frameIndex: 13, valid: true),
                dynamicSnapshot: .init(), frameInputs: .init())
            let targets = makeAtomicTargets(layerID: 7, generation: 1)
            let pool = SceneOffscreenTexturePool(factory: { _ in targets.prepared })
            guard case let .claimed(preflight) = coordinator.preflightClaim(layerID: 7),
                  case .ready = coordinator.prepareFrame([.init(claim: preflight,
                    targetPlan: .init(token: preflight.token,
                        allocation: .init(graphPlan: .init(key: .init(layerID: 7)))),
                    sourceTexture: makeTexture(device, "additive-source"), sourceUniforms: .init(),
                    sourcePipeline: .init(), terminalReplayTarget: target, terminalReplayBlendMode: blendMode,
                    frameInputs: .fixture)], pool: pool, commandBuffer: buffer),
                  case let .claimed(claim) = coordinator.claim(layerID: 7),
                  case let .encoded(_, ticket) = coordinator.executeClaimed(claim: claim,
                    dependencyEffects: [], commandBuffer: buffer),
                  ticket.hasTerminalMaterialReplay == replay,
                  ticket.terminalReplayBlendMode == (replay ? blendMode : nil),
                  ticket.terminalReadsCurrentAttachment == (replay && readsAttachment)
            else { return false }
            SceneSubmissionTerminalReplayFixture.expectedTarget = target
            SceneSubmissionTerminalReplayFixture.succeeds = true
            SceneSubmissionTerminalReplayFixture.commandBuffers = []
            SceneSubmissionTerminalReplayFixture.replayModes = []
            SceneSubmissionTerminalReplayFixture.attachmentReads = []
            let main = SceneMainPassEncoder(commandBuffer: buffer, target: target,
                clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: true)
            if !replay {
                guard case .notApplicable = coordinator.drawTerminalMaterialReplay(ticket, mainPass: main),
                      case .consumed = coordinator.markComposite(ticket,
                        texture: prepared.finalTexture, consumed: true) else { return false }
                return SceneSubmissionTerminalReplayFixture.commandBuffers.isEmpty
                    && !coordinator.frameRequiresDrop
            }
            guard case .consumed = coordinator.drawTerminalMaterialReplay(ticket, mainPass: main) else {
                return false
            }
            return SceneSubmissionTerminalReplayFixture.replayModes == [blendMode]
                && SceneSubmissionTerminalReplayFixture.attachmentReads == [readsAttachment]
                && SceneSubmissionTerminalReplayFixture.commandBuffers.count == 1
        }
        let propagatedMode = propagatedRole()
        let propagatedAttachment = propagatedRole(blendMode: 0, readsAttachment: true)
        results["requestAttachmentRoleReachesIssuedTicketAndConsumesOnce"] = propagatedAttachment
        results["requestModeReachesPreparedRoleAndIssuedTicket"] = propagatedMode
        let success = scenario()
        results["terminalReceiptConsumesOnceWithoutTextureSampling"] =
            success.outcome == "consumed" && success.calls == 1 && success.consumed && !success.dropped
                && propagatedMode && propagatedAttachment
        let additive = scenario(blendMode: 31)
        results["additiveTerminalReceiptConsumesActualRoleOnce"] =
            additive.outcome == "consumed" && additive.calls == 1 && additive.consumed
                && !additive.dropped && SceneSubmissionTerminalReplayFixture.replayModes == [31]
        // Keep the existing Python assertion connected to the added mode checks.
        results["terminalReceiptConsumesOnceWithoutTextureSampling"] =
            results["terminalReceiptConsumesOnceWithoutTextureSampling"] == true
                && results["additiveTerminalReceiptConsumesActualRoleOnce"] == true
        for kind in [SceneDependencyRenderPlan.Binding.Kind.imageLayerBlend,
                     .visibleImageGraphOutput, .solidLayer, .resolvedMaterial] {
            let ready = scenario(dependencyKind: kind)
            results["externalPrimaryReady_\(kind)_ConsumesTerminalReceipt"] =
                ready.outcome == "consumed" && ready.calls == 1
                    && ready.consumed && !ready.dropped && ready.dependencyConsumed
        }
        let hiddenDependency = scenario(mutate: { _, ticket in
            ticket = .init(identity: ticket.identity, epoch: ticket.epoch,
                finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                consumesExternalPrimaryDependency: false,
                effectFailures: ticket.effectFailures, hasTerminalMaterialReplay: true)
        }, dependencyKind: .imageLayerBlend)
        results["externalPrimaryTicketCannotHideConsumption"] =
            hiddenDependency.outcome == "terminal-material-replay-target-rejected"
                && hiddenDependency.calls == 0 && !hiddenDependency.consumed
                && hiddenDependency.dropped
        let inventedDependency = scenario(mutate: { _, ticket in
            ticket = .init(identity: ticket.identity, epoch: ticket.epoch,
                finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                consumesExternalPrimaryDependency: true,
                effectFailures: [], hasTerminalMaterialReplay: true)
        })
        results["terminalTicketCannotInventDependencyConsumption"] =
            inventedDependency.outcome == "terminal-material-replay-target-rejected"
                && inventedDependency.calls == 0 && !inventedDependency.consumed
                && inventedDependency.dropped
        let missing = scenario(replay: false, ordinaryAfterNotApplicable: true,
            dependencyKind: .resolvedMaterial, providerUnavailable: true)
        results["missingProviderKeepsOrdinaryLocalFallbackReceipt"] =
            missing.bypassReason == "external-primary-provider-source-unavailable"
                && !missing.dependencyConsumed && missing.outcome == "consumed"
                && missing.calls == 0 && missing.consumed && !missing.dropped
        // Execution emits local passthrough diagnostics alongside a valid
        // prepared terminal draw; they must not turn its receipt into a frame drop.
        let localFailure = scenario(mutate: { _, ticket in
            ticket = .init(identity: ticket.identity, epoch: ticket.epoch,
                finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                consumesExternalPrimaryDependency: false,
                effectFailures: [.init(layerID: 7, effectIndex: 1,
                    descriptorID: "local-visual-failure", reasonCode: "material-generic-owner-revoked")],
                hasTerminalMaterialReplay: true)
        })
        results["localVisualFailurePreservesPreparedTerminalReceipt"] =
            localFailure.outcome == "consumed" && localFailure.calls == 1
                && localFailure.consumed && !localFailure.dropped
        let opaque = scenario(content: .color(.resolved(.opaque)))
        results["opaqueTerminalReceiptConsumesOnce"] =
            opaque.outcome == "consumed" && opaque.calls == 1 && opaque.consumed && !opaque.dropped
        let straight = scenario(content: .color(.resolved(.straightAlpha)))
        let data = scenario(content: .data)
        results["straightTerminalReceiptConsumesOnce"] =
            straight.outcome == "consumed" && straight.calls == 1
                && straight.consumed && !straight.dropped
        results["dataOutputRejectsBeforeDraw"] =
            data.outcome == "terminal-material-replay-target-rejected"
                && data.calls == 0 && !data.consumed && data.dropped
        let inactive = scenario(replay: false)
        results["absentReplayLeavesTicketForOrdinaryTextureComposite"] =
            inactive.outcome == "not-applicable" && inactive.calls == 0 && !inactive.consumed && !inactive.dropped
        let ordinaryFallback = scenario(replay: false, ordinaryAfterNotApplicable: true)
        results["absentReplayAllowsOrdinaryTextureReceipt"] =
            ordinaryFallback.outcome == "consumed" && ordinaryFallback.calls == 0
                && ordinaryFallback.consumed && !ordinaryFallback.dropped
        let additiveFallback = scenario(replay: false, blendMode: 31, ordinaryAfterNotApplicable: true)
        results["additiveWithoutReplayAllowsOrdinaryTextureReceipt"] =
            additiveFallback.outcome == "consumed" && additiveFallback.calls == 0
                && additiveFallback.consumed && !additiveFallback.dropped
        results["absentReplayAllowsOrdinaryTextureReceipt"] =
            results["absentReplayAllowsOrdinaryTextureReceipt"] == true
                && results["additiveWithoutReplayAllowsOrdinaryTextureReceipt"] == true
        let attachmentFallback = propagatedRole(blendMode: 0, readsAttachment: true, replay: false)
        results["attachmentWithoutReplayKeepsOrdinaryTextureReceipt"] = attachmentFallback
        results["absentReplayAllowsOrdinaryTextureReceipt"] =
            results["absentReplayAllowsOrdinaryTextureReceipt"] == true && attachmentFallback
        let repeated = scenario(repeated: true)
        results["repeatedTerminalReceiptRejectsWithoutSecondDraw"] =
            repeated.outcome == "terminal-material-replay-ticket-reused" && repeated.calls == 1 && repeated.dropped
        let old = scenario(mutate: { _, ticket in
            ticket = .init(identity: ticket.identity, epoch: ticket.epoch + 1,
                finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                consumesExternalPrimaryDependency: false, effectFailures: [], hasTerminalMaterialReplay: true)
        })
        results["staleTerminalTicketRejectsBeforeDraw"] =
            old.outcome == "terminal-material-replay-ticket-missing" && old.calls == 0 && old.dropped
        let foreign = scenario(wrongBuffer: true)
        results["foreignCommandBufferRejectsBeforeDraw"] =
            foreign.outcome == "terminal-material-replay-target-rejected" && foreign.calls == 0 && foreign.dropped
        let wrongTarget = scenario(wrongTarget: true)
        results["foreignMainTargetRejectsWithoutReceipt"] =
            wrongTarget.outcome == "terminal-material-replay-encode-failed" && wrongTarget.calls == 0 && wrongTarget.dropped
        let failure = scenario(succeeds: false)
        results["terminalAppendFailureDropsFrameWithoutFallbackReceipt"] =
            failure.outcome == "terminal-material-replay-encode-failed" && failure.calls == 1 && !failure.consumed && failure.dropped
        let ordinary = scenario(legacyReceipt: true)
        let named = scenario(namedReceipt: true)
        results["terminalReplayCannotClaimLegacyTextureOrNamedReceipt"] =
            ordinary.outcome == "final-composite-terminal-replay-receipt-required"
                && named.outcome == "named-publication-terminal-replay-receipt-required"
                && ordinary.calls == 0 && named.calls == 0 && ordinary.dropped && named.dropped
        let unsupported = scenario(supportsReplay: false)
        results["unadmittedReplayRejectsBeforeDraw"] =
            unsupported.outcome == "terminal-material-replay-target-rejected" && unsupported.calls == 0 && unsupported.dropped
        let mismatch = scenario(mutate: { _, ticket in
            ticket = .init(identity: ticket.identity, epoch: ticket.epoch,
                finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                consumesExternalPrimaryDependency: false, effectFailures: [])
        })
        results["ticketCannotHidePreparedReplay"] =
            mismatch.outcome == "terminal-material-replay-ticket-mismatch" && mismatch.calls == 0 && mismatch.dropped
        for mode in [0, 31] {
            let wrongMode = scenario(blendMode: mode, mutate: { _, ticket in
                ticket = .init(identity: ticket.identity, epoch: ticket.epoch,
                    finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                    consumesExternalPrimaryDependency: ticket.consumesExternalPrimaryDependency,
                    effectFailures: ticket.effectFailures, hasTerminalMaterialReplay: true,
                    terminalReplayBlendMode: mode == 0 ? 31 : 0)
            })
            let rejected = wrongMode.outcome == "terminal-material-replay-ticket-mismatch"
                && wrongMode.calls == 0 && !wrongMode.consumed && wrongMode.dropped
            results["ticketCannotChangePreparedBlendMode_\(mode)"] = rejected
            results["ticketCannotHidePreparedReplay"] =
                results["ticketCannotHidePreparedReplay"] == true && rejected
        }
        for readsAttachment in [false, true] {
            let wrongFlag = scenario(readsCurrentAttachment: readsAttachment, mutate: { _, ticket in
                ticket = .init(identity: ticket.identity, epoch: ticket.epoch,
                    finalTextureIdentity: ticket.finalTextureIdentity, finalContent: ticket.finalContent,
                    consumesExternalPrimaryDependency: ticket.consumesExternalPrimaryDependency,
                    effectFailures: ticket.effectFailures, hasTerminalMaterialReplay: true,
                    terminalReplayBlendMode: 0, terminalReadsCurrentAttachment: !readsAttachment)
            })
            let rejected = wrongFlag.outcome == "terminal-material-replay-ticket-mismatch"
                && wrongFlag.calls == 0 && !wrongFlag.consumed && wrongFlag.dropped
            results["ticketCannotChangePreparedAttachmentRead_\(readsAttachment)"] = rejected
            results["ticketCannotHidePreparedReplay"] =
                results["ticketCannotHidePreparedReplay"] == true && rejected
        }
        let attachmentRepeated = scenario(readsCurrentAttachment: true, repeated: true)
        let rejectsAttachmentReuse = attachmentRepeated.outcome == "terminal-material-replay-ticket-reused"
            && attachmentRepeated.calls == 1 && attachmentRepeated.consumed && attachmentRepeated.dropped
            && SceneSubmissionTerminalReplayFixture.attachmentReads == [true]
        results["attachmentTerminalReceiptRejectsSecondConsumption"] = rejectsAttachmentReuse
        results["repeatedTerminalReceiptRejectsWithoutSecondDraw"] =
            results["repeatedTerminalReceiptRejectsWithoutSecondDraw"] == true && rejectsAttachmentReuse
        let additiveRepeated = scenario(blendMode: 31, repeated: true)
        results["additiveTerminalReceiptRejectsSecondConsumption"] =
            additiveRepeated.outcome == "terminal-material-replay-ticket-reused"
                && additiveRepeated.calls == 1 && additiveRepeated.dropped
                && SceneSubmissionTerminalReplayFixture.replayModes == [31]
        results["repeatedTerminalReceiptRejectsWithoutSecondDraw"] =
            results["repeatedTerminalReceiptRejectsWithoutSecondDraw"] == true
                && results["additiveTerminalReceiptRejectsSecondConsumption"] == true
        let unclaimed = scenario(mutate: { coordinator, _ in coordinator.activeByID[1]?.claimConsumed = false })
        results["unconsumedClaimRejectsBeforeDraw"] =
            unclaimed.outcome == "terminal-material-replay-ticket-mismatch" && unclaimed.calls == 0 && unclaimed.dropped
        return results
    }
}
