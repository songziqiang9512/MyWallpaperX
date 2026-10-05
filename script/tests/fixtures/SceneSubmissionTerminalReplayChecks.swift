import Foundation
import Metal

// The graph itself is opaque in this coordinator-only fixture. These hooks
// observe the real coordinator's one-shot handoff without issuing GPU work.
enum SceneSubmissionTerminalReplayFixture {
    static var expectedTarget: MTLTexture?
    static var succeeds = true
    static var commandBuffers: [ObjectIdentifier] = []
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
        guard prepared.terminalMaterialReplay != nil,
              mainPass.belongs(to: commandBuffer), targetMatches else {
            return false
        }
        SceneSubmissionTerminalReplayFixture.commandBuffers.append(
            ObjectIdentifier(commandBuffer)
        )
        return SceneSubmissionTerminalReplayFixture.succeeds
    }
}

enum SceneSubmissionTerminalReplayChecks {
    static func run(device: MTLDevice, queue: MTLCommandQueue) -> [String: Bool] {
        var results: [String: Bool] = [:]
        func scenario(
            replay: Bool = true,
            supportsReplay: Bool = true,
            content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
            mutate: (Coordinator, inout SceneResolvedMaterialRuntimeBridge.ExecutionTicket) -> Void = { _, _ in },
            wrongBuffer: Bool = false,
            wrongTarget: Bool = false,
            succeeds: Bool = true,
            legacyReceipt: Bool = false,
            namedReceipt: Bool = false,
            ordinaryAfterNotApplicable: Bool = false,
            repeated: Bool = false
        ) -> (outcome: String, calls: Int, consumed: Bool, dropped: Bool) {
            var capability = makeCapabilities().capabilitiesByLayerID[7]!
            capability.supportsTerminalMaterialReplay = supportsReplay
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
            prepared.terminalMaterialReplay = replay ? true : nil
            coordinator.frameIsActive = true
            coordinator.framePreparationComplete = true
            coordinator.activeTransactions = [1]
            coordinator.activeByID[1] = makeLedger(
                coordinator: coordinator,
                identity: 1,
                commandBuffer: buffer,
                prepared: prepared,
                commit: makeCommit(generation: 1),
                candidate: [:],
                phase: .encoded
            )
            var ticket = SceneResolvedMaterialRuntimeBridge.ExecutionTicket(
                identity: 1,
                epoch: coordinator.executionEpoch,
                finalTextureIdentity: ObjectIdentifier(prepared.finalTexture),
                finalContent: prepared.finalResource.publication.candidate.content,
                consumesExternalPrimaryDependency: false,
                effectFailures: [],
                hasTerminalMaterialReplay: replay
            )
            mutate(coordinator, &ticket)
            SceneSubmissionTerminalReplayFixture.expectedTarget = target
            SceneSubmissionTerminalReplayFixture.succeeds = succeeds
            SceneSubmissionTerminalReplayFixture.commandBuffers = []
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
                    consumed, coordinator.frameRequiresDrop)
        }
        let success = scenario()
        results["terminalReceiptConsumesOnceWithoutTextureSampling"] =
            success.outcome == "consumed" && success.calls == 1 && success.consumed && !success.dropped
        let opaque = scenario(content: .color(.resolved(.opaque)))
        results["opaqueTerminalReceiptConsumesOnce"] =
            opaque.outcome == "consumed" && opaque.calls == 1 && opaque.consumed && !opaque.dropped
        let straight = scenario(content: .color(.resolved(.straightAlpha)))
        let data = scenario(content: .data)
        results["unassociatedOrDataOutputRejectsBeforeDraw"] =
            straight.outcome == "terminal-material-replay-target-rejected"
                && data.outcome == "terminal-material-replay-target-rejected"
                && straight.calls == 0 && data.calls == 0
                && !straight.consumed && !data.consumed && straight.dropped && data.dropped
        let inactive = scenario(replay: false)
        results["absentReplayLeavesTicketForOrdinaryTextureComposite"] =
            inactive.outcome == "not-applicable" && inactive.calls == 0 && !inactive.consumed && !inactive.dropped
        let ordinaryFallback = scenario(replay: false, ordinaryAfterNotApplicable: true)
        results["absentReplayAllowsOrdinaryTextureReceipt"] =
            ordinaryFallback.outcome == "consumed" && ordinaryFallback.calls == 0
                && ordinaryFallback.consumed && !ordinaryFallback.dropped
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
        let unclaimed = scenario(mutate: { coordinator, _ in coordinator.activeByID[1]?.claimConsumed = false })
        results["unconsumedClaimRejectsBeforeDraw"] =
            unclaimed.outcome == "terminal-material-replay-ticket-mismatch" && unclaimed.calls == 0 && unclaimed.dropped
        return results
    }
}
