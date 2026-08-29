import CoreGraphics
import Foundation
import Metal

/// Prepares one complete R4 layer transaction before appending any Metal
/// command. The layer full-frame pair is captured once and shared by every
/// admitted effect; persistent state remains limited to authored FBOs.
final class SceneResolvedMaterialGraphExecutor {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    typealias Pair = SceneLayerFullFramePairPlan

    enum Failure: Error, Equatable {
        case invalidClaim
        case invalidFrame
        case invalidLease
        case stateRejected
        case historyRejected
        case graphPublicationRejected
        case graphStructureRejected
        case materialFinalizerRejected(
            stageIndex: Int,
            effect: Graph.EffectKey,
            nodeIndex: Int,
            materialOrdinal: Int,
            failure: SceneResolvedMaterialFailure
        )
        case materialPassEncoderRejected
        case materialPassPreparationRejected(
            stageIndex: Int,
            nodeIndex: Int,
            materialOrdinal: Int,
            programKey: String,
            failure: SceneResolvedMaterialPassEncoder.PreparationFailure
        )
        case resourceCommandRejected
        case functionInvocationStaleFrame
        case functionInvocationUnknownEffect
        case functionInvocationUnknownFunction
        case functionInvocationTargetUnavailable
        case functionClearEncodeRejected
        case captureRejected
        case encodeRejected
        case contentGenerationOverflow
        case stalePreparation
    }

    struct PreparedStage {
        let effect: Graph.EffectKey
        let graph: Graph
        let pairStep: Pair.EffectStep
        let transition: State.Transition
        let programCacheKeys: [String]
        let effectLocalFailureReasonCode: String?
        let effectLocalActivationBypassReasonCode: String?
        /// The effect-local fallback discarded a planned persistent target
        /// candidate instead of publishing it as readable history.
        let discardedPersistentTargetState: Bool
        let inputWidth, inputHeight: Int
        let historyRehydrateCopyCount: Int
        let historyContentDiscarded: Bool
        /// Complete readable FBO publications for this frame's candidate.
        let frameResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        /// History-only publications allowed to survive in a committed tail.
        let persistentResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let effectOutputResource: SceneFrameTextureResource

        fileprivate let commands: [Command]
    }

    struct PreparedGraph {
        let stages: [PreparedStage]
        let finalTexture: MTLTexture
        let finalResource: SceneFrameTextureResource
        let historyTokensByEffect: [Graph.EffectKey: Set<State.PhysicalToken>]
        let sceneBackgroundResource: SceneFrameTextureResource?

        fileprivate let ownerToken: UUID
        fileprivate let resetGeneration: UInt64
        fileprivate let queueIdentity: ObjectIdentifier
        fileprivate let sourceCommand: Command
    }

    struct PairAtom {
        let member: Pair.Member
        let resource: SceneFrameTextureResource
        let representation: SceneShaderColorRepresentation
    }

    struct HistoryContext {
        let rehydration: [State.PhysicalToken: State.PhysicalToken]
        let commands: [SceneGraphResourcePassEncoder.PreparedCommand]
        /// A descriptor-changing reprepare preserves the logical swap
        /// permutation but intentionally starts the new storage transparent.
        let discardsPreviousContent: Bool
    }

    enum Command {
        case resource(SceneGraphResourcePassEncoder.PreparedCommand)
        case functionClear(
            SceneGraphResourcePassEncoder.PreparedCommand,
            invocationOrdinal: Int,
            targetOrdinal: Int
        )
        case material(SceneResolvedMaterialPassEncoder.PreparedPass)
    }

    typealias StageBoundaryObserver = (
        Int, PreparedStage, MTLCommandBuffer
    ) -> Bool

    typealias FunctionClearEncodeObserver = (
        Int, Int, Int, MTLCommandBuffer
    ) -> Bool

    let device: MTLDevice
    let capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    let materialEncoder: SceneResolvedMaterialPassEncoder
    let pipelineWarmupReport: SceneResolvedMaterialPassEncoder.WarmupReport
    private let ownerToken = UUID()
    var resourceEncoder: SceneGraphResourcePassEncoder?
    private var queueIdentity: ObjectIdentifier?
    private var resetGeneration: UInt64 = 0
    private var pairContentGeneration: UInt64 = 0
    let effectLocalFallbackLock = NSLock()
    var effectLocalFallbackCounts: [String: Int] = [:]
    let typedUniformPublicationLock = NSLock()
    var typedUniformPublicationIdentities: Set<String> = []

    init?(
        device: MTLDevice,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    ) {
        guard let materialEncoder = SceneResolvedMaterialPassEncoder(device: device) else {
            return nil
        }
        self.device = device
        self.capabilities = capabilities
        self.materialEncoder = materialEncoder
        pipelineWarmupReport = materialEncoder.warmup(
            capabilities.launchPipelineWarmupPlans(device: device)
        )
        pipelineWarmupReport.reportLines.forEach { NSLog("%@", $0) }
    }

    func prepare(
        token: SceneResolvedMaterialExecutionCapabilityCatalog.Token,
        leases: [SceneGraphRenderTargetLease],
        historyRehydrateCopiesByEffect: [
            Graph.EffectKey: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]
        ],
        frame: SceneResolvedMaterialFrameSnapshot,
        sceneBackgroundResource: SceneFrameTextureResource? = nil,
        sourceTexture: MTLTexture?,
        sourceUniforms: SceneLayerFragmentUniforms?,
        sourcePipeline: SceneImageLayerPipeline,
        frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs,
        commandBuffer: MTLCommandBuffer,
        previousStates: [Graph.EffectKey: State],
        previousGraphResources: [
            Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]
        ],
        materialFunctionInvocations:
            [SceneGraphMaterialFunctionInvocationRequest] = [],
        effectGeneration: UInt64,
        resetGeneration: UInt64
    ) -> Result<PreparedGraph, Failure> {
        guard let capability = capabilities.resolve(token),
              commandBuffer.status == .notEnqueued,
              commandBuffer.commandQueue.device.registryID == device.registryID,
              ensureResourceEncoder(commandBuffer.commandQueue),
              let firstLease = leases.first else {
            return .failure(.invalidClaim)
        }
        let resolvedInvocations: [
            Graph.EffectKey: [SceneGraphClearFunctionRegistry.ClearFunction]
        ]
        switch resolveMaterialFunctionInvocations(
            materialFunctionInvocations,
            capability: capability,
            leases: leases,
            frameEpoch: frame.textureRegistrySnapshot.frameEpoch
        ) {
        case let .success(value): resolvedInvocations = value
        case let .failure(failure): return .failure(failure)
        }
        guard validate(
            capability: capability,
            leases: leases,
            materialFunctionTargetsByEffect: resolvedInvocations.mapValues {
                Set($0.flatMap(\.targets))
            }
        ) else {
            return .failure(.invalidClaim)
        }
        let executionFrame: SceneResolvedMaterialFrameSnapshot
        switch (capability.sceneBackgroundRequirement, sceneBackgroundResource) {
        case (nil, nil):
            executionFrame = frame
        case let (requirement?, resource?):
            guard requirement.layerID == capability.layerID,
                  requirement.effect.layerID == capability.layerID,
                  let replacement = frame.overlayingSceneBackground(
                      consumerLayerID: requirement.layerID,
                      resource: resource
                  ) else { return .failure(.invalidFrame) }
            executionFrame = replacement
        case (nil, _?), (_?, nil):
            return .failure(.invalidFrame)
        }
        let baseTarget = pairTexture(
            lease: firstLease,
            member: capability.pairPlan.baseCaptureMember
        )
        let baseCommand: SceneGraphResourcePassEncoder.PreparedCommand
        switch capability.sourceRoute {
        case .capturedLayerTexture, .capturedMainTargetTexture:
            guard let sourceTexture, let sourceUniforms,
                  let capture = resourceEncoder?.prepareSourceCapture(
                      source: sourceTexture,
                      target: baseTarget,
                      uniforms: sourceUniforms,
                      pipeline: sourcePipeline
                  ) else { return .failure(.captureRejected) }
            baseCommand = capture
        case .transparentDirectDraw:
            guard sourceTexture == nil, sourceUniforms == nil,
                  let initialization = resourceEncoder?.prepareInitialization(
                      target: baseTarget,
                      clear: .init(red: 0, green: 0, blue: 0, alpha: 0)
                  ) else { return .failure(.captureRejected) }
            baseCommand = initialization
        }
        guard let captureGeneration = nextPairGeneration(),
              let base = pairResource(
                  lease: firstLease,
                  identity: capability.pairPlan.baseCaptureIdentity,
                  member: capability.pairPlan.baseCaptureMember,
                  generation: captureGeneration,
                  representation: .premultipliedAlpha
              ) else { return .failure(.contentGenerationOverflow) }

        let sourceCommand = Command.resource(baseCommand)
        var pair = PairAtom(
            member: capability.pairPlan.baseCaptureMember,
            resource: base,
            representation: .premultipliedAlpha
        )
        var publications = [
            capability.pairPlan.baseCaptureIdentity: base,
        ]
        var stages: [PreparedStage] = []

        for index in capability.stages.indices {
            var stageCommands: [Command] = []
            let stageCapability = capability.stages[index]
            let product = stageCapability.product
            let graph = product.graph
            let pairStep = capability.pairPlan.effects[index]
            let lease = leases[index]
            guard let effect = graph.effects.first?.key,
                  effect == pairStep.effect,
                  pair.member == pairStep.inputMember,
                  let input = pairResource(
                      lease: lease,
                      identity: pairStep.inputIdentity,
                      member: pair.member,
                      generation: pair.resource.resourceGeneration,
                      representation: pair.representation
                  ) else { return .failure(.invalidLease) }
            publications[pairStep.inputIdentity] = input
            pair = .init(
                member: pair.member,
                resource: input,
                representation: pair.representation
            )

            let previous = previousStates[effect] ?? .empty
            let previousResources = previousGraphResources[effect] ?? [:]
            guard let history = prepareHistoryContext(
                historyRehydrateCopiesByEffect[effect] ?? [],
                previous: previous,
                previousResources: previousResources,
                lease: lease,
                effectGeneration: effectGeneration,
                resetGeneration: resetGeneration
            ) else { return .failure(.historyRejected) }
            let reduction = State.reduce(
                graph: graph,
                targetPlan: lease.table.plan,
                pairStep: pairStep,
                allocation: lease.framebufferAllocation,
                effectGeneration: effectGeneration,
                resetGeneration: resetGeneration,
                previous: previous,
                historyRehydration: history.rehydration,
                materialFunctionInvocations: (resolvedInvocations[effect] ?? []).map {
                    .init(name: $0.name, targets: $0.targets)
                }
            )
            guard case let .success(transition) = reduction,
                  publishRehydratedHistory(
                      transition: transition,
                      previous: previous,
                      previousResources: previousResources,
                      history: history,
                      lease: lease,
                      publications: &publications
                  ) else { return .failure(.stateRejected) }
            stageCommands.append(contentsOf: history.commands.map(Command.resource))

            var programKeys: [String] = []
            var effectLocalFailureReasonCode: String?
            var effectLocalActivationBypassReasonCode: String?
            if let failure = prepare(
                stageIndex: index,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                stageCapability: stageCapability,
                capability: capability,
                lease: lease,
                frame: executionFrame,
                frameInputs: frameInputs,
                pair: &pair,
                publications: &publications,
                commands: &stageCommands,
                programKeys: &programKeys,
                effectLocalFailureReasonCode: &effectLocalFailureReasonCode,
                effectLocalActivationBypassReasonCode:
                    &effectLocalActivationBypassReasonCode
            ) {
                return .failure(failure)
            }
            let committedTransition: State.Transition
            var discardedPersistentTargetState = false
            if effectLocalFailureReasonCode != nil
                || effectLocalActivationBypassReasonCode != nil,
               !graph.renderTargets.isEmpty {
                guard let discarded = State.discardingUncommittedVisualFailure(
                    transition,
                    previous: previous
                ) else { return .failure(.stateRejected) }
                discardedPersistentTargetState =
                    !transition.nextState.historyClosureIdentities.isEmpty
                        && discarded.nextState.historyClosureIdentities.isEmpty
                committedTransition = discarded
            } else {
                committedTransition = transition
            }
            guard !stageCommands.isEmpty
                    || effectLocalFailureReasonCode != nil
                    || effectLocalActivationBypassReasonCode != nil,
                  pair.member == pairStep.outputMember,
                  let final = publications[pairStep.outputIdentity],
                  final.publication.texture === pair.resource.publication.texture,
                  final.resourceGeneration == pair.resource.resourceGeneration,
                  final.publication.isSameAtom(as: pair.resource.publication),
                  let frameResources = resources(
                      matching: committedTransition.transaction.mappingAfter,
                      from: publications
                  ), let persistentResources = resources(
                      matching: committedTransition.nextState.logicalMapping,
                      from: publications
                  ) else { return .failure(.graphPublicationRejected) }
            stages.append(.init(
                effect: effect,
                graph: graph,
                pairStep: pairStep,
                transition: committedTransition,
                programCacheKeys: programKeys,
                effectLocalFailureReasonCode: effectLocalFailureReasonCode,
                effectLocalActivationBypassReasonCode:
                    effectLocalActivationBypassReasonCode,
                discardedPersistentTargetState: discardedPersistentTargetState,
                inputWidth: lease.table.plan.inputExtent.width,
                inputHeight: lease.table.plan.inputExtent.height,
                historyRehydrateCopyCount: history.commands.count,
                historyContentDiscarded: history.discardsPreviousContent,
                frameResources: frameResources,
                persistentResources: persistentResources,
                effectOutputResource: final,
                commands: stageCommands
            ))
        }

        guard pair.member == capability.pairPlan.terminalMember,
              pair.member == Pair.fixedTerminalMember,
              pair.representation == .opaque
                || pair.representation == .premultipliedAlpha,
              let terminal = stages.last?.effectOutputResource,
              terminal.publication.requestIdentity
                == .graph(capability.pairPlan.terminalOutputIdentity),
              terminal.publication.texture === pair.resource.publication.texture,
              let queueIdentity,
              let historyTokens = historyTokens(stages) else {
            return .failure(.graphPublicationRejected)
        }
        return .success(.init(
            stages: stages,
            finalTexture: terminal.publication.texture,
            finalResource: terminal,
            historyTokensByEffect: historyTokens,
            sceneBackgroundResource: sceneBackgroundResource,
            ownerToken: ownerToken,
            resetGeneration: self.resetGeneration,
            queueIdentity: queueIdentity,
            sourceCommand: sourceCommand
        ))
    }

    /// `true` means every preflighted command was appended. Commit still waits
    /// for final compositor conservation and GPU completion.
    func encode(_ preparedGraph: PreparedGraph, commandBuffer: MTLCommandBuffer) -> Bool {
        if case .success = encodeResult(
            preparedGraph,
            commandBuffer: commandBuffer
        ) { return true }
        return false
    }

    func encodeResult(
        _ preparedGraph: PreparedGraph,
        commandBuffer: MTLCommandBuffer
    ) -> Result<Void, Failure> {
        encodePreparedStages(
            preparedGraph,
            commandBuffer: commandBuffer,
            stageObserver: nil,
            functionClearObserver: nil
        )
    }

    #if SCENE_GRAPH_TESTING
    func encode(
        _ preparedGraph: PreparedGraph,
        commandBuffer: MTLCommandBuffer,
        stageBoundaryObserver: @escaping StageBoundaryObserver
    ) -> Bool {
        if case .success = encodePreparedStages(
            preparedGraph,
            commandBuffer: commandBuffer,
            stageObserver: stageBoundaryObserver,
            functionClearObserver: nil
        ) { return true }
        return false
    }

    func encodeResult(
        _ preparedGraph: PreparedGraph,
        commandBuffer: MTLCommandBuffer,
        functionClearObserver: @escaping FunctionClearEncodeObserver
    ) -> Result<Void, Failure> {
        encodePreparedStages(
            preparedGraph,
            commandBuffer: commandBuffer,
            stageObserver: nil,
            functionClearObserver: functionClearObserver
        )
    }
    #endif

    private func encodePreparedStages(
        _ preparedGraph: PreparedGraph,
        commandBuffer: MTLCommandBuffer,
        stageObserver: StageBoundaryObserver?,
        functionClearObserver: FunctionClearEncodeObserver?
    ) -> Result<Void, Failure> {
        guard preparedGraph.ownerToken == ownerToken,
              preparedGraph.resetGeneration == resetGeneration,
              preparedGraph.queueIdentity == ObjectIdentifier(commandBuffer.commandQueue),
              commandBuffer.status == .notEnqueued else {
            return .failure(.stalePreparation)
        }
        guard encode(preparedGraph.sourceCommand, commandBuffer: commandBuffer) else {
            return .failure(.encodeRejected)
        }
        for (stageIndex, stage) in preparedGraph.stages.enumerated() {
            for command in stage.commands {
                if case let .functionClear(
                    _, invocationOrdinal, targetOrdinal
                ) = command, functionClearObserver?(
                    stageIndex,
                    invocationOrdinal,
                    targetOrdinal,
                    commandBuffer
                ) == false {
                    return .failure(.functionClearEncodeRejected)
                }
                guard encode(command, commandBuffer: commandBuffer) else {
                    if case .functionClear = command {
                        return .failure(.functionClearEncodeRejected)
                    }
                    return .failure(.encodeRejected)
                }
            }
            guard stageObserver?(
                stageIndex, stage, commandBuffer
            ) != false else { return .failure(.encodeRejected) }
        }
        return .success(())
    }

    private func encode(
        _ command: Command,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        switch command {
        case let .resource(value):
            resourceEncoder?.encode(value, commandBuffer: commandBuffer) == true
        case let .functionClear(value, _, _):
            resourceEncoder?.encode(value, commandBuffer: commandBuffer) == true
        case let .material(value):
            materialEncoder.encode(value, commandBuffer: commandBuffer)
        }
    }

    @discardableResult
    func reset() -> Bool {
        guard resetGeneration < UInt64.max else { return false }
        resetGeneration += 1
        materialEncoder.reset()
        resourceEncoder?.reset()
        return true
    }

    private func ensureResourceEncoder(_ queue: MTLCommandQueue) -> Bool {
        let identity = ObjectIdentifier(queue)
        if let queueIdentity { return queueIdentity == identity }
        queueIdentity = identity
        resourceEncoder = .init(commandQueue: queue)
        return true
    }

    func nextPairGeneration() -> UInt64? {
        guard pairContentGeneration < UInt64.max else { return nil }
        pairContentGeneration += 1
        return pairContentGeneration
    }
}
