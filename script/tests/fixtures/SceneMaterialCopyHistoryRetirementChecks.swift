private struct PendingCoordinatorFrame {
    let commandBuffer: MTLCommandBuffer
    let currentReadback: Readback?
    let historyReadback: Readback?
    let outputReadback: Readback
    let finalContent: SceneTextureContent
    let finalTexture: MTLTexture
}

private func claimedExecution(
    catalog: Capabilities,
    admitted: AdmittedLayerGraph
) -> SceneResolvedMaterialRuntimeBridge.ClaimedExecution {
    guard let claim = catalog.claim(admitted),
          let capability = catalog.resolve(claim.token),
          capability.layerID == admitted.layerID,
          capability.effectSubjectsAreConserved else {
        fatalError("coordinator claim unavailable layer=\(admitted.layerID) "
            + catalog.reportLines.joined(separator: " | "))
    }
    return .init(
        layerID: admitted.layerID,
        pairPlan: capability.pairPlan,
        dependencyOwnership: capability.dependencyOwnership,
        sourceRoute: capability.sourceRoute,
        token: claim.token
    )
}

private func consumePreparedClaim(
    _ claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
    coordinator: SceneResolvedMaterialSubmissionCoordinator
) {
    coordinator.lock.lock()
    defer { coordinator.lock.unlock() }
    guard let identity = coordinator.preparedLedgerByLayerID[claim.layerID],
          var ledger = coordinator.activeByID[identity],
          ledger.capabilityToken == claim.token,
          ledger.phase == .allocationCommitted,
          !ledger.claimConsumed else {
        fatalError("prepared coordinator claim unavailable")
    }
    ledger.claimConsumed = true
    coordinator.activeByID[identity] = ledger
    coordinator.frameClaimed += 1
}

private func submitCoordinatorFrame(
    index: UInt64,
    coordinator: SceneResolvedMaterialSubmissionCoordinator,
    claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
    graph: Graph,
    executionPlan: SceneEffectStageExecutionPlan,
    pool: SceneOffscreenTexturePool,
    source: MTLTexture,
    pipeline: SceneImageLayerPipeline,
    queue: MTLCommandQueue,
    expectedContent: SceneTextureContent,
    usesExternalResourceBundle: Bool = true,
    dependencyEffects: [SceneDependencyEffectInput] = [], requiresHistory: Bool = true,
    enqueue: Bool = true, waitEvent: MTLSharedEvent? = nil, includesSceneColor: Bool = false
) -> PendingCoordinatorFrame {
    guard let commandBuffer = queue.makeCommandBuffer() else {
        fatalError("coordinator command buffer unavailable")
    }
    if let waitEvent { commandBuffer.encodeWaitForEvent(waitEvent, value: 1) }
    beginFrame(coordinator, index: index)
    let allocation = framePlan(
        pool: pool,
        graph: graph,
        commandBuffer: commandBuffer
    )
    let targetPlan = SceneResolvedMaterialFrameTargetPlan(
        token: claim.token,
        allocation: allocation
    )
    let request = SceneResolvedMaterialRuntimeBridge.FramePreparationRequest(
        claim: claim,
        targetPlan: targetPlan,
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: pipeline,
        frameInputs: .init(dependencyEffects: dependencyEffects)
    )
    let bundle = usesExternalResourceBundle ? coordinator.prepareFrameResourceBundle(
        plans: [targetPlan], pool: pool, commandBuffer: commandBuffer) : nil
    if usesExternalResourceBundle && bundle == nil { fatalError("resource bundle allocation failed") }
    let generations = pool.allocationCache.locked {
        Set(pool.allocationCache.residents.compactMap { key, entry -> UInt64? in
            if !requiresHistory {
                return entry.preparationPins.isEmpty ? nil : entry.allocation.generation
            }
            if case .pending = key { return entry.allocation.generation }
            return nil
        })
    }
    switch coordinator.prepareFrame(
        [request], pool: pool, commandBuffer: commandBuffer, resourceBundle: bundle
    ) {
    case .ready:
        break
    case let .rejected(reason):
        fatalError("coordinator frame preparation failed: \(reason)")
    }
    if usesExternalResourceBundle {
        bundle?.cancel() // Ownership already moved; cannot cancel the local commit.
        guard let identity = coordinator.preparedLedgerByLayerID[claim.layerID],
              let commit = coordinator.activeByID[identity]?.commit,
              generations.contains(commit.submissionPin.generation),
              pool.allocationCache.locked({ pool.allocationCache.residents.values.allSatisfy {
                  $0.preparationPins.isEmpty
              } }) else { fatalError("external bundle did not transfer exact targets") }
    }
    consumePreparedClaim(claim, coordinator: coordinator)

    let texture: MTLTexture
    let ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket
    switch coordinator.executeClaimed(
        claim: claim,
        dependencyEffects: dependencyEffects,
        commandBuffer: commandBuffer
    ) {
    case let .encoded(value, valueTicket):
        texture = value
        ticket = valueTicket
    case let .failed(reason):
        fatalError("coordinator execution failed: \(reason)")
    }
    let outputConsumed: SceneResolvedMaterialRuntimeBridge.CompositeOutcome
    if expectedContent == .data {
        outputConsumed = coordinator.markNamedPublication(
            ticket,
            texture: texture,
            published: true
        )
    } else {
        outputConsumed = coordinator.markComposite(
            ticket,
            texture: texture,
            consumed: true
        )
    }
    if includesSceneColor {
        guard let color = coordinator.reserveSceneColor(pool: pool, width: extent.width,
                height: extent.height, frameIndex: index, commandBuffer: commandBuffer, intent: .snapshot),
              let encoder = commandBuffer.makeBlitCommandEncoder()
        else { fatalError("lifecycle scene color unavailable") }
        encoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: extent.width, height: extent.height, depth: 1),
            to: color.raw, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
        encoder.endEncoding()
        precondition(coordinator.markSceneColorSnapshot(on: commandBuffer))
    }
    guard ticket.finalContent == expectedContent,
          let stage = coordinator.activeByID[ticket.identity]?.prepared.stages.first,
          texture.width == extent.width, texture.height == extent.height,
          case .consumed = outputConsumed,
          coordinator.sealFrame(on: commandBuffer),
          let outputReadback = appendReadback(texture, commandBuffer: commandBuffer)
    else { fatalError("coordinator publication or compositor failed") }
    let currentTexture = graph.renderTargets.first { $0.texture.name == "current" }
        .flatMap { stage.frameResources[$0.texture]?.publication.texture }
    let historyTexture = graph.renderTargets.first { $0.texture.name == "history" }
        .flatMap { stage.frameResources[$0.texture]?.publication.texture }
    let currentReadback = currentTexture.flatMap { appendReadback($0, commandBuffer: commandBuffer) }
    let historyReadback = historyTexture.flatMap { appendReadback($0, commandBuffer: commandBuffer) }
    if requiresHistory {
        guard let currentTexture, let historyTexture, currentReadback != nil, historyReadback != nil,
              currentTexture.width == extent.width, currentTexture.height == extent.height,
              historyTexture.width == extent.width, historyTexture.height == extent.height
        else { fatalError("history readback unavailable") }
    }
    if enqueue { commandBuffer.commit() }
    _ = coordinator.endFrame()
    return .init(
        commandBuffer: commandBuffer,
        currentReadback: currentReadback,
        historyReadback: historyReadback,
        outputReadback: outputReadback,
        finalContent: ticket.finalContent, finalTexture: texture
    )
}

private func completeCoordinatorFrame(
    _ pending: PendingCoordinatorFrame,
    coordinator: SceneResolvedMaterialSubmissionCoordinator
) -> CoordinatorFrameResult {
    let commandBuffer = pending.commandBuffer
    commandBuffer.waitUntilCompleted()
    let completed = commandBuffer.status == .completed && commandBuffer.error == nil
    coordinator.completeCommandBuffer(
        identity: ObjectIdentifier(commandBuffer), observationID: coordinator.commandBufferRecords[ObjectIdentifier(commandBuffer)]?.observationID ?? 0,
        status: completed ? .completed : .failed
    )
    return .init(
        currentPixels: pending.currentReadback?.pixels ?? [],
        historyPixels: pending.historyReadback?.pixels ?? [],
        outputPixels: pending.outputReadback.pixels,
        completed: completed,
        finalContent: pending.finalContent
    )
}


private func retirementPeerGraph() -> Graph {
    let owner = Graph.EffectKey(layerID: 92, effectIndex: 0, descriptorID: "healthy-current")
    let ingress = Graph.TextureIdentity(kind: .layerSource, layerID: 92, effect: nil, name: nil)
    let terminal = Graph.TextureIdentity(kind: .effectOutput, layerID: 92, effect: owner, name: nil)
    let node = material(2, ordinal: 0, target: terminal,
        bindings: [binding(slot: 0, name: "previous", texture: ingress)],
        owner: owner, materialPassID: "healthy#0")
    return .init(layerID: 92, effects: [.init(key: owner,
        definitionPath: "effects/healthy/effect.json", input: ingress, output: terminal,
        nodeIndices: [2])], renderTargets: [], nodes: [node], finalOutput: terminal, blockers: [])
}

private func retirementDescriptor(
    _ graphs: [Graph], namedConsumer: Int? = nil, namedProvider: Int? = nil
) -> SceneRenderDescriptor {
    var layers = graphs.flatMap { descriptor(for: $0).layers }
    if let consumer = namedConsumer, let provider = namedProvider,
       let index = layers.firstIndex(where: { $0.id == consumer }) {
        let slot = SceneEffectPassSlot(effectID: graphs.first { $0.layerID == consumer }!
            .effects[0].key.descriptorID, passIndex: 0, slotIndex: 1)
        layers[index].dependencyLayerIDs = [provider]
        layers[index].namedReferences = [.init(consumerLayerID: consumer,
            providerLayerID: provider, slot: slot, variant: .primary)]
        layers[index].namedBindings = [.init(consumerLayerID: consumer,
            providerLayerID: provider, slot: slot, blendMode: 0, kind: .resolvedMaterial)]
        layers[layers.firstIndex { $0.id == provider }!].visible = false
    }
    var definitionPaths: Set<String> = []
    var materialPassIDs: Set<String> = []
    return .init(layers: layers,
        materialPasses: graphs.flatMap { descriptor(for: $0).materialPasses }
            .filter { materialPassIDs.insert($0.id).inserted },
        effectDefinitions: graphs.flatMap { descriptor(for: $0).effectDefinitions }
            .filter { definitionPaths.insert($0.relativePath).inserted })
}

private func retirementCapabilities(
    _ graphs: [Graph], descriptor: SceneRenderDescriptor,
    namedConsumer: Int? = nil, namedProvider: Int? = nil
) -> Capabilities {
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    for renderGraph in graphs {
        for node in renderGraph.nodes where node.kind == .material {
            let named: SceneNamedTextureReference? = renderGraph.layerID == namedConsumer && node.nodeIndex == 0
                ? namedProvider.map { .init(providerLayerID: $0, variant: .primary) } : nil
            let value = template(for: node, mixWeight: 0.25, content: .color, namedProvider: named)
            entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value,
                textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
        }
    }
    return try! .init(admissionCandidates: SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor, authoredPlans: graphs),
        materialCatalog: .init(entries: entries, resourceDemandIssues: []))
}

private func adoptHistoryTopology(
    _ surface: SceneDesktopWallpaperSession.Surface, revision: UInt64,
    destroyed: Set<Int>, frame: UInt64
) {
    surface.updateSimulation(timing: .init(frameIndex: frame),
        dynamicValues: .empty(frameIndex: frame), puppetAnimationFrame: [:], spriteTimes: [:],
        layerTopology: .init(topologyRevision: revision, destroyedAuthoredLayerIDs: destroyed),
        mediaThumbnail: .init(), mediaInputGeneration: 0)
}

private func historyPinCount(_ pool: SceneOffscreenTexturePool, layer: Int) -> Int {
    pool.allocationCache.locked {
        pool.allocationCache.residents.values.reduce(0) { count, entry in
            count + entry.historyPins.values.filter { $0.effect.layerID == layer }.count
        }
    }
}

private func historyLayerIDs(_ tails: [Graph.EffectKey: SceneResolvedMaterialSubmissionCoordinator.Tail]) -> Set<Int> {
    Set(tails.keys.map(\.layerID))
}

private struct HistoryRetirementFixture {
    let victim = graph()
    let peer = retirementPeerGraph()
    let descriptor: SceneRenderDescriptor
    let catalog: Capabilities
    let owner: SceneResolvedMaterialSubmissionCoordinator
    let pool: SceneOffscreenTexturePool
    let surface: SceneDesktopWallpaperSession.Surface
    init(_ device: MTLDevice, additional: [Graph] = [],
         logSink: @escaping SceneResolvedMaterialSubmissionCoordinator.LogSink = { _ in }) {
        let graphs = [victim, peer] + additional
        descriptor = retirementDescriptor(graphs)
        catalog = retirementCapabilities(graphs, descriptor: descriptor)
        owner = .init(device: device, capabilities: catalog, logSink: logSink)
        pool = .init(device: device, maxDimension: 64, residentByteBudget: 1_048_576)
        surface = .init(owner, descriptor: descriptor)
        adoptHistoryTopology(surface, revision: 0, destroyed: [], frame: 0)
    }
    func submit(
        _ renderGraph: Graph, index: UInt64, source: MTLTexture, pipeline: SceneImageLayerPipeline,
        queue: MTLCommandQueue, enqueue: Bool = true, waitEvent: MTLSharedEvent? = nil,
        includesSceneColor: Bool = false
    ) -> PendingCoordinatorFrame {
        submitCoordinatorFrame(index: index, coordinator: owner,
            claim: claimedExecution(catalog: catalog, admitted: admitted(renderGraph)),
            graph: renderGraph, executionPlan: admitted(renderGraph).stagePrograms[0].executionPlan,
            pool: pool, source: source, pipeline: pipeline, queue: queue,
            expectedContent: .color(.resolved(.straightAlpha)),
            requiresHistory: !renderGraph.renderTargets.isEmpty, enqueue: enqueue, waitEvent: waitEvent,
            includesSceneColor: includesSceneColor)
    }
    func close() {
        owner.invalidate(reason: .surfaceStop)
        pool.reset()
    }
}

private func completedRetirementChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> [String: Bool] {
    let fixture = HistoryRetirementFixture(device)
    defer { fixture.close() }
    let owner = fixture.owner
    let first = completeCoordinatorFrame(fixture.submit(fixture.victim, index: 0,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    // Keep the exact old value alive; explicit pin release must not depend on ARC.
    let frozenTail = owner.committedTails[effect]!
    let generation = (owner.executionEpoch, owner.effectGeneration, owner.resetGeneration)
    let before = historyPinCount(fixture.pool, layer: layerID)
    _ = fixture.surface.sceneScriptPausedSurfaceInput(timing: .init(frameIndex: 0),
        dynamicValues: .empty(frameIndex: 0))
    let held = owner.committedTails[effect]?.historyPin === frozenTail.historyPin
        && fixture.surface.simulationFrame?.topology.destroyedAuthoredLayerIDs.isEmpty == true
        && historyPinCount(fixture.pool, layer: layerID) == before
    adoptHistoryTopology(fixture.surface, revision: 1, destroyed: [layerID], frame: 1)
    let retired = owner.committedTails.isEmpty && owner.scheduledTails.isEmpty
        && historyPinCount(fixture.pool, layer: layerID) == 0
    let peer = fixture.submit(fixture.peer, index: 1, source: source,
        pipeline: pipeline, queue: queue, enqueue: false)
    let independent = owner.pendingSubmissions.count == 1
        && owner.pendingSubmissions[0].finalTails.isEmpty && !owner.shouldDeferFrame
    owner.cancelUnsubmittedFrame(on: peer.commandBuffer)
    let cancelled = owner.pendingSubmissions.isEmpty && owner.activeByID.isEmpty
        && historyLayerIDs(owner.scheduledTails).isEmpty
    adoptHistoryTopology(fixture.surface, revision: 1, destroyed: [layerID], frame: 1)
    adoptHistoryTopology(fixture.surface, revision: 2, destroyed: [layerID], frame: 2)
    let peerOne = completeCoordinatorFrame(fixture.submit(fixture.peer, index: 2,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    let peerTwo = completeCoordinatorFrame(fixture.submit(fixture.peer, index: 3,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    return [
        "qualifiedHistoryPixels": first.completed && approximately(first.outputPixels, expected(scale: 0.25))
            && before > 0 && !frozenTail.persistentResources.isEmpty,
        "heldAdoptedHistoryPreserved": held,
        "adoptedDestroyReleasesOnlyFutureHistory": retired,
        "healthyPeerNoLongerSerializesOnDeadTail": independent,
        "unsubmittedPeerCancelKeepsRetiredState": cancelled,
        "repeatAndOrderOnlyTopologyDoNotRevive": owner.committedTails.isEmpty && owner.scheduledTails.isEmpty,
        "healthyPeerPixelsAcrossFrames": peerOne.completed && peerTwo.completed
            && approximately(peerOne.outputPixels, expected(scale: 1))
            && peerOne.outputPixels == peerTwo.outputPixels,
        "retirementKeepsGenerations": generation.0 == owner.executionEpoch
            && generation.1 == owner.effectGeneration && generation.2 == owner.resetGeneration,
    ]
}

private func inFlightRetirementChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline,
    terminal: SceneGraphExecutionGPUCompletionStatus
) -> [String: Bool] {
    let fixture = HistoryRetirementFixture(device)
    defer { fixture.close() }
    let owner = fixture.owner
    _ = completeCoordinatorFrame(fixture.submit(fixture.victim, index: 0,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    let frozen = owner.committedTails[effect]!
    let event = device.makeSharedEvent()!
    defer { event.signaledValue = 1 }
    let pending = fixture.submit(fixture.victim, index: 1,
        source: source, pipeline: pipeline, queue: queue, waitEvent: event)
    let beforePins = historyPinCount(fixture.pool, layer: layerID)
    let pendingLedger = owner.activeByID.values.first { $0.layerID == layerID }!
    let prepared = pendingLedger.prepared
    let observation = owner.commandBufferRecords[ObjectIdentifier(pending.commandBuffer)]!.observationID
    adoptHistoryTopology(fixture.surface, revision: 1, destroyed: [layerID], frame: 2)
    let futureRetired = owner.committedTails.isEmpty && owner.scheduledTails.isEmpty
        && owner.pendingSubmissions.allSatisfy { $0.finalTails.isEmpty }
    let held = historyPinCount(fixture.pool, layer: layerID) == beforePins && beforePins > 0
        && owner.activeByID[pendingLedger.identity]?.prepared.finalTexture === prepared.finalTexture
        && frozen.historyPin != nil && !prepared.historyTokensByEffect.isEmpty
    var peerCancel = false
    if !owner.shouldDeferFrame {
        let peer = fixture.submit(fixture.peer, index: 2, source: source,
            pipeline: pipeline, queue: queue, enqueue: false)
        owner.cancelUnsubmittedFrame(on: peer.commandBuffer)
        peerCancel = owner.pendingSubmissions.count == 1
            && historyPinCount(fixture.pool, layer: layerID) == beforePins
    }
    event.signaledValue = 1
    pending.commandBuffer.waitUntilCompleted()
    let completed = pending.commandBuffer.status == .completed && pending.commandBuffer.error == nil
    // Failure injection uses the original completion seam after real GPU work.
    owner.completeCommandBuffer(identity: ObjectIdentifier(pending.commandBuffer),
        observationID: observation, status: terminal)
    let drained = owner.pendingSubmissions.isEmpty && owner.activeByID.isEmpty
        && historyPinCount(fixture.pool, layer: layerID) == 0
    owner.completeCommandBuffer(identity: ObjectIdentifier(pending.commandBuffer),
        observationID: observation, status: .completed)
    return [
        "oldAndNewHistoryHeldThroughRealGPUWait": held,
        "pendingPromotionRetiredAtAdoption": futureRetired,
        "laterUnsubmittedPeerCancelDoesNotReleaseOldGPUInputs": peerCancel,
        "realGPUStillReadsFrozenHistory": completed
            && approximately(pending.outputReadback.pixels, expected(scale: 0.4375)),
        "terminalReleasesRetiredPins": drained,
        "lateRepeatedCompletionCannotRepromote": owner.committedTails.isEmpty && owner.scheduledTails.isEmpty,
    ]
}

private func retirementThenStopChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> [String: Bool] {
    let healthy = graph(layer: 93)
    let fixture = HistoryRetirementFixture(device, additional: [healthy])
    let owner = fixture.owner
    _ = completeCoordinatorFrame(fixture.submit(healthy, index: 0,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    _ = completeCoordinatorFrame(fixture.submit(fixture.victim, index: 1,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    let frozen = owner.committedTails
    let event = device.makeSharedEvent()!
    defer { event.signaledValue = 1; fixture.close() }
    let pending = fixture.submit(fixture.victim, index: 2,
        source: source, pipeline: pipeline, queue: queue, waitEvent: event)
    let beforeVictim = historyPinCount(fixture.pool, layer: layerID)
    let beforeHealthy = historyPinCount(fixture.pool, layer: healthy.layerID)
    adoptHistoryTopology(fixture.surface, revision: 1, destroyed: [layerID], frame: 3)
    let healthyUnchanged = historyLayerIDs(owner.committedTails) == [healthy.layerID]
        && owner.committedTails[healthy.effects[0].key]?.historyPin === frozen[healthy.effects[0].key]?.historyPin
    owner.invalidate(reason: .surfaceStop)
    let held = historyPinCount(fixture.pool, layer: layerID) == beforeVictim
        && historyPinCount(fixture.pool, layer: healthy.layerID) == beforeHealthy
        && beforeVictim > 0 && beforeHealthy > 0
    event.signaledValue = 1
    _ = completeCoordinatorFrame(pending, coordinator: owner)
    return [
        "unrelatedHistoryOwnerUnchanged": healthyUnchanged,
        "stopKeepsBothRetiredAndLivePinsUntilTerminal": held,
        "stopMergesPinsRatherThanDroppingLiveHistory": historyPinCount(fixture.pool, layer: layerID) == 0
            && historyPinCount(fixture.pool, layer: healthy.layerID) == 0
            && !frozen.isEmpty && owner.pendingSubmissions.isEmpty && owner.activeByID.isEmpty,
        "stopCannotPromoteRetiredTails": owner.committedTails.isEmpty && owner.scheduledTails.isEmpty,
    ]
}

func graphSceneColorCancellationChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> [String: [String: Bool]] {
    var results: [String: [String: Bool]] = [:]
    for reason: SceneGraphExecutionResetReason in [.surfaceStop, .sceneSwitch] {
        let recorder = LogRecorder()
        let fixture = HistoryRetirementFixture(device, logSink: { recorder.append($0) })
        let owner = fixture.owner
        _ = completeCoordinatorFrame(fixture.submit(fixture.victim, index: 0,
            source: source, pipeline: pipeline, queue: queue), coordinator: owner)
        let previous = owner.committedTails[effect]!
        let event = device.makeSharedEvent()!
        defer { event.signaledValue = 1; fixture.close() }
        let pending = fixture.submit(fixture.victim, index: 1,
            source: source, pipeline: pipeline, queue: queue, waitEvent: event, includesSceneColor: true)
        let registration = owner.commandBufferRecords[ObjectIdentifier(pending.commandBuffer)]!.observationID
        let color = owner.pendingSubmissions[0].sceneColor!
        let pins = historyPinCount(fixture.pool, layer: layerID)
        let sealed = owner.pendingSubmissions.count == 1
            && owner.pendingSubmissions[0].ledgerIDs.count == 1
            && !owner.pendingSubmissions[0].finalTails.isEmpty
            && color.snapshotCopied && pins > 0
        owner.invalidate(reason: reason); fixture.pool.reset()
        let held = owner.pendingSubmissions.count == 1 && owner.activeByID.count == 1
            && owner.completedSceneColor == nil && owner.committedTails.isEmpty
            && color.epoch != owner.executionEpoch && !color.matchesCurrentEpoch
            && historyPinCount(fixture.pool, layer: layerID) == pins
            && fixture.pool.residentByteCost > 0
        event.signaledValue = 1
        let completed = completeCoordinatorFrame(pending, coordinator: owner)
        let logBeforeReplay = recorder.lines
        let retired = owner.pendingSubmissions.isEmpty && owner.activeByID.isEmpty
            && owner.commandBufferRecords.isEmpty && historyPinCount(fixture.pool, layer: layerID) == 0
            && fixture.pool.residentTextureCount == 0 && fixture.pool.residentByteCost == 0
        owner.completeCommandBuffer(identity: ObjectIdentifier(pending.commandBuffer),
            observationID: registration, status: .completed)
        results[reason.rawValue] = [
            "realGraphHistoryAndSceneColorSealed": sealed && !previous.persistentResources.isEmpty,
            "invalidatedContentHeldUntilGPUTerminal": held,
            "actualGPUReadsPriorHistory": completed.completed
                && approximately(completed.outputPixels, expected(scale: 0.4375)),
            "normalLifecycleHasNoFalseFailure": !logBeforeReplay.contains {
                $0.contains("outcome=failed") || $0.contains("lifecycle-cancellation-ledger-invariant-rejected")
            },
            "allPinsRetiredWithoutPromotion": retired && owner.completedSceneColor == nil
                && owner.committedTails.isEmpty && owner.scheduledTails.isEmpty,
            "repeatedTerminalCannotRepublishOrReleaseAgain": recorder.lines == logBeforeReplay
                && owner.pendingSubmissions.isEmpty && owner.activeByID.isEmpty
                && owner.completedSceneColor == nil && fixture.pool.residentByteCost == 0,
        ]
    }
    return results
}

private func reverseCompletionRetirementChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> [String: Bool] {
    let fixture = HistoryRetirementFixture(device)
    defer { fixture.close() }
    let owner = fixture.owner
    _ = completeCoordinatorFrame(fixture.submit(fixture.victim, index: 0,
        source: source, pipeline: pipeline, queue: queue), coordinator: owner)
    let frozen = owner.committedTails[effect]!
    let event = device.makeSharedEvent()!
    defer { event.signaledValue = 1 }
    let first = fixture.submit(fixture.victim, index: 1,
        source: source, pipeline: pipeline, queue: queue, waitEvent: event)
    let firstObservation = owner.commandBufferRecords[ObjectIdentifier(first.commandBuffer)]!.observationID
    adoptHistoryTopology(fixture.surface, revision: 1, destroyed: [layerID], frame: 2)
    var reverseHeld = false
    var peerPixels = false
    if !owner.shouldDeferFrame {
        let second = fixture.submit(fixture.peer, index: 2,
            source: source, pipeline: pipeline, queue: queue)
        let secondObservation = owner.commandBufferRecords[ObjectIdentifier(second.commandBuffer)]!.observationID
        event.signaledValue = 1
        first.commandBuffer.waitUntilCompleted()
        second.commandBuffer.waitUntilCompleted()
        owner.completeCommandBuffer(identity: ObjectIdentifier(second.commandBuffer),
            observationID: secondObservation, status: .completed)
        reverseHeld = owner.pendingSubmissions.count == 2 && owner.committedTails.isEmpty
            && historyPinCount(fixture.pool, layer: layerID) > 0 && frozen.historyPin != nil
        peerPixels = second.commandBuffer.status == .completed && second.commandBuffer.error == nil
            && approximately(second.outputReadback.pixels, expected(scale: 1))
    }
    event.signaledValue = 1
    first.commandBuffer.waitUntilCompleted()
    owner.completeCommandBuffer(identity: ObjectIdentifier(first.commandBuffer),
        observationID: firstObservation, status: .completed)
    return [
        "reverseTerminalWaitsForOriginalGPUOwner": reverseHeld,
        "independentPeerRealPixels": peerPixels,
        "orderedDrainCannotRepromoteDeadHistory": owner.pendingSubmissions.isEmpty
            && owner.committedTails.isEmpty && owner.scheduledTails.isEmpty
            && owner.activeByID.isEmpty && historyPinCount(fixture.pool, layer: layerID) == 0,
    ]
}

private struct NamedHistoryFrame {
    let provider: CoordinatorFrameResult
    let consumer: CoordinatorFrameResult
    let publication: SceneFrameTextureResource
}

private func submitNamedHistoryFrame(
    index: UInt64, owner: SceneResolvedMaterialSubmissionCoordinator, catalog: Capabilities,
    provider: Graph, consumer: Graph, pool: SceneOffscreenTexturePool,
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> NamedHistoryFrame {
    let command = queue.makeCommandBuffer()!
    let named = SceneNamedTextureReference(providerLayerID: provider.layerID, variant: .primary)
    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
        width: extent.width, height: extent.height, mipmapped: false)
    targetDescriptor.storageMode = .private
    targetDescriptor.usage = [.shaderRead, .renderTarget]
    let reservation = device.makeTexture(descriptor: targetDescriptor)!
    let publication = SceneFrameTextureResource.reservedNamedLayerTarget(reference: named,
        frameEpoch: index, texture: reservation, content: .color(.resolved(.straightAlpha)))!
    let binding = SceneEffectPassSlot(effectID: consumer.effects[0].key.descriptorID,
        passIndex: 0, slotIndex: 1)
    let input = SceneDependencyEffectInput(consumerLayerID: consumer.layerID,
        providerLayerID: provider.layerID, slot: binding, frameEpoch: index,
        texture: reservation, content: .color(.resolved(.straightAlpha)), namedReference: named,
        reservedMaterialResource: publication)
    let graphs = [provider, consumer]
    let claims = graphs.map { claimedExecution(catalog: catalog, admitted: admitted($0)) }
    guard case let .externalPrimary(ownership) = claims[1].dependencyOwnership,
          ownership.providerLayerID == provider.layerID,
          ownership.consumerLayerID == consumer.layerID,
          ownership.slot == binding else { fatalError("named history ownership did not qualify") }
    beginFrame(owner, index: index)
    let requests = zip(graphs, claims).map { renderGraph, claim in
        SceneResolvedMaterialRuntimeBridge.FramePreparationRequest(claim: claim,
            targetPlan: .init(token: claim.token,
                allocation: framePlan(pool: pool, graph: renderGraph, commandBuffer: command)),
            sourceTexture: source, sourceUniforms: .neutral(), sourcePipeline: pipeline,
            frameInputs: .init(dependencyEffects: renderGraph.layerID == consumer.layerID ? [input] : []))
    }
    guard case .ready = owner.prepareFrame(requests, pool: pool, commandBuffer: command)
    else { fatalError("named history preparation did not qualify") }
    var readbacks: [(Readback, Readback, Readback, SceneTextureContent)] = []
    for (renderGraph, claim) in zip(graphs, claims) {
        consumePreparedClaim(claim, coordinator: owner)
        guard case let .encoded(texture, ticket) = owner.executeClaimed(claim: claim,
            dependencyEffects: renderGraph.layerID == consumer.layerID ? [input] : [], commandBuffer: command),
              let stage = owner.activeByID[ticket.identity]?.prepared.stages.first,
              let currentID = renderGraph.renderTargets.first(where: { $0.texture.name == "current" })?.texture,
              let historyID = renderGraph.renderTargets.first(where: { $0.texture.name == "history" })?.texture,
              let currentTexture = stage.frameResources[currentID]?.publication.texture,
              let historyTexture = stage.frameResources[historyID]?.publication.texture
        else { fatalError("named history execution did not qualify") }
        if renderGraph.layerID == provider.layerID {
            let encoder = SceneGraphResourcePassEncoder(commandQueue: queue)
            guard reservation !== texture,
                  let copy = encoder.prepareCopy(source: texture, target: reservation),
                  encoder.encode(copy, commandBuffer: command),
                  case .consumed = owner.markNamedPublication(ticket, texture: texture, published: true)
            else { fatalError("real named reservation copy failed") }
        } else {
            guard case .consumed = owner.markComposite(ticket, texture: texture, consumed: true)
            else { fatalError("named history consumer output failed") }
        }
        guard let currentReadback = appendReadback(currentTexture, commandBuffer: command),
              let historyReadback = appendReadback(historyTexture, commandBuffer: command),
              let outputReadback = appendReadback(texture, commandBuffer: command)
        else { fatalError("named history readback failed") }
        readbacks.append((currentReadback, historyReadback, outputReadback, ticket.finalContent))
    }
    guard owner.sealFrame(on: command) else { fatalError("named history seal failed") }
    _ = owner.endFrame()
    command.commit()
    command.waitUntilCompleted()
    let completed = command.status == .completed && command.error == nil
    owner.completeCommandBuffer(identity: ObjectIdentifier(command),
        observationID: owner.commandBufferRecords[ObjectIdentifier(command)]?.observationID ?? 0,
        status: completed ? .completed : .failed)
    let results = readbacks.map { value in
        CoordinatorFrameResult(currentPixels: value.0.pixels, historyPixels: value.1.pixels,
            outputPixels: value.2.pixels, completed: completed, finalContent: value.3)
    }
    return .init(provider: results[0], consumer: results[1], publication: publication)
}

private func namedHistoryRetirementChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> [String: Bool] {
    let victim = graph()
    let provider = graph(layer: 93)
    let consumer = graph(layer: 94, readsHistoryAsPrimary: true)
    let graphs = [victim, provider, consumer]
    let descriptor = retirementDescriptor(graphs, namedConsumer: consumer.layerID, namedProvider: provider.layerID)
    let catalog = retirementCapabilities(graphs, descriptor: descriptor,
        namedConsumer: consumer.layerID, namedProvider: provider.layerID)
    let owner = SceneResolvedMaterialSubmissionCoordinator(device: device, capabilities: catalog, logSink: { _ in })
    let pool = SceneOffscreenTexturePool(device: device, maxDimension: 64, residentByteBudget: 1_048_576)
    defer { owner.invalidate(reason: .surfaceStop); pool.reset() }
    let surface = SceneDesktopWallpaperSession.Surface(owner, descriptor: descriptor)
    adoptHistoryTopology(surface, revision: 0, destroyed: [], frame: 0)
    let victimFrame = submitCoordinatorFrame(index: 0, coordinator: owner,
        claim: claimedExecution(catalog: catalog, admitted: admitted(victim)), graph: victim,
        executionPlan: admitted(victim).stagePrograms[0].executionPlan,
        pool: pool, source: source, pipeline: pipeline, queue: queue,
        expectedContent: .color(.resolved(.straightAlpha)))
    _ = completeCoordinatorFrame(victimFrame, coordinator: owner)
    let first = submitNamedHistoryFrame(index: 1, owner: owner, catalog: catalog,
        provider: provider, consumer: consumer, pool: pool, device: device,
        queue: queue, source: source, pipeline: pipeline)
    let providerEffect = provider.effects[0].key
    let consumerEffect = consumer.effects[0].key
    let frozenProvider = owner.committedTails[providerEffect]!
    let frozenConsumer = owner.committedTails[consumerEffect]!
    let providerPins = historyPinCount(pool, layer: provider.layerID)
    let consumerPins = historyPinCount(pool, layer: consumer.layerID)
    adoptHistoryTopology(surface, revision: 1, destroyed: [victim.layerID], frame: 2)
    let unrelatedPreserved = owner.committedTails[providerEffect]?.historyPin === frozenProvider.historyPin
        && owner.committedTails[consumerEffect]?.historyPin === frozenConsumer.historyPin
        && historyPinCount(pool, layer: provider.layerID) == providerPins
        && historyPinCount(pool, layer: consumer.layerID) == consumerPins
    let second = submitNamedHistoryFrame(index: 2, owner: owner, catalog: catalog,
        provider: provider, consumer: consumer, pool: pool, device: device,
        queue: queue, source: source, pipeline: pipeline)
    let consumerBeforeProviderDeath = owner.committedTails[consumerEffect]!
    let consumerPinsBeforeProviderDeath = historyPinCount(pool, layer: consumer.layerID)
    adoptHistoryTopology(surface, revision: 2, destroyed: [victim.layerID, provider.layerID], frame: 3)
    return [
        "typedHiddenProviderAndOwnHistoryConsumerQualified": descriptor.layers.first { $0.id == provider.layerID }?.visible == false
            && first.provider.completed && first.consumer.completed && providerPins > 0 && consumerPins > 0,
        "namedCopyAndConsumerProduceActualPixels": approximately(first.provider.outputPixels, expected(scale: 0.25))
            && approximately(first.consumer.outputPixels, expected(scale: 0.1875)),
        "unrelatedDestroyKeepsHiddenProviderAndConsumerHistory": unrelatedPreserved,
        "liveNamedHistoryContinuesAcrossRetirement": second.provider.completed && second.consumer.completed
            && approximately(second.provider.outputPixels, expected(scale: 0.4375))
            && approximately(second.consumer.outputPixels, expected(scale: 0.375)),
        "onlyDestroyedHistoryOwnersRetire": historyLayerIDs(owner.committedTails) == [consumer.layerID]
            && historyPinCount(pool, layer: victim.layerID) == 0 && historyPinCount(pool, layer: provider.layerID) == 0,
        "providerDeathPreservesConsumerOwnedHistory": owner.committedTails[consumerEffect]?.historyPin
                === consumerBeforeProviderDeath.historyPin
            && historyPinCount(pool, layer: consumer.layerID) == consumerPinsBeforeProviderDeath,
        "oldNamedPublicationKeepsItsIndependentTexture": first.publication.publication.texture
                !== second.publication.publication.texture
            && first.publication.publication.contentGeneration > 0,
    ]
}

func graphHistoryRetirementChecks(
    device: MTLDevice, queue: MTLCommandQueue, source: MTLTexture, pipeline: SceneImageLayerPipeline
) -> [String: [String: Bool]] {
    [
        "completed": completedRetirementChecks(device: device, queue: queue, source: source, pipeline: pipeline),
        "inFlightSuccess": inFlightRetirementChecks(device: device, queue: queue,
            source: source, pipeline: pipeline, terminal: .completed),
        "inFlightFailureInjection": inFlightRetirementChecks(device: device, queue: queue,
            source: source, pipeline: pipeline, terminal: .failed),
        "reverseCompletion": reverseCompletionRetirementChecks(device: device, queue: queue, source: source, pipeline: pipeline),
        "retireThenStop": retirementThenStopChecks(device: device, queue: queue, source: source, pipeline: pipeline),
        "typedNamedHistory": namedHistoryRetirementChecks(device: device, queue: queue, source: source, pipeline: pipeline),
    ]
}
