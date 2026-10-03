import Foundation
import Metal

private typealias Coordinator = SceneResolvedMaterialSubmissionCoordinator
private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias State = SceneGraphExecutionState

private let effect = Graph.EffectKey(
    layerID: 7, effectIndex: 0, descriptorID: "fixture"
)
private let historyIdentity = Graph.TextureIdentity(
    kind: .framebuffer, layerID: 7, effect: effect, name: "history"
)
private let observationOutputIdentity = Graph.TextureIdentity(
    kind: .effectOutput, layerID: 7, effect: effect, name: "pair-output"
)

private func effect(for layerID: Int) -> Graph.EffectKey {
    layerID == 7 ? effect : .init(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "fixture-\(layerID)"
    )
}

private func outputIdentity(for layerID: Int) -> Graph.TextureIdentity {
    let value = effect(for: layerID)
    return .init(
        kind: .effectOutput,
        layerID: layerID,
        effect: value,
        name: "pair-output-\(layerID)"
    )
}

private func makeTexture(_ device: MTLDevice, _ label: String) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 2,
        height: 2,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .renderTarget]
    guard let texture = device.makeTexture(descriptor: descriptor) else {
        fatalError("texture unavailable")
    }
    texture.label = label
    return texture
}

private func makeResource(
    texture: MTLTexture,
    token: String,
    generation: UInt64
) -> SceneFrameTextureResource {
    .init(
        publication: .init(
            requestIdentity: .graph(historyIdentity),
            candidate: .init(
                texture: texture,
                identity: .provider(.graph(
                    allocationGeneration: generation,
                    physicalToken: token
                )),
                purpose: .premultipliedColor
            ),
            contentGeneration: 1
        ),
        resourceGeneration: 1
    )
}

private func makeTail(
    device: MTLDevice,
    token: String,
    generation: UInt64,
    pin: SceneGraphRenderTargetResidencyPin,
    reset: UInt64 = 1
) -> Coordinator.Tail {
    let versioned = State.VersionedResource(
        token: .init(rawValue: token),
        contentGeneration: 1
    )
    let state = State(
        effectGeneration: 1,
        resetGeneration: reset,
        allocationGeneration: generation,
        logicalMapping: [historyIdentity: versioned],
        historyLogicalIdentities: [historyIdentity],
        historyClosureIdentities: [historyIdentity]
    )
    return .init(
        state: state,
        persistentResources: [
            historyIdentity: makeResource(
                texture: makeTexture(device, "history-\(token)"),
                token: token,
                generation: generation
            )
        ],
        historyPin: pin,
        mappingGeneration: generation
    )
}

private func makePrepared(
    device: MTLDevice,
    texture: MTLTexture? = nil
) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
    let final = texture ?? makeTexture(device, "final")
    return .init(
        stages: [],
        finalResource: makeResource(texture: final, token: "final", generation: 1),
        finalTexture: final,
        historyTokensByEffect: [:]
    )
}

private func makeObservationTransition(
    device: MTLDevice,
    programCacheKeys: [String] = ["fixture-program"]
) -> SceneResolvedMaterialGraphExecutor.PreparedStage {
    let resource = SceneFrameTextureResource(
        publication: .init(
            requestIdentity: .graph(observationOutputIdentity),
            candidate: .init(
                texture: makeTexture(device, "observation-output"),
                identity: .provider(.graph(
                    allocationGeneration: 3,
                    physicalToken: "observation-output-token"
                )),
                purpose: .premultipliedColor
            ),
            contentGeneration: 1
        ),
        resourceGeneration: 1
    )
    let graph = Graph(
        layerID: 7,
        effects: [.init(key: effect)],
        nodes: [.init(
            nodeIndex: 0,
            kind: .material,
            materialOrdinal: 0
        )]
    )
    let nextState = State(
        effectGeneration: 4,
        resetGeneration: 5,
        allocationGeneration: 3,
        logicalMapping: [:],
        historyLogicalIdentities: [],
        historyClosureIdentities: []
    )
    let transaction = State.Transaction(
        intents: [.material(
            nodeIndex: 0,
            materialOrdinal: 0,
            bindings: [],
            target: nil
        )],
        mappingBefore: [:],
        mappingAfter: [:],
        allocationGeneration: 3,
        effectGeneration: 4,
        resetGeneration: 5
    )
    return .init(
        effect: effect,
        graph: graph,
        pairStep: .init(
            effect: effect,
            inputIdentity: observationOutputIdentity,
            outputIdentity: observationOutputIdentity,
            inputMember: .zero,
            outputMember: .zero,
            nodes: [.init(
                nodeIndex: 0,
                kind: .material,
                rotatesAfterNode: true
            )]
        ),
        transition: .init(nextState: nextState, transaction: transaction),
        inputWidth: 2_048,
        inputHeight: 1_152,
        fullFramePairIsShared: false,
        fullFramePairGeneration: transaction.allocationGeneration,
        historyRehydrateCopyCount: 0,
        historyContentDiscarded: false,
        frameResources: [:],
        persistentResources: [:],
        effectOutputResource: resource,
        programCacheKeys: programCacheKeys,
        effectLocalFailureReasonCode: nil,
        effectLocalActivationBypassReasonCode: nil,
        discardedPersistentTargetState: false
    )
}

private func makeObservedPrepared(
    device: MTLDevice
) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
    let transition = makeObservationTransition(device: device)
    return .init(
        stages: [transition],
        finalResource: transition.effectOutputResource,
        finalTexture: transition.effectOutputResource.publication.texture,
        historyTokensByEffect: [:]
    )
}

private func makeAtomicPrepared(
    device: MTLDevice,
    layerID: Int,
    generation: UInt64,
    terminalSampling: SceneTextureSampling = .linearClamp,
    discardedPersistentTargetState: Bool = false,
    forgedDiscardTransaction: Bool = false
) -> SceneResolvedMaterialGraphExecutor.PreparedGraph {
    let key = effect(for: layerID)
    let output = outputIdentity(for: layerID)
    let texture = makeTexture(device, "atomic-final-\(layerID)")
    let resource = SceneFrameTextureResource(
        publication: .init(
            requestIdentity: .graph(output),
            candidate: .init(
                texture: texture,
                identity: .provider(.graph(
                    allocationGeneration: generation,
                    physicalToken: "atomic-output-\(layerID)"
                )),
                purpose: .premultipliedColor,
                sampling: terminalSampling
            ),
            contentGeneration: 1
        ),
        resourceGeneration: 1
    )
    let graph = Graph(
        layerID: layerID,
        effects: [.init(key: key)],
        nodes: [.init(nodeIndex: 0, kind: .material, materialOrdinal: 0)],
        renderTargets: discardedPersistentTargetState ? [output] : []
    )
    let state = State(
        effectGeneration: 1,
        resetGeneration: 1,
        allocationGeneration: generation,
        logicalMapping: [:],
        historyLogicalIdentities: [],
        historyClosureIdentities: []
    )
    let transaction = State.Transaction(
        intents: discardedPersistentTargetState && !forgedDiscardTransaction
            ? []
            : [.material(
                nodeIndex: 0,
                materialOrdinal: 0,
                bindings: [],
                target: nil
            )],
        mappingBefore: [:],
        mappingAfter: [:],
        allocationGeneration: generation,
        effectGeneration: 1,
        resetGeneration: 1
    )
    let transition = SceneResolvedMaterialGraphExecutor.PreparedStage(
        effect: key,
        graph: graph,
        pairStep: .init(
            effect: key,
            inputIdentity: output,
            outputIdentity: output,
            inputMember: .zero,
            outputMember: .zero,
            nodes: [.init(
                nodeIndex: 0,
                kind: .material,
                rotatesAfterNode: true
            )]
        ),
        transition: .init(nextState: state, transaction: transaction),
        inputWidth: 2_048,
        inputHeight: 1_152,
        fullFramePairIsShared: false,
        fullFramePairGeneration: transaction.allocationGeneration,
        historyRehydrateCopyCount: 0,
        historyContentDiscarded: false,
        frameResources: [:],
        persistentResources: [:],
        effectOutputResource: resource,
        programCacheKeys: ["atomic-program-\(layerID)"],
        effectLocalFailureReasonCode: discardedPersistentTargetState
            ? "fixture-effect-local-visual-failure"
            : nil,
        effectLocalActivationBypassReasonCode: nil,
        discardedPersistentTargetState: discardedPersistentTargetState
    )
    return .init(
        stages: [transition],
        finalResource: resource,
        finalTexture: texture,
        historyTokensByEffect: [:]
    )
}

private func makeAtomicTargets(
    layerID: Int,
    generation: UInt64
) -> (
    prepared: ScenePreparedPersistentGraphTargets,
    commit: ScenePreparedPersistentGraphTargets.Commit
) {
    let lease = SceneGraphRenderTargetLease(
        table: .init(plan: .init(identity: layerID)),
        generation: generation,
        texturesByToken: [:],
        fullFramePair: .init(
            first: .init(rawValue: "pair-\(layerID)-zero"),
            second: .init(rawValue: "pair-\(layerID)-one")
        )
    )
    let commit = ScenePreparedPersistentGraphTargets.Commit(
        leases: [lease],
        submissionPin: .init(purpose: .submission, generation: generation),
        historyPinsByEffect: [:]
    )
    return (
        .init(leases: [lease], action: { _, _, _ in commit }),
        commit
    )
}

private func makeCommittedObservationBase() -> State {
    .init(
        effectGeneration: 3,
        resetGeneration: 4,
        allocationGeneration: 2,
        logicalMapping: [historyIdentity: .init(
            token: .init(rawValue: "committed-history-token"),
            contentGeneration: 7
        )],
        historyLogicalIdentities: [historyIdentity],
        historyClosureIdentities: [historyIdentity]
    )
}

private func makeCommit(
    generation: UInt64,
    historyPin: SceneGraphRenderTargetResidencyPin? = nil
) -> ScenePreparedPersistentGraphTargets.Commit {
    .init(
        leases: [],
        submissionPin: .init(purpose: .submission, generation: generation),
        historyPinsByEffect: historyPin.map { [effect: $0] } ?? [:]
    )
}

private func makeLedger(
    coordinator: Coordinator,
    identity: UInt64,
    commandBuffer: MTLCommandBuffer,
    prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph,
    preparedDependencyEffects: [SceneDependencyEffectInput] = [],
    commit: ScenePreparedPersistentGraphTargets.Commit,
    blueprint: Coordinator.CandidateBlueprint? = nil,
    candidate: [Graph.EffectKey: Coordinator.Tail]? = nil,
    phase: Coordinator.LedgerPhase,
    submissionID: UInt64? = nil,
    claimed: Bool = true,
    consumed: Bool = false
) -> Coordinator.PreparedLedger {
    .init(
        identity: identity,
        epoch: coordinator.executionEpoch,
        frameIndex: identity,
        layerID: 7,
        capabilityToken: .init(value: 7),
        prepared: prepared,
        preparedDependencyEffects: preparedDependencyEffects,
        preparedDependencyUnavailability: nil,
        commandBuffer: commandBuffer,
        committedBaseTails: coordinator.committedTails,
        blueprint: blueprint,
        candidateTails: candidate,
        commit: commit,
        phase: phase,
        claimConsumed: claimed,
        ticketConsumed: consumed,
        outputConsumed: consumed,
        compositorConsumed: consumed,
        submissionID: submissionID
    )
}

private func externalPrimaryBinding(
    consumerLayerID: Int = 7,
    providerLayerID: Int = 42,
    slotIndex: Int = 1,
    blendMode: Int = 0,
    kind: SceneDependencyRenderPlan.Binding.Kind = .resolvedMaterial,
    requiresResolvedMaterialProgram: Bool = false
) -> SceneDependencyRenderPlan.Binding {
    .init(
        consumerLayerID: consumerLayerID,
        providerLayerID: providerLayerID,
        slot: .init(
            effectID: "effect-\(consumerLayerID)",
            passIndex: 0,
            slotIndex: slotIndex
        ),
        blendMode: blendMode,
        kind: kind,
        requiresResolvedMaterialProgram: requiresResolvedMaterialProgram
    )
}

private func dependencyInput(
    binding: SceneDependencyRenderPlan.Binding,
    texture: MTLTexture,
    frameEpoch: UInt64 = 13,
    consumerLayerID: Int? = nil,
    providerLayerID: Int? = nil,
    variant: SceneNamedTextureReference.Variant = .primary,
    slot: SceneEffectPassSlot? = nil,
    blendMode: Int? = nil
) -> SceneDependencyEffectInput {
    .init(
        consumerLayerID: consumerLayerID ?? binding.consumerLayerID,
        providerLayerID: providerLayerID ?? binding.providerLayerID,
        variant: variant,
        slot: slot ?? binding.slot,
        blendMode: blendMode ?? binding.blendMode,
        frameEpoch: frameEpoch,
        texture: texture
    )
}

private func makeCapabilities(
    layerIDs: [Int] = [7],
    dependencyOwnershipByLayerID: [
        Int: SceneResolvedMaterialDependencyOwnership
    ] = [:],
    visualFailureReasonByLayerID: [Int: String] = [:],
    resolvesClaims: Bool = true
) -> SceneResolvedMaterialExecutionCapabilityCatalog {
    let capabilities = layerIDs.map { layerID ->
        SceneResolvedMaterialExecutionCapabilityCatalog.ChainCapability in
        let key = effect(for: layerID)
        let graph = Graph(
            layerID: layerID,
            effects: [.init(key: key)],
            nodes: [.init(nodeIndex: 0, kind: .material)]
        )
        return .init(
            layerID: layerID,
            pairPlan: .init(layerID: layerID),
            admittedProducts: [.init(graph: graph)],
            stages: [.init(
                subject: .init(
                    key: key,
                    family: visualFailureReasonByLayerID[layerID] == nil
                        ? "resolved-material" : "visual-failure-passthrough"
                ),
                visualFailureReasonCode: visualFailureReasonByLayerID[layerID]
            )],
            dependencyOwnership:
                dependencyOwnershipByLayerID[layerID] ?? .none,
            sourceRoute: .capturedLayerTexture
        )
    }
    return .init(
        capability: capabilities.first,
        additionalCapabilities: Array(capabilities.dropFirst()),
        resolvesClaims: resolvesClaims
    )
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func makeCoordinator(
    _ device: MTLDevice,
    layerIDs: [Int] = [7],
    dependencyOwnershipByLayerID: [
        Int: SceneResolvedMaterialDependencyOwnership
    ] = [:],
    resolvesClaims: Bool = true,
    logSink: @escaping Coordinator.LogSink = { _ in }
) -> Coordinator {
    .init(
        device: device,
        capabilities: makeCapabilities(
            layerIDs: layerIDs,
            dependencyOwnershipByLayerID: dependencyOwnershipByLayerID,
            resolvesClaims: resolvesClaims
        ),
        logSink: logSink
    )
}

private func seedPendingSuccess(
    coordinator: Coordinator,
    identity: UInt64,
    commandBuffer: MTLCommandBuffer,
    tail: Coordinator.Tail?,
    commit: ScenePreparedPersistentGraphTargets.Commit,
    prepared: SceneResolvedMaterialGraphExecutor.PreparedGraph? = nil
) {
    _ = coordinator.observeCommandBufferLocked(commandBuffer)
    let ledger = makeLedger(
        coordinator: coordinator,
        identity: identity,
        commandBuffer: commandBuffer,
        prepared: prepared ?? makePrepared(device: commandBuffer.device),
        commit: commit,
        candidate: tail.map { [effect: $0] } ?? [:],
        phase: .sealed,
        submissionID: identity,
        consumed: true
    )
    coordinator.activeByID[identity] = ledger
    coordinator.pendingSubmissions.append(.init(
        identity: identity,
        ledgerIDs: [identity],
        commandBufferIdentities: [ObjectIdentifier(commandBuffer)],
        finalTails: tail.map { [effect: $0] } ?? [:],
        gpuStatus: nil,
        cancellationReason: nil,
        retiredHistoryPins: []
    ))
    coordinator.scheduledTails = tail.map { [effect: $0] } ?? [:]
}

private struct CancellationResult {
    let graphLines: [String]
    let releasedPins: Bool
    let clearedState: Bool
}

private func runPendingCancellation(
    device: MTLDevice,
    queue: MTLCommandQueue,
    reasonCode: String,
    gpuStatus: SceneGraphExecutionGPUCompletionStatus,
    consumed: Bool = true
) -> CancellationResult {
    let recorder = LogRecorder()
    let coordinator = makeCoordinator(
        device,
        logSink: { recorder.append($0) }
    )
    let commandBuffer = queue.makeCommandBuffer()!
    _ = coordinator.observeCommandBufferLocked(commandBuffer)
    let historyPin = SceneGraphRenderTargetResidencyPin(
        purpose: .history(effect, [.init(rawValue: "cancelled-history")]),
        generation: 3
    )
    let retiredPin = SceneGraphRenderTargetResidencyPin(
        purpose: .history(effect, [.init(rawValue: "retired-history")]),
        generation: 2
    )
    let commit = makeCommit(generation: 3, historyPin: historyPin)
    let tail = makeTail(
        device: device,
        token: "cancelled-history",
        generation: 3,
        pin: historyPin
    )
    coordinator.activeByID[1] = makeLedger(
        coordinator: coordinator,
        identity: 1,
        commandBuffer: commandBuffer,
        prepared: makeObservedPrepared(device: device),
        commit: commit,
        candidate: [effect: tail],
        phase: .sealed,
        submissionID: 1,
        consumed: consumed
    )
    coordinator.pendingSubmissions = [.init(
        identity: 1,
        ledgerIDs: [1],
        commandBufferIdentities: [ObjectIdentifier(commandBuffer)],
        finalTails: [effect: tail],
        gpuStatus: nil,
        cancellationReason: reasonCode,
        retiredHistoryPins: [retiredPin]
    )]
    coordinator.completeCommandBuffer(
        identity: ObjectIdentifier(commandBuffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(commandBuffer)]?.observationID ?? 0,
        status: gpuStatus
    )
    return .init(
        graphLines: recorder.lines.filter {
            $0.contains("axis=graph-execution")
        },
        releasedPins: commit.submissionPin.releaseCount == 1
            && historyPin.releaseCount == 1
            && retiredPin.releaseCount == 1,
        clearedState: coordinator.activeByID.isEmpty
            && coordinator.pendingSubmissions.isEmpty
    )
}

private func recordedFailure(
    _ result: CancellationResult,
    reasonCode: String,
    gpuStatus: SceneGraphExecutionGPUCompletionStatus?
) -> Bool {
    let gpu = gpuStatus?.rawValue ?? "-"
    return result.releasedPins
        && result.clearedState
        && result.graphLines.contains {
            $0.contains("outcome=failed")
                && $0.contains("failure=\(reasonCode)")
                && $0.contains("gpuCompletion=\(gpu)")
                && !$0.contains("diagnostic=")
    }
}

private struct DependencyExecutionProbe {
    let reasonCode: String
    let consumesExternalPrimaryDependency: Bool?
}

private func executeExternalDependency(
    device: MTLDevice,
    queue: MTLCommandQueue,
    binding: SceneDependencyRenderPlan.Binding,
    preparedDependencyEffect: SceneDependencyEffectInput?,
    readyDependencyEffect: SceneDependencyEffectInput?
) -> DependencyExecutionProbe {
    SceneResolvedMaterialGraphExecutor.encodeSucceeds = true
    let coordinator = makeCoordinator(
        device,
        dependencyOwnershipByLayerID: [7: .externalPrimary(binding)]
    )
    let buffer = queue.makeCommandBuffer()!
    let commit = makeCommit(generation: 1)
    coordinator.frameIsActive = true
    coordinator.frame = .init(frameIndex: 13)
    coordinator.activeByID[1] = makeLedger(
        coordinator: coordinator,
        identity: 1,
        commandBuffer: buffer,
        prepared: makePrepared(device: device),
        preparedDependencyEffects:
            preparedDependencyEffect.map { [$0] } ?? [],
        commit: commit,
        phase: .allocationCommitted,
        claimed: false
    )
    coordinator.activeTransactions = [1]
    coordinator.preparedLedgerByLayerID = [7: 1]
    coordinator.framePreparationComplete = true
    let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
    switch coordinator.claim(layerID: 7) {
    case let .claimed(value): claim = value
    case let .rejected(reasonCode):
        return .init(
            reasonCode: reasonCode,
            consumesExternalPrimaryDependency: nil
        )
    case .notMigrated:
        return .init(
            reasonCode: "not-migrated",
            consumesExternalPrimaryDependency: nil
        )
    }
    switch coordinator.executeClaimed(
        claim: claim,
        dependencyEffects: readyDependencyEffect.map { [$0] } ?? [],
        commandBuffer: buffer
    ) {
    case let .encoded(_, ticket):
        return .init(
            reasonCode: "encoded",
            consumesExternalPrimaryDependency:
                ticket.consumesExternalPrimaryDependency
        )
    case let .failed(reasonCode):
        return .init(
            reasonCode: reasonCode,
            consumesExternalPrimaryDependency: nil
        )
    }
}

